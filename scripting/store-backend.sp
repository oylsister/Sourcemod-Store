#pragma semicolon 1

#include <sourcemod>
#include <store>

#define PLUGIN_NAME "[Store] Backend Module"
#define PLUGIN_DESCRIPTION "Backend module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_backend_version"

#define MAX_CATEGORIES	32
#define MAX_ITEMS 		1024
#define MAX_LOADOUTS	32
#define MAX_QUERY_SIZES	2048

enum Category
{
	CategoryId,
	CategoryPriority,
	String:CategoryDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH],
	String:CategoryDescription[STORE_MAX_DESCRIPTION_LENGTH],
	String:CategoryRequirePlugin[STORE_MAX_REQUIREPLUGIN_LENGTH]
}

enum Item
{
	ItemId,
	ItemPriority,
	String:ItemName[STORE_MAX_NAME_LENGTH],
	String:ItemDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH],
	String:ItemDescription[STORE_MAX_DESCRIPTION_LENGTH],
	String:ItemType[STORE_MAX_TYPE_LENGTH],
	String:ItemLoadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH],
	ItemPrice,
	ItemCategoryId,
	bool:ItemIsBuyable,
	bool:ItemIsTradeable,
	bool:ItemIsRefundable,
	ItemFlags
}

enum Loadout
{
	LoadoutId,
	String:LoadoutDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH],
	String:LoadoutGame[STORE_MAX_LOADOUTGAME_LENGTH],
	String:LoadoutClass[STORE_MAX_LOADOUTCLASS_LENGTH],
	LoadoutTeam
}

new Handle:g_dbInitializedForward;
new Handle:g_reloadItemsForward;
new Handle:g_reloadItemsPostForward;

new Handle:g_hSQL;
new g_reconnectCounter = 0;

new g_categories[MAX_CATEGORIES][Category];
new g_categoryCount = -1;

new g_items[MAX_ITEMS][Item];
new g_itemCount = -1;

new g_loadouts[MAX_LOADOUTS][Loadout];
new g_loadoutCount = -1;

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
	CreateNative("Store_Register", Native_Register);
	CreateNative("Store_RegisterClient", Native_RegisterClient);
	CreateNative("Store_GetClientAccountID", Native_GetClientAccountID);

	CreateNative("Store_GetCategories", Native_GetCategories);
	CreateNative("Store_GetCategoryPriority", Native_GetCategoryPriority);
	CreateNative("Store_GetCategoryDisplayName", Native_GetCategoryDisplayName);
	CreateNative("Store_GetCategoryDescription", Native_GetCategoryDescription);
	CreateNative("Store_GetCategoryPluginRequired", Native_GetCategoryPluginRequired);

	CreateNative("Store_GetItems", Native_GetItems);
	CreateNative("Store_GetItemPriority", Native_GetItemPriority);
	CreateNative("Store_GetItemName", Native_GetItemName);
	CreateNative("Store_GetItemDisplayName", Native_GetItemDisplayName);
	CreateNative("Store_GetItemDescription", Native_GetItemDescription);
	CreateNative("Store_GetItemType", Native_GetItemType);
	CreateNative("Store_GetItemLoadoutSlot", Native_GetItemLoadoutSlot);
	CreateNative("Store_GetItemPrice", Native_GetItemPrice);
	CreateNative("Store_GetItemCategory", Native_GetItemCategory);
	CreateNative("Store_IsItemBuyable", Native_IsItemBuyable);
	CreateNative("Store_IsItemTradeable", Native_IsItemTradeable);
	CreateNative("Store_IsItemRefundable", Native_IsItemRefundable);
	CreateNative("Store_GetItemAttributes", Native_GetItemAttributes);
	CreateNative("Store_WriteItemAttributes", Native_WriteItemAttributes);

	CreateNative("Store_GetLoadouts", Native_GetLoadouts);
	CreateNative("Store_GetLoadoutDisplayName", Native_GetLoadoutDisplayName);
	CreateNative("Store_GetLoadoutGame", Native_GetLoadoutGame);
	CreateNative("Store_GetLoadoutClass", Native_GetLoadoutClass);
	CreateNative("Store_GetLoadoutTeam", Native_GetLoadoutTeam);

	CreateNative("Store_GetUserItems", Native_GetUserItems);
	CreateNative("Store_GetUserItemCount", Native_GetUserItemCount);
	CreateNative("Store_GetCredits", Native_GetCredits);
	CreateNative("Store_GetCreditsEx", Native_GetCreditsEx);

	CreateNative("Store_GiveCredits", Native_GiveCredits);
	CreateNative("Store_GiveCreditsToUsers", Native_GiveCreditsToUsers);
	CreateNative("Store_GiveDifferentCreditsToUsers", Native_GiveDifferentCreditsToUsers);
	CreateNative("Store_GiveItem", Native_GiveItem);
	
	CreateNative("Store_RemoveCredits", Native_RemoveCredits);
	CreateNative("Store_RemoveCreditsFromUsers", Native_RemoveCreditsFromUsers);

	CreateNative("Store_BuyItem", Native_BuyItem);
	CreateNative("Store_RemoveUserItem", Native_RemoveUserItem);

	CreateNative("Store_SetItemEquippedState", Native_SetItemEquippedState);
	CreateNative("Store_GetEquippedItemsByType", Native_GetEquippedItemsByType);

	CreateNative("Store_ReloadItemCache", Native_ReloadItemCache);
	CreateNative("Store_RegisterPluginModule", Native_RegisterPluginModule);
	
	CreateNative("Store_SQLTQuery", Native_SQLTQuery);
	
	g_dbInitializedForward = CreateGlobalForward("Store_OnDatabaseInitialized", ET_Event);
	g_reloadItemsForward = CreateGlobalForward("Store_OnReloadItems", ET_Event);
	g_reloadItemsPostForward = CreateGlobalForward("Store_OnReloadItemsPost", ET_Event);

	RegPluginLibrary("store-backend");
	return APLRes_Success;
}

public OnPluginStart()
{
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	RegAdminCmd("store_reloaditems", Command_ReloadItems, ADMFLAG_RCON, "Reloads store item cache.");
	RegAdminCmd("sm_store_reloaditems", Command_ReloadItems, ADMFLAG_RCON, "Reloads store item cache.");
	RegAdminCmd("sm_native_credits", Command_TestCreditsNative, ADMFLAG_RCON);
}

public OnAllPluginsLoaded()
{
	ConnectSQL();
}

public OnPluginEnd()
{
	Store_LogWarning("WARNING: Please change the map or restart the server, you cannot reload store-backend while the map is loaded. (CRASH WARNING)");
}

