/*+===================================================================
  File:    GLOBALS.INC

  Summary: This file contains global variables used by the bot
           control plugin.

  Origin:  Created by Bintr on 13.06.2026.
===================================================================+*/

#if defined _botcontrol_globals_included
    #endinput
#endif
#define _botcontrol_globals_included

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include "const"

PLAYERATTRIBUTES g_aPlayerAttribs[ MAXPLAYERS_ARRAY_SAFE ];
BOTATTRIBUTES    g_aBotAttribs[ MAXPLAYERS_ARRAY_SAFE ];

ConVar sm_botcontrol_premium_flags;
ConVar sm_botcontrol_groupid;

Handle g_hSyncObj;

int g_nDeployingBombState_Offset;
