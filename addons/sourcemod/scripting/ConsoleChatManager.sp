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

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

#pragma newdecls required

#define MAXLENGTH_INPUT		512

#define NORMALHUD 1
#define CSGO_WARMUPTIMER 2

Handle kv;
char Path[PLATFORM_MAX_PATH];

char lastMessage[MAXLENGTH_INPUT] = "";

ConVar g_ConsoleMessage;
ConVar g_cBlockSpam;
ConVar g_cBlockSpamDelay;
ConVar g_EnableTranslation;
ConVar g_EnableHud;
ConVar g_cHudPosition;
ConVar g_cHudColor;
ConVar g_cHudMapSymbols;
ConVar g_cHudSymbols;
ConVar g_cHudDuration;
ConVar g_cHudDurationFadeOut;
ConVar g_cHudType;
ConVar g_cHudHtmlColor;
ConVar g_cvHUDChannel;

float HudPos[2];
int HudColor[3];
bool HudMapSymbols;
bool HudSymbols;

int number, onumber;
Handle timerHandle, HudSync;

char Blacklist[][] = {
	"recharge", "recast", "cooldown", "cool"
};

bool isCSGO;
bool g_bPlugin_DynamicChannels = false;

int lastMessageTime = -1;
int roundStartedTime = -1;
int hudtype;

char htmlcolor[64];

public Plugin myinfo = 
{
	name = "ConsoleChatManager",
	author = "Franc1sco Steam: franug, maxime1907, inGame, AntiTeal, Oylsister, .Rushaway",
	description = "Interact with console messages",
	version = "2.3.0",
	url = ""
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	DeleteTimer();
	HudSync = CreateHudSynchronizer();

	g_ConsoleMessage = CreateConVar("sm_consolechatmanager_tag", "{green}[NARRATOR] {white}", "The tag that will be printed instead of the console default messages");

	g_EnableTranslation = CreateConVar("sm_consolechatmanager_translation", "0", "Enable translation of console chat messages. 1 = Enabled, 0 = Disabled");

	g_EnableHud = CreateConVar("sm_consolechatmanager_hud", "1", "Enables printing the console output in the middle of the screen");
	g_cHudDuration = CreateConVar("sm_consolechatmanager_hud_duration", "2.5", "How long the message stays");
	g_cHudDurationFadeOut = CreateConVar("sm_consolechatmanager_hud_duration_fadeout", "1.0", "How long the message takes to disapear");
	g_cHudPosition = CreateConVar("sm_consolechatmanager_hud_position", "-1.0 0.125", "The X and Y position for the hud.");
	g_cHudColor = CreateConVar("sm_consolechatmanager_hud_color", "0 255 0", "RGB color value for the hud.");
	g_cHudMapSymbols = CreateConVar("sm_consolechatmanager_hud_mapsymbols", "1", "Eliminate the original prefix and suffix from the map text when displayed in the Hud.", _, true, 0.0, true, 1.0);
	g_cHudSymbols = CreateConVar("sm_consolechatmanager_hud_symbols", "1", "Determines whether >> and << are wrapped around the text.");
	g_cHudType = CreateConVar("sm_consolechatmanager_hud_type", "1.0", "Specify the type of Hud Msg [1 = SendTextHud, 2 = CS:GO Warmup Timer]", _, true, 1.0, true, 2.0);
	g_cHudHtmlColor = CreateConVar("sm_consolechatmanager_hud_htmlcolor", "#6CFF00", "Html color for second type of Hud Message");
	g_cvHUDChannel = CreateConVar("sm_consolechatmanager_hud_channel", "0", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 6.0);

	g_cBlockSpam = CreateConVar("sm_consolechatmanager_block_spam", "1", "Blocks console messages that repeat the same message.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cBlockSpamDelay = CreateConVar("sm_consolechatmanager_block_spam_delay", "1", "Time to wait before printing the same message", FCVAR_NONE, true, 1.0, true, 60.0);

	g_cHudPosition.AddChangeHook(OnConVarChanged);
	g_cHudColor.AddChangeHook(OnConVarChanged);
	g_cHudMapSymbols.AddChangeHook(OnConVarChanged);
	g_cHudSymbols.AddChangeHook(OnConVarChanged);
	g_cHudType.AddChangeHook(OnConVarChanged);

	AddCommandListener(SayConsole, "say");

	AutoExecConfig(true);

	GetConVars();
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
	isCSGO = (GetEngineVersion() == Engine_CSGO);
	return APLRes_Success;
}

public void OnMapStart()
{
	if (g_EnableTranslation.BoolValue)
		ReadT();
}

public void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	GetConVars();
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	roundStartedTime = GetTime();
	DeleteTimer();
}

public int GetCurrentRoundTime()
{
	Handle hFreezeTime = FindConVar("mp_freezetime"); // Freezetime Handle
	int freezeTime = GetConVarInt(hFreezeTime); // Freezetime in seconds
	return GameRules_GetProp("m_iRoundTime") - ( (GetTime() - roundStartedTime) - freezeTime );
}

public int GetRoundTimeAtTimerEnd()
{
	return GetCurrentRoundTime() - number; 
}

public void DeleteTimer()
{
	if(timerHandle != INVALID_HANDLE)
	{
		KillTimer(timerHandle);
		timerHandle = INVALID_HANDLE;
	}
}

public void GetConVars()
{
	char StringPos[2][8];
	char PosValue[16];
	g_cHudPosition.GetString(PosValue, sizeof(PosValue));
	ExplodeString(PosValue, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));

	HudPos[0] = StringToFloat(StringPos[0]);
	HudPos[1] = StringToFloat(StringPos[1]);

	char ColorValue[64];
	g_cHudColor.GetString(ColorValue, sizeof(ColorValue));

	ColorStringToArray(ColorValue, HudColor);

	HudMapSymbols = g_cHudMapSymbols.BoolValue;
	HudSymbols = g_cHudSymbols.BoolValue;

	hudtype = g_cHudType.IntValue;

	g_cHudHtmlColor.GetString(htmlcolor, sizeof(htmlcolor));
}

public void ColorStringToArray(const char[] sColorString, int aColor[3])
{
	char asColors[4][4];
	ExplodeString(sColorString, " ", asColors, sizeof(asColors), sizeof(asColors[]));

	aColor[0] = StringToInt(asColors[0]);
	aColor[1] = StringToInt(asColors[1]);
	aColor[2] = StringToInt(asColors[2]);
}

public void ReadT()
{
	delete kv;

	char map[64];
	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, Path, sizeof(Path), "configs/consolechatmanager/%s.txt", map);

	kv = CreateKeyValues("Console_C");

	if(!FileExists(Path)) KeyValuesToFile(kv, Path);
	else FileToKeyValues(kv, Path);
	
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

				Format(buffer, 255, "sound/%s", buffer);
				AddFileToDownloadsTable(buffer);
			}
			
		} while (KvGotoNextKey(kv));
	}

	KvRewind(kv);
}

public bool CheckString(const char[] string)
{
	for (int i = 0; i < sizeof(Blacklist); i++)
	{
		if(StrContains(string, Blacklist[i], false) != -1)
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
	if (CheckString(FilterText))
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
	number = consoleNumber;
	onumber = consoleNumber;
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

	if (g_cBlockSpam.BoolValue)
	{
		int currentTime = GetTime();
		if (strcmp(sText, lastMessage, true) == 0)
		{
			if (lastMessageTime != -1 && ((currentTime - lastMessageTime) <= g_cBlockSpamDelay.IntValue))
			{
				lastMessage = sText;
				lastMessageTime = currentTime;
				return Plugin_Handled;
			}
		}
		lastMessage = sText;
		lastMessageTime = currentTime;
	}

	char soundp[255], soundt[255];
	if (g_EnableTranslation.BoolValue)
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
			KeyValuesToFile(kv, Path);
			KvJumpToKey(kv, sText);
		}

		bool blocked = (KvGetNum(kv, "blocked", 0)?true:false);

		if(blocked)
		{
			KvRewind(kv);
			return Plugin_Handled;
		}

		KvGetString(kv, "sound", soundp, sizeof(soundp), "default");
		if(strcmp(soundp, "default") == 0)
			Format(soundt, 255, "common/talk.wav");
		else
			Format(soundt, 255, soundp);
	}

	char sFinalText[1024];
	char sConsoleTag[255];
	char sCountryTag[3];
	char sIP[26];
	bool isCountable = IsCountable(sText);

	g_ConsoleMessage.GetString(sConsoleTag, sizeof(sConsoleTag));

	for(int i = 1 ; i < MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if (g_EnableTranslation.BoolValue)
			{
				GetClientIP(i, sIP, sizeof(sIP));
				GeoipCode2(sIP, sCountryTag);
				KvGetString(kv, sCountryTag, sText, sizeof(sText), "LANGMISSING");

				if (strcmp(sText, "LANGMISSING") == 0) KvGetString(kv, "default", sText, sizeof(sText));
			}

			Format(sFinalText, sizeof(sFinalText), "%s%s", sConsoleTag, sText);

			if(isCountable && GetRoundTimeAtTimerEnd() > 0)
			{
				float fMinutes = GetRoundTimeAtTimerEnd() / 60.0;
				int minutes = RoundToFloor(fMinutes);
				int seconds = GetRoundTimeAtTimerEnd() - minutes * 60;
				char roundTimeText[32];

				Format(roundTimeText, sizeof(roundTimeText), " {orange}@ %i:%s%i", minutes, (seconds < 10 ? "0" : ""), seconds);
				Format(sFinalText, sizeof(sFinalText), "%s%s", sFinalText, roundTimeText);
			}

			CPrintToChat(i, sFinalText);
			PrepareHudMsg(i, sText);
		}
	}

	if (g_EnableTranslation.BoolValue)
	{
		if(strcmp(soundp, "none", false) != 0)
			EmitSoundToAll(soundt);

		if(KvJumpToKey(kv, "hinttext"))
		{
			for(int i = 1 ; i < MaxClients; i++)
				if(IsClientInGame(i))
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

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
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
	if(timerHandle != INVALID_HANDLE)
	{
		KillTimer(timerHandle);
		timerHandle = INVALID_HANDLE;
	}

	DataPack TimerPack;
	timerHandle = CreateDataTimer(1.0, RepeatMsg, TimerPack, TIMER_REPEAT);
	TimerPack.WriteString(szMessage);
}

public Action RepeatMsg(Handle timer, Handle pack)
{
	number--;
	if (number <= 0)
	{
		DeleteTimer();
		for (int i = 1; i <= MAXPLAYERS + 1; i++)
		{
			if(IsValidClient(i))
			{
				ClearSyncHud(i, HudSync);
			}
		}
		return Plugin_Handled;
	}

	char string[MAXLENGTH_INPUT + 10], sNumber[8], sONumber[8];

	ResetPack(pack);
	ReadPackString(pack, string, sizeof(string));

	IntToString(onumber, sONumber, sizeof(sONumber));
	IntToString(number, sNumber, sizeof(sNumber));

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

void RemoveDuplicatePrefixAndSuffix(char[] sBuffer, bool isRepeated = false)
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
	if (!g_EnableHud.BoolValue || !IsValidClient(client))
		return;

	if (HudMapSymbols)
		RemoveDuplicatePrefixAndSuffix(sBuffer, isRepeated);

	RemoveTextInBraces(sBuffer, true, true);

	bool containsDecimal = StringContainDecimal(sBuffer);
	bool isCountdown = !containsDecimal && IsCountable(sBuffer);

	char szMessage[MAXLENGTH_INPUT + 10];
	FormatEx(szMessage, sizeof(szMessage), "%s", sBuffer);

	if (!isRepeated && HudSymbols)
		FormatEx(szMessage, sizeof(szMessage), ">> %s <<", sBuffer);

	if (isCountdown)
		InitCountDown(szMessage);

	if (isCSGO && hudtype == NORMALHUD)
		SendCSGO_HudMsg(client, szMessage, isCountdown);
	else
		SendHudMsg(client, szMessage, isCountdown);
}

stock void SendHudMsg(int client, const char[] szMessage, bool isCountdown)
{
	if (!IsValidClient(client))
		return;

	float duration = isCountdown ? 1.0 : g_cHudDuration.FloatValue;
	SetHudTextParams(HudPos[0], HudPos[1], duration, HudColor[0], HudColor[1], HudColor[2], 255, 0, 0.0, 0.0, g_cHudDurationFadeOut.FloatValue);

	bool bDynamicAvailable = false;
	int iHUDChannel = -1;

	int iChannel = g_cvHUDChannel.IntValue;
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
		ClearSyncHud(client, HudSync);
		ShowSyncHudText(client, HudSync, szMessage);
	}
}

stock void SendCSGO_HudMsg(int client, const char[] szMessage, bool isCountdown)
{
	if (!isCSGO || !IsValidClient(client))
		return;

	// Event use int for duration
	int duration = isCountdown ? 2 : RoundToNearest(g_cHudDuration.FloatValue);

	// We don't want to mess with original constant char
	char originalmsg[MAX_BUFFER_LENGTH + 10];
	Format(originalmsg, sizeof(originalmsg), "%s", szMessage);

	int orilen = strlen(originalmsg);

	// Need to remove These Html symbol from console message and replace with new html symbol.
	ReplaceString(originalmsg, orilen, "<", "&lt;", false);
	ReplaceString(originalmsg, orilen, ">", "&gt;", false);

	// Put color in to the message
	char newmessage[MAX_BUFFER_LENGTH + 10];
	int newlen = strlen(newmessage);

	// If the message is too long we need to reduce font size.
	if(newlen <= 65)
		// Put color in to the message (These html format is fine)
		Format(newmessage, sizeof(newmessage), "<span class='fontSize-l'><span color='%s'>%s</span></span>", htmlcolor, originalmsg);
	else if(newlen <= 100)
		Format(newmessage, sizeof(newmessage), "<span class='fontSize-m'><span color='%s'>%s</span></span>", htmlcolor, originalmsg);
	else
		Format(newmessage, sizeof(newmessage), "<span class='fontSize-sm'><span color='%s'>%s</span></span>", htmlcolor, originalmsg);

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
				if(IsClientInGame(i) && !IsFakeClient(i))
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
