#pragma semicolon 1

#include <sourcemod>
#include <store>

#define PLUGIN_NAME "[Store] Shop Module"
#define PLUGIN_DESCRIPTION "Shop module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_shop_version"

//Config Globals
new bool:g_confirmItemPurchase = false;
new bool:g_hideEmptyCategories = false;
new bool:g_showCategoryDescriptions = true;
new bool:g_allowBuyingDuplicates = false;
new bool:g_equipAfterPurchase = true;
new String:sPriority_Categories[256];
new String:sPriority_Items[256];

new String:g_currencyName[64];

new Handle:g_buyItemForward;
new Handle:g_buyItemPostForward;

new Handle:categories_menu[MAXPLAYERS + 1];
new iLeft[MAXPLAYERS + 1] =  { 0, ... };

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = STORE_AUTHORS,
	description = PLUGIN_DESCRIPTION,
	version = STORE_VERSION,
	url = STORE_URL
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("Store_OpenShop", Native_OpenShop);
	CreateNative("Store_OpenShopCategory", Native_OpenShopCategory);
	
	g_buyItemForward = CreateGlobalForward("Store_OnBuyItem", ET_Event, Param_Cell, Param_Cell);
	g_buyItemPostForward = CreateGlobalForward("Store_OnBuyItem_Post", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	RegPluginLibrary("store-shop");
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	LoadConfig();
}

public Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Shop", "Shop Description", _, OnMainMenuShopClick, 2);
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
	BuildPath(Path_SM, path, sizeof(path), "configs/store/shop.cfg");

	if (!FileToKeyValues(kv, path))
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	new String:menuCommands[255];
	KvGetString(kv, "shop_commands", menuCommands, sizeof(menuCommands), "!shop /shop");
	Store_RegisterChatCommands(menuCommands, ChatCommand_OpenShop);

	g_confirmItemPurchase = bool:KvGetNum(kv, "confirm_item_purchase", 0);
	g_hideEmptyCategories = bool:KvGetNum(kv, "hide_empty_categories", 0);
	g_showCategoryDescriptions = bool:KvGetNum(kv, "show_category_descriptions", 1);
	g_allowBuyingDuplicates = bool:KvGetNum(kv, "allow_buying_duplicates", 0);
	g_equipAfterPurchase = bool:KvGetNum(kv, "equip_after_purchase", 1);
	
	if (KvJumpToKey(kv, "Menu Sorting"))
	{
		if (KvJumpToKey(kv, "Categories") && KvGotoFirstSubKey(kv, false))
		{
			CreatePriorityString(kv, sPriority_Categories, sizeof(sPriority_Categories));
			KvGoBack(kv);
		}
		
		if (KvJumpToKey(kv, "Items") && KvGotoFirstSubKey(kv, false))
		{
			CreatePriorityString(kv, sPriority_Items, sizeof(sPriority_Items));
			KvGoBack(kv);
		}
		
		KvGoBack(kv);
	}

	CloseHandle(kv);
	
	Store_AddMainMenuItem("Shop", "Shop Description", _, OnMainMenuShopClick, 2);
}

CreatePriorityString(Handle:hKV, String:sPriority[], maxsize)
{
	Format(sPriority, maxsize, "ORDER BY ");
	
	do {
		new String:sName[256];
		KvGetSectionName(hKV, sName, sizeof(sName));
		
		new String:sValue[256];
		KvGetString(hKV, NULL_STRING, sValue, sizeof(sValue));
		
		new String:sSource[256];
		Format(sSource, sizeof(sSource), "%s %s, ", sValue, sName);
		
		StrCat(sPriority, maxsize, sSource);
		
	} while (KvGotoNextKey(hKV, false));
	KvGoBack(hKV);
	
	Format(sPriority, maxsize, "%s;", sPriority);
	ReplaceString(sPriority, maxsize, ", ;", ";");
}

public OnMainMenuShopClick(client, const String:value[])
{
	OpenShop(client);
}

public ChatCommand_OpenShop(client)
{
	OpenShop(client);
}

