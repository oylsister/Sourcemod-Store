#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <adminmenu>
#include <store>
#include <smartdm>

#define PLUGIN_NAME "[Store] Gifting Module"
#define PLUGIN_DESCRIPTION "Gifting module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_gifting_version"

#define MAX_CREDIT_CHOICES 100

enum Present
{
	Present_Owner,
	String:Present_Data[64]
}

enum GiftAction
{
	GiftAction_Send,
	GiftAction_Drop
}

enum GiftType
{
	GiftType_Credits,
	GiftType_Item
}

enum GiftRequest
{
	bool:GiftRequestActive,
	GiftRequestSender,
	GiftType:GiftRequestType,
	GiftRequestValue
}

new String:g_currencyName[64];

new g_creditChoices[MAX_CREDIT_CHOICES];
new g_giftRequests[MAXPLAYERS+1][GiftRequest];

new g_spawnedPresents[2048][Present];
new String:g_itemModel[32];
new String:g_creditsModel[32];
new bool:g_drop_enabled;

new String:g_game[32];

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = STORE_AUTHORS,
	description = PLUGIN_DESCRIPTION,
	version = STORE_VERSION,
	url = STORE_URL
};

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	GetGameFolderName(g_game, sizeof(g_game));
	
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	
	LoadConfig();
}

public Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Gift", "Gift Description", _, OnMainMenuGiftClick, 5);
}

public OnConfigsExecuted()
{    
	Store_GetCurrencyName(g_currencyName, sizeof(g_currencyName));
}

public Store_OnDatabaseInitialized()
{
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
}

LoadConfig() 
{
	new Handle:kv = CreateKeyValues("root");
	
	new String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/gifting.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}
	
	new String:creditChoices[MAX_CREDIT_CHOICES][10];

	new String:creditChoicesString[255];
	KvGetString(kv, "credits_choices", creditChoicesString, sizeof(creditChoicesString));

	new choices = ExplodeString(creditChoicesString, " ", creditChoices, sizeof(creditChoices), sizeof(creditChoices[]));
	
	for (new choice = 0; choice < choices; choice++)
	{
		g_creditChoices[choice] = StringToInt(creditChoices[choice]);
	}
	
	g_drop_enabled = bool:KvGetNum(kv, "drop_enabled", 0);

	if (g_drop_enabled)
	{
		KvGetString(kv, "itemModel", g_itemModel, sizeof(g_itemModel), "");
		KvGetString(kv, "creditsModel", g_creditsModel, sizeof(g_creditsModel), "");

		if (!g_itemModel[0] || !FileExists(g_itemModel, true))
		{
			if (StrEqual(g_game, "cstrike"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/cs_gift.mdl");
			}
			else if (StrEqual(g_game, "tf"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/tf_gift.mdl");
			}
			else if (StrEqual(g_game, "dod"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/dod_gift.mdl");
			}
			else
			{
				g_drop_enabled = false;
			}
		}
	}
	
	if (KvJumpToKey(kv, "Commands"))
	{
		new String:sBuffer[256];
		KvGetString(kv, "gifting_commands", sBuffer, sizeof(sBuffer), "!gift /gift");
		Store_RegisterChatCommands(sBuffer, ChatCommand_Gift);
		
		KvGetString(kv, "accept_commands", sBuffer, sizeof(sBuffer), "!accept /accept");
		Store_RegisterChatCommands(sBuffer, ChatCommand_Accept);
		
		KvGetString(kv, "cancel_commands", sBuffer, sizeof(sBuffer), "!cancel /cancel");
		Store_RegisterChatCommands(sBuffer, ChatCommand_Cancel);
		
		if (g_drop_enabled)
		{
			if (!g_creditsModel[0] || !FileExists(g_creditsModel, true))
			{
				strcopy(g_creditsModel,sizeof(g_creditsModel),g_itemModel);
			}
			
			KvGetString(kv, "drop_commands", sBuffer, sizeof(sBuffer), "!drop /drop");
			Store_RegisterChatCommands(sBuffer, ChatCommand_Drop);
		}
	}

	CloseHandle(kv);
	
	Store_AddMainMenuItem("Gift", "Gift Description", _, OnMainMenuGiftClick, 5);
}

public OnMapStart()
{
	if (!g_drop_enabled)
	{
		return;
	}
		
	PrecacheModel(g_itemModel, true);
		
	Downloader_AddFileToDownloadsTable(g_itemModel);
	
	if (!StrEqual(g_itemModel, g_creditsModel))
	{
		PrecacheModel(g_creditsModel, true);
		Downloader_AddFileToDownloadsTable(g_creditsModel);
	}
}

public DropGetCreditsCallback(credits, any:pack)
{
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	new needed = ReadPackCell(pack);

	if (credits >= needed)
	{
		Store_RemoveCredits(GetSteamAccountID(client), needed, DropGiveCreditsCallback, pack);
	}
	else
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Not enough credits", g_currencyName);
	}
}

public DropGiveCreditsCallback(accountId, any:pack)
{
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	new credits = ReadPackCell(pack);
	
	CloseHandle(pack);

	new String:value[32];
	Format(value, sizeof(value), "credits,%d", credits);

	CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Credits Dropped", credits, g_currencyName);

	new present;
	if ((present = SpawnPresent(client, g_creditsModel)) != -1)
	{
		strcopy(g_spawnedPresents[present][Present_Data], 64, value);
		g_spawnedPresents[present][Present_Owner] = client;
	}
}

public OnMainMenuGiftClick(client, const String:value[])
{
	OpenGiftingMenu(client);
}

public Action:Event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast) 
{ 
	g_giftRequests[GetClientOfUserId(GetEventInt(event, "userid"))][GiftRequestActive] = false;
}

