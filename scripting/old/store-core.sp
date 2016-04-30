#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <store>

#pragma newdecls required

#define PLUGIN_NAME "[Store] Core Module"
#define PLUGIN_DESCRIPTION "Core module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_core_version"

#define MAX_MENU_ITEMS 32
#define MAX_CHAT_COMMANDS 100

char sQuery_Register[] = "INSERT INTO %s_users (auth, name, credits, token, ip) VALUES ('%d', '%s', '%d', '%s', '%s') ON DUPLICATE KEY UPDATE name = '%s', token = '%s', ip = '%s';";
char sQuery_GetClientUserID[] = "SELECT id FROM %s_users WHERE auth = '%d';";
char sQuery_GetCategories[] = "SELECT id, priority, display_name, description, require_plugin, enable_server_restriction FROM %s_categories %s;";
char sQuery_GetItems[] = "SELECT id, priority, name, display_name, description, type, loadout_slot, price, category_id, attrs, LENGTH(attrs) AS attrs_len, is_buyable, is_tradeable, is_refundable, flags, enable_server_restriction FROM %s_items %s;";
char sQuery_GetItemAttributes[] = "SELECT attrs, LENGTH(attrs) AS attrs_len FROM %s_items WHERE name = '%s';";
char sQuery_WriteItemAttributes[] = "UPDATE %s_items SET attrs = '%s}' WHERE name = '%s';";
char sQuery_GetLoadouts[] = "SELECT id, display_name, game, class, team FROM %s_loadouts;";
char sQuery_GetClientLoadouts[] = "SELECT loadout_id FROM %s_users_loadouts WHERE user_id = '%d';";
char sQuery_QueryEquippedLoadout[] = "SELECT eqp_loadout_id FROM %s_users WHERE auth = '%d';";
char sQuery_GetUserItems[] = "SELECT item_id, EXISTS(SELECT * FROM %s_items_loadouts WHERE %s_items_loadouts.item_id = %s_users_items.id AND %s_items_loadouts.loadout_id = %d) AS equipped, COUNT(*) AS count FROM %s_users_items INNER JOIN %s_users ON %s_users.id = %s_users_items.user_id INNER JOIN %s_items ON %s_items.id = %s_users_items.item_id WHERE %s_users.auth = %d AND ((%s_users_items.acquire_date IS NULL OR %s_items.expiry_time IS NULL OR %s_items.expiry_time = 0) OR (%s_users_items.acquire_date IS NOT NULL AND %s_items.expiry_time IS NOT NULL AND %s_items.expiry_time <> 0 AND DATE_ADD(%s_users_items.acquire_date, INTERVAL %s_items.expiry_time SECOND) > NOW()))";
char sQuery_GetUserItems_categoryId[] = "%s AND %s_items.category_id = %d";
char sQuery_GetUserItems_isBuyable[] = "%s AND %s_items.is_buyable = %b";
char sQuery_GetUserItems_isTradeable[] = "%s AND %s_items.is_tradeable = %b";
char sQuery_GetUserItems_isRefundable[] = "%s AND %s_items.is_refundable = %b";
char sQuery_GetUserItems_type[] = "%s AND %s_items.type = '%s'";
char sQuery_GetUserItems_GroupByID[] = "%s GROUP BY item_id;";
char sQuery_GetUserItemsCount[] = "SELECT COUNT(*) AS count FROM %s_users_items INNER JOIN %s_users ON %s_users.id = %s_users_items.user_id INNER JOIN %s_items ON %s_items.id = %s_users_items.item_id WHERE %s_items.name = '%s' AND %s_users.auth = %d;";
char sQuery_GetCredits[] = "SELECT credits FROM %s_users WHERE auth = %d;";
char sQuery_RemoveUserItem[] = "DELETE FROM %s_users_items WHERE %s_users_items.item_id = %d AND %s_users_items.user_id IN (SELECT %s_users.id FROM %s_users WHERE %s_users.auth = %d) LIMIT 1;";
char sQuery_EquipUnequipItem[] = "INSERT INTO %s_items_loadouts (loadout_id, item_id) SELECT %d AS loadout_id, %s_users_items.id FROM %s_users_items INNER JOIN %s_users ON %s_users.id = %s_users_items.user_id WHERE %s_users.auth = %d AND %s_users_items.item_id = %d LIMIT 1;";
char sQuery_UnequipItem[] = "DELETE %s_items_loadouts FROM %s_items_loadouts INNER JOIN %s_users_items ON %s_users_items.id = %s_items_loadouts.item_id INNER JOIN %s_users ON %s_users.id = %s_users_items.user_id INNER JOIN %s_items ON %s_items.id = %s_users_items.item_id WHERE %s_users.auth = %d AND %s_items.loadout_slot = (SELECT loadout_slot from %s_items WHERE %s_items.id = %d)";
char sQuery_UnequipItem_loadoutId[] = "%s AND %s_items_loadouts.loadout_id = %d;";
char sQuery_GetEquippedItemsByType[] = "SELECT %s_items.id FROM %s_users_items INNER JOIN %s_items ON %s_items.id = %s_users_items.item_id INNER JOIN %s_users ON %s_users.id = %s_users_items.user_id INNER JOIN %s_items_loadouts ON %s_items_loadouts.item_id = %s_users_items.id WHERE %s_users.auth = %d AND %s_items.type = '%s' AND %s_items_loadouts.loadout_id = %d;";
char sQuery_GiveCredits[] = "UPDATE %s_users SET credits = credits + %d WHERE auth = %d;";
char sQuery_RemoveCredits_Negative[] = "UPDATE %s_users SET credits = 0 WHERE auth = %d;";
char sQuery_RemoveCredits[] = "UPDATE %s_users SET credits = credits - %d WHERE auth = %d;";
char sQuery_GiveItem[] = "INSERT INTO %s_users_items (user_id, item_id, acquire_date, acquire_method) SELECT %s_users.id AS userId, '%d' AS item_id, NOW() as acquire_date, ";
char sQuery_GiveItem_Shop[] = "%s'shop'";
char sQuery_GiveItem_Trade[] = "%s'trade'";
char sQuery_GiveItem_Gift[] = "%s'gift'";
char sQuery_GiveItem_Admin[] = "%s'admin'";
char sQuery_GiveItem_Web[] = "%s'web'";
char sQuery_GiveItem_Unknown[] = "%sNULL";
char sQuery_GiveItem_End[] = "%s AS acquire_method FROM %s_users WHERE auth = %d;";
char sQuery_GiveCreditsToUsers[] = "UPDATE %s_users SET credits = credits + %d WHERE auth IN (";
char sQuery_GiveCreditsToUsers_End[] = "%s);";
char sQuery_RemoveCreditsFromUsers[] = "UPDATE %s_users SET credits = credits - %d WHERE auth IN (";
char sQuery_RemoveCreditsFromUsers_End[] = "%s);";
char sQuery_GiveDifferentCreditsToUsers[] = "UPDATE %s_users SET credits = credits + CASE auth";
char sQuery_GiveDifferentCreditsToUsers_accountIdsLength[] = "%s WHEN %d THEN %d";
char sQuery_GiveDifferentCreditsToUsers_End[] = "%s END WHERE auth IN (";
char sQuery_RemoveDifferentCreditsFromUsers[] = "UPDATE %s_users SET credits = credits - CASE auth";
char sQuery_RemoveDifferentCreditsFromUsers_accountIdsLength[] = "%s WHEN %d THEN %d";
char sQuery_RemoveDifferentCreditsFromUsers_End[] = "%s END WHERE auth IN (";
char sQuery_GetCreditsEx[] = "SELECT credits FROM %s_users WHERE auth = %d;";
char sQuery_RegisterPluginModule[] = "INSERT INTO %s_versions (mod_name, mod_description, mod_ver_convar, mod_ver_number, server_id, last_updated) VALUES ('%s', '%s', '%s', '%s', '%d', NOW()) ON DUPLICATE KEY UPDATE mod_name = VALUES(mod_name), mod_description = VALUES(mod_description), mod_ver_convar = VALUES(mod_ver_convar), mod_ver_number = VALUES(mod_ver_number), server_id = VALUES(server_id), last_updated = NOW();";
char sQuery_CacheRestrictionsCategories[] = "SELECT category_id, server_id FROM %s_servers_categories;";
char sQuery_CacheRestrictionsItems[] = "SELECT item_id, server_id FROM %s_servers_items;";
char sQuery_GenerateNewToken[] = "UPDATE `%s_users` SET token = '%s' WHERE auth = '%d'";
char sQuery_LogToDatabase[] = "INSERT INTO %s_log (datetime, server_id, severity, location, message) VALUES (NOW(), '%i', '%s', '%s', '%s');";

////////////////////
//Categories Data
enum Category
{
	CategoryId,
	CategoryPriority,
	String:CategoryDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH],
	String:CategoryDescription[STORE_MAX_DESCRIPTION_LENGTH],
	String:CategoryRequirePlugin[STORE_MAX_REQUIREPLUGIN_LENGTH],
	bool:CategoryDisableServerRestriction
}

int g_categories[MAX_CATEGORIES][Category];
int g_categoryCount = -1;

////////////////////
//Items Data
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
	ItemFlags,
	bool:ItemDisableServerRestriction
}

int g_items[MAX_ITEMS][Item];
int g_itemCount = -1;

////////////////////
//Loadouts Data
enum Loadout
{
	LoadoutId,
	String:LoadoutDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH],
	String:LoadoutGame[STORE_MAX_LOADOUTGAME_LENGTH],
	String:LoadoutClass[STORE_MAX_LOADOUTCLASS_LENGTH],
	LoadoutTeam
}

int g_loadouts[MAX_LOADOUTS][Loadout];
int g_loadoutCount = -1;

////////////////////
//Main Menu Data
enum MenuItem
{
	String:MenuItemDisplayName[32],
	String:MenuItemDescription[128],
	String:MenuItemValue[64],
	Handle:MenuItemPlugin,
	Store_MenuItemClickCallback:MenuItemCallback,
	MenuItemOrder,
	bool:MenuItemTranslate,
	bool:MenuItemDisabled
}

int g_menuItems[MAX_MENU_ITEMS + 1][MenuItem];
int g_menuItemCount;

////////////////////
//Chat Commands Data
enum ChatCommand
{
	String:ChatCommandName[32],
	Handle:ChatCommandPlugin,
	Store_ChatCommandCallback:ChatCommandCallback,
}

int g_chatCommands[MAX_CHAT_COMMANDS + 1][ChatCommand];
int g_chatCommandCount;

////////////////////
//Forwards
Handle g_dbInitializedForward;
Handle g_reloadItemsForward;
Handle g_reloadItemsPostForward;
Handle g_hOnChatCommandForward;
Handle g_hOnChatCommandPostForward;
Handle g_hOnCoreLoaded;

////////////////////
//Config Globals
char g_baseURL[256];
DBPriority g_queryPriority;
bool g_motdSound;
bool g_motdFullscreen;
bool g_singleServerMode;
bool g_printSQLQueries;
char g_currencyName[64];
char g_sqlconfigentry[64];
bool g_showChatCommands;
int g_firstConnectionCredits;
bool g_showMenuDescriptions;
int g_serverID;
char g_tokenCharacters[256];
int g_tokenSize;
Store_AccessType g_accessTypes;

