#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <vscript_proxy>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name = "[NMRiH] Quick Unloading",
	author = "Dysphie",
	description = "Fetch ammo by pressing E on dropped weapons",
	version = "1.2.0",
	url = ""
};

bool lateloaded;
ConVar cvNudgeAmt;
ConVar cvWeightPerAmmo;
ConVar cvMaxCarry;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	cvMaxCarry = FindConVar("inv_maxcarry");
	cvWeightPerAmmo = FindConVar("inv_ammoweight");
	cvNudgeAmt = CreateConVar("sm_quickunload_nudge_force", "50.0");

	AutoExecConfig();

	if (lateloaded)
	{
		int maxEnts = GetMaxEntities();
		for (int e = MaxClients+1; e < maxEnts; e++)
			if (IsValidEdict(e) && IsEntityWeapon(e))
				OnWeaponCreated(e);	
	}
}

public void OnEntityCreated(int e, const char[] classname)
{
	if (IsValidEdict(e) && IsEntityWeapon(e))
		OnWeaponCreated(e);
}

public Action OnWeaponUse(int weapon, int activator, int client, UseType type, float value)
{
	if (!IsValidClient(client) || CanPickUpWeapon(client, weapon))
		return Plugin_Continue;

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon == -1)
		return Plugin_Continue;

	int wantedType = GetPrimaryAmmoType(activeWeapon);
	if (wantedType == -1 || wantedType != GetPrimaryAmmoType(weapon))
		return Plugin_Continue;

	if (UnloadWeapon(client, weapon))
	{
		NudgeWeapon(client, weapon);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

void NudgeWeapon(int client, int weapon)
{
	float goalPos[3];
	GetClientEyePosition(client, goalPos);

	float curPos[3];
	GetEntPropVector(weapon, Prop_Data, "m_vecAbsOrigin", curPos);

	float dirVec[3];
	MakeVectorFromPoints(curPos, goalPos, dirVec);
	NormalizeVector(dirVec, dirVec);
	ScaleVector(dirVec, cvNudgeAmt.FloatValue);

	TeleportEntity(weapon, NULL_VECTOR, NULL_VECTOR, dirVec);
}

int UnloadWeapon(int client, int weapon)
{
	if (!UsesPrimaryAmmo(weapon) || !UsesClipsForAmmo1(weapon))
		return false;
	
	int ammoBoxes = GetEntProp(weapon, Prop_Send, "m_iClip1");
	if (ammoBoxes <= 0)
		return false;

	int ammoBoxWeight = cvWeightPerAmmo.IntValue;
	if (ammoBoxWeight < 1)
		ammoBoxWeight = 1;

	int maxWeight = GetAvailableWeight(client);
	int takeBoxes = maxWeight / ammoBoxes * ammoBoxWeight;
	if (takeBoxes > ammoBoxes)
		takeBoxes = ammoBoxes;

	SetEntProp(weapon, Prop_Send, "m_iClip1", ammoBoxes - takeBoxes);	
	GivePlayerAmmo(client, takeBoxes, GetPrimaryAmmoType(weapon));
	SendAmmoUpdate(client);
	return true;
}

bool UsesClipsForAmmo1(int weapon)
{
	return RunEntVScriptBool(weapon, "UsesClipsForAmmo1()");
}

int GetPrimaryAmmoType(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
}

int GetAvailableWeight(int client)
{
	return max(0, cvMaxCarry.IntValue - GetCarriedWeight(client));
}

int GetCarriedWeight(int client)
{
	return RunEntVScriptInt(client, "GetCarriedWeight()");
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

void OnWeaponCreated(int weapon)
{
	SDKHook(weapon, SDKHook_Use, OnWeaponUse);
}

bool IsEntityWeapon(int entity)
{
	return HasEntProp(entity, Prop_Send, "m_flAmmoCheckStart");
}

bool UsesPrimaryAmmo(int weapon)
{
	return GetPrimaryAmmoType(weapon) >= 0;
}

int GetWeaponWeight(int weapon)
{
	return RunEntVScriptInt(weapon, "GetWeight()");
}

bool CanPickUpWeapon(int client, int weapon)
{
	if (GetAvailableWeight(client) < GetWeaponWeight(weapon))
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

any max(any a, any b)
{
	return (a > b) ? a : b;
}