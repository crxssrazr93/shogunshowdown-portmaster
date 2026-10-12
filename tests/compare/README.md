# Render comparison (PC side)

Renders the same game states with the game's original OpenGL shaders, with the port's GLSL ES 3.00 conversion, and with the port's ASTC compressed textures on top, frame by frame, and compares the pictures. Test code only: nothing here is shipped, and nothing under `port/`, `setup/` or `build/` is touched.

## The three copies

`make_copies.sh` builds them from the untouched Steam Linux build (`~/Games/steam-ports/shogunshowdown/linux`, checked against the original MD5s in `port/shogunshowdown/tools/patchscript`), following `build/make_patches.sh` and the setup script:

* `cmp-ref`: everything the port does except `setup/gles_shaders2021.py` and the ASTC step. Original OpenGLCore shader programs. Audio load types, the UI aspect patch, `PortSharp` (sharp upscaling, 4:3 fit) and the Steam stub are in.
* `cmp-port`: everything except the ASTC step. The six patched files are checked against the MD5s `patchscript` expects after the xdelta patches, so this is what the port ships. It isolates the shader conversion.
* `cmp-astc`: `cmp-port` plus setup step 7 (`port/shogunshowdown/tools/astc_textures.py` with an x86_64 astcenc, `astcenc-avx2` 5.3.0 from `~/Games/steam-ports/tools/astcenc/bin`, set `ASTCENC` to use another). The device uses PortMaster's own astcenc, which may be another version, so the compressed bytes can differ a little from the device's.

Then, identically in all three, the test helper `PortCapture` is injected. The script lists the files that differ and stops if one is not meant to: ref against port may differ only in the five shader carrying files (`globalgamemanagers.assets`, `resources.assets`, `sharedassets0.assets`, `sharedassets2.assets`, `Resources/unity_builtin_extra`), port against astc only in the three texture files (`resources.assets`, `sharedassets1.assets`, `sharedassets2.assets` and their `.resS`).

`PortSharp` and the UI patches are in all three, and `run_capture.sh` gives all three the same `SHOGUN_ASPECT` (default `fill`) and `SHOGUN_SHARP` (default `1`), the port's defaults.

## How a run is made repeatable

`PortCapture.cs` (injected into `GameInitialization.Start` by `capture_inject.cs`, Mono.Cecil) fixes the simulation step, the clocks and the random seeds and writes the frames. What this game needs on top:

* Fixed simulation step of 1/30 s per rendered frame (`Time.captureFramerate`). The game's own tweening is LeanTween (in `Assembly-CSharp-firstpass`), plus UnityEngine.UI and TextMeshPro, so `Time.unscaledDeltaTime`, `Time.unscaledTime`, `Time.realtimeSinceStartup` and `new WaitForSecondsRealtime` are redirected to a frame based clock in `Assembly-CSharp`, `Assembly-CSharp-firstpass`, `UnityEngine.UI` and `Unity.TextMeshPro`. (The game has no DOTween. It loads every scene with the synchronous `LoadScene`, so the `LoadSceneAsync` wrapper stays unused.)
* Randomness: `UnityEngine.Random` and the game's one `System.Random` (`Utils.MyRandom._R`, created from the clock, used for shuffles, enemy and reward picks) are reseeded when a scene loads and every frame in the title scene. Every `ParticleSystem` gets a fixed seed. The only `DateTime.Now` names a save backup.
* The first scene (`GameInitialization`) waits for the localization system, which takes a different number of frames on every run, so the title screen used to load at a different `Time.time`. The game clock (`timeScale` 0 and the redirected clock) therefore stands still from `GameInitialization.Start` until the first scene change, and then until the window has focus (Unity drops gamepad input without focus; a run that was fast enough to press a button before the window system gave focus lost that press, which is why `run_capture.sh` focuses the window every second from the start).
* The game's `GameStateResetter` (the scene "Skip tutorial" and run restarts go through) destroys every GameObject except one called `SteamManager`, so the helper's object has that name. A scene that loads a second time is called `<name>#2` in frame lists and input scripts (`Combat#2` is the combat scene after the tutorial was skipped), and its files are written as `Combat2_<frame>.png`.
* Input is the new Input System (a `PlayerInput` with a Combat and a Menu action map, schemes `GamepadA`, `GamepadB`, `GamepadLegacy`, `KeyboardAndMouse`, `KeyboardOnly`; `PORTCAP_ACTIONS=1` logs every action and binding). `PortCapture` adds a virtual gamepad and feeds it by scene frame number (`PORTCAP_INPUT`), and disables every real device inside the game (`PORTCAP_ONLYPAD`), so the handheld's own pad cannot disturb the run. The game picks the `GamepadA` scheme for it. Buttons: RT and LT move right and left, Y turns around, A picks the selected tile into the attack queue (and interacts), X attacks (a tap in a fight, a hold of about a second on the camp's GO button), B waits, RB toggles the info mode, the D-pad navigates, START pauses. A tap is 6 frames (`PORTCAP_TAP`).
* The player runs under `setarch -R` (Mono's object hashes are address based), in an offscreen Xvfb (never the desktop display), in bwrap without input devices, with a null ALSA device (FMOD crashes listing this PC's plugins).

## Scenarios (`scenarios.sh`)

All start from an empty home, so the first run is the tutorial. Menu steps are 50 to 60 frames apart.

* `fight` (24 frames, about 1700 frames of play): title ("press any button" and the menu), the tutorial's first frames and the pause menu, skip the tutorial (a new run), the camp, hero selection (hold X on GO), the map, the first fight in the bamboo grove (queue tiles with A, attack with X, wave 1 won, wave 2 begins, more moves).
* `hub` (11 frames): the camp's archive (quests panel) and the shop (unlock tiles, D-pad navigation).
* `tutorial` (18 frames, about 3500 frames): the tutorial lessons (moving, attack queue, attacking, info mode, practice dummies, turns, the first enemy).

## Running

```
tests/compare/make_copies.sh                      # once: cmp-ref, cmp-port, cmp-astc, PortCapture in all
tests/compare/run_all.sh fight                    # 2 runs of each build, summary in out/summary_fight.txt
RES=720x720 RUNS=1 tests/compare/run_all.sh fight # square screen (PortSharp fill mode), summary_fight_720x720.txt
tests/compare/run_capture.sh ref fight ref_fight_1          # one run: ref|port|astc, scenario, tag [WxH]
tests/compare/compare.py ref_fight_1 port_fight_1           # one pair (--strict: exit 1 on any difference)
tests/compare/compare_runs.py fight ref port                # all runs of two builds, best pair per frame
tests/compare/diff_hist.py ref_fight_1 port_fight_1         # difference values against the sRGB steps
tests/compare/log_scan.py ref_fight_1 port_fight_1 astc_fight_1   # shader errors in player.log
tests/compare/sheet.py ref_fight_1                          # contact sheet of a run (exploring)
tests/compare/install_capture.sh                            # rebuild PortCapture after editing it
```

A run takes about 5 minutes (software GL renders the fight scenes at about 6 frames per second); `run_all.sh` runs two games at a time. `run_capture.sh` env: `ACTIONS=1`, `TRACE=1` (per frame trace), `SEED`, `ASPECT`, `SHARP`, `FRAMES_OVERRIDE`, `INPUT_OVERRIDE`, `MAXWAIT`. Needs mono with `mcs` and Mono.Cecil 0.11, `bwrap`, `Xvfb`, `xdotool`, python with PIL and numpy, and UnityPy and lz4 for `make_copies.sh` (it uses the steam-ports `venv-unity`, or makes `tests/compare/.venv`).

## Reading the output

`compare.py`: per frame PSNR, maximum absolute channel difference, share of pixels with any channel differing (`%>0`), by more than 2 and by more than 16, and in `out/<name>/` a `_heat.png` (difference times 8 in red over a dark copy) and a `_side.png` (A, B, heat) for each frame that differs. `compare_runs.py` takes several runs of each build and compares the best pair per frame next to how far a build differs from itself. `log_scan.py` counts shader compile and link failures, "not supported", "fallback" and error shader lines per shader name (the GL extension list contains `GL_KHR_no_error` and is skipped).

## Results (2026-10-13)

See the end of this file for the numbers of the last runs. Determinism: every frame of the `fight` scenario is bit identical between two runs of the same build, for `cmp-ref`, `cmp-port` and `cmp-astc`, at 640x480 (24 of 24 frames each, two games running at once).

Reading the differences between builds:

* ref against port (the shader conversion, plus the move from a desktop GL to a GLES 3.2 context, which cannot be separated on this PC because the converted programs do not run on a desktop GL context and the originals do not run on GLES): every frame differs a little. 2.5 to 12.5% of the pixels differ by 1 or more, 0.3 to 1.8% by more than 2, and the largest difference is 13 on almost every frame (22 on a few). The difference values are not spread evenly: they peak at 13, 9 and 6 (`diff_hist.py`), which are the sRGB steps between neighbouring levels of an 8 bit linear buffer (0 to 1 is 13 levels, 1 to 2 is 9, 2 to 3 is 6.6). The game renders into a linear 8 bit buffer and encodes to sRGB on the way out, so when the two GL implementations round one buffer level apart, the output differs by that step in the darkest areas and by 1 or 2 elsewhere. That is rounding, not a different picture. The frames of the map screen also show up to 10 pixels per frame that differ by up to 100: one screen pixel wide columns at the edge between two art pixels where the nearest neighbour sample falls on the neighbouring art pixel (`out/ref_vs_port_fight/Combat2_00540_side.png`). Nothing visible differs in any frame.
* port against astc: ASTC 4x4 compression artefacts, as expected. They sit on sprite edges, fine pixel art and small UI text (`out/port_vs_astc_fight/Combat2_00780_side.png`); at most 3% of the pixels differ by more than 2, at most 0.05% by more than 16 (largest 70).
* ref against astc: the sum of both.

Shader log scan: `cmp-ref` has no problems. `cmp-port` and `cmp-astc` log, once the first enemy dies, `GLSL 1.50 is not supported` and `GLSL 3.30 is not supported` (GLES only takes ES versions) for the engine's own `GUI/Text Shader` ("Creation of internal variant of shader 'GUI/Text Shader' failed", 4 times) and `ShaderProgram is unsupported` 12 times. The cause is a file the port does not convert: `Resources/unity default resources` holds six engine shaders (`Hidden/InternalErrorShader`, `Hidden/InternalClear`, `Hidden/Internal-Colored`, `Hidden/Internal-Loading`, `GUI/Text Shader`, `Hidden/FrameDebuggerRenderTargetDisplay`) and `setup/gles_shaders2021.py` does not list it. No captured frame shows a difference from it (IMGUI draws nothing visible), but the shaders stay GLSL 150 and 330 on the device too, where the same four messages appear. Converting them would add a seventh patched game file to setup for no visible change, so the port leaves them as they are.

Device run (RG35XX H, Knulli, `dev_fight_1`, 640x480): the installed port's data is byte identical to `cmp-astc`, textures included, so `astc_fight_1` is the reference. All 24 frames show the same picture: same scenes, same positions, same UI, nothing missing. The pixels still differ by 1 to 4 levels over most of each frame (PSNR 28.6 to 42.7 dB), for one reason: Mali keeps more precision than an 8 bit linear buffer in the game's full screen vignette pass. The PC frames only hold the sRGB values an 8 bit linear buffer can produce (0, 13, 22, 28, 34, 38 below 40), the device frames hold every value, and the difference map follows the vignette's gradient with contour lines where the PC version bands. Rounding the device frames through an 8 bit linear buffer does not make them identical, so the device also rounds the gradient a level or two higher; that is invisible. The few pixels that differ by more than 16 (at most 0.33% of a frame) are one pixel tall rows on the edges of the large banner text and of UI boxes, the nearest neighbour ties described above. The device log has the same `GUI/Text Shader` messages and nothing else.

## On the device

`device/Shogun Compare.sh` is a test launcher (never shipped) that runs the port's own game path (box64, glespass, Westonpack, crusty_glx, 640x480) with PortCapture and writes `ports/shogcmp/portcap/<tag>/frames`. The scenario's input script and frame list come from `scenarios.sh` copied next to it, so device and PC use the same ones.

1. Make `ports/shogcmp` on the device from the installed, set up port: copy `gamedata` (with the patched and ASTC converted `ShogunShowdown_Data`), `box64`, `glespass` and `steamstub` from `ports/shogunshowdown`. Then copy `PortCapture.dll`, `Assembly-CSharp.dll`, `Assembly-CSharp-firstpass.dll`, `UnityEngine.UI.dll` and `Unity.TextMeshPro.dll` from `cmp-astc/ShogunShowdown_Data/Managed/` into `ports/shogcmp/gamedata/ShogunShowdown_Data/Managed/` (`Assembly-CSharp.dll` there is the port's patched one plus the helper; the other three are the game's own with the clock redirects). Check first that `globalgamemanagers.assets`, `sharedassets0.assets`, `Resources/unity_builtin_extra` and `PortSharp.dll` are byte identical to `cmp-astc` (md5sum). The texture files (`resources.assets`, `sharedassets1.assets`, `sharedassets2.assets` and their `.resS`) are the ones PortMaster's astcenc made on the device and may differ in bytes from this PC's astcenc, which only changes the compression noise.
2. Copy `device/Shogun Compare.sh` to `ports/`, and `scenarios.sh` and a `run.cfg` into `ports/shogcmp/`. `run.cfg` holds `SCEN=fight` and `TAG=dev_fight_1` (`SHOGUN_ASPECT=fill`, `SHOGUN_SHARP=1` and `RES=640x480` are the defaults). Reload the game list (`curl localhost:1234/reloadgames`) and launch it (`curl -d "<path>" localhost:1234/launch`).
3. Turn address space randomisation off for the run (`echo 0 > /proc/sys/kernel/randomize_va_space`, as `setarch -R` on the PC) and back on afterwards (`echo 2`). The run starts from an empty `ports/shogcmp/home`, so it always plays the tutorial first and then the skip.
4. When `PortCapture: done` is in `ports/shogcmp/portcap/<tag>/player.log`, stop the game (`curl localhost:1234/emukill`), copy `portcap/<tag>/frames` to `tests/compare/runs/<tag>/frames` here and run `./compare.py ref_fight_1 dev_fight_1`, `./compare.py port_fight_1 dev_fight_1` and `./compare.py astc_fight_1 dev_fight_1`.
5. Remove `ports/shogcmp` and the launcher from the device afterwards.

The device frame rate is lower than the PC's in some scenes, which does not matter: the game advances 1/30 s per rendered frame whatever the real speed.

## Numbers of the last runs

Per frame tables are in `out/summary_<scenario>.txt` (written by `run_all.sh`, not committed). Ranges over the frames of one scenario, first run of each build, 640x480 unless noted:

| scenario | pair | PSNR dB | max difference | pixels differing | by more than 2 | by more than 16 |
|---|---|---|---|---|---|---|
| fight (24 frames) | ref, port | 52.9 to 56.6 | 13 (map frames 93 to 100) | 2.5 to 12.5% | 0.28 to 1.82% | up to 0.003% |
| fight | port, astc | 50.4 to 61.5 | 13 to 70 | 0.6 to 8.2% | 0.10 to 3.03% | up to 0.046% |
| fight | ref, astc | 49.5 to 55.5 | 13 to 100 | 3.5 to 18.2% | 0.37 to 4.30% | up to 0.045% |
| fight, 720x720 | ref, port | 51.8 to 59.9 | 13 (map frames 102) | 1.5 to 13.2% | 0.15 to 1.58% | up to 0.004% |
| fight, 720x720 | port, astc | 50.2 to 63.3 | 13 to 70 | 0.4 to 9.0% | 0.07 to 3.44% | up to 0.050% |
| hub (11 frames) | ref, port | 48.2 to 56.6 | 13 to 15 | 3.0 to 28.3% | 0.28 to 5.07% | 0 |
| hub | port, astc | 50.0 to 61.5 | 13 to 70 | 0.6 to 5.1% | 0.10 to 2.21% | up to 0.057% |
| tutorial (18 frames) | ref, port | 54.7 to 57.5 | 13 to 14 | 4.3 to 10.4% | 0.84 to 1.36% | 0 |
| tutorial | port, astc | 50.5 to 59.5 | 25 to 70 | 2.7 to 5.3% | 0.72 to 2.22% | up to 0.058% |

Two runs of the same build are bit identical in every scenario (fight 24 of 24, hub 11 of 11, tutorial 18 of 18, for ref, port and astc; the 720x720 fight ran once per build). A run started again after the last helper change (a 30 second limit on waiting for the window focus) is bit identical to the earlier ones.

What was tried and does not work: running `cmp-port` on a desktop GL context (no `gles_force.so`) to separate the context from the shader conversion. The converted programs then render black or garbage, so the ref against port difference stays a combined one.