public OnMapStart()
{
	if (g_hSQL != INVALID_HANDLE)
	{
		ReloadItemCache(-1);
	}
}

Register(accountId, const String:name[] = "", credits = 0)
{
	new String:safeName[2 * 32 + 1];
	SQL_EscapeString(g_hSQL, name, safeName, sizeof(safeName));

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "INSERT INTO store_users (auth, name, credits) VALUES (%d, '%s', %d) ON DUPLICATE KEY UPDATE name = '%s';", accountId, safeName, credits, safeName);
	SQL_TQuery(g_hSQL, T_RegisterCallback, sQuery, _, DBPrio_High);
	Store_LogTrace("[SQL Query] Register - %s", sQuery);
}

RegisterClient(client, credits = 0)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}
		
	new String:name[64];
	GetClientName(client, name, sizeof(name));

	Register(GetSteamAccountID(client), name, credits);
}

public T_RegisterCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on Register: %s", error);
	}
}

GetCategories(client, Store_GetItemsCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, bool:loadFromCache = true, String:sPriority[], any:data = 0)
{
	if (loadFromCache && g_categoryCount != -1)
	{
		if (callback == INVALID_FUNCTION)
		{
			return;
		}

		new categories[g_categoryCount];
		new count = 0;

		for (new category = 0; category < g_categoryCount; category++)
		{
			categories[count] = g_categories[category][CategoryId];
			count++;
		}

		Call_StartFunction(plugin, callback);
		Call_PushArray(categories, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
		
		new String:sName[MAX_NAME_LENGTH];
		if (client > 0) GetClientName(client, sName, sizeof(sName));
		
		Store_LogDebug("Categories Pulled for '%s': Count = %i - LoadFromCache: %s - Priority String: %s", strlen(sName) != 0 ? sName: "Console", count, loadFromCache ? "True" : "False", strlen(sPriority) != 0 ? sPriority : "N/A");
	}
	else
	{
		new Handle:hPack = CreateDataPack();
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, _:plugin);
		WritePackCell(hPack, _:data);
		
		new String:sQuery[MAX_QUERY_SIZES];
		Format(sQuery, sizeof(sQuery), "SELECT id, priority, display_name, description, require_plugin FROM store_categories %s", sPriority);
		SQL_TQuery(g_hSQL, T_GetCategoriesCallback, sQuery, hPack);
		Store_LogTrace("[SQL Query] GetCategories - %s", sQuery);
	}
	
	if (client != -1)
	{
		CReplyToCommand(client, "%t%t", (client != 0) ? "Store Tag Colored" : "Store Tag", "Reloaded categories");
	}
}

public T_GetCategoriesCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(hPack);
		Store_LogError("SQL Error on GetCategories: %s", error);
		return;
	}

	ResetPack(hPack);

	new Store_GetItemsCallback:callback = Store_GetItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	g_categoryCount = 0;

	while (SQL_FetchRow(hndl))
	{
		g_categories[g_categoryCount][CategoryId] = SQL_FetchInt(hndl, 0);
		g_categories[g_categoryCount][CategoryPriority] = SQL_FetchInt(hndl, 1);
		SQL_FetchString(hndl, 2, g_categories[g_categoryCount][CategoryDisplayName], STORE_MAX_DISPLAY_NAME_LENGTH);
		SQL_FetchString(hndl, 3, g_categories[g_categoryCount][CategoryDescription], STORE_MAX_DESCRIPTION_LENGTH);
		SQL_FetchString(hndl, 4, g_categories[g_categoryCount][CategoryRequirePlugin], STORE_MAX_REQUIREPLUGIN_LENGTH);

		g_categoryCount++;
	}

	GetCategories(-1, callback, plugin, true, "", arg);
}

GetCategoryIndex(id)
{
	for (new index = 0; index < g_categoryCount; index++)
	{
		if (g_categories[index][CategoryId] == id)
		{
			return index;
		}
	}

	return -1;
}

GetItems(client, Handle:filter = INVALID_HANDLE, Store_GetItemsCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, bool:loadFromCache = true, const String:sPriority[], any:data = 0)
{
	if (loadFromCache && g_itemCount != -1)
	{
		if (callback == INVALID_FUNCTION)
		{
			return;
		}
		
		new categoryId;
		new bool:categoryFilter = filter == INVALID_HANDLE ? false : GetTrieValue(filter, "category_id", categoryId);

		new bool:isBuyable;
		new bool:buyableFilter = filter == INVALID_HANDLE ? false : GetTrieValue(filter, "is_buyable", isBuyable);

		new bool:isTradeable;
		new bool:tradeableFilter = filter == INVALID_HANDLE ? false : GetTrieValue(filter, "is_tradeable", isTradeable);

		new bool:isRefundable;
		new bool:refundableFilter = filter == INVALID_HANDLE ? false : GetTrieValue(filter, "is_refundable", isRefundable);

		new String:type[STORE_MAX_TYPE_LENGTH];
		new bool:typeFilter = filter == INVALID_HANDLE ? false : GetTrieString(filter, "type", type, sizeof(type));

		new flags;
		new bool:flagsFilter = filter == INVALID_HANDLE ? false : GetTrieValue(filter, "flags", flags);

		CloseHandle(filter);

		new items[g_itemCount];
		
		new count = 0;
		
		for (new item = 0; item < g_itemCount; item++)
		{
			if ((!categoryFilter || categoryId == g_items[item][ItemCategoryId]) && (!buyableFilter || isBuyable == g_items[item][ItemIsBuyable]) && (!tradeableFilter || isTradeable == g_items[item][ItemIsTradeable]) && (!refundableFilter || isRefundable == g_items[item][ItemIsRefundable]) && (!typeFilter || StrEqual(type, g_items[item][ItemType])) && (!flagsFilter || !g_items[item][ItemFlags] || (flags & g_items[item][ItemFlags])))
			{
				items[count] = g_items[item][ItemId];
				count++;
			}
		}

		Call_StartFunction(plugin, callback);
		Call_PushArray(items, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
		
		new String:sName[MAX_NAME_LENGTH];
		if (client > 0) GetClientName(client, sName, sizeof(sName));
		
		Store_LogDebug("Items Pulled for '%s': Count = %i - LoadFromCache: %s - Priority String: %s", strlen(sName) != 0 ? sName : "Console", count, loadFromCache ? "True" : "False", strlen(sPriority) != 0 ? sPriority : "N/A");
	}
	else
	{
		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, _:filter);
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, _:plugin);
		WritePackCell(hPack, _:data);
		
		new String:sQuery[MAX_QUERY_SIZES];
		Format(sQuery, sizeof(sQuery), "SELECT id, priority, name, display_name, description, type, loadout_slot, price, category_id, attrs, LENGTH(attrs) AS attrs_len, is_buyable, is_tradeable, is_refundable, flags FROM store_items ORDER BY price, display_name %s", sPriority);
		SQL_TQuery(g_hSQL, T_GetItemsCallback, sQuery, hPack);
		Store_LogTrace("[SQL Query] GetItems - %s", sQuery);
	}
	
	if (client != -1)
	{
		CReplyToCommand(client, "%t%t", (client != 0) ? "Store Tag Colored" : "Store Tag", "Reloaded items");
	}
}

