#pragma semicolon 1

#include <sourcemod>
#include <store>

#define PLUGIN_NAME "[Store] Shop Module"
#define PLUGIN_DESCRIPTION "Shop module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_shop_version"

new String:g_currencyName[64];

new bool:g_hideEmptyCategories = false;
new bool:g_confirmItemPurchase = false;
new bool:g_allowBuyingDuplicates = false;
new bool:g_hideCategoryDescriptions = false;
new bool:g_equipAfterPurchase = false;

new String:sPriority_Categories[256];
new String:sPriority_Items[256];

new Handle:g_buyItemForward;
new Handle:g_buyItemPostForward;

new Handle:categories_menu[MAXPLAYERS+1];

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
	g_hideCategoryDescriptions = bool:KvGetNum(kv, "hide_category_descriptions", 0);
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
	
	Store_GetCategories(GetCategoriesCallback, true, sPriority_Categories, GetClientSerial(client));
}

public GetCategoriesCallback(ids[], count, any:serial)
{
	new client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return;
	}
		
	if (count < 1)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "No categories available");
		return;
	}
	
	categories_menu[client] = CreateMenu(ShopMenuSelectHandle);
	SetMenuTitle(categories_menu[client], "%T\n \n", "Shop", client);
	
	new bool:bNoCategories = true;
	for (new category = 0; category < count; category++)
	{
		new String:requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));

		if (!StrEqual(requiredPlugin, "") && !Store_IsItemTypeRegistered(requiredPlugin))
		{
			continue;
		}

		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackCell(pack, ids[category]);
		WritePackCell(pack, count - category - 1);

		new Handle:filter = CreateTrie();
		SetTrieValue(filter, "is_buyable", 1);
		SetTrieValue(filter, "category_id", ids[category]);
		SetTrieValue(filter, "flags", GetUserFlagBits(client));

		Store_GetItems(filter, GetItemsForCategoryCallback, true, sPriority_Items, pack);
		bNoCategories = false;
	}
	
	if (bNoCategories)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "No categories available");
	}
}

public GetItemsForCategoryCallback(ids[], count, any:pack)
{
	ResetPack(pack);

	new serial = ReadPackCell(pack);
	new categoryId = ReadPackCell(pack);
	new left = ReadPackCell(pack);

	CloseHandle(pack);

	new client = GetClientFromSerial(serial);
	
	if (client == 0)
	{
		return;
	}

	if (!g_hideEmptyCategories || count > 0)
	{
		new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetCategoryDisplayName(categoryId, displayName, sizeof(displayName));

		if (!g_hideCategoryDescriptions)
		{
			new String:description[STORE_MAX_DESCRIPTION_LENGTH];
			Store_GetCategoryDescription(categoryId, description, sizeof(description));

			new String:itemText[sizeof(displayName) + 1 + sizeof(description)];
			Format(itemText, sizeof(itemText), "%s\n%s", displayName, description);
		}

		new String:itemValue[8];
		IntToString(categoryId, itemValue, sizeof(itemValue));

		AddMenuItem(categories_menu[client], itemValue, displayName);
	}

	if (left == 0)
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
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, categoryId);

	new Handle:filter = CreateTrie();
	SetTrieValue(filter, "is_buyable", 1);
	SetTrieValue(filter, "category_id", categoryId);
	SetTrieValue(filter, "flags", GetUserFlagBits(client));

	Store_GetItems(filter, GetItemsCallback, true, sPriority_Items, pack);
}

public GetItemsCallback(ids[], count, any:pack)
{
	ResetPack(pack);

	new serial = ReadPackCell(pack);
	new categoryId = ReadPackCell(pack);

	CloseHandle(pack);

	new client = GetClientFromSerial(serial);

	if (client == 0)
	{
		return;
	}
	
	if (count == 0)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "No items in this category");
		OpenShop(client);

		return;
	}

	new String:categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));

	new Handle:menu = CreateMenu(ShopCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Shop", client, categoryDisplayName);

	for (new item = 0; item < count; item++)
	{
		new String:displayName[64];
		new String:description[128];
		new String:text[sizeof(displayName) + sizeof(description) + 5];

		Store_GetItemDisplayName(ids[item], displayName, sizeof(displayName));

		if (!g_hideCategoryDescriptions)
		{
			Store_GetItemDescription(ids[item], description, sizeof(description));
			Format(text, sizeof(text), "%s [%d %s]\n%s", displayName, Store_GetItemPrice(ids[item]), g_currencyName, description);
		}
		else
		{
			Format(text, sizeof(text), "%s [%d %s]", displayName, Store_GetItemPrice(ids[item]), g_currencyName);
		}

		new String:value[8];
		IntToString(ids[item], value, sizeof(value));

		AddMenuItem(menu, value, text);
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

		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackCell(pack, itemId);

		Store_GetUserItemCount(GetSteamAccountID(client), itemName, DoBuyItem_ItemCountCallBack, pack);
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

		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackCell(pack, itemId);

		Store_BuyItem(GetSteamAccountID(client), itemId, OnBuyItemComplete, pack);
	}
}

public DoBuyItem_ItemCountCallBack(count, any:pack)
{
	ResetPack(pack);

	new client = GetClientFromSerial(ReadPackCell(pack));
	new itemId = ReadPackCell(pack);

	CloseHandle(pack);
	
	if (!client)
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
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Already purchased item", displayName);
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

public OnBuyItemComplete(bool:success, any:pack)
{
	ResetPack(pack);

	new client = GetClientFromSerial(ReadPackCell(pack));
	new itemId = ReadPackCell(pack);

	CloseHandle(pack);
	
	if (!client)
	{
		return;
	}

	if (!success)
	{
		CPrintToChat(client, "%s%t", STORE_PREFIX, "Not enough credits to buy", g_currencyName);
		return;
	}
		
	new String:displayName[64];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
	CPrintToChat(client, "%s%t", STORE_PREFIX, "Item Purchase Successful", displayName);
	
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
					
					new String:displayName[64];
					Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
					
					CPrintToChat(client, "%s%t", STORE_PREFIX, "Item Purchase Equipped", displayName, loadout);
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
