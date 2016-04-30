#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smartdm>
#include <EasyJSON>
#include <zombiereloaded>

//Store Includes
#include <store/store-core>
#include <store/store-inventory>
#include <store/store-loadouts>

enum Equipment
{
	String:EquipmentName[STORE_MAX_NAME_LENGTH],
	String:EquipmentModelPath[PLATFORM_MAX_PATH], 
	Float:EquipmentPosition[3],
	Float:EquipmentAngles[3],
	String:EquipmentFlag[2],
	String:EquipmentAttachment[32]
}

enum EquipmentPlayerModelSettings
{
	String:EquipmentName[STORE_MAX_NAME_LENGTH],
	String:PlayerModelPath[PLATFORM_MAX_PATH],
	Float:Position[3],
	Float:Angles[3]
}

Handle g_hLookupAttachment;

bool g_zombieReloaded;

int g_equipment[1024][Equipment];
int g_equipmentCount = 0;

Handle g_equipmentNameIndex;
Handle g_loadoutSlotList;

int g_playerModels[1024][EquipmentPlayerModelSettings];
int g_playerModelCount = 0;

int g_iEquipment[MAXPLAYERS + 1][32];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("ZR_IsClientHuman"); 
	MarkNativeAsOptional("ZR_IsClientZombie"); 

	return APLRes_Success;
}

public Plugin myinfo =
{
	name        = "[Store] Equipment",
	author      = "alongub",
	description = "Equipment component for [Store]",
	version     = "1.1-alpha",
	url         = "https://github.com/alongubkin/store"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	g_loadoutSlotList = CreateArray(ByteCountToCells(32));
	
	g_zombieReloaded = LibraryExists("zombiereloaded");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	Handle hGameConf = LoadGameConfigFile("store-equipment.gamedata");
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "LookupAttachment");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	g_hLookupAttachment = EndPrepSDKCall();	

	Store_RegisterItemType("equipment", OnEquip, LoadItem);
	
	g_equipmentNameIndex = CreateTrie();
}

public void OnMapStart()
{
	for (int i = 0; i < g_equipmentCount; i++)
	{
		if (strcmp(g_equipment[i][EquipmentModelPath], "") != 0 && (FileExists(g_equipment[i][EquipmentModelPath]) || FileExists(g_equipment[i][EquipmentModelPath], true)))
		{
			PrecacheModel(g_equipment[i][EquipmentModelPath]);
			Downloader_AddFileToDownloadsTable(g_equipment[i][EquipmentModelPath]);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = true;
	}
	
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("equipment", OnEquip, LoadItem);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = false;
	}
}

public void OnClientDisconnect(int client)
{
	UnequipAll(client);
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!g_zombieReloaded || (g_zombieReloaded && ZR_IsClientHuman(client)))
	{
		CreateTimer(1.0, SpawnTimer, GetClientSerial(client));
	}
	else
	{
		UnequipAll(client);
	}
	
	return Plugin_Continue;
}

public void Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	UnequipAll(client);
}

public int ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	UnequipAll(client);
}

public int ZR_OnClientRespawned(int client, ZR_RespawnCondition condition)
{
	UnequipAll(client);
}

public Action SpawnTimer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return Plugin_Continue;
	}
	
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		return Plugin_Continue;
	}
		
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "equipment", Store_GetClientLoadout(client), OnGetPlayerEquipment, serial);
	return Plugin_Continue;
}

public void Store_OnClientLoadoutChanged(int client)
{
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "equipment", Store_GetClientLoadout(client), OnGetPlayerEquipment, GetClientSerial(client));
}