public T_GetItemsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(hPack);
		Store_LogError("SQL Error on GetItems: %s", error);
		return;
	}

	Call_StartForward(g_reloadItemsForward);
	Call_Finish();
	
	ResetPack(hPack);
	
	new Handle:filter = Handle:ReadPackCell(hPack);
	new Store_GetItemsCallback:callback = Store_GetItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	g_itemCount = 0;

	while (SQL_FetchRow(hndl))
	{
		g_items[g_itemCount][ItemId] = SQL_FetchInt(hndl, 0);
		g_items[g_itemCount][ItemPriority] = SQL_FetchInt(hndl, 1);
		SQL_FetchString(hndl, 2, g_items[g_itemCount][ItemName], STORE_MAX_NAME_LENGTH);
		SQL_FetchString(hndl, 3, g_items[g_itemCount][ItemDisplayName], STORE_MAX_DISPLAY_NAME_LENGTH);
		SQL_FetchString(hndl, 4, g_items[g_itemCount][ItemDescription], STORE_MAX_DESCRIPTION_LENGTH);
		SQL_FetchString(hndl, 5, g_items[g_itemCount][ItemType], STORE_MAX_TYPE_LENGTH);
		SQL_FetchString(hndl, 6, g_items[g_itemCount][ItemLoadoutSlot], STORE_MAX_LOADOUTSLOT_LENGTH);
		g_items[g_itemCount][ItemPrice] = SQL_FetchInt(hndl, 7);
		g_items[g_itemCount][ItemCategoryId] = SQL_FetchInt(hndl, 8);

		if (!SQL_IsFieldNull(hndl, 9))
		{
			new attrsLength = SQL_FetchInt(hndl, 10);

			new String:attrs[attrsLength+1];
			SQL_FetchString(hndl, 9, attrs, attrsLength+1);

			Store_CallItemAttrsCallback(g_items[g_itemCount][ItemType], g_items[g_itemCount][ItemName], attrs);
		}

		g_items[g_itemCount][ItemIsBuyable] = bool:SQL_FetchInt(hndl, 11);
		g_items[g_itemCount][ItemIsTradeable] = bool:SQL_FetchInt(hndl, 12);
		g_items[g_itemCount][ItemIsRefundable] = bool:SQL_FetchInt(hndl, 13);

		new String:flags[11];
		SQL_FetchString(hndl, 14, flags, sizeof(flags));
		g_items[g_itemCount][ItemFlags] = ReadFlagString(flags);
				
		g_itemCount++;
	}

	Call_StartForward(g_reloadItemsPostForward);
	Call_Finish();

	GetItems(-1, filter, callback, plugin, true, "", arg);
}

GetItemIndex(id)
{
	for (new index = 0; index < g_itemCount; index++)
	{
		if (g_items[index][ItemId] == id)
		{
			return index;
		}
	}

	return -1;
}

GetItemAttributes(const String:itemName[], Store_ItemGetAttributesCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackString(hPack, itemName);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new itemNameLength = 2*strlen(itemName)+1;

	new String:itemNameSafe[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT attrs, LENGTH(attrs) AS attrs_len FROM store_items WHERE name = '%s'", itemNameSafe);
	SQL_TQuery(g_hSQL, T_GetItemAttributesCallback, sQuery, hPack);
	Store_LogTrace("[SQL Query] GetItemAttributes - %s", sQuery);
}

public T_GetItemAttributesCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);
	
	new String:itemName[STORE_MAX_NAME_LENGTH];
	ReadPackString(hPack, itemName, sizeof(itemName));
	
	new Store_ItemGetAttributesCallback:callback = Store_ItemGetAttributesCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);
	
	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GetItemAttributes: %s", error);
		return;
	}
	
	if (SQL_FetchRow(hndl) && !SQL_IsFieldNull(hndl, 0))
	{
		new attrsLength = SQL_FetchInt(hndl, 1);
		
		new String:attrs[attrsLength+1];
		SQL_FetchString(hndl, 0, attrs, attrsLength+1);
		
		if (callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushString(itemName);
			Call_PushString(attrs);
			Call_PushCell(arg);
			Call_Finish();
		}
	}
}

WriteItemAttributes(const String:itemName[], const String:attrs[], Store_BuyItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new itemNameLength = 2 * strlen(itemName) + 1;
	new String:itemNameSafe[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);

	new attrsLength = 10 * 1024;
	new String:attrsSafe[2*attrsLength+1];
	SQL_EscapeString(g_hSQL, attrs, attrsSafe, 2*attrsLength+1);
	
	new String:sQuery[attrsLength + MAX_QUERY_SIZES];
	Format(sQuery, attrsLength + MAX_QUERY_SIZES, "UPDATE store_items SET attrs = '%s}' WHERE name = '%s'", attrsSafe, itemNameSafe);
	SQL_TQuery(g_hSQL, T_WriteItemAttributesCallback, sQuery, hPack);
	Store_LogTrace("[SQL Query] WriteItemAttributes - %s", sQuery);
}

public T_WriteItemAttributesCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new Store_BuyItemCallback:callback = Store_BuyItemCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on WriteItemAttributes: %s", error);
		return;
	}

	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(true);
		Call_PushCell(arg);
		Call_Finish();
	}
}

GetLoadouts(Handle:filter, Store_GetItemsCallback:callback = INVALID_FUNCTION, Handle:plugin = INVALID_HANDLE, bool:loadFromCache = true, any:data = 0)
{
	if (loadFromCache && g_loadoutCount != -1)
	{
		if (callback == INVALID_FUNCTION)
		{
			return;
		}

		new loadouts[g_loadoutCount];
		new count = 0;

		new String:game[32];
		new bool:gameFilter = filter == INVALID_HANDLE ? false : GetTrieString(filter, "game", game, sizeof(game));

		new String:class[32];
		new bool:classFilter = filter == INVALID_HANDLE ? false : GetTrieString(filter, "class", class, sizeof(class));

		CloseHandle(filter);

		for (new loadout = 0; loadout < g_loadoutCount; loadout++)
		{
			if ((!gameFilter || StrEqual(game, "") || StrEqual(g_loadouts[loadout][LoadoutGame], "") || StrEqual(game, g_loadouts[loadout][LoadoutGame])) && (!classFilter || StrEqual(class, "") || StrEqual(g_loadouts[loadout][LoadoutClass], "") || StrEqual(class, g_loadouts[loadout][LoadoutClass])))
			{
				loadouts[count] = g_loadouts[loadout][LoadoutId];
				count++;
			}
		}

		Call_StartFunction(plugin, callback);
		Call_PushArray(loadouts, count);
		Call_PushCell(count);
		Call_PushCell(data);
		Call_Finish();
		
		Store_LogDebug("Loadouts Pulled: Count = %i - LoadFromCache: %s", count, loadFromCache ? "True" : "False");
	}
	else
	{
		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, _:filter);
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, _:plugin);
		WritePackCell(hPack, _:data);
		
		new String:sQuery[MAX_QUERY_SIZES];
		Format(sQuery, sizeof(sQuery), "SELECT id, display_name, game, class, team FROM store_loadouts");
		SQL_TQuery(g_hSQL, T_GetLoadoutsCallback, sQuery, hPack);
		Store_LogTrace("[SQL Query] GetLoadouts - %s", sQuery);
	}
}

public T_GetLoadoutsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	if (hndl == INVALID_HANDLE)
	{
		CloseHandle(hPack);

		Store_LogError("SQL Error on GetLoadouts: %s", error);
		return;
	}

	ResetPack(hPack);

	new Handle:filter = Handle:ReadPackCell(hPack);
	new Store_GetItemsCallback:callback = Store_GetItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	g_loadoutCount = 0;

	while (SQL_FetchRow(hndl))
	{
		g_loadouts[g_loadoutCount][LoadoutId] = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, g_loadouts[g_loadoutCount][LoadoutDisplayName], STORE_MAX_DISPLAY_NAME_LENGTH);
		SQL_FetchString(hndl, 2, g_loadouts[g_loadoutCount][LoadoutGame], STORE_MAX_LOADOUTGAME_LENGTH);
		SQL_FetchString(hndl, 3, g_loadouts[g_loadoutCount][LoadoutClass], STORE_MAX_LOADOUTCLASS_LENGTH);
		g_loadouts[g_loadoutCount][LoadoutTeam] = SQL_IsFieldNull(hndl, 4) ? -1 : SQL_FetchInt(hndl, 4);
		
		g_loadoutCount++;
	}

	GetLoadouts(filter, callback, plugin, true, arg);
}

GetLoadoutIndex(id)
{
	for (new index = 0; index < g_loadoutCount; index++)
	{
		if (g_loadouts[index][LoadoutId] == id)
		{
			return index;
		}
	}

	return -1;
}

GetUserItems(Handle:filter, accountId, loadoutId, Store_GetUserItemsCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, _:filter);
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);
	
	if (g_itemCount == -1)
	{
		Store_LogWarning("Store_GetUserItems has been called before item loading.");
		GetItems(-1, INVALID_HANDLE, GetUserItemsLoadCallback, INVALID_HANDLE, true, "", hPack);

		return;
	}

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT item_id, EXISTS(SELECT * FROM store_users_items_loadouts WHERE store_users_items_loadouts.useritem_id = store_users_items.id AND store_users_items_loadouts.loadout_id = %d) AS equipped, COUNT(*) AS count FROM store_users_items INNER JOIN store_users ON store_users.id = store_users_items.user_id INNER JOIN store_items ON store_items.id = store_users_items.item_id WHERE store_users.auth = %d AND ((store_users_items.acquire_date IS NULL OR store_items.expiry_time IS NULL OR store_items.expiry_time = 0) OR (store_users_items.acquire_date IS NOT NULL AND store_items.expiry_time IS NOT NULL AND store_items.expiry_time <> 0 AND DATE_ADD(store_users_items.acquire_date, INTERVAL store_items.expiry_time SECOND) > NOW()))", loadoutId, accountId);

	new categoryId;
	if (GetTrieValue(filter, "category_id", categoryId))
	{
		Format(sQuery, sizeof(sQuery), "%s AND store_items.category_id = %d", sQuery, categoryId);
	}
	
	new bool:isBuyable;
	if (GetTrieValue(filter, "is_buyable", isBuyable))
	{
		Format(sQuery, sizeof(sQuery), "%s AND store_items.is_buyable = %b", sQuery, isBuyable);
	}
	
	new bool:isTradeable;
	if (GetTrieValue(filter, "is_tradeable", isTradeable))
	{
		Format(sQuery, sizeof(sQuery), "%s AND store_items.is_tradeable = %b", sQuery, isTradeable);
	}
	
	new bool:isRefundable;
	if (GetTrieValue(filter, "is_refundable", isRefundable))
	{
		Format(sQuery, sizeof(sQuery), "%s AND store_items.is_refundable = %b", sQuery, isRefundable);
	}
	
	new String:type[STORE_MAX_TYPE_LENGTH];
	if (GetTrieString(filter, "type", type, sizeof(type)))
	{
		new typeLength = 2*strlen(type)+1;

		new String:buffer[typeLength];
		SQL_EscapeString(g_hSQL, type, buffer, typeLength);

		Format(sQuery, sizeof(sQuery), "%s AND store_items.type = '%s'", sQuery, buffer);
	}

	Format(sQuery, sizeof(sQuery), "%s GROUP BY item_id", sQuery);

	CloseHandle(filter);

	SQL_TQuery(g_hSQL, T_GetUserItemsCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] GetUserItems - %s", sQuery);
}

public GetUserItemsLoadCallback(ids[], count, any:hPack)
{
	ResetPack(hPack);

	new Handle:filter = Handle:ReadPackCell(hPack);
	new accountId = ReadPackCell(hPack);
	new loadoutId = ReadPackCell(hPack);
	new Store_GetUserItemsCallback:callback = Store_GetUserItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	GetUserItems(filter, accountId, loadoutId, callback, plugin, arg);
}

public T_GetUserItemsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);
	ReadPackCell(hPack);
	ReadPackCell(hPack);
	
	new loadoutId = ReadPackCell(hPack);
	new Store_GetUserItemsCallback:callback = Store_GetUserItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);
	
	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GetUserItems: %s", error);
		return;
	}
	
	new count = SQL_GetRowCount(hndl);
	
	new ids[count];
	new bool:equipped[count];
	new itemCount[count];

	new index = 0;
	while (SQL_FetchRow(hndl))
	{
		ids[index] = SQL_FetchInt(hndl, 0);
		equipped[index] = bool:SQL_FetchInt(hndl, 1);
		itemCount[index] = SQL_FetchInt(hndl, 2);

		index++;
	}

	Call_StartFunction(plugin, callback);
	Call_PushArray(ids, count);
	Call_PushArray(equipped, count);
	Call_PushArray(itemCount, count);
	Call_PushCell(count);
	Call_PushCell(loadoutId);
	Call_PushCell(_:arg);
	Call_Finish();
}

