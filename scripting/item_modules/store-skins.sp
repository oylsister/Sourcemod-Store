#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <smartdm>
#include <EasyJSON>

//Store Includes
#include <store/store-core>
#include <store/store-inventory>
#include <store/store-loadouts>

enum Skin
{
	String:SkinName[STORE_MAX_NAME_LENGTH],
	String:SkinModelPath[PLATFORM_MAX_PATH], 
	SkinTeams[5]
}

int g_skins[1024][Skin];
int g_skinCount = 0;

Handle g_skinNameIndex;

char g_game[32];

public Plugin myinfo =
{
    name        = "[Store] Skins",
    author      = "alongub",
    description = "Skins component for [Store]",
    version     = "1.1-alpha",
    url         = "https://github.com/alongubkin/store"
};

public void OnPluginStart()
{
	LoadTranslations("store.phrases");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	Store_RegisterItemType("skin", OnEquip, LoadItem);
	GetGameFolderName(g_game, sizeof(g_game));
	
	g_skinNameIndex = CreateTrie();
}

public void OnMapStart()
{
	for (int i = 0; i < g_skinCount; i++)
	{
		if (strcmp(g_skins[i][SkinModelPath], "") != 0 && (FileExists(g_skins[i][SkinModelPath]) || FileExists(g_skins[i][SkinModelPath], true)))
		{
			PrecacheModel(g_skins[i][SkinModelPath]);
			Downloader_AddFileToDownloadsTable(g_skins[i][SkinModelPath]);
		}
	}
}

public void OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("skin", OnEquip, LoadItem);
	}
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	if (IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	CreateTimer(1.0, Timer_Spawn, GetClientSerial(client));
	
	return Plugin_Continue;
}

public Action Timer_Spawn(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return Plugin_Continue;
	}
		
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "skin", Store_GetClientLoadout(client), OnGetPlayerSkin, serial);
	
	return Plugin_Continue;
}

public void Store_OnClientLoadoutChanged(int client)
{
	Store_GetEquippedItemsByType(Store_GetClientAccountID(client), "skin", Store_GetClientLoadout(client), OnGetPlayerSkin, GetClientSerial(client));
}

public void OnGetPlayerSkin(int[] ids, int count, any serial)
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
	
	int team = GetClientTeam(client);
	for (int i = 0; i < count; i++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(ids[i], itemName, sizeof(itemName));
		
		int skin = -1;
		if (!GetTrieValue(g_skinNameIndex, itemName, skin))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			continue;
		}

		bool teamAllowed;
		for (int x = 0; x < 5; x++)
		{
			if (g_skins[skin][SkinTeams][x] == team)
			{
				teamAllowed = true;
				break;
			}
		}

		if (!teamAllowed)
		{
			continue;
		}

		if (StrEqual(g_game, "tf"))
		{
			SetVariantString(g_skins[skin][SkinModelPath]);
			AcceptEntityInput(client, "SetCustomModel");
			SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
		}
		else
		{
			SetEntityModel(client, g_skins[skin][SkinModelPath]);
		}
	}
}

public void Store_OnReloadItems() 
{
	ClearTrie(g_skinNameIndex);
	
	g_skinCount = 0;
	
	Store_RegisterItemType("skin", OnEquip, LoadItem);
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_skins[g_skinCount][SkinName], STORE_MAX_NAME_LENGTH, itemName);

	SetTrieValue(g_skinNameIndex, g_skins[g_skinCount][SkinName], g_skinCount);

	Handle json = DecodeJSON(attrs);
	JSONGetString(json, "model", g_skins[g_skinCount][SkinModelPath], PLATFORM_MAX_PATH);

	if (strcmp(g_skins[g_skinCount][SkinModelPath], "") != 0 && (FileExists(g_skins[g_skinCount][SkinModelPath]) || FileExists(g_skins[g_skinCount][SkinModelPath], true)))
	{
		PrecacheModel(g_skins[g_skinCount][SkinModelPath]);
		Downloader_AddFileToDownloadsTable(g_skins[g_skinCount][SkinModelPath]);
	}

	Handle teams;
	JSONGetObject(json, "teams", teams);
	
	int size = GetJSONArraySize(teams);
	
	for (int i = 0; i < size; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));
		
		JSONGetInteger(teams, sID, g_skins[g_skinCount][SkinTeams][i]);
	}

	DestroyJSON(json);

	g_skinCount++;
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	if (equipped)
	{
		return Store_UnequipItem;
	}
	
	PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item apply next spawn");
	return Store_EquipItem;
}