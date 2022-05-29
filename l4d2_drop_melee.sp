/*
*	Drop Melee Weapon on Death
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

*	Name	:	[L4D2] Drop Melee Weapon on Death
*	Author	:	SilverShot
*	Descrp	:	Drops a players melee weapon when they die.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=337958
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.0 (29-May-2022)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

int g_iMelee[MAXPLAYERS+1];



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D2] Drop Melee Weapon on Death",
	author = "SilverShot",
	description = "Drops a players melee weapon when they die.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=337958"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();

	if( test != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("l4d2_drop_melee_version", PLUGIN_VERSION, "Drop Melee Weapon on Death plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	HookEvent("player_death", Event_PlayerDeath);

	// Late load
	int weapon;
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame(i) )
		{
			OnClientPutInServer(i);

			weapon = GetPlayerWeaponSlot(i, 1);
			if( weapon != -1 )
			{
				OnWeaponEquip(i, weapon);
			}
		}
	}
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponCanUsePost, OnWeaponEquip);
}

Action OnWeaponEquip(int client, int weapon)
{
	static char sTemp[16];
	GetEdictClassname(weapon, sTemp, sizeof(sTemp));
	if( strcmp(sTemp, "weapon_melee") == 0 )
	{
		g_iMelee[client] = EntIndexToEntRef(weapon);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( client && IsClientInGame(client) && GetClientTeam(client) == 2 )
	{
		int entity = g_iMelee[client];
		if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		{
			// Old weapon remains at 0,0,0, still with the client as the "m_hOwnerEntity".
			static char sTemp[32];
			GetEntPropString(entity, Prop_Data, "m_strMapSetScriptName", sTemp, sizeof(sTemp));
			RemoveEntity(entity);

			// Create new and drop
			entity = CreateEntityByName("weapon_melee");
			if( entity != -1 )
			{
				float vPos[3];
				GetClientAbsOrigin(client, vPos);
				vPos[0] += 30;
				vPos[1] += 30;
				vPos[2] += 35.0;

				DispatchKeyValue(entity, "solid", "6");
				DispatchKeyValue(entity, "melee_script_name", sTemp);
				TeleportEntity(entity, vPos, view_as<float>({ 10.0, 10.0, 1.0 }), NULL_VECTOR);
				DispatchSpawn(entity);
			}
		}
	}
}