public ChatCommand_Gift(client)
{
	OpenGiftingMenu(client);
}

public ChatCommand_Accept(client)
{
	if (!g_giftRequests[client][GiftRequestActive])
	{
		return;
	}

	if (g_giftRequests[client][GiftRequestType] == GiftType_Credits)
	{
		GiftCredits(g_giftRequests[client][GiftRequestSender], client, g_giftRequests[client][GiftRequestValue]);
	}
	else
	{
		GiftItem(g_giftRequests[client][GiftRequestSender], client, g_giftRequests[client][GiftRequestValue]);
	}
	
	g_giftRequests[client][GiftRequestActive] = false;
}

public ChatCommand_Cancel(client)
{
	if (g_giftRequests[client][GiftRequestActive])
	{
		g_giftRequests[client][GiftRequestActive] = false;
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Cancel");
	}
}

public ChatCommand_Drop(client, const String:command[], const String:args[])
{
	if (strlen(args) <= 0)
	{
		if (command[0] == 0x2F)
		{
			CPrintToChat(client, "%sUsage: %s <%s>", STORE_PREFIX, command, g_currencyName);
		}
		else
		{
			CPrintToChatAll("%sUsage: %s <%s>", STORE_PREFIX, command, g_currencyName);
		}
		
		return;
	}

	new credits = StringToInt(args);

	if (credits < 1)
	{
		if (command[0] == 0x2F)
		{
			CPrintToChat(client, "%s%d is not a valid amount!", STORE_PREFIX, credits);
		}
		else
		{
			CPrintToChatAll("%s%d is not a valid amount!", STORE_PREFIX, credits);
		}
		
		return;
	}

	new Handle:pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, credits);

	Store_GetCredits(GetSteamAccountID(client), DropGetCreditsCallback, pack);
}

OpenGiftingMenu(client)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		
		if (g_giftRequests[i][GiftRequestActive] && g_giftRequests[i][GiftRequestSender] == client)
		{
			CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Active Session");
			return;
		}
	}

	new Handle:menu = CreateMenu(GiftTypeMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Gift Type Menu Title", client);

	new String:item[32];
	Format(item, sizeof(item), "%T", "Item", client);

	AddMenuItem(menu, "credits", g_currencyName);
	AddMenuItem(menu, "item", item);
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public GiftTypeMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:giftType[10];
			if (GetMenuItem(menu, slot, giftType, sizeof(giftType)))
			{
				if (StrEqual(giftType, "credits"))
				{
					if (g_drop_enabled)
					{
						OpenChooseActionMenu(client, GiftType_Credits);
					}
					else
					{
						OpenChoosePlayerMenu(client, GiftType_Credits);
					}
				}
				else if (StrEqual(giftType, "item"))
				{
					if (g_drop_enabled)
					{
						OpenChooseActionMenu(client, GiftType_Item);
					}
					else
					{
						OpenChoosePlayerMenu(client, GiftType_Item);
					}
				}
			}
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				Store_OpenMainMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}
}

OpenChooseActionMenu(client, GiftType:giftType)
{
	new Handle:menu = CreateMenu(ChooseActionMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Gift Delivery Method", client);

	new String:s_giftType[32];
	if (giftType == GiftType_Credits)
	strcopy(s_giftType, sizeof(s_giftType), "credits");
	else if (giftType == GiftType_Item)
	strcopy(s_giftType, sizeof(s_giftType), "item");

	new String:send[32], String:drop[32];
	Format(send, sizeof(send), "%s,send", s_giftType);
	Format(drop, sizeof(drop), "%s,drop", s_giftType);

	new String:methodSend[32], String:methodDrop[32];
	Format(methodSend, sizeof(methodSend), "%T", "Gift Method Send", client);
	Format(methodDrop, sizeof(methodDrop), "%T", "Gift Method Drop", client);

	AddMenuItem(menu, send, methodSend);
	AddMenuItem(menu, drop, methodDrop);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public ChooseActionMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:values[32];
			if (GetMenuItem(menu, slot, values, sizeof(values)))
			{
				new String:brokenValues[2][32];
				ExplodeString(values, ",", brokenValues, sizeof(brokenValues), sizeof(brokenValues[]));

				new GiftType:giftType;

				if (StrEqual(brokenValues[0], "credits"))
				{
					giftType = GiftType_Credits;
				}
				else if (StrEqual(brokenValues[0], "item"))
				{
					giftType = GiftType_Item;
				}

				if (StrEqual(brokenValues[1], "send"))
				{
					OpenChoosePlayerMenu(client, giftType);
				}
				else if (StrEqual(brokenValues[1], "drop"))
				{
					if (giftType == GiftType_Item)
					{
						OpenSelectItemMenu(client, GiftAction_Drop, -1);
					}
					else if (giftType == GiftType_Credits)
					{
						OpenSelectCreditsMenu(client, GiftAction_Drop, -1);
					}
				}
			}
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}
}

OpenChoosePlayerMenu(client, GiftType:giftType)
{
	new Handle:menu;
	
	switch (giftType)
	{
		case GiftType_Credits: menu = CreateMenu(ChoosePlayerCreditsMenuSelectHandle);
		case GiftType_Item: menu = CreateMenu(ChoosePlayerItemMenuSelectHandle);
		default: return;
	}

	SetMenuTitle(menu, "Select Player:\n \n");

	AddTargetsToMenu2(menu, 0, COMMAND_FILTER_NO_BOTS);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

public ChoosePlayerCreditsMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
			OpenSelectCreditsMenu(client, GiftAction_Send, GetClientOfUserId(StringToInt(sMenuItem)));
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}
}

public ChoosePlayerItemMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
			OpenSelectItemMenu(client, GiftAction_Send, GetClientOfUserId(StringToInt(sMenuItem)));
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}
}

OpenSelectCreditsMenu(client, GiftAction:giftAction, giftTo = -1)
{
	if (giftAction == GiftAction_Send && giftTo == -1)
	{
		return;
	}

	new Handle:menu = CreateMenu(CreditsMenuSelectItem);

	SetMenuTitle(menu, "Select %s:", g_currencyName);

	for (new choice = 0; choice < sizeof(g_creditChoices); choice++)
	{
		if (g_creditChoices[choice] == 0) continue;

		new String:text[48];
		IntToString(g_creditChoices[choice], text, sizeof(text));

		new String:value[32];
		Format(value, sizeof(value), "%d,%d,%d", _:giftAction, giftTo, g_creditChoices[choice]);

		AddMenuItem(menu, value, text);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public CreditsMenuSelectItem(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
			
			new String:values[3][16];
			ExplodeString(sMenuItem, ",", values, sizeof(values), sizeof(values[]));
				
			new giftAction = _:StringToInt(values[0]);
			new giftTo = StringToInt(values[1]);
			new credits = StringToInt(values[2]);
			
			new Handle:pack = CreateDataPack();
			WritePackCell(pack, client);
			WritePackCell(pack, giftAction);
			WritePackCell(pack, giftTo);
			WritePackCell(pack, credits);
			
			Store_GetCredits(GetSteamAccountID(client), GetCreditsCallback, pack);
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}
}

public GetCreditsCallback(credits, any:pack)
{
	ResetPack(pack);

	new client = ReadPackCell(pack);
	new GiftAction:giftAction = GiftAction:ReadPackCell(pack);
	new giftTo = ReadPackCell(pack);
	new giftCredits = ReadPackCell(pack);

	CloseHandle(pack);

	if (giftCredits > credits)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Not enough credits", g_currencyName);
	}
	else
	{
		OpenGiveCreditsConfirmMenu(client, giftAction, giftTo, giftCredits);
	}
}

OpenGiveCreditsConfirmMenu(client, GiftAction:giftAction, giftTo, credits)
{
	new Handle:menu = CreateMenu(CreditsConfirmMenuSelectItem);
	new String:value[32];
	
	switch (giftAction)
	{
	case GiftAction_Send:
		{
			new String:name[32];
			GetClientName(giftTo, name, sizeof(name));
			SetMenuTitle(menu, "%T", "Gift Credit Confirmation", client, name, credits, g_currencyName);
			Format(value, sizeof(value), "%d,%d,%d", _:giftAction, giftTo, credits);
		}
	case GiftAction_Drop:
		{
			SetMenuTitle(menu, "%T", "Drop Credit Confirmation", client, credits, g_currencyName);
			Format(value, sizeof(value), "%d,%d,%d", _:giftAction, giftTo, credits);
		}
	}

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);  
}

public CreditsConfirmMenuSelectItem(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
			if (!StrEqual(sMenuItem, ""))
			{
				new String:values[3][16];
				ExplodeString(sMenuItem, ",", values, sizeof(values), sizeof(values[]));

				new GiftAction:giftAction = GiftAction:StringToInt(values[0]);
				new giftTo = StringToInt(values[1]);
				new credits = StringToInt(values[2]);

				if (giftAction == GiftAction_Send)
				{
					AskForPermission(client, giftTo, GiftType_Credits, credits);
				}
				else if (giftAction == GiftAction_Drop)
				{
					new String:data[32];
					Format(data, sizeof(data), "credits,%d", credits);

					new Handle:pack = CreateDataPack();
					WritePackCell(pack, client);
					WritePackCell(pack, credits);

					Store_GetCredits(GetSteamAccountID(client), DropGetCreditsCallback, pack);
				}
			}
		}
	case MenuAction_DisplayItem:
		{
			new String:sDisplay[64];
			GetMenuItem(menu, slot, "", 0, _, sDisplay, sizeof(sDisplay));

			new String:buffer[255];
			Format(buffer, sizeof(buffer), "%T", sDisplay, client);

			return RedrawMenuItem(buffer);
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenChoosePlayerMenu(client, GiftType_Credits);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}

	return false;
}

OpenSelectItemMenu(client, GiftAction:giftAction, giftTo = -1)
{
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, _:giftAction);
	WritePackCell(pack, giftTo);

	new Handle:filter = CreateTrie();
	SetTrieValue(filter, "is_tradeable", 1);

	Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetUserItemsCallback, pack);
}

public GetUserItemsCallback(ids[], bool:equipped[], itemCount[], count, loadoutId, any:pack)
{		
	ResetPack(pack);
	
	new serial = ReadPackCell(pack);
	new GiftAction:giftAction = GiftAction:ReadPackCell(pack);
	new giftTo = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	new client = GetClientFromSerial(serial);
	
	if (!client)
	{
		return;
	}
	
	if (count == 0)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "No items");	
		return;
	}
	
	new Handle:menu = CreateMenu(ItemMenuSelectHandle);
	SetMenuTitle(menu, "Select item:\n \n");
	
	for (new item = 0; item < count; item++)
	{
		new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], displayName, sizeof(displayName));
		
		new String:text[4 + sizeof(displayName) + 6];
		Format(text, sizeof(text), "%s%s", text, displayName);
		
		if (itemCount[item] > 1)
		{
			Format(text, sizeof(text), "%s (%d)", text, itemCount[item]);
		}
		
		new String:value[32];
		Format(value, sizeof(value), "%d,%d,%d", _:giftAction, giftTo, ids[item]);
		
		AddMenuItem(menu, value, text);    
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public ItemMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
			OpenGiveItemConfirmMenu(client, sMenuItem);
		}
	case MenuAction_Cancel: OpenGiftingMenu(client); //OpenChoosePlayerMenu(client, GiftType_Item);
	case MenuAction_End: CloseHandle(menu);
	}
}

OpenGiveItemConfirmMenu(client, const String:value[])
{
	new String:values[3][16];
	ExplodeString(value, ",", values, sizeof(values), sizeof(values[]));

	new GiftAction:giftAction = GiftAction:StringToInt(values[0]);
	new giftTo = StringToInt(values[1]);
	new itemId = StringToInt(values[2]);

	new String:name[32];
	if (giftAction == GiftAction_Send)
	{
		GetClientName(giftTo, name, sizeof(name));
	}

	new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));

	new Handle:menu = CreateMenu(ItemConfirmMenuSelectItem);
	switch (giftAction)
	{
	case GiftAction_Send: SetMenuTitle(menu, "%T", "Gift Item Confirmation", client, name, displayName);
	case GiftAction_Drop: SetMenuTitle(menu, "%T", "Drop Item Confirmation", client, displayName);
	}

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public ItemConfirmMenuSelectItem(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
	case MenuAction_Select:
		{
			new String:sMenuItem[64];
			GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
			
			if (strlen(sMenuItem) != 0)
			{
				new String:values[3][16];
				ExplodeString(sMenuItem, ",", values, sizeof(values), sizeof(values[]));

				new GiftAction:giftAction = GiftAction:StringToInt(values[0]);
				new giftTo = StringToInt(values[1]);
				new itemId = StringToInt(values[2]);
				
				switch (giftAction)
				{
				case GiftAction_Send: AskForPermission(client, giftTo, GiftType_Item, itemId);
				case GiftAction_Drop:
					{
						new present = SpawnPresent(client, g_itemModel);
						if (IsValidEntity(present))
						{
							new String:data[32];
							Format(data, sizeof(data), "item,%d", itemId);

							strcopy(g_spawnedPresents[present][Present_Data], 64, data);
							g_spawnedPresents[present][Present_Owner] = client;

							Store_RemoveUserItem(GetSteamAccountID(client), itemId, DropItemCallback, client);
						}
					}
				}
			}
		}
	case MenuAction_DisplayItem:
		{
			new String:sDisplay[64];
			GetMenuItem(menu, slot, "", 0, _, sDisplay, sizeof(sDisplay));

			new String:buffer[255];
			Format(buffer, sizeof(buffer), "%T", sDisplay, client);

			return RedrawMenuItem(buffer);
		}
	case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
	case MenuAction_End: CloseHandle(menu);
	}

	return false;
}

public DropItemCallback(accountId, itemId, any:client)
{
	new String:displayName[64];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
	CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Item Dropped", displayName);
}

AskForPermission(client, giftTo, GiftType:giftType, value)
{
	new String:giftToName[32];
	GetClientName(giftTo, giftToName, sizeof(giftToName));

	CPrintToChatEx(client, giftTo, "%s%t", STORE_PREFIX, "Gift Waiting to accept", client, giftToName);

	new String:clientName[32];
	GetClientName(client, clientName, sizeof(clientName));	

	new String:what[64];

	if (giftType == GiftType_Credits)
	{
		Format(what, sizeof(what), "%d %s", value, g_currencyName);
	}
	else if (giftType == GiftType_Item)
	{
		Store_GetItemDisplayName(value, what, sizeof(what));	
	}
	
	CPrintToChatEx(giftTo, client, "%s%t", STORE_PREFIX, "Gift Request Accept", client, clientName, what);

	g_giftRequests[giftTo][GiftRequestActive] = true;
	g_giftRequests[giftTo][GiftRequestSender] = client;
	g_giftRequests[giftTo][GiftRequestType] = giftType;
	g_giftRequests[giftTo][GiftRequestValue] = value;
}

GiftCredits(from, to, amount)
{
	Store_LogInfo("Client %L is giving currency %i to client %L.", from, amount, to);
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, from);
	WritePackCell(pack, to);
	WritePackCell(pack, amount);
	
	Store_RemoveCredits(GetSteamAccountID(from), amount, TakeCreditsCallback, pack);
}

public TakeCreditsCallback(accountId, any:pack)
{
	ResetPack(pack);
	
	new from = ReadPackCell(pack);
	new to = ReadPackCell(pack);
	new amount = ReadPackCell(pack);
	
	if (from > 0){}

	Store_GiveCredits(GetSteamAccountID(to), amount, GiveCreditsCallback, pack);
}

public GiveCreditsCallback(accountId, any:pack)
{
	ResetPack(pack);

	new from = ReadPackCell(pack);
	new to = ReadPackCell(pack);

	CloseHandle(pack);

	new String:receiverName[32];
	GetClientName(to, receiverName, sizeof(receiverName));	

	CPrintToChatEx(from, to, "%s%t", STORE_PREFIX, "Gift accepted - sender", receiverName);

	new String:senderName[32];
	GetClientName(from, senderName, sizeof(senderName));

	CPrintToChatEx(to, from, "%s%t", STORE_PREFIX, "Gift accepted - receiver", senderName);
}

GiftItem(from, to, itemId)
{
	Store_LogInfo("Client %L is giving ItemID %i to client %L.", from, itemId, to);
	
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, from);
	WritePackCell(pack, to);
	WritePackCell(pack, itemId);

	Store_RemoveUserItem(GetSteamAccountID(from), itemId, RemoveUserItemCallback, pack);
}

public RemoveUserItemCallback(accountId, itemId, any:pack)
{
	ResetPack(pack);

	new from = ReadPackCell(pack);
	new to = ReadPackCell(pack);
	
	if (from > 0){}

	Store_GiveItem(GetSteamAccountID(to), itemId, Store_Gift, GiveCreditsCallback, pack);
}

SpawnPresent(owner, const String:model[])
{
	new present = CreateEntityByName("prop_physics_override");

	if (IsValidEntity(present))
	{
		new String:targetname[100];

		Format(targetname, sizeof(targetname), "gift_%i", present);

		DispatchKeyValue(present, "model", model);
		DispatchKeyValue(present, "physicsmode", "2");
		DispatchKeyValue(present, "massScale", "1.0");
		DispatchKeyValue(present, "targetname", targetname);
		DispatchSpawn(present);
		
		SetEntProp(present, Prop_Send, "m_usSolidFlags", 8);
		SetEntProp(present, Prop_Send, "m_CollisionGroup", 1);
		
		new Float:pos[3];
		GetClientAbsOrigin(owner, pos);
		pos[2] += 16;

		TeleportEntity(present, pos, NULL_VECTOR, NULL_VECTOR);
		
		new rotator = CreateEntityByName("func_rotating");
		DispatchKeyValueVector(rotator, "origin", pos);
		DispatchKeyValue(rotator, "targetname", targetname);
		DispatchKeyValue(rotator, "maxspeed", "200");
		DispatchKeyValue(rotator, "friction", "0");
		DispatchKeyValue(rotator, "dmg", "0");
		DispatchKeyValue(rotator, "solid", "0");
		DispatchKeyValue(rotator, "spawnflags", "64");
		DispatchSpawn(rotator);
		
		SetVariantString("!activator");
		AcceptEntityInput(present, "SetParent", rotator, rotator);
		AcceptEntityInput(rotator, "Start");
		
		SetEntPropEnt(present, Prop_Send, "m_hEffectEntity", rotator);

		SDKHook(present, SDKHook_StartTouch, OnStartTouch);
	}
	
	return present;
}

public OnStartTouch(present, client)
{
	if (!(0 < client <= MaxClients) || g_spawnedPresents[present][Present_Owner] == client)
	{
		return;
	}

	new rotator = GetEntPropEnt(present, Prop_Send, "m_hEffectEntity");
	
	if (rotator && IsValidEdict(rotator))
	{
		AcceptEntityInput(rotator, "Kill");
	}
	
	AcceptEntityInput(present, "Kill");
	
	new String:values[2][16];
	ExplodeString(g_spawnedPresents[present][Present_Data], ",", values, sizeof(values), sizeof(values[]));
	
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackString(pack,values[0]);
	
	if (StrEqual(values[0],"credits"))
	{
		new credits = StringToInt(values[1]);
		WritePackCell(pack, credits);
		Store_GiveCredits(GetSteamAccountID(client), credits, PickupGiveCallback, pack);
	}
	else if (StrEqual(values[0], "item"))
	{
		new itemId = StringToInt(values[1]);
		WritePackCell(pack, itemId);
		Store_GiveItem(GetSteamAccountID(client), itemId, Store_Gift, PickupGiveCallback, pack);
	}
}

public PickupGiveCallback(accountId, any:pack)
{
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	
	new String:itemType[32];
	ReadPackString(pack, itemType, sizeof(itemType));
	
	new value = ReadPackCell(pack);

	if (StrEqual(itemType, "credits"))
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Credits Found", value, g_currencyName); //translate
		Store_LogInfo("Client successfully picked up %i %s as a gift.", value, g_currencyName);
	}
	else if (StrEqual(itemType, "item"))
	{
		new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(value, displayName, sizeof(displayName));
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Gift Item Found", displayName); //translate
		Store_LogInfo("Client successfully picked up the item %s as a gift.", displayName);
	}
}