GetUserItemCount(accountId, const String:itemName[], Store_GetUserItemCountCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new itemNameLength = 2*strlen(itemName)+1;

	new String:itemNameSafe[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT COUNT(*) AS count FROM store_users_items INNER JOIN store_users ON store_users.id = store_users_items.user_id INNER JOIN store_items ON store_items.id = store_users_items.item_id WHERE store_items.name = '%s' AND store_users.auth = %d", itemNameSafe, accountId);
	SQL_TQuery(g_hSQL, T_GetUserItemCountCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] GetUserItemCount - %s", sQuery);
}

public T_GetUserItemCountCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new Store_GetUserItemCountCallback:callback = Store_GetUserItemCountCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GetUserItemCount: %s", error);
		return;
	}

	if (SQL_FetchRow(hndl))
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(SQL_FetchInt(hndl, 0));
		Call_PushCell(_:arg);
		Call_Finish();
	}
}

GetCredits(accountId, Store_GetCreditsCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT credits FROM store_users WHERE auth = %d", accountId);
	SQL_TQuery(g_hSQL, T_GetCreditsCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] GetCredits - %s", sQuery);
}

public T_GetCreditsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new Store_GetCreditsCallback:callback = Store_GetCreditsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);
	
	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GetCredits: %s", error);
		return;
	}
	
	if (SQL_FetchRow(hndl))
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(SQL_FetchInt(hndl, 0));
		Call_PushCell(_:arg);
		Call_Finish();
	}
}

BuyItem(accountId, itemId, Store_BuyItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	GetCredits(accountId, T_BuyItemGetCreditsCallback, INVALID_HANDLE, hPack);
}

public T_BuyItemGetCreditsCallback(credits, any:hPack)
{
	ResetPack(hPack);

	new itemId = ReadPackCell(hPack);
	new accountId = ReadPackCell(hPack);
	new Store_BuyItemCallback:callback = Store_BuyItemCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	if (credits < g_items[GetItemIndex(itemId)][ItemPrice])
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(0);
		Call_PushCell(_:arg);
		Call_Finish();

		return;
	}

	GiveCredits(accountId, -g_items[GetItemIndex(itemId)][ItemPrice], BuyItemGiveCreditsCallback, _, hPack);
}

public BuyItemGiveCreditsCallback(accountId, credits, any:hPack)
{
	ResetPack(hPack);

	new itemId = ReadPackCell(hPack);
	GiveItem(accountId, itemId, Store_Shop, BuyItemGiveItemCallback, _, hPack);
}

public BuyItemGiveItemCallback(accountId, any:hPack)
{
	ResetPack(hPack);
	ReadPackCell(hPack);
	ReadPackCell(hPack);
	
	new Store_BuyItemCallback:callback = Store_BuyItemCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	Call_StartFunction(plugin, callback);
	Call_PushCell(1);
	Call_PushCell(_:arg);
	Call_Finish();
}

RemoveUserItem(accountId, itemId, Store_UseItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	UnequipItem(accountId, itemId, -1, RemoveUserItemUnnequipCallback, _, hPack);
}

public RemoveUserItemUnnequipCallback(accountId, itemId, loadoutId, any:hPack)
{
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "DELETE FROM store_users_items WHERE store_users_items.item_id = %d AND store_users_items.user_id IN (SELECT store_users.id FROM store_users WHERE store_users.auth = %d) LIMIT 1", itemId, accountId);
	SQL_TQuery(g_hSQL, T_RemoveUserItemCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] RemoveUserItemUnequipCallback - %s", sQuery);
}

public T_RemoveUserItemCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new itemId = ReadPackCell(hPack);
	new Store_UseItemCallback:callback = Store_UseItemCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on UseItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(_:arg);
	Call_Finish();
}

SetItemEquippedState(accountId, itemId, loadoutId, bool:isEquipped, Store_EquipItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	switch (isEquipped)
	{
		case true: EquipItem(accountId, itemId, loadoutId, callback, plugin, data);
		case false: UnequipItem(accountId, itemId, loadoutId, callback, plugin, data);
	}
}

EquipItem(accountId, itemId, loadoutId, Store_EquipItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	UnequipItem(accountId, itemId, loadoutId, EquipUnequipItemCallback, _, hPack);
}

public EquipUnequipItemCallback(accountId, itemId, loadoutId, any:hPack)
{
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "INSERT INTO store_users_items_loadouts (loadout_id, useritem_id) SELECT %d AS loadout_id, store_users_items.id FROM store_users_items INNER JOIN store_users ON store_users.id = store_users_items.user_id WHERE store_users.auth = %d AND store_users_items.item_id = %d LIMIT 1", loadoutId, accountId, itemId);
	SQL_TQuery(g_hSQL, T_EquipItemCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] EquipUnequipItemCallback - %s", sQuery);
}

public T_EquipItemCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new itemId = ReadPackCell(hPack);
	new loadoutId = ReadPackCell(hPack);
	new Store_GiveCreditsCallback:callback = Store_GiveCreditsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on EquipItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(loadoutId);
	Call_PushCell(_:arg);
	Call_Finish();
}

UnequipItem(accountId, itemId, loadoutId, Store_EquipItemCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "DELETE store_users_items_loadouts FROM store_users_items_loadouts INNER JOIN store_users_items ON store_users_items.id = store_users_items_loadouts.useritem_id INNER JOIN store_users ON store_users.id = store_users_items.user_id INNER JOIN store_items ON store_items.id = store_users_items.item_id WHERE store_users.auth = %d AND store_items.loadout_slot = (SELECT loadout_slot from store_items WHERE store_items.id = %d)", accountId, itemId);

	if (loadoutId != -1)
	{
		Format(sQuery, sizeof(sQuery), "%s AND store_users_items_loadouts.loadout_id = %d", sQuery, loadoutId);
	}

	SQL_TQuery(g_hSQL, T_UnequipItemCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] UnequipItem - %s", sQuery);
}

public T_UnequipItemCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new itemId = ReadPackCell(hPack);
	new loadoutId = ReadPackCell(hPack);
	new Store_GiveCreditsCallback:callback = Store_GiveCreditsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on UnequipItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(loadoutId);
	Call_PushCell(_:arg);
	Call_Finish();
}