OpenShop(client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || categories_menu[client] != INVALID_HANDLE)
	{
		return;
	}
	
	Store_GetCategories(GetCategoriesCallback, true, sPriority_Categories, GetClientUserId(client));
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
	
	categories_menu[client] = CreateMenu(ShopMenuSelectHandle);
	SetMenuTitle(categories_menu[client], "%T\n \n", "Shop", client);
	
	new bool:bNoCategories = true;
	for (new category = 0; category < count; category++)
	{
		new String:requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));
		
		if (strlen(requiredPlugin) == 0 || !Store_IsItemTypeRegistered(requiredPlugin))
		{
			iLeft[client] = count - category - 1;
			CheckLeft(client);
			continue;
		}
		
		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, GetClientUserId(client));
		WritePackCell(hPack, ids[category]);
		iLeft[client] = count - category - 1;

		new Handle:filter = CreateTrie();
		SetTrieValue(filter, "is_buyable", 1);
		SetTrieValue(filter, "category_id", ids[category]);
		SetTrieValue(filter, "flags", GetUserFlagBits(client));

		Store_GetItems(filter, GetItemsForCategoryCallback, true, sPriority_Items, hPack);
		bNoCategories = false;
	}
	
	if (bNoCategories)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No categories available");
	}
}

public GetItemsForCategoryCallback(ids[], count, any:hPack)
{
	ResetPack(hPack);

	new client = GetClientOfUserId(ReadPackCell(hPack));
	new categoryId = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (!g_hideEmptyCategories || count > 0)
	{
		new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetCategoryDisplayName(categoryId, sDisplayName, sizeof(sDisplayName));
		
		new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetCategoryDescription(categoryId, sDescription, sizeof(sDescription));
		
		new String:sDisplay[sizeof(sDisplayName) + 1 + sizeof(sDescription)];
		Format(sDisplay, sizeof(sDisplay), "%s", sDisplayName);

		if (g_showCategoryDescriptions)
		{
			Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplay, sDescription);
		}

		new String:sItem[12];
		IntToString(categoryId, sItem, sizeof(sItem));

		AddMenuItem(categories_menu[client], sItem, sDisplay);
	}
	
	CheckLeft(client);
}

CheckLeft(client)
{
	if (iLeft[client] <= 0)
	{
		SetMenuExitBackButton(categories_menu[client], true);
		DisplayMenu(categories_menu[client], client, 0);
		categories_menu[client] = INVALID_HANDLE;
	}
}

public ShopMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				OpenShopCategory(client, StringToInt(sMenuItem));
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

OpenShopCategory(client, categoryId)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackCell(hPack, categoryId);

	new Handle:filter = CreateTrie();
	SetTrieValue(filter, "is_buyable", 1);
	SetTrieValue(filter, "category_id", categoryId);
	SetTrieValue(filter, "flags", GetUserFlagBits(client));

	Store_GetItems(filter, GetItemsCallback, true, sPriority_Items, hPack);
}

public GetItemsCallback(ids[], count, any:hPack)
{
	ResetPack(hPack);

	new client = GetClientOfUserId(ReadPackCell(hPack));
	new categoryId = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (!client || !IsClientInGame(client))
	{
		return;
	}
	
	if (count == 0)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No items in this category");
		OpenShop(client);

		return;
	}

	new String:categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));

	new Handle:menu = CreateMenu(ShopCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Shop", client, categoryDisplayName);

	for (new item = 0; item < count; item++)
	{
		new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], sDisplayName, sizeof(sDisplayName));
		
		new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetItemDescription(ids[item], sDescription, sizeof(sDescription));
		
		new String:sDisplay[sizeof(sDisplayName) + sizeof(sDescription) + 5];
		Format(sDisplay, sizeof(sDisplay), "%s [%d %s]", sDisplayName, Store_GetItemPrice(ids[item]), g_currencyName);

		if (g_showCategoryDescriptions)
		{
			Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplay, sDescription);
		}

		new String:sItem[12];
		IntToString(ids[item], sItem, sizeof(sItem));

		AddMenuItem(menu, sItem, sDisplay);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public ShopCategoryMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				DoBuyItem(client, StringToInt(sMenuItem));
			}
		case MenuAction_Cancel:
			{
				if (slot == MenuCancel_ExitBack)
				{
					OpenShop(client);
				}
			}
		case MenuAction_End: CloseHandle(menu);
	}
}

