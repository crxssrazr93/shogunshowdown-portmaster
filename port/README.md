## Installation

Buy the game on [Steam](https://store.steampowered.com/app/2084000/Shogun_Showdown/) and download the Linux build (Steam build 20620547) with the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244):

`download_depot 2084000 2084002 5092188064288801929`

Copy `ShogunShowdown.x86_64`, `UnityPlayer.so` and the `ShogunShowdown_Data` folder into `ports/shogunshowdown/gamedata/`. The first start patches your copy for the device (about a minute, again after a game update) and stops with a message if the build is a different one. If files are missing or damaged, copy the game files again: the next start patches them.

## Controls

The game reads the pad itself. Buttons are named as the game's prompts show them. They work by position, as SDL lays them out: A is the bottom button (labelled B on Anbernic devices). On Knulli you can swap them per game: long press X on the game in the ports list and change its A/B layout setting.

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

On 1 GB devices turn on zram (or swap) in your firmware's settings, so the game does not run out of memory.

Runs through box64 and Westonpack. Saves are in `conf/unity3d/Roboatino/ShogunShowdown/`. The picture is 16:9, so 4:3 screens show bars. The port scales the game's low resolution picture with sharp bilinear filtering, so its pixels stay even on screens that are not a whole multiple of it. On square screens the picture fills the width and the side panels move in; set `SHOGUN_ASPECT="fit"` in `shogunshowdown/shogunshowdown.cfg` for a 4:3 picture with black bars instead, where the panels cover nothing. The steam stub only lets the game start and contains no DRM checks.

Source and build instructions: https://github.com/crxssrazr93/shogunshowdown-portmaster

## Reporting problems

Please send `ports/shogunshowdown/log.txt`, `ports/shogunshowdown/setup_log.txt` and `player.log` (Unity's own log). `log.txt` is rewritten on every start and the run before it is kept as `log.prev.txt` (the setup log likewise), so send both if the game was started again after the problem. Lines starting with `PORT:` list the device, firmware, screen, memory and swap, the state of the setup, and at the end how long the game ran and whether the system ran out of memory.

## Thanks

Roboatino and Goblinz Publishing, ptitSeb (box64), binarycounter (Westonpack and the Papers, Please Steam stub this one follows), Knifethrower (Unity porting tools, glespass), Arm (astcenc), the PortMaster team.
