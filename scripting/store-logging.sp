/*
	Special thanks to Bara20 for a base to work off of. I decided not to include his include with this plugin since It's fairly straight forward code.
	-https://github.com/Bara20/Extended-Logging/blob/master/addons/sourcemod/scripting/include/extended_logging.inc
	-https://forums.alliedmods.net/showthread.php?t=247769
*/
#pragma semicolon 1

#include <sourcemod>
#include <store>

enum ELOG_LEVEL
{
	DEFAULT = 0,
	TRACE,
	DEBUG,
	INFO,
	WARN,
	ERROR
}

new String:g_sELogLevel[6][32] =
{
	"default",
	"trace",
	"debug",
	"info",
	"warn",
	"error"
};

new String:sLoggingPath[PLATFORM_MAX_PATH];
new String:sLoggingFilename[64];
new String:sDateFormat[12];

//Status of certain types of logs.
new bool:bLog_Default = true, bool:bLog_Trace = true, bool:bLog_Debug = true, bool:bLog_Info = true, bool:bLog_Warn = true, bool:bLog_Error = true;

//Status of certain types under subfolders.
new bool:bFolder_Default = false, bool:bFolder_Trace = false, bool:bFolder_Debug = false, bool:bFolder_Info = false, bool:bFolder_Warn = false, bool:bFolder_Error = false;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) 
{
	CreateNative("Store_Log", Native_Store_Log);
	CreateNative("Store_LogTrace", Native_Store_LogTrace);
	CreateNative("Store_LogDebug", Native_Store_LogDebug);
	CreateNative("Store_LogInfo", Native_Store_LogInfo);
	CreateNative("Store_LogWarning", Native_Store_LogWarning);
	CreateNative("Store_LogError", Native_Store_LogError);
	
	RegPluginLibrary("store-logging");
	
	return APLRes_Success;
}

public Plugin:myinfo =
{
	name        = "[Store] Logging",
	author      = "Keith Warren (Drixevel) & Bara20",
	description = "Logging component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/alongubkin/store"
};

public OnPluginStart() 
{
	LoadConfig();
	
	RegServerCmd("sm_teststorelogging", TestStoreLogging);
}

public Action:TestStoreLogging(args)
{
	Store_Log("Logging type: Default - Format: %i", 1);
	Store_LogTrace("Logging type: Trace - Format: %i", 1);
	Store_LogDebug("Logging type: Debug - Format: %i", 1);
	Store_LogInfo("Logging type: Info - Format: %i", 1);
	Store_LogWarning("Logging type: Warning - Format: %i", 1);
	Store_LogError("Logging type: Error - Format: %i", 1);
	
	PrintToServer("Test logs have been created.");
	
	return Plugin_Handled;
}

/**
 * Load plugin config.
 */
LoadConfig() 
{
	new Handle:hKV = CreateKeyValues("root");
	
	new String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/store/logging.cfg");
	
	if (!FileToKeyValues(hKV, sPath)) 
	{
		CloseHandle(hKV);
		SetFailState("Can't read config file %s", sPath);
	}

	KvGetString(hKV, "logging_path", sLoggingPath, sizeof(sLoggingPath));
	KvGetString(hKV, "logging_filename", sLoggingFilename, sizeof(sLoggingFilename));
	KvGetString(hKV, "date_format", sDateFormat, sizeof(sDateFormat));
	
	if (KvJumpToKey(hKV, "Logging_types"))
	{
		bLog_Default = bool:KvGetNum(hKV, "default", 1);
		bLog_Trace = bool:KvGetNum(hKV, "trace", 1);
		bLog_Debug = bool:KvGetNum(hKV, "debug", 1);
		bLog_Info = bool:KvGetNum(hKV, "info", 1);
		bLog_Warn = bool:KvGetNum(hKV, "warn", 1);
		bLog_Error = bool:KvGetNum(hKV, "error", 1);
		
		KvGoBack(hKV);
	}
	
	new bool:bSubDirectories = bool:KvGetNum(hKV, "log_subfolders", 0);
	
	if (bSubDirectories && KvJumpToKey(hKV, "Logging_subfolders"))
	{
		bFolder_Default = bool:KvGetNum(hKV, "default", 0);
		bFolder_Trace = bool:KvGetNum(hKV, "trace", 0);
		bFolder_Debug = bool:KvGetNum(hKV, "debug", 0);
		bFolder_Info = bool:KvGetNum(hKV, "info", 0);
		bFolder_Warn = bool:KvGetNum(hKV, "warn", 0);
		bFolder_Error = bool:KvGetNum(hKV, "error", 0);
		
		KvGoBack(hKV);
	}
	
	CloseHandle(hKV);
}

