// Patches DynamicUIPositioner in Assembly-CSharp.dll so the side panels fit screens narrower
// than 16:9.
//
// The game moves its left and right side panels (the button help in fights, among others)
// towards the middle only when the screen is exactly 1280 wide (the Steam Deck's 1280x800), by a
// fixed 0.5 units (0.25 for the small shift). Every camera is orthographic with size 4.21875, so
// the view is 8.4375 units high and each side edge sits 4.21875 * aspect units from the middle:
// 7.5 at 16:9, 6.75 at 16:10, 5.625 at 4:3. On 4:3 the right panel is cut off.
//
// After the patch the width test is gone and the shift is computed from the screen's aspect, as
// PortSharp.Aspect() (setup/PortSharp.cs) reports it (4:3 at least in its fit mode):
// PortShift(base) = max(0, 4.21875 * (16/9 - aspect) - 0.25) * base / 0.5,
// which gives the original 0.5 / 0.25 at 1280x800, nothing at 16:9 and wider, and 1.625 / 0.8125
// at 4:3. The shop button rule (mode 3) is unchanged.
//
// Build: mcs -r:Mono.Cecil.dll -out:ui_aspect_patch.exe ui_aspect_patch.cs
// Usage: mono ui_aspect_patch.exe <Managed dir> <output Assembly-CSharp.dll> <PortSharp.dll>
using System;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class UiAspectPatch
{
    static int Main(string[] args)
    {
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(args[0]);
        var asm = AssemblyDefinition.ReadAssembly(System.IO.Path.Combine(args[0], "Assembly-CSharp.dll"),
            new ReaderParameters { AssemblyResolver = resolver });
        var mod = asm.MainModule;
        var pos = mod.GetType("DynamicUIPositioner");
        if (pos == null || pos.Methods.Any(m => m.Name == "PortShift")) {
            Console.Error.WriteLine("DynamicUIPositioner missing or already patched");
            return 1;
        }
        var target = pos.Methods.Single(m => m.Name == "ProgressionPositioningMode");

        // static float PortShift(float baseShift)
        var core = mod.AssemblyReferences.Single(r => r.Name == "UnityEngine.CoreModule");
        var mathf = new TypeReference("UnityEngine", "Mathf", mod, core) { IsValueType = true };
        var aspect = mod.ImportReference(ModuleDefinition.ReadModule(args[2]).GetType("PortSharp").Methods
            .Single(m => m.Name == "Aspect"));
        var max = new MethodReference("Max", mod.TypeSystem.Single, mathf);
        max.Parameters.Add(new ParameterDefinition(mod.TypeSystem.Single));
        max.Parameters.Add(new ParameterDefinition(mod.TypeSystem.Single));
        var shift = new MethodDefinition("PortShift",
            MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig, mod.TypeSystem.Single);
        shift.Parameters.Add(new ParameterDefinition("baseShift", ParameterAttributes.None, mod.TypeSystem.Single));
        var il = shift.Body.GetILProcessor();
        il.Emit(OpCodes.Ldc_R4, 4.21875f);
        il.Emit(OpCodes.Ldc_R4, 16f / 9f);
        il.Emit(OpCodes.Call, aspect);
        il.Emit(OpCodes.Sub);
        il.Emit(OpCodes.Mul);
        il.Emit(OpCodes.Ldc_R4, 0.25f);
        il.Emit(OpCodes.Sub);
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Mul);
        il.Emit(OpCodes.Ldc_R4, 2f);
        il.Emit(OpCodes.Mul);
        il.Emit(OpCodes.Ldc_R4, 0f);
        il.Emit(OpCodes.Call, max);
        il.Emit(OpCodes.Ret);
        pos.Methods.Add(shift);

        // In ProgressionPositioningMode: the width test always passes (get_width() is replaced by
        // pop + 1280), and each fixed shift constant goes through PortShift.
        var body = target.Body.GetILProcessor();
        int widths = 0, consts = 0;
        foreach (var ins in target.Body.Instructions.ToList()) {
            if (ins.OpCode == OpCodes.Call && ins.Operand is MethodReference m &&
                m.Name == "get_width" && m.DeclaringType.Name == "Resolution") {
                var pop = body.Create(OpCodes.Pop);
                body.InsertBefore(ins, pop);
                ins.OpCode = OpCodes.Ldc_I4;
                ins.Operand = 1280;
                widths++;
            } else if (ins.OpCode == OpCodes.Ldc_R4 && ins.Next.OpCode == OpCodes.Call &&
                       ins.Next.Operand is MethodReference v && v.DeclaringType.Name == "Vector3" &&
                       (v.Name == "get_right" || v.Name == "get_left") && consts < 3) {
                body.InsertAfter(ins, body.Create(OpCodes.Call, shift));
                consts++;
            }
        }
        if (widths != 3 || consts != 3) {
            Console.Error.WriteLine($"unexpected method body: {widths} width tests, {consts} shifts");
            return 1;
        }
        asm.Write(args[1]);
        return 0;
    }
}