DoBuyItem(client, itemId, bool:confirmed = false, bool:checkeddupes = false)
{
	if (g_confirmItemPurchase && !confirmed)
	{
		DisplayConfirmationMenu(client, itemId);
	}
	else if (!g_allowBuyingDuplicates && !checkeddupes)
	{
		new String:itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(itemId, itemName, sizeof(itemName));

		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, GetClientUserId(client));
		WritePackCell(hPack, itemId);

		Store_GetUserItemCount(GetSteamAccountID(client), itemName, DoBuyItem_ItemCountCallBack, hPack);
	}
	else
	{
		new Action:result = Plugin_Continue;

		Call_StartForward(g_buyItemForward);
		Call_PushCell(client);
		Call_PushCell(itemId);
		Call_Finish(_:result);

		if (result == Plugin_Handled || result == Plugin_Stop)
		{
			return;
		}

		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, GetClientUserId(client));
		WritePackCell(hPack, itemId);

		Store_BuyItem(GetSteamAccountID(client), itemId, OnBuyItemComplete, hPack);
	}
}

public DoBuyItem_ItemCountCallBack(count, any:hPack)
{
	ResetPack(hPack);

	new client = GetClientOfUserId(ReadPackCell(hPack));
	new itemId = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (count <= 0)
	{
		DoBuyItem(client, itemId, true, true);
	}
	else
	{
		new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		CPrintToChat(client, "%t%t", "Store Tag Colored", "Already purchased item", displayName);
	}
}

DisplayConfirmationMenu(client, itemId)
{
	new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));

	new Handle:menu = CreateMenu(ConfirmationMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Item Purchase Confirmation", client,  displayName);

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
					OpenShop(client);
				}
				else
				{
					DoBuyItem(client, StringToInt(sMenuItem), true);
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
		case MenuAction_Cancel: OpenShop(client);
		case MenuAction_End: CloseHandle(menu);
	}

	return false;
}

public OnBuyItemComplete(bool:success, any:hPack)
{
	ResetPack(hPack);

	new client = GetClientOfUserId(ReadPackCell(hPack));
	new itemId = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (!success)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "Not enough credits to buy", g_currencyName);
		return;
	}
		
	new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
	CPrintToChat(client, "%t%t", "Store Tag Colored", "Item Purchase Successful", displayName);
	
	if (g_equipAfterPurchase)
	{
		new Handle:hMenu = CreateMenu(EquipAfterPurchaseMenuHandle);
		SetMenuTitle(hMenu, "%t", "Item Purchase Menu Title", displayName);
		
		new String:sItemID[64];
		IntToString(itemId, sItemID, sizeof(sItemID));
		
		AddMenuItem(hMenu, sItemID, "Yes");
		AddMenuItem(hMenu, "", "No");
		
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
	else
	{	
		OpenShop(client);
	}

	Call_StartForward(g_buyItemPostForward);
	Call_PushCell(client);
	Call_PushCell(itemId);
	Call_PushCell(success);
	Call_Finish();
}

public EquipAfterPurchaseMenuHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64], String:sDisplay[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem), _, sDisplay, sizeof(sDisplay));
				
				if (StrEqual(sDisplay, "Yes"))
				{
					new loadout = Store_GetClientLoadout(client);
					new itemId = StringToInt(sMenuItem);
					Store_SetItemEquippedState(GetSteamAccountID(client), itemId, loadout, true, EquipItemCallback);
					
					new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
					Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
					
					CPrintToChat(client, "%t%t", "Store Tag Colored", "Item Purchase Equipped", displayName, loadout);
				}
				
				OpenShop(client);
			}
		case MenuAction_End: CloseHandle(menu);
	}
}

public EquipItemCallback(accountId, itemId, loadoutId, any:data)
{
	
}

public Native_OpenShop(Handle:plugin, params)
{
	OpenShop(GetNativeCell(1));
}

public Native_OpenShopCategory(Handle:plugin, params)
{
	OpenShopCategory(GetNativeCell(1), GetNativeCell(2));
}
