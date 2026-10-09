// Adds a call to PortSharp.Init() (setup/PortSharp.cs) at the start of
// GameInitialization.PCInitialization in Assembly-CSharp.dll, so the sharp upscaling starts with
// the game. PortSharp.dll has to sit next to Assembly-CSharp.dll in Managed/ (the launcher puts it
// there).
//
// Build: mcs -r:Mono.Cecil.dll -out:sharp_inject.exe sharp_inject.cs
// Usage: mono sharp_inject.exe <Assembly-CSharp.dll in> <PortSharp.dll> <Assembly-CSharp.dll out>
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class SharpInject
{
    static int Main(string[] args)
    {
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0])));
        var asm = AssemblyDefinition.ReadAssembly(args[0], new ReaderParameters { AssemblyResolver = resolver });
        var mod = asm.MainModule;
        var helper = ModuleDefinition.ReadModule(args[1]);
        var init = mod.ImportReference(helper.GetType("PortSharp").Methods.Single(m => m.Name == "Init"));
        var start = mod.GetType("GameInitialization")?.Methods.SingleOrDefault(m => m.Name == "PCInitialization");
        if (start == null || start.Body.Instructions.Any(i =>
                i.Operand is MethodReference r && r.DeclaringType.Name == "PortSharp")) {
            Console.Error.WriteLine("GameInitialization.PCInitialization missing or already patched");
            return 1;
        }
        start.Body.GetILProcessor().InsertBefore(start.Body.Instructions[0], Instruction.Create(OpCodes.Call, init));
        asm.Write(args[2]);
        return 0;
    }
}
