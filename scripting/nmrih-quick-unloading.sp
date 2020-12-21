#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name        = "[NMRiH] Quick Unloading",
    author      = "Dysphie",
    description = "Fetch ammo by pressing E on dropped weapons",
    version     = "1.0.0",
    url         = ""
};

Handle hUnloadWeapon;
Handle hGetWeaponWeight;
Handle hGetAmmoCarryWeight;
bool lateloaded;

ConVar hSndNoSpace;
ConVar hSndEmpty;
ConVar hSndGrab;
ConVar hInvMaxCarry;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	SetUpSDKCalls();

	hInvMaxCarry = FindConVar("inv_maxcarry");

	hSndNoSpace = CreateConVar("sm_quickunload_snd_nospace", 
		"ui/vote_failed.wav",
		"Sound to play when player lacks inventory space to grab the ammo");

	hSndEmpty = CreateConVar("sm_quickunload_snd_empty", 
		"weapons/firearms/hndg_beretta92fs/Beretta92_DryFire.wav",
		"Sound to play when a player tries to unload an empty gun");

	hSndGrab = CreateConVar("sm_quickunload_snd_grab", 
		"player/ammo_pickup_01.wav",
		"Sound to play when player grabs ammo from a gun");

	hSndNoSpace.AddChangeHook(OnSndChanged);
	hSndEmpty.AddChangeHook(OnSndChanged);
	hSndGrab.AddChangeHook(OnSndChanged);

	if (lateloaded)
	{
		int maxEnts = GetEntityCount();
		for (int e = MaxClients+1; e < maxEnts; e++)
			if (IsValidEntity(e) && IsEntityWeapon(e) && UsesPrimaryAmmo(e))
				SDKHook(e, SDKHook_Use, OnWeaponUse);		
	}
}

public void OnSndChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (newValue[0])
		PrecacheSound(newValue);
}

public void OnMapStart()
{
	char buffer[PLATFORM_MAX_PATH];
	hSndNoSpace.GetString(buffer, sizeof(buffer));
	if (buffer[0])
		PrecacheSound(buffer);

	hSndEmpty.GetString(buffer, sizeof(buffer));
	if (buffer[0])
		PrecacheSound(buffer);

	hSndGrab.GetString(buffer, sizeof(buffer));
	if (buffer[0])
		PrecacheSound(buffer);
}

void SetUpSDKCalls()
{
	GameData gamedata = new GameData("quick-unload.games");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "UnloadWeapon");
	hUnloadWeapon = EndPrepSDKCall();
	if (!hUnloadWeapon)
		SetFailState("Failed to set up SDKCall for UnloadWeapon");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "GetWeaponWeight");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGetWeaponWeight = EndPrepSDKCall();
	if (!hGetWeaponWeight)
		SetFailState("Failed to set up SDKCall for GetWeaponWeight");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "GetAmmoCarryWeight");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGetAmmoCarryWeight = EndPrepSDKCall();
	if (!hGetAmmoCarryWeight)
		SetFailState("Failed to set up SDKCall for GetAmmoCarryWeight");

	delete gamedata;	
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (IsEntityWeapon(entity) && UsesPrimaryAmmo(entity))
		SDKHook(entity, SDKHook_Use, OnWeaponUse);
}

public Action OnWeaponUse(int weapon, int activator, int client, UseType type, float value)
{
	if (!IsValidClient(client) || CanPickUpWeapon(client, weapon))
		return Plugin_Continue;

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon == -1)
		return Plugin_Continue;

	if (GetAmmoType(activeWeapon) != GetAmmoType(weapon))
		return Plugin_Continue;

	char sound[PLATFORM_MAX_PATH];
	int targetWeaponAmmo = GetWeaponAmmo(weapon);
	if (targetWeaponAmmo > 0)
	{
		UnloadWeapon(client, weapon);

		int taken = targetWeaponAmmo - GetWeaponAmmo(weapon);
		if (taken > 0)
		{
			hSndGrab.GetString(sound, sizeof(sound));
			EmitSoundToAll(sound, client);
			SendAmmoUpdate(client);
		}
		else
		{
			hSndNoSpace.GetString(sound, sizeof(sound));
			EmitSoundToClient(client, sound, client);
		}
	}
	else
	{
		hSndEmpty.GetString(sound, sizeof(sound));
		EmitSoundToClient(client, sound, weapon);
	}
	
	return Plugin_Handled;
}

int GetWeaponAmmo(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iClip1");
}

int GetAmmoType(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
}

void UnloadWeapon(int client, int weapon)
{
	int oldOwner = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	SetEntPropEnt(weapon, Prop_Send, "m_hOwner", client);
	SDKCall(hUnloadWeapon, weapon);
	SetEntPropEnt(weapon, Prop_Send, "m_hOwner", oldOwner);
}

void SendAmmoUpdate(int client)
{
	StartMessageOne("AmmoUpdate", client);
	EndMessage();
}

bool IsValidClient(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}

bool IsEntityWeapon(int entity)
{
	return HasEntProp(entity, Prop_Send, "m_flAmmoCheckStart");
}

bool UsesPrimaryAmmo(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") >= 0;
}

int GetWeaponWeight(int weapon)
{
	return SDKCall(hGetWeaponWeight, weapon);
}

int GetCarriedWeight(int client)
{
	int itemWeight = GetEntProp(client, Prop_Send, "_carriedWeight");
	return itemWeight + GetAmmoCarryWeight(client);
}

int GetAmmoCarryWeight(int client)
{
	return SDKCall(hGetAmmoCarryWeight, client);
}

bool CanPickUpWeapon(int client, int weapon)
{
	int carriedWeight = GetCarriedWeight(client);
	int weaponWeight = GetWeaponWeight(weapon);

	if (carriedWeight + weaponWeight > hInvMaxCarry.IntValue)
		return false;

	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));

	return !PlayerOwnsWeapon(client, classname);
}

bool PlayerOwnsWeapon(int client, const char[] classname)
{
	int max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	char buffer[32];

	for (int i; i < max; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon != -1)
		{
			GetEntityClassname(weapon, buffer, sizeof(buffer));
			if (strcmp(buffer, classname) == 0)
				return true;
		}
	}

	return false;
}