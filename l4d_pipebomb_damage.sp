/*
*	PipeBomb Damage Modifier
*	Copyright (C) 2024 Silvers
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



#define PLUGIN_VERSION 		"1.10"

/*======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] PipeBomb Damage Modifier
*	Author	:	SilverShot
*	Descrp	:	Modifies PipeBomb damage.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=320901
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.10 (21-Apr-2024)
	- Fixed random error spam. Thanks to "CrazMan" for reporting.

1.9 (13-Jan-2024)
	- Plugin now supports simultaneous explosions from PipeBombs and breakable props (propane tank, oxygen tank etc) to correctly detect PipeBombs.

1.8 (19-Jun-2023)
	- Compatibility update for the "Detonation Force" plugin by "OIRV" to scale the additional damage created. Thanks to "Fsky" for reporting.

1.7 (23-Apr-2022)
	- Compatibility update for the "Damaged Grenades Explode" plugin. Thanks to "Shao" for reporting.

1.6 (14-Jul-2021)
	- Compatibility update for the "Bots Ignore PipeBombs and Shoot" plugin.

1.5 (15-May-2020)
	- Fixed 1.3 changes breaking the plugin from working.
	- Optimized the plugin even more.
	- Replaced "point_hurt" entity with "SDKHooks_TakeDamage" function.

1.4 (10-May-2020)
	- Extra checks to prevent "IsAllowedGameMode" throwing errors.
	- Various changes to tidy up code.

1.3 (05-Apr-2020)
	- Fixed affecting "weapon_oxygentank" which creates a "pipe_bomb_projectile" on explosion.
	- Thanks to "MasterMind420" for the fix method.

1.2 (01-Apr-2020)
	- Fixed "IsAllowedGameMode" from throwing errors when the "_tog" cvar was changed before MapStart.

1.1 (14-Jan-2020)
	- Added cvar "l4d_pipebomb_damage_tank" to modify damage against the Tank.

1.0 (14-Jan-2020)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define CVAR_FLAGS			FCVAR_NOTIFY


ConVar g_hCvarAllow, g_hDecayDecay, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarSpecial, g_hCvarSelf, g_hCvarSurvivor, g_hCvarTank;
float g_fCvarSpecial, g_fCvarSelf, g_fCvarSurvivor, g_fCvarTank, g_fDecayDecay, g_fGameTimeF, g_fCreatedTime[2048];
// float g_fGameTime; // Old version
bool g_bCvarAllow, g_bMapStarted, g_bLeft4Dead2, g_bIgnoreDamage, g_bDetonationForcePlugin;
int g_iClassTank, g_iClientOwner;



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] PipeBomb Damage Modifier",
	author = "SilverShot",
	description = "Modifies PipeBomb damage.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=320901"
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
	// ====================================================================================================
	// CVARS
	// ====================================================================================================
	g_hCvarAllow =			CreateConVar(	"l4d_pipebomb_damage_allow",		"1",				"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes =			CreateConVar(	"l4d_pipebomb_damage_modes",		"",					"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff =		CreateConVar(	"l4d_pipebomb_damage_modes_off",	"",					"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog =		CreateConVar(	"l4d_pipebomb_damage_modes_tog",	"0",				"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarSpecial =		CreateConVar(	"l4d_pipebomb_damage_special",		"1.0",				"Damage multiplier against Special Infected.", CVAR_FLAGS );
	g_hCvarSelf =			CreateConVar(	"l4d_pipebomb_damage_self",			"1.0",				"Damage multiplier against PipeBomb owner.", CVAR_FLAGS );
	g_hCvarSurvivor =		CreateConVar(	"l4d_pipebomb_damage_survivor",		"1.0",				"Damage multiplier against Survivors.", CVAR_FLAGS );
	g_hCvarTank =			CreateConVar(	"l4d_pipebomb_damage_tank",			"1.0",				"Damage multiplier against the Tank.", CVAR_FLAGS );
	CreateConVar(							"l4d_pipebomb_damage_version",		PLUGIN_VERSION,		"PipeBomb Damage Modifier plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,					"l4d_pipebomb_damage");

	g_hDecayDecay = FindConVar("pain_pills_decay_rate");
	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarSpecial.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarSelf.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarSurvivor.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTank.AddChangeHook(ConVarChanged_Cvars);
	g_hDecayDecay.AddChangeHook(ConVarChanged_Cvars);

	g_iClassTank = g_bLeft4Dead2 ? 8 : 5;
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnMapStart()
{
	g_bMapStarted = true;
}

public void OnMapEnd()
{
	g_bMapStarted = false;
}

public void OnConfigsExecuted()
{
	IsAllowed();
	g_bDetonationForcePlugin = FindConVar("l4d2_detonation_force_version") != null;
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
	g_fCvarSpecial = g_hCvarSpecial.FloatValue;
	g_fCvarSelf = g_hCvarSelf.FloatValue;
	g_fCvarSurvivor = g_hCvarSurvivor.FloatValue;
	g_fCvarTank = g_hCvarTank.FloatValue;
	g_fDecayDecay = g_hDecayDecay.FloatValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		// HookEvent("break_prop", Event_BreakProp, EventHookMode_PostNoCopy);
		HookClients(true);

		g_bCvarAllow = true;
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		// UnhookEvent("break_prop", Event_BreakProp, EventHookMode_PostNoCopy);
		HookClients(false);

		g_bCvarAllow = false;
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
//					HOOKS
// ====================================================================================================
/* Old version
void Event_BreakProp(Event event, const char[] name, bool dontBroadcast)
{
	g_fGameTime = GetGameTime();
}
*/

public void OnEntityCreated(int entity, const char[] classname)
{
	if( g_bCvarAllow && strncmp(classname, "pipe_bomb_p", 11) == 0 ) // pipe_bomb_projectile
	{
		g_fCreatedTime[entity] = GetGameTime();
	}
}

public void OnClientPutInServer(int client)
{
	if( g_bCvarAllow )
	{
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	}
}

void HookClients(bool hook)
{
	static bool hooked;

	if( hook && !hooked )
	{
		hooked = true;

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame(i) )
			{
				SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamage);
			}
		}
	}
	else if( !hook && hooked )
	{
		hooked = false;

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientInGame(i) )
			{
				SDKUnhook(i, SDKHook_OnTakeDamageAlive, OnTakeDamage);
			}
		}
	}
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if( !g_bIgnoreDamage && inflictor > MaxClients && damagetype & (DMG_BLAST|DMG_BLAST_SURFACE|DMG_NERVEGAS) )
	{
		bool checked;
		char classname[22];
		GetEdictClassname(inflictor, classname, sizeof(classname));

		// if( (GetGameTime() != g_fGameTime && // Old version
		if( (g_fCreatedTime[inflictor] + 0.1 < GetGameTime() && strcmp(classname, "pipe_bomb_projectile") == 0) || GetEntProp(inflictor, Prop_Data, "m_iHammerID") == 19712806 ) // 19712806 used by "Damaged Grenades Explode" and "Bots Ignore PipeBombs and Shoot" to identify damage
		{
			g_fGameTimeF = GetGameTime();
			g_iClientOwner = attacker;

			checked = true;
		}
		else if( g_bDetonationForcePlugin ) // This plugin adds extra damage using the "point_hurt" entity, the owner no longer exists and damage cannot be scaled correctly
		{
			if( damagetype & DMG_NERVEGAS && GetGameTime() - g_fGameTimeF < 0.1 && strcmp(classname, "point_hurt") == 0 ) // Detonation uses this damage type and occurs within 0.1s of the original pipebomb exploding
			{
				GetEntPropString(victim, Prop_Data, "m_iName", classname, sizeof(classname));
				if( strcmp(classname, "hurtme") == 0 ) // Match the targetname giving by the other plugin
				{
					checked = true;

					if( victim == g_iClientOwner ) attacker = g_iClientOwner;
				}
			}
		}

		if( checked )
		{
			int team = GetClientTeam(victim);
			if( team == 3 )
			{
				int class = GetEntProp(victim, Prop_Send, "m_zombieClass");

				if( class == g_iClassTank )
					damage *= g_fCvarTank;
				else
					damage *= g_fCvarSpecial;
			} else {
				if( victim == attacker )
					damage *= g_fCvarSelf;
				else
					damage *= g_fCvarSurvivor;

				// Otherwise the player is killed instead of incapacitated.
				float health = GetClientHealth(victim) + GetTempHealth(victim);
				if( health - damage <= 0 )
				{
					g_bIgnoreDamage = true;
					HurtEntity(victim, attacker, health);
					g_bIgnoreDamage = false;

					damage = 0.0;
					return Plugin_Handled;
				}
			}

			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

float GetTempHealth(int client)
{
	float fGameTime = GetGameTime();
	float fHealthTime = GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
	float fHealth = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	fHealth -= (fGameTime - fHealthTime) * g_fDecayDecay;
	return fHealth < 0.0 ? 0.0 : fHealth;
}

void HurtEntity(int victim, int client, float damage)
{
	SDKHooks_TakeDamage(victim, client, client, damage, DMG_BLAST);
}
