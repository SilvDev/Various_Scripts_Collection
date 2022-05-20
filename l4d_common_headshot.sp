/*
*	Common Infected Headshot Damage
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



#define PLUGIN_VERSION		"1.1"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Common Infected Headshot Damage
*	Author	:	SilverShot
*	Descrp	:	Prevents insta kill headshots and scales Headshot damage on Common Infected.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=337806
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.1 (20-May-2022)
	- Added cvar "l4d_common_headshot_melee" to block applying damage to melee weapons. Requested by "Maur0".

1.0 (16-May-2022)
	- Initial release.

======================================================================================*/

#pragma newdecls required
#pragma semicolon 1

#include <sdkhooks>
#include <sdktools>

#define CVAR_FLAGS			FCVAR_NOTIFY

ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog;
ConVar g_hCvarHeadshot, g_hCvarMelee;
float g_fCvarHeadshot;
bool g_bLeft4Dead2, g_bCvarAllow, g_bCvarMelee;
int g_iHitGroup[2048];



// ====================================================================================================
//					PLUGIN START
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Common Infected Headshot Damage",
	author = "SilverShot",
	description = "Prevents insta kill headshots and scales Headshot damage on Common Infected.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=337806"
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
	g_hCvarAllow = CreateConVar(			"l4d_common_headshot_allow",			"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes = CreateConVar(			"l4d_common_headshot_modes",			"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff = CreateConVar(			"l4d_common_headshot_modes_off",		"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog = CreateConVar(			"l4d_common_headshot_modes_tog",		"0",			"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarHeadshot = CreateConVar(			"l4d_common_headshot_damage",			"1.0",			"Scale damage value applied on headshots.");
	if( g_bLeft4Dead2 )
		g_hCvarMelee = CreateConVar(		"l4d_common_headshot_melee",			"0",			"0=Off. 1=Apply damage handling to melee weapons.");
	CreateConVar(							"l4d_common_headshot_version",			PLUGIN_VERSION,	"Common Infected Headshot Damage plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,					"l4d_common_headshot");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarHeadshot.AddChangeHook(ConVarChanged_Cvars);
	if( g_bLeft4Dead2 )
		g_hCvarMelee.AddChangeHook(ConVarChanged_Cvars);
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
}

public void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

public void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_fCvarHeadshot = g_hCvarHeadshot.FloatValue;
	if( g_bLeft4Dead2 )
		g_bCvarMelee = g_hCvarMelee.BoolValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		g_bCvarAllow = true;

		int entity = -1;
		while( (entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE )
		{
			SDKHook(entity, SDKHook_TraceAttack, OnTraceAttack);
			SDKHook(entity, SDKHook_OnTakeDamageAlive, OnTakeDamage);
		}
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		g_bCvarAllow = false;

		int entity = -1;
		while( (entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE )
		{
			SDKUnhook(entity, SDKHook_TraceAttack, OnTraceAttack);
			SDKUnhook(entity, SDKHook_OnTakeDamageAlive, OnTakeDamage);
		}
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

public void OnGamemode(const char[] output, int caller, int activator, float delay)
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
public void OnEntityCreated(int entity, const char[] classname)
{
	if( g_bCvarAllow && strcmp(classname, "infected") == 0 )
	{
		SDKHook(entity, SDKHook_TraceAttack, OnTraceAttack);
		SDKHook(entity, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	}
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	g_iHitGroup[victim] = hitgroup;
	// PrintToChatAll("\x01Common: \x04%d \x01Hitgroup: \x04%d", victim, hitgroup);

	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if( g_iHitGroup[victim] == 1 && attacker >= 1 && attacker <= MaxClients && GetClientTeam(attacker) == 2 )
	{
		// PrintToChatAll("\x01Headshot \x04%d \x01got \x04%f \x01damage", victim, damage);

		g_iHitGroup[victim] = 0;
		damage *= g_fCvarHeadshot;

		// PrintToChatAll("\x01Headshot \x04%d \x01set \x04%f \x01damage", victim, damage);

		if( GetEntProp(victim, Prop_Data, "m_iHealth") - damage > 0.0 )
		{
			// Prevent headshot insta-death
			SetEntProp(victim, Prop_Data, "m_LastHitGroup", 2);

			bool wounds = true;

			if( g_bLeft4Dead2 )
			{
				static char sTemp[48];

				if( !g_bCvarMelee )
				{
					GetEntityClassname(inflictor, sTemp, sizeof sTemp);
					if( strcmp(sTemp[7], "melee") == 0 )
					{
						return Plugin_Continue;
					}
				}

				GetEntPropString(victim, Prop_Data, "m_ModelName", sTemp, sizeof(sTemp));

				if( strcmp(sTemp, "models/infected/common_male_") == 0 &&
					(
					strcmp(sTemp[28], "ceda.mdl") == 0 ||
					strcmp(sTemp[28], "clown.mdl") == 0 ||
					strcmp(sTemp[28], "fallen_survivor.mdl") == 0 ||
					strcmp(sTemp[28], "jimmy.mdl") == 0 ||
					strcmp(sTemp[28], "mud.mdl") == 0 ||
					strcmp(sTemp[28], "riot.mdl") == 0 ||
					strcmp(sTemp[28], "roadcrew.mdl") == 0
					)
				)
				{
					wounds = false;
				}
			}

			if( wounds == false )
			{
				SetEntProp(victim, Prop_Send, "m_iRequestedWound1", -1);
				SetEntProp(victim, Prop_Send, "m_iRequestedWound2", -1);
			} else {
				// Change completely destroyed head gib to partial head gib with brains showing
				if( GetEntProp(victim, Prop_Send, "m_iRequestedWound1") == 8 )
					SetEntProp(victim, Prop_Send, "m_iRequestedWound1", 6);
				if( GetEntProp(victim, Prop_Send, "m_iRequestedWound2") == 8 )
					SetEntProp(victim, Prop_Send, "m_iRequestedWound2", 6);
			}
		}

		// PrintToChatAll("\x01Headshot \x04%d \x01dif \x04%f \x01damage", victim, damage);

		return Plugin_Changed;
	}

	return Plugin_Continue;
}