public void Store_OnReloadItems()
{
	ClearTrie(g_equipmentNameIndex);
	
	g_equipmentCount = 0;
	
	Store_RegisterItemType("equipment", OnEquip, LoadItem);
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_equipment[g_equipmentCount][EquipmentName], STORE_MAX_NAME_LENGTH, itemName);

	SetTrieValue(g_equipmentNameIndex, g_equipment[g_equipmentCount][EquipmentName], g_equipmentCount);

	Handle json = DecodeJSON(attrs);
	JSONGetString(json, "model", g_equipment[g_equipmentCount][EquipmentModelPath], PLATFORM_MAX_PATH);
	JSONGetString(json, "attachment", g_equipment[g_equipmentCount][EquipmentAttachment], 32);
	
	Handle position;
	JSONGetObject(json, "position", position);

	for (int i = 0; i <= 2; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));
		
		JSONGetFloat(position, sID, g_equipment[g_equipmentCount][EquipmentPosition][i]);
	}

	CloseHandle(position);

	Handle angles;
	JSONGetObject(json, "angles", angles);

	for (int i = 0; i <= 2; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));
		
		JSONGetFloat(angles, sID, g_equipment[g_equipmentCount][EquipmentAngles][i]);
	}

	CloseHandle(angles);

	if (strcmp(g_equipment[g_equipmentCount][EquipmentModelPath], "") != 0 && (FileExists(g_equipment[g_equipmentCount][EquipmentModelPath]) || FileExists(g_equipment[g_equipmentCount][EquipmentModelPath], true)))
	{
		PrecacheModel(g_equipment[g_equipmentCount][EquipmentModelPath]);
		Downloader_AddFileToDownloadsTable(g_equipment[g_equipmentCount][EquipmentModelPath]);
	}

	Handle playerModels;
	JSONGetObject(json, "playermodels", playerModels);

	if (playerModels != INVALID_HANDLE && JSON_TypeOf(playerModels) == Type_Array)
	{
		for (int i = 0, size = GetJSONArraySize(playerModels); i < size; i++)
		{
			char sID2[12];
			IntToString(i, sID2, sizeof(sID2));
			
			Handle playerModel;
			JSONGetArray(playerModels, sID2, playerModel);

			if (playerModel == INVALID_HANDLE)
			{
				continue;
			}

			if (JSON_TypeOf(playerModel) != Type_Object)
			{
				continue;
			}

			JSONGetString(playerModel, "playermodel", g_playerModels[g_playerModelCount][PlayerModelPath], PLATFORM_MAX_PATH);

			Handle playerModelPosition;
			JSONGetObject(playerModel, "position", playerModelPosition);

			for (int x = 0; x <= 2; x++)
			{
				char sID[12];
				IntToString(x, sID, sizeof(sID));
				
				JSONGetFloat(playerModelPosition, sID, g_playerModels[g_playerModelCount][Position][i]);
			}

			CloseHandle(playerModelPosition);

			Handle playerModelAngles;
			JSONGetObject(playerModel, "angles", playerModelAngles);

			for (int x = 0; x <= 2; x++)
			{
				char sID[12];
				IntToString(x, sID, sizeof(sID));
				
				JSONGetFloat(playerModelAngles, sID, g_playerModels[g_playerModelCount][Angles][i]);
			}

			strcopy(g_playerModels[g_playerModelCount][EquipmentName], STORE_MAX_NAME_LENGTH, itemName);

			CloseHandle(playerModelAngles);
			CloseHandle(playerModel);

			g_playerModelCount++;
		}

		CloseHandle(playerModels);
	}

	DestroyJSON(json);

	g_equipmentCount++;
}

public void OnGetPlayerEquipment(int[] ids, int count, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return;
	}
		
	if (!IsClientInGame(client))
	{
		return;
	}
	
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	for (int i = 0; i < count; i++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(ids[i], itemName, sizeof(itemName));
		
		char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
		Store_GetItemLoadoutSlot(ids[i], loadoutSlot, sizeof(loadoutSlot));
		
		int loadoutSlotIndex = FindStringInArray(g_loadoutSlotList, loadoutSlot);
		
		if (loadoutSlotIndex == -1)
		{
			loadoutSlotIndex = PushArrayString(g_loadoutSlotList, loadoutSlot);
		}
		
		Unequip(client, loadoutSlotIndex);
		
		if (!g_zombieReloaded || (g_zombieReloaded && ZR_IsClientHuman(client)))
		{
			Equip(client, loadoutSlotIndex, itemName);
		}
	}
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	if (!IsClientInGame(client))
	{
		return Store_DoNothing;
	}
	
	if (!IsPlayerAlive(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Must be alive to equip");
		return Store_DoNothing;
	}
	
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Must be human to equip");	
		return Store_DoNothing;
	}
	
	char name[STORE_MAX_NAME_LENGTH];
	Store_GetItemName(itemId, name, sizeof(name));
	
	char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
	Store_GetItemLoadoutSlot(itemId, loadoutSlot, sizeof(loadoutSlot));
	
	int loadoutSlotIndex = FindStringInArray(g_loadoutSlotList, loadoutSlot);
	
	if (loadoutSlotIndex == -1)
	{
		loadoutSlotIndex = PushArrayString(g_loadoutSlotList, loadoutSlot);
	}
		
	if (equipped)
	{
		if (!Unequip(client, loadoutSlotIndex))
		{
			return Store_DoNothing;
		}
	
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);
		return Store_UnequipItem;
	}
	else
	{
		if (!Equip(client, loadoutSlotIndex, name))
		{
			return Store_DoNothing;
		}
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);
		return Store_EquipItem;
	}
}