GetEquippedItemsByType(accountId, const String:type[], loadoutId, Store_GetItemsCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);
	
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT store_items.id FROM store_users_items INNER JOIN store_items ON store_items.id = store_users_items.item_id INNER JOIN store_users ON store_users.id = store_users_items.user_id INNER JOIN store_users_items_loadouts ON store_users_items_loadouts.useritem_id = store_users_items.id WHERE store_users.auth = %d AND store_items.type = '%s' AND store_users_items_loadouts.loadout_id = %d", accountId, type, loadoutId);
	SQL_TQuery(g_hSQL, T_GetEquippedItemsByTypeCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] GetEquippedItemsByType - %s", sQuery);
}

public T_GetEquippedItemsByTypeCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new Store_GetItemsCallback:callback = Store_GetItemsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GetEquippedItemsByType: %s", error);
		return;
	}

	new count = SQL_GetRowCount(hndl);
	new ids[count];

	new index = 0;
	while (SQL_FetchRow(hndl))
	{
		ids[index] = SQL_FetchInt(hndl, 0);
		index++;
	}

	Call_StartFunction(plugin, callback);
	Call_PushArray(ids, count);
	Call_PushCell(count);
	Call_PushCell(arg);
	Call_Finish();
}

GiveCredits(accountId, credits, Store_GiveCreditsCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, credits);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = credits + %d WHERE auth = %d", credits, accountId);
	SQL_TQuery(g_hSQL, T_GiveCreditsCallback, sQuery, hPack);
	Store_LogTrace("[SQL Query] GiveCredits - %s", sQuery);
}

public T_GiveCreditsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new credits = ReadPackCell(hPack);
	new Store_GiveCreditsCallback:callback = Store_GiveCreditsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GiveCredits: %s", error);
		return;
	}

	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(credits);
		Call_PushCell(_:arg);
		Call_Finish();
	}
}

RemoveCredits(accountId, credits, Store_RemoveCreditsCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, credits);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);
	
	Store_LogDebug("Native - RemoveCredits - accountId = %d, credits = %d", accountId, credits);
	
	new bool:bIsNegative = false;
	
	if (Store_GetCreditsEx(accountId) < credits)
	{
		bIsNegative = true;
		WritePackCell(hPack, bIsNegative);
		
		new String:sQuery[MAX_QUERY_SIZES];
		Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = %d WHERE auth = %d", 0, accountId);
		SQL_TQuery(g_hSQL, T_RemoveCreditsCallback, sQuery, hPack);
		Store_LogTrace("[SQL Query] RemoveCredits [Less than 0] - %s", sQuery);
		
		return;
	}
	
	WritePackCell(hPack, bIsNegative);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = credits - %d WHERE auth = %d", credits, accountId);
	SQL_TQuery(g_hSQL, T_RemoveCreditsCallback, sQuery, hPack);
	Store_LogTrace("[SQL Query] RemoveCredits - %s", sQuery);
}

public T_RemoveCreditsCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new credits = ReadPackCell(hPack);
	new Store_RemoveCreditsCallback:callback = Store_RemoveCreditsCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);
	new bIsNegative = ReadPackCell(hPack);

	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on RemoveCredits: %s", error);
		return;
	}

	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(credits);
		Call_PushCell(bIsNegative);
		Call_PushCell(_:arg);
		Call_Finish();
	}
}

GiveItem(accountId, itemId, Store_AcquireMethod:acquireMethod = Store_Unknown, Store_AccountCallback:callback, Handle:plugin = INVALID_HANDLE, any:data = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, _:plugin);
	WritePackCell(hPack, _:data);

	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "INSERT INTO store_users_items (user_id, item_id, acquire_date, acquire_method) SELECT store_users.id AS userId, '%d' AS item_id, NOW() as acquire_date, ", itemId);
	
	switch (acquireMethod)
	{
		case Store_Shop: Format(sQuery, sizeof(sQuery), "%s'shop'", sQuery);
		case Store_Trade: Format(sQuery, sizeof(sQuery), "%s'trade'", sQuery);
		case Store_Gift: Format(sQuery, sizeof(sQuery), "%s'gift'", sQuery);
		case Store_Admin: Format(sQuery, sizeof(sQuery), "%s'admin'", sQuery);
		case Store_Web: Format(sQuery, sizeof(sQuery), "%s'web'", sQuery);
		case Store_Unknown: Format(sQuery, sizeof(sQuery), "%sNULL", sQuery);
	}

	Format(sQuery, sizeof(sQuery), "%s AS acquire_method FROM store_users WHERE auth = %d", sQuery, accountId);
	SQL_TQuery(g_hSQL, T_GiveItemCallback, sQuery, hPack, DBPrio_High);
	Store_LogTrace("[SQL Query] GiveItem - %s", sQuery);
}

public T_GiveItemCallback(Handle:owner, Handle:hndl, const String:error[], any:hPack)
{
	ResetPack(hPack);

	new accountId = ReadPackCell(hPack);
	new Store_AccountCallback:callback = Store_AccountCallback:ReadPackFunction(hPack);
	new Handle:plugin = Handle:ReadPackCell(hPack);
	new arg = ReadPackCell(hPack);
	
	CloseHandle(hPack);
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GiveItem: %s", error);
		return;
	}
	
	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(_:arg);
		Call_Finish();
	}
}

GiveCreditsToUsers(accountIds[], accountIdsLength, credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = credits + %d WHERE auth IN (", credits);

	for (new i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), "%s)", sQuery);
	SQL_TQuery(g_hSQL, T_GiveCreditsToUsersCallback, sQuery);
	Store_LogTrace("[SQL Query] GiveCreditsToUsers - %s", sQuery);
}

public T_GiveCreditsToUsersCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GiveCreditsToUsers: %s", error);
	}
}

RemoveCreditsFromUsers(accountIds[], accountIdsLength, credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = credits - %d WHERE auth IN (", credits);

	for (new i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), "%s)", sQuery);
	SQL_TQuery(g_hSQL, T_RemoveCreditsFromUsersCallback, sQuery);
	Store_LogTrace("[SQL Query] RemoveCreditsFromUsers - %s", sQuery);
}

public T_RemoveCreditsFromUsersCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on RemoveCreditsFromUsers: %s", error);
		return;
	}
}

GiveDifferentCreditsToUsers(accountIds[], accountIdsLength, credits[])
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "UPDATE store_users SET credits = credits + CASE auth");

	for (new i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s WHEN %d THEN %d", sQuery, accountIds[i], credits[i]);
	}

	Format(sQuery, sizeof(sQuery), "%s END WHERE auth IN (", sQuery);

	for (new i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), "%s)", sQuery);
	SQL_TQuery(g_hSQL, T_GiveDifferentCreditsToUsersCallback, sQuery);
	Store_LogTrace("[SQL Query] GiveDifferentCreditsToUsers - %s", sQuery);
}

public T_GiveDifferentCreditsToUsersCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on GiveDifferentCreditsToUsers: %s", error);
	}
}

ReloadItemCache(client)
{
	GetCategories(client, _, _, false, "");
	GetItems(client, _, _, _, false, "");
}

ConnectSQL()
{
	if (g_hSQL != INVALID_HANDLE)
	{
		CloseHandle(g_hSQL);
		g_hSQL = INVALID_HANDLE;
	}

	new String:sBuffer[64];
	Store_GetSQLEntry(sBuffer, sizeof(sBuffer));

	if (SQL_CheckConfig(sBuffer))
	{
		SQL_TConnect(T_ConnectSQLCallback, sBuffer);
	}
	else
	{
		SetFailState("No config entry found for '%s' in databases.cfg.", sBuffer);
	}
}

public T_ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_reconnectCounter >= 5)
	{
		SetFailState("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("Connection to SQL database has failed, Reason: %s", error);
		
		g_reconnectCounter++;
		ConnectSQL();
		
		return;
	}
	
	g_hSQL = CloneHandle(hndl);
	CloseHandle(hndl);
	
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
	
	Call_StartForward(g_dbInitializedForward);
	Call_Finish();
	
	ReloadItemCache(-1);
	
	g_reconnectCounter = 1;
}

public Action:Command_ReloadItems(client, args)
{
	if (client != 0)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "Check console for reload outputs");
	}
	
	RequestFrame(Frame_ReloadItems, client);
	return Plugin_Handled;
}

public Frame_ReloadItems(any:client)
{
	CReplyToCommand(client, "%t%t", (client != 0) ? "Store Tag Colored" : "Store Tag", "Reloading categories and items");
	ReloadItemCache(client);
}

public Action:Command_TestCreditsNative(client, args)
{
	new credits = Store_GetCreditsEx(GetSteamAccountID(client));
	PrintToChat(client, "credits = %d", credits);
	return Plugin_Handled;
}

public Native_Register(Handle:plugin, params)
{
	new String:name[64];
	GetNativeString(2, name, sizeof(name));

	Register(GetNativeCell(1), name, GetNativeCell(3));
}

public Native_RegisterClient(Handle:plugin, params)
{
	RegisterClient(GetNativeCell(1), GetNativeCell(2));
}

public Native_GetClientAccountID(Handle:plugin, params)
{
	new client = GetNativeCell(1);
	new AccountID = GetSteamAccountID(client);
	
	if (AccountID == 0)
	{
		ThrowNativeError(SP_ERROR_INDEX, "Error retrieving client Steam Account ID %L.", client);
	}
	
	return AccountID;
}

public Native_GetCategories(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	new length;
	GetNativeStringLength(3, length);
	
	new String:sString[length + 1];
	GetNativeString(3, sString, length + 1);
	
	GetCategories(-1, Store_GetItemsCallback:GetNativeFunction(1), plugin, bool:GetNativeCell(2), sString, data);
}

public Native_GetCategoryPriority(Handle:plugin, params)
{
	return g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryPriority];
}

public Native_GetCategoryDisplayName(Handle:plugin, params)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryDisplayName], GetNativeCell(3));
}

public Native_GetCategoryDescription(Handle:plugin, params)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryDescription], GetNativeCell(3));
}

public Native_GetCategoryPluginRequired(Handle:plugin, params)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryRequirePlugin], GetNativeCell(3));
}

public Native_GetItems(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 5)
	{
		data = GetNativeCell(5);
	}
	
	new length;
	GetNativeStringLength(4, length);
	
	new String:sString[length + 1];
	GetNativeString(4, sString, length + 1);
	
	GetItems(-1, Handle:GetNativeCell(1), Store_GetItemsCallback:GetNativeFunction(2), plugin, bool:GetNativeCell(3), sString, data);
}

public Native_GetItemName(Handle:plugin, params)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemName], GetNativeCell(3));
}

public Native_GetItemDisplayName(Handle:plugin, params)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemDisplayName], GetNativeCell(3));
}

public Native_GetItemDescription(Handle:plugin, params)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemDescription], GetNativeCell(3));
}

public Native_GetItemType(Handle:plugin, params)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemType], GetNativeCell(3));
}

public Native_GetItemLoadoutSlot(Handle:plugin, params)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemLoadoutSlot], GetNativeCell(3));
}

public Native_GetItemPrice(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemPrice];
}

public Native_GetItemCategory(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemCategoryId];
}

public Native_IsItemBuyable(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsBuyable];
}

public Native_IsItemTradeable(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsTradeable];
}

public Native_IsItemRefundable(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsRefundable];
}

public Native_GetItemPriority(Handle:plugin, params)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemPriority];
}

public Native_GetItemAttributes(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 3)
	{
		data = GetNativeCell(3);
	}
	
	new String:itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(1, itemName, sizeof(itemName));

	GetItemAttributes(itemName, Store_ItemGetAttributesCallback:GetNativeFunction(2), plugin, data);
}

public Native_WriteItemAttributes(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	new String:itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(1, itemName, sizeof(itemName));

	new attrsLength = 10*1024;
	GetNativeStringLength(2, attrsLength);

	new String:attrs[attrsLength];
	GetNativeString(2, attrs, attrsLength);

	WriteItemAttributes(itemName, attrs, Store_BuyItemCallback:GetNativeFunction(3), plugin, data);
}

public Native_GetLoadouts(Handle:plugin, params)
{
	new any:data = 0;
	
	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	GetLoadouts(Handle:GetNativeCell(1), Store_GetItemsCallback:GetNativeFunction(2), plugin, bool:GetNativeCell(3), data);
}

public Native_GetLoadoutDisplayName(Handle:plugin, params)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutDisplayName], GetNativeCell(3));
}

public Native_GetLoadoutGame(Handle:plugin, params)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutGame], GetNativeCell(3));
}

public Native_GetLoadoutClass(Handle:plugin, params)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutClass], GetNativeCell(3));
}

public Native_GetLoadoutTeam(Handle:plugin, params)
{
	return g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutTeam];
}

public Native_GetUserItems(Handle:plugin, params)
{
	new any:data = 0;
	
	if (params == 5)
	{
		data = GetNativeCell(5);
	}
	
	GetUserItems(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), Store_GetUserItemsCallback:GetNativeFunction(4), plugin, data);
}

public Native_GetUserItemCount(Handle:plugin, params)
{
	new any:data = 0;
	
	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	new String:itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(2, itemName, sizeof(itemName));

	GetUserItemCount(GetNativeCell(1), itemName, Store_GetUserItemCountCallback:GetNativeFunction(3), plugin, data);
}

public Native_GetCredits(Handle:plugin, params)
{
	new any:data = 0;
	
	if (params == 3)
	{
		data = GetNativeCell(3);
	}
	
	GetCredits(GetNativeCell(1), Store_GetCreditsCallback:GetNativeFunction(2), plugin, data);
}

public Native_GetCreditsEx(Handle:plugin, params)
{
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "SELECT credits FROM store_users WHERE auth = %d;", GetNativeCell(1));
	new Handle:hQuery = SQL_Query(g_hSQL, sQuery);
	
	new credits = -1;
	
	if (hQuery == INVALID_HANDLE)
	{
		new String:sError[512];
		SQL_GetError(g_hSQL, sError, sizeof(sError));
		Store_LogError("SQL Error on GetCreditsEx: %s", sError);
		return credits;
	}
		
	if (SQL_FetchRow(hQuery))
	{
		credits = SQL_FetchInt(hQuery, 0);
	}
	
	CloseHandle(hQuery);
	
	return credits;
}

public Native_BuyItem(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	BuyItem(GetNativeCell(1), GetNativeCell(2), Store_BuyItemCallback:GetNativeFunction(3), plugin, data);
}

public Native_RemoveUserItem(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}
	
	RemoveUserItem(GetNativeCell(1), GetNativeCell(2), Store_UseItemCallback:GetNativeFunction(3), plugin, data);
}

public Native_SetItemEquippedState(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 6)
	{
		data = GetNativeCell(6);
	}
	
	SetItemEquippedState(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), Store_EquipItemCallback:GetNativeFunction(5), plugin, data);
}

public Native_GetEquippedItemsByType(Handle:plugin, params)
{
	new String:type[32];
	GetNativeString(2, type, sizeof(type));

	new any:data = 0;

	if (params == 5)
	{
		data = GetNativeCell(5);
	}
	
	GetEquippedItemsByType(GetNativeCell(1), type, GetNativeCell(3), Store_GetItemsCallback:GetNativeFunction(4), plugin, data);
}

public Native_GiveCredits(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}

	GiveCredits(GetNativeCell(1), GetNativeCell(2), Store_GiveCreditsCallback:GetNativeFunction(3), plugin, data);
}

public Native_GiveCreditsToUsers(Handle:plugin, params)
{
	new length = GetNativeCell(2);

	new accountIds[length];
	GetNativeArray(1, accountIds, length);

	GiveCreditsToUsers(accountIds, length, GetNativeCell(3));
}

public Native_GiveItem(Handle:plugin, params)
{
	new any:data = 0;
	
	if (params == 5)
	{
		data = GetNativeCell(5);
	}
	
	GiveItem(GetNativeCell(1), GetNativeCell(2), Store_AcquireMethod:GetNativeCell(3), Store_AccountCallback:GetNativeFunction(4), plugin, data);
}

public Native_GiveDifferentCreditsToUsers(Handle:plugin, params)
{
	new length = GetNativeCell(2);

	new accountIds[length];
	GetNativeArray(1, accountIds, length);

	new credits[length];
	GetNativeArray(3, credits, length);

	GiveDifferentCreditsToUsers(accountIds, length, credits);
}

public Native_RemoveCredits(Handle:plugin, params)
{
	new any:data = 0;

	if (params == 4)
	{
		data = GetNativeCell(4);
	}

	RemoveCredits(GetNativeCell(1), GetNativeCell(2), Store_RemoveCreditsCallback:GetNativeFunction(3), plugin, data);
}

public Native_RemoveCreditsFromUsers(Handle:plugin, params)
{
	new length = GetNativeCell(2);

	new accountIds[length];
	GetNativeArray(1, accountIds, length);

	RemoveCreditsFromUsers(accountIds, length, GetNativeCell(3));
}

public Native_ReloadItemCache(Handle:plugin, params)
{
	ReloadItemCache(-1);
}

public Native_RegisterPluginModule(Handle:plugin, params)
{
	new length;
	GetNativeStringLength(1, length);
	
	new String:sName[length + 1];
	GetNativeString(1, sName, length + 1);
	
	new length2;
	GetNativeStringLength(2, length2);
	
	new String:sDescription[length2 + 1];
	GetNativeString(2, sDescription, length2 + 1);
	
	new length3;
	GetNativeStringLength(3, length3);
	
	new String:sVersion_ConVar[length3 + 1];
	GetNativeString(3, sVersion_ConVar, length3 + 1);
	
	new length4;
	GetNativeStringLength(4, length4);
	
	new String:sVersion[length4 + 1];
	GetNativeString(4, sVersion, length4 + 1);
	
	new String:sQuery[MAX_QUERY_SIZES];
	Format(sQuery, sizeof(sQuery), "INSERT INTO store_versions (mod_name, mod_description, mod_ver_convar, mod_ver_number, server_id, last_updated) VALUES ('%s', '%s', '%s', '%s', '%d', NOW()) ON DUPLICATE KEY UPDATE mod_name = VALUES(mod_name), mod_description = VALUES(mod_description), mod_ver_convar = VALUES(mod_ver_convar), mod_ver_number = VALUES(mod_ver_number), server_id = VALUES(server_id), last_updated = NOW();", sName, sDescription, sVersion_ConVar, sVersion, Store_GetServerID());
	SQL_TQuery(g_hSQL, T_RegisterPluginModuleCallback, sQuery);
	Store_LogTrace("[SQL Query] RegisterPluginModule - %s", sQuery);
}

public T_RegisterPluginModuleCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Store_LogError("SQL Error on RegisterPluginModule: %s", error);
	}
}

public Native_SQLTQuery(Handle:plugin, params)
{
	new SQLTCallback:callback = SQLTCallback:GetNativeFunction(1);
	
	new size;
	GetNativeStringLength(2, size);
	
	new String:sQuery[size];
	GetNativeString(2, sQuery, size);
	
	new data = GetNativeCell(3);
	new DBPriority:prio = DBPriority:GetNativeCell(4);
	
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, _:plugin);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, data);
	
	SQL_TQuery(g_hSQL, Query_Callback, sQuery, hPack, prio);
	Store_LogTrace("[SQL Query] Store_TQuery - %s", sQuery);
}

public Query_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	
	new Handle:plugin = Handle:ReadPackCell(data);
	new SQLTCallback:callback = SQLTCallback:ReadPackFunction(data);
	new hPack = ReadPackCell(data);
	
	CloseHandle(data);
	
	Call_StartFunction(plugin, callback);
	Call_PushCell(owner);
	Call_PushCell(hndl);
	Call_PushString(error);
	Call_PushCell(hPack);
	Call_Finish();
}