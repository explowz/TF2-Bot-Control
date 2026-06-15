/*+===================================================================
  File:    CONST.INC

  Summary: This file contains constants used by the bot control
           plugin.

  Origin:  Created by Bintr on 12.06.2026.
===================================================================+*/

#if defined _botcontrol_const_included
    #endinput
#endif
#define _botcontrol_const_included

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <tf2>

#define FLT_MAX 3.402823466e38

#define MAXPLAYERS_ARRAY_SAFE   ( MAXPLAYERS + 1 )

#define TF_TEAM_PVE_INVADERS    TFTeam_Blue // invading bot team in mann vs machine
#define TF_TEAM_PVE_DEFENDERS   TFTeam_Red  // defending player team in mann vs machine

//
// Max size (in bytes of UTF-8 data, not in characters) of server fields, including null terminator.
//
const int k_cbMaxGameServerGameDir         = 32;
const int k_cbMaxGameServerMapName         = 32;
const int k_cbMaxGameServerGameDescription = 64;
const int k_cbMaxGameServerName            = 64;
const int k_cbMaxGameServerTags            = 128;
const int k_cbMaxGameServerGameData        = 2048;

enum struct PLAYERATTRIBUTES
{
    int  iBotSerial;
    bool bIsGroupMember;

    bool IsControlling()
    {
        return this.iBotSerial != 0;
    }
}

enum struct BOTATTRIBUTES
{
    int iPlayerSerial;

    bool IsControlled()
    {
        return this.iPlayerSerial != 0;
    }
}

enum BombDeployingState_t
{
    TF_BOMB_DEPLOYING_NONE,
    TF_BOMB_DEPLOYING_DELAY,
    TF_BOMB_DEPLOYING_ANIMATING,
    TF_BOMB_DEPLOYING_COMPLETE,

    TF_BOMB_DEPLOYING_NOT_COUNT
}

// Spectator Movement modes
enum
{
    OBS_MODE_NONE = 0,  // not in spectator mode
    OBS_MODE_DEATHCAM,  // special mode for death cam animation
    OBS_MODE_FREEZECAM, // zooms to a target, and freeze-frames on them
    OBS_MODE_FIXED,     // view from a fixed camera position
    OBS_MODE_IN_EYE,    // follow a player in first person view
    OBS_MODE_CHASE,     // follow a player in third person view
    OBS_MODE_POI,       // PASSTIME point of interest - game objective, big fight, anything interesting; added in the middle of the enum due to tons of hard-coded "<ROAMING" enum compares
    OBS_MODE_ROAMING,   // free roaming

    NUM_OBSERVER_MODES
}
