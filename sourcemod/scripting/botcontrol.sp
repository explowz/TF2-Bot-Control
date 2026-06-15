/*+===================================================================
  File:    BOTCONTROL.SP

  Summary: This plugin allows players to take control of robots
           in the Mann vs. Machine gamemode.

  Origin:  Created by Bintr on 12.06.2026.
===================================================================+*/

#if !defined _DEBUG
    #define LOG_SERVER_DISABLE
#endif

#include <sourcemod>
#include <testing>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <SteamWorks>
#include <pluginstatemanager>
#include <stocksoup/string>
#include <stocksoup/log_server>
#include <stocksoup/convars>
#include <stocksoup/tf/voice_hook>
#include <stocksoup/tf/entity_prop_stocks>

#include <botcontrol/const>
#include <botcontrol/globals>
#include <botcontrol/stocks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name        = "[TF2] MvM Bot Control",
    author      = "Bintr",
    description = "Allows players to take control of a robot in the Mann vs. Machine gamemode.",
    version     = "0.1",
    url         = "https://github.com/explowz/TF2-Bot-Control"
};

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginStart

  Summary:  Called when the plugin is fully initialized and all
            known external references are resolved. This is only
            called once in the lifetime of the plugin, and is
            paired with OnPluginEnd().

            If any run-time error is thrown during this callback,
            the plugin will be marked as failed.

            This function initializes all of our console variables,
            global variables, and more.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginStart()
{
    if ( GetEngineVersion() != Engine_TF2 )
    {
        SetFailState( "This plugin only works for the game Team Fotress 2." );
    }

    CreateVersionConVar( "sm_botcontrol_version", "[TF2] MvM Bot Control version" );

    GameData Conf = new GameData( "botcontrol" );
    if ( !Conf )
    {
        SetFailState( "Could not find gamedata file \"botcontrol.txt\"." );
    }

    PSM_Init( "sm_botcontrol_enabled", Conf );
    PSM_AddShouldEnableCallback( IsMannVsMachineMode );
    PSM_AddPluginStateChangedHook( SetGameDescription );

    sm_botcontrol_premium_flags = CreateConVar(
                                                "sm_botcontrol_premium_flags",
                                                "o",
                                                "The required flags a player should have to be considered a premium player. " ...
                                                    "For more information, please refer to admin_levels.cfg."
                                              );
    sm_botcontrol_groupid       = CreateConVar(
                                                "sm_botcontrol_groupid",
                                                "571",
                                                "The groupID32 of the group the user must be a member of to control bots with the \"group\" attribute.",
                                                _,
                                                true
                                              );

    RegisterVoiceCommandCallback( Voice_Medic, PlayerControlBot );
    PSM_AddCommandListener( VoiceMenuListener, "voicemenu" );

    // HUD messages are taken care of in `OnPlayerRunCmdPost`
    g_hSyncObj = CreateHudSynchronizer();

    g_nDeployingBombState_Offset = Conf.GetOffset( "CTFPlayer::m_nDeployingBombState" );

    // Request our clients' group affiliation status every 30 seconds
    CreateTimer( 30.0, UpdateUsersGroupStatus, _, TIMER_REPEAT );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnConfigsExecuted

  Summary:  Called when the map has loaded, servercfgfile (server.cfg)
            has been executed, and all plugin configs are done
            executing. This is the best place to initialize plugin
            functions which are based on cvar data.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnConfigsExecuted()
{
    PSM_TogglePluginState();
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginEnd

  Summary:  Called when the plugin is about to be unloaded.

            It is not necessary to close any handles or remove
            hooks in this function. SourceMod guarantees that
            plugin shutdown automatically and correctly releases
            all resources.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginEnd()
{
    PSM_SetPluginState( false );

    // Make sure we don't leave any HUD text on clients' screens
    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame( i ) && !IsFakeClient( i ) )
        {
            ClearSyncHud( i, g_hSyncObj );
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SteamWorks_OnClientGroupStatus

  Summary:  This callback function is called by the
            `RequestUserGroupStatus` Steamworks function
            (`SteamWorks_GetUserGroupStatus` and
            `SteamWorks_GetUserGroupStatusAuthID` in our case)
            and contains the result of the user's group status.

  Args:     int iAuthId
              The Steam account ID of the user for which the group
              status was requested.
            int iGroupId
              The group ID for which `iAuthId`'s group status was
              requested.
            bool bIsMember
              This parameter will be `true` if the user with Steam
              ID `iAuthId` is a member of the group with group ID
              `iGroupId`. Otherwise, this parameter will be `false`.
            bool bIsOfficer
              This parameter will be `true` if the user with Steam
              ID `iAuthId` is a group officer of the group with
              group ID `iGroupId`. Otherwise, this parameter will
              be `false`.
              Note: This parameter cannot be `true` if `bIsMember`
              is `false`.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void SteamWorks_OnClientGroupStatus( int iAuthId, int iGroupId, bool bIsMember, bool bIsOfficer )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( iGroupId != sm_botcontrol_groupid.IntValue )
    {
        // Not the group we care about
        return;
    }

    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( !IsClientConnected( i ) )
        {
            continue;
        }

        if ( GetSteamAccountID( i ) == iAuthId )
        {
            LogServer( "Received group status response for %L. bIsMember = %d", i, bIsMember );
            g_aPlayerAttribs[ i ].bIsGroupMember = bIsMember;
            return;
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: UpdateUsersGroupStatus

  Summary:  This function initiates a group status update for all
            players connected to the server. The status is returned
            in the `SteamWorks_OnClientGroupStatus` callback function.

  Args:     Handle hTimer
              A handle to the timer that called this function. If
              the function was not called by a timer, this value
              will be `null`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void UpdateUsersGroupStatus( Handle hTimer )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( !IsServerProcessing() )
    {
        return;
    }

    LogServer( "Initiating a group status update..." );

    if ( !SteamWorks_IsConnected() )
    {
        LogMessage( "Could not initiate a group status update. The server is not connected to Steam." );
        return;
    }

    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientConnected( i ) && !IsFakeClient( i ) )
        {
            if ( !SteamWorks_GetUserGroupStatus( i, sm_botcontrol_groupid.IntValue ) )
            {
                LogError( "Failed to request group status for user %L. Please make sure the group ID is valid.", i );
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPlayerRunCmdPost

  Summary:  Called after a clients movement buttons were processed.

            This function shows our HUD messages realted to taking
            control of a bot to clients spectating an invaing bot.

  Args:     int iClient
              Client index.
            int iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int iImpulse
              The current impulse command.
            const float vecVelocity[ 3 ]
              Player's velocity.
            const float angEyeAngles[ 3 ]
              Player's view angles.
            int iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int iSubtype
              Weapon subtype when selected from a menu.
            int iCmdNum
              Command number. Increments from the first command sent.
            int iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            const int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPlayerRunCmdPost(
    int         iClient,
    int         iButtons,
    int         iImpulse,
    const float vecVelocity[ 3 ],
    const float angEyeAngles[ 3 ],
    int         iWeapon,
    int         iSubtype,
    int         iCmdNum,
    int         iTickCount,
    int         iSeed,
    const int   posMouse[ 2 ]
    )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( IsFakeClient( iClient ) )
    {
        // Bots can't control other bots
        return;
    }

    if ( TF2_GetClientTeam( iClient ) != TFTeam_Spectator )
    {
        /*--------------------------------------------------------------------
          A player must choose the bot they wish to take control of by
          spectating them.
        --------------------------------------------------------------------*/
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( GameRules_GetRoundState() != RoundState_RoundRunning )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
    if ( iObserverMode != OBS_MODE_IN_EYE && iObserverMode != OBS_MODE_CHASE )
    {
        /*--------------------------------------------------------------------
          Only allow a player to control a bot if they're specifically
          spectating it, not just free roaming around the map.
        --------------------------------------------------------------------*/
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    static int c_iPrevObserverTargetSerial = 0;
    int        iObserverTarget             = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

    /*--------------------------------------------------------------------
      This check is needed because NextBots such as skeletons and
      Merasmus are also fake clients, but do not inherit `CTFPlayer`.
    --------------------------------------------------------------------*/
    if ( !IsPlayerIndex( iObserverTarget ) )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( !IsFakeClient( iObserverTarget ) )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_GetClientTeam( iObserverTarget ) != TF_TEAM_PVE_INVADERS )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( !IsPlayerAlive( iObserverTarget ) )
    {
        c_iPrevObserverTargetSerial = 0;    // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
    {
        c_iPrevObserverTargetSerial = 0;    // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Charging ) )
    {
        /*--------------------------------------------------------------------
          Disallow taking control of a bot while it's charging, so we don't
          have to implement logic to force a charge with a non-full charge
          meter.
        --------------------------------------------------------------------*/
        c_iPrevObserverTargetSerial = 0;    // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    // TODO: Allow players to take control over stunned bots
    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) )
    {
        /*--------------------------------------------------------------------
          For now just disallow taking control of stunned bots. Making this
          work correctly is a bit of a hassle. We'll just do it sometime in
          the future.
        --------------------------------------------------------------------*/
        c_iPrevObserverTargetSerial = 0;    // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( GetDeployingBombState( iObserverTarget ) != TF_BOMB_DEPLOYING_NONE )
    {
        c_iPrevObserverTargetSerial = 0;    // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    // Don't continuously redraw the HUD message if the target hasn't changed
    int iObserverTargetSerial = GetClientSerial( iObserverTarget );
    if ( iObserverTargetSerial == c_iPrevObserverTargetSerial )
    {
        return;
    }
    c_iPrevObserverTargetSerial = iObserverTargetSerial;

    // Shove it in the middle-ish of their screens
    SetHudTextParams( -1.0, 0.4, FLT_MAX, 255, 255, 0, 255 );

    // Check if the bot has any custom description set
    Address pCustomDesc = TF2Attrib_GetByName( iObserverTarget, "custom desc attr" );
    if ( pCustomDesc )
    {
        char szDesc[ 8 ] = "";
        TF2Attrib_UnsafeGetStringValue( TF2Attrib_GetValue( pCustomDesc ), szDesc, sizeof( szDesc ) );

        if ( StrEqual( szDesc, "block", false ) )
        {
            // Players can't control this bot
            ShowSyncHudText( iClient, g_hSyncObj, "This bot is blocked" );
            return;
        }
        else if ( StrEqual( szDesc, "premium", false ) )
        {
            char szFlags[ 32 ];
            sm_botcontrol_premium_flags.GetString( szFlags, sizeof( szFlags ) );
            if ( !( GetUserFlagBits( iClient ) & ReadFlagString( szFlags ) ) )
            {
                // Only players with the required flag(s) can control this bot
                ShowSyncHudText( iClient, g_hSyncObj, "This bot is premium-only" );
                return;
            }
        }
        else if ( StrEqual( szDesc, "group", false ) )
        {
            if ( !g_aPlayerAttribs[ iClient ].bIsGroupMember )
            {
                // Only players that are members of the Steam group can control this bot
                ShowSyncHudText( iClient, g_hSyncObj, "This bot is for group members only" );
                return;
            }
        }
    }

    ShowSyncHudText( iClient, g_hSyncObj, "Call for a MEDIC! to control this bot" );
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: PlayerControlBot

  Summary:  This callback function is called every time a player
            calls for a medic. If the player is a spectator, and
            their observer target is a bot, it shelves the bot and
            spawns the client with the index `iClient` into the
            exact state the bot was, exactly mirroring its position,
            weapons, conditions, etc.

  Args:     int iClient
              Client index of the client that called for a medic.
            TFVoiceCommand eVoiceCommand
              The type of voice command. In the case of this callback,
              this parameter will always be `Voice_Medic`.

  Returns:  Action
              `Plugin_Continue` to continue the forward calls,
              `Plugin_Handled` to stop the calling chain,
              `Plugin_Stop` to block the voice command.
-----------------------------------------------------------------F-F*/
Action PlayerControlBot( int iClient, TFVoiceCommand eVoiceCommand )
{
#if defined _DEBUG
    SetTestContext( "PlayerControlBot" );
#endif

#if defined _DEBUG
    AssertFalse( "IsFakeClient( iClient )", IsFakeClient( iClient ) );
#endif

    if ( !IsPlayerIndex( iClient ) )
    {
        /*--------------------------------------------------------------------
          The server should never execute "voicemenu" as it doens't do
          anything, but let's avoid a crash.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    if ( !IsClientInGame( iClient ) )
    {
        /*--------------------------------------------------------------------
          Again, clients not yet in the game have no reason to execute
          "voicemenu", but we guard against this too.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    /*--------------------------------------------------------------------
      A player must choose the bot they wish to take control of by
      spectating them.
    --------------------------------------------------------------------*/
    if ( TF2_GetClientTeam( iClient ) != TFTeam_Spectator )
    {
        return Plugin_Continue;
    }

    if ( GameRules_GetRoundState() != RoundState_RoundRunning )
    {
        return Plugin_Continue;
    }

    int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
    if ( iObserverMode != OBS_MODE_IN_EYE && iObserverMode != OBS_MODE_CHASE )
    {
        /*--------------------------------------------------------------------
          Only allow a player to control a bot if they're specifically
          spectating it, not just free roaming around the map.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    int iObserverTarget = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

    /*--------------------------------------------------------------------
      This check is needed because NextBots such as skeletons and
      Merasmus are also fake clients, but do not inherit `CTFPlayer`.
    --------------------------------------------------------------------*/
    if ( !IsPlayerIndex( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

#if defined _DEBUG
    AssertTrue( "IsClientInGame( iObserverTarget )", IsClientInGame( iObserverTarget ) );
#endif

    if ( !IsFakeClient( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

    if ( TF2_GetClientTeam( iObserverTarget ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Continue;
    }

    if ( !IsPlayerAlive( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
    {
        PrintHintText( iClient, "Please wait until the bot finishes taunting." );
        return Plugin_Continue;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Charging ) )
    {
        /*--------------------------------------------------------------------
          Disallow taking control of a bot while it's charging so we don't
          have to implement logic to force a charge with a non-full charge
          meter.
        --------------------------------------------------------------------*/
        PrintHintText( iClient, "Please wait until the bot finishes charging." );
        return Plugin_Continue;
    }

    // TODO: Allow players to take control of stunned bots
    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) )
    {
        /*--------------------------------------------------------------------
          For now just disallow taking control of stunned bots. Making this
          work correctly is a bit of a hassle. We'll just do it sometime in
          the future.
        --------------------------------------------------------------------*/
        PrintHintText( iClient, "Please wait until the bot is no longer stunned." );
        return Plugin_Continue;
    }

    if ( GetDeployingBombState( iObserverTarget ) != TF_BOMB_DEPLOYING_NONE )
    {
        return Plugin_Continue;
    }

    // Check if the bot has any custom description set
    Address pCustomDesc = TF2Attrib_GetByName( iObserverTarget, "custom desc attr" );
    if ( pCustomDesc )
    {
        char szDesc[ 8 ] = "";
        TF2Attrib_UnsafeGetStringValue( TF2Attrib_GetValue( pCustomDesc ), szDesc, sizeof( szDesc ) );

        if ( StrEqual( szDesc, "block", false ) )
        {
            // Players can't control this bot
            return Plugin_Continue;
        }
        else if ( StrEqual( szDesc, "premium", false ) )
        {
            char szFlags[ 32 ];
            sm_botcontrol_premium_flags.GetString( szFlags, sizeof( szFlags ) );
            if ( !( GetUserFlagBits( iClient ) & ReadFlagString( szFlags ) ) )
            {
                // Only players with the required flag(s) can control this bot
                return Plugin_Continue;
            }
        }
        else if ( StrEqual( szDesc, "group", false ) )
        {
            if ( !g_aPlayerAttribs[ iClient ].bIsGroupMember )
            {
                // Only players that are members of the group can control this bot
                return Plugin_Continue;
            }
        }
    }

    // TODO: Add the logic which actually mirrors the bot

    return Plugin_Handled;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: SetGameDescription

  Summary:  This function is called every time the plugin's state
            is changed. Based on `bEnabled`, it changes the game
            description to either our custom one or the original one.

  Args:     bool bEnabled
              If the plugin was enabled, this variable will be `true`.
              If the plugin was disabled, this variable will be `false`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void SetGameDescription( bool bEnabled )
{
    if ( bEnabled )
    {
        SteamWorks_SetGameDescription( ":: Bot Control ::" );
    }
    else
    {
        char szDescription[ k_cbMaxGameServerGameDescription ];
        GetGameDescription( szDescription, sizeof( szDescription ), true );
        SteamWorks_SetGameDescription( szDescription );
    }
}
