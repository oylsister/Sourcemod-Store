#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <EasyJSON>
#include <zombiereloaded>

//Store Includes
#include <store/store-core>
#include <store/store-inventory>
#include <store/store-loadouts>

enum Trail
{
	String:TrailName[STORE_MAX_NAME_LENGTH],
	String:TrailMaterial[PLATFORM_MAX_PATH],
	Float:TrailLifetime,
	Float:TrailWidth,
	Float:TrailEndWidth,
	TrailFadeLength,
	TrailColor[4],
	TrailModelIndex
}

int g_trails[1024][Trail];
int g_trailCount;
bool g_zombieReloaded;

char g_game[32];

Handle g_trailsNameIndex;
Handle g_trailTimers[MAXPLAYERS+1];
int g_SpriteModel[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("ZR_IsClientHuman"); 
	MarkNativeAsOptional("ZR_IsClientZombie"); 

	return APLRes_Success;
}

public Plugin myinfo =
{
	name        = "[Store] Trails",
	author      = "alongub",
	description = "Trails component for [Store]",
	version     = "1.1-alpha",
	url         = "https://github.com/alongubkin/store"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	g_zombieReloaded = LibraryExists("zombiereloaded");
	
	HookEvent("player_spawn", PlayerSpawn);
	HookEvent("player_death", PlayerDeath);
	HookEvent("player_team", PlayerTeam);
	HookEvent("round_end", RoundEnd);
	
	g_trailsNameIndex = CreateTrie();

	GetGameFolderName(g_game, sizeof(g_game));

	Store_RegisterItemType("trails", OnEquip, LoadItem);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = true;
	}
	
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("trails", OnEquip, LoadItem);
	}	
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = false;
	}
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_SpriteModel[i] = -1;
	}

	for (int i = 0; i < g_trailCount; i++)
	{
		if (strcmp(g_trails[i][TrailMaterial], "") != 0 && (FileExists(g_trails[i][TrailMaterial]) || FileExists(g_trails[i][TrailMaterial], true)))
		{
			char sBuffer[PLATFORM_MAX_PATH];
			strcopy(sBuffer, sizeof(sBuffer), g_trails[i][TrailMaterial]);
			g_trails[i][TrailModelIndex] = PrecacheModel(sBuffer);
			AddFileToDownloadsTable(sBuffer);
			ReplaceString(sBuffer, sizeof(sBuffer), ".vmt", ".vtf", false);
			AddFileToDownloadsTable(sBuffer);
		}
	}
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_trailTimers[i] != INVALID_HANDLE)
		{
			CloseHandle(g_trailTimers[i]);
			g_trailTimers[i] = INVALID_HANDLE;
		}

		g_SpriteModel[i] = -1;
	}
}

public void Store_OnReloadItems() 
{
	ClearTrie(g_trailsNameIndex);
	
	g_trailCount = 0;
	
	Store_RegisterItemType("trails", OnEquip, LoadItem);
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_trails[g_trailCount][TrailName], STORE_MAX_NAME_LENGTH, itemName);
		
	SetTrieValue(g_trailsNameIndex, g_trails[g_trailCount][TrailName], g_trailCount);
	
	Handle json = DecodeJSON(attrs);
	JSONGetString(json, "material", g_trails[g_trailCount][TrailMaterial], PLATFORM_MAX_PATH);

	JSONGetFloat(json, "lifetime", g_trails[g_trailCount][TrailLifetime]);
	
	if (g_trails[g_trailCount][TrailLifetime] == 0.0)
	{
		g_trails[g_trailCount][TrailLifetime] = 1.0;
	}

	JSONGetFloat(json, "width", g_trails[g_trailCount][TrailWidth]);

	if (g_trails[g_trailCount][TrailWidth] == 0.0)
	{
		g_trails[g_trailCount][TrailWidth] = 15.0;
	}

	JSONGetFloat(json, "endwidth", g_trails[g_trailCount][TrailEndWidth]); 

	if (g_trails[g_trailCount][TrailEndWidth] == 0.0)
	{
		g_trails[g_trailCount][TrailEndWidth] = 6.0;
	}

	JSONGetInteger(json, "fadelength", g_trails[g_trailCount][TrailFadeLength]); 

	if (g_trails[g_trailCount][TrailFadeLength] == 0)
	{
		g_trails[g_trailCount][TrailFadeLength] = 1;
	}
	
	Handle color;
	JSONGetObject(json, "color", color);

	if (color == INVALID_HANDLE)
	{
		g_trails[g_trailCount][TrailColor] = { 255, 255, 255, 255 };
	}
	else
	{
		for (int i = 0; i < 4; i++)
		{
			char sID[12];
			IntToString(i, sID, sizeof(sID));
			
			JSONGetInteger(color, sID, g_trails[g_trailCount][TrailColor][i]);
		}

		CloseHandle(color);
	}

	CloseHandle(json);

	if (strcmp(g_trails[g_trailCount][TrailMaterial], "") != 0 && (FileExists(g_trails[g_trailCount][TrailMaterial]) || FileExists(g_trails[g_trailCount][TrailMaterial], true)))
	{
		char sBuffer[PLATFORM_MAX_PATH];
		strcopy(sBuffer, sizeof(sBuffer), g_trails[g_trailCount][TrailMaterial]);
		g_trails[g_trailCount][TrailModelIndex] = PrecacheModel(sBuffer);
		AddFileToDownloadsTable(sBuffer);
		ReplaceString(sBuffer, sizeof(sBuffer), ".vmt", ".vtf", false);
		AddFileToDownloadsTable(sBuffer);
	}
	
	g_trailCount++;
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	if (!IsClientInGame(client))
	{
		return Store_DoNothing;
	}
	
	if (!IsPlayerAlive(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item apply next spawn");
		return Store_EquipItem;
	}

	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item apply next spawn");	
		return Store_EquipItem;
	}
	
	char name[STORE_MAX_NAME_LENGTH];
	Store_GetItemName(itemId, name, sizeof(name));
	
	char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
	Store_GetItemLoadoutSlot(itemId, loadoutSlot, sizeof(loadoutSlot));
	
	KillTrail(client);

	if (equipped)
	{
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);

		return Store_UnequipItem;
	}
	else
	{		
		if (!Equip(client, name))
		{
			return Store_DoNothing;
		}
			
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);

		return Store_EquipItem;
	}
}

public void OnClientDisconnect(int client)
{
	if (g_trailTimers[client] != INVALID_HANDLE)
	{
		CloseHandle(g_trailTimers[client]);
		g_trailTimers[client] = INVALID_HANDLE;
	}

	g_SpriteModel[client] = -1;
}

public Action PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (IsClientInGame(client) && IsPlayerAlive(client)) 
	{
		if (g_trailTimers[client] != INVALID_HANDLE)
		{
			CloseHandle(g_trailTimers[client]);
			g_trailTimers[client] = INVALID_HANDLE;
		}

		g_SpriteModel[client] = -1;

		CreateTimer(1.0, GiveTrail, GetClientSerial(client));
	}
}

public void PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid") );
	
	if (GetEventInt(event, "team") < 2)
	{
		KillTrail(client);
	}
}

public Action PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	KillTrail(client);
}

public Action RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_trailTimers[i] != INVALID_HANDLE)
		{
			CloseHandle(g_trailTimers[i]);
			g_trailTimers[i] = INVALID_HANDLE;
		}

		g_SpriteModel[i] = -1;
	}
}

public Action GiveTrail(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
		
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		return Plugin_Continue;
	}
		
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "trails", Store_GetClientLoadout(client), OnGetPlayerTrail, GetClientSerial(client));
	return Plugin_Handled;
}

public void Store_OnClientLoadoutChanged(int client)
{
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "trails", Store_GetClientLoadout(client), OnGetPlayerTrail, GetClientSerial(client));
}

public void OnGetPlayerTrail(int[] ids, int count, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return;
	}
		
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		return;
	}
		
	KillTrail(client);
	
	for (int i = 0; i < count; i++)
	{
		char itemName[32];
		Store_GetItemName(ids[i], itemName, sizeof(itemName));
		
		Equip(client, itemName);
	}
}

