#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>
#include <store>

#undef REQUIRE_EXTENSIONS
#include <tf2_stocks>

#define PLUGIN_NAME "[Store] Loadouts Module"
#define PLUGIN_DESCRIPTION "Loadouts module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_loadouts_version"

//Config Globals

stock const String:TF2_ClassName[TFClassType][] = {"", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer" };

new Handle:g_clientLoadoutChangedForward;

new String:g_game[STORE_MAX_LOADOUTGAME_LENGTH];

new g_clientLoadout[MAXPLAYERS+1];
new Handle:g_lastClientLoadout;

new bool:g_databaseInitialized;

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
	CreateNative("Store_OpenLoadoutMenu", Native_OpenLoadoutMenu);
	CreateNative("Store_GetClientCurrentLoadout", Native_GetClientLoadout);
	CreateNative("Store_GetClientLoadout", Native_GetClientLoadout);
	
	g_clientLoadoutChangedForward = CreateGlobalForward("Store_OnClientLoadoutChanged", ET_Event, Param_Cell);
	
	RegPluginLibrary("store-loadout");
	RegPluginLibrary("store-loadouts");
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	g_lastClientLoadout = RegClientCookie("lastClientLoadout", "Client loadout", CookieAccess_Protected);
	
	GetGameFolderName(g_game, sizeof(g_game));
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	LoadConfig();
}

public Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Loadout", "Loadout Description", _, OnMainMenuLoadoutClick, 10);
}

public OnMapStart()
{
	if (g_databaseInitialized)
	{
		Store_GetLoadouts(INVALID_HANDLE, INVALID_FUNCTION, false);
	}
}

public Store_OnDatabaseInitialized()
{
	g_databaseInitialized = true;
	Store_GetLoadouts(INVALID_HANDLE, INVALID_FUNCTION, false);
	
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
}

public OnClientCookiesCached(client)
{
	new String:buffer[12];
	GetClientCookie(client, g_lastClientLoadout, buffer, sizeof(buffer));
	g_clientLoadout[client] = StringToInt(buffer);
}

LoadConfig() 
{
	new Handle:kv = CreateKeyValues("root");
	
	new String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/loadout.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	new String:menuCommands[255];
	KvGetString(kv, "loadout_commands", menuCommands, sizeof(menuCommands));
	Store_RegisterChatCommands(menuCommands, ChatCommand_OpenLoadout);
	
	CloseHandle(kv);
	
	Store_AddMainMenuItem("Loadout", "Loadout Description", _, OnMainMenuLoadoutClick, 10);
}

public ChatCommand_OpenLoadout(client)
{
	OpenLoadoutMenu(client);
}

public OnMainMenuLoadoutClick(client, const String:value[])
{
	OpenLoadoutMenu(client);
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_clientLoadout[client] == 0 || !IsLoadoutAvailableFor(client, g_clientLoadout[client]))
	{
		FindOptimalLoadoutFor(client);
	}
}

OpenLoadoutMenu(client)
{
	new Handle:filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		new String:className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, GetLoadoutsCallback, true, client);
}

public GetLoadoutsCallback(ids[], count, any:client)
{
	new Handle:menu = CreateMenu(LoadoutMenuSelectHandle);
	SetMenuTitle(menu, "Loadout\n \n");
		
	for (new loadout = 0; loadout < count; loadout++)
	{
		new String:displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetLoadoutDisplayName(ids[loadout], displayName, sizeof(displayName));
		
		new String:itemText[sizeof(displayName) + 3];
		
		if (g_clientLoadout[client] == ids[loadout])
		{
			strcopy(itemText, sizeof(itemText), "[L] ");
		}
		
		Format(itemText, sizeof(itemText), "%s%s", itemText, displayName);
		
		new String:itemValue[8];
		IntToString(ids[loadout], itemValue, sizeof(itemValue));
		
		AddMenuItem(menu, itemValue, itemText);
	}
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public LoadoutMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				g_clientLoadout[client] = StringToInt(sMenuItem);			
				SetClientCookie(client, g_lastClientLoadout, sMenuItem);
				
				Call_StartForward(g_clientLoadoutChangedForward);
				Call_PushCell(client);
				Call_Finish();
				
				OpenLoadoutMenu(client);
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

bool:IsLoadoutAvailableFor(client, loadout)
{
	new String:game[STORE_MAX_LOADOUTGAME_LENGTH];
	Store_GetLoadoutGame(loadout, game, sizeof(game));
	
	if (!StrEqual(game, "") && !StrEqual(game, g_game))
	{
		return false;
	}
	
	if (StrEqual(g_game, "tf"))
	{
		new String:loadoutClass[STORE_MAX_LOADOUTCLASS_LENGTH];
		Store_GetLoadoutClass(loadout, loadoutClass, sizeof(loadoutClass));
		
		new String:className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		
		if (!StrEqual(loadoutClass, "") && !StrEqual(loadoutClass, className))
		{
			return false;
		}
	}
	
	new loadoutTeam = Store_GetLoadoutTeam(loadout);
	if (loadoutTeam != -1 && GetClientTeam(client) != loadoutTeam)
	{
		return false;
	}
		
	return true;
}

FindOptimalLoadoutFor(client)
{
	if (!g_databaseInitialized)
	{
		return;
	}
	
	new Handle:filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		new String:className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, FindOptimalLoadoutCallback, true, GetClientUserId(client));
}

public FindOptimalLoadoutCallback(ids[], count, any:data)
{
	new client = GetClientOfUserId(data);
	
	if (!client)
	{
		return;
	}
	
	if (count > 0)
	{
		g_clientLoadout[client] = ids[0];
		
		new String:buffer[12];
		IntToString(g_clientLoadout[client], buffer, sizeof(buffer));
		
		SetClientCookie(client, g_lastClientLoadout, buffer);
		
		Call_StartForward(g_clientLoadoutChangedForward);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		Store_LogWarning("No loadout found.");
	}	
}

public Native_OpenLoadoutMenu(Handle:plugin, params)
{       
	OpenLoadoutMenu(GetNativeCell(1));
}

public Native_GetClientLoadout(Handle:plugin, params)
{       
	return g_clientLoadout[GetNativeCell(1)];
}

TF2_GetClassName(TFClassType:classType, String:buffer[], maxlength)
{
	strcopy(buffer, maxlength, TF2_ClassName[classType]);
}