// Decode small, independently verified local byte windows. NOT a function map.
// @category MVC2
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.MemoryBlock;
import java.io.*;
import java.nio.file.*;

public class DisassembleWindows extends GhidraScript {
    @Override public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2) throw new IllegalArgumentException("windows directory, output TSV required");
        Path dir = Paths.get(args[0]);
        try (PrintWriter out = new PrintWriter(args[1])) {
            out.println("window\tva\tmnemonic\tinstruction\tflow_type\tflows");
            for (String line : Files.readAllLines(dir.resolve("windows.tsv"))) {
                if (line.isBlank()) continue;
                String[] fields = line.split("\t");
                String name = fields[0];
                long base = Long.parseUnsignedLong(fields[1], 16);
                int count = Integer.parseInt(fields[2]);
                byte[] bytes = Files.readAllBytes(dir.resolve(name + ".bin"));
                if (bytes.length != count) throw new IOException("Wrong size: " + name);
                byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
                StringBuilder hash = new StringBuilder();
                for (byte b : digest) hash.append(String.format("%02x", b & 255));
                if (!hash.toString().equals(fields[3])) throw new IOException("Hash mismatch: " + name);
                Address start = toAddr(base);
                MemoryBlock block = currentProgram.getMemory().getBlock(start);
                if (block == null) {
                    block = currentProgram.getMemory().createInitializedBlock(
                        name, start, new ByteArrayInputStream(bytes), count, monitor, false);
                }
                byte[] mapped = new byte[count];
                if (currentProgram.getMemory().getBytes(start, mapped) != count ||
                    !java.util.Arrays.equals(mapped, bytes))
                    throw new IOException("Mapped bytes differ: " + name);
                block.setExecute(true);
                block.setRead(true);
                for (int offset = 0; offset < count; offset += 4) {
                    Address at = start.add(offset);
                    disassemble(at);
                    Instruction i = currentProgram.getListing().getInstructionAt(at);
                    if (i == null) continue;
                    StringBuilder flows = new StringBuilder();
                    for (Address dest : i.getFlows()) {
                        if (flows.length() > 0) flows.append(",");
                        flows.append(dest.toString());
                    }
                    out.printf("%s\t%s\t%s\t%s\t%s\t%s%n", name, at,
                        i.getMnemonicString(), i.toString(), i.getFlowType(), flows);
                }
            }
        }
        println("Window disassembly exported (partial bytes, not complete-game analysis)");
    }
}