bool Equip(int client, const char[] name)
{	
	KillTrail(client);

	int trail = -1;
	if (!GetTrieValue(g_trailsNameIndex, name, trail))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
		return false;
	}

	if (StrEqual(g_game, "csgo"))
	{
		EquipTrailTempEnts(client, trail);

		Handle pack;
		g_trailTimers[client] = CreateDataTimer(0.1, Timer_RenderBeam, pack, TIMER_REPEAT);

		WritePackCell(pack, GetClientSerial(client));
		WritePackCell(pack, trail);

		return true;
	}
	else
	{
		return EquipTrail(client, trail);
	}
}

bool EquipTrailTempEnts(int client, int trail)
{
	int entityToFollow = GetPlayerWeaponSlot(client, 2);
	
	if (entityToFollow == -1)
	{
		entityToFollow = client;
	}

	int color[4];
	Array_Copy(g_trails[client][TrailColor], color, sizeof(color));

	TE_SetupBeamFollow(entityToFollow, g_trails[trail][TrailModelIndex], 0, g_trails[trail][TrailLifetime], g_trails[trail][TrailWidth], g_trails[trail][TrailEndWidth], g_trails[trail][TrailFadeLength], color);
	TE_SendToAll();

	return true;
}

bool EquipTrail(int client, int trail)
{
	g_SpriteModel[client] = CreateEntityByName("env_spritetrail");

	if (!IsValidEntity(g_SpriteModel[client]))
	{
		return false;
	}

	char strTargetName[MAX_NAME_LENGTH];
	GetClientName(client, strTargetName, sizeof(strTargetName));

	DispatchKeyValue(client, "targetname", strTargetName);
	DispatchKeyValue(g_SpriteModel[client], "parentname", strTargetName);
	DispatchKeyValueFloat(g_SpriteModel[client], "lifetime", g_trails[trail][TrailLifetime]);
	DispatchKeyValueFloat(g_SpriteModel[client], "endwidth", g_trails[trail][TrailEndWidth]);
	DispatchKeyValueFloat(g_SpriteModel[client], "startwidth", g_trails[trail][TrailWidth]);
	DispatchKeyValue(g_SpriteModel[client], "spritename", g_trails[trail][TrailMaterial]);
	DispatchKeyValue(g_SpriteModel[client], "renderamt", "255");

	char color[32];
	Format(color, sizeof(color), "%d %d %d %d", g_trails[trail][TrailColor][0], g_trails[trail][TrailColor][1], g_trails[trail][TrailColor][2], g_trails[trail][TrailColor][3]);

	DispatchKeyValue(g_SpriteModel[client], "rendercolor", color);
	DispatchKeyValue(g_SpriteModel[client], "rendermode", "5");

	DispatchSpawn(g_SpriteModel[client]);

	float Client_Origin[3];
	GetClientAbsOrigin(client,Client_Origin);
	Client_Origin[2] += 10.0;

	TeleportEntity(g_SpriteModel[client], Client_Origin, NULL_VECTOR, NULL_VECTOR);

	SetVariantString(strTargetName);
	AcceptEntityInput(g_SpriteModel[client], "SetParent"); 
	SetEntPropFloat(g_SpriteModel[client], Prop_Send, "m_flTextureRes", 0.05);

	return true;
}

void KillTrail(int client)
{
	if (g_trailTimers[client] != INVALID_HANDLE)
	{
		CloseHandle(g_trailTimers[client]);
		g_trailTimers[client] = INVALID_HANDLE;
	}

	if (g_SpriteModel[client] != -1 && IsValidEntity(g_SpriteModel[client]))
	{
		RemoveEdict(g_SpriteModel[client]);
	}

	g_SpriteModel[client] = -1;
}

public int ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	KillTrail(client);
}

public Action Timer_RenderBeam(Handle timer, Handle pack)
{
	ResetPack(pack);

	int	client = GetClientFromSerial(ReadPackCell(pack));

	if (client == 0)
	{
		return Plugin_Stop;
	}

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);		

	bool isMoving = !(velocity[0] == 0.0 && velocity[1] == 0.0 && velocity[2] == 0.0);
	
	if (isMoving)
	{
		return Plugin_Continue;
	}

	EquipTrailTempEnts(client, ReadPackCell(pack));
	return Plugin_Continue;
}

void Array_Copy(const any[] array, any[] newArray, int size)
{
	for (int i = 0; i < size; i++) 
	{
		newArray[i] = array[i];
	}
}