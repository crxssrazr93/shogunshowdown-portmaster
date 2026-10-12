// Injects PortCapture (PortCapture.cs) into a game's Managed folder. Test builds only.
//  * Assembly-CSharp.dll: a call to PortCapture.Init() at the start of GameInitialization.Start
//    (the first script to run in the first scene).
//  * Assembly-CSharp.dll, Assembly-CSharp-firstpass.dll (LeanTween), UnityEngine.UI.dll,
//    Unity.TextMeshPro.dll: every call of
//    Time.unscaledDeltaTime, Time.unscaledTime and Time.realtimeSinceStartup becomes a call of
//    PortCapture's frame based version, and SceneManager.LoadSceneAsync(string, LoadSceneMode) a call
//    of PortCapture.LoadSceneAsync (freezes the game clock while the scene loads), and every
//    new WaitForSecondsRealtime(float) a new PortWaitRealtime(float) (waits on the frame based clock).
// The unpatched assemblies are kept as <name>.dll.nocap and always used as the input, so the tool
// can be run again after PortCapture.cs changed. PortCapture.dll has to sit in Managed/ too.
//
// Build: mcs -r:Mono.Cecil.dll -out:capture_inject.exe capture_inject.cs
// Usage: mono capture_inject.exe <Managed dir> <PortCapture.dll>
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class CaptureInject
{
    static int Main(string[] args)
    {
        string dir = args[0];
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(dir);
        var helper = ModuleDefinition.ReadModule(args[1]);
        var cls = helper.GetType("PortCapture");
        Func<string, MethodDefinition> M = n => cls.Methods.Single(m => m.Name == n);
        foreach (var name in new[] { "Assembly-CSharp", "Assembly-CSharp-firstpass", "UnityEngine.UI", "Unity.TextMeshPro" }) {
            string src = Path.Combine(dir, name + ".dll"), orig = src + ".nocap";
            if (!File.Exists(orig)) File.Copy(src, orig);
            var asm = AssemblyDefinition.ReadAssembly(orig, new ReaderParameters { AssemblyResolver = resolver });
            var mod = asm.MainModule;
            int n = 0;
            foreach (var type in mod.GetTypes())
                foreach (var method in type.Methods.Where(m => m.HasBody))
                    foreach (var ins in method.Body.Instructions) {
                        var r = ins.Operand as MethodReference;
                        if (r == null) continue;
                        string t = r.DeclaringType.FullName, target = null;
                        if (t == "UnityEngine.Time") {
                            if (r.Name == "get_unscaledDeltaTime") target = "UnscaledDeltaTime";
                            else if (r.Name == "get_unscaledTime") target = "UnscaledTime";
                            else if (r.Name == "get_realtimeSinceStartup") target = "RealtimeSinceStartup";
                        } else if (t == "UnityEngine.SceneManagement.SceneManager" && r.Name == "LoadSceneAsync"
                                   && r.Parameters.Count == 2 && r.Parameters[0].ParameterType.FullName == "System.String")
                            target = "LoadSceneAsync";
                        if (t == "UnityEngine.WaitForSecondsRealtime" && r.Name == ".ctor" && ins.OpCode == OpCodes.Newobj) {
                            ins.Operand = mod.ImportReference(helper.GetType("PortWaitRealtime").Methods.Single(m => m.IsConstructor && !m.IsStatic));
                            n++; continue;
                        }
                        if (target == null) continue;
                        ins.Operand = mod.ImportReference(M(target));
                        n++;
                    }
            if (name == "Assembly-CSharp") {
                var start = mod.GetType("GameInitialization")?.Methods.SingleOrDefault(m => m.Name == "Start");
                if (start == null) { Console.Error.WriteLine("GameInitialization.Start missing"); return 1; }
                start.Body.GetILProcessor().InsertBefore(start.Body.Instructions[0],
                    Instruction.Create(OpCodes.Call, mod.ImportReference(M("Init"))));
            }
            asm.Write(src);
            Console.WriteLine(name + ": " + n + " calls redirected");
        }
        return 0;
    }
}
