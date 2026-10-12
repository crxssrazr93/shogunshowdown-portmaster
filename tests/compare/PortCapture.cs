// Test only helper (never shipped): makes a run of Shogun Showdown reproducible and saves
// numbered frames of the screen, so two builds of the game can be compared pixel by pixel.
//
//  * Time.captureFramerate: the simulation advances a fixed step per rendered frame.
//  * UnityEngine.Random and the game's one System.Random (Utils.MyRandom._R, created from the wall
//    clock; it shuffles and picks enemies, the map and rewards) are reseeded when a scene loads and,
//    in the title scene, every frame, so the first draws of a run do not depend on how long the menus
//    took. Every ParticleSystem gets a fixed random seed (new ones are found by a rescan every
//    frame). The game's one DateTime.Now is the name of a save backup.
//  * Every wall clock source is replaced by a frame based clock in the game's own assemblies
//    (capture_inject.cs redirects Time.unscaledDeltaTime, Time.unscaledTime and
//    Time.realtimeSinceStartup to PortCapture's versions, new WaitForSecondsRealtime to PortWaitRealtime, and SceneManager.LoadSceneAsync to a
//    wrapper that freezes the game clock while the scene loads; Shogun loads its scenes with the
//    synchronous LoadScene, so that wrapper is not used). Unity's captureFramerate only
//    fixes Time.deltaTime; the UI (UnityEngine.UI, TextMeshPro, the menu key repeat) runs on unscaled time.
//  * Input comes from a virtual gamepad that PortCapture feeds by scene frame (PORTCAP_INPUT), so
//    the menus are driven by frame numbers, not by when a script pressed a key.
//  * A frame counter per scene (rendered frames since the scene loaded). At the frames listed in
//    PORTCAP_FRAMES the back buffer is read at the end of the frame and written as a PNG.
//
// Environment:
//   PORTCAP_DIR     output folder (default ./portcap)
//   PORTCAP_FRAMES  "TitleScreen:90,200;Combat:30,150,300" (scene name, then frame numbers)
//   PORTCAP_SEED    random seed (default 1234)
//   PORTCAP_FPS     capture framerate (default 30)
//   PORTCAP_INPUT   "TitleScreen:900:A;TitleScreen:1000:A;Combat:600:RIGHT"
//                   scene:frame:action, action = BUTTON (tap: PORTCAP_TAP frames down, default 6), +BUTTON (hold) or
//                   -BUTTON (release). Buttons: A B X Y START SELECT LB RB LT RT DUP DDOWN DLEFT
//                   DRIGHT, stick LEFT RIGHT UP DOWN (left stick, full deflection)
//   PORTCAP_TRACE   1 = write <dir>/trace.txt, one line per frame (scene, scene frame, Time.time,
//                   Time.timeScale, Random state), to find where two runs part
//   PORTCAP_ACTIONS 1 = log every input action and binding of the game's PlayerInput when a scene loads
//   PORTCAP_STATE   1 = also write <scene>_<frame>.txt next to each PNG (a few game numbers that
//                   must match between two runs: Random state sample, Time.time, particle count)
// Every capture is logged as "PortCapture: wrote <file>"; "PortCapture: done" follows the last one.
//
// Build: mcs -target:library -r:<Managed>/UnityEngine.CoreModule.dll ... -out:PortCapture.dll PortCapture.cs
// Injected into GameInitialization.Start by capture_inject.cs.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.SceneManagement;

public static class PortCapture
{
    static bool started;
    internal static int fps;                 // 0 until Init has run: the helpers then return the real values
    internal static bool frozen;             // the game clock stands still while a scene loads
    static int lastFrame = -1;
    static float clock;
    static float savedScale;

    // the frame based replacements for Time.unscaledDeltaTime, Time.unscaledTime and
    // Time.realtimeSinceStartup (see capture_inject.cs)
    internal static void Advance()
    {
        int f = Time.frameCount;
        if (f == lastFrame) return;
        if (lastFrame >= 0 && !frozen) clock += (f - lastFrame) / (float)fps;
        lastFrame = f;
    }
    public static float UnscaledDeltaTime() { if (fps == 0) return Time.unscaledDeltaTime; Advance(); return frozen ? 0f : 1f / fps; }
    public static float UnscaledTime() { if (fps == 0) return Time.unscaledTime; Advance(); return clock; }
    public static float RealtimeSinceStartup() { if (fps == 0) return Time.realtimeSinceStartup; Advance(); return clock; }

