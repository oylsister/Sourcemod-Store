#pragma semicolon 1

#include <sourcemod>
#include <store>

#define PLUGIN_NAME "[Store] Inventory Module"
#define PLUGIN_DESCRIPTION "Inventory module for the Sourcemod Store."
#define PLUGIN_VERSION_CONVAR "store_inventory_version"

//Config Globals
new bool:g_hideEmptyCategories = false;
new bool:g_showMenuDescriptions = true;
new bool:g_showItemsMenuDescriptions = true;

new Handle:g_itemTypes;
new Handle:g_itemTypeNameIndex;

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
	CreateNative("Store_OpenInventory", Native_OpenInventory);
	CreateNative("Store_OpenInventoryCategory", Native_OpenInventoryCategory);
	
	CreateNative("Store_RegisterItemType", Native_RegisterItemType);
	CreateNative("Store_IsItemTypeRegistered", Native_IsItemTypeRegistered);
	
	CreateNative("Store_CallItemAttrsCallback", Native_CallItemAttrsCallback);
		
	RegPluginLibrary("store-inventory");	
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	CreateConVar(PLUGIN_VERSION_CONVAR, STORE_VERSION, PLUGIN_NAME, FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	
	RegAdminCmd("store_itemtypes", Command_PrintItemTypes, ADMFLAG_RCON, "Prints registered item types");
	RegAdminCmd("sm_store_itemtypes", Command_PrintItemTypes, ADMFLAG_RCON, "Prints registered item types");
	
	g_itemTypes = CreateArray();
	g_itemTypeNameIndex = CreateTrie();
	
	LoadConfig();
}

public Store_OnCoreLoaded()
{
	Store_AddMainMenuItem("Inventory", "Inventory Description", _, OnMainMenuInventoryClick, 4);
}

public Store_OnDatabaseInitialized()
{
	Store_RegisterPluginModule(PLUGIN_NAME, PLUGIN_DESCRIPTION, PLUGIN_VERSION_CONVAR, STORE_VERSION);
}

LoadConfig() 
{
	new Handle:kv = CreateKeyValues("root");
	
	new String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/inventory.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	new String:menuCommands[255];
	KvGetString(kv, "inventory_commands", menuCommands, sizeof(menuCommands), "!inventory /inventory !inv /inv");
	Store_RegisterChatCommands(menuCommands, ChatCommand_OpenInventory);

	g_hideEmptyCategories = bool:KvGetNum(kv, "hide_empty_categories", 0);
	g_showMenuDescriptions = bool:KvGetNum(kv, "show_menu_descriptions", 1);
	g_showItemsMenuDescriptions = bool:KvGetNum(kv, "show_itesm_menu_descriptions", 1);
	
	CloseHandle(kv);
	
	Store_AddMainMenuItem("Inventory", "Inventory Description", _, OnMainMenuInventoryClick, 4);
}

public OnMainMenuInventoryClick(client, const String:value[])
{
	OpenInventory(client);
}

public ChatCommand_OpenInventory(client)
{
	OpenInventory(client);
}

public Action:Command_PrintItemTypes(client, args)
{
	for (new itemTypeIndex = 0, size = GetArraySize(g_itemTypes); itemTypeIndex < size; itemTypeIndex++)
	{
		new Handle:itemType = Handle:GetArrayCell(g_itemTypes, itemTypeIndex);
		
		ResetPack(itemType);
		new Handle:plugin = Handle:ReadPackCell(itemType);

		SetPackPosition(itemType, 24);
		new String:typeName[32];
		ReadPackString(itemType, typeName, sizeof(typeName));

		ResetPack(itemType);

		new String:pluginName[32];
		GetPluginFilename(plugin, pluginName, sizeof(pluginName));

		CReplyToCommand(client, " \"%s\" - %s", typeName, pluginName);			
	}

	return Plugin_Handled;
}

OpenInventory(client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || categories_menu[client] != INVALID_HANDLE)
	{
		return;
	}
	
	Store_GetCategories(GetCategoriesCallback, true, "", GetClientUserId(client));
}
public GetCategoriesCallback(ids[], count, any:data)
{	
	new client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
	
	if (count < 1)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No categories available");
		return;
	}
	
	categories_menu[client] = CreateMenu(InventoryMenuSelectHandle);
	SetMenuTitle(categories_menu[client], "%T\n \n", "Inventory", client);
	SetMenuExitBackButton(categories_menu[client], true);
	
	new bool:bNoCategories = true;
	for (new category = 0; category < count; category++)
	{
		new String:requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));
		
		new typeIndex;
		if (!StrEqual(requiredPlugin, "") && !GetTrieValue(g_itemTypeNameIndex, requiredPlugin, typeIndex))
		{
			continue;
		}

		new Handle:hPack = CreateDataPack();
		WritePackCell(hPack, GetClientUserId(client));
		WritePackCell(hPack, ids[category]);
		WritePackCell(hPack, count - category - 1);
		
		new Handle:filter = CreateTrie();
		SetTrieValue(filter, "category_id", ids[category]);
		SetTrieValue(filter, "flags", GetUserFlagBits(client));

		Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetItemsForCategoryCallback, hPack);
		bNoCategories = false;
	}
	
	if (bNoCategories)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "No categories available");
	}
}

public GetItemsForCategoryCallback(ids[], bool:equipped[], itemCount[], count, loadoutId, any:hPack)
{
	ResetPack(hPack);
	
	new client = GetClientOfUserId(ReadPackCell(hPack));
	new categoryId = ReadPackCell(hPack);
	new left = ReadPackCell(hPack);
	
	CloseHandle(hPack);
		
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (g_hideEmptyCategories && count <= 0)
	{
		if (left == 0)
		{
			DisplayMenu(categories_menu[client], client, MENU_TIME_FOREVER);
			categories_menu[client] = INVALID_HANDLE;
		}
		
		return;
	}
	
	new String:sValue[8];
	IntToString(categoryId, sValue, sizeof(sValue));

	new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetCategoryDisplayName(categoryId, sDisplayName, sizeof(sDisplayName));
	
	new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
	Store_GetCategoryDescription(categoryId, sDescription, sizeof(sDescription));
	
	new String:sDisplay[sizeof(sDisplayName) + 1 + sizeof(sDescription)];
	Format(sDisplay, sizeof(sDisplay), "%s", sDisplayName);
	
	if (g_showMenuDescriptions)
	{
		Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplay, sDescription);
	}
	
	AddMenuItem(categories_menu[client], sValue, sDisplay);

	if (left == 0)
	{
		DisplayMenu(categories_menu[client], client, MENU_TIME_FOREVER);
		categories_menu[client] = INVALID_HANDLE;
	}
}

public InventoryMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				OpenInventoryCategory(client, StringToInt(sMenuItem));
			}
		case MenuAction_Cancel:
			{
				if (slot == MenuCancel_ExitBack)
				{
					Store_OpenMainMenu(client);
				}
			}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

OpenInventoryCategory(client, categoryId, slot = 0)
{
	new Handle:hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackCell(hPack, categoryId);
	WritePackCell(hPack, slot);
	
	new Handle:filter = CreateTrie();
	SetTrieValue(filter, "category_id", categoryId);
	SetTrieValue(filter, "flags", GetUserFlagBits(client));

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
	
	if (count < 1)
	{
		CPrintToChat(client, "%t%t", "Store Tag Colored", "Inventory category is empty");
		OpenInventory(client);
		return;
	}
	
	new String:categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));
		
	new Handle:menu = CreateMenu(InventoryCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Inventory", client, categoryDisplayName);
	
	for (new item = 0; item < count; item++)
	{
		new String:sDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], sDisplayName, sizeof(sDisplayName));
		
		new String:sDescription[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetItemDescription(ids[item], sDescription, sizeof(sDescription));
		
		new String:sDisplay[4 + sizeof(sDisplayName) + sizeof(sDescription)+ 6];
		Format(sDisplay, sizeof(sDisplay), "%s", sDisplayName);
		
		if (equipped[item])
		{
			Format(sDisplay, sizeof(sDisplay), "[E] %s", sDisplay);
		}
				
		if (itemCount[item] > 1)
		{
			Format(sDisplay, sizeof(sDisplay), "%s (%d)", sDisplay, itemCount[item]);
		}
		
		if (g_showItemsMenuDescriptions)
		{
			Format(sDisplay, sizeof(sDisplay), "%s\n%s", sDisplay, sDescription);
		}
		
		new String:sItem[16];
		Format(sItem, sizeof(sItem), "%b,%d", equipped[item], ids[item]);
		
		AddMenuItem(menu, sItem, sDisplay);
	}

	SetMenuExitBackButton(menu, true);
	
	if (slot != 0)
	{
		DisplayMenuAtItem(menu, client, slot, 0);
		return;
	}
	
	DisplayMenu(menu, client, 0);
}

public InventoryCategoryMenuSelectHandle(Handle:menu, MenuAction:action, client, slot)
{
	switch (action)
	{
		case MenuAction_Select:
			{
				new String:sMenuItem[64];
				GetMenuItem(menu, slot, sMenuItem, sizeof(sMenuItem));
				
				new String:buffers[2][16];
				ExplodeString(sMenuItem, ",", buffers, sizeof(buffers), sizeof(buffers[]));
				
				new bool:equipped = bool:StringToInt(buffers[0]);
				new id = StringToInt(buffers[1]);
				
				new String:name[STORE_MAX_NAME_LENGTH];
				Store_GetItemName(id, name, sizeof(name));
				
				new String:type[STORE_MAX_TYPE_LENGTH];
				Store_GetItemType(id, type, sizeof(type));
				
				new String:loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
				Store_GetItemLoadoutSlot(id, loadoutSlot, sizeof(loadoutSlot));
				
				new itemTypeIndex = -1;
				GetTrieValue(g_itemTypeNameIndex, type, itemTypeIndex);
				
				if (itemTypeIndex == -1)
				{
					CPrintToChat(client, "%t%t", "Store Tag Colored", "Item type not registered", type);
					Store_LogWarning("The item type '%s' wasn't registered by any plugin.", type);
					
					OpenInventoryCategory(client, Store_GetItemCategory(id));
					
					return;
				}
				
				new Store_ItemUseAction:callbackValue = Store_DoNothing;
				
				new Handle:itemType = GetArrayCell(g_itemTypes, itemTypeIndex);
				ResetPack(itemType);
				
				new Handle:plugin = Handle:ReadPackCell(itemType);
				new Store_ItemUseCallback:callback = Store_ItemUseCallback:ReadPackFunction(itemType);
				
				Call_StartFunction(plugin, callback);
				Call_PushCell(client);
				Call_PushCell(id);
				Call_PushCell(equipped);
				Call_Finish(callbackValue);
				
				if (callbackValue != Store_DoNothing)
				{
					new auth = GetSteamAccountID(client);

					if (callbackValue == Store_EquipItem)
					{
						if (StrEqual(loadoutSlot, ""))
						{
							Store_LogWarning("A user tried to equip an item that doesn't have a loadout slot.");
						}
						else
						{
							Store_SetItemEquippedState(auth, id, Store_GetClientLoadout(client), true, EquipItemCallback, GetClientUserId(client));
						}
					}
					else if (callbackValue == Store_UnequipItem)
					{
						if (StrEqual(loadoutSlot, ""))
						{
							Store_LogWarning("A user tried to unequip an item that doesn't have a loadout slot.");
						}
						else
						{				
							Store_SetItemEquippedState(auth, id, Store_GetClientLoadout(client), false, EquipItemCallback, GetClientUserId(client));
						}
					}
					else if (callbackValue == Store_DeleteItem)
					{
						Store_RemoveUserItem(auth, id, UseItemCallback, GetClientUserId(client));
					}
				}
			}
		case MenuAction_Cancel: OpenInventory(client);
		case MenuAction_End: CloseHandle(menu);
	}
}

public EquipItemCallback(accountId, itemId, loadoutId, any:data)
{
	new client = GetClientOfUserId(data);
		
	if (!client || !IsClientInGame(client))
	{
		return;
	}
	
	OpenInventoryCategory(client, Store_GetItemCategory(itemId));
}

public UseItemCallback(accountId, itemId, any:data)
{
	new client = GetClientOfUserId(data);
		
	if (!client || !IsClientInGame(client))
	{
		return;
	}
	
	OpenInventoryCategory(client, Store_GetItemCategory(itemId));
}

RegisterItemType(const String:type[], Handle:plugin, Store_ItemUseCallback:useCallback, Store_ItemGetAttributesCallback:attrsCallback = INVALID_FUNCTION)
{
	if (g_itemTypes == INVALID_HANDLE)
	{
		g_itemTypes = CreateArray();
	}
	
	if (g_itemTypeNameIndex == INVALID_HANDLE)
	{
		g_itemTypeNameIndex = CreateTrie();
	}
	else
	{
		new itemType;
		if (GetTrieValue(g_itemTypeNameIndex, type, itemType))
		{
			CloseHandle(Handle:GetArrayCell(g_itemTypes, itemType));
		}
	}

	new Handle:itemType = CreateDataPack();
	WritePackCell(itemType, _:plugin);
	WritePackFunction(itemType, useCallback);
	WritePackFunction(itemType, attrsCallback);
	WritePackString(itemType, type);

	new index = PushArrayCell(g_itemTypes, itemType);
	SetTrieValue(g_itemTypeNameIndex, type, index);
}

public Native_OpenInventory(Handle:plugin, params)
{       
	OpenInventory(GetNativeCell(1));
}

public Native_OpenInventoryCategory(Handle:plugin, params)
{       
	OpenInventoryCategory(GetNativeCell(1), GetNativeCell(2));
}

public Native_RegisterItemType(Handle:plugin, params)
{
	new String:type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));
	RegisterItemType(type, plugin, Store_ItemUseCallback:GetNativeFunction(2), Store_ItemGetAttributesCallback:GetNativeFunction(3));
}

public Native_IsItemTypeRegistered(Handle:plugin, params)
{
	new String:type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));
		
	new typeIndex;
	return GetTrieValue(g_itemTypeNameIndex, type, typeIndex);
}

public Native_CallItemAttrsCallback(Handle:plugin, params)
{
	if (g_itemTypeNameIndex == INVALID_HANDLE)
	{
		return false;
	}
	
	new String:type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));

	new typeIndex;
	if (!GetTrieValue(g_itemTypeNameIndex, type, typeIndex))
	{
		return false;
	}

	new String:name[STORE_MAX_NAME_LENGTH];
	GetNativeString(2, name, sizeof(name));

	new String:attrs[STORE_MAX_ATTRIBUTES_LENGTH];
	GetNativeString(3, attrs, sizeof(attrs));		

	new Handle:hPack = GetArrayCell(g_itemTypes, typeIndex);
	ResetPack(hPack);

	new Handle:callbackPlugin = Handle:ReadPackCell(hPack);
	
	ReadPackFunction(hPack);
	
	new Store_ItemGetAttributesCallback:callback = Store_ItemGetAttributesCallback:ReadPackFunction(hPack);
	
	if (callback == INVALID_FUNCTION)
	{
		return false;
	}
	
	Call_StartFunction(callbackPlugin, callback);
	Call_PushString(name);
	Call_PushString(attrs);
	Call_Finish();	
	
	return true;
}
