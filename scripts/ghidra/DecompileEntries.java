// Partial entries only. Deliberately assigns no SDK names.
// @category MVC2
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import java.io.PrintWriter;
import java.nio.file.*;
import java.util.*;

public class DecompileEntries extends GhidraScript {
    @Override public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2) throw new IllegalArgumentException("entries TSV, output directory required");
        Path dir = Paths.get(args[1]);
        Files.createDirectories(dir);
        List<String> facts = new ArrayList<>();
        DecompInterface dec = new DecompInterface();
        try {
            if (!dec.openProgram(currentProgram)) throw new IllegalStateException("Decompiler startup failed");
            for (String line : Files.readAllLines(Paths.get(args[0]))) {
                if (line.isBlank()) continue;
                Address at = toAddr(Long.parseUnsignedLong(line.trim(), 16));
                Function f = getFunctionAt(at);
                if (f == null) f = createFunction(at, "candidate_" + at.toString());
                if (f == null) throw new IllegalStateException("Missing function at " + at);
                DecompileResults result = dec.decompileFunction(f, 60, monitor);
                if (!result.decompileCompleted()) throw new IllegalStateException(result.getErrorMessage());
                try (PrintWriter out = new PrintWriter(dir.resolve(at.toString()+".c").toFile())) {
                    out.println("/* PARTIAL US WINDOW ONLY: inferred types; not full ELF/runtime proof */");
                    out.println(result.getDecompiledFunction().getC());
                }
                List<String> calls = new ArrayList<>();
                InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    Instruction i = it.next();
                    if (!i.getFlowType().isCall()) continue;
                    for (Address target : i.getFlows())
                        calls.add(String.format("{\"site\":\"0x%s\",\"target\":\"0x%s\"}", i.getAddress(), target));
                }
                facts.add(String.format("{\"entry\":\"0x%s\",\"body_min\":\"0x%s\",\"body_max\":\"0x%s\",\"body_bytes\":%d,\"direct_calls\":[%s]}",
                    at, f.getBody().getMinAddress(), f.getBody().getMaxAddress(), f.getBody().getNumAddresses(), String.join(",",calls)));
            }
            Files.writeString(dir.resolve("functions.json"), "["+String.join(",\n",facts)+"]\n");
        } finally { dec.dispose(); }
        println("Partial entries decompiled successfully: " + facts.size());
    }
}
