/*  Console Chat Manager
 *
 *  Copyright (C) 2022 Francisco 'Franc1sco' García, maxime1907
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <geoip>
#include <utilshelper>
#include <dhooks>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

#pragma newdecls required

enum EHudNotify
{
	HUD_PRINTNOTIFY = 1,
	HUD_PRINTCONSOLE = 2,
	HUD_PRINTTALK = 3,
	HUD_PRINTCENTER = 4
}

#define MAXLENGTH_INPUT 512
#define NORMALHUD 1

ConVar g_ConsoleMessage, g_EnableTranslation, g_cRemoveConsoleTag;
ConVar g_cBlockSpam, g_cBlockSpamDelay;
ConVar g_EnableHud, g_cHudPosition, g_cHudColor, g_cHudHtmlColor;
ConVar g_cHudMapSymbols, g_cHudSymbols;
ConVar g_cHudDuration, g_cHudDurationFadeOut;
ConVar g_cvHUDChannel;

char g_sBlacklist[][] = { "recharge", "recast", "cooldown", "cool" };
StringMap g_hColorMap;
StringMap g_hHexMap;
char g_sColorSymbols[][] = { "\x01", "\x03", "\x04", "\x05", "\x06" }; // \x07 and \x08 is ommitted because it requires additional check
char g_sPath[PLATFORM_MAX_PATH];
char g_sLastMessage[MAXLENGTH_INPUT] = "";
char g_sConsoleTag[255];
char g_sHudPosition[16], g_sHudColor[64], g_sHtmlColor[64];

float g_fHudPos[2];
float g_fHudDuration, g_fHudFadeOutDuration;

bool g_bPlugin_DynamicChannels = false;
bool g_bTranslation, g_bEnableHud, g_bHudMapSymbols, g_bHudSymbols, g_bBlockSpam, g_bRemoveConsoleTag;

int g_iHudColor[3];
int g_iNumber, g_iOnumber;
int g_iLastMessageTime = -1;
int g_iRoundStartedTime = -1;
int g_iHUDChannel, g_iBlockSpamDelay;

Handle kv;
Handle g_hTimerHandle, g_hHudSync;

DHookSetup g_hClientPrintDtr;

public Plugin myinfo =
{
	name = "ConsoleChatManager",
	author = "Franc1sco Steam: franug, maxime1907, inGame, AntiTeal, Oylsister, .Rushaway, tilgep, koen",
	description = "Interact with console messages",
	version = "2.4.2",
	url = ""
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	DeleteTimer();
	g_hHudSync = CreateHudSynchronizer();

	RegAdminCmd("sm_ccm_reloadcfg", Command_ReloadConfig, ADMFLAG_CONFIG, "Reload translations file");

	g_ConsoleMessage = CreateConVar("sm_consolechatmanager_tag", "{green}[NARRATOR] {white}", "The tag that will be printed instead of the console default messages");
	g_cRemoveConsoleTag = CreateConVar("sm_consolechatmanager_remove_tag", "0", "Remove console tag if message contain square bracket and a color name", _, true, 0.0, true, 1.0);

	g_EnableTranslation = CreateConVar("sm_consolechatmanager_translation", "0", "Enable translation of console chat messages. 1 = Enabled, 0 = Disabled");

	g_EnableHud = CreateConVar("sm_consolechatmanager_hud", "1", "Enables printing the console output in the middle of the screen");
	g_cHudDuration = CreateConVar("sm_consolechatmanager_hud_duration", "2.5", "How long the message stays");
	g_cHudDurationFadeOut = CreateConVar("sm_consolechatmanager_hud_duration_fadeout", "1.0", "How long the message takes to disapear");
	g_cHudPosition = CreateConVar("sm_consolechatmanager_hud_position", "-1.0 0.125", "The X and Y position for the hud.");
	g_cHudColor = CreateConVar("sm_consolechatmanager_hud_color", "0 255 0", "RGB color value for the hud.");
	g_cHudMapSymbols = CreateConVar("sm_consolechatmanager_hud_mapsymbols", "1", "Eliminate the original prefix and suffix from the map text when displayed in the Hud.", _, true, 0.0, true, 1.0);
	g_cHudSymbols = CreateConVar("sm_consolechatmanager_hud_symbols", "1", "Determines whether >> and << are wrapped around the text.");
	g_cHudHtmlColor = CreateConVar("sm_consolechatmanager_hud_htmlcolor", "#6CFF00", "Html color for second type of Hud Message");
	g_cvHUDChannel = CreateConVar("sm_consolechatmanager_hud_channel", "0", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 5.0);

	g_cBlockSpam = CreateConVar("sm_consolechatmanager_block_spam", "1", "Blocks console messages that repeat the same message.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cBlockSpamDelay = CreateConVar("sm_consolechatmanager_block_spam_delay", "1", "Time to wait before printing the same message", FCVAR_NONE, true, 1.0, true, 60.0);

	// Hook Convars
	g_ConsoleMessage.AddChangeHook(OnConVarChanged);
	g_cRemoveConsoleTag.AddChangeHook(OnConVarChanged);
	g_EnableTranslation.AddChangeHook(OnConVarChanged);
	g_EnableHud.AddChangeHook(OnConVarChanged);
	g_cHudDuration.AddChangeHook(OnConVarChanged);
	g_cHudDurationFadeOut.AddChangeHook(OnConVarChanged);
	g_cHudPosition.AddChangeHook(OnConVarChanged);
	g_cHudColor.AddChangeHook(OnConVarChanged);
	g_cHudMapSymbols.AddChangeHook(OnConVarChanged);
	g_cHudSymbols.AddChangeHook(OnConVarChanged);
	g_cHudHtmlColor.AddChangeHook(OnConVarChanged);
	g_cvHUDChannel.AddChangeHook(OnConVarChanged);
	g_cBlockSpam.AddChangeHook(OnConVarChanged);
	g_cBlockSpamDelay.AddChangeHook(OnConVarChanged);

	// Initilize convars values
	g_ConsoleMessage.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	g_bRemoveConsoleTag = g_cRemoveConsoleTag.BoolValue;
	g_bTranslation = g_EnableTranslation.BoolValue;
	g_bEnableHud = g_EnableHud.BoolValue;
	g_fHudDuration = g_cHudDuration.FloatValue;
	g_fHudFadeOutDuration = g_cHudDurationFadeOut.FloatValue;
	UpdateHudPosition();
	UpdateHudColor();
	g_bHudMapSymbols = g_cHudMapSymbols.BoolValue;
	g_bHudSymbols = g_cHudSymbols.BoolValue;
	g_cHudHtmlColor.GetString(g_sHtmlColor, sizeof(g_sHtmlColor));
	g_iHUDChannel = g_cvHUDChannel.IntValue;
	g_bBlockSpam = g_cBlockSpam.BoolValue;
	g_iBlockSpamDelay = g_cBlockSpamDelay.IntValue;

	AddCommandListener(SayConsole, "say");

	AutoExecConfig(true);

	// For now VScript detour is only supported for Counter-Strike: Source
	EngineVersion iEngine = GetEngineVersion();
	if (iEngine != Engine_CSS)
		return;

	// ClientPrint detour
	GameData gd;
	if ((gd = new GameData("ConsoleChatManager.games")) == null)
	{
		LogError("[ConsoleChatManager] gamedata file not found or failed to load");
		return;
	}

	if ((g_hClientPrintDtr = DynamicDetour.FromConf(gd, "ClientPrint")) == null)
	{
		LogError("[ConsoleChatManager] Failed to setup ClientPrint detour!");
		delete gd;
		return;
	}
	else
	{
		if (!DHookEnableDetour(g_hClientPrintDtr, false, Detour_ClientPrint))
			LogError("[ConsoleChatManager] Failed to detour ClientPrint()");
		else
			LogMessage("[ConsoleChatManager] Successfully detoured ClientPrint()");
	}
}

public void OnPluginEnd()
{
	if (g_hColorMap != null)
		delete g_hColorMap;
	delete g_hHexMap;
}

public void OnAllPluginsLoaded()
{
	g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPlugin_DynamicChannels = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPlugin_DynamicChannels = false;
}

public void OnMapStart()
{
	if (g_bTranslation)
		ReadT();

	InitColorMap();
}

public void OnMapEnd()
{
	if (g_hColorMap != null)
		delete g_hColorMap;

	g_hColorMap = new StringMap();

	delete g_hHexMap;
	g_hHexMap = new StringMap();
}

public void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_ConsoleMessage)
		g_ConsoleMessage.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	else if (convar == g_cRemoveConsoleTag)
		g_bRemoveConsoleTag = g_cRemoveConsoleTag.BoolValue;
	else if (convar == g_EnableTranslation)
		g_bTranslation = g_EnableTranslation.BoolValue;
	else if (convar == g_EnableHud)
		g_bEnableHud = g_EnableHud.BoolValue;
	else if (convar == g_cHudDuration)
		g_fHudDuration = g_cHudDuration.FloatValue;
	else if (convar == g_cHudDurationFadeOut)
		g_fHudFadeOutDuration = g_cHudDurationFadeOut.FloatValue;
	else if (convar == g_cHudPosition)
		UpdateHudPosition();
	else if (convar == g_cHudColor)
		UpdateHudColor();
	else if (convar == g_cHudMapSymbols)
		g_bHudMapSymbols = g_cHudMapSymbols.BoolValue;
	else if (convar == g_cHudSymbols)
		g_bHudSymbols = g_cHudSymbols.BoolValue;
	else if (convar == g_cHudHtmlColor)
		g_cHudHtmlColor.GetString(g_sHtmlColor, sizeof(g_sHtmlColor));
	else if (convar == g_cvHUDChannel)
		g_iHUDChannel = g_cvHUDChannel.IntValue;
	else if (convar == g_cBlockSpam)
		g_bBlockSpam = g_cBlockSpam.BoolValue;
	else if (convar == g_cBlockSpamDelay)
		g_iBlockSpamDelay = g_cBlockSpamDelay.IntValue;
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_iRoundStartedTime = GetTime();
	DeleteTimer();
}

public int GetCurrentRoundTime()
{
	Handle hFreezeTime = FindConVar("mp_freezetime"); // Freezetime Handle
	int freezeTime = GetConVarInt(hFreezeTime); // Freezetime in seconds
	return GameRules_GetProp("m_iRoundTime") - ( (GetTime() - g_iRoundStartedTime) - freezeTime );
}

public int GetRoundTimeAtTimerEnd()
{
	return GetCurrentRoundTime() - g_iNumber;
}

public void DeleteTimer()
{
	if (g_hTimerHandle != INVALID_HANDLE)
	{
		KillTimer(g_hTimerHandle);
		g_hTimerHandle = INVALID_HANDLE;
	}
}

stock void UpdateHudPosition()
{
	char StringPos[2][8];
	g_cHudPosition.GetString(g_sHudPosition, sizeof(g_sHudPosition));
	ExplodeString(g_sHudPosition, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));
	g_fHudPos[0] = StringToFloat(StringPos[0]);
	g_fHudPos[1] = StringToFloat(StringPos[1]);
}

stock void UpdateHudColor()
{
	g_cHudColor.GetString(g_sHudColor, sizeof(g_sHudColor));
	ColorStringToArray(g_sHudColor, g_iHudColor);
}

public Action Command_ReloadConfig(int client, int argc)
{
	ReadT();
	CReplyToCommand(client, "{green}[CCM] {default}Translation file has been reloaded.");
	LogAction(client, -1, "[CCM] %L Reloaded the translation file.", client);
	return Plugin_Handled;
}

public void ReadT()
{
	delete kv;

	char map[64];
	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/consolechatmanager/%s.txt", map);

	if (!FileExists(g_sPath))
	{
		StringToLowerCase(map);
		BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/consolechatmanager/%s.txt", map);
	}

	kv = CreateKeyValues("Console_C");
	// File not found, create the file
	if (!FileExists(g_sPath))
		KeyValuesToFile(kv, g_sPath);
	else
		FileToKeyValues(kv, g_sPath);

	CheckSounds();
}

void CheckSounds()
{
	PrecacheSound("common/talk.wav", false);

	char buffer[255];
	if (KvGotoFirstSubKey(kv))
	{
		do
		{
			KvGetString(kv, "sound", buffer, 64, "default");
			if (strcmp(buffer, "default", false) != 0)
			{
				PrecacheSound(buffer);

				FormatEx(buffer, 255, "sound/%s", buffer);
				AddFileToDownloadsTable(buffer);
			}

		} while (KvGotoNextKey(kv));
	}

	KvRewind(kv);
}

public bool CheckStringBlacklist(const char[] string)
{
	for (int i = 0; i < sizeof(g_sBlacklist); i++)
	{
		if (StrContains(string, g_sBlacklist[i], false) != -1)
			return true;
	}
	return false;
}

public bool IsCountable(const char sMessage[MAXLENGTH_INPUT])
{
	char FilterText[sizeof(sMessage)+1], ChatArray[32][MAXLENGTH_INPUT];
	int consoleNumber, filterPos;
	bool isCountable = false;

	for (int i = 0; i < sizeof(sMessage); i++)
	{
		if (IsCharAlpha(sMessage[i]) || IsCharNumeric(sMessage[i]) || IsCharSpace(sMessage[i]))
			FilterText[filterPos++] = sMessage[i];
	}
	FilterText[filterPos] = '\0';
	TrimString(FilterText);

	if (CheckStringBlacklist(sMessage))
		return isCountable;

	int words = ExplodeString(FilterText, " ", ChatArray, sizeof(ChatArray), sizeof(ChatArray[]));

	if (words == 1)
	{
		if (StringToInt(ChatArray[0]) != 0)
		{
			isCountable = true;
			consoleNumber = StringToInt(ChatArray[0]);
		}
	}

	for (int i = 0; i <= words; i++)
	{
		if (StringToInt(ChatArray[i]) != 0)
		{
			if (i + 1 <= words && (strcmp(ChatArray[i + 1], "s", false) == 0 || (IsCharEqualIgnoreCase(ChatArray[i + 1][0], 's') && IsCharEqualIgnoreCase(ChatArray[i + 1][1], 'e'))))
			{
				consoleNumber = StringToInt(ChatArray[i]);
				isCountable = true;
			}
			if (!isCountable && i + 2 <= words && (strcmp(ChatArray[i + 2], "s", false) == 0 || (IsCharEqualIgnoreCase(ChatArray[i + 2][0], 's') && IsCharEqualIgnoreCase(ChatArray[i + 2][1], 'e'))))
			{
				consoleNumber = StringToInt(ChatArray[i]);
				isCountable = true;
			}
		}
		if (!isCountable)
		{
			char word[MAXLENGTH_INPUT];
			strcopy(word, sizeof(word), ChatArray[i]);
			int len = strlen(word);

			if (IsCharNumeric(word[0]))
			{
				if (IsCharNumeric(word[1]))
				{
					if (IsCharNumeric(word[2]))
					{
						if (IsCharEqualIgnoreCase(word[3], 's'))
						{
							consoleNumber = StringEnder(word, 5, len);
							isCountable = true;
						}
					}
					else if (IsCharEqualIgnoreCase(word[2], 's'))
					{
						consoleNumber = StringEnder(word, 4, len);
						isCountable = true;
					}
				}
				else if (IsCharEqualIgnoreCase(word[1], 's'))
				{
					consoleNumber = StringEnder(word, 3, len);
					isCountable = true;
				}
			}
		}
		if (isCountable)
		{
			g_iNumber = consoleNumber;
			g_iOnumber = consoleNumber;
			break;
		}
	}
	return isCountable;
}

public Action SayConsole(int client, const char[] command, int args)
{
	if (client)
		return Plugin_Continue;

	char sText[MAXLENGTH_INPUT];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);

	SendServerMessage(sText, false);

	return Plugin_Handled;
}

public MRESReturn Detour_ClientPrint(Handle hParams)
{
	// Check if message was sent from server console
	int iPlayer = DHookGetParam(hParams, 1);
	if (iPlayer != 0)
		return MRES_Ignored;

	// Check if the print was sent to chat
	EHudNotify iDestination = view_as<EHudNotify>(DHookGetParam(hParams, 2));
	if (iDestination != HUD_PRINTTALK)
		return MRES_Ignored;

	// Get chat message and pass through display function
	char sBuffer[MAXLENGTH_INPUT];
	DHookGetParamString(hParams, 3, sBuffer, sizeof(sBuffer));
	SendServerMessage(sBuffer, true);
	return MRES_Supercede;
}

public int StringEnder(char[] a, int b, int c)
{
	if (IsCharEqualIgnoreCase(a[b], 'c'))
		a[c - 3] = '\0';
	else
		a[c - 1] = '\0';
	return StringToInt(a);
}

public void InitCountDown(const char[] szMessage)
{
	DeleteTimer();
	DataPack TimerPack;
	g_hTimerHandle = CreateDataTimer(1.0, RepeatMsg, TimerPack, TIMER_REPEAT);
	TimerPack.WriteString(szMessage);
}

public Action RepeatMsg(Handle timer, Handle pack)
{
	g_iNumber--;
	if (g_iNumber <= 0)
	{
		DeleteTimer();
		for (int i = 1; i <= MAXPLAYERS + 1; i++)
		{
			if (IsValidClient(i, false, false, false))
				ClearSyncHud(i, g_hHudSync);
		}
		return Plugin_Handled;
	}

	char string[MAXLENGTH_INPUT + 10], sNumber[8], sONumber[8];

	ResetPack(pack);
	ReadPackString(pack, string, sizeof(string));

	IntToString(g_iOnumber, sONumber, sizeof(sONumber));
	IntToString(g_iNumber, sNumber, sizeof(sNumber));

	ReplaceString(string, sizeof(string), sONumber, sNumber);

	for (int i = 1; i <= MAXPLAYERS + 1; i++)
		SendHudMsg(i, string, true);

	return Plugin_Handled;
}

stock void RemoveTextInBraces(char[] szMessage, bool bRemoveInt = false, bool bRemoveBracesForInt = false)
{
	bool bracesFound = true;
	while (bracesFound)
	{
		int start = StrContains(szMessage, "{", false);
		int end = StrContains(szMessage, "}", false);

		if (start != -1 && end != -1)
		{
			bool isInteger = false;
			if (bRemoveInt)
			{
				isInteger = true;
				// Check if content between braces is not an integer value
				for (int i = start + 1; i < end; i++)
				{
					if (!(szMessage[i] >= '0' && szMessage[i] <= '9') && szMessage[i] != '.')
					{
						isInteger = false;
						break;
					}
				}
			}

			if (!isInteger)
			{
				// Content between braces is not an integer, remove it along with braces
				int len = strlen(szMessage), i = 0, j = 0;
				while (i < len)
				{
					if ((i < start) || (i > end))
					{
						szMessage[j] = szMessage[i];
						j++;
					}
					i++;
				}
				szMessage[j] = '\0';
			}
			else if (bRemoveBracesForInt)
			{
				// Content between braces is an integer, remove the braces only
				for (int i = start; i <= end; i++)
				{
					if (szMessage[i] == '{' || szMessage[i] == '}')
						szMessage[i] = ' ';
				}
			}
		}
		else
		{
			// No (more) braces found, we can exit the loop
			bracesFound = false;
		}
	}
}

stock void RemoveDuplicatePrefixAndSuffix(char[] sBuffer)
{
	if (!sBuffer[0] || sBuffer[0] == '\0')
		return;

	int length = strlen(sBuffer);

	// Find the longest prefix
	int prefixLength = 0;
	while (prefixLength < length && sBuffer[prefixLength] == sBuffer[0])
		prefixLength++;

	// Find the longest suffix
	int suffixLength = 0;
	while (suffixLength < length && sBuffer[length - suffixLength - 1] == sBuffer[length - 1])
		suffixLength++;

	// Check if there are duplicate prefix and suffix
	if (prefixLength > 1 && suffixLength > 1 && prefixLength + suffixLength < length)
	{
		// Remove duplicates
		int newSize = length - prefixLength - suffixLength;
		for (int i = 0; i < newSize; i++)
			sBuffer[i] = sBuffer[i + prefixLength];

		sBuffer[newSize] = '\0';
	}
}

public bool StringContainDecimal(char[] input)
{
	for (int i = 0; i < strlen(input); i++)
	{
		if (input[i] == '.' || input[i] == ',')
			return true;
	}

	return false;
}

stock void PrepareHudMsg(int client, char[] sBuffer, bool isCountdown = false)
{
	if (!g_bEnableHud || !IsValidClient(client, false, false, false))
		return;

	SendHudMsg(client, sBuffer, isCountdown);
}

stock void SendHudMsg(int client, const char[] szMessage, bool isCountdown)
{
	if (!IsValidClient(client, false, false, false))
		return;

	float duration = isCountdown ? 1.0 : g_fHudDuration;
	SetHudTextParams(g_fHudPos[0], g_fHudPos[1], duration, g_iHudColor[0], g_iHudColor[1], g_iHudColor[2], 255, 0, 0.0, 0.0, g_fHudFadeOutDuration);

	bool bDynamicAvailable = false;
	int iHUDChannel = -1;

	int iChannel = g_iHUDChannel;
	if (iChannel < 0 || iChannel > 5)
		iChannel = 0;

	bDynamicAvailable = g_bPlugin_DynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;

#if defined _DynamicChannels_included_
	if (bDynamicAvailable)
		iHUDChannel = GetDynamicChannel(iChannel);
#endif

	if (bDynamicAvailable)
		ShowHudText(client, iHUDChannel, szMessage);
	else
	{
		ClearSyncHud(client, g_hHudSync);
		ShowSyncHudText(client, g_hHudSync, szMessage);
	}
}

/**
 * Checks if a message contains square brackets with content after them
 * Optimized to do single pass through string with early returns
 *
 * @param szMessage    The message to check
 * @return             True if valid square brackets with content are found
 */
stock bool ItContainSquarebracket(const char[] szMessage)
{
	int length = strlen(szMessage);
	if (length < 3) // Needs at least 3 chars: [x]
		return false;

	for (int i = 0; i < length - 2; i++) // -2 because we need room for ] and content
	{
		if (szMessage[i] != '[')
			continue;

		// Look for matching ] with content after
		for (int j = i + 1; j < length - 1; j++)
		{
			if (szMessage[j] == ']')
			{
				// Found closing bracket, check if there's content after
				if (szMessage[j + 1] != '\0')
					return true;

				break; // No content after ], try next [
			}
		}
	}
	return false;
}

/**
 * Checks if a sequence of characters contain color codes
 *
 * @param sMessage      The string to check
 * @return             	True if a color code is found, false if not
 */
stock bool ItContainColorcode(const char[] szMessage)
{
	int len = strlen(szMessage), colorPos = 0;
	bool inBrace = false;
	char colorName[64];

	for (int i = 0; i < len; i++)
	{
		if (szMessage[i] == '{')
		{
			inBrace = true;
			colorPos = 0;
			continue;
		}

		if (inBrace)
		{
			if (szMessage[i] == '}')
			{
				// End of color name, check if valid
				colorName[colorPos] = '\0';
				int dummy;
				if (g_hColorMap.GetValue(colorName, dummy))
					return true;

				inBrace = false;
			}
			else if (colorPos < sizeof(colorName) - 1)
			{
				// Build color name
				colorName[colorPos++] = szMessage[i];
			}
			else
			{
				// Color name too long, reset
				inBrace = false;
			}
		}
	}

	return false;
}

/**
 * Checks if a sequence of characters are valid hex characters
 *
 * @param sMessage      The string to check
 * @param startPos      Starting position in the string
 * @param length        Number of characters to check
 * @return             	True if all characters are valid hex, false otherwise
 */
stock bool IsValidHexSequence(const char[] sMessage, int startPos, int length)
{
	bool dummy;
	for (int i = 0; i < length; i++)
	{
		if (!g_hHexMap.GetValue(sMessage[startPos + i], dummy))
			return false;
	}

	return true;
}

/**
 * Removes color from a string
 *
 * @param sMessage          The string to clean up
 * @return none
 */
stock void RemoveColorCodes(char[] sMessage)
{
	int len = strlen(sMessage);
	int writePos = 0;

	for (int i = 0; i < len; i++)
	{
		// Check for bell character (\x07) followed by 6 hex chars
		if (sMessage[i] == '\x07' && i + 6 < len && IsValidHexSequence(sMessage, i + 1, 6))
		{
			i += 6;
			continue;
		}
		// Check for \x08 character followed by 8 hex chars
		else if (sMessage[i] == '\x08' && i + 8 < len && IsValidHexSequence(sMessage, i + 1, 8))
		{
			i += 8;
			continue;
		}

		// Copy character to new position
		sMessage[writePos] = sMessage[i];
		writePos++;
	}

	// Null terminate the string
	sMessage[writePos] = '\0';

	// Check if string has other color codes
	for (int j = 0; j < sizeof(g_sColorSymbols); j++)
		ReplaceString(sMessage, strlen(sMessage), g_sColorSymbols[j], "", false);
}

/**
 * Display message to clients
 *
 * @param sMessage			The message to display
 * @param bScript			If the chat message is vscript (so color codes are properly handled)
 * @return none
 */
stock void SendServerMessage(const char[] sMessage, bool bScript = false)
{
	// Because color codes break number detection and hud formatting
	// we create a separate "clean" string to store text w/o colors
	char sText[MAXLENGTH_INPUT], sTrimText[MAXLENGTH_INPUT];

	// Store raw color message to sText
	strcopy(sText, sizeof(sText), sMessage);
	StripQuotes(sText);

	// Store the raw message to sTrimText then we clean up the string
	strcopy(sTrimText, sizeof(sTrimText), sText);
	RemoveColorCodes(sTrimText);

	if (g_bBlockSpam)
	{
		int currentTime = GetTime();
		if (strcmp(sText, g_sLastMessage, true) == 0)
		{
			if (g_iLastMessageTime != -1 && ((currentTime - g_iLastMessageTime) <= g_iBlockSpamDelay))
			{
				g_sLastMessage = sText;
				g_iLastMessageTime = currentTime;
				return;
			}
		}
		g_sLastMessage = sText;
		g_iLastMessageTime = currentTime;
	}

	char soundp[255], soundt[255];
	if (g_bTranslation)
	{
		if (kv == INVALID_HANDLE)
			ReadT();

		if (!KvJumpToKey(kv, sText))
		{
			KvJumpToKey(kv, sText, true);
			KvSetString(kv, "default", sText);
			KvRewind(kv);
			KeyValuesToFile(kv, g_sPath);
			KvJumpToKey(kv, sText);
		}

		bool blocked = (KvGetNum(kv, "blocked", 0) ? true : false);
		if (blocked)
		{
			KvRewind(kv);
			return;
		}

		KvGetString(kv, "sound", soundp, sizeof(soundp), "default");
		if (strcmp(soundp, "default") == 0)
			FormatEx(soundt, 255, "common/talk.wav");
		else
			FormatEx(soundt, 255, soundp);
	}

	char sFinalText[1024];
	char sCountryTag[3];
	char sIP[26];
	bool isCountable = IsCountable(sTrimText);
	bool containsDecimal = StringContainDecimal(sTrimText);
	bool isCountdown = !containsDecimal && isCountable;

	for (int i = 1 ; i < MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i))
			continue;

		if (g_bTranslation)
		{
			GetClientIP(i, sIP, sizeof(sIP));
			GeoipCode2(sIP, sCountryTag);
			KvGetString(kv, sCountryTag, sText, sizeof(sText), "LANGMISSING");

			if (strcmp(sText, "LANGMISSING") == 0)
				KvGetString(kv, "default", sText, sizeof(sText));
		}

		FormatEx(sFinalText, sizeof(sFinalText), "%s", sText);

		if (!g_bRemoveConsoleTag || g_bRemoveConsoleTag && (!ItContainSquarebracket(sText) || !ItContainColorcode(sText)))
			// Because vscript messages can use custom chat colors, don't add console tag in this case
			if (!bScript)
				FormatEx(sFinalText, sizeof(sFinalText), "%s%s", g_sConsoleTag, sText);

		if (isCountable && GetRoundTimeAtTimerEnd() > 0)
		{
			float fMinutes = GetRoundTimeAtTimerEnd() / 60.0;
			int minutes = RoundToFloor(fMinutes);
			int seconds = GetRoundTimeAtTimerEnd() - minutes * 60;
			char roundTimeText[32];

			FormatEx(roundTimeText, sizeof(roundTimeText), " {orange}@ %i:%s%i", minutes, (seconds < 10 ? "0" : ""), seconds);
			FormatEx(sFinalText, sizeof(sFinalText), "%s%s", sFinalText, roundTimeText);
		}

		CPrintToChat(i, sFinalText);

		// Prepare HUD message
		if (g_bEnableHud)
		{
			if (g_bHudMapSymbols)
				RemoveDuplicatePrefixAndSuffix(sTrimText);

			RemoveTextInBraces(sTrimText, true, true);

			char szMessage[MAXLENGTH_INPUT + 10];
			if (g_bHudSymbols)
				FormatEx(szMessage, sizeof(szMessage), ">> %s <<", sTrimText);
			else
				FormatEx(szMessage, sizeof(szMessage), "%s", sTrimText);

			PrepareHudMsg(i, szMessage, isCountdown);

			if (isCountable)
				InitCountDown(szMessage);
		}
	}

	if (g_bTranslation)
	{
		if (strcmp(soundp, "none", false) != 0)
			EmitSoundToAll(soundt);

		if (KvJumpToKey(kv, "hinttext"))
		{
			for (int i = 1 ; i < MaxClients; i++)
			{
				if (!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i))
					continue;

				GetClientIP(i, sIP, sizeof(sIP));
				GeoipCode2(sIP, sCountryTag);
				KvGetString(kv, sCountryTag, sText, sizeof(sText), "LANGMISSING");

				if (strcmp(sText, "LANGMISSING") == 0)
					KvGetString(kv, "default", sText, sizeof(sText));

				PrintHintText(i, sText);
			}
		}

		KvRewind(kv);
	}
}

void InitColorMap()
{
	if (g_hColorMap != null)
		delete g_hColorMap;

	g_hColorMap = new StringMap();

	char colors[][] = {
		"aliceblue", "allies", "ancient", "antiquewhite", "aqua", "aquamarine", "arcana", "axis", "azure",
		"beige", "bisque", "black", "blanchedalmond", "blue", "blueviolet", "brown", "burlywood",
		"cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue", "cornsilk", "crimson", "cyan",
		"darkblue", "darkcyan", "darkgoldenrod", "darkgray", "darkgreen", "darkkhaki", "darkmagenta", "darkolivegreen",
		"darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen", "darkslateblue", "darkslategray", "darkturquoise",
		"darkviolet", "deeppink", "deepskyblue", "dimgray", "dodgerblue", "exalted", "firebrick", "floralwhite",
		"forestgreen", "fuchsia", "fullblue", "fullred", "gainsboro", "ghostwhite", "gold", "goldenrod",
		"gray", "grey", "green", "greenyellow", "honeydew", "hotpink", "indianred", "indigo", "ivory",
		"khaki", "lavender", "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral", "lightcyan",
		"lightgoldenrodyellow", "lightgray", "lightgreen", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray",
		"lightslategrey", "lightsteelblue", "lightyellow", "lime", "limegreen", "linen", "magenta", "maroon",
		"mediumaquamarine", "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise",
		"mediumvioletred", "midnightblue", "mintcream", "mistyrose", "moccasin", "navajowhite", "navy", "normal", "oldlace",
		"olive", "olivedrab", "orange", "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise",
		"palevioletred", "papayawhip", "peachpuff", "peru", "pink", "plum", "powderblue", "purple",
		"rare", "red", "rosybrown", "royalblue", "saddlebrown", "salmon", "sandybrown", "seagreen",
		"seashell", "sienna", "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow",
		"springgreen", "steelblue", "tan", "teal", "thistle", "tomato", "turquoise", "uncommon", "unique",
		"unusual", "valve", "vintage", "violet", "wheat", "white", "whitesmoke", "yellow", "yellowgreen"
	};

	for (int i = 0; i < sizeof(colors); i++)
		g_hColorMap.SetValue(colors[i], 1);

	delete g_hHexMap;
	g_hHexMap = new StringMap();

	static const char HexChar[][] = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "a", "b", "c", "d", "e", "f"};
	for (int i = 0; i < sizeof(HexChar); i++)
		g_hHexMap.SetValue(HexChar[i], true);
}
