// Stand in libsteam_api.so for Shogun Showdown (Steamworks.NET). MIT license. Follows BinaryCounter's Papers, Please stub.
//
// Not a Steam emulator: no ownership, license or DRM check exists in the game or in this file.
// It provides only the Steam functions the game calls. The game's own code calls SteamAPI.Init,
// RestartAppIfNecessary, RunCallbacks, Shutdown, SetWarningMessageHook, IsSteamRunningOnSteamDeck,
// GetPersonaName (a debug log line), and GetAchievement, SetAchievement and StoreStats; the rest
// is what Steamworks.NET calls while starting up and running callbacks (found by logging every
// call on a full run).
//
// Init succeeds and the interface getters return a placeholder so Steamworks.NET considers Steam
// available (without that the game's first scene never loads). Everything else reports nothing:
// no callbacks, no achievements (none are stored), an empty player name.
#include <stdint.h>

typedef intptr_t ptr;
static uint64_t placeholder_vtable[64];
static struct { uint64_t *vtable; uint64_t pad[15]; } placeholder = { placeholder_vtable, {0} };
#define PLACEHOLDER(name) ptr name(void) { return (ptr)&placeholder; }
#define ZERO(name) ptr name(void) { return 0; }

// Startup and shutdown
ptr SteamAPI_Init(void) { return 1; }
ZERO(SteamAPI_RestartAppIfNecessary)
ZERO(SteamAPI_Shutdown)
ptr SteamAPI_GetHSteamUser(void) { return 1; }
ptr SteamAPI_GetHSteamPipe(void) { return 1; }

// Callbacks (manual dispatch): there never is one
ZERO(SteamAPI_ManualDispatch_Init)
ZERO(SteamAPI_ManualDispatch_RunFrame)
ZERO(SteamAPI_ManualDispatch_GetNextCallback)
ZERO(SteamAPI_ManualDispatch_FreeLastCallback)
ZERO(SteamAPI_ManualDispatch_GetAPICallResult)

// Interfaces
PLACEHOLDER(SteamInternal_CreateInterface)
PLACEHOLDER(SteamInternal_FindOrCreateUserInterface)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamAppList)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamApps)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamFriends)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamGameSearch)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamHTMLSurface)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamHTTP)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamInput)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamInventory)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamMatchmaking)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamMatchmakingServers)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamMusic)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamMusicRemote)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamNetworking)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamParentalSettings)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamParties)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamRemotePlay)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamRemoteStorage)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamScreenshots)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamUGC)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamUser)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamUserStats)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamUtils)
PLACEHOLDER(SteamAPI_ISteamClient_GetISteamVideo)
ZERO(SteamAPI_ISteamClient_SetWarningMessageHook)

// Calls from the game
ZERO(SteamAPI_ISteamUtils_IsSteamRunningOnSteamDeck)
ptr SteamAPI_ISteamFriends_GetPersonaName(void) { return (ptr)""; }
ptr SteamAPI_ISteamUserStats_GetAchievement(void *self, const char *name, uint8_t *achieved) {
  (void)self; (void)name;
  if (achieved) *achieved = 0;
  return 0;
}
ZERO(SteamAPI_ISteamUserStats_SetAchievement)
ZERO(SteamAPI_ISteamUserStats_StoreStats)
