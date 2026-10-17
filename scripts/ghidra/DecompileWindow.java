// Partial-window decompiler probe. Does not identify SDK functions by name.
// @category MVC2
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import java.io.PrintWriter;

public class DecompileWindow extends GhidraScript {
    @Override public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 3) throw new IllegalArgumentException("entry hex, pseudocode output, metadata output required");
        Address at = toAddr(Long.parseUnsignedLong(args[0].replace("0x", ""), 16));
        Function f = getFunctionAt(at);
        if (f == null) f = createFunction(at, "candidate_module_wrapper");
        if (f == null) throw new IllegalStateException("Function could not be created");
        DecompInterface decompiler = new DecompInterface();
        try {
            if (!decompiler.openProgram(currentProgram)) throw new IllegalStateException("Decompiler failed to open program");
            DecompileResults result = decompiler.decompileFunction(f, 60, monitor);
            if (!result.decompileCompleted()) throw new IllegalStateException(result.getErrorMessage());
            try (PrintWriter out = new PrintWriter(args[1])) {
                out.println("/* PARTIAL WINDOW ONLY: inferred pseudocode, no ABI/SDK identity proof */");
                out.println(result.getDecompiledFunction().getC());
            }
            try (PrintWriter meta = new PrintWriter(args[2])) {
                meta.printf("{\"entry\":\"0x%s\",\"body_min\":\"0x%s\",\"body_max\":\"0x%s\",\"body_bytes\":%d}%n",
                    at, f.getBody().getMinAddress(), f.getBody().getMaxAddress(), f.getBody().getNumAddresses());
            }
            println("Partial window decompilation exported");
        } finally { decompiler.dispose(); }
    }
}
