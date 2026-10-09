# Shogun Showdown for PortMaster

A [PortMaster](https://portmaster.games/) port of [Shogun Showdown](https://store.steampowered.com/app/2084000/Shogun_Showdown/) (Roboatino, Goblinz Publishing, 2023), a turn based roguelike, for Linux handhelds with ARM64 CPUs.

The port runs the game's own x86_64 Linux build (Unity 2021.3). No game files are included: you supply them from your Steam copy, and the port adapts them on the device the first time it starts.

| | |
|--|--|
| Status | Runs on an Anbernic RG35XX H (Knulli, Mali G31, 1 GB): title, menus, camp, runs and fights work with the controller and sound. About 30 fps on the title screen and 18 fps in fights. Other devices untested. |
| Target | aarch64 PortMaster devices with an OpenGL ES 3 GPU that supports ASTC textures, 1 GB RAM or more |
| Runtimes | Westonpack (`weston_pkg_0.2`, crusty_glx), bundled box64 |
| Memory | about 640 MB for the game plus 190 MB of GPU memory in a fight on the device |
| Supported game version | Steam build 20620547 (depot 2084002, manifest 5092188064288801929) |

## For players

1. Buy the game on Steam.
2. Open the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244) and download the Linux build:
   ```
   download_depot 2084000 2084002 5092188064288801929
   ```
3. Copy everything from the download (`ShogunShowdown.x86_64`, `UnityPlayer.so` and the `ShogunShowdown_Data` folder) into `ports/shogunshowdown/gamedata/` on your device.
4. Start **Shogun Showdown** from the Ports menu. The first start shows PortMaster's patcher screen for about a minute while it adapts the game files.

Controls, notes and known limitations are in [port/README.md](port/README.md), the file that ships with the port.

## How it works

```
Shogun Showdown.sh (PortMaster launcher)
  ├ first start: PortMaster patcher → tools/patchscript
  │     xdelta patches (patch/, MD5 checked) → OpenGL ES 3 shaders, streamed audio
  │     tools/astc_textures.py + PortMaster's astcenc → large textures as ASTC 4x4
  └ westonwrap.sh headless noop kiosk crusty_glx   (Weston + Xwayland, GLX on OpenGL ES)
      └ box64                                       (x86_64 to aarch64 dynamic recompiler)
          └ ShogunShowdown.x86_64 + UnityPlayer.so (Unity 2021.3, Mono)
              ├ glespass/libGL.so.1                 GL calls straight to the GLES driver (aarch64)
              ├ box64/box64-x86_64-linux-gnu/       box64's x86_64 libgcc_s
              └ steamstub/libsteam_api.so           stand in for the Steam API (x86_64)
```

* **Graphics.** The Linux Unity player only accepts the OpenGLCore renderer, but its GL backend runs on an OpenGL ES 3.2 context. So every OpenGLCore shader program in the game's files is rewritten as GLSL ES 3.00 in place (`setup/gles_shaders2021.py`), and the player gets an ES context from Westonpack's crusty_glx. glespass, a pass through libGL from the Night in the Woods and Gone Home ports, hands the GL calls to the Mali driver unchanged and moves the EGL context to Unity's render thread.
* **Memory.** The game's sprites are uncompressed (about 250 MB on the GPU, which on these devices is ordinary RAM) and its music was decoded into RAM at start (about 450 MB). The port makes long clips stream (`setup/audio_loadtype.py`) and converts the large textures to ASTC 4x4 on the device, which looks the same at the game's pixel scale.
* **Steam.** The game needs the Steam API to start. The stub provides only the functions the game calls and makes no ownership checks.
* **Controls.** The player has an older SDL built in that numbers a pad's buttons differently from PortMaster's mapping; the launcher renumbers the mapping from the pad's key capabilities.

The full story, including what did not work and why, is in [docs/PORTING.md](docs/PORTING.md).

## Building

Everything the port ships that is not game data is built from source:

```
build/build.sh          # box64, glespass, the Steam stub (Docker, Ubuntu 20.04)
build/package.sh        # shogunshowdown.zip
```

The game file patches are made from an untouched copy of the supported Steam build. They are already in the repository; to regenerate them (for example for a new game version):

```
python3 -m venv venv && venv/bin/pip install -r setup/requirements.txt
PYTHON=venv/bin/python build/make_patches.sh <folder with ShogunShowdown_Data>
```

This writes `port/shogunshowdown/patch/*.xdelta`, `port/shogunshowdown/tools/astc_manifest.json` (file offsets and sizes, no game content) and the MD5s in `tools/patchscript`. Run on build 20620547 it reproduces the committed files byte for byte.

## Testing

* `tests/localtest.sh` runs the game on a PC the way the device does (OpenGL ES 3.2 context, handheld resolution, scripted virtual pad, bwrap with only that pad visible). Point `GAME_DIR` at a copy of the game with the setup applied.
* `tests/device/` has the scripts used on the RG35XX H test unit running Knulli: remote commands, screenshots from the framebuffer, button injection into the built in pad, a frame counter, a reliable stop, and `perf_run.sh` for frame rate comparisons.

## Licenses

The files written for this port are MIT licensed ([LICENSE](LICENSE)). box64 (MIT), libgcc_s (GPL with the GCC runtime library exception), glespass (MIT) and the vendored shader rewriter from Knifethrower's [PM-Porting-Tools](https://github.com/Knifethrower/PM-Porting-Tools) (0BSD) keep their own licenses; the port's copies are in `port/shogunshowdown/licenses/`. The game is not part of this repository.

## Thanks

Roboatino for Shogun Showdown, ptitSeb for [box64](https://github.com/ptitSeb/box64), binarycounter for [Westonpack](https://github.com/binarycounter/Westonpack/wiki), Knifethrower for the Unity porting tools and glespass, Arm for [astcenc](https://github.com/ARM-software/astc-encoder), and the PortMaster team.