public Native_Store_Log(Handle:hPlugin, iParams) 
{
	if (!bLog_Default) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, DEFAULT, bFolder_Default, sFormat);
}

public Native_Store_LogTrace(Handle:hPlugin, iParams) 
{
	if (!bLog_Trace) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, TRACE, bFolder_Trace, sFormat);
}

public Native_Store_LogDebug(Handle:hPlugin, iParams) 
{
	if (!bLog_Debug) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, DEBUG, bFolder_Debug, sFormat);
}

public Native_Store_LogInfo(Handle:hPlugin, iParams) 
{
	if (!bLog_Info) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, INFO, bFolder_Info, sFormat);
}

public Native_Store_LogWarning(Handle:hPlugin, iParams) 
{
	if (!bLog_Warn) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, WARN, bFolder_Warn, sFormat);
}

public Native_Store_LogError(Handle:hPlugin, iParams) 
{
	if (!bLog_Error) return;
	
	new String:sFormat[1024];
	FormatNativeString(0, 1, 2, sizeof(sFormat), _, sFormat);
	
	new String:sDate[24];
	FormatTime(sDate, sizeof(sDate), sDateFormat, GetTime());
	
	Log_File(sLoggingPath, sLoggingFilename, sDate, ERROR, bFolder_Error, sFormat);
}

Log_File(const String:sPath[] = "", const String:sFile[] = "store", const String:sDate[] = "", ELOG_LEVEL:eLevel = DEFAULT, bool:bLogToFolder = false, const String:format[], any:...)
{
	new String:sPath_Build[PLATFORM_MAX_PATH + 1], String:sLevelPath[PLATFORM_MAX_PATH + 1], String:sFile_Build[PLATFORM_MAX_PATH + 1], String:sBuffer[1024];

	if (strlen(sPath) != 0)
	{
		BuildPath(Path_SM, sPath_Build, sizeof(sPath_Build), "logs/%s", sPath);
		
		if(!DirExists(sPath_Build))
		{
			CreateDirectory(sPath_Build, 511);
		}
	}
	else
	{
		BuildPath(Path_SM, sPath_Build, sizeof(sPath_Build), "logs");
	}

	if (bLogToFolder)
	{
		Format(sLevelPath, sizeof(sLevelPath), "%s/%s", sPath_Build, g_sELogLevel[eLevel]);
	}
	else
	{
		Format(sLevelPath, sizeof(sLevelPath), "%s", sPath_Build);
	}

	
	if (!DirExists(sLevelPath))
	{
		CreateDirectory(sLevelPath, 511);
	}

	if (strlen(sDate) != 0)
	{
		Format(sFile_Build, sizeof(sFile_Build), "%s/%s_%s.log", sLevelPath, sFile, sDate);
	}
	else
	{
		Format(sFile_Build, sizeof(sFile_Build), "%s/%s.log", sLevelPath, sFile);
	}

	VFormat(sBuffer, sizeof(sBuffer), format, 7);
	Format(sBuffer, sizeof(sBuffer), "[Store] %s", sBuffer);
	LogToFileEx(sFile_Build, sBuffer);
}