## Installation

Buy the game on [Steam](https://store.steampowered.com/app/2084000/Shogun_Showdown/) and download the Linux build (Steam build 20620547) with the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244):

`download_depot 2084000 2084002 5092188064288801929`

Copy `ShogunShowdown.x86_64`, `UnityPlayer.so` and the `ShogunShowdown_Data` folder into `ports/shogunshowdown/gamedata/`. The first start patches your copy for the device (about a minute, again after a game update) and stops with a message if the build is a different one.

## Controls

The game reads the pad itself. Buttons are named as the game's prompts show them. On Knulli they act as labelled on the device. Other firmwares use SDL's layout by position, where A is the bottom button (labelled B on Anbernic devices).

| Button | Action |
| :----- | :----- |
| L2 / R2 | Move left / right |
| Y | Turn around |
| X | Attack, hold on GO to start |
| A | Confirm |
| B | Wait a turn, back |
| R1 / Select | Info / Map |
| Start | Pause |
| Select + Start | Exit |

## Notes

Runs through box64 and Westonpack. Saves are in `conf/unity3d/Roboatino/ShogunShowdown/`. The picture is 16:9, so 4:3 screens show bars. The steam stub only lets the game start and contains no DRM checks.

Source and build instructions: https://github.com/crxssrazr93/shogunshowdown-portmaster

## Thanks

Roboatino and Goblinz Publishing, ptitSeb (box64), binarycounter (Westonpack and the Papers, Please Steam stub this one follows), Knifethrower (Unity porting tools, glespass), Arm (astcenc), the PortMaster team.
