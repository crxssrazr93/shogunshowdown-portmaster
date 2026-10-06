This is not a Steam emulator, and it does not break, bypass or circumvent any DRM or license
check. Shogun Showdown makes no ownership checks, and this library implements none.

The game needs the Steam API to start: without Steam its first scene never loads (a black
screen), even with a steam_appid.txt, because it asks Steam whether it runs on a Steam Deck and
that call fails. This stand-in provides only the Steam functions the game calls: Steam starts,
there are never any callbacks, the player name is empty and achievements go nowhere. Every other
call returns 0.

The approach (a minimal libsteam_api.so that only lets the game start) follows BinaryCounter's
stub for Papers, Please.

You still need your own copy of the game from Steam; no game files are included in this port.

The source (steamstub.c) is included and MIT licensed (see licenses/LICENSE.shogunshowdown.txt).
Build: gcc -shared -fPIC -O2 -o libsteam_api.so steamstub.c
