// Sharp upscaling for Shogun Showdown on screens that are not a whole multiple of its 480x270 picture.
//
// The game renders its scene into the 480x270 RenderTexture "LowResRenderTexture" (point filtered)
// and shows it on a RawImage scaled to the screen height: 1.78x at 640x480, 2.67x at 720x720 and
// 1280x720, so art pixels come out 1 or 2 (2 or 3) screen pixels wide. Here the RawImage shows a
// copy k times larger instead (k = screen height / 270, rounded up, at least 2), made each frame
// with nearest neighbour sampling, and drawn with bilinear filtering: every art pixel becomes a
// k x k block, and only the edges between blocks are blended when it is scaled to the screen
// ("sharp bilinear"). What the game draws is unchanged. SHOGUN_SHARP=0 turns it off.
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public static class PortSharp
{
    static bool started;
    static RenderTexture low, big;
    static RawImage image;

    public static void Init()
    {
        if (started) return;
        started = true;
        if (Environment.GetEnvironmentVariable("SHOGUN_SHARP") == "0") return;
        SceneManager.sceneLoaded += (s, m) => Hook();
        RenderPipelineManager.beginCameraRendering += BeforeCamera;
        Hook();
    }

    static void Hook()
    {
        image = null;
        foreach (var ri in Resources.FindObjectsOfTypeAll<RawImage>()) {
            var t = ri.texture as RenderTexture;
            if (ri.gameObject.scene.IsValid() && t != null && (t.name == "LowResRenderTexture" || t == big)) {
                image = ri;
                if (t != big) low = t;
            }
        }
        if (image == null || low == null) return;
        int k = Math.Max(2, (Screen.height + low.height - 1) / low.height);
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

    // Runs before every camera; the copy is made before the camera that draws the RawImage, after
    // the scene camera has filled the low resolution target.
    static void BeforeCamera(ScriptableRenderContext ctx, Camera cam)
    {
        if (image == null || big == null || low == null || cam.targetTexture != null) return;
        if (!image.isActiveAndEnabled || (cam.cullingMask & (1 << image.gameObject.layer)) == 0) return;
        Graphics.Blit(low, big);
    }
}
