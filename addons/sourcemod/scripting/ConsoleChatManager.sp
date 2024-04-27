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
#include <utilshelper.inc>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

#pragma newdecls required

#define MAXLENGTH_INPUT		512
#define NORMALHUD 1
#define CSGO_WARMUPTIMER 2

ConVar g_ConsoleMessage, g_EnableTranslation, g_cRemoveConsoleTag;
ConVar g_cBlockSpam, g_cBlockSpamDelay;
ConVar g_EnableHud, g_cHudPosition, g_cHudColor, g_cHudHtmlColor;
ConVar g_cHudMapSymbols, g_cHudSymbols;
ConVar g_cHudDuration, g_cHudDurationFadeOut;
ConVar g_cHudType, g_cvHUDChannel;

char g_sBlacklist[][] = { "recharge", "recast", "cooldown", "cool" };
char g_sColorlist[][] = {
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
	"unusual", "valve", "vintage", "violet", "wheat", "white", "whitesmoke", "yellow", "yellowgreen" };
char g_sPath[PLATFORM_MAX_PATH];
char g_sLastMessage[MAXLENGTH_INPUT] = "";
char g_sConsoleTag[255];
char g_sHudPosition[16], g_sHudColor[64], g_sHtmlColor[64];

float g_fHudPos[2];
float g_fHudDuration, g_fHudFadeOutDuration;

bool g_bisCSGO = false;
bool g_bPlugin_DynamicChannels = false;
bool g_bTranslation, g_bEnableHud, g_bHudMapSymbols, g_bHudSymbols, g_bBlockSpam, g_bRemoveConsoleTag;

int g_iHudColor[3];
int g_iNumber, g_iOnumber;
int g_iLastMessageTime = -1;
int g_iRoundStartedTime = -1;
int g_iHudtype, g_iHUDChannel, g_iBlockSpamDelay;

Handle kv;
Handle g_hTimerHandle, g_hHudSync;

public Plugin myinfo = 
{
	name = "ConsoleChatManager",
	author = "Franc1sco Steam: franug, maxime1907, inGame, AntiTeal, Oylsister, .Rushaway",
	description = "Interact with console messages",
	version = "2.3.1",
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
	g_cHudType = CreateConVar("sm_consolechatmanager_hud_type", "1", "Specify the type of Hud Msg [1 = SendTextHud, 2 = CS:GO Warmup Timer]", _, true, 1.0, true, 2.0);
	g_cHudHtmlColor = CreateConVar("sm_consolechatmanager_hud_htmlcolor", "#6CFF00", "Html color for second type of Hud Message");
	g_cvHUDChannel = CreateConVar("sm_consolechatmanager_hud_channel", "0", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 6.0);

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
	g_cHudType.AddChangeHook(OnConVarChanged);
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
	g_iHudtype = g_cHudType.IntValue;
	g_cHudHtmlColor.GetString(g_sHtmlColor, sizeof(g_sHtmlColor));
	g_iHUDChannel = g_cvHUDChannel.IntValue;
	g_bBlockSpam = g_cBlockSpam.BoolValue;
	g_iBlockSpamDelay = g_cBlockSpamDelay.IntValue;

	AddCommandListener(SayConsole, "say");

	AutoExecConfig(true);
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bisCSGO = (GetEngineVersion() == Engine_CSGO);
	return APLRes_Success;
}

public void OnMapStart()
{
	if (g_bTranslation)
		ReadT();
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
	else if (convar == g_cHudType)
		g_iHudtype = g_cHudType.IntValue;
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
	if(g_hTimerHandle != INVALID_HANDLE)
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

	if(!FileExists(g_sPath))
	{
		StringToLowerCase(map);
		BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "configs/consolechatmanager/%s.txt", map);
	}

	kv = CreateKeyValues("Console_C");
	// File not found, create the file
	if(!FileExists(g_sPath))
		KeyValuesToFile(kv, g_sPath);
	else
		FileToKeyValues(kv, g_sPath);
	
	CheckSounds();
}

void CheckSounds()
{
	PrecacheSound("common/talk.wav", false);

	char buffer[255];
	if(KvGotoFirstSubKey(kv))
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
		if(StrContains(string, g_sBlacklist[i], false) != -1)
		{
			return true;
		}
	}
	return false;
}

public bool IsCountable(const char[] sMessage)
{
	char FilterText[MAXLENGTH_INPUT], ChatArray[32][MAXLENGTH_INPUT];
	int consoleNumber, filterPos;
	bool countable = false;

	for (int i = 0; i < MAXLENGTH_INPUT && filterPos < MAXLENGTH_INPUT; i++)
	{
		if (IsCharAlpha(sMessage[i]) || IsCharNumeric(sMessage[i]) || IsCharSpace(sMessage[i]))
		{
			FilterText[filterPos++] = sMessage[i];
		}
	}
	FilterText[filterPos] = '\0';
	TrimString(FilterText);

	// Check if the filtered message is empty or contains only spaces
	if (CheckStringBlacklist(FilterText))
		return false;

	int words = ExplodeString(FilterText, " ", ChatArray, sizeof(ChatArray), sizeof(ChatArray[]));

	// Loop through the words to find a countable number
	for (int i = 0; i < words; i++)
	{
		int num = StringToInt(ChatArray[i]);
		if (num != 0)
		{
			// Check for other conditions to set countable to true
			if (i + 1 < words && (strcmp(ChatArray[i + 1], "s", false) == 0 || (CharEqual(ChatArray[i + 1][0], 's') && CharEqual(ChatArray[i + 1][1], 'e'))))
			{
				countable = true;
			}
			else if (i + 2 < words && (strcmp(ChatArray[i + 2], "s", false) == 0 || (CharEqual(ChatArray[i + 2][0], 's') && CharEqual(ChatArray[i + 2][1], 'e'))))
			{
				countable = true;
			}
			else if (IsCountableNumber(ChatArray[i]))
			{
				countable = true;
			}

			if (countable)
			{
				consoleNumber = num;
			}
		}
	}

	// Update the countable number and return whether it was found
	g_iNumber = consoleNumber;
	g_iOnumber = consoleNumber;
	return consoleNumber != 0 && countable;
}

bool IsCountableNumber(const char[] word)
{
	int len = strlen(word);
	if (len > 1 && IsCharNumeric(word[0]))
	{
		if (len > 2 && IsCharNumeric(word[1]))
		{
			if (len > 3 && IsCharNumeric(word[2]) && CharEqual(word[3], 's'))
			{
				return true;
			}
			else if (CharEqual(word[2], 's'))
			{
				return true;
			}
		}
		else if (CharEqual(word[1], 's'))
		{
			return true;
		}
	}
	return false;
}

public Action SayConsole(int client, const char[] command, int args)
{
	if (client)
		return Plugin_Continue;

	char sText[MAXLENGTH_INPUT];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);

	if (g_bBlockSpam)
	{
		int currentTime = GetTime();
		if (strcmp(sText, g_sLastMessage, true) == 0)
		{
			if (g_iLastMessageTime != -1 && ((currentTime - g_iLastMessageTime) <= g_iBlockSpamDelay))
			{
				g_sLastMessage = sText;
				g_iLastMessageTime = currentTime;
				return Plugin_Handled;
			}
		}
		g_sLastMessage = sText;
		g_iLastMessageTime = currentTime;
	}

	char soundp[255], soundt[255];
	if (g_bTranslation)
	{
		if(kv == INVALID_HANDLE)
		{
			ReadT();
		}

		if(!KvJumpToKey(kv, sText))
		{
			KvJumpToKey(kv, sText, true);
			KvSetString(kv, "default", sText);
			KvRewind(kv);
			KeyValuesToFile(kv, g_sPath);
			KvJumpToKey(kv, sText);
		}

		bool blocked = (KvGetNum(kv, "blocked", 0) ? true : false);

		if(blocked)
		{
			KvRewind(kv);
			return Plugin_Handled;
		}

		KvGetString(kv, "sound", soundp, sizeof(soundp), "default");
		if(strcmp(soundp, "default") == 0)
			FormatEx(soundt, 255, "common/talk.wav");
		else
			FormatEx(soundt, 255, soundp);
	}

	char sFinalText[1024];
	char sCountryTag[3];
	char sIP[26];
	bool isCountable = IsCountable(sText);

	for(int i = 1 ; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && (!IsFakeClient(i) || IsClientSourceTV(i)))
		{
			if (g_bTranslation)
			{
				GetClientIP(i, sIP, sizeof(sIP));
				GeoipCode2(sIP, sCountryTag);
				KvGetString(kv, sCountryTag, sText, sizeof(sText), "LANGMISSING");

				if (strcmp(sText, "LANGMISSING") == 0) KvGetString(kv, "default", sText, sizeof(sText));
			}

			FormatEx(sFinalText, sizeof(sFinalText), "%s", sText);

			if (!g_bRemoveConsoleTag || g_bRemoveConsoleTag && (!ItContainSquarebracket(sText) || !ItContainColorcode(sText)))
				FormatEx(sFinalText, sizeof(sFinalText), "%s%s", g_sConsoleTag, sText);

			if(isCountable && GetRoundTimeAtTimerEnd() > 0)
			{
				float fMinutes = GetRoundTimeAtTimerEnd() / 60.0;
				int minutes = RoundToFloor(fMinutes);
				int seconds = GetRoundTimeAtTimerEnd() - minutes * 60;
				char roundTimeText[32];

				FormatEx(roundTimeText, sizeof(roundTimeText), " {orange}@ %i:%s%i", minutes, (seconds < 10 ? "0" : ""), seconds);
				FormatEx(sFinalText, sizeof(sFinalText), "%s%s", sFinalText, roundTimeText);
			}

			CPrintToChat(i, sFinalText);
			PrepareHudMsg(i, sText);
		}
	}

	if (g_bTranslation)
	{
		if(strcmp(soundp, "none", false) != 0)
			EmitSoundToAll(soundt);

		if(KvJumpToKey(kv, "hinttext"))
		{
			for(int i = 1 ; i < MaxClients; i++)
				if(IsClientInGame(i) && (!IsFakeClient(i) || IsClientSourceTV(i)))
				{
					GetClientIP(i, sIP, sizeof(sIP));
					GeoipCode2(sIP, sCountryTag);
					KvGetString(kv, sCountryTag, sText, sizeof(sText), "LANGMISSING");

					if (strcmp(sText, "LANGMISSING") == 0) KvGetString(kv, "default", sText, sizeof(sText));
				
					PrintHintText(i, sText);
				}
		}

		KvRewind(kv);
	}
	return Plugin_Handled;
}

public bool CharEqual(int a, int b)
{
	if(a == b || a == CharToLower(b) || a == CharToUpper(b))
	{
		return true;
	}
	return false;
}

public int StringEnder(char[] a, int b, int c)
{
	if(CharEqual(a[b], 'c'))
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
	if(g_hTimerHandle != INVALID_HANDLE)
	{
		KillTimer(g_hTimerHandle);
		g_hTimerHandle = INVALID_HANDLE;
	}

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
			if(IsValidClient(i, false, false, false))
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
		PrepareHudMsg(i, string, true);

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

stock void RemoveDuplicatePrefixAndSuffix(char[] sBuffer, bool isRepeated = false)
{
	if (isRepeated || !sBuffer[0] || sBuffer[0] == '\0')
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
		{
			sBuffer[i] = sBuffer[i + prefixLength];
		}

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

stock void PrepareHudMsg(int client, char[] sBuffer, bool isRepeated = false)
{
	if (!g_bEnableHud || !IsValidClient(client, false, false, false))
		return;

	if (g_bHudMapSymbols)
		RemoveDuplicatePrefixAndSuffix(sBuffer, isRepeated);

	RemoveTextInBraces(sBuffer, true, true);

	bool containsDecimal = StringContainDecimal(sBuffer);
	bool isCountdown = !containsDecimal && IsCountable(sBuffer);

	char szMessage[MAXLENGTH_INPUT + 10];
	FormatEx(szMessage, sizeof(szMessage), "%s", sBuffer);

	if (!isRepeated && g_bHudSymbols)
		FormatEx(szMessage, sizeof(szMessage), ">> %s <<", sBuffer);

	if (isCountdown)
		InitCountDown(szMessage);

	if (g_bisCSGO && g_iHudtype == NORMALHUD)
		SendCSGO_HudMsg(client, szMessage, isCountdown);
	else
		SendHudMsg(client, szMessage, isCountdown);
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
	if (iChannel < 0 || iChannel > 6)
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

stock void SendCSGO_HudMsg(int client, const char[] szMessage, bool isCountdown)
{
	if (!g_bisCSGO || !IsValidClient(client, false, false, false))
		return;

	// Event use int for duration
	int duration = isCountdown ? 2 : RoundToNearest(g_fHudDuration);

	// We don't want to mess with original constant char
	char originalmsg[MAX_BUFFER_LENGTH + 10];
	FormatEx(originalmsg, sizeof(originalmsg), "%s", szMessage);

	int orilen = strlen(originalmsg);

	// Need to remove These Html symbol from console message and replace with new html symbol.
	ReplaceString(originalmsg, orilen, "<", "&lt;", false);
	ReplaceString(originalmsg, orilen, ">", "&gt;", false);

	// Put color in to the message
	char newmessage[MAX_BUFFER_LENGTH + 10];
	int newlen = strlen(newmessage);

	// If the message is too long we need to reduce font size.
	if(newlen <= 65)
		// Put color in to the message (These html FormatEx is fine)
		FormatEx(newmessage, sizeof(newmessage), "<span class='fontSize-l'><span color='%s'>%s</span></span>", g_sHtmlColor, originalmsg);
	else if(newlen <= 100)
		FormatEx(newmessage, sizeof(newmessage), "<span class='fontSize-m'><span color='%s'>%s</span></span>", g_sHtmlColor, originalmsg);
	else
		FormatEx(newmessage, sizeof(newmessage), "<span class='fontSize-sm'><span color='%s'>%s</span></span>", g_sHtmlColor, originalmsg);

	// Fire the message to player (https://github.com/Kxnrl/CSGO-HtmlHud/blob/main/fys.huds.sp#L167)
	Event event = CreateEvent("show_survival_respawn_status");
	if (event != null)
	{
		event.SetString("loc_token", newmessage);
		event.SetInt("duration", duration);
		event.SetInt("userid", -1);
		if(client == -1)
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && (!IsFakeClient(i) || IsClientSourceTV(i)))
				{
					event.FireToClient(i);
				}
			}
		}
		else
		{
			event.FireToClient(client);
		}
		event.Cancel();
	}
}

stock bool ItContainSquarebracket(char[] szMessage)
{
	int i = 0;
	bool foundOpeningBracket = false;
	
	// Iterate through the message until the end or until we find ']' if we've already found '['
	while (szMessage[i] != '\0')
	{
		if (szMessage[i] == '[')
			foundOpeningBracket = true;
		// If we've found a ']' and we've previously found a '[', check if there's content after ']'
		else if (szMessage[i] == ']' && foundOpeningBracket && strlen(szMessage) > i + 1)
			return true;
		i++;
	}

	// If we reach here, either '[' or ']' wasn't found or there was no content after ']'
	return false;
}

stock bool ItContainColorcode(char[] szMessage)
{
	char szColor[64];
	for (int i = 0; i < sizeof(g_sColorlist); i++)
	{
		FormatEx(szColor, sizeof(szColor), "{%s}", g_sColorlist[i]);
		if(StrContains(szMessage, szColor, false) != -1)
			return true;
	}

	return false;
}