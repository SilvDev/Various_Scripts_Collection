/*
*	Door Barricades
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



#define PLUGIN_VERSION 		"1.0"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Door Barricades
*	Author	:	SilverShot
*	Descrp	:	Allows Survivors to create Barricades on broken doorways.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=338036
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.0 (01-June-2022)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define CVAR_FLAGS			FCVAR_NOTIFY
#define MODEL_PLANK1		"models/props_debris/wood_board04a.mdl"
#define MODEL_PLANK2		"models/props_debris/wood_board05a.mdl"
#define SOUND_HAMMER1		"physics/wood/wood_box_impact_bullet1.wav"
#define SOUND_HAMMER2		"physics/wood/wood_box_impact_hard4.wav"
#define SOUND_HAMMER3		"physics/wood/wood_box_impact_hard5.wav"
// #define SOUND_HAMMER1		"weapons/tonfa/tonfa_impact_world1.wav" // L4D2 sound
// #define SOUND_HAMMER2		"weapons/tonfa/tonfa_impact_world2.wav" // L4D2 sound


// Thanks to "Dragokas":
enum // m_eDoorState
{
	DOOR_STATE_CLOSED,
	DOOR_STATE_OPENING_IN_PROGRESS,
	DOOR_STATE_OPENED,
	DOOR_STATE_CLOSING_IN_PROGRESS
}

enum
{
	TYPE_COMMON,
	TYPE_INFECTED,
	TYPE_SURVIVOR,
	TYPE_TANK,
}

ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarDamageC, g_hCvarDamageI, g_hCvarDamageS, g_hCvarDamageT, g_hCvarHealth, g_hCvarRange, g_hCvarTime, g_hCvarTimePress, g_hCvarTimeWait;
int g_iCvarDamageC, g_iCvarDamageI, g_iCvarDamageS, g_iCvarDamageT, g_iCvarHealth;
float g_fCvarRange, g_fCvarTime, g_fCvarTimeWait, g_fCvarTimePress;
bool g_bCvarAllow, g_bMapStarted;

int g_iBarricade[2048][4];
int g_iRelative[2048];
int g_iRelIndex[2048];
int g_iDoors[2048];
float g_vAng[2048][3];
float g_vPos[2048][3];
float g_fPressing[MAXPLAYERS+1];
float g_fTimeout[MAXPLAYERS+1];
float g_fTimePress[MAXPLAYERS+1];
float g_fTimeSound[MAXPLAYERS+1];
int g_iPressing[MAXPLAYERS+1];
bool g_bLeft4Dead2;



// ====================================================================================================
//					PLUGIN START
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Door Barricades",
	author = "SilverShot",
	description = "Allows Survivors to create Barricades on broken doorways.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=338036"
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
	// Cvars
	g_hCvarAllow =		CreateConVar(	"l4d_door_barricade_allow",				"1",				"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes =		CreateConVar(	"l4d_door_barricade_modes",				"",					"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff =	CreateConVar(	"l4d_door_barricade_modes_off",			"",					"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog =	CreateConVar(	"l4d_door_barricade_modes_tog",			"0",				"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarDamageC =	CreateConVar(	"l4d_door_barricade_damage_common",		"250",				"0=Default game damage. Amount of damage to cause to planks when shoved by a Common Infected.", CVAR_FLAGS );
	g_hCvarDamageI =	CreateConVar(	"l4d_door_barricade_damage_infected",	"250",				"0=Default game damage. Amount of damage to cause to planks when shoved by a Special Infected.", CVAR_FLAGS );
	g_hCvarDamageS =	CreateConVar(	"l4d_door_barricade_damage_survivor",	"250",				"0=Default game damage. Amount of damage to cause to planks when shoved by a Survivor.", CVAR_FLAGS );
	g_hCvarDamageT =	CreateConVar(	"l4d_door_barricade_damage_tank",		"0",				"0=Default game damage. Amount of damage to cause to planks when shoved by a Tank.", CVAR_FLAGS );
	g_hCvarHealth =		CreateConVar(	"l4d_door_barricade_health",			"500",				"Health of each plank.", CVAR_FLAGS );
	g_hCvarRange =		CreateConVar(	"l4d_door_barricade_range",				"100.0",			"Range required by Survivors to an open doorway to create planks. Large values may affect other nearby doorways.", CVAR_FLAGS );
	g_hCvarTime =		CreateConVar(	"l4d_door_barricade_time",				"5.0",				"How long does it take to build 1 plank.", CVAR_FLAGS );
	g_hCvarTimePress =	CreateConVar(	"l4d_door_barricade_time_press",		"0.3",				"How long must someone be holding +USE before building starts.", CVAR_FLAGS );
	g_hCvarTimeWait =	CreateConVar(	"l4d_door_barricade_time_wait",			"0.5",				"How long after building a plank to make the player wait until they can build again.", CVAR_FLAGS );
	CreateConVar(						"l4d_door_barricade_version",			PLUGIN_VERSION,		"Door Barricades plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,				"l4d_door_barricade");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarDamageC.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarDamageI.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarDamageS.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarDamageT.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarHealth.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarRange.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTime.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTimePress.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTimeWait.AddChangeHook(ConVarChanged_Cvars);

	// Commands
	if( g_bLeft4Dead2 && CommandExists("sm_doors_glow") == false )
	{
		RegAdminCmd("sm_doors_glow", CmdGlow, ADMFLAG_ROOT, "Debug testing command to show all doors.");
	}
}

bool g_bGlow;
Action CmdGlow(int client, int args)
{
	g_bGlow = !g_bGlow;

	int entity = -1;
	while( (entity = FindEntityByClassname(entity, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
	{
		SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
		SetEntProp(entity, Prop_Send, "m_glowColorOverride", 255);
		SetEntProp(entity, Prop_Send, "m_nGlowRange", g_bGlow ? 0 : 9999);
		SetEntProp(entity, Prop_Send, "m_nGlowRangeMin", 20);
		if( g_bGlow )
			AcceptEntityInput(entity, "StartGlowing");
		else
			AcceptEntityInput(entity, "StopGlowing");
	}

	return Plugin_Handled;
}



// ====================================================================================================
//					PLUGIN END
// ====================================================================================================
public void OnPluginEnd()
{
	ResetPlugin();
}

void ResetPlugin()
{
	// Reset client arrays, progress bar and movement
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iPressing[i] && IsClientInGame(i) )
		{
			if( g_bLeft4Dead2 )
			{
				SetEntPropFloat(i, Prop_Send, "m_flProgressBarDuration", 0.0);
			}
			else
			{
				SetEntPropString(i, Prop_Send, "m_progressBarText", "");
				SetEntProp(i, Prop_Send, "m_iProgressBarDuration", 0);
			}
			SetEntPropFloat(i, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
			SetEntityMoveType(i, MOVETYPE_WALK);
		}

		g_iPressing[i] = 0;
		g_fPressing[i] = 0.0;
		g_fTimeout[i] = 0.0;
		g_fTimePress[i] = 0.0;
		g_fTimeSound[i] = 0.0;
	}

	// Reset entity arrays, delete planks
	int entity;

	for( int i = 0; i < 2048; i++ )
	{
		g_vAng[i] = view_as<float>({ 0.0, 0.0, 0.0 });
		g_vPos[i] = view_as<float>({ 0.0, 0.0, 0.0 });
		g_iDoors[i] = 0;
		g_iRelative[i] = 0;
		g_iRelIndex[i] = 0;

		for( int x = 0; x < 4; x++ )
		{
			entity = g_iBarricade[i][x];
			if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
			{
				RemoveEntity(entity);
			}

			g_iBarricade[i][x] = 0;
		}
	}
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnMapStart()
{
	g_bMapStarted = true;

	PrecacheModel(MODEL_PLANK1);
	PrecacheModel(MODEL_PLANK2);
	PrecacheSound(SOUND_HAMMER1);
	PrecacheSound(SOUND_HAMMER2);
	PrecacheSound(SOUND_HAMMER3);
}

public void OnMapEnd()
{
	g_bGlow = false;
	g_bMapStarted = false;

	ResetPlugin();
}

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
	g_iCvarDamageC = g_hCvarDamageC.IntValue;
	g_iCvarDamageI = g_hCvarDamageI.IntValue;
	g_iCvarDamageS = g_hCvarDamageS.IntValue;
	g_iCvarDamageT = g_hCvarDamageT.IntValue;
	g_iCvarHealth = g_hCvarHealth.IntValue;
	g_fCvarRange = g_hCvarRange.FloatValue;
	g_fCvarTime = g_hCvarTime.FloatValue;
	g_fCvarTimePress = g_hCvarTimePress.FloatValue;
	g_fCvarTimeWait = g_hCvarTimeWait.FloatValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		g_bCvarAllow = true;

		HookEvent("round_end",			Event_RoundEnd,		EventHookMode_PostNoCopy);

		int entity = -1;
		while( (entity = FindEntityByClassname(entity, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
		{
			SpawnPost(entity);
		}
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		g_bCvarAllow = false;

		UnhookEvent("round_end",		Event_RoundEnd,		EventHookMode_PostNoCopy);

		ResetPlugin();
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
//					EVENTS
// ====================================================================================================
void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bGlow = false;
	ResetPlugin();
}


// ====================================================================================================
//					DOOR SPAWN
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
	// Ignore outhouse doors and gun cabinet doors
	static char sModel[64];
	GetEntPropString(entity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	if(
		strcmp(sModel, "models/props_urban/outhouse_door001.mdl") == 0 ||
		strcmp(sModel, "models/props_unique/guncabinet01_ldoor.mdl") == 0 ||
		strcmp(sModel, "models/props_unique/guncabinet01_rdoor.mdl") == 0
	) return;

	// Store ref
	g_iDoors[entity] = EntIndexToEntRef(entity);

	// Save positions
	float vAng[3], vPos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);
	GetEntPropVector(entity, Prop_Data, "m_angRotationClosed", vAng);
	vAng[1] -= 90.0;

	// Change height since L4D1 and L4D2 door models have different ground position (vPos[2])
	if( strncmp(sModel, "models/props_doors", 18) == 0 )
	{
		vPos[2] -= 10.0;
	} else {
		vPos[2] += 42.0;
	}

	g_vPos[entity] = vPos;
	g_vAng[entity] = vAng;

	// Find double doors
	MatchRelatives(entity);
}

void MatchRelatives(int entity)
{
	static char sTemp[128], sTarget[128];
	int target = -1;

	// Match relative doors by "m_SlaveName"
	GetEntPropString(entity, Prop_Data, "m_SlaveName", sTemp, sizeof(sTemp));

	if( sTemp[0] != 0 )
	{
		while( (target = FindEntityByClassname(target, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
		{
			if( target != entity )
			{
				GetEntPropString(target, Prop_Data, "m_iName", sTarget, sizeof(sTarget));
				if( strcmp(sTemp, sTarget) == 0 )
				{
					g_iRelative[target] = EntIndexToEntRef(entity);
					g_iRelative[entity] = EntIndexToEntRef(target);
					g_iRelIndex[target] = entity;
					g_iRelIndex[entity] = target;
					return;
				}
			}
		}
	}

	// Match relative doors by "m_iName"
	GetEntPropString(entity, Prop_Data, "m_iName", sTemp, sizeof(sTemp));

	if( sTemp[0] != 0 )
	{
		target = -1;

		while( (target = FindEntityByClassname(target, "prop_door_rotating")) != INVALID_ENT_REFERENCE )
		{
			if( target != entity )
			{
				GetEntPropString(target, Prop_Data, "m_iName", sTarget, sizeof(sTarget));
				if( strcmp(sTemp, sTarget) == 0 )
				{
					g_iRelative[target] = EntIndexToEntRef(entity);
					g_iRelative[entity] = EntIndexToEntRef(target);

					g_iRelIndex[target] = entity;
					g_iRelIndex[entity] = target;
					return;
				}
			}
		}
	}
}



// ====================================================================================================
//					KEYBINDS
// ====================================================================================================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if( !g_bCvarAllow ) return Plugin_Continue;

	if( buttons & IN_USE )
	{
		// Validation checks
		if( !IsPlayerAlive(client) || GetClientTeam(client) != 2 ) return Plugin_Continue;
		if( IsReviving(client) || IsIncapped(client) || IsClientPinned(client) ) return Plugin_Continue;

		// Time pressing +USE
		if( g_fTimePress[client] == 0.0 )
		{
			g_fTimePress[client] = GetGameTime();
		}
		else if( GetGameTime() > g_fTimePress[client] + g_fCvarTimePress )
		{
			if( g_fTimeout[client] < GetGameTime() )
			{
				int index;

				if( !g_iPressing[client] )
				{
					// Player pos, find nearest door that existed
					float range = g_fCvarRange;
					float dist;
					float vPos[3];
					GetClientAbsOrigin(client, vPos);

					// Loop doors
					for( int i = 0; i < 2048; i++ )
					{
						// Door pos
						if( g_vPos[i][0] && g_vPos[i][1] && g_vPos[i][2] )
						{
							// Door is dead
							if( g_iDoors[i] && EntRefToEntIndex(g_iDoors[i]) == INVALID_ENT_REFERENCE && !IsValidEntRef(g_iRelative[i]) )
							{
								dist = GetVectorDistance(vPos, g_vPos[i]);

								if( dist < range )
								{
									range = dist;
									index = i;
								}
							}
						}
					}
				} else {
					index = g_iPressing[client];
				}

				if( index && (!IsValidEntRef(g_iBarricade[index][0]) || !IsValidEntRef(g_iBarricade[index][1]) || !IsValidEntRef(g_iBarricade[index][2]) || !IsValidEntRef(g_iBarricade[index][3])) )
				{
					// Start pressing
					if( !g_iPressing[client] )
					{
						g_fPressing[client] = GetGameTime() + g_fCvarTime;
						g_iPressing[client] = index;
						if( g_bLeft4Dead2 )
						{
							SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", g_fCvarTime);
						}
						else
						{
							SetEntPropString(client, Prop_Send, "m_progressBarText", "BUILDING BARRICADE...");
							SetEntProp(client, Prop_Send, "m_iProgressBarDuration", RoundFloat(g_fCvarTime));
						}
						SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
						SetEntityMoveType(client, MOVETYPE_NONE);
						TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 0.0 }));
					} else {
						PlaySound(client);

						// Finished pressing
						if( g_fPressing[client] < GetGameTime() )
						{
							g_fTimePress[client] = 0.0;
							g_fTimeout[client] = GetGameTime() + g_fCvarTimeWait;
							g_iPressing[client] = 0;
							if( g_bLeft4Dead2 )
							{
								SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
							}
							else
							{
								SetEntPropString(client, Prop_Send, "m_progressBarText", "");
								SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
							}
							SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
							SetEntityMoveType(client, MOVETYPE_WALK);
							BuildBarricade(index);
						}
					}
				}
			}
		}
	}
	else
	{
		g_fTimePress[client] = 0.0;

		if( g_iPressing[client] )
		{
			g_iPressing[client] = 0;
			g_fPressing[client] = 0.0;

			if( g_bLeft4Dead2 )
			{
				SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
			}
			else
			{
				SetEntPropString(client, Prop_Send, "m_progressBarText", "");
				SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
			}
			SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
			SetEntityMoveType(client, MOVETYPE_WALK);
		}
	}

	return Plugin_Continue;
}



// ====================================================================================================
//					SOUND
// ====================================================================================================
void PlaySound(int client)
{
	if( g_fTimeSound[client] < GetGameTime() )
	{
		g_fTimeSound[client] = GetGameTime() + GetRandomFloat(0.35, 0.5);

		SetRandomSeed(RoundFloat(GetTickedTime()));
		switch( GetRandomInt(1, 3) )
		{
			case 1: EmitSoundToAll(SOUND_HAMMER1, client);
			case 2: EmitSoundToAll(SOUND_HAMMER2, client);
			case 3: EmitSoundToAll(SOUND_HAMMER3, client);
		}
	}
}



// ====================================================================================================
//					MAKE BARRICADE
// ====================================================================================================
void BuildBarricade(int index)
{
	int plank;

	if( !IsValidEntRef(g_iBarricade[index][0]) )			plank = 1;
	else if( !IsValidEntRef(g_iBarricade[index][1]) )		plank = 2;
	else if( !IsValidEntRef(g_iBarricade[index][2]) )		plank = 3;
	else if( !IsValidEntRef(g_iBarricade[index][3]) )		plank = 4;

	if( plank )
	{
		bool dbl_door = g_iRelative[index] != 0;

		int entity = CreateEntityByName("prop_physics");
		if( entity != -1 )
		{
			// If double doors, set relative barricade reference to prevent dupe barricades being created
			g_iBarricade[index][plank - 1] = EntIndexToEntRef(entity);
			if( dbl_door ) g_iBarricade[g_iRelIndex[index]][plank - 1] = EntIndexToEntRef(entity);

			DispatchKeyValue(entity, "solid", "6");
			DispatchKeyValue(entity, "model", dbl_door ? MODEL_PLANK2 : MODEL_PLANK1);
			DispatchSpawn(entity);
			SetEntityMoveType(entity, MOVETYPE_NONE);

			// Health
			SetEntProp(entity, Prop_Data, "m_iHealth", g_iCvarHealth);

			SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);

			// Position
			float vAng[3];
			float vPos[3];

			vAng = g_vAng[index];
			vPos = g_vPos[index];

			// Move into center of door
			if( dbl_door ) // Double door
				MoveSideway(vPos, vAng, vPos, -50.0);
			else
				MoveSideway(vPos, vAng, vPos, -25.0);

			switch( plank )
			{
				case 1:
				{
					// Ang up right, very bottom of door
					vAng[1] -= 90.0;
					vAng[2] += 92.0;
					vPos[2] -= dbl_door ? 28.0 : 20.0;
				}
				case 2:
				{
					// Ang up right, bottom of door
					vAng[1] -= 90.0;
					vAng[2] += dbl_door ? 89.0 : 96.0;
					vPos[2] -= dbl_door ? 10.0 : 7.0;
				}
				case 3:
				{
					// Ang up left, middle of door
					vAng[1] -= 90.0;
					vAng[2] += dbl_door ? 87.0 : 85.0;
					vPos[2] += dbl_door ? 12.0 : 8.0;
				}
				case 4:
				{
					// Ang up right, top of door
					vAng[1] -= 90.0;
					vAng[2] += dbl_door ? 92.0 : 95.0;
					vPos[2] += dbl_door ? 35.0 : 25.0;
				}
			}

			float angleX = vAng[0];
			float angleY = vAng[1];
			float angleZ = vAng[2];
			float vNew[3];
			float vLoc[3];
			NormalizeVector(vPos, vLoc);

			// Thanks to "Don't Fear The Reaper" for the Rotation Matrix:
			vNew[0] = (vLoc[0] * Cosine(angleX) * Cosine(angleY)) - (vLoc[1] * Cosine(angleZ) * Sine(angleY)) + (vLoc[1] * Sine(angleZ) * Sine(angleX) * Cosine(angleY)) + (vLoc[2] * Sine(angleZ) * Sine(angleY)) + (vLoc[2] * Cosine(angleZ) * Sine(angleX) * Cosine(angleY));
			vNew[1] = (vLoc[0] * Cosine(angleX) * Sine(angleY)) + (vLoc[1] * Cosine(angleZ) * Cosine(angleY)) + (vLoc[1] * Sine(angleZ) * Sine(angleX) * Sine(angleY)) - (vLoc[2] * Sine(angleZ) * Cosine(angleY)) + (vLoc[2] * Cosine(angleZ) * Sine(angleX) * Sine(angleY));
			vNew[2] = (-1.0 * vLoc[0] * Sine(angleX)) + (vLoc[1] * Sine(angleZ) * Cosine(angleX)) + (vLoc[2] * Cosine(angleZ) * Cosine(angleX));
			vLoc = vNew;

			AddVectors(vPos, vLoc, vLoc);
			TeleportEntity(entity, vLoc, vAng, NULL_VECTOR); // Hanging left, middle of door
		}
	}
}

void MoveSideway(const float vPos[3], const float vAng[3], float vReturn[3], float fDistance)
{
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vReturn = vPos;
	vReturn[0] += vDir[0] * fDistance;
	vReturn[1] += vDir[1] * fDistance;
}



// ====================================================================================================
//					HEALTH
// ====================================================================================================
Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if( damagetype == DMG_CLUB )
	{
		int type;

		if( attacker > MaxClients )
		{
			type = TYPE_COMMON;
		}
		else if( attacker <= MaxClients && inflictor <= MaxClients ) // inflictor can be melee weapon which is also DMG_CLUB
		{
			if( GetClientTeam(attacker) == 3 )
			{
				int class = GetEntProp(attacker, Prop_Send, "m_zombieClass");
				if( (g_bLeft4Dead2 && class == 8) || g_bLeft4Dead2 && class == 5 )
					type = TYPE_TANK;
				else
					type = TYPE_INFECTED;
			}
			else
				type = TYPE_SURVIVOR;
		}

		switch( type )
		{
			case TYPE_COMMON:		if( !g_iCvarDamageC ) type = 0;
			case TYPE_INFECTED:		if( !g_iCvarDamageI ) type = 0;
			case TYPE_SURVIVOR:		if( !g_iCvarDamageS ) type = 0;
			case TYPE_TANK:			if( !g_iCvarDamageT ) type = 0;
		}
		if( type )
		{
			int health = GetEntProp(victim, Prop_Data, "m_iHealth");

			// Must set health on frame, after 1 hit the game sets the doors health to 0
			DataPack dPack = new DataPack();
			dPack.WriteCell(EntIndexToEntRef(victim));
			dPack.WriteCell(health);
			dPack.WriteCell(type);
			RequestFrame(OnFrameHealth, dPack);
		}

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

void OnFrameHealth(DataPack dPack)
{
	dPack.Reset();

	int entity = dPack.ReadCell();
	int health = dPack.ReadCell();
	int type = dPack.ReadCell();
	delete dPack;

	if( EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
	{
		switch( type )
		{
			case TYPE_COMMON:		health = health - g_iCvarDamageC;
			case TYPE_INFECTED:		health = health - g_iCvarDamageI;
			case TYPE_SURVIVOR:		health = health - g_iCvarDamageS;
			case TYPE_TANK:			health = health - g_iCvarDamageT;
		}

		if( health > 0 )
			SetEntProp(entity, Prop_Data, "m_iHealth", health);
		else
			SetEntProp(entity, Prop_Data, "m_iHealth", 0);
	}
}



// ====================================================================================================
//					STOCKS
// ====================================================================================================
bool IsValidEntRef(int entity)
{
	if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
}

bool IsReviving(int client)
{
	if( GetEntPropEnt(client, Prop_Send, "m_reviveOwner") > 0 )
		return true;
	return false;
}

bool IsIncapped(int client)
{
	if( GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) > 0 )
		return true;
	return false;
}

bool IsClientPinned(int client)
{
	if(
		GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0
	) return true;

	if( g_bLeft4Dead2 &&
	(
		GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0
	)) return true;

	return false;
}
