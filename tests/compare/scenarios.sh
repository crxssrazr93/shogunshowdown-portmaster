# Scenarios for run_capture.sh (and the device launcher): sets FRAMES (PORTCAP_FRAMES) and INPUT
# (PORTCAP_INPUT). Both are "scene:frame:action" lists keyed by the frames since a scene loaded.
# A scene that loads a second time is called <name>#2 (PortCapture.cs): "Skip tutorial" in the pause
# menu goes ResetGameState, GameInitialization, then Combat again, which is Combat#2 here.
#
# The game's controls on the virtual pad (GamepadA scheme): RT/LT move right/left, Y turns around,
# A picks the selected tile into the attack queue (or interacts), X attacks (a tap in fights, a
# hold of about a second to press the camp's GO button), D-pad navigates, START pauses.
# Menu steps are spaced 50 to 60 frames apart so the animations of the previous step are over.
#
# Fresh home (no save): the first run is the tutorial.
#   fight     title, skip the tutorial, camp, hero selection, map, the first fight (about 1700 frames)
#   hub       title, skip the tutorial, camp: archive quests and the shop (about 700 frames)
#   tutorial  title, the tutorial lessons through its first enemy fight (about 3400 frames)
scenario() {
  local skip="TitleScreen:120:A;TitleScreen:270:A;Combat:150:START;Combat:200:DDOWN;Combat:250:A"
  case "$1" in
    fight)
      FRAMES="TitleScreen:60,200;Combat:60,180;Combat#2:100,240,330,360,420,540,660,720,780,860,910,960,1010,1060,1160,1260,1360,1460,1560,1700"
      INPUT="$skip;Combat#2:90:RT;Combat#2:150:RT;Combat#2:300:+X;Combat#2:480:-X;Combat#2:600:A"
      INPUT="$INPUT;Combat#2:780:RT;Combat#2:840:A;Combat#2:900:A;Combat#2:960:X;Combat#2:1080:RT;Combat#2:1140:A;Combat#2:1200:A;Combat#2:1260:X"
      INPUT="$INPUT;Combat#2:1380:LT;Combat#2:1440:A;Combat#2:1500:A;Combat#2:1560:X";;
    hub)
      FRAMES="TitleScreen:200;Combat:180;Combat#2:60,120,150,240,330,420,500,600,700"
      INPUT="$skip;Combat#2:90:LT;Combat#2:150:LT;Combat#2:240:A;Combat#2:400:DRIGHT;Combat#2:520:DRIGHT;Combat#2:640:DLEFT";;
    tutorial)
      FRAMES="TitleScreen:200;Combat:60,150,300,560,770,1000,1230,1580,1900,2200,2480,2700,2750,3000,3200,3350,3500"
      INPUT="TitleScreen:120:A;TitleScreen:270:A;Combat:200:RT;Combat:260:RT;Combat:320:RT;Combat:380:LT;Combat:440:LT;Combat:500:Y"
      INPUT="$INPUT;Combat:560:LT;Combat:600:LT;Combat:640:LT;Combat:700:A;Combat:740:A;Combat:780:X;Combat:830:X"
      INPUT="$INPUT;Combat:880:RT;Combat:920:RT;Combat:960:RT;Combat:1000:RT;Combat:1040:RT;Combat:1100:A;Combat:1160:A;Combat:1220:X;Combat:1280:X"
      INPUT="$INPUT;Combat:1340:LT;Combat:1380:LT;Combat:1420:LT;Combat:1460:LT;Combat:1560:RB;Combat:1620:DRIGHT;Combat:1680:DLEFT;Combat:1740:RB"
      INPUT="$INPUT;Combat:1800:RT;Combat:1860:RT;Combat:1920:RT;Combat:1980:RT;Combat:2040:A;Combat:2100:A;Combat:2160:X"
      INPUT="$INPUT;Combat:2260:RT;Combat:2320:A;Combat:2380:A;Combat:2440:X;Combat:2540:LT;Combat:2600:X"
      INPUT="$INPUT;Combat:2660:RT;Combat:2720:RT;Combat:2780:RT;Combat:2840:RT;Combat:2960:A;Combat:3020:A;Combat:3080:X;Combat:3200:A;Combat:3260:A;Combat:3320:X";;
    probe) FRAMES="TitleScreen:300,600,900,1200"; INPUT="";;
    *) return 1;;
  esac
}