    // SceneManager.LoadSceneAsync(string, LoadSceneMode) in the game's code goes through this: how
    // many frames a scene takes to load depends on the machine, so the game clock (Time.time and
    // the unscaled clock above) is frozen until sceneLoaded, and Time.time is the same at the first
    // frame of every run.
    public static AsyncOperation LoadSceneAsync(string name, LoadSceneMode mode)
    {
        if (fps != 0 && !frozen) { Advance(); frozen = true; savedScale = Time.timeScale; Time.timeScale = 0f; Debug.Log("PortCapture: clock frozen for " + name + " at game time " + Time.time.ToString("R")); }
        return SceneManager.LoadSceneAsync(name, mode);
    }
    internal static void Thaw()
    {
        if (!frozen) return;
        Advance(); frozen = false; Time.timeScale = savedScale;
        Debug.Log("PortCapture: clock thawed at game time " + Time.time.ToString("R"));
    }

    public static void Init()
    {
        if (started) return;
        started = true;
        // named like the game's own Steam object: its GameStateResetter (the scene a run restart or
        // "Skip tutorial" goes through) destroys every GameObject except one called "SteamManager",
        // which would end the capture
        var go = new GameObject("SteamManager");
        UnityEngine.Object.DontDestroyOnLoad(go);
        go.AddComponent<PortCaptureBehaviour>();
        // The first scene (GameInitialization) waits for the localization system to start, which
        // takes a different number of frames on every run; the title screen would then load at a
        // different Time.time (and shaders, tweens and the menu's own timers start from it). The game
        // clock stands still until that scene has been left, as it does while a scene loads in
        // LoadSceneAsync.
        if (!frozen) { Advance(); frozen = true; savedScale = Time.timeScale; Time.timeScale = 0f; Debug.Log("PortCapture: clock frozen until the first scene change, game time " + Time.time.ToString("R")); }
    }
}

// replaces WaitForSecondsRealtime (which waits on the machine's real clock) with a wait on the frame
// based clock; the game's own and the UI libraries' newobj calls are redirected here
public class PortWaitRealtime : WaitForSecondsRealtime
{
    float until = -1f;
    public PortWaitRealtime(float time) : base(time) { }
    public override bool keepWaiting
    {
        get {
            if (until < 0f) until = PortCapture.RealtimeSinceStartup() + waitTime;
            bool wait = PortCapture.RealtimeSinceStartup() < until;
            if (!wait) until = -1f;
            return wait;
        }
    }
}

public class PortCaptureBehaviour : MonoBehaviour
{
    int seed, fps, sceneFrame, tap;
    string dir, scene = "";
    bool state;
    readonly Dictionary<string, HashSet<int>> wanted = new Dictionary<string, HashSet<int>>();
    readonly Dictionary<string, int> last = new Dictionary<string, int>();
    readonly HashSet<string> finished = new HashSet<string>();
    bool allDone;
    StreamWriter trace;
    int dumpFrom = 1, dumpTo = 0;     // PORTCAP_DUMP="380-386": per body lines in the trace for those scene frames
    Gamepad pad;
    GamepadState padState;
    readonly Dictionary<string, List<KeyValuePair<int, string>>> input = new Dictionary<string, List<KeyValuePair<int, string>>>();
    readonly List<KeyValuePair<int, string>> release = new List<KeyValuePair<int, string>>();   // tap ends, by scene frame

    static string Env(string k, string d) { var v = Environment.GetEnvironmentVariable(k); return string.IsNullOrEmpty(v) ? d : v; }

    void Awake()
    {
        seed = int.Parse(Env("PORTCAP_SEED", "1234"));
        fps = int.Parse(Env("PORTCAP_FPS", "30"));
        tap = int.Parse(Env("PORTCAP_TAP", "6"));
        dir = Env("PORTCAP_DIR", "portcap");
        state = Env("PORTCAP_STATE", "0") == "1";
        Directory.CreateDirectory(dir);
        foreach (var part in Env("PORTCAP_FRAMES", "").Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)) {
            var kv = part.Split(':');
            if (kv.Length != 2) continue;
            var set = new HashSet<int>(); int max = 0;
            foreach (var f in kv[1].Split(',')) { int n; if (int.TryParse(f.Trim(), out n)) { set.Add(n); max = Math.Max(max, n); } }
            wanted[kv[0].Trim()] = set; last[kv[0].Trim()] = max;
        }
        foreach (var part in Env("PORTCAP_INPUT", "").Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)) {
            var kv = part.Split(':');
            int fr;
            if (kv.Length != 3 || !int.TryParse(kv[1], out fr)) continue;
            List<KeyValuePair<int, string>> l;
            if (!input.TryGetValue(kv[0].Trim(), out l)) input[kv[0].Trim()] = l = new List<KeyValuePair<int, string>>();
            l.Add(new KeyValuePair<int, string>(fr, kv[2].Trim()));
        }
        Application.runInBackground = true;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        pad = InputSystem.AddDevice<Gamepad>("PortCapture pad");
        // only the virtual pad drives the game: a real pad (stick drift on a handheld), keyboard or
        // pointer would make the device and PC runs differ (PORTCAP_ONLYPAD=0 keeps them)
        if (Env("PORTCAP_ONLYPAD", "1") == "1") {
            foreach (var d in InputSystem.devices) DisableReal(d);
            InputSystem.onDeviceChange += (d, change) => {
                if (change == InputDeviceChange.Added || change == InputDeviceChange.Reconnected || change == InputDeviceChange.Enabled) DisableReal(d);
            };
        }
        var dump = Env("PORTCAP_DUMP", "").Split('-');
        if (dump.Length == 2) { int.TryParse(dump[0], out dumpFrom); int.TryParse(dump[1], out dumpTo); }
        if (Env("PORTCAP_TRACE", "0") == "1") trace = new StreamWriter(System.IO.Path.Combine(dir, "trace.txt")) { AutoFlush = true };
        Time.captureFramerate = fps;      // PORTCAP_FPS=0: the game's own clock (to tell the helper's effects from the game's)
        PortCapture.fps = fps;
        QualitySettings.vSyncCount = 0;
        UnityEngine.Random.InitState(seed);
        SceneManager.sceneLoaded += OnLoaded;
        scene = baseScene = SceneManager.GetActiveScene().name;
        Debug.Log("PortCapture: seed " + seed + ", " + fps + " fps, dir " + dir + ", scenes " + string.Join(",", new List<string>(wanted.Keys).ToArray()));
        StartCoroutine(EndOfFrame());
    }

    void DisableReal(InputDevice d)
    {
        if (d == pad || !d.enabled) return;
        InputSystem.DisableDevice(d);
        Debug.Log("PortCapture: input device disabled: " + d.name + " (" + d.layout + ")");
    }

    // a scene that loads again (a run restart goes through the title or Combat again) is called
    // <name>#2, <name>#3 ... in PORTCAP_FRAMES and PORTCAP_INPUT, so scripts for the first and the
    // second visit do not mix; files are written as <name>2_<frame>.png
    readonly Dictionary<string, int> visits = new Dictionary<string, int>();
    string baseScene = "";

    void OnLoaded(Scene s, LoadSceneMode mode)
    {
        int n; visits.TryGetValue(s.name, out n); visits[s.name] = ++n;
        baseScene = s.name;
        scene = n == 1 ? s.name : s.name + "#" + n;
        loaded = true;
        sceneFrame = 0;
        UnityEngine.Random.InitState(seed);
        ReseedSystemRandom();
        // Unity drops gamepad input while its window has no focus; the clock stays frozen until it has
        // (a run that reaches the menus before the window system gave it focus lost a button press)
        if (Application.isFocused || waitFocus == "0") PortCapture.Thaw(); else { focusSince = Time.realtimeSinceStartup; Debug.Log("PortCapture: waiting for the window focus"); }
        if (Env("PORTCAP_ACTIONS", "0") == "1") LogActions();
        SeedParticles();
        Debug.Log("PortCapture: scene " + scene + " loaded, game time " + Time.time.ToString("R"));
    }

    static bool Button(string n, out GamepadButton b)
    {
        switch (n) {
            case "A": b = GamepadButton.South; return true;
            case "B": b = GamepadButton.East; return true;
            case "X": b = GamepadButton.West; return true;
            case "Y": b = GamepadButton.North; return true;
            case "START": b = GamepadButton.Start; return true;
            case "SELECT": b = GamepadButton.Select; return true;
            case "LB": b = GamepadButton.LeftShoulder; return true;
            case "RB": b = GamepadButton.RightShoulder; return true;
            case "DUP": b = GamepadButton.DpadUp; return true;
            case "DDOWN": b = GamepadButton.DpadDown; return true;
            case "DLEFT": b = GamepadButton.DpadLeft; return true;
            case "DRIGHT": b = GamepadButton.DpadRight; return true;
        }
        b = GamepadButton.South; return false;
    }

    // set (down = true) or clear one button, trigger or stick direction of the virtual pad
    void Apply(string n, bool down)
    {
        GamepadButton b;
        if (Button(n, out b)) {
            if (down) padState.buttons |= 1u << (int)b; else padState.buttons &= ~(1u << (int)b);
        } else if (n == "RT") padState.rightTrigger = down ? 1f : 0f;
        else if (n == "LT") padState.leftTrigger = down ? 1f : 0f;
        else if (n == "LEFT") padState.leftStick = new Vector2(down ? -1f : 0f, padState.leftStick.y);
        else if (n == "RIGHT") padState.leftStick = new Vector2(down ? 1f : 0f, padState.leftStick.y);
        else if (n == "UP") padState.leftStick = new Vector2(padState.leftStick.x, down ? 1f : 0f);
        else if (n == "DOWN") padState.leftStick = new Vector2(padState.leftStick.x, down ? -1f : 0f);
    }

    void DriveInput()
    {
        bool changed = false;
        List<KeyValuePair<int, string>> l;
        if (input.TryGetValue(scene, out l)) {
            foreach (var e in l) {
                if (e.Key != sceneFrame) continue;
                if (e.Value.StartsWith("+")) Apply(e.Value.Substring(1), true);
                else if (e.Value.StartsWith("-")) Apply(e.Value.Substring(1), false);
                else { Apply(e.Value, true); release.Add(new KeyValuePair<int, string>(sceneFrame + tap, e.Value)); }
                changed = true;
                Debug.Log("PortCapture: input " + scene + " frame " + sceneFrame + " " + e.Value);
            }
        }
        for (int i = release.Count - 1; i >= 0; i--) {
            if (release[i].Key != sceneFrame) continue;
            Apply(release[i].Value, false); release.RemoveAt(i); changed = true;
        }
        if (changed && pad != null) InputSystem.QueueStateEvent(pad, padState);
    }

    bool loaded;
    float focusSince = -1f;
    string waitFocus = Env("PORTCAP_WAITFOCUS", "1");

    void Update()
    {
        PortCapture.Advance();
        // (a window system that never reports focus does not stall the run for more than 30 real seconds)
        if (PortCapture.frozen && loaded && (Application.isFocused || (focusSince > 0f && Time.realtimeSinceStartup - focusSince > 30f))) {
            if (!Application.isFocused) Debug.Log("PortCapture: no window focus after 30 s, going on");
            PortCapture.Thaw();
        }
        if (!PortCapture.frozen) sceneFrame++;
        DriveInput();
    }

    void LateUpdate()
    {
        if (trace != null && baseScene == "Combat" && sceneFrame >= dumpFrom && sceneFrame <= dumpTo) {
            var rbs = UnityEngine.Object.FindObjectsOfType<Rigidbody2D>();
            Array.Sort(rbs, (a, b) => a.GetInstanceID().CompareTo(b.GetInstanceID()));
            foreach (var rb in rbs)
                trace.WriteLine("  body " + sceneFrame + " " + rb.GetInstanceID() + " " + rb.gameObject.name + " " + rb.position.x.ToString("R") + " " + rb.position.y.ToString("R") + " v " + rb.velocity.x.ToString("R") + " " + rb.velocity.y.ToString("R") + " " + rb.IsAwake());
        }
        if (trace != null)
            trace.WriteLine(scene + " " + sceneFrame + " t=" + Time.time.ToString("R") + " scale=" + Time.timeScale + " fixed=" + Time.fixedTime.ToString("R") + " rnd=" + JsonUtility.ToJson(UnityEngine.Random.state) + Bodies());
        SeedParticles();        // systems created this frame (death effects, ...) play from a fixed seed
        // Menu time varies with the wall clock; whatever the title scene drew, the next scene
        // starts from the same Random state (its Awake runs before sceneLoaded fires).
        if (baseScene == "TitleScreen") { UnityEngine.Random.InitState(seed); ReseedSystemRandom(); }
    }

    // Utils.MyRandom._R (private static System.Random, created from the clock) -> a fixed seed
    static System.Reflection.FieldInfo rField;
    void ReseedSystemRandom()
    {
        if (rField == null) {
            var t = Type.GetType("Utils.MyRandom, Assembly-CSharp");
            if (t == null) return;
            rField = t.GetField("_R", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
            if (rField == null) return;
        }
        if (Env("PORTCAP_NORESEED", "0") != "1") rField.SetValue(null, new System.Random(seed));
    }

    void LogActions()
    {
        foreach (var pi in UnityEngine.Object.FindObjectsOfType<PlayerInput>()) {
            Debug.Log("PortCapture: PlayerInput " + pi.name + " scheme " + pi.currentControlScheme + " map " + (pi.currentActionMap != null ? pi.currentActionMap.name : "-"));
            foreach (var map in pi.actions.actionMaps)
                foreach (var a in map.actions) {
                    var sb = new StringBuilder();
                    foreach (var b in a.bindings) sb.Append(" [" + b.groups + "] " + b.path + (b.isComposite ? "(composite " + b.name + ")" : "") + (string.IsNullOrEmpty(b.interactions) ? "" : " {" + b.interactions + "}"));
                    Debug.Log("PortCapture: action " + map.name + "/" + a.name + " enabled=" + a.enabled + sb);
                }
        }
    }

    // number and summed positions of the active 2D bodies: where two runs part shows here first
    static string Bodies()
    {
        int n = 0; double sx = 0, sy = 0;
        foreach (var rb in UnityEngine.Object.FindObjectsOfType<Rigidbody2D>()) { n++; sx += rb.position.x; sy += rb.position.y; }
        return " bodies=" + n + " sum=" + sx.ToString("R") + "," + sy.ToString("R");
    }

    static int Hash(string s) { unchecked { int h = (int)2166136261; foreach (char c in s) h = (h ^ c) * 16777619; return h & 0x7fffffff; } }

    static string Path(Transform t) { var sb = new StringBuilder(t.name); for (t = t.parent; t != null; t = t.parent) sb.Insert(0, t.name + "/"); return sb.ToString(); }

    int particles;
    void SeedParticles()
    {
        if (Env("PORTCAP_NOPARTICLES", "0") == "1") return;
        var all = Resources.FindObjectsOfTypeAll<ParticleSystem>();
        int n = 0;
        foreach (var ps in all) {
            if (!ps.gameObject.scene.IsValid()) continue;   // assets, not scene objects
            n++;
            if (!ps.useAutoRandomSeed) continue;
            bool playing = ps.isPlaying;
            if (playing) ps.Stop(false, ParticleSystemStopBehavior.StopEmittingAndClear);
            ps.useAutoRandomSeed = false;
            ps.randomSeed = (uint)(Hash(Path(ps.transform)) ^ seed);
            if (playing) ps.Play(false);
        }
        particles = n;
    }

    IEnumerator EndOfFrame()
    {
        var eof = new WaitForEndOfFrame();
        while (true) {
            yield return eof;
            HashSet<int> set;
            if (!wanted.TryGetValue(scene, out set) || !set.Contains(sceneFrame)) continue;
            Capture(sceneFrame);
            if (sceneFrame >= last[scene]) {
                finished.Add(scene);
                if (!allDone && finished.Count == wanted.Count) { allDone = true; Debug.Log("PortCapture: done"); }
            }
        }
    }

    void Capture(int frame)
    {
        int w = Screen.width, h = Screen.height;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0, false);
        tex.Apply(false);
        var png = tex.EncodeToPNG();
        UnityEngine.Object.Destroy(tex);
        var name = scene.Replace("#", "") + "_" + frame.ToString("D5");
        File.WriteAllBytes(System.IO.Path.Combine(dir, name + ".png"), png);
        if (state) {
            // draws from a copy of the generator state: restore it afterwards so the game's sequence is unchanged
            var st = UnityEngine.Random.state;
            var sb = new StringBuilder();
            sb.AppendLine("scene " + scene + " frame " + frame);
            sb.AppendLine("time " + Time.time.ToString("R") + " unscaled " + Time.unscaledTime.ToString("R") + " fixed " + Time.fixedTime.ToString("R"));
            sb.AppendLine("random " + UnityEngine.Random.value.ToString("R") + " " + UnityEngine.Random.value.ToString("R"));
            sb.AppendLine("particleSystems " + particles + " gameObjects " + Resources.FindObjectsOfTypeAll<GameObject>().Length);
            UnityEngine.Random.state = st;
            File.WriteAllText(System.IO.Path.Combine(dir, name + ".txt"), sb.ToString());
        }
        Debug.Log("PortCapture: wrote " + name + ".png (" + w + "x" + h + ")");
    }
}
