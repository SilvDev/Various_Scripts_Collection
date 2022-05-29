/*
*	Lock Doors
*	Copyright (C) 2022 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION 		"1.6"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Lock Doors
*	Author	:	SilverShot
*	Descrp	:	Replicates an old feature Valve removed, allowing players to lock and unlock doors. Also sets open/closed/locked doors health.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=322899
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.6 (29-May-2022)
	- Added command "sm_lock_doors_health" to check a doors health.
	- Added cvar "l4d_lock_doors_random" to randomly open or close doors on round start.
	- Fixed the health not being consistently set correctly.
	- Fixed locking or unlocking from opening or closing the door.
	- Fixed issues with double doors not being handled together.
	- Change cvar "l4d_lock_doors_text" description and default value for hint messages printing to all instead of an individual client and vice versa.

	- Thanks to "gongo" for reporting issues and testing.
	- Thanks to "Toranks" for help testing.

1.5 (20-Jul-2021)
	- Blocked some door models that are missing the door knob animation. Thanks to "sonic155" for reporting.

1.4 (21-Jun-2021)
	- Added door handle animation and sound when attempting to open a locked door. Requested by "The Renegadist".

1.3 (18-Aug-2020)
	- Added cvar "l4d_lock_doors_range" to set the distance players must be to lock or unlock doors.

1.2 (10-May-2020)
	- Extra checks to prevent "IsAllowedGameMode" throwing errors.
	- Various changes to tidy up code.

1.1 (08-Apr-2020)
	- Changed the lock sound and increased volume.
	- Fixed server start or when the plugin was enabled again. Thanks to "Cuba" for reporting.

1.0 (07-Apr-2020)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define CVAR_FLAGS				FCVAR_NOTIFY
#define SOUND_LOCK				"doors/default_locked.wav" // door_lock_1
#define SOUND_LOCKED			"doors/latchlocked2.wav"
#define SOUND_UNLOCK			"doors/door_latch3.wav"

#define DOOR_FLAG_IGNORE_USE	32768
#define DEBUG_PRINT				0

// Testing: l4d_lock_doors_health_open 1.0; l4d_lock_doors_health_shut 2.0; l4d_lock_doors_health_lock 3.0;

enum // m_eDoorState
{
	DOOR_STATE_CLOSED,
	DOOR_STATE_OPENING_IN_PROGRESS,
	DOOR_STATE_OPENED,
	DOOR_STATE_CLOSING_IN_PROGRESS
}


ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarHealthL, g_hCvarHealthO, g_hCvarHealthS, g_hCvarHealthT, g_hCvarKeys, g_hCvarRandom, g_hCvarRange, g_hCvarText, g_hCvarVoca;
float g_fCvarHealthL, g_fCvarHealthO, g_fCvarHealthS, g_fCvarRange;
int g_iCvarKeys, g_iCvarRandom, g_iCvarText, g_iCvarVoca, g_iCvarHealthT;

bool g_bCvarAllow, g_bMapStarted, g_bLeft4Dead2;
float g_fLastUse[MAXPLAYERS+1], g_fLastPrint;
int g_iDoors[2048];
int g_iFlags[2048];
int g_iRelative[2048];


// Vocalize for Left 4 Dead 2
static const char g_Coach[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoor06", "closethedoorc101", "closethedoorc102"
};
static const char g_Ellis[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoorc101", "closethedoorc102"
};
static const char g_Nick[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoor06", "closethedoor07", "closethedoor08", "closethedoor09", "closethedoorc101", "closethedoorc102"
};
static const char g_Rochelle[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoorc101", "closethedoorc102", "closethedoorc103", "closethedoorc104", "closethedoorc105"
};

// Vocalize for Left 4 Dead
static const char g_Bill[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoor06", "closethedoor07", "closethedoor08", "closethedoor09", "closethedoor10", "closethedoor11", "closethedoor12", "closethedoor13"
};
static const char g_Francis[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoor06", "closethedoor07", "closethedoor08", "closethedoor09", "closethedoor10", "closethedoor11", "closethedoor12"
};
static const char g_Louis[][] =
{
	"closethedoor01", "closethedoor02", "closethedoor03", "closethedoor04", "closethedoor05", "closethedoor06", "closethedoor07"
};
static const char g_Zoey[][] =
{
	"closethedoor01", "closethedoor07", "closethedoor08", "closethedoor11", "closethedoor16", "closethedoor17", "closethedoor19", "closethedoor22", "closethedoor28", "closethedoor29", "closethedoor33", "closethedoor41", "closethedoor42", "closethedoor45", "closethedoor50"
};



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Lock Doors",
	author = "SilverShot",
	description = "Replicates an old feature Valve removed, allowing players to lock and unlock doors. Also sets open/closed/locked doors health.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=322899"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();

	if( test == Engine_Left4Dead ) g_bLeft4Dead2 = false;
	else if( test == Engine_Left4Dead2 ) g_bLeft4Dead2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hCvarAllow =		CreateConVar("l4d_lock_doors_allow",			"1",				"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes =		CreateConVar("l4d_lock_doors_modes",			"",					"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff =	CreateConVar("l4d_lock_doors_modes_off",		"",					"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog =	CreateConVar("l4d_lock_doors_modes_tog",		"0",				"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarHealthL =	CreateConVar("l4d_lock_doors_health_lock",		"2.0",				"0=Off. Percentage of health to set when the door is locked.", CVAR_FLAGS );
	g_hCvarHealthO =	CreateConVar("l4d_lock_doors_health_open",		"0.5",				"0=Off. Percentage of health to set when the door is open.", CVAR_FLAGS );
	g_hCvarHealthS =	CreateConVar("l4d_lock_doors_health_shut",		"1.0",				"0=Off. Percentage of health to set when the door is shut.", CVAR_FLAGS );
	g_hCvarHealthT =	CreateConVar("l4d_lock_doors_health_total",		"840",				"0=Off. How much health doors have on spawn (840 game default).", CVAR_FLAGS );
	g_hCvarKeys =		CreateConVar("l4d_lock_doors_keys",				"1",				"Which key combination to lock/unlock doors: 1=Shift (walk) + E (use). 2=Ctrl (duck) + E (use).", CVAR_FLAGS );
	g_hCvarRandom =		CreateConVar("l4d_lock_doors_random",			"0",				"0=Off. On round start the chance out of 100 to randomly open a closed door, or close an open door.", CVAR_FLAGS );
	g_hCvarRange =		CreateConVar("l4d_lock_doors_range",			"150",				"0=Any distance. How close a player must be to the door they're trying to lock or unlock.", CVAR_FLAGS );
	g_hCvarText =		CreateConVar("l4d_lock_doors_text",				"11",				"0=Off. Display a chat message when: 1=Locking doors. 2=Unlocking doors. 4=To all players. 8=To self. Add numbers together.", CVAR_FLAGS );
	g_hCvarVoca =		CreateConVar("l4d_lock_doors_vocalize",			"1",				"0=Off. 1=-Vocalize when locking doors.", CVAR_FLAGS );
	CreateConVar(					"l4d_lock_doors_version",			PLUGIN_VERSION,		"Lock Doors plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,			"l4d_lock_doors");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarHealthL.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarHealthO.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarHealthS.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarHealthT.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarKeys.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarText.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarRandom.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarRange.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarVoca.AddChangeHook(ConVarChanged_Cvars);

	RegAdminCmd("sm_lock_doors_health", CmdHealth, ADMFLAG_ROOT, "Returns the health of the door you're aiming at.");
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
}

void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_fCvarHealthL = g_hCvarHealthL.FloatValue;
	g_fCvarHealthO = g_hCvarHealthO.FloatValue;
	g_fCvarHealthS = g_hCvarHealthS.FloatValue;
	g_iCvarHealthT = g_hCvarHealthT.IntValue;
	g_iCvarKeys = g_hCvarKeys.IntValue;
	g_iCvarText = g_hCvarText.IntValue;
	g_iCvarRandom = g_hCvarRandom.IntValue;
	g_fCvarRange = g_hCvarRange.FloatValue;
	g_iCvarVoca = g_hCvarVoca.IntValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		g_bCvarAllow = true;

		ResetPlugin();
		SearchForDoors();

		HookEvent("round_start",	Event_RoundStart);
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		g_bCvarAllow = false;

		UnhookEvent("round_start",	Event_RoundStart);
	}
}

int g_iCurrentMode;
bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == null )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog != 0 )
	{
		if( g_bMapStarted == false )
			return false;

		g_iCurrentMode = 0;

		int entity = CreateEntityByName("info_gamemode");
		if( IsValidEntity(entity) )
		{
			DispatchSpawn(entity);
			HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
			ActivateEntity(entity);
			AcceptEntityInput(entity, "PostSpawnActivate");
			if( IsValidEntity(entity) ) // Because sometimes "PostSpawnActivate" seems to kill the ent.
				RemoveEdict(entity); // Because multiple plugins creating at once, avoid too many duplicate ents in the same frame
		}

		if( g_iCurrentMode == 0 )
			return false;

		if( !(iCvarModesTog & g_iCurrentMode) )
			return false;
	}

	char sGameModes[64], sGameMode[64];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	Format(sGameMode, sizeof(sGameMode), ",%s,", sGameMode);

	g_hCvarModes.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) == -1 )
			return false;
	}

	g_hCvarModesOff.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) != -1 )
			return false;
	}

	return true;
}

void OnGamemode(const char[] output, int caller, int activator, float delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
	else if( strcmp(output, "OnScavenge") == 0 )
		g_iCurrentMode = 8;
}



// ====================================================================================================
//					DOOR STUFF
// ====================================================================================================
Action CmdHealth(int client, int args)
{
	if( client )
	{
		int entity = GetClientAimTarget(client, false);
		if( entity != -1 )
		{
			char sTemp[32];
			GetEdictClassname(entity, sTemp, sizeof(sTemp));
			if( strcmp(sTemp, "prop_door_rotating") == 0 )
			{
				ReplyToCommand(client, "Door %d health = %d", entity, GetEntProp(entity, Prop_Data, "m_iHealth"));
				return Plugin_Handled;
			}
		}
	} else {
		ReplyToCommand(client, "Command can only be used %s", IsDedicatedServer() ? "in game on a dedicated server." : "in chat on a Listen server.");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "Invalid door or no entity.");

	return Plugin_Handled;
}

void SearchForDoors()
{
	char sTarget[128];
	int entity = -1;

	while( (entity = FindEntityByClassname(entity, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
	{
		if( GetEntProp(entity, Prop_Data, "m_bLocked") == 0 )
		{
			g_iDoors[entity] = EntIndexToEntRef(entity);

			// Hooks
			HookSingleEntityOutput(entity, "OnFullyOpen", Door_Moved);
			HookSingleEntityOutput(entity, "OnFullyClosed", Door_Moved);

			g_iFlags[entity] = -1;

			// Health
			SetDoorHealth(entity, true);

			// Find double doors
			MatchRelatives(entity);

			if( g_iCvarRandom )
			{
				if( GetRandomInt(1, 100) <= g_iCvarRandom )
				{
					if( GetEntProp(entity, Prop_Data, "m_eDoorState") == DOOR_STATE_OPENED )
					{
						AcceptEntityInput(entity, "Close");
					}
					else if( GetEntProp(entity, Prop_Data, "m_eDoorState") == DOOR_STATE_CLOSED )
					{
						GetEntPropString(entity, Prop_Data, "m_iName", sTarget, sizeof(sTarget));
						SetVariantString(sTarget);
						AcceptEntityInput(entity, "OpenAwayFrom"); // Support for double doors and doors opening in the correct direction
					}
				}
			}
		}
	}
}

void SetDoorHealth(int entity, bool spawned = false)
{
	if( spawned )
	{
		int health = g_iCvarHealthT ? g_iCvarHealthT : GetEntProp(entity, Prop_Data, "m_iHealth");

		int state = GetEntProp(entity, Prop_Data, "m_eDoorState");
		if( (state == DOOR_STATE_CLOSED || state == DOOR_STATE_CLOSING_IN_PROGRESS) && g_fCvarHealthS )				SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthS)); // Closed
		else if( (state == DOOR_STATE_OPENED || state == DOOR_STATE_OPENING_IN_PROGRESS) && g_fCvarHealthO )		SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthO)); // Opened

		#if DEBUG_PRINT
		PrintToChatAll("SPAWNED: (%d) %s %d > %d", entity, state == 0 ? "CLOSED" : "OPENED", health, GetEntProp(entity, Prop_Data, "m_iHealth"));
		PrintToServer("SPAWNED: (%d) %s %d > %d", entity, state == 0 ? "CLOSED" : "OPENED", health, GetEntProp(entity, Prop_Data, "m_iHealth"));
		#endif
	}
	else if( g_fCvarHealthO || g_fCvarHealthS )
	{
		int health = GetEntProp(entity, Prop_Data, "m_iHealth");
		int state = GetEntProp(entity, Prop_Data, "m_eDoorState");

		if( (state == DOOR_STATE_CLOSED || state == DOOR_STATE_CLOSING_IN_PROGRESS) && g_fCvarHealthS )				SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthS / (g_fCvarHealthO ? g_fCvarHealthO : 1.0))); // Closed
		else if( (state == DOOR_STATE_OPENED || state == DOOR_STATE_OPENING_IN_PROGRESS) && g_fCvarHealthO )		SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthO / (g_fCvarHealthS ? g_fCvarHealthS : 1.0))); // Opened

		#if DEBUG_PRINT
		PrintToChatAll("%s (%d) %d > %d", state == 0 ? "CLOSED" : "OPENED", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
		PrintToServer("%s (%d) %d > %d", state == 0 ? "CLOSED" : "OPENED", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
		#endif
	}

	if( g_iFlags[entity] == -1 )
	{
		g_iFlags[entity] = GetEntProp(entity, Prop_Send, "m_spawnflags");
		SetEntProp(entity, Prop_Send, "m_spawnflags", DOOR_FLAG_IGNORE_USE); // Prevent +USE
		CreateTimer(0.2, TimerDoorSet, EntIndexToEntRef(entity));
	}
}

Action TimerDoorSet(Handle timer, any entity)
{
	entity = EntRefToEntIndex(entity);
	if( entity != INVALID_ENT_REFERENCE )
	{
		SetEntProp(entity, Prop_Send, "m_spawnflags", g_iFlags[entity]);
		g_iFlags[entity] = -1;
	}
}

void Door_Moved(const char[] output, int caller, int activator, float delay)
{
	SetDoorHealth(caller);
}

void MatchRelatives(int entity)
{
	static char sTemp[128], sTarget[128];
	GetEntPropString(entity, Prop_Data, "m_SlaveName", sTemp, sizeof(sTemp));

	int target = -1;

	if( sTemp[0] != 0 )
	{
		while( (target = FindEntityByClassname(target, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
		{
			GetEntPropString(target, Prop_Data, "m_iName", sTarget, sizeof(sTarget));
			if( strcmp(sTemp, sTarget) == 0 )
			{
				g_iRelative[target] = EntIndexToEntRef(entity);
				g_iRelative[entity] = EntIndexToEntRef(target);
				return;
			}
		}
	}
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
public void OnEntityCreated(int entity, const char[] classname)
{
	if( g_bCvarAllow && strcmp(classname, "prop_door_rotating") == 0 )
	{
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost);
	}
}

void SpawnPost(int entity)
{
	if( GetEntProp(entity, Prop_Data, "m_bLocked") == 0 )
	{
		g_iDoors[entity] = EntIndexToEntRef(entity);

		// Hooks
		HookSingleEntityOutput(entity, "OnFullyOpen", Door_Moved);
		HookSingleEntityOutput(entity, "OnFullyClosed", Door_Moved);

		g_iFlags[entity] = -1;

		// Health
		SetDoorHealth(entity, true);

		// Find double doors
		MatchRelatives(entity);
	}
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetPlugin();
}

public void OnMapStart()
{
	g_bMapStarted = true;

	PrecacheSound(SOUND_LOCK);
	PrecacheSound(SOUND_LOCKED);
	PrecacheSound(SOUND_UNLOCK);
}

public void OnMapEnd()
{
	g_bMapStarted = false;

	ResetPlugin();
}

void ResetPlugin()
{
	g_fLastPrint = 0.0;

	for( int i = 0; i <= MaxClients; i++ )
	{
		g_fLastUse[i] = 0.0;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if( g_bCvarAllow && buttons & IN_USE && GetGameTime() > g_fLastUse[client] )
	{
		if( GetClientTeam(client) == 2 && IsPlayerAlive(client) )
		{
			int entity = GetClientAimTarget(client, false);
			if( entity > MaxClients && g_iDoors[entity] == EntIndexToEntRef(entity) )
			{
				// Door not rotating
				if( GetEntProp(entity, Prop_Data, "m_eDoorState") == DOOR_STATE_CLOSED )
				{
					// Range text
					if( g_fCvarRange )
					{
						float vPos[3], vEnd[3];
						GetClientAbsOrigin(client, vPos);
						GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vEnd);
						if( GetVectorDistance(vPos, vEnd) > g_fCvarRange ) return Plugin_Continue;
					}

					// Door locked
					if( GetEntProp(entity, Prop_Data, "m_bLocked") )
					{
						// Attempting to lock/unlock
						if( ((g_iCvarKeys == 1 && buttons & IN_SPEED) || (g_iCvarKeys == 2 && buttons & IN_DUCK)) )
						{
							// Text
							if( g_iCvarText & 2 )
							{
								if( g_fLastPrint != GetGameTime() )
								{
									g_fLastPrint = GetGameTime();
									if( g_iCvarText & 4 )			PrintToChatAll("\x04%N \x01unlocked a door", client);
									else if( g_iCvarText & 8 )		PrintToChat(client, "\x04%N \x01unlocked a door", client);
								}
							}

							// Sound
							PlaySound(entity, 2);

							// Relative
							int target = g_iRelative[entity];
							if( target && (target = EntRefToEntIndex(target)) != INVALID_ENT_REFERENCE )
							{
								// Action
								AcceptEntityInput(target, "InputUnlock");
								SetEntProp(target, Prop_Data, "m_bLocked", 0);
								ChangeEdictState(target, 0);

								// Health
								int health = GetEntProp(target, Prop_Data, "m_iHealth");
								SetEntProp(target, Prop_Data, "m_iHealth", RoundFloat(health / g_fCvarHealthL)); // Divide by locked health

								#if DEBUG_PRINT
								PrintToChatAll("UNLOCK RELATIVE (%d) %d > %d", target, health, GetEntProp(target, Prop_Data, "m_iHealth"));
								PrintToServer("UNLOCK RELATIVE (%d) %d > %d", target, health, GetEntProp(target, Prop_Data, "m_iHealth"));
								#endif

								// Prevent opening
								if( g_iFlags[target] == -1 )
								{
									g_iFlags[target] = GetEntProp(target, Prop_Send, "m_spawnflags");
									SetEntProp(target, Prop_Send, "m_spawnflags", DOOR_FLAG_IGNORE_USE); // Prevent +USE
									CreateTimer(0.2, TimerDoorSet, EntIndexToEntRef(target));
								}
							}

							// Action
							AcceptEntityInput(entity, "InputUnlock");
							SetEntProp(entity, Prop_Data, "m_bLocked", 0);
							ChangeEdictState(entity, 0);

							// Health
							int health = GetEntProp(entity, Prop_Data, "m_iHealth");
							SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health / g_fCvarHealthL)); // Divide by locked health

							#if DEBUG_PRINT
							PrintToChatAll("UNLOCK (%d) %d > %d", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
							PrintToServer("UNLOCK (%d) %d > %d", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
							#endif

							// Prevent opening
							if( g_iFlags[entity] == -1 )
							{
								g_iFlags[entity] = GetEntProp(entity, Prop_Send, "m_spawnflags");
								SetEntProp(entity, Prop_Send, "m_spawnflags", DOOR_FLAG_IGNORE_USE); // Prevent +USE
								CreateTimer(0.2, TimerDoorSet, EntIndexToEntRef(entity));
							}

							// RequestFrame(OnOpen, EntIndexToEntRef(entity));
						// Pressing use, attempting to open a locked door
						} else {
							PlaySound(entity, 3);

							g_fLastUse[client] = GetGameTime() + 0.3;

							static char model[64];
							GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));

							// These doors have no animation
							if(	strcmp(model, "models/props_downtown/metal_door_112.mdl") &&
								strncmp(model, "models/props_doors/shack", 24) &&
								strcmp(model, "models/props_downtown/door_interior_112_01.mdl")
							)
							{
								SetVariantString("KnobTurnFail");
								AcceptEntityInput(entity, "SetAnimation");
							}

							return Plugin_Continue;
						}
					}
					// Not locked
					else
					{
						if( ((g_iCvarKeys == 1 && buttons & IN_SPEED) || (g_iCvarKeys == 2 && buttons & IN_DUCK)) )
						{
							// Text
							if( g_iCvarText & 1 )
							{
								if( g_fLastPrint != GetGameTime() )
								{
									g_fLastPrint = GetGameTime();
									if( g_iCvarText & 4 )			PrintToChatAll("\x04%N \x01locked a door", client);
									else if( g_iCvarText & 8 )		PrintToChat(client, "\x043%N \x01locked a door", client);
								}
							}

							// Sound, vocalize
							if( g_iCvarVoca )
							{
								PlayVocalize(client);
							}

							PlaySound(entity, 1);

							// Relative
							int target = g_iRelative[entity];
							if( target && (target = EntRefToEntIndex(target)) != INVALID_ENT_REFERENCE )
							{
								// Action
								AcceptEntityInput(target, "InputLock");
								SetEntProp(target, Prop_Data, "m_bLocked", 1);
								ChangeEdictState(target, 0);

								// Health
								int health = GetEntProp(target, Prop_Data, "m_iHealth");
								SetEntProp(target, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthL));

								#if DEBUG_PRINT
								PrintToChatAll("LOCK RELATIVE (%d) %d > %d", target, health, GetEntProp(target, Prop_Data, "m_iHealth"));
								PrintToServer("LOCK RELATIVE (%d) %d > %d", target, health, GetEntProp(target, Prop_Data, "m_iHealth"));
								#endif

								// Prevent opening
								if( g_iFlags[target] == -1 )
								{
									g_iFlags[target] = GetEntProp(target, Prop_Send, "m_spawnflags");
									SetEntProp(target, Prop_Send, "m_spawnflags", DOOR_FLAG_IGNORE_USE); // Prevent +USE
									CreateTimer(0.2, TimerDoorSet, EntIndexToEntRef(target));
								}
							}

							// Action
							AcceptEntityInput(entity, "InputLock");
							SetEntProp(entity, Prop_Data, "m_bLocked", 1);
							ChangeEdictState(entity, 0);

							// Health
							int health = GetEntProp(entity, Prop_Data, "m_iHealth");
							SetEntProp(entity, Prop_Data, "m_iHealth", RoundFloat(health * g_fCvarHealthL));

							#if DEBUG_PRINT
							PrintToChatAll("LOCK (%d) %d > %d", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
							PrintToServer("LOCK (%d) %d > %d", entity, health, GetEntProp(entity, Prop_Data, "m_iHealth"));
							#endif

							// Prevent opening
							if( g_iFlags[entity] == -1 )
							{
								g_iFlags[entity] = GetEntProp(entity, Prop_Send, "m_spawnflags");
								SetEntProp(entity, Prop_Send, "m_spawnflags", DOOR_FLAG_IGNORE_USE); // Prevent +USE
								CreateTimer(0.2, TimerDoorSet, EntIndexToEntRef(entity));
							}
						}
					}
				}
			}
		}

		g_fLastUse[client] = GetGameTime() + 0.3; // Avoid spamming resources
	}

	return Plugin_Continue;
}

void PlaySound(int entity, int type)
{
	EmitSoundToAll(type == 1 ? SOUND_LOCK : type == 2 ? SOUND_UNLOCK : SOUND_LOCKED, entity, SNDCHAN_AUTO, type == 1 ? SNDLEVEL_AIRCRAFT : SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
}



// ====================================================================================================
//					VOCALIZE SCENE
// ====================================================================================================
void PlayVocalize(int client)
{
	// Declare variables
	int surv, max;
	static char model[40];

	// Get survivor model
	GetEntPropString(client, Prop_Data, "m_ModelName", model, sizeof(model));

	switch( model[29] )
	{
		case 'c': { Format(model, sizeof(model), "coach");		surv = 1; }
		case 'b': { Format(model, sizeof(model), "gambler");	surv = 2; }
		case 'h': { Format(model, sizeof(model), "mechanic");	surv = 3; }
		case 'd': { Format(model, sizeof(model), "producer");	surv = 4; }
		case 'v': { Format(model, sizeof(model), "NamVet");		surv = 5; }
		case 'e': { Format(model, sizeof(model), "Biker");		surv = 6; }
		case 'a': { Format(model, sizeof(model), "Manager");	surv = 7; }
		case 'n': { Format(model, sizeof(model), "TeenGirl");	surv = 8; }
		default:
		{
			int character = GetEntProp(client, Prop_Send, "m_survivorCharacter");

			if( g_bLeft4Dead2 )
			{
				switch( character )
				{
					case 0:	{ Format(model, sizeof(model), "gambler");		surv = 2; } // Nick
					case 1:	{ Format(model, sizeof(model), "producer");		surv = 4; } // Rochelle
					case 2:	{ Format(model, sizeof(model), "coach");		surv = 1; } // Coach
					case 3:	{ Format(model, sizeof(model), "mechanic");		surv = 3; } // Ellis
					case 4:	{ Format(model, sizeof(model), "NamVet");		surv = 5; } // Bill
					case 5:	{ Format(model, sizeof(model), "TeenGirl");		surv = 8; } // Zoey
					case 6:	{ Format(model, sizeof(model), "Biker");		surv = 6; } // Francis
					case 7:	{ Format(model, sizeof(model), "Manager");		surv = 7; } // Louis
				}
			} else {
				switch( character )
				{
					case 0:	 { Format(model, sizeof(model) ,"TeenGirl");	surv = 8; } // Zoey
					case 1:	 { Format(model, sizeof(model) ,"NamVet");		surv = 5; } // Bill
					case 2:	 { Format(model, sizeof(model) ,"Biker");		surv = 6; } // Francis
					case 3:	 { Format(model, sizeof(model) ,"Manager");		surv = 7; } // Louis
				}
			}
		}
	}

	// Failed for some reason? Should never happen.
	if( surv == 0 )
		return;

	// Lock
	switch( surv )
	{
		case 1: max = sizeof(g_Coach);		// Coach
		case 2: max = sizeof(g_Nick);		// Nick
		case 3: max = sizeof(g_Ellis);		// Ellis
		case 4: max = sizeof(g_Rochelle);	// Rochelle
		case 5: max = sizeof(g_Bill);		// Bill
		case 6: max = sizeof(g_Francis);	// Francis
		case 7: max = sizeof(g_Louis);		// Louis
		case 8: max = sizeof(g_Zoey);		// Zoey
	}

	// Random number
	int random = GetRandomInt(0, max - 1);

	// Select random vocalize
	static char sTemp[40];
	switch( surv )
	{
		case 1: Format(sTemp, sizeof(sTemp), g_Coach[random]);
		case 2: Format(sTemp, sizeof(sTemp), g_Nick[random]);
		case 3: Format(sTemp, sizeof(sTemp), g_Ellis[random]);
		case 4: Format(sTemp, sizeof(sTemp), g_Rochelle[random]);
		case 5: Format(sTemp, sizeof(sTemp), g_Bill[random]);
		case 6: Format(sTemp, sizeof(sTemp), g_Francis[random]);
		case 7: Format(sTemp, sizeof(sTemp), g_Louis[random]);
		case 8: Format(sTemp, sizeof(sTemp), g_Zoey[random]);
	}

	// Create scene location and call
	Format(sTemp, sizeof(sTemp), "scenes/%s/%s.vcd", model, sTemp);
	VocalizeScene(client, sTemp);
}

// Taken from:
// [Tech Demo] L4D2 Vocalize ANYTHING
// https://forums.alliedmods.net/showthread.php?t=122270
// author = "AtomicStryker"
void VocalizeScene(int client, const char[] scenefile)
{
	int entity = CreateEntityByName("instanced_scripted_scene");
	DispatchKeyValue(entity, "SceneFile", scenefile);
	DispatchSpawn(entity);
	SetEntPropEnt(entity, Prop_Data, "m_hOwner", client);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start", client, client);
}