////////////////////
//Plugin Globals
bool bDeveloperMode[MAXPLAYERS + 1];
char sClientToken[MAXPLAYERS + 1][MAX_TOKEN_SIZE];

Handle g_hSQL;

Handle hCategoriesCache;
Handle hCategoriesCache2;

Handle hItemsCache;
Handle hItemsCache2;

////////////////////
//Plugin Info
public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = STORE_AUTHORS,
	description = PLUGIN_DESCRIPTION,
	version = STORE_VERSION,
	url = STORE_URL
};

////////////////////
//Plugin Functions
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Store_ReloadCacheStacks", Native_ReloadCacheStacks);
	CreateNative("Store_RegisterPluginModule", Native_RegisterPluginModule);
	CreateNative("Store_GetStoreBaseURL", Native_GetStoreBaseURL);
	CreateNative("Store_OpenMOTDWindow", Native_OpenMOTDWindow);
	CreateNative("Store_OpenMainMenu", Native_OpenMainMenu);
	CreateNative("Store_AddMainMenuItem", Native_AddMainMenuItem);
	CreateNative("Store_AddMainMenuItemEx", Native_AddMainMenuItemEx);
	CreateNative("Store_GetCurrencyName", Native_GetCurrencyName);
	CreateNative("Store_GetSQLEntry", Native_GetSQLEntry);
	CreateNative("Store_RegisterChatCommands", Native_RegisterChatCommands);
	CreateNative("Store_GetServerID", Native_GetServerID);
	CreateNative("Store_ClientIsDeveloper", Native_ClientIsDeveloper);
	CreateNative("Store_GetClientToken", Native_GetClientToken);
	CreateNative("Store_GenerateNewToken", Native_GenerateNewToken);
	
	CreateNative("Store_Register", Native_Register);
	CreateNative("Store_RegisterClient", Native_RegisterClient);
	CreateNative("Store_GetClientAccountID", Native_GetClientAccountID);
	CreateNative("Store_GetClientUserID", Native_GetClientUserID);
	CreateNative("Store_SaveClientToken", Native_SaveClientToken);
	CreateNative("Store_GetUserItems", Native_GetUserItems);
	CreateNative("Store_GetUserItemsCount", Native_GetUserItemsCount);
	CreateNative("Store_GetCredits", Native_GetCredits);
	CreateNative("Store_GetCreditsEx", Native_GetCreditsEx);
	CreateNative("Store_GiveCredits", Native_GiveCredits);
	CreateNative("Store_GiveCreditsToUsers", Native_GiveCreditsToUsers);
	CreateNative("Store_GiveDifferentCreditsToUsers", Native_GiveDifferentCreditsToUsers);
	CreateNative("Store_GiveItem", Native_GiveItem);
	CreateNative("Store_RemoveCredits", Native_RemoveCredits);
	CreateNative("Store_RemoveCreditsFromUsers", Native_RemoveCreditsFromUsers);
	CreateNative("Store_RemoveDifferentCreditsFromUsers", Native_RemoveDifferentCreditsFromUsers);
	CreateNative("Store_BuyItem", Native_BuyItem);
	CreateNative("Store_RemoveUserItem", Native_RemoveUserItem);
	CreateNative("Store_SetItemEquippedState", Native_SetItemEquippedState);
	CreateNative("Store_GetEquippedItemsByType", Native_GetEquippedItemsByType);
	
	CreateNative("Store_GetCategories", Native_GetCategories);
	CreateNative("Store_GetCategoryDisplayName", Native_GetCategoryDisplayName);
	CreateNative("Store_GetCategoryDescription", Native_GetCategoryDescription);
	CreateNative("Store_GetCategoryPluginRequired", Native_GetCategoryPluginRequired);
	CreateNative("Store_GetCategoryServerRestriction", Native_GetCategoryServerRestriction);
	CreateNative("Store_GetCategoryPriority", Native_GetCategoryPriority);
	CreateNative("Store_ProcessCategory", Native_ProcessCategory);
	
	CreateNative("Store_GetItems", Native_GetItems);
	CreateNative("Store_GetItemName", Native_GetItemName);
	CreateNative("Store_GetItemDisplayName", Native_GetItemDisplayName);
	CreateNative("Store_GetItemDescription", Native_GetItemDescription);
	CreateNative("Store_GetItemType", Native_GetItemType);
	CreateNative("Store_GetItemLoadoutSlot", Native_GetItemLoadoutSlot);
	CreateNative("Store_GetItemPrice", Native_GetItemPrice);
	CreateNative("Store_GetItemCategory", Native_GetItemCategory);
	CreateNative("Store_GetItemPriority", Native_GetItemPriority);
	CreateNative("Store_GetItemServerRestriction", Native_GetItemServerRestriction);
	CreateNative("Store_IsItemBuyable", Native_IsItemBuyable);
	CreateNative("Store_IsItemTradeable", Native_IsItemTradeable);
	CreateNative("Store_IsItemRefundable", Native_IsItemRefundable);
	CreateNative("Store_GetItemAttributes", Native_GetItemAttributes);
	CreateNative("Store_WriteItemAttributes", Native_WriteItemAttributes);
	CreateNative("Store_ProcessItem", Native_ProcessItem);
	
	CreateNative("Store_GetLoadouts", Native_GetLoadouts);
	CreateNative("Store_GetLoadoutDisplayName", Native_GetLoadoutDisplayName);
	CreateNative("Store_GetLoadoutGame", Native_GetLoadoutGame);
	CreateNative("Store_GetLoadoutClass", Native_GetLoadoutClass);
	CreateNative("Store_GetLoadoutTeam", Native_GetLoadoutTeam);
	CreateNative("Store_GetClientLoadouts", Native_GetClientLoadouts);
	CreateNative("Store_QueryEquippedLoadout", Native_QueryEquippedLoadout);
	CreateNative("Store_SaveEquippedLoadout", Native_SaveEquippedLoadout);
	
	CreateNative("Store_SQLTQuery", Native_SQLTQuery);
	CreateNative("Store_SQLEscapeString", Native_SQLEscapeString);
	CreateNative("Store_SQLLogQuery", Native_SQLLogQuery);
	
	CreateNative("Store_DisplayClientsMenu", Native_DisplayClientsMenu);
	CreateNative("Store_GetGlobalAccessType", Native_GetGlobalAccessType);
	
	g_dbInitializedForward = CreateGlobalForward("Store_OnDatabaseInitialized", ET_Ignore);
	g_reloadItemsForward = CreateGlobalForward("Store_OnReloadItems", ET_Ignore);
	g_reloadItemsPostForward = CreateGlobalForward("Store_OnReloadItems_Post", ET_Ignore);
	g_hOnChatCommandForward = CreateGlobalForward("Store_OnChatCommand", ET_Event, Param_Cell, Param_String, Param_String);
	g_hOnChatCommandPostForward = CreateGlobalForward("Store_OnChatCommand_Post", ET_Ignore, Param_Cell, Param_String, Param_String);
	g_hOnCoreLoaded = CreateGlobalForward("Store_OnCoreLoaded", ET_Ignore);
	
	RegPluginLibrary("store-core");
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_DONTRECORD);

	RegAdminCmd("sm_reloaditems", Command_ReloadItems, ADMFLAG_ROOT, "Reloads store item cache.");
	RegAdminCmd("sm_devmode", Command_DeveloperMode, ADMFLAG_ROOT, "Toggles developer mode on the client.");
	RegAdminCmd("sm_givecredits", Command_GiveCredits, ADMFLAG_ROOT, "Gives credits to a player.");
	RegAdminCmd("sm_removecredits", Command_RemoveCredits, ADMFLAG_ROOT, "Remove credits from a player.");
	
	hCategoriesCache = CreateArray();
	hCategoriesCache2 = CreateArray();
	hItemsCache = CreateArray();
	hItemsCache2 = CreateArray();
}

public void OnAllPluginsLoaded()
{
	LoadConfig("Core", "configs/store/core.cfg");
	
	Call_StartForward(g_hOnCoreLoaded);
	Call_Finish();
	
	if (IsServerProcessing())
	{
		ConnectSQL();
	}
	else
	{
		CreateTimer(2.0, CheckServerProcessing, _, TIMER_REPEAT);
	}
}

void LoadConfig(const char[] sName, const char[] sFile)
{
	Handle hKV = CreateKeyValues(sName);

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), sFile);

	if (!FileToKeyValues(hKV, sPath))
	{
		CloseHandle(hKV);
		SetFailState("Can't read config file %s", sPath);
	}
	
	KvGetString(hKV, "base_url", g_baseURL, sizeof(g_baseURL));
	
	char sPrioString[32];
	KvGetString(hKV, "query_speed", sPrioString, sizeof(sPrioString));
	
	if (StrEqual(sPrioString, "High", false))
	{
		g_queryPriority = DBPrio_High;
	}
	else if (StrEqual(sPrioString, "Normal", false))
	{
		g_queryPriority = DBPrio_Normal;
	}
	else if (StrEqual(sPrioString, "Low", false))
	{
		g_queryPriority = DBPrio_Low;
	}
	
	g_motdSound = view_as<bool>(KvGetNum(hKV, "motd_sounds", 1));
	g_motdFullscreen = view_as<bool>(KvGetNum(hKV, "motd_fullscreen", 1));
	g_singleServerMode = view_as<bool>(KvGetNum(hKV, "single_server", 0));
	g_printSQLQueries = view_as<bool>(KvGetNum(hKV, "show_sql_queries", 0));

	KvGetString(hKV, "currency_name", g_currencyName, sizeof(g_currencyName), "Credits");
	KvGetString(hKV, "sql_config_entry", g_sqlconfigentry, sizeof(g_sqlconfigentry), "default");

	if (KvJumpToKey(hKV, "Commands"))
	{
		char buffer[256];

		KvGetString(hKV, "mainmenu_commands", buffer, sizeof(buffer), "!store /store");
		Store_RegisterChatCommands(buffer, ChatCommand_OpenMainMenu);

		KvGetString(hKV, "credits_commands", buffer, sizeof(buffer), "!credits /credits");
		Store_RegisterChatCommands(buffer, ChatCommand_Credits);

		KvGoBack(hKV);
	}
	
	g_showChatCommands = view_as<bool>(KvGetNum(hKV, "show_chat_commands", 1));
	g_firstConnectionCredits = KvGetNum(hKV, "first_connection_credits");
	g_showMenuDescriptions = view_as<bool>(KvGetNum(hKV, "show_menu_descriptions", 1));
	g_serverID = KvGetNum(hKV, "server_id", 1);
	
	KvGetString(hKV, "allowed_token_characters", g_tokenCharacters, sizeof(g_tokenCharacters), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789");
	
	g_tokenSize = KvGetNum(hKV, "token_length", 32);
	
	if (g_tokenSize > MAX_TOKEN_SIZE)
	{
		g_tokenSize = MAX_TOKEN_SIZE;
		Store_LogWarning("Token size cannot be more than the size of %i, please fix this in configs. Setting to max value.", MAX_TOKEN_SIZE);
	}
	
	g_accessTypes = view_as<Store_AccessType>(KvGetNum(hKV, "system_access_types", 0));
	
	CloseHandle(hKV);
	
	if (g_singleServerMode)
	{
		Store_LogNotice("SINGLE SERVER MODE IS ON!");
	}
}

public Action CheckServerProcessing(Handle hTimer)
{
	if (!IsServerProcessing())
	{
		return Plugin_Continue;
	}
	
	ConnectSQL();
	return Plugin_Stop;
}

public void OnClientPostAdminCheck(int client)
{
	bDeveloperMode[client] = false;
	Store_RegisterClient(client, g_firstConnectionCredits);
}

public void OnClientDisconnect(int client)
{
	bDeveloperMode[client] = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	char sArgsTrimmed[256];
	int sArgsLen = strlen(sArgs);

	if (sArgsLen >= 2 && sArgs[0] == '"' && sArgs[sArgsLen - 1] == '"')
	{
		strcopy(sArgsTrimmed, sArgsLen - 1, sArgs[1]);
	}
	else
	{
		strcopy(sArgsTrimmed, sizeof(sArgsTrimmed), sArgs);
	}

	char cmds[2][256];
	ExplodeString(sArgsTrimmed, " ", cmds, sizeof(cmds), sizeof(cmds[]), true);

	if (strlen(cmds[0]) <= 0)
	{
		return Plugin_Continue;
	}
	
	for (int i = 0; i < g_chatCommandCount; i++)
	{
		if (StrEqual(cmds[0], g_chatCommands[i][ChatCommandName], false))
		{
			Action result = Plugin_Continue;
			Call_StartForward(g_hOnChatCommandForward);
			Call_PushCell(client);
			Call_PushString(cmds[0]);
			Call_PushString(cmds[1]);
			Call_Finish(result);

			if (result == Plugin_Handled || result == Plugin_Stop)
			{
				return Plugin_Continue;
			}
			
			Call_StartFunction(g_chatCommands[i][ChatCommandPlugin], g_chatCommands[i][ChatCommandCallback]);
			Call_PushCell(client);
			Call_PushString(cmds[0]);
			Call_PushString(cmds[1]);
			Call_Finish();

			Call_StartForward(g_hOnChatCommandPostForward);
			Call_PushCell(client);
			Call_PushString(cmds[0]);
			Call_PushString(cmds[1]);
			Call_Finish();
			
			if (cmds[0][0] == 0x2F)
			{
				return Plugin_Handled;
			}
			
			if (g_showChatCommands)
			{
				return Plugin_Continue;
			}
		}
	}

	return Plugin_Continue;
}

public void ChatCommand_OpenMainMenu(int client)
{
	OpenMainMenu(client);
}

public void ChatCommand_Credits(int client)
{
	Store_GetCredits(GetSteamAccountID(client), OnCommandGetCredits, client);
}

public void OnCommandGetCredits(int credits, any client)
{
	CPrintToChat(client, "%t%t", "Store Tag Colored", "Store Menu Credits", credits, g_currencyName);
}

////////////////////
//Plugin Commands
public Action Command_ReloadItems(int client, int args)
{
	CReplyToCommand(client, "%t%t", "Store Tag Colored", "Reloading categories and items");
	
	if (!ReloadCacheStacks(client))
	{
		CReplyToCommand(client, "There was an error reloading categories & items, please check error logs."); //Translate
	}
	
	return Plugin_Handled;
}

public Action Command_DeveloperMode(int client, int args)
{
	bDeveloperMode[client] = bDeveloperMode[client] ? false : true;
	CPrintToChat(client, "%t%t", "Store Tag Colored", "Store Developer Toggled", bDeveloperMode[client] ? "ON" : "OFF");
	
	return Plugin_Handled;
}

public Action Command_GiveCredits(int client, int args)
{
	if (args < 2)
	{
		CReplyToCommand(client, "%t Usage: sm_givecredits <target-string> <credits>", "Store Tag Colored");
		return Plugin_Handled;
	}
	
	char target[64];
	GetCmdArg(1, target, sizeof(target));
	
	char sAmount[32];
	GetCmdArg(2, sAmount, sizeof(sAmount));
	int iMoney = StringToInt(sAmount);
	
	int target_list[MAXPLAYERS];
	char target_name[MAX_TARGET_LENGTH];
	bool tn_is_ml;
	
	int target_count = ProcessTargetString(target, 0, target_list, MAXPLAYERS, 0, target_name, sizeof(target_name), tn_is_ml);

	if (target_count <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int[] accountIds = new int[target_count];
	int count;
	
	for (int i = 0; i < target_count; i++)
	{
		if (!IsClientInGame(target_list[i]) || IsFakeClient(target_list[i]))
		{
			continue;
		}
		
		accountIds[count] = GetSteamAccountID(target_list[i]);
		count++;

		CPrintToChat(target_list[i], "%t%t", "Store Tag Colored", "Received Credits", iMoney, g_currencyName);
	}

	Store_GiveCreditsToUsers(accountIds, count, iMoney);
	return Plugin_Handled;
}

public Action Command_RemoveCredits(int client, int args)
{
	if (args < 2)
	{
		CReplyToCommand(client, "%t Usage: sm_removecredits <target-string> <credits>", "Store Tag Colored");
		return Plugin_Handled;
	}
	
	char target[64];
	GetCmdArg(1, target, sizeof(target));
	
	char sAmount[32];
	GetCmdArg(2, sAmount, sizeof(sAmount));
	int iMoney = StringToInt(sAmount);
	
	int target_list[MAXPLAYERS];
	char target_name[MAX_TARGET_LENGTH];
	bool tn_is_ml;
	
	int target_count = ProcessTargetString(target, 0, target_list, MAXPLAYERS, 0, target_name, sizeof(target_name), tn_is_ml);

	if (target_count <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		if (!IsClientInGame(target_list[i]) || IsFakeClient(target_list[i]))
		{
			continue;
		}
		
		Store_RemoveCredits(GetSteamAccountID(target_list[i]), iMoney, OnRemoveCreditsCallback, GetClientUserId(client));
	}
	
	return Plugin_Handled;
}

public void OnRemoveCreditsCallback(int accountId, int credits, bool bIsNegative, any data)
{
	int client = GetClientOfUserId(data);
	
	if (client && IsClientInGame(client))
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "Deducted Credits", credits, g_currencyName);
		
		if (bIsNegative)
		{
			CPrintToChat(client, "%t%t", "Store Tag Colored", "Deducted Credits Less Than Zero", g_currencyName);
		}
	}
}

////////////////////
//Functions
void AddMainMenuItem(bool bTranslate = true, const char[] displayName, const char[] description = "", const char[] value = "", Handle plugin = INVALID_HANDLE, Store_MenuItemClickCallback callback, int order = 32, bool bDisabled = false)
{
	int item;
	
	for (; item <= g_menuItemCount; item++)
	{
		if (item == g_menuItemCount || StrEqual(g_menuItems[item][MenuItemDisplayName], displayName))
		{
			break;
		}
	}

	strcopy(g_menuItems[item][MenuItemDisplayName], 32, displayName);
	strcopy(g_menuItems[item][MenuItemDescription], 128, description);
	strcopy(g_menuItems[item][MenuItemValue], 64, value);
	g_menuItems[item][MenuItemPlugin] = plugin;
	g_menuItems[item][MenuItemCallback] = callback;
	g_menuItems[item][MenuItemOrder] = order;
	g_menuItems[item][MenuItemTranslate] = bTranslate;
	g_menuItems[item][MenuItemDisabled] = bDisabled;

	if (item == g_menuItemCount)
	{
		g_menuItemCount++;
	}
}

void SortMainMenuItems()
{
	int sortIndex = sizeof(g_menuItems) - 1;

	for (int x = 0; x < g_menuItemCount; x++)
	{
		for (int y = 0; y < g_menuItemCount; y++)
		{
			if (g_menuItems[x][MenuItemOrder] < g_menuItems[y][MenuItemOrder])
			{
				g_menuItems[sortIndex] = g_menuItems[x];
				g_menuItems[x] = g_menuItems[y];
				g_menuItems[y] = g_menuItems[sortIndex];
			}
		}
	}
}

void OpenMainMenu(int client)
{
	SortMainMenuItems();
	Store_GetCredits(GetSteamAccountID(client), OnGetCreditsComplete, GetClientUserId(client));
}

public void OnGetCreditsComplete(int credits, any data)
{
	int client = GetClientOfUserId(data);

	if (!client)
	{
		return;
	}
	
	Handle menu = CreateMenu(MainMenuSelectHandle);
	SetMenuTitle(menu, "%T%T\n%T\n \n", "Store Menu Title", client, "Store Menu Main Menu", client, STORE_VERSION, "Store Menu Credits", client, g_currencyName, credits);

	for (int item = 0; item < g_menuItemCount; item++)
	{
		char sDisplay[MAX_MESSAGE_LENGTH];
		switch (g_showMenuDescriptions)
		{
			case true:
			{
				switch (g_menuItems[item][MenuItemTranslate])
				{
					case true: Format(sDisplay, sizeof(sDisplay), "%T\n%T", g_menuItems[item][MenuItemDisplayName], client, g_menuItems[item][MenuItemDescription], client);
					case false: Format(sDisplay, sizeof(sDisplay), "%s\n%s", g_menuItems[item][MenuItemDisplayName], g_menuItems[item][MenuItemDescription]);
				}
			}
			case false:
			{
				switch (g_menuItems[item][MenuItemTranslate])
				{
					case true: Format(sDisplay, sizeof(sDisplay), "%T", g_menuItems[item][MenuItemDisplayName], client);
					case false: Format(sDisplay, sizeof(sDisplay), "%s", g_menuItems[item][MenuItemDisplayName]);
				}
			}
		}

		AddMenuItem(menu, g_menuItems[item][MenuItemValue], sDisplay, g_menuItems[item][MenuItemDisabled] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MainMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			Call_StartFunction(g_menuItems[slot][MenuItemPlugin], g_menuItems[slot][MenuItemCallback]);
			Call_PushCell(client);
			Call_PushString(g_menuItems[slot][MenuItemValue]);
			Call_Finish();
		}
		case MenuAction_End: CloseHandle(menu);
	}
}

void GenerateRandomToken(char[] sToken)
{
	String_GetRandom(sToken, MAX_TOKEN_SIZE, g_tokenSize, g_tokenCharacters);
}

bool RegisterCommands(Handle plugin, const char[] commands, Store_ChatCommandCallback callback)
{
	if (g_chatCommandCount >= MAX_CHAT_COMMANDS)
	{
		return false;
	}
	
	char splitcommands[32][32];
	int count;

	count = ExplodeString(commands, " ", splitcommands, sizeof(splitcommands), sizeof(splitcommands[]));

	if (count <= 0)
	{
		return false;
	}
	
	if (g_chatCommandCount + count >= MAX_CHAT_COMMANDS)
	{
		return false;
	}

	for (int i = 0; i < g_chatCommandCount; i++)
	{
		for (int n = 0; n < count; n++)
		{
			if (StrEqual(splitcommands[n], g_chatCommands[i][ChatCommandName], false))
			{
				return false;
			}
		}
	}

	for (int i = 0; i < count; i++)
	{
		strcopy(g_chatCommands[g_chatCommandCount][ChatCommandName], 32, splitcommands[i]);
		g_chatCommands[g_chatCommandCount][ChatCommandPlugin] = plugin;
		g_chatCommands[g_chatCommandCount][ChatCommandCallback] = callback;

		g_chatCommandCount++;
	}

	return true;
}

void Register(int accountId, const char[] name = "", int credits = 0, const char[] token = "", const char[] ip = "")
{
	char safeName[2 * 32 + 1];
	SQL_EscapeString(g_hSQL, name, safeName, sizeof(safeName));

	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_Register, STORE_DATABASE_PREFIX, accountId, safeName, credits, token, ip, safeName, token, ip);
	Store_Local_TQuery("Register", SQLCall_Registration, sQuery);
}

void RegisterClient(int client, int credits = 0)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}
	
	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	
	char sToken[MAX_TOKEN_SIZE];
	Store_GetClientToken(client, sToken, sizeof(sToken));
	
	char sIP[MAX_NAME_LENGTH];
	GetClientIP(client, sIP, sizeof(sIP));

	Register(GetSteamAccountID(client), sName, credits, sToken, sIP);
}

public void SQLCall_Registration(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on Register: %s", error);
	}
}

bool GetCategories(int client = 0, Store_GetItemsCallback callback = INVALID_FUNCTION, Handle plugin = null, bool loadFromCache = true, char[] sPriority, any data = 0)
{
	if (loadFromCache && g_categoryCount != -1)
	{
		int[] categories = new int[g_categoryCount];
		int count = 0;

		for (int category = 0; category < g_categoryCount; category++)
		{
			categories[count] = g_categories[category][CategoryId];
			count++;
		}
		
		if (callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushArray(categories, count);
			Call_PushCell(count);
			Call_PushCell(data);
			Call_Finish();
		}
		
		return true;
	}
	else
	{
		Handle hPack = CreateDataPack();
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, plugin);
		WritePackCell(hPack, data);
		WritePackCell(hPack, client);
		
		char sQuery[MAX_QUERY_SIZE];
		Format(sQuery, sizeof(sQuery), sQuery_GetCategories, STORE_DATABASE_PREFIX, sPriority);
		Store_Local_TQuery("GetCategories", SQLCall_RetrieveCategories, sQuery, hPack);
	}
	
	return true;
}

public void SQLCall_RetrieveCategories(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	Store_GetItemsCallback callback = view_as<Store_GetItemsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	int client = GetClientOfUserId(ReadPackCell(data));

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on GetCategories: %s", error);
		return;
	}

	g_categoryCount = 0;

	while (SQL_FetchRow(hndl))
	{
		g_categories[g_categoryCount][CategoryId] = SQL_FetchInt(hndl, 0);
		g_categories[g_categoryCount][CategoryPriority] = SQL_FetchInt(hndl, 1);
		SQL_FetchString(hndl, 2, g_categories[g_categoryCount][CategoryDisplayName], STORE_MAX_DISPLAY_NAME_LENGTH);
		SQL_FetchString(hndl, 3, g_categories[g_categoryCount][CategoryDescription], STORE_MAX_DESCRIPTION_LENGTH);
		SQL_FetchString(hndl, 4, g_categories[g_categoryCount][CategoryRequirePlugin], STORE_MAX_REQUIREPLUGIN_LENGTH);
		g_categories[g_categoryCount][CategoryDisableServerRestriction] = view_as<bool>(SQL_FetchInt(hndl, 5));

		g_categoryCount++;
	}
	
	GetCategories(client, callback, plugin, true, "", arg);
}

int GetCategoryIndex(int id)
{
	for (int i = 0; i < g_categoryCount; i++)
	{
		if (g_categories[i][CategoryId] == id)
		{
			return i;
		}
	}

	return -1;
}

bool GetItems(int client = 0, Handle filter = null, Store_GetItemsCallback callback = INVALID_FUNCTION, Handle plugin = null, bool loadFromCache = true, const char[] sPriority = "", any data = 0)
{
	if (loadFromCache && g_itemCount != -1)
	{
		int categoryId;
		bool categoryFilter = filter == null ? false : GetTrieValue(filter, "category_id", categoryId);

		bool isBuyable;
		bool buyableFilter = filter == null ? false : GetTrieValue(filter, "is_buyable", isBuyable);

		bool isTradeable;
		bool tradeableFilter = filter == null ? false : GetTrieValue(filter, "is_tradeable", isTradeable);

		bool isRefundable;
		bool refundableFilter = filter == null ? false : GetTrieValue(filter, "is_refundable", isRefundable);

		char type[STORE_MAX_TYPE_LENGTH];
		bool typeFilter = filter == null ? false : GetTrieString(filter, "type", type, sizeof(type));

		int flags;
		bool flagsFilter = filter == null ? false : GetTrieValue(filter, "flags", flags);

		CloseHandle(filter);

		int[] items = new int[g_itemCount];
		
		int count = 0;
		
		for (int item = 0; item < g_itemCount; item++)
		{
			if ((!categoryFilter || categoryId == g_items[item][ItemCategoryId]) && (!buyableFilter || isBuyable == g_items[item][ItemIsBuyable]) && (!tradeableFilter || isTradeable == g_items[item][ItemIsTradeable]) && (!refundableFilter || isRefundable == g_items[item][ItemIsRefundable]) && (!typeFilter || StrEqual(type, g_items[item][ItemType])) && (!flagsFilter || !g_items[item][ItemFlags] || (flags & g_items[item][ItemFlags])))
			{
				items[count] = g_items[item][ItemId];
				count++;
			}
		}
		
		if (callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushArray(items, count);
			Call_PushCell(count);
			Call_PushCell(data);
			Call_Finish();
		}
		
		Call_StartForward(g_reloadItemsPostForward);
		Call_Finish();
		
		return true;
	}
	else
	{
		Call_StartForward(g_reloadItemsForward);
		Call_Finish();
		
		Handle hPack = CreateDataPack();
		WritePackCell(hPack, filter);
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, plugin);
		WritePackCell(hPack, data);
		WritePackCell(hPack, client);
		
		char sQuery[MAX_QUERY_SIZE];
		Format(sQuery, sizeof(sQuery), sQuery_GetItems, STORE_DATABASE_PREFIX, sPriority);
		Store_Local_TQuery("GetItems", SQLCall_RetrieveItems, sQuery, hPack);
	}
	
	return true;
}

public void SQLCall_RetrieveItems(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		CloseHandle(data);
		LogError("SQL Error on GetItems: %s", error);
		return;
	}
	
	ResetPack(data);
	
	Handle filter = view_as<Handle>(ReadPackCell(data));
	Store_GetItemsCallback callback = view_as<Store_GetItemsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	int client = GetClientOfUserId(ReadPackCell(data));

	CloseHandle(data);

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
			int attrsLength = SQL_FetchInt(hndl, 10);
			
			char[] attrs = new char[attrsLength + 1];
			SQL_FetchString(hndl, 9, attrs, attrsLength+1);

			Store_CallItemAttrsCallback(g_items[g_itemCount][ItemType], g_items[g_itemCount][ItemName], attrs);
		}

		g_items[g_itemCount][ItemIsBuyable] = view_as<bool>(SQL_FetchInt(hndl, 11));
		g_items[g_itemCount][ItemIsTradeable] = view_as<bool>(SQL_FetchInt(hndl, 12));
		g_items[g_itemCount][ItemIsRefundable] = view_as<bool>(SQL_FetchInt(hndl, 13));

		char flags[11];
		SQL_FetchString(hndl, 14, flags, sizeof(flags));
		g_items[g_itemCount][ItemFlags] = ReadFlagString(flags);
		
		g_items[g_itemCount][ItemDisableServerRestriction] = view_as<bool>(SQL_FetchInt(hndl, 15));
				
		g_itemCount++;
	}
	
	GetItems(client, filter, callback, plugin, true, "", arg);
}

void GetCacheStacks()
{
	char sQuery[MAX_QUERY_SIZE];
	
	Format(sQuery, sizeof(sQuery), sQuery_CacheRestrictionsCategories, STORE_DATABASE_PREFIX);
	Store_Local_TQuery("GetCategoryCacheStacks", SQLCall_GetCategoryRestrictions, sQuery);
	
	Format(sQuery, sizeof(sQuery), sQuery_CacheRestrictionsItems, STORE_DATABASE_PREFIX);
	Store_Local_TQuery("GetItemCacheStacks", SQLCall_GetItemRestrictions, sQuery);
}

public void SQLCall_GetCategoryRestrictions(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetCategoryRestrictions: %s", error);
		return;
	}
	
	while (SQL_FetchRow(hndl) && !SQL_IsFieldNull(hndl, 0))
	{
		int CategoryID = SQL_FetchInt(hndl, 0);
		int ServerID = SQL_FetchInt(hndl, 1);
		
		PushArrayCell(hCategoriesCache, CategoryID);
		PushArrayCell(hCategoriesCache2, ServerID);
	}
}

public void SQLCall_GetItemRestrictions(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetItemRestrictions: %s", error);
		return;
	}
	
	while (SQL_FetchRow(hndl) && !SQL_IsFieldNull(hndl, 0))
	{
		int ItemID = SQL_FetchInt(hndl, 0);
		int ServerID = SQL_FetchInt(hndl, 1);
		
		PushArrayCell(hItemsCache, ItemID);
		PushArrayCell(hItemsCache2, ServerID);
	}
}

int GetItemIndex(int id)
{
	for (int i = 0; i < g_itemCount; i++)
	{
		if (g_items[i][ItemId] == id)
		{
			return i;
		}
	}

	return -1;
}

void GetItemAttributes(const char[] itemName, Store_ItemGetAttributesCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackString(hPack, itemName);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	int itemNameLength = 2 * strlen(itemName) + 1;

	char[] itemNameSafe = new char[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetItemAttributes, STORE_DATABASE_PREFIX, itemNameSafe);
	Store_Local_TQuery("GetItemAttributes", SQLCall_GetItemAttributes, sQuery, hPack);
}

public void SQLCall_GetItemAttributes(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	char itemName[STORE_MAX_NAME_LENGTH];
	ReadPackString(data, itemName, sizeof(itemName));
	
	Store_ItemGetAttributesCallback callback = view_as<Store_ItemGetAttributesCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetItemAttributes: %s", error);
		return;
	}
	
	if (SQL_FetchRow(hndl) && !SQL_IsFieldNull(hndl, 0))
	{
		int attrsLength = SQL_FetchInt(hndl, 1);
		
		char[] attrs = new char[attrsLength + 1];
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

void WriteItemAttributes(const char[] itemName, const char[] attrs, Store_BuyItemCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	int itemNameLength = 2 * strlen(itemName) + 1;
	char[] itemNameSafe = new char[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);

	int attrsLength = 10 * 1024;
	char[] attrsSafe = new char[2 * attrsLength + 1];
	SQL_EscapeString(g_hSQL, attrs, attrsSafe, 2 * attrsLength + 1);
	
	char[] sQuery = new char[attrsLength + MAX_QUERY_SIZE];
	Format(sQuery, attrsLength + MAX_QUERY_SIZE, sQuery_WriteItemAttributes, STORE_DATABASE_PREFIX, attrsSafe, itemNameSafe);
	Store_Local_TQuery("WriteItemAttributes", SQLCall_WriteItemAttributes, sQuery, hPack);
}

public void SQLCall_WriteItemAttributes(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	Store_BuyItemCallback callback = view_as<Store_BuyItemCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on WriteItemAttributes: %s", error);
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

bool GetLoadouts(Handle filter, Store_GetItemsCallback callback = INVALID_FUNCTION, Handle plugin = null, bool loadFromCache = true, any data = 0)
{
	if (loadFromCache && g_loadoutCount != -1)
	{
		int[] loadouts = new int[g_loadoutCount];
		int count = 0;

		char game[32];
		bool gameFilter = filter == null ? false : GetTrieString(filter, "game", game, sizeof(game));

		char class[32];
		bool classFilter = filter == null ? false : GetTrieString(filter, "class", class, sizeof(class));

		CloseHandle(filter);

		for (int loadout = 0; loadout < g_loadoutCount; loadout++)
		{
			if ((!gameFilter || strlen(game) == 0 || strlen(g_loadouts[loadout][LoadoutGame]) == 0 || StrEqual(game, g_loadouts[loadout][LoadoutGame])) && (!classFilter || strlen(class) == 0 || strlen(g_loadouts[loadout][LoadoutClass]) == 0 || StrEqual(class, g_loadouts[loadout][LoadoutClass])))
			{
				loadouts[count] = g_loadouts[loadout][LoadoutId];
				count++;
			}
		}
		
		if (callback != INVALID_FUNCTION)
		{
			Call_StartFunction(plugin, callback);
			Call_PushArray(loadouts, count);
			Call_PushCell(count);
			Call_PushCell(data);
			Call_Finish();
		}
		
		return true;
	}
	else
	{
		Handle hPack = CreateDataPack();
		WritePackCell(hPack, filter);
		WritePackFunction(hPack, callback);
		WritePackCell(hPack, plugin);
		WritePackCell(hPack, data);
		
		char sQuery[MAX_QUERY_SIZE];
		Format(sQuery, sizeof(sQuery), sQuery_GetLoadouts, STORE_DATABASE_PREFIX);
		Store_Local_TQuery("GetLoadouts", SQLCall_GetLoadouts, sQuery, hPack);
	}
	
	return true;
}

public void SQLCall_GetLoadouts(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		CloseHandle(data);

		LogError("SQL Error on SQLCall_GetLoadouts: %s", error);
		return;
	}
	
	ResetPack(data);
	
	Handle filter = view_as<Handle>(ReadPackCell(data));
	Store_GetItemsCallback callback = view_as<Store_GetItemsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int data2 = ReadPackCell(data);
	
	CloseHandle(data);
	
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
	
	GetLoadouts(filter, callback, plugin, true, data2);
}

int GetLoadoutIndex(int id)
{
	for (int i = 0; i < g_loadoutCount; i++)
	{
		if (g_loadouts[i][LoadoutId] == id)
		{
			return i;
		}
	}

	return -1;
}

void GetClientLoadouts(int accountId, Store_GetUserLoadoutsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetClientLoadouts, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("GetClientLoadouts", SQLCall_GetClientLoadouts, sQuery, hPack);
}

public void SQLCall_GetClientLoadouts(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	int accountId = ReadPackCell(data);
	Store_GetUserLoadoutsCallback callback = view_as<Store_GetUserLoadoutsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetClientLoadouts: %s", error);
		return;
	}
	
	int count = SQL_GetRowCount(hndl);
	
	int[] ids = new int[count];

	int index = 0;
	while (SQL_FetchRow(hndl))
	{
		ids[index] = SQL_FetchInt(hndl, 0);
		index++;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushArray(ids, count);
	Call_PushCell(count);
	Call_PushCell(arg);
	Call_Finish();
}

void QueryEquippedLoadout(int accountId, Store_GetUserEquippedLoadoutCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_QueryEquippedLoadout, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("QueryEquippedLoadout", SQLCall_QueryEquippedLoadout, sQuery, hPack);
}

public void SQLCall_QueryEquippedLoadout(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	int accountId = ReadPackCell(data);
	Store_GetUserEquippedLoadoutCallback callback = view_as<Store_GetUserEquippedLoadoutCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_QueryEquippedLoadout: %s", error);
		return;
	}
	
	if (SQL_FetchRow(hndl))
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(SQL_FetchInt(hndl, 0));
		Call_PushCell(arg);
		Call_Finish();
	}
}

void SaveEquippedLoadout(int accountId, int loadoutId, Store_SaveUserEquippedLoadoutCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_QueryEquippedLoadout, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("SaveEquippedLoadout", SQLCall_SaveEquippedLoadout, sQuery, hPack);
}

public void SQLCall_SaveEquippedLoadout(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	int accountId = ReadPackCell(data);
	int loadoutId = ReadPackCell(data);
	Store_SaveUserEquippedLoadoutCallback callback = view_as<Store_SaveUserEquippedLoadoutCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_SaveEquippedLoadout: %s", error);
		return;
	}
	
	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(loadoutId);
	Call_PushCell(arg);
	Call_Finish();
}

void GetUserItems(Handle filter, int accountId, int loadoutId, Store_GetUserItemsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, filter);
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	if (g_itemCount == -1)
	{
		LogError("Store_GetUserItems has been called before items have loaded.");
		GetItems(0, _, ReloadUserItems, _, true, "", hPack);

		return;
	}
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetUserItems, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, loadoutId, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, accountId, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX);
	
	int categoryId;
	if (GetTrieValue(filter, "category_id", categoryId))
	{
		Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_categoryId, sQuery, STORE_DATABASE_PREFIX, categoryId);
	}
	
	bool isBuyable;
	if (GetTrieValue(filter, "is_buyable", isBuyable))
	{
		Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_isBuyable, sQuery, STORE_DATABASE_PREFIX, isBuyable);
	}
	
	bool isTradeable;
	if (GetTrieValue(filter, "is_tradeable", isTradeable))
	{
		Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_isTradeable, sQuery, STORE_DATABASE_PREFIX, isTradeable);
	}
	
	bool isRefundable;
	if (GetTrieValue(filter, "is_refundable", isRefundable))
	{
		Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_isRefundable, sQuery, STORE_DATABASE_PREFIX, isRefundable);
	}
	
	char type[STORE_MAX_TYPE_LENGTH];
	if (GetTrieString(filter, "type", type, sizeof(type)))
	{
		int typeLength = 2 * strlen(type) + 1;
		
		char[] buffer = new char[typeLength];
		SQL_EscapeString(g_hSQL, type, buffer, typeLength);

		Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_type, sQuery, STORE_DATABASE_PREFIX, buffer);
	}

	CloseHandle(filter);
	
	Format(sQuery, sizeof(sQuery), sQuery_GetUserItems_GroupByID, sQuery);
	Store_Local_TQuery("GetUserItems", SQLCall_GetUserItems, sQuery, hPack);
}

public void ReloadUserItems(int[] ids, int count, any hPack)
{
	ResetPack(hPack);

	Handle filter = view_as<Handle>(ReadPackCell(hPack));
	int accountId = ReadPackCell(hPack);
	int loadoutId = ReadPackCell(hPack);
	Store_GetUserItemsCallback callback = view_as<Store_GetUserItemsCallback>(ReadPackFunction(hPack));
	Handle plugin = view_as<Handle>(ReadPackCell(hPack));
	int arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	GetUserItems(filter, accountId, loadoutId, callback, plugin, arg);
}

public void SQLCall_GetUserItems(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	ReadPackCell(data);
	ReadPackCell(data);
	
	int loadoutId = ReadPackCell(data);
	Store_GetUserItemsCallback callback = view_as<Store_GetUserItemsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetUserItems: %s", error);
		return;
	}
	
	int count = SQL_GetRowCount(hndl);
	
	int[] ids = new int[count];
	bool[] equipped = new bool[count];
	int[] itemCount = new int[count];

	int index = 0;
	while (SQL_FetchRow(hndl))
	{
		ids[index] = SQL_FetchInt(hndl, 0);
		equipped[index] = view_as<bool>(SQL_FetchInt(hndl, 1));
		itemCount[index] = SQL_FetchInt(hndl, 2);

		index++;
	}

	Call_StartFunction(plugin, callback);
	Call_PushArray(ids, count);
	Call_PushArray(equipped, count);
	Call_PushArray(itemCount, count);
	Call_PushCell(count);
	Call_PushCell(loadoutId);
	Call_PushCell(arg);
	Call_Finish();
}

void GetUserItemsCount(int accountId, const char[] itemName, Store_GetUserItemsCountCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	int itemNameLength = 2 * strlen(itemName) + 1;
	
	char[] itemNameSafe = new char[itemNameLength];
	SQL_EscapeString(g_hSQL, itemName, itemNameSafe, itemNameLength);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetUserItemsCount, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, itemNameSafe, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("GetUserItemsCount", SQLCall_GetUserItemsCount, sQuery, hPack);
}

public void SQLCall_GetUserItemsCount(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	Store_GetUserItemsCountCallback callback = view_as<Store_GetUserItemsCountCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetUserItemsCount: %s", error);
		return;
	}

	if (SQL_FetchRow(hndl))
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(SQL_FetchInt(hndl, 0));
		Call_PushCell(arg);
		Call_Finish();
	}
}

void GetCredits(int accountId, Store_GetCreditsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetCredits, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("GetCredits", SQLCall_GetCredits, sQuery, hPack);
}

public void SQLCall_GetCredits(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	Store_GetCreditsCallback callback = view_as<Store_GetCreditsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on GetCredits: %s", error);
		return;
	}
	
	if (SQL_FetchRow(hndl))
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(SQL_FetchInt(hndl, 0));
		Call_PushCell(arg);
		Call_Finish();
	}
}

void BuyItem(int accountId, int itemId, Store_BuyItemCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	GetCredits(accountId, OnGetCreditsForItemBuy, _, hPack);
}

public void OnGetCreditsForItemBuy(int credits, any hPack)
{
	ResetPack(hPack);

	int itemId = ReadPackCell(hPack);
	int accountId = ReadPackCell(hPack);
	Store_BuyItemCallback callback = view_as<Store_BuyItemCallback>(ReadPackFunction(hPack));
	Handle plugin = view_as<Handle>(ReadPackCell(hPack));
	int arg = ReadPackCell(hPack);

	if (credits < g_items[GetItemIndex(itemId)][ItemPrice])
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(0);
		Call_PushCell(arg);
		Call_Finish();

		return;
	}

	RemoveCredits(accountId, g_items[GetItemIndex(itemId)][ItemPrice], OnBuyItemGiveItem, _, hPack);
}

public void OnBuyItemGiveItem(int accountId, int credits, bool bNegative, any hPack)
{
	ResetPack(hPack);

	int itemId = ReadPackCell(hPack);
	GiveItem(accountId, itemId, Store_Shop, OnGiveItemFromBuyItem, _, hPack);
}

public void OnGiveItemFromBuyItem(int accountId, any hPack)
{
	ResetPack(hPack);
	ReadPackCell(hPack);
	ReadPackCell(hPack);
	
	Store_BuyItemCallback callback = view_as<Store_BuyItemCallback>(ReadPackFunction(hPack));
	Handle plugin = view_as<Handle>(ReadPackCell(hPack));
	int arg = ReadPackCell(hPack);

	CloseHandle(hPack);

	Call_StartFunction(plugin, callback);
	Call_PushCell(1);
	Call_PushCell(arg);
	Call_Finish();
}

void RemoveUserItem(int accountId, int itemId, Store_UseItemCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	UnequipItem(accountId, itemId, -1, OnRemoveUserItem, _, hPack);
}

public void OnRemoveUserItem(int accountId, int itemId, int loadoutId, any hPack)
{
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_RemoveUserItem, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, itemId, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("RemoveUserItemUnequipCallback", SQLCall_RemoveUserItem, sQuery, hPack);
}

public void SQLCall_RemoveUserItem(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	int itemId = ReadPackCell(data);
	Store_UseItemCallback callback = view_as<Store_UseItemCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_RemoveUserItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(arg);
	Call_Finish();
}

void SetItemEquippedState(int accountId, int itemId, int loadoutId, bool isEquipped, Store_EquipItemCallback callback, Handle plugin = null, any data = 0)
{
	switch (isEquipped)
	{
		case true: EquipItem(accountId, itemId, loadoutId, callback, plugin, data);
		case false: UnequipItem(accountId, itemId, loadoutId, callback, plugin, data);
	}
}

void EquipItem(int accountId, int itemId, int loadoutId, Store_EquipItemCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	UnequipItem(accountId, itemId, loadoutId, OnUnequipItemToEquipNewItem, _, hPack);
}

public void OnUnequipItemToEquipNewItem(int accountId, int itemId, int loadoutId, any hPack)
{
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_EquipUnequipItem, STORE_DATABASE_PREFIX, loadoutId, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, accountId, STORE_DATABASE_PREFIX, itemId);
	Store_Local_TQuery("EquipUnequipItemCallback", SQLCall_EquipItem, sQuery, hPack);
}

public void SQLCall_EquipItem(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	int itemId = ReadPackCell(data);
	int loadoutId = ReadPackCell(data);
	Store_GiveCreditsCallback callback = view_as<Store_GiveCreditsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_EquipItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(loadoutId);
	Call_PushCell(arg);
	Call_Finish();
}

void UnequipItem(int accountId, int itemId, int loadoutId, Store_EquipItemCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, itemId);
	WritePackCell(hPack, loadoutId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_UnequipItem, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, accountId, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, itemId);

	if (loadoutId != -1)
	{
		Format(sQuery, sizeof(sQuery), sQuery_UnequipItem_loadoutId, sQuery, STORE_DATABASE_PREFIX, loadoutId);
	}
	
	Store_Local_TQuery("UnequipItem", SQLCall_UnequipItem, sQuery, hPack);
}

public void SQLCall_UnequipItem(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	int itemId = ReadPackCell(data);
	int loadoutId = ReadPackCell(data);
	Store_GiveCreditsCallback callback = view_as<Store_GiveCreditsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_UnequipItem: %s", error);
		return;
	}

	Call_StartFunction(plugin, callback);
	Call_PushCell(accountId);
	Call_PushCell(itemId);
	Call_PushCell(loadoutId);
	Call_PushCell(arg);
	Call_Finish();
}

void GetEquippedItemsByType(int accountId, const char[] type, int loadoutId, Store_GetItemsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetEquippedItemsByType, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, accountId, STORE_DATABASE_PREFIX, type, STORE_DATABASE_PREFIX, loadoutId);
	Store_Local_TQuery("GetEquipptedItemsByType", SQLCall_GetEquippedItemsByType, sQuery, hPack);
}

public void SQLCall_GetEquippedItemsByType(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	Store_GetItemsCallback callback = view_as<Store_GetItemsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GetEquippedItemsByType: %s", error);
		return;
	}

	int count = SQL_GetRowCount(hndl);
	int[] ids = new int[count];

	int index = 0;
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

void GiveCredits(int accountId, int credits, Store_GiveCreditsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, credits);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GiveCredits, STORE_DATABASE_PREFIX, credits, accountId);
	Store_Local_TQuery("GiveCredits", SQLCall_GiveCredits, sQuery, hPack);
}

public void SQLCall_GiveCredits(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	int credits = ReadPackCell(data);
	Store_GiveCreditsCallback callback = view_as<Store_GiveCreditsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GiveCredits: %s", error);
		return;
	}

	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(credits);
		Call_PushCell(arg);
		Call_Finish();
	}
}

void RemoveCredits(int accountId, int credits, Store_RemoveCreditsCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackCell(hPack, credits);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);
	
	bool bIsNegative;
	if (Store_GetCreditsEx(accountId) < credits)
	{
		bIsNegative = true;
		WritePackCell(hPack, bIsNegative);
		
		char sQuery[MAX_QUERY_SIZE];
		Format(sQuery, sizeof(sQuery), sQuery_RemoveCredits_Negative, STORE_DATABASE_PREFIX, accountId);
		Store_Local_TQuery("RemoveCredits", SQLCall_RemoveCredits, sQuery, hPack);
		
		return;
	}
	
	WritePackCell(hPack, bIsNegative);

	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_RemoveCredits, STORE_DATABASE_PREFIX, credits, accountId);
	Store_Local_TQuery("RemoveCredits", SQLCall_RemoveCredits, sQuery, hPack);
}

public void SQLCall_RemoveCredits(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	int credits = ReadPackCell(data);
	Store_RemoveCreditsCallback callback = view_as<Store_RemoveCreditsCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	int bIsNegative = view_as<bool>(ReadPackCell(data));

	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_RemoveCredits: %s", error);
		return;
	}

	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(credits);
		Call_PushCell(bIsNegative);
		Call_PushCell(arg);
		Call_Finish();
	}
}

void GiveItem(int accountId, int itemId, Store_AcquireMethod acquireMethod = Store_Unknown, Store_AccountCallback callback, Handle plugin = null, any data = 0)
{
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, accountId);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, plugin);
	WritePackCell(hPack, data);

	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GiveItem, STORE_DATABASE_PREFIX, STORE_DATABASE_PREFIX, itemId);
	
	switch (acquireMethod)
	{
		case Store_Shop: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Shop, sQuery);
		case Store_Trade: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Trade, sQuery);
		case Store_Gift: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Gift, sQuery);
		case Store_Admin: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Admin, sQuery);
		case Store_Web: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Web, sQuery);
		case Store_Unknown: Format(sQuery, sizeof(sQuery), sQuery_GiveItem_Unknown, sQuery);
	}

	Format(sQuery, sizeof(sQuery), sQuery_GiveItem_End, sQuery, STORE_DATABASE_PREFIX, accountId);
	Store_Local_TQuery("GiveItem", SQLCall_GiveItem, sQuery, hPack);
}

public void SQLCall_GiveItem(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);

	int accountId = ReadPackCell(data);
	Store_AccountCallback callback = view_as<Store_AccountCallback>(ReadPackFunction(data));
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	int arg = ReadPackCell(data);
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GiveItem: %s", error);
		return;
	}
	
	if (callback != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, callback);
		Call_PushCell(accountId);
		Call_PushCell(arg);
		Call_Finish();
	}
}

void GiveCreditsToUsers(int[] accountIds, int accountIdsLength, int credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GiveCreditsToUsers, STORE_DATABASE_PREFIX, credits);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), sQuery_GiveCreditsToUsers_End, sQuery);
	Store_Local_TQuery("GiveCreditsToUsers", SQLCall_GiveCreditsToUsers, sQuery);
}

public void SQLCall_GiveCreditsToUsers(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_GiveCreditsToUsers: %s", error);
	}
}

void RemoveCreditsFromUsers(int[] accountIds, int accountIdsLength, int credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_RemoveCreditsFromUsers, STORE_DATABASE_PREFIX, credits);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), sQuery_RemoveCreditsFromUsers_End, sQuery);
	Store_Local_TQuery("RemoveCreditsFromUsers", SQLCall_RemoveCreditsFromUsers, sQuery);
}

public void SQLCall_RemoveCreditsFromUsers(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on RemoveCreditsFromUsers: %s", error);
	}
}

void GiveDifferentCreditsToUsers(int[] accountIds, int accountIdsLength, int[] credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GiveDifferentCreditsToUsers, STORE_DATABASE_PREFIX);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), sQuery_RemoveDifferentCreditsFromUsers_accountIdsLength, sQuery, accountIds[i], credits[i]);
	}

	Format(sQuery, sizeof(sQuery), sQuery_GiveDifferentCreditsToUsers_End, sQuery);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), "%s)", sQuery);
	Store_Local_TQuery("GiveDifferentCreditsToUsers", SQLCall_GiveDifferentCreditsToUsers, sQuery);
}

public void SQLCall_GiveDifferentCreditsToUsers(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on GiveDifferentCreditsToUsers: %s", error);
	}
}

void RemoveDifferentCreditsFromUsers(int[] accountIds, int accountIdsLength, int[] credits)
{
	if (accountIdsLength == 0)
	{
		return;
	}
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_RemoveDifferentCreditsFromUsers, STORE_DATABASE_PREFIX);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), sQuery_GiveDifferentCreditsToUsers_accountIdsLength, sQuery, accountIds[i], credits[i]);
	}

	Format(sQuery, sizeof(sQuery), sQuery_RemoveDifferentCreditsFromUsers_End, sQuery);

	for (int i = 0; i < accountIdsLength; i++)
	{
		Format(sQuery, sizeof(sQuery), "%s%d", sQuery, accountIds[i]);

		if (i < accountIdsLength - 1)
		{
			Format(sQuery, sizeof(sQuery), "%s, ", sQuery);
		}
	}

	Format(sQuery, sizeof(sQuery), "%s)", sQuery);
	Store_Local_TQuery("RemoveDifferentCreditsFromUsers", SQLCall_RemoveDifferentCreditsFromUsers, sQuery);
}

public void SQLCall_RemoveDifferentCreditsFromUsers(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_RemoveDifferentCreditsFromUsers: %s", error);
	}
}

bool ReloadCacheStacks(int client = 0)
{
	if (g_hSQL != null)
	{
		return false;
	}
	
	if (GetCategories(client, _, _, false, ""))
	{
		CPrintToChatAll("%t%t", "Store Tag Colored", "Reloaded categories");
	}
	
	if (GetItems(client, _, _, _, false, ""))
	{
		CPrintToChatAll("%t%t", "Store Tag Colored", "Reloaded items");
	}
	
	GetCacheStacks();
	
	return true;
}

void ConnectSQL()
{
	if (g_hSQL != null)
	{
		CloseHandle(g_hSQL);
		g_hSQL = null;
	}

	char sBuffer[64];
	Store_GetSQLEntry(sBuffer, sizeof(sBuffer));

	if (SQL_CheckConfig(sBuffer))
	{
		SQL_TConnect(SQLCall_ConnectToDatabase, sBuffer);
	}
	else
	{
		SetFailState("No config entry found for '%s' in databases.cfg.", sBuffer);
	}
}

public void SQLCall_ConnectToDatabase(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Connection to SQL database has failed! Error: %s", error);
		return;
	}
	
	g_hSQL = CloneHandle(hndl);
	SQL_SetCharset(g_hSQL, "utf8");
	
	CloseHandle(hndl);
	
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
	
	Call_StartForward(g_dbInitializedForward);
	Call_Finish();
	
	ReloadCacheStacks();
}

void Store_Local_TQuery(const char[] sQueryName, SQLTCallback callback, const char[] sQuery, any data = 0)
{
	SQL_TQuery(g_hSQL, callback, sQuery, data, g_queryPriority);
	
	if (g_printSQLQueries && strlen(sQueryName) != 0)
	{
		
	}
}

////////////////////
//Natives
public int Native_ReloadCacheStacks(Handle plugin, int numParams)
{
	ReloadCacheStacks();
}

public int Native_RegisterPluginModule(Handle plugin, int numParams)
{
	int ServerID = Store_GetServerID();
	
	int length;
	GetNativeStringLength(1, length);
	
	char[] sName = new char[length + 1];
	GetNativeString(1, sName, length + 1);
	
	int length2;
	GetNativeStringLength(2, length2);
	
	char[] sDescription = new char[length2 + 1];
	GetNativeString(2, sDescription, length2 + 1);
	
	int length3;
	GetNativeStringLength(3, length3);
	
	char[] sVersion_ConVar = new char[length3 + 1];
	GetNativeString(3, sVersion_ConVar, length3 + 1);
	
	int length4;
	GetNativeStringLength(4, length4);
	
	char[] sVersion = new char[length4 + 1];
	GetNativeString(4, sVersion, length4 + 1);
	
	if (ServerID <= 0)
	{
		LogError("Error registering module '%s - %s' due to ServerID being 0 or below, please fix this issue.", sName, sVersion);
		return;
	}
		
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_RegisterPluginModule, STORE_DATABASE_PREFIX, sName, sDescription, sVersion_ConVar, sVersion, ServerID);
	Store_Local_TQuery("RegisterPluginModule", SQLCall_RegisterPluginModule, sQuery);
}

public int Native_GetStoreBaseURL(Handle plugin, int numParams)
{
	SetNativeString(1, g_baseURL, GetNativeCell(2));
}

public int Native_OpenMOTDWindow(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (!client || !IsClientInGame(client))
	{
		return false;
	}
	
	int size;
	
	GetNativeStringLength(2, size);
	
	char[] sTitle = new char[size + 1];
	GetNativeString(2, sTitle, size + 1);
	
	GetNativeStringLength(3, size);
	
	char[] sURL = new char[size + 1];
	GetNativeString(3, sURL, size + 1);
	
	char sSound[PLATFORM_MAX_PATH];
	GetNativeString(4, sSound, sizeof(sSound));
	
	switch (GetEngineVersion())
	{
		case Engine_CSGO:
		{
			ShowMOTDPanel(client, sTitle, sURL, MOTDPANEL_TYPE_URL);
		}
		
		default:
		{
			Handle Radio = CreateKeyValues("motd");
			KvSetString(Radio, "title", sTitle);
			KvSetString(Radio, "type", "2");
			KvSetString(Radio, "msg", sURL);
			KvSetNum(Radio, "cmd", 5);
			KvSetNum(Radio, "customsvr", g_motdFullscreen ? 1 : 0);
			ShowVGUIPanel(client, "info", Radio, true);
			CloseHandle(Radio);
		}
	}
	
	if (g_motdSound && strlen(sSound) != 0)
	{
		EmitSoundToClient(client, sSound);
	}
	
	return true;
}

public int Native_OpenMainMenu(Handle plugin, int params)
{
	OpenMainMenu(GetNativeCell(1));
}

public int Native_AddMainMenuItem(Handle plugin, int params)
{
	char displayName[32];
	GetNativeString(1, displayName, sizeof(displayName));

	char description[128];
	GetNativeString(2, description, sizeof(description));

	char value[64];
	GetNativeString(3, value, sizeof(value));

	AddMainMenuItem(true, displayName, description, value, plugin, view_as<Store_MenuItemClickCallback>(GetNativeFunction(4)), GetNativeCell(5));
}

public int Native_AddMainMenuItemEx(Handle plugin, int params)
{
	char displayName[32];
	GetNativeString(1, displayName, sizeof(displayName));

	char description[128];
	GetNativeString(2, description, sizeof(description));

	char value[64];
	GetNativeString(3, value, sizeof(value));

	AddMainMenuItem(false, displayName, description, value, plugin, view_as<Store_MenuItemClickCallback>(GetNativeFunction(4)), GetNativeCell(5));
}

public int Native_GetCurrencyName(Handle plugin, int params)
{
	SetNativeString(1, g_currencyName, GetNativeCell(2));
}

public int Native_GetSQLEntry(Handle plugin, int params)
{
	SetNativeString(1, g_sqlconfigentry, GetNativeCell(2));
}

public int Native_RegisterChatCommands(Handle plugin, int params)
{
	char command[32];
	GetNativeString(1, command, sizeof(command));

	return RegisterCommands(plugin, command, view_as<Store_ChatCommandCallback>(GetNativeFunction(2)));
}

public int Native_GetServerID(Handle plugin, int params)
{
	if (g_serverID < 0)
	{
		char sPluginName[128];
		GetPluginInfo(plugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
		
		LogError("Plugin Module '%s' attempted to get the serverID when It's currently set to a number below 0.", sPluginName);
		
		return 0;
	}
	
	return g_serverID;
}

public int Native_ClientIsDeveloper(Handle plugin, int params)
{
	return bDeveloperMode[GetNativeCell(1)];
}

public int Native_GetClientToken(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (strlen(sClientToken[client]) == 0)
	{
		char sToken[MAX_TOKEN_SIZE];
		GenerateRandomToken(sToken);
		strcopy(sClientToken[client], MAX_TOKEN_SIZE, sToken);
	}
	
	SetNativeString(2, sClientToken[client], GetNativeCell(3));
}

public int Native_GenerateNewToken(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	char sToken[MAX_TOKEN_SIZE];
	GenerateRandomToken(sToken);
	strcopy(sClientToken[client], MAX_TOKEN_SIZE, sToken);
	
	Store_SaveClientToken(client, sToken);
}

/////
//User Natives
public int Native_Register(Handle plugin, int numParams)
{
	char name[MAX_NAME_LENGTH];
	GetNativeString(2, name, sizeof(name));

	Register(GetNativeCell(1), name, GetNativeCell(3));
}

public int Native_RegisterClient(Handle plugin, int numParams)
{
	RegisterClient(GetNativeCell(1), GetNativeCell(2));
}

public int Native_GetClientAccountID(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int AccountID = GetSteamAccountID(client);
	
	if (AccountID == 0)
	{
		ThrowNativeError(SP_ERROR_INDEX, "Error retrieving client Steam Account ID %L.", client);
	}
	
	return AccountID;
}

public int Native_GetClientUserID(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetClientUserID, STORE_DATABASE_PREFIX, GetSteamAccountID(client));
	Handle hQuery = SQL_Query(g_hSQL, sQuery);
	
	int user_id = -1;
	
	if (hQuery == null)
	{
		char sError[512];
		SQL_GetError(g_hSQL, sError, sizeof(sError));
		LogError("SQL Error on Native_GetClientUserID: %s", sError);
		return user_id;
	}
		
	if (SQL_FetchRow(hQuery))
	{
		user_id = SQL_FetchInt(hQuery, 0);
	}
	
	CloseHandle(hQuery);
	
	return user_id;
}

public int Native_SaveClientToken(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	char sToken[MAX_TOKEN_SIZE];
	GetNativeString(2, sToken, sizeof(sToken));
	
	bool bVerbose = view_as<bool>(GetNativeCell(3));
	
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackString(hPack, sToken);
	WritePackCell(hPack, bVerbose);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GenerateNewToken, STORE_DATABASE_PREFIX, sToken, GetSteamAccountID(client));
	Store_Local_TQuery("GenerateNewToken", SQLCall_GenerateNewToken, sQuery, hPack);
}

public int Native_GetUserItems(Handle plugin, int numParams)
{
	GetUserItems(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), view_as<Store_GetUserItemsCallback>(GetNativeFunction(4)), plugin, view_as<any>(GetNativeCell(5)));
}

public int Native_GetUserItemsCount(Handle plugin, int numParams)
{
	char itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(2, itemName, sizeof(itemName));

	GetUserItemsCount(GetNativeCell(1), itemName, view_as<Store_GetUserItemsCountCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_GetCredits(Handle plugin, int numParams)
{
	GetCredits(GetNativeCell(1), view_as<Store_GetCreditsCallback>(GetNativeFunction(2)), plugin, view_as<any>(GetNativeCell(3)));
}

public int Native_GetCreditsEx(Handle plugin, int numParams)
{	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_GetCreditsEx, STORE_DATABASE_PREFIX, GetNativeCell(1));
	Handle hQuery = SQL_Query(g_hSQL, sQuery);
	
	int credits = -1;
	
	if (hQuery == null)
	{
		char sError[512];
		SQL_GetError(g_hSQL, sError, sizeof(sError));
		LogError("SQL Error on GetCreditsEx: %s", sError);
		return credits;
	}
		
	if (SQL_FetchRow(hQuery))
	{
		credits = SQL_FetchInt(hQuery, 0);
	}
	
	CloseHandle(hQuery);
	
	return credits;
}

public int Native_GiveCredits(Handle plugin, int numParams)
{
	GiveCredits(GetNativeCell(1), GetNativeCell(2), view_as<Store_GiveCreditsCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_GiveCreditsToUsers(Handle plugin, int numParams)
{
	int length = GetNativeCell(2);
	
	int[] accountIds = new int[length];
	GetNativeArray(1, accountIds, length);

	GiveCreditsToUsers(accountIds, length, GetNativeCell(3));
}

public int Native_GiveDifferentCreditsToUsers(Handle plugin, int params)
{
	int length = GetNativeCell(2);

	int[] accountIds = new int[length];
	GetNativeArray(1, accountIds, length);

	int[] credits = new int[length];
	GetNativeArray(3, credits, length);

	GiveDifferentCreditsToUsers(accountIds, length, credits);
}

public int Native_GiveItem(Handle plugin, int numParams)
{
	GiveItem(GetNativeCell(1), GetNativeCell(2), view_as<Store_AcquireMethod>(GetNativeCell(3)), view_as<Store_AccountCallback>(GetNativeFunction(4)), plugin, view_as<any>(GetNativeCell(5)));
}

public int Native_RemoveCredits(Handle plugin, int numParams)
{
	RemoveCredits(GetNativeCell(1), GetNativeCell(2), view_as<Store_RemoveCreditsCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_RemoveCreditsFromUsers(Handle plugin, int numParams)
{
	int length = GetNativeCell(2);

	int[] accountIds = new int[length];
	GetNativeArray(1, accountIds, length);

	RemoveCreditsFromUsers(accountIds, length, GetNativeCell(3));
}

public int Native_RemoveDifferentCreditsFromUsers(Handle plugin, int numParams)
{
	int length = GetNativeCell(2);

	int[] accountIds = new int[length];
	GetNativeArray(1, accountIds, length);

	int[] credits = new int[length];
	GetNativeArray(3, credits, length);

	RemoveDifferentCreditsFromUsers(accountIds, length, credits);
}

public int Native_BuyItem(Handle plugin, int numParams)
{
	BuyItem(GetNativeCell(1), GetNativeCell(2), view_as<Store_BuyItemCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_RemoveUserItem(Handle plugin, int numParams)
{
	RemoveUserItem(GetNativeCell(1), GetNativeCell(2), view_as<Store_UseItemCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_SetItemEquippedState(Handle plugin, int numParams)
{
	SetItemEquippedState(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), view_as<Store_EquipItemCallback>(GetNativeFunction(5)), plugin, view_as<any>(GetNativeCell(6)));
}

public int Native_GetEquippedItemsByType(Handle plugin, int numParams)
{
	char type[32];
	GetNativeString(2, type, sizeof(type));
	
	GetEquippedItemsByType(GetNativeCell(1), type, GetNativeCell(3), view_as<Store_GetItemsCallback>(GetNativeFunction(4)), plugin, view_as<any>(GetNativeCell(5)));
}

/////
//Categories Natives
public int Native_GetCategories(Handle plugin, int numParams)
{
	int length;
	GetNativeStringLength(3, length);
	
	char[] sString = new char[length + 1];
	GetNativeString(3, sString, length + 1);
	
	GetCategories(0, view_as<Store_GetItemsCallback>(GetNativeFunction(1)), plugin, GetNativeCell(2), sString, view_as<any>(GetNativeCell(4)));
}

public int Native_GetCategoryDisplayName(Handle plugin, int numParams)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryDisplayName], GetNativeCell(3));
}

public int Native_GetCategoryDescription(Handle plugin, int numParams)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryDescription], GetNativeCell(3));
}

public int Native_GetCategoryPluginRequired(Handle plugin, int numParams)
{
	SetNativeString(2, g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryRequirePlugin], GetNativeCell(3));
}

public int Native_GetCategoryServerRestriction(Handle plugin, int numParams)
{
	return g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryDisableServerRestriction];
}

public int Native_GetCategoryPriority(Handle plugin, int numParams)
{
	return g_categories[GetCategoryIndex(GetNativeCell(1))][CategoryPriority];
}

public int Native_ProcessCategory(Handle plugin, int numParams)
{
	int ServerID = GetNativeCell(1);
	int CategoryID = GetNativeCell(2);
	
	if (ServerID <= 0)
	{
		return true;
	}
	
	for (int i = 0; i < GetArraySize(hCategoriesCache); i++)
	{
		if (GetArrayCell(hCategoriesCache, i) == CategoryID)
		{
			if (GetArrayCell(hCategoriesCache2, i) == ServerID)
			{
				return true;
			}
		}
	}
	
	return false;
}

/////
//Item Natives
public int Native_GetItems(Handle plugin, int numParams)
{
	int length;
	GetNativeStringLength(4, length);
	
	char[] sString = new char[length + 1];
	GetNativeString(4, sString, length + 1);
	
	GetItems(0, GetNativeCell(1), view_as<Store_GetItemsCallback>(GetNativeFunction(2)), plugin, GetNativeCell(3), sString, view_as<any>(GetNativeCell(5)));
}

public int Native_GetItemName(Handle plugin, int numParams)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemName], GetNativeCell(3));
}

public int Native_GetItemDisplayName(Handle plugin, int numParams)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemDisplayName], GetNativeCell(3));
}

public int Native_GetItemDescription(Handle plugin, int numParams)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemDescription], GetNativeCell(3));
}

public int Native_GetItemType(Handle plugin, int numParams)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemType], GetNativeCell(3));
}

public int Native_GetItemLoadoutSlot(Handle plugin, int numParams)
{
	SetNativeString(2, g_items[GetItemIndex(GetNativeCell(1))][ItemLoadoutSlot], GetNativeCell(3));
}

public int Native_GetItemPrice(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemPrice];
}

public int Native_GetItemCategory(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemCategoryId];
}

public int Native_GetItemPriority(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemPriority];
}

public int Native_GetItemServerRestriction(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemDisableServerRestriction];
}

public int Native_IsItemBuyable(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsBuyable];
}

public int Native_IsItemTradeable(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsTradeable];
}

public int Native_IsItemRefundable(Handle plugin, int numParams)
{
	return g_items[GetItemIndex(GetNativeCell(1))][ItemIsRefundable];
}

public int Native_GetItemAttributes(Handle plugin, int numParams)
{
	char itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(1, itemName, sizeof(itemName));

	GetItemAttributes(itemName, view_as<Store_ItemGetAttributesCallback>(GetNativeFunction(2)), plugin, view_as<any>(GetNativeCell(3)));
}

public int Native_WriteItemAttributes(Handle plugin, int numParams)
{
	char itemName[STORE_MAX_NAME_LENGTH];
	GetNativeString(1, itemName, sizeof(itemName));

	int attrsLength = 10 * 1024;
	GetNativeStringLength(2, attrsLength);
	
	char[] attrs = new char[attrsLength + 1];
	GetNativeString(2, attrs, attrsLength + 1);

	WriteItemAttributes(itemName, attrs, view_as<Store_BuyItemCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

public int Native_ProcessItem(Handle plugin, int numParams)
{
	int ServerID = GetNativeCell(1);
	int ItemID = GetNativeCell(2);
	
	if (ServerID <= 0)
	{
		return true;
	}
	
	for (int i = 0; i < GetArraySize(hItemsCache); i++)
	{
		if (GetArrayCell(hItemsCache, i) == ItemID)
		{
			if (GetArrayCell(hItemsCache2, i) == ServerID)
			{
				return true;
			}
		}
	}
	
	return false;
}

/////
//Loadout Natives
public int Native_GetLoadouts(Handle plugin, int numParams)
{
	GetLoadouts(GetNativeCell(1), view_as<Store_GetItemsCallback>(GetNativeFunction(2)), plugin, GetNativeCell(3), view_as<any>(GetNativeCell(4)));
}

public int Native_GetLoadoutDisplayName(Handle plugin, int numParams)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutDisplayName], GetNativeCell(3));
}

public int Native_GetLoadoutGame(Handle plugin, int numParams)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutGame], GetNativeCell(3));
}

public int Native_GetLoadoutClass(Handle plugin, int numParams)
{
	SetNativeString(2, g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutClass], GetNativeCell(3));
}

public int Native_GetLoadoutTeam(Handle plugin, int numParams)
{
	return g_loadouts[GetLoadoutIndex(GetNativeCell(1))][LoadoutTeam];
}

public int Native_GetClientLoadouts(Handle plugin, int numParams)
{
	GetClientLoadouts(GetNativeCell(1), view_as<Store_GetUserLoadoutsCallback>(GetNativeFunction(2)), plugin, view_as<any>(GetNativeCell(3)));
}

public int Native_QueryEquippedLoadout(Handle plugin, int numParams)
{
	QueryEquippedLoadout(GetNativeCell(1), view_as<Store_GetUserEquippedLoadoutCallback>(GetNativeFunction(2)), plugin, view_as<any>(GetNativeCell(3)));
}

public int Native_SaveEquippedLoadout(Handle plugin, int numParams)
{
	SaveEquippedLoadout(GetNativeCell(1), GetNativeCell(2), view_as<Store_SaveUserEquippedLoadoutCallback>(GetNativeFunction(3)), plugin, view_as<any>(GetNativeCell(4)));
}

/////
//SQL Natives
public int Native_SQLTQuery(Handle plugin, int numParams)
{
	SQLTCallback callback = view_as<SQLTCallback>(GetNativeFunction(1));
	
	int size;
	GetNativeStringLength(2, size);
	
	char[] sQuery = new char[size + 1];
	GetNativeString(2, sQuery, size + 1);
	
	int data = GetNativeCell(3);
	
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, plugin);
	WritePackFunction(hPack, callback);
	WritePackCell(hPack, data);
	
	Store_Local_TQuery("Native", callback, sQuery, data);
}

public int Native_SQLEscapeString(Handle plugin, int numParams)
{
	int size;
	GetNativeStringLength(1, size);
	
	char[] sOrig = new char[size + 1];
	GetNativeString(1, sOrig, size + 1);
	
	size = 2 * size + 1;
	char[] sNew = new char[size + 1];
	SQL_EscapeString(g_hSQL, sOrig, sNew, size + 1);
	
	SetNativeString(2, sNew, size);
}

public int Native_SQLLogQuery(Handle plugin, int numParams)
{
	int size;
	
	GetNativeStringLength(1, size);
	
	char[] sSeverity = new char[size + 1];
	GetNativeString(1, sSeverity, size + 1);
	
	GetNativeStringLength(2, size);
	
	char[] sLocation = new char[size + 1];
	GetNativeString(2, sLocation, size + 1);
	
	GetNativeStringLength(3, size);
	
	char[] sMessage = new char[size + 1];
	GetNativeString(3, sMessage, size + 1);
	
	char sQuery[MAX_QUERY_SIZE];
	Format(sQuery, sizeof(sQuery), sQuery_LogToDatabase, STORE_DATABASE_PREFIX, Store_GetServerID(), sSeverity, sLocation, sMessage);
	Store_Local_TQuery("Log", SQLCall_VoidQuery, sQuery);
}

public int Native_DisplayClientsMenu(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	MenuHandler hMenuHandler = view_as<MenuHandler>(GetNativeFunction(2));
	bool bExitBack = GetNativeCell(3);
	
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || hMenuHandler == INVALID_FUNCTION)
	{
		Store_LogWarning("Client index %i has requested a clients menu and failed.", client);
		return false;
	}
	
	Handle hMenu = CreateMenu(hMenuHandler);
	SetMenuTitle(hMenu, "Choose a client:");
	SetMenuExitBackButton(hMenu, bExitBack);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(client) || client == i)
		{
			continue;
		}
		
		char sID[12];
		IntToString(i, sID, sizeof(sID));
		
		char sName[MAX_NAME_LENGTH];
		GetClientName(i, sName, sizeof(sName));
		
		AddMenuItem(hMenu, sID, sName);
	}
	
	if (GetMenuItemCount(hMenu) < 1)
	{
		AddMenuItem(hMenu, "", "[None Found]", ITEMDRAW_DISABLED);
	}
	
	return DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int Native_GetGlobalAccessType(Handle plugin, int numParams)
{
	return view_as<int>(g_accessTypes);
}

////////////////////
//Native Callbacks
public void SQLCall_RegisterPluginModule(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on SQLCall_RegisterPluginModule: %s", error);
	}
}

public int SQLCall_GenerateNewToken(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	int client = GetClientOfUserId(ReadPackCell(data));
	
	char sToken[MAX_TOKEN_SIZE];
	ReadPackString(data, sToken, sizeof(sToken));
	
	bool bVerbose = view_as<bool>(ReadPackCell(data));
	
	CloseHandle(data);
	
	if (hndl == null)
	{
		LogError("SQL Error on Generating a new token: %s", error);
		return;
	}
	
	if (client != 0 && bVerbose)
	{
		CPrintToChat(client, "Your new token has been set to '%s'.", sToken); //Translate
	}
}

public void Query_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	
	Handle plugin = view_as<Handle>(ReadPackCell(data));
	SQLTCallback callback = view_as<SQLTCallback>(ReadPackFunction(data));
	int hPack = ReadPackCell(data);
	
	CloseHandle(data);
	
	Call_StartFunction(plugin, callback);
	Call_PushCell(owner);
	Call_PushCell(hndl);
	Call_PushString(error);
	Call_PushCell(hPack);
	Call_Finish();
}

public void SQLCall_VoidQuery(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("SQL Error on VoidQuery: %s", error);
	}
}