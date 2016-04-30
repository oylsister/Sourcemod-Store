#pragma semicolon 1

#include <sourcemod>
#include <store>

#pragma newdecls required

#define PLUGIN_NAME "[Store] Trading Module"
#define PLUGIN_DESCRIPTION "Trading module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_trading_version"

//Config Globals
int g_itemMenuOrder;

stock bool bIsSearching[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = STORE_AUTHORS,
	description = PLUGIN_DESCRIPTION,
	version = STORE_VERSION,
	url = STORE_URL
};

public void OnPluginStart()
{
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_DONTRECORD);
}

public void OnConfigsExecuted()
{
	Store_OnCoreLoaded();
}

public void Store_OnDatabaseInitialized()
{
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
}

public void Store_OnCoreLoaded()
{
	LoadConfig("Trading", "configs/store/trading.cfg");
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
	
	char sCommand[255];
	KvGetString(hKV, "trade_commands", sCommand, sizeof(sCommand), "!trade /trade");
	Store_RegisterChatCommands(sCommand, ChatCommand_OpenTrade);
	
	g_itemMenuOrder = KvGetNum(hKV, "menu_item_order", 12);
	
	CloseHandle(hKV);
	
	Store_AddMainMenuItem("Trade", "Trade Description", _, OnMainMenuTradeClick, g_itemMenuOrder);
}

public void OnMainMenuTradeClick(int client, const char[] value)
{
	OpenTrade(client);
}

public void ChatCommand_OpenTrade(int client)
{
	OpenTrade(client);
}

void OpenTrade(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}
	
	Handle hMenu = CreateMenu(MenuHandle_OpenTradesMenu);
	SetMenuTitle(hMenu, "%T%T\n \n", "Store Menu Title", client, "Store Menu Trades Menu", client);
	
	AddMenuItem(hMenu, "Manage", "Manage Trades");
	AddMenuItem(hMenu, "Start", "Start a Trade");
	
	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_OpenTradesMenu(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				char sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				if (StrEqual(sMenuItem, "Manage"))
				{
					
				}
				else if (StrEqual(sMenuItem, "Start"))
				{
					Store_DisplayClientsMenu(client, MenuHandler_PickClient);
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

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	
}

public int MenuHandler_PickClient(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				char sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				CPrintToChat(client, "Test");
			}
		case MenuAction_Cancel:
			{
				if (slot == MenuCancel_ExitBack)
				{
					OpenTrade(client);
				}
			}
		case MenuAction_End: CloseHandle(menu);
	}
}