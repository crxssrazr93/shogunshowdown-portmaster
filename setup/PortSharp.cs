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
using System;
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