bool Equip(int client, int loadoutSlot, const char[] name)
{
	Unequip(client, loadoutSlot);
		
	int equipment = -1;
	if (!GetTrieValue(g_equipmentNameIndex, name, equipment))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
		return false;
	}
	
	if (!LookupAttachment(client, g_equipment[equipment][EquipmentAttachment])) 
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Player model unsupported");
		return false;
	}
	
	float or[3];
	GetClientAbsOrigin(client,or);
	
	float ang[3];
	GetClientAbsAngles(client,ang);

	char clientModel[PLATFORM_MAX_PATH];
	GetClientModel(client, clientModel, sizeof(clientModel));
	
	int playerModel = -1;
	for (int i = 0; i < g_playerModelCount; i++)
	{
		if (StrEqual(g_equipment[equipment][EquipmentName], g_playerModels[i][EquipmentName]) && StrEqual(clientModel, g_playerModels[i][PlayerModelPath], false))
		{
			playerModel = i;
			break;
		}
	}

	if (playerModel == -1)
	{
		ang[0] += g_equipment[equipment][EquipmentAngles][0];
		ang[1] += g_equipment[equipment][EquipmentAngles][1];
		ang[2] += g_equipment[equipment][EquipmentAngles][2];
	}
	else
	{
		ang[0] += g_playerModels[playerModel][Angles][0];
		ang[1] += g_playerModels[playerModel][Angles][1];
		ang[2] += g_playerModels[playerModel][Angles][2];		
	}

	float fOffset[3];

	if (playerModel == -1)
	{
		fOffset[0] = g_equipment[equipment][EquipmentPosition][0];
		fOffset[1] = g_equipment[equipment][EquipmentPosition][1];
		fOffset[2] = g_equipment[equipment][EquipmentPosition][2];	
	}
	else
	{
		fOffset[0] = g_playerModels[playerModel][Position][0];
		fOffset[1] = g_playerModels[playerModel][Position][1];
		fOffset[2] = g_playerModels[playerModel][Position][2];		
	}
	
	float fForward[3]; float fRight[3]; float fUp[3];
	GetAngleVectors(ang, fForward, fRight, fUp);

	or[0] += fRight[0] * fOffset[0] + fForward[0] * fOffset[1] + fUp[0] * fOffset[2];
	or[1] += fRight[1] * fOffset[0] + fForward[1] * fOffset[1] + fUp[1] * fOffset[2];
	or[2] += fRight[2] * fOffset[0] + fForward[2] * fOffset[1] + fUp[2] * fOffset[2];

	int entity = CreateEntityByName("prop_dynamic_override");
	
	if (IsValidEntity(entity))
	{
		DispatchKeyValue(entity, "model", g_equipment[equipment][EquipmentModelPath]);
		DispatchKeyValue(entity, "spawnflags", "256");
		DispatchKeyValue(entity, "solid", "0");
		SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
		
		DispatchSpawn(entity);	
		AcceptEntityInput(entity, "TurnOn", entity, entity, 0);
		
		g_iEquipment[client][loadoutSlot] = entity;
		
		SDKHook(entity, SDKHook_SetTransmit, ShouldHide);
		
		TeleportEntity(entity, or, ang, NULL_VECTOR); 
		
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client, entity, 0);
		
		SetVariantString(g_equipment[equipment][EquipmentAttachment]);
		AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset", entity, entity, 0);
		
		return true;
	}
	
	return false;
}

bool Unequip(int client, int loadoutSlot)
{      
	if (g_iEquipment[client][loadoutSlot] != 0 && IsValidEntity(g_iEquipment[client][loadoutSlot]))
	{
		SDKUnhook(g_iEquipment[client][loadoutSlot], SDKHook_SetTransmit, ShouldHide);
		AcceptEntityInput(g_iEquipment[client][loadoutSlot], "Kill");
	}
	
	g_iEquipment[client][loadoutSlot] = 0;
	return true;
}

void UnequipAll(int client)
{
	for (int i = 0, size = GetArraySize(g_loadoutSlotList); i < size; i++)
	{
		Unequip(client, i);
	}
}

public Action ShouldHide(int ent, int client)
{	
	for (int i = 0, size = GetArraySize(g_loadoutSlotList); i < size; i++)
	{
		if (ent == g_iEquipment[client][i])
		{
			return Plugin_Handled;
		}
	}
	
	if (IsClientInGame(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == 4 && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") >= 0)
	{
		for (int i = 0, size = GetArraySize(g_loadoutSlotList); i < size; i++)
		{
			if (ent == g_iEquipment[GetEntPropEnt(client, Prop_Send, "m_hObserverTarget")][i])
			{
				return Plugin_Handled;
			}
		}
	}
	
	return Plugin_Continue;
}

bool LookupAttachment(int client, char[] point)
{
	if (g_hLookupAttachment == INVALID_HANDLE)
	{
		return false;
	}

	if (client <= 0 || !IsClientInGame(client))
	{
		return false;
	}
	
	return SDKCall(g_hLookupAttachment, client, point);
}