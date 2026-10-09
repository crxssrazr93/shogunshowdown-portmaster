# Porting notes

How Shogun Showdown was brought to PortMaster devices, in the order the problems came up, with the approaches that failed and why. Measurements are from an Anbernic RG35XX H (Allwinner H700, 4 Cortex A53 cores, Mali G31 MP1 with the r20p0 blob driver, 1 GB RAM, 486 MB swap) running Knulli, unless they say PC.

## 1. The game

* Unity 2021.3.43f1, Mono scripting, Universal Render Pipeline with the 2D Renderer (2D lights, bloom, three cameras per frame), the new Input System, Steamworks.NET.
* The Linux build is x86_64 only, so it runs under box64 inside Westonpack, which provides Weston, Xwayland and GLX over EGL (crusty_glx).
* Steam build 20620547, depot 2084002, 456 MB.

## 2. Graphics: OpenGL ES 3 from an OpenGLCore build

The 2021.3 Linux player only accepts OpenGLCore (17) or Vulkan (21) in its graphics API list; GLES3 (11) gives "Unknown renderer". It picks OpenGLCore shader programs by renderer, not by context, but its GL backend runs fine on an OpenGL ES 3.x context (it logs `GLES: 3`). So:

* `setup/gles_shaders2021.py` replaces the code of every OpenGLCore program (GLSL 150/330 from HLSLcc) with its GLSL ES 3.00 translation, keeping the program type. The text rewriter is unityport's `convert_program` (Knifethrower's PM-Porting-Tools, 0BSD, vendored in `setup/vendor/`); the 2021.3 blob layout (nested per platform segment tables, LZ4 compressed) is handled here.
* crusty_glx gives the player an ES context through GLX. glespass (from the Night in the Woods and Gone Home ports) is the `libGL.so.1` that box64's GL wrapper loads; it passes the calls to the GLES driver unchanged instead of translating them like gl4es.
* On a PC, `tests/pc/gles_force.c` makes Mesa create ES contexts the same way, which is how the conversion was developed.

### What failed on the device, in order

1. **Black screen, every shader failing to link, "no info log".** glespass logged `first glCompileShader ... (shader 0)`: object names of 0 mean no current context. crusty keeps its EGL context current on the main thread only, and Unity renders on its own thread, so every GL call from that thread was dropped. `GLESPASS_CTXFIX=1` (already in glespass) moves the EGL context when Unity hands the GLX context over. `-force-gfx-direct` would also work but puts rendering on the busy main thread.
2. **`P0005: #version must be on the first line`.** The converter put a marker comment (`// port: GLSL ES 3.00`) before `#version 300 es` so a second run could skip converted programs. Mesa accepts a comment there, Mali does not.
3. **Moving the marker to the end did not help.** Unity treats any text outside a program's stage sections as shared code and puts it in front of every stage, so the comment landed above `#version` again. The marker is gone: converted programs declare `#version 300 es` and the converter only touches 150/330 programs anyway. Lesson: Mesa is not a stand in for Mali's GLSL front end; test shaders on the device early.
4. **Title art and scene black, only the interface visible, no GL errors.** This took the longest. Ruled out, each by a direct test:
   * texture compression formats (the sprites are RGBA32; the format survey is in the workspace),
   * functions glespass binds to a no op (a new `GLESPASS_NOOPLOG` names every such function on its first call; none were called),
   * driver errors (`GLESPASS_KHRDEBUG` installs a KHR_debug callback; the only message was a harmless `glTexParameterf` pname),
   * unconverted shaders (a survey of every shader: all used ones are ES),
   * frame alpha (`GLESPASS_OPAQUE`), threading (`-force-gfx-direct`),
   * Mali's missing extensions, by disabling them in Mesa on the PC (that pushed Mesa onto llvmpipe and ES 2.0, so the test was void).

   What found it was a frame probe (`GLESPASS_PROBE=N`): for one frame it logs every framebuffer bind, clear, draw count, blit and invalidate, the formats of the attached textures, and the centre pixel of each framebuffer as the frame leaves it. The scene rendered correctly into its 480x270 target, post processing worked, and a second camera put the correct picture on screen. The last camera (interface and post processing) then started with a colour clear of the shared 640x480 target before drawing over it, so only the interface survived. That camera relies on its target keeping the previous cameras' output (a "don't care" load). Unity evidently turns "don't care" into a clear on GPUs it takes for tile based, judged from the `GL_RENDERER` / `GL_VENDOR` strings: Mesa on the PC does not get the clear, Mali does, and hiding the strings removes it (this is inferred from that test, not from Unity's source). `GLESPASS_VENDOR` / `GLESPASS_RENDERER` give the player neutral strings (`Generic`, `GLES-device`), and the picture is complete.

The PortMaster ports repository has no Unity port, and the research found no known good reference for a Unity 2020+ URP game on these devices, so these notes may help the next one.

## 3. Memory

| State | Before | After |
| :---- | :----- | :---- |
| Audio at start (PC) | about 900 MB RSS, 577 MB of decoded PCM | about 400 MB |
| GPU memory in a run (device) | 349 MB, then killed by the OOM killer | 187 MB |
| Swap free in a fight (device) | 0 | about 200 MB |

* **Audio.** Every clip was Vorbis with load type DecompressOnLoad, all in the boot scene. `setup/audio_loadtype.py` sets clips over 60 s to Streaming and over 10 s to CompressedInMemory; the Vorbis data is unchanged.
* **Textures.** Starting a run took the GPU from 103 to 349 MB (Mali GPU memory is plain RAM and cannot be swapped) while the game's own memory filled the swap. None of the textures were readable or mipmapped, so there was nothing to save losslessly. ASTC 4x4 stores them at a quarter of the size and looks the same at the game's scale (compared at 2x zoom). Unity's GL backend accepts ASTC on these drivers (no "not supported" fallback in the log).
* **How the conversion runs.** It has to happen on the player's own copy. `setup/astc_manifest.py` records at build time, for every texture to convert (677 of them, at least 64x64), the offsets of the fixed size fields to rewrite in the `.assets` file and where its pixels are in the `.resS` file, plus the MD5s of the files those offsets belong to. `tools/astc_textures.py` (python3 standard library only) reads each texture, writes a top left origin TGA (so the rows stay in Unity's bottom up order), runs PortMaster's `astcenc` (`-fast`, 4x4), appends the blocks to the `.resS` file and rewrites the four fields in a copy of the `.assets` file, which then replaces the original. It takes 52 s on the device. An interrupted run is detected by the `.resS` size and redone from the original part.

### Reinstalls, new copies and interrupted setups

The texture step first kept its markers (the MD5 each converted file was left with) in the port folder's `astc/`, apart from the files. Game data copied into a fresh port folder then matched neither the original nor the patched MD5, and the setup failed every time after that. The markers now sit next to the files they describe (`ShogunShowdown_Data/<file>.astc_done`); the launcher moves markers from older releases there. The marker is written before the converted `.assets` file replaces the old one, so a setup stopped between the two renames leaves the unconverted file, which the next run converts again. A converted `.assets` only counts as done while its `.resS` still holds the appended textures (a fresh `.resS` copied over a converted install asks for the whole game again instead of leaving textures pointing past its end), and a missing file is reported as missing instead of as an unexpected version. Tested on the PC (fresh setup, old marker layout, a stop between the renames, a fresh `.resS`, a missing file, then the game copied again: byte identical to the first setup) and on the RG35XX H (an install with the old layout, setup rerun, title screen).

## 4. Steam

Without Steam the first scene never loads: with `steam_appid.txt` and no client, `SteamAPI.Init` fails, and the game's `GameInitialization.InitializeAndSwitchScene` then calls `SteamUtils.IsSteamRunningOnSteamDeck`, which throws. So the port needs a stand in `libsteam_api.so`.

The first stand in answered all 1059 Steamworks exports. Before submission it was cut to the 49 functions that are actually used:

* the game's own code calls 12 Steamworks.NET methods (found with `monodis` on `Assembly-CSharp.dll`): Init, RestartAppIfNecessary, RunCallbacks, Shutdown, SetWarningMessageHook, IsSteamRunningOnSteamDeck, GetPersonaName (only in a debug log line), GetAchievement, SetAchievement and StoreStats;
* Steamworks.NET's own start up asks for every interface pointer, and RunCallbacks uses manual dispatch (a logging build of the stub recorded every call on a full run).

Init succeeds and the interface getters return a placeholder object so Steamworks.NET considers Steam available; everything else reports nothing. The game makes no ownership checks and the stub has none. This follows the stubs in the merged Papers, Please and Osmos ports.

The original library is kept as `gamedata/libsteam_api.so.orig`, outside `Plugins/`: Unity loads every library in that folder, and an early version that left the backup there had the player load both.

## 5. Controls

1. **Only the D-pad worked.** Unity's Input System uses an SDL built into the player, older than the SDL PortMaster's mappings are written for. It numbers buttons from BTN_JOYSTICK (0x120) up first and then every lower key code; current SDL numbers all key codes in ascending order. The H700 pads also report codes 1, 114 and 115, so every button index in PortMaster's mapping was off by three while the hat (D-pad) was fine. The launcher renumbers the built in pad's mapping line from the pad's `capabilities/key` bitmap and passes it to the game as a `VAR=value` argument to `westonwrap.sh`. Exporting it was not enough: Westonpack sources PortMaster's `control.txt` again before it starts the game, and on muOS that exports the original mapping over the launcher's (Knulli's does not). `westonwrap.sh` evals its arguments, so the mapping goes as one line with the spaces in the pad's name replaced (SDL matches the GUID). Tested on an RG35XX H with muOS: menus, a new run, L2/R2 moves, Start pause, exit hotkey.

   PortMaster also expects `# PORTMASTER: <zip>, <script>` at the top of the launcher; without it harbourmaster inserts the line the first time it downloads a runtime, which broke a launcher that was running at the time.
2. Tried first, without effect: `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1`, and giving the window X input focus (`GLESPASS_FOCUS=1`, X already reported the window as focused). Both were the wrong assumption: the pad was seen all along.
3. The game's default scheme is positional (Xbox): south confirms, west attacks, LT/RT move. On Anbernic pads the bottom button is labelled B. The shipped README lists both names. GO in the camp is a hold on the attack button.

## 6. Packaging

* The launcher runs PortMaster's patcher (`utils/patcher.txt`) when the stamp of the nine files the setup changes does not match. `tools/patchscript` checks each patched file's MD5 before and after, skips files already done (including files the ASTC step rewrote, through its markers in `astc/`), and writes the stamp only when everything succeeded. A different game version stops with a message instead of a broken game.
* box64 has no native wrapper for `libgcc_s.so.1`, which `UnityPlayer.so` and Mono need; the port carries box64's x86_64 copy (`BOX64_LD_LIBRARY_PATH`), as Papers, Please does.
* `build/make_patches.sh` regenerates the xdelta patches, the manifest and the MD5s from an untouched Steam copy and reproduces the committed files byte for byte.

## 7. Performance

| Where | fps |
| :---- | :-- |
| Title | 25 (30 with the box64 settings below) |
| Fight | 14.5 (17.5 to 18.5) |

The main thread is at about 93% of a core in fights, and Unity's render thread and the GPU are mostly idle, so this is the game's and URP's C# code under box64. Tried without effect: `BOX64_DYNAREC_BIGBLOCK=3` with `FORWARD`, `CALLRET`, `SAFEFLAGS=0`, `FASTNAN`, `FASTROUND`; `BOX64_DYNAREC_STRONGMEM=0`. Doubling the physics timestep (0.02 to 0.04 s) halved the fight frame rate and was dropped. The game is turn based, so 14 fps is playable, but animations are choppy.

**Why those box64 settings did nothing, and what helped (2026-10-09).** box64 0.4.4 recognises the Mono runtime and then forces `BOX64_DYNAREC_BIGBLOCK=0` and `STRONGMEM=1`, overriding whatever the launcher sets, so every dynarec experiment above ran with the same settings. `BOX64_DYNAREC_BLEEDING_EDGE=0` switches that off. Measured in the same fight (presented fps, RG35XX H):

| box64 settings (all with `BLEEDING_EDGE=0` except the first) | Title | Fight |
| :-- | :-- | :-- |
| none (Mono profile: BIGBLOCK 0, STRONGMEM 1) | 25.4 | 13.7 |
| STRONGMEM 1, BIGBLOCK 0 | 24.4 | 13.8 |
| STRONGMEM 1, BIGBLOCK 1 | 29.8 | 16.4 |
| STRONGMEM 1, BIGBLOCK 2 (shipped) | 30.4 | 18.0 |
| STRONGMEM 1, BIGBLOCK 3 | 30.6 | 18.4 |
| STRONGMEM 0, BIGBLOCK 2 | 30.8 | 18.6 |
| box64 defaults (STRONGMEM 0, BIGBLOCK 1) | 30.8 | 18.7 |

The cost is BIGBLOCK 0. The launcher passes `BLEEDING_EDGE=0 STRONGMEM=1 BIGBLOCK=2`: nearly all of the gain, with the strong memory ordering kept for Mono's threads. Thirteen minutes of random input through fights, deaths and restarts ran without a fault. `MONO_INLINELIMIT=80` changed nothing (13.8). Also without effect (fights 17.1 to 17.3 either way): vsync off (`vSyncCount` 0 in Options.dat; the title stays at 30, so the game caps its frame rate), and skipping URP's per frame volume update on the two cameras without post processing (LowResCamera, MainCamera) through `SetVolumeFrameworkUpdateMode(ViaScripting)`.

### Sharp upscaling

The game draws its scene into a 480x270 render texture with point filtering and shows it on a RawImage scaled to the screen height: 1.78x at 640x480 and 2.67x at 720x720 and 1280x720. With nearest neighbour sampling at those factors, art pixels come out 1 or 2 (2 or 3) screen pixels wide, so lines wobble in width as things move. `setup/PortSharp.cs` (built into `patch/PortSharp.dll`) swaps the RawImage's texture for a copy k times larger (k = screen height / 270 rounded up, at least 2), filled each frame with a nearest neighbour `Graphics.Blit` just before the camera that draws the RawImage, and shown with bilinear filtering. Every art pixel becomes an even block and only the edges between blocks are blended ("sharp bilinear"). `setup/sharp_inject.cs` adds the call to `PortSharp.Init()` at the start of `GameInitialization.PCInitialization`; the launcher copies `PortSharp.dll` into `Managed/` when it is missing or differs. On the RG35XX H (480x270 drawn through 960x540) fights ran at 17.1 to 17.2 fps with it and 17.2 without. `SHOGUN_SHARP=0` turns it off.

## 8. glespass diagnostics added

All off unless set, documented at the top of `glespass/glespass.c`:

| Variable | What it does |
| :------- | :----------- |
| `GLESPASS_NOOPLOG=1` | names each GL function without an implementation on its first call |
| `GLESPASS_KHRDEBUG=N` | logs up to N driver messages through KHR_debug, each distinct one at most 3 times |
| `GLESPASS_PROBE=N` | logs how frame N is drawn (framebuffers, formats, clears, draws, blits, invalidates, centre pixels) |
| `GLESPASS_VENDOR`, `GLESPASS_RENDERER` | replace the `GL_VENDOR` / `GL_RENDERER` strings the game sees (used by the port) |
| `GLESPASS_FOCUS=1` | gives the game window X input focus when it lacks it |

## 9. Still to do

* Frame rate in fights. Ideas not yet tried: Unity's `-force-gfx-direct` with box64 settings tuned for it, turning off bloom (a data change, with a visible difference), and profiling the main thread with box64's perf map on a PC.
* Testing on other devices and CFWs, especially screens other than 640x480 and devices with more RAM.
* The button help panel at the right edge of fights is partly cut off on 4:3 screens (the game's own layout).

**ROCKNIX: "BOX64 Error: Loading needed libs".** ROCKNIX exports its own `BOX64_LD_LIBRARY_PATH=/usr/share/box64/lib`, and on a ROCKNIX x55 (libmali) the game started with that value instead of the port's, even though the launcher set it on `westonwrap.sh`'s environment (westonwrap sources PortMaster's control files again before it starts the game). box64 then could not find the game's x86 libraries. The launcher now passes the box64 settings as `VAR=value` arguments to `westonwrap.sh`, which applies them to the game's command itself, and sets `BOX64_LOG=1` so a log names any library that still fails to load.
