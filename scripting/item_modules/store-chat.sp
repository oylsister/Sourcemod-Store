#pragma semicolon 1

#include <sourcemod>
#include <scp>
#include <multicolors>
#include <EasyJSON>

//Store Includes
#include <store/store-core>
#include <store/store-inventory>
#include <store/store-loadouts>

Handle g_hTitleNames;
Handle g_hTitleData;
Handle g_hNameColors;
Handle g_hNameData;
Handle g_hChatColors;
Handle g_hChatData;

int g_clientTitles[MAXPLAYERS + 1] = { -1, ... };
int g_clientNameColors[MAXPLAYERS + 1] = { -1, ... };
int g_clientChatColors[MAXPLAYERS + 1] = { -1, ... };

Handle g_titlesNameIndex;
Handle g_namecolorsNameIndex;
Handle g_chatcolorsNameIndex;

public Plugin myinfo =
{
	name        = "[Store] Chat",
	author      = "Panduh, Revamped by Keith Warren (Drixevel)",
	description = "Titles and colors for store system.",
	version     = "1.0.0",
	url         = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	g_titlesNameIndex = CreateTrie();
	g_namecolorsNameIndex = CreateTrie();
	g_chatcolorsNameIndex = CreateTrie();
	
	g_hTitleNames = CreateArray(ByteCountToCells(STORE_MAX_NAME_LENGTH));
	g_hTitleData = CreateTrie();
	
	g_hNameColors = CreateArray(ByteCountToCells(STORE_MAX_NAME_LENGTH));
	g_hNameData = CreateTrie();
	
	g_hChatColors = CreateArray(ByteCountToCells(STORE_MAX_NAME_LENGTH));
	g_hChatData = CreateTrie();
}

public void OnConfigsExecuted()
{
	RegisterAllItemTypes();
}

public OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store-inventory"))
	{
		RegisterAllItemTypes();
	}	
}

public Store_OnReloadItems()
{
	ClearTrie(g_titlesNameIndex);
	ClearTrie(g_namecolorsNameIndex);
	ClearTrie(g_chatcolorsNameIndex);
	
	RegisterAllItemTypes();
}

void RegisterAllItemTypes()
{
	Store_RegisterItemType("title", OnTitleLoad, OnTitleLoadItem);
	Store_RegisterItemType("namecolor", OnNameEquip, OnLoadNameItem);
	Store_RegisterItemType("chatcolor", OnChatEquip, OnLoadChatItem);	
}

public void OnClientPostAdminCheck(int client)
{
	VerifyLoadouts(client);
}

public void Store_OnClientLoadoutChanged(int client)
{
	VerifyLoadouts(client);
}

void VerifyLoadouts(int client)
{
	g_clientTitles[client] = -1;
	g_clientNameColors[client] = -1;
	g_clientChatColors[client] = -1;
	
	int iAccount = Store_GetClientAccountID(client);
	int iLoadout = Store_GetClientLoadout(client);
	int iUserID = GetClientUserId(client);
	
	Store_GetEquippedItemsByType(iAccount, "title", iLoadout, OnGetPlayerTitle, iUserID);
	Store_GetEquippedItemsByType(iAccount, "namecolor", iLoadout, OnGetPlayerNameColor, iUserID);
	Store_GetEquippedItemsByType(iAccount, "chatcolor", iLoadout, OnGetPlayerChatColor, iUserID);
}

public void OnGetPlayerTitle(int[] titles, int count, any data)
{
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
		
	for (int i = 0; i < count; i++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(titles[i], itemName, sizeof(itemName));
		
		int title = -1;
		if (!GetTrieValue(g_titlesNameIndex, itemName, title))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			continue;
		}
		
		g_clientTitles[client] = title;
		break;
	}
}

public void OnGetPlayerNameColor(int[] titles, int count, any data)
{
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
		
	for (int i = 0; i < count; i++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(titles[i], itemName, sizeof(itemName));
		
		int namecolor = -1;
		if (!GetTrieValue(g_namecolorsNameIndex, itemName, namecolor))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			continue;
		}
		
		g_clientNameColors[client] = namecolor;
		break;
	}
}

public void OnGetPlayerChatColor(int[] titles, int count, any data)
{
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
		
	for (new i = 0; i < count; i++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(titles[i], itemName, sizeof(itemName));
		
		int chatcolor = -1;
		if (!GetTrieValue(g_chatcolorsNameIndex, itemName, chatcolor))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			continue;
		}
		
		g_clientChatColors[client] = chatcolor;
		break;
	}
}

public void OnTitleLoadItem(const char[] itemName, const char[] attrs)
{
	PushArrayString(g_hTitleNames, itemName);
	
	Handle json = DecodeJSON(attrs);	

	char sTitle[64];
	if (IsSource2009())
	{
		JSONGetString(json, "colorful_text", sTitle, sizeof(sTitle));
		CFormatColor(sTitle, sizeof(sTitle));
	}
	else
	{
		JSONGetString(json, "text", sTitle, sizeof(sTitle));
		C_Format(sTitle, sizeof(sTitle));
	}
	
	SetTrieString(g_hTitleData, itemName, sTitle);

	DestroyJSON(json);
}

public void OnLoadNameItem(const char[] itemName, const char[] attrs)
{
	PushArrayString(g_hNameColors, itemName);
	
	Handle json = DecodeJSON(attrs);	
	
	char sNameColor[64];
	if (IsSource2009())
	{
		JSONGetString(json, "color", sNameColor, sizeof(sNameColor));
		CFormatColor(sNameColor, sizeof(sNameColor));
	}
	else
	{
		JSONGetString(json, "text", sNameColor, sizeof(sNameColor));
		C_Format(sNameColor, sizeof(sNameColor));
	}
	
	SetTrieString(g_hNameData, itemName, sNameColor);

	DestroyJSON(json);
}

public void OnLoadChatItem(const char[] itemName, const char[] attrs)
{
	PushArrayString(g_hChatColors, itemName);
	
	Handle json = DecodeJSON(attrs);	
	
	char sChatColor[64];
	if (IsSource2009())
	{
		JSONGetString(json, "color", sChatColor, sizeof(sChatColor));
		CFormatColor(sChatColor, sizeof(sChatColor));
	}
	else
	{
		JSONGetString(json, "text", sChatColor, sizeof(sChatColor));
		C_Format(sChatColor, sizeof(sChatColor));
	}
	
	SetTrieString(g_hChatData, itemName, sChatColor);

	DestroyJSON(json);
}

public Store_ItemUseAction OnTitleLoad(int client, int itemId, bool equipped)
{
	char name[32];
	Store_GetItemName(itemId, name, sizeof(name));

	if (equipped)
	{
		g_clientTitles[client] = -1;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);

		return Store_UnequipItem;
	}
	else
	{
		int title = -1;
		if (!GetTrieValue(g_titlesNameIndex, name, title))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			return Store_DoNothing;
		}
		
		g_clientTitles[client] = title;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);

		return Store_EquipItem;
	}
}

public Store_ItemUseAction OnNameEquip(int client, int itemId, bool equipped)
{
	char name[32];
	Store_GetItemName(itemId, name, sizeof(name));

	if (equipped)
	{
		g_clientNameColors[client] = -1;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);

		return Store_UnequipItem;
	}
	else
	{
		int namecolor = -1;
		if (!GetTrieValue(g_namecolorsNameIndex, name, namecolor))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			return Store_DoNothing;
		}
		
		g_clientNameColors[client] = namecolor;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);

		return Store_EquipItem;
	}
}

public Store_ItemUseAction OnChatEquip(int client, int itemId, bool equipped)
{
	char name[32];
	Store_GetItemName(itemId, name, sizeof(name));

	if (equipped)
	{
		g_clientChatColors[client] = -1;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);

		return Store_UnequipItem;
	}
	else
	{
		int chatcolor = -1;
		if (!GetTrieValue(g_chatcolorsNameIndex, name, chatcolor))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			return Store_DoNothing;
		}
		
		g_clientChatColors[client] = chatcolor;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);

		return Store_EquipItem;
	}
}

public Action OnChatMessage(int& author, Handle recipients, char[] name, char[] message)
{
	bool bChanged;
	char sNewName[MAXLENGTH_NAME];
	
	int iTitle = g_clientTitles[author];
	if (iTitle != -1)
	{
		char sItemName[STORE_MAX_NAME_LENGTH];
		GetArrayString(g_hTitleNames, iTitle, sItemName, sizeof(sItemName));
		
		char sTitle[STORE_MAX_NAME_LENGTH];
		GetTrieString(g_hTitleData, sItemName, sTitle, sizeof(sTitle));
		
		Format(sNewName, sizeof(sNewName), "%s", sTitle);
		bChanged = true;
	}
	
	int iNameColor = g_clientNameColors[author];
	if (iNameColor != -1)
	{
		char sItemName[STORE_MAX_NAME_LENGTH];
		GetArrayString(g_hNameColors, iNameColor, sItemName, sizeof(sItemName));
		
		char sNameColor[STORE_MAX_NAME_LENGTH];
		GetTrieString(g_hNameData, sItemName, sNameColor, sizeof(sNameColor));
		
		Format(sNameColor, sizeof(sNameColor), "%s%s%s", strlen(sNameColor) > 6 ? "\x08" : "\x07", sNameColor, name);
		
		StrCat(sNewName, MAXLENGTH_NAME, sNameColor);
		bChanged = true;
		
		strcopy(name, MAXLENGTH_NAME, sNewName);
	}
	else if (iTitle != -1)
	{
		StrCat(sNewName, MAXLENGTH_NAME, name);
		bChanged = true;
		
		strcopy(name, MAXLENGTH_NAME, sNewName);
	}
	
	int iChatColor = g_clientChatColors[author];
	if (iChatColor != -1)
	{
		char sItemName[STORE_MAX_NAME_LENGTH];
		GetArrayString(g_hChatColors, iNameColor, sItemName, sizeof(sItemName));
		
		char sChatColor[STORE_MAX_NAME_LENGTH];
		GetTrieString(g_hChatData, sItemName, sChatColor, sizeof(sChatColor));
		
		Format(sChatColor, sizeof(sChatColor), "%s%s%s", strlen(sChatColor) > 6 ? "\x08" : "\x07", sChatColor, message);
		strcopy(message, MAXLENGTH_MESSAGE, sChatColor);
		bChanged = true;
	}
	
	return bChanged ? Plugin_Changed : Plugin_Continue;
}