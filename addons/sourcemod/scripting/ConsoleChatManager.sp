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

#include <sdktools>
#include <multicolors>
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
#define MAXLENGTH_SAYTEXT2 249
#define NORMALHUD 1

ConVar g_hCVar_ConsoleMessage;
ConVar g_hCVar_BlockSpam;
ConVar g_hCVar_BlockSpamDelay;
ConVar g_hCVar_EnableHud;
ConVar g_hCVar_HudPosition;
ConVar g_hCVar_HudColor;
ConVar g_hCVar_HudDuration;
ConVar g_hCVar_HudDurationFadeOut;
ConVar g_hCVar_HudChannel;

char g_sBlacklist[][] = { "recharge", "recast", "cooldown", "cool", "cd" };
char g_sColorSymbols[][] = { "\x01", "\x03", "\x04", "\x05", "\x06" }; // \x07 and \x08 is ommitted because it requires additional check
char g_sLastMessage[MAXLENGTH_INPUT] = "";
char g_sConsoleTag[255];
char g_sHudPosition[16], g_sHudColor[64];

float g_fHudPos[2];
float g_fHudDuration;
float g_fHudFadeOutDuration;

bool g_bPlugin_DynamicChannels = false;
bool g_bEnableHud;
bool g_bBlockSpam;

int g_iHudColor[3];
int g_iNumber, g_iOnumber;
int g_iLastMessageTime = -1;
int g_iRoundStartedTime = -1;
int g_iHUDChannel;
int g_iBlockSpamDelay;

Handle g_hTimerHandle;
Handle g_hHudSync;

DHookSetup g_hClientPrintDtr;

public Plugin myinfo =
{
	name = "ConsoleChatManager-Lite",
	author = "Franc1sco Franug, maxime1907, inGame, AntiTeal, Oylsister, .Rushaway, tilgep, koen",
	description = "Interact with console messages",
	version = "2.4.5",
	url = ""
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	DeleteTimer();
	g_hHudSync = CreateHudSynchronizer();

	g_hCVar_ConsoleMessage = CreateConVar("sm_consolechatmanager_tag", "{green}[Console] {white}", "The tag that will be printed instead of the console default messages");

	g_hCVar_EnableHud = CreateConVar("sm_consolechatmanager_hud", "1", "Enables printing the console output in the middle of the screen");
	g_hCVar_HudDuration = CreateConVar("sm_consolechatmanager_hud_duration", "2.5", "How long the message stays");
	g_hCVar_HudDurationFadeOut = CreateConVar("sm_consolechatmanager_hud_duration_fadeout", "1.0", "How long the message takes to disapear");
	g_hCVar_HudPosition = CreateConVar("sm_consolechatmanager_hud_position", "-1.0 0.125", "The X and Y position for the hud.");
	g_hCVar_HudColor = CreateConVar("sm_consolechatmanager_hud_color", "0 255 0", "RGB color value for the hud.");
	g_hCVar_HudChannel = CreateConVar("sm_consolechatmanager_hud_channel", "0", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 5.0);

	g_hCVar_BlockSpam = CreateConVar("sm_consolechatmanager_block_spam", "1", "Blocks console messages that repeat the same message.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVar_BlockSpamDelay = CreateConVar("sm_consolechatmanager_block_spam_delay", "1", "Time to wait before printing the same message", FCVAR_NONE, true, 1.0, true, 60.0);

	// Hook Convars
	g_hCVar_ConsoleMessage.AddChangeHook(OnConVarChanged);
	g_hCVar_EnableHud.AddChangeHook(OnConVarChanged);
	g_hCVar_HudDuration.AddChangeHook(OnConVarChanged);
	g_hCVar_HudDurationFadeOut.AddChangeHook(OnConVarChanged);
	g_hCVar_HudPosition.AddChangeHook(OnConVarChanged);
	g_hCVar_HudColor.AddChangeHook(OnConVarChanged);
	g_hCVar_HudChannel.AddChangeHook(OnConVarChanged);
	g_hCVar_BlockSpam.AddChangeHook(OnConVarChanged);
	g_hCVar_BlockSpamDelay.AddChangeHook(OnConVarChanged);

	// Initilize convars values
	g_hCVar_ConsoleMessage.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	g_bEnableHud = g_hCVar_EnableHud.BoolValue;
	g_fHudDuration = g_hCVar_HudDuration.FloatValue;
	g_fHudFadeOutDuration = g_hCVar_HudDurationFadeOut.FloatValue;
	UpdateHudPosition();
	UpdateHudColor();
	g_iHUDChannel = g_hCVar_HudChannel.IntValue;
	g_bBlockSpam = g_hCVar_BlockSpam.BoolValue;
	g_iBlockSpamDelay = g_hCVar_BlockSpamDelay.IntValue;

	AddCommandListener(SayConsole, "say");

	AutoExecConfig(true);

	// For now VScript detour is only supported for Counter-Strike: Source
	EngineVersion iEngine = GetEngineVersion();
	if (iEngine != Engine_CSS)
	{
		return;
	}

	// ClientPrint detour
	GameData gd;
	if ((gd = new GameData("ConsoleChatManager.games")) == null)
	{
		LogError("Failed to find or load gamedata file!");
		return;
	}

	if ((g_hClientPrintDtr = DynamicDetour.FromConf(gd, "ClientPrint")) == null)
	{
		LogError("Failed to setup ClientPrint() detour!");
		delete gd;
		return;
	}
	else
	{
		if (!DHookEnableDetour(g_hClientPrintDtr, false, Detour_ClientPrint))
		{
			LogError("Failed to detour ClientPrint()!");
		}
		else
		{
			LogMessage("Failed Successfully detoured ClientPrint()!");
		}
	}
}

public void OnAllPluginsLoaded()
{
	g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = false;
	}
}

public void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_hCVar_ConsoleMessage)
	{
		g_hCVar_ConsoleMessage.GetString(g_sConsoleTag, sizeof(g_sConsoleTag));
	}
	else if (convar == g_hCVar_EnableHud)
	{
		g_bEnableHud = g_hCVar_EnableHud.BoolValue;
	}
	else if (convar == g_hCVar_HudDuration)
	{
		g_fHudDuration = g_hCVar_HudDuration.FloatValue;
	}
	else if (convar == g_hCVar_HudDurationFadeOut)
	{
		g_fHudFadeOutDuration = g_hCVar_HudDurationFadeOut.FloatValue;
	}
	else if (convar == g_hCVar_HudPosition)
	{
		UpdateHudPosition();
	}
	else if (convar == g_hCVar_HudColor)
	{
		UpdateHudColor();
	}
	else if (convar == g_hCVar_HudChannel)
	{
		g_iHUDChannel = g_hCVar_HudChannel.IntValue;
	}
	else if (convar == g_hCVar_BlockSpam)
	{
		g_bBlockSpam = g_hCVar_BlockSpam.BoolValue;
	}
	else if (convar == g_hCVar_BlockSpamDelay)
	{
		g_iBlockSpamDelay = g_hCVar_BlockSpamDelay.IntValue;
	}
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
	g_hCVar_HudPosition.GetString(g_sHudPosition, sizeof(g_sHudPosition));
	ExplodeString(g_sHudPosition, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));
	g_fHudPos[0] = StringToFloat(StringPos[0]);
	g_fHudPos[1] = StringToFloat(StringPos[1]);
}

stock void UpdateHudColor()
{
	g_hCVar_HudColor.GetString(g_sHudColor, sizeof(g_sHudColor));
	ColorStringToArray(g_sHudColor, g_iHudColor);
}

public bool CheckStringBlacklist(const char[] string)
{
	for (int i = 0; i < sizeof(g_sBlacklist); i++)
	{
		if (StrContains(string, g_sBlacklist[i], false) != -1)
		{
			return true;
		}
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
		{
			FilterText[filterPos++] = sMessage[i];
		}
	}

	FilterText[filterPos] = '\0';
	TrimString(FilterText);

	if (CheckStringBlacklist(sMessage))
	{
		return isCountable;
	}

	int words = ExplodeString(FilterText, " ", ChatArray, sizeof(ChatArray), sizeof(ChatArray[]));

	if (words == 1)
	{
		if (StringToInt(ChatArray[0]) != 0)
		{
			isCountable = true;
			consoleNumber = StringToInt(ChatArray[0]);
		}
	}

	for (int i = 0; i < words; i++)
	{
		if (StringToInt(ChatArray[i]) != 0)
		{
			if (i + 1 < words && (strcmp(ChatArray[i + 1], "s", false) == 0 || (IsCharEqualIgnoreCase(ChatArray[i + 1][0], 's') && IsCharEqualIgnoreCase(ChatArray[i + 1][1], 'e'))))
			{
				consoleNumber = StringToInt(ChatArray[i]);
				isCountable = true;
			}

			if (!isCountable && i + 2 < words && (strcmp(ChatArray[i + 2], "s", false) == 0 || (IsCharEqualIgnoreCase(ChatArray[i + 2][0], 's') && IsCharEqualIgnoreCase(ChatArray[i + 2][1], 'e'))))
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
	{
		return Plugin_Continue;
	}

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
	{
		return MRES_Ignored;
	}

	// Check if the print was sent to chat
	EHudNotify iDestination = view_as<EHudNotify>(DHookGetParam(hParams, 2));
	if (iDestination != HUD_PRINTTALK)
	{
		return MRES_Ignored;
	}

	// Get chat message and pass through display function
	char sBuffer[MAXLENGTH_INPUT];
	DHookGetParamString(hParams, 3, sBuffer, sizeof(sBuffer));
	SendServerMessage(sBuffer, true);

	return MRES_Supercede;
}

public int StringEnder(char[] a, int b, int c)
{
	if (IsCharEqualIgnoreCase(a[b], 'c'))
	{
		a[c - 3] = '\0';
	}
	else
	{
		a[c - 1] = '\0';
	}

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
			{
				ClearSyncHud(i, g_hHudSync);
			}
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
	{
		SendHudMsg(i, string, true);
	}

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
					{
						szMessage[i] = ' ';
					}
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

public bool StringContainDecimal(char[] input)
{
	for (int i = 0; i < strlen(input); i++)
	{
		if (input[i] == '.' || input[i] == ',')
		{
			return true;
		}
	}

	return false;
}

stock void SendHudMsg(int client, const char[] szMessage, bool isCountdown)
{
	if (!IsValidClient(client, false, false, false))
	{
		return;
	}

	float duration = isCountdown ? 1.0 : g_fHudDuration;
	SetHudTextParams(g_fHudPos[0], g_fHudPos[1], duration, g_iHudColor[0], g_iHudColor[1], g_iHudColor[2], 255, 0, 0.0, 0.0, g_fHudFadeOutDuration);

	bool bDynamicAvailable = false;
	int iHUDChannel = -1;

	int iChannel = g_iHUDChannel;
	if (iChannel < 0 || iChannel > 5)
	{
		iChannel = 0;
	}

	bDynamicAvailable = g_bPlugin_DynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;

#if defined _DynamicChannels_included_
	if (bDynamicAvailable)
	{
		iHUDChannel = GetDynamicChannel(iChannel);
	}
#endif

	if (bDynamicAvailable)
	{
		ShowHudText(client, iHUDChannel, szMessage);
	}
	else
	{
		ClearSyncHud(client, g_hHudSync);
		ShowSyncHudText(client, g_hHudSync, szMessage);
	}
}

/**
 * Checks if a sequence of characters are valid hex characters
 *
 * @param sMessage      The string to check
 * @param startPos      Starting position in the string
 * @param length        Number of characters to check
 * @return             True if all characters are valid hex, false otherwise
 */
stock bool IsValidHexSequence(const char[] sMessage, int startPos, int length)
{
	for (int j = 0; j < length; j++)
	{
		char c = sMessage[startPos + j];
		bool isDigit = (c >= '0' && c <= '9');
		bool isUpperHex = (c >= 'A' && c <= 'F');
		bool isLowerHex = (c >= 'a' && c <= 'f');

		if (!isDigit && !isUpperHex && !isLowerHex)
		{
			return false;
		}
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
	{
		ReplaceString(sMessage, strlen(sMessage), g_sColorSymbols[j], "", false);
	}
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

	char sFinalText[1024];
	bool isCountable = IsCountable(sTrimText);
	bool containsDecimal = StringContainDecimal(sTrimText);
	bool isCountdown = !containsDecimal && isCountable;

	FormatEx(sFinalText, sizeof(sFinalText), "%s", sText);

	// Because vscript messages can use custom chat colors, don't add console tag in this case
	if (!bScript)
	{
		FormatEx(sFinalText, sizeof(sFinalText), "%s%s", g_sConsoleTag, sText);
	}

	if (isCountable && GetRoundTimeAtTimerEnd() > 0)
	{
		float fMinutes = GetRoundTimeAtTimerEnd() / 60.0;
		int minutes = RoundToFloor(fMinutes);
		int seconds = GetRoundTimeAtTimerEnd() - minutes * 60;
		char roundTimeText[32];

		FormatEx(roundTimeText, sizeof(roundTimeText), " {orange}@ %i:%s%i", minutes, (seconds < 10 ? "0" : ""), seconds);
		FormatEx(sFinalText, sizeof(sFinalText), "%s%s", sFinalText, roundTimeText);
	}

	// Overflow protection
	if (MAXLENGTH_SAYTEXT2 - strlen(sFinalText) <= 1)
	{
		PrintToServer("[ConsoleChatManager] Message is too long to be sent to clients, skipping display. Message: %s", sFinalText);
		return;
	}

	CPrintToChatAll(sFinalText);

	// Prepare HUD message
	if (g_bEnableHud)
	{
		RemoveTextInBraces(sTrimText, true, true);
		char szMessage[MAXLENGTH_INPUT + 10];
		FormatEx(szMessage, sizeof(szMessage), "%s", sTrimText);
		for (int i = 1 ; i < MaxClients; i++)
		{
			SendHudMsg(i, szMessage, isCountdown);
		}

		if (isCountable)
		{
			InitCountDown(szMessage);
		}
	}
}
