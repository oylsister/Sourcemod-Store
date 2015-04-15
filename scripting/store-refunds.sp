#pragma semicolon 1

#include <sourcemod>
#include <store>

#define PLUGIN_NAME "[Store] Refunds Module"
#define PLUGIN_DESCRIPTION "Refunds module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_refunds_version"

//Config Globals
new Float:g_refundPricePercentage = 0.5;
new bool:g_confirmItemRefund = true;
new bool:g_ShowMenuDescriptions = true;
new bool:g_showMenuItemDescriptions = true;

new String:g_currencyName[64];

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
	
	LoadConfig();
}

public Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Refund", "Refund Description", _, OnMainMenuRefundClick, 6);
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
	BuildPath(Path_SM, path, sizeof(path), "configs/store/refund.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	new String:menuCommands[255];
	KvGetString(kv, "refund_commands", menuCommands, sizeof(menuCommands), "!refund /refund !sell /sell");
	Store_RegisterChatCommands(menuCommands, ChatCommand_OpenRefund);
	
	g_refundPricePercentage = KvGetFloat(kv, "refund_price_percentage", 0.5);
	g_confirmItemRefund = bool:KvGetNum(kv, "confirm_item_refund", 1);
	g_ShowMenuDescriptions = bool:KvGetNum(kv, "show_menu_descriptions", 1);
	g_showMenuItemDescriptions = bool:KvGetNum(kv, "show_menu_item_descriptions", 1);

	CloseHandle(kv);
	
	Store_AddMainMenuItem("Refund", "Refund Description", _, OnMainMenuRefundClick, 6);
}

public OnMainMenuRefundClick(client, const String:value[])
{
	OpenRefundMenu(client);
}

public ChatCommand_OpenRefund(client)
{
	OpenRefundMenu(client);
}

OpenRefundMenu(client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}
	
	Store_GetCategories(GetCategoriesCallback, true, "", GetClientUserId(client));
}

public GetCategoriesCallback(ids[], count, any:data)
{		
	new client = GetClientOfUserId(data);
	
	if (!client)
	{
		return;
	}
	
	if (count < 1)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No categories available");
		return;
	}
		
	new Handle:menu = CreateMenu(RefundMenuSelectHandle);
	SetMenuTitle(menu, "%T\n \n", "Refund", client);
	
	new bool:bNoCategories = true;
	for (new category = 0; category < count; category++)
	{
		new String:requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));
		
		if (!StrEqual(requiredPlugin, "") && !Store_IsItemTypeRegistered(requiredPlugin))
		{
			continue;
		}
			
		new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetCategoryDisplayName(ids[category], sDisplayName, sizeof(sDisplayName));

		new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetCategoryDescription(ids[category], sDescription, sizeof(sDescription));

		new String:sDisplay[sizeof(sDisplayName) + 1 + sizeof(sDescription)];
		Format(sDisplay, sizeof(sDisplay), "%s", sDisplayName);
		
		if (g_ShowMenuDescriptions)
		{
			Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplayName, sDescription);
		}
		
		new String:sItem[12];
		IntToString(ids[category], sItem, sizeof(sItem));
		
		AddMenuItem(menu, sItem, sDisplay);
		bNoCategories = false;
	}
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
	
	if (bNoCategories)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No categories available");
	}
}

public RefundMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				OpenRefundCategory(client, StringToInt(sMenuItem));
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

OpenRefundCategory(client, categoryId, slot = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackCell(hPack, categoryId);
	WritePackCell(hPack, slot);

	new Handle:filter = CreateTrie();
	SetTrieValue(filter, "is_refundable", 1);
	SetTrieValue(filter, "category_id", categoryId);

	Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetUserItemsCallback, hPack);
}

public GetUserItemsCallback(ids[], bool:equipped[], itemCount[], count, loadoutId, any:hPack)
{	
	ResetPack(hPack);
	
	new client = GetClientOfUserId(ReadPackCell(hPack));
	new categoryId = ReadPackCell(hPack);
	new slot = ReadPackCell(hPack);
	
	CloseHandle(hPack);
		
	if (!client || !IsClientInGame(client))
	{
		return;
	}
		
	if (count == 0)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No items in this category");
		OpenRefundMenu(client);
		
		return;
	}
	
	new String:categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));
		
	new Handle:menu = CreateMenu(RefundCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Refund", client, categoryDisplayName);
	
	for (new item = 0; item < count; item++)
	{
		new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], sDisplayName, sizeof(sDisplayName));
		
		new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetItemDescription(ids[item], sDescription, sizeof(sDescription));
		
		new String:sDisplay[4 + sizeof(sDisplayName) + sizeof(sDescription)+ 6];
		Format(sDisplay, sizeof(sDisplay), "%s", sDisplayName);
		
		if (itemCount[item] > 1)
		{
			Format(sDisplay, sizeof(sDisplay), "%s (%d)", sDisplay, itemCount[item]);
		}
		
		Format(sDisplay, sizeof(sDisplay), "%s - %d %s", sDisplay, RoundToZero(Store_GetItemPrice(ids[item]) * g_refundPricePercentage), g_currencyName);
		
		if (g_showMenuItemDescriptions && strlen(sDisplay) != 0)
		{
			Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplay, sDescription);
		}
		
		new String:sItem[12];
		IntToString(ids[item], sItem, sizeof(sItem));
		
		AddMenuItem(menu, sItem, sDisplay);    
	}

	SetMenuExitBackButton(menu, true);
	
	if (slot != 0)
	{
		DisplayMenuAtItem(menu, client, slot, MENU_TIME_FOREVER);
		return;
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public RefundCategoryMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				switch (g_confirmItemRefund)
				{
					case true: DisplayConfirmationMenu(client, StringToInt(sMenuItem));
					case false: Store_RemoveUserItem(GetSteamAccountID(client), StringToInt(sMenuItem), OnRemoveUserItemComplete, GetClientUserId(client));
				}
			}
		case MenuAction_Cancel: OpenRefundMenu(client);
		case MenuAction_End: CloseHandle(menu);
	}
}

DisplayConfirmationMenu(client, itemId)
{
	new String:displayName[64];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));

	new Handle:menu = CreateMenu(ConfirmationMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Item Refund Confirmation", client, displayName, RoundToZero(Store_GetItemPrice(itemId) * g_refundPricePercentage), g_currencyName);

	new String:value[8];
	IntToString(itemId, value, sizeof(value));

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "no", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, 0);  
}

public ConfirmationMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				if (StrEqual(sMenuItem, "no"))
				{
					OpenRefundMenu(client);
				}
				else
				{
					Store_RemoveUserItem(GetSteamAccountID(client), StringToInt(sMenuItem), OnRemoveUserItemComplete, GetClientUserId(client));
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
		case MenuAction_Cancel: OpenRefundMenu(client);
		case MenuAction_End: CloseHandle(menu);
	}

	return false;
}

public OnRemoveUserItemComplete(accountId, itemId, any:data)
{
	new client = GetClientOfUserId(data);

	if (client == 0)
	{
		return;
	}
	
	new credits = RoundToZero(Store_GetItemPrice(itemId) * g_refundPricePercentage);

	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackCell(hPack, itemId);

	Store_GiveCredits(accountId, credits, OnGiveCreditsComplete, hPack);
}

public OnGiveCreditsComplete(accountId, credits, any:hPack)
{
	ResetPack(hPack);

	new client = GetClientOfUserId(ReadPackCell(hPack));
	new itemId = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (!client || !IsClientInGame(client))
	{
		return;
	}
	
	new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
	CPrintToChat(client, "%t%t", "Store Tag Colored", "Refund Message", displayName, credits, g_currencyName);

	OpenRefundMenu(client);
}