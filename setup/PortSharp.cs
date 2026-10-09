// Picture fixes for Shogun Showdown, started from the game code (setup/sharp_inject.cs).
//
// Sharp upscaling: the game renders its scene into the 480x270 RenderTexture "LowResRenderTexture"
// (point filtered) and shows it on a RawImage scaled to the screen height: 1.78x at 640x480,
// 2.67x at 720x720 and 1280x720, so art pixels come out 1 or 2 (2 or 3) screen pixels wide. Here
// the RawImage shows a copy k times larger instead (k = picture height / 270, rounded up, at least
// 2), made each frame with nearest neighbour sampling, and drawn with bilinear filtering: every
// art pixel becomes a k x k block, and only the edges between blocks are blended when it is scaled
// to the screen ("sharp bilinear"). What the game draws is unchanged. SHOGUN_SHARP=0 turns it off.
//
// 4:3 fit: on screens narrower than 4:3 (square ones) the game shows its 16:9 picture across the
// width, and the side panels (button help, info) are moved in to stay on screen, where they cover
// the outer tiles (setup/ui_aspect_patch.cs computes how far from Aspect()). SHOGUN_ASPECT=fit
// gives every camera that draws to the screen a centred 4:3 viewport instead, with black bars
// above and below, and reports 4:3 to that layout, so the screen looks as it does at 640x480.
// The game's canvases are all world space, so they follow the camera viewports.
//
// Title screen run summary: the box with the saved run (run time, hero, location) opens to the
// right of Continue, and its right side is off screen when the screen is narrower than 16:9 (the
// game only keeps boxes opened above or below their target inside the screen). There it opens
// below Continue at the right edge of the screen, beside the other menu items.
using System;
using System.Reflection;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public static class PortSharp
{
    static bool started, sharp, fit;
    static RenderTexture low, big;
    static RawImage image;
    static Camera clearCam;

    public static void Init()
    {
        if (started) return;
        started = true;
        sharp = Environment.GetEnvironmentVariable("SHOGUN_SHARP") != "0";
        fit = Environment.GetEnvironmentVariable("SHOGUN_ASPECT") == "fit";
        SceneManager.sceneLoaded += (s, m) => Hook();
        RenderPipelineManager.beginCameraRendering += BeforeCamera;
        Hook();
    }

    // The screen aspect the panel layout works with: 4:3 at least in fit mode
    public static float Aspect()
    {
        return Letterbox() ? 4f / 3f : (float)Screen.width / Screen.height;
    }

    // whole numbers, so a 4:3 screen does not count as narrower through float rounding
    static bool Letterbox() { return fit && Screen.width * 3 < Screen.height * 4; }

    static Rect FitRect()
    {
        float h = (float)Screen.width / Screen.height * 3f / 4f;
        return new Rect(0f, (1f - h) / 2f, 1f, h);
    }

    static void Hook()
    {
        MoveContinueInfo();
        if (Letterbox() && clearCam == null) {
            // the bars are outside every viewport; this camera clears the whole screen first
            var go = new GameObject("PortFitClear");
            UnityEngine.Object.DontDestroyOnLoad(go);
            clearCam = go.AddComponent<Camera>();
            clearCam.depth = -100;
            clearCam.cullingMask = 0;
            clearCam.clearFlags = CameraClearFlags.SolidColor;
            clearCam.backgroundColor = Color.black;
            Debug.Log("PortSharp: 4:3 view on a " + Screen.width + "x" + Screen.height + " screen");
        }
        if (!sharp) return;
        image = null;
        foreach (var ri in Resources.FindObjectsOfTypeAll<RawImage>()) {
            var t = ri.texture as RenderTexture;
            if (ri.gameObject.scene.IsValid() && t != null && (t.name == "LowResRenderTexture" || t == big)) {
                image = ri;
                if (t != big) low = t;
            }
        }
        if (image == null || low == null) return;
        int height = Letterbox() ? Screen.width * 3 / 4 : Screen.height;
        int k = Math.Max(2, (height + low.height - 1) / low.height);
        if (big == null || big.width != low.width * k || big.height != low.height * k) {
            if (big != null) big.Release();
            big = new RenderTexture(low.width * k, low.height * k, 0, RenderTextureFormat.ARGB32);
            big.name = "PortSharpUpscale";
            big.filterMode = FilterMode.Bilinear;
            big.Create();
            Debug.Log("PortSharp: " + low.width + "x" + low.height + " shown through " + big.width + "x" + big.height);
        }
        image.texture = big;
    }

    // The game's types are in Assembly-CSharp, which references this assembly, so they are reached
    // through reflection.
    static void MoveContinueInfo()
    {
        if (Aspect() >= 1.7f) return;
        var itemType = Type.GetType("ContinueRunMenuItem, Assembly-CSharp");
        var baseType = Type.GetType("OptionsMenuItem, Assembly-CSharp");
        var actType = Type.GetType("InfoBoxActivator, Assembly-CSharp");
        if (itemType == null || baseType == null || actType == null) return;
        const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var actField = baseType.GetField("infoBoxActivator", F);
        var posField = actType.GetField("positioning", F);
        var targetField = actType.GetField("infoBoxTarget", F);
        if (actField == null || posField == null || targetField == null) return;
        foreach (var o in Resources.FindObjectsOfTypeAll(itemType)) {
            var item = o as Component;
            if (item == null || !item.gameObject.scene.IsValid()) continue;
            var act = actField.GetValue(item) as Component;
            if (act == null) continue;
            // Below Continue, between the menu and the right edge of the screen, beside the other
            // menu items. Every camera is orthographic with size 4.21875, so the right edge is
            // 4.21875 * aspect units from the middle. The box opened below a target spans from 1.23
            // units left of it to 2.27 right of it (3.5 units, measured); the menu items reach about
            // 1.15 units from the middle. It is scaled down where that gap is narrower than the box
            // (square screens), and its right side kept 0.45 units from the screen edge.
            var orig = targetField.GetValue(act) as Transform;
            if (orig == null || orig.name == "PortContinueInfoTarget") continue;
            float edge = 4.21875f * Aspect() - 0.45f;
            float boxScale = Mathf.Min(1f, (edge - 1.15f) / 3.5f);
            var target = new GameObject("PortContinueInfoTarget").transform;
            target.SetParent(orig.parent, false);
            target.position = new Vector3(edge - 2.27f * boxScale, orig.position.y - 0.25f, orig.position.z);
            // the game opens the box as a child of its target (and animates the box's own scale), so
            // the target carries the scale
            target.localScale = new Vector3(boxScale, boxScale, 1f);
            posField.SetValue(act, Enum.ToObject(posField.FieldType, 4));  // InfoBox.PositioningEnum.Below
            targetField.SetValue(act, target);
            Debug.Log("PortSharp: run summary box below Continue on the right, target " + orig.position + " -> " + target.position + ", scale " + boxScale);
        }
    }

    // Runs before every camera. Fit mode: a screen camera gets the 4:3 viewport before it draws.
    // Sharp: the copy is made before the camera that draws the RawImage, after the scene camera
    // has filled the low resolution target.
    static void BeforeCamera(ScriptableRenderContext ctx, Camera cam)
    {
        if (cam.targetTexture != null) return;
        if (cam != clearCam && Letterbox()) {
            var r = FitRect();
            if (cam.rect != r) cam.rect = r;
        }
        if (image == null || big == null || low == null) return;
        if (!image.isActiveAndEnabled || (cam.cullingMask & (1 << image.gameObject.layer)) == 0) return;
        Graphics.Blit(low, big);
    }
}
