/*+===================================================================
  File:    DYNAMICDETOURS.INC

  Summary: This file contains dynamic detour callback functions used
           by the bot control plugin.

  Origin:  Created by Bintr on 18.06.2026.
===================================================================+*/

#if defined _botcontrol_dynamicdetours_included
    #endinput
#endif
#define _botcontrol_dynamicdetours_included

#include <sourcemod>
#include <dhooks>
#include <tf2>

#include "globals"
#include "const"
#include "stocks"

#pragma newdecls required
#pragma semicolon 1

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_CanBuild_Pre

  Summary:  This function is called before every
            `CTFPlayer::CanBuild` call and its main purpose is to
            block human invaders from building teleporter entrances.

            Original function signature:
            `int CTFPlayer::CanBuild( int iObjectType, int iObjectMode )`

  Args:     int iThis
              Calling client index.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_CanBuild_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() )
    {
        TFObjectType iObjectType = hParams.Get( 1 );
        if ( iObjectType == TFObject_Teleporter  )
        {
            TFObjectMode iObjectMode = hParams.Get( 2 );
            if ( iObjectMode == TFObjectMode_Entrance )
            {
                // Invader engineers don't build teleporter entrances
                hReturn.Value = CB_CANNOT_BUILD;
                return MRES_Supercede;
            }
            else if ( iObjectMode == TFObjectMode_Exit )
            {
                /*--------------------------------------------------------------------
                  Invader engineers only build teleporter exits if `TeleportWhere`
                  is set and the map has at least one active teleporter exit hint
                  entity.
                --------------------------------------------------------------------*/
                int iBot = GetClientFromSerial( g_aPlayerAttribs[ iThis ].iBotSerial );
                if ( CTFBot_GetTeleportWhereCount( iBot ) == 0 || !FindHint( false, true ) )
                {
                    hReturn.Value = CB_CANNOT_BUILD;
                    return MRES_Supercede;
                }
            }
        }
        else if ( iObjectType == TFObject_Sapper )
        {
            // Invader spies can build as many sappers as they want
            hReturn.Value = CB_CAN_BUILD;
            return MRES_Supercede;
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_HandleCommand_JoinTeam_Pre

  Summary:  This function is called before every
            `CTFPlayer::HandleCommand_JoinTeam` call and its purpose
            is to restore the controlled bot and block direct team
            switches from the invading team to the defending team.

            Original function signature:
            `void CTFPlayer::HandleCommand_JoinTeam( const char *pTeamName )`

  Args:     int iThis
              Calling client index.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_HandleCommand_JoinTeam_Pre( int iThis, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() )
    {
        /*--------------------------------------------------------------------
          `CTFPlayer::HandleCommand_JoinTeam` forces the player to commit
          suicide before changing teams, meaning that the "player_team"
          event gets fired after the player is already dead. Therefore,
          we restore the bot in here.
        --------------------------------------------------------------------*/
        RestoreBot( iThis );

        return MRES_Supercede;
    }

    // BUGBUG: What do we do if the controlled bot's class was changed?

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTraceFilterObject_ShouldHitEntity_Pre

  Summary:  This function is called before every
            `CTraceFilterObject::ShouldHitEntity` call and its purpose
            is to disallow sentry busters to be bodyblocked.

            Original function signature:
            `bool CTraceFilterObject::ShouldHitEntity( IHandleEntity *pHandleEntity, int contentsMask )`

  Args:     Address pThis
              Memory address of calling `CTraceFilterObject` object.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTraceFilterObject_ShouldHitEntity_Pre( Address pThis, DHookReturn hReturn, DHookParam hParams )
{
    int iMe     = GetEntityFromAddress( GetPassEntity( pThis ) );
    int iEntity = GetEntityFromAddress( hParams.Get( 1 ) );

    if ( IsPlayerIndex( iEntity ) )
    {
        int iBot;

        if ( g_aPlayerAttribs[ iEntity ].IsControlling() )
        {
            iBot = GetClientFromSerial( g_aPlayerAttribs[ iEntity ].iBotSerial );
            if ( GetPrevMission( iBot ) == MISSION_DESTROY_SENTRIES )
            {
                // Don't collide with sentry busters since they don't collide with us
                hReturn.Value = false;
                return MRES_Supercede;
            }
        }

        if ( g_aPlayerAttribs[ iMe ].IsControlling() )
        {
            iBot = GetClientFromSerial( g_aPlayerAttribs[ iMe ].iBotSerial );
            if ( GetPrevMission( iBot ) == MISSION_DESTROY_SENTRIES )
            {
                // Sentry Busters don't collide with enemies (so they can't be body-blocked)
                hReturn.Value = false;
                return MRES_Supercede;
            }
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayerShared_OnConditionAdded_Pre

  Summary:  This function is called before every
            `CTFPlayerShared::OnConditionAdded` call and its purpose
            is fake the player's bot status so that the game stuns
            them when `TFCond_MVMBotRadiowave` is applied.

            Original function signature:
            `void CTFPlayerShared::OnConditionAdded( ETFCond eCond )`

  Args:     Address pThis
              Memory address of `CTFPlayerShared` object.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayerShared_OnConditionAdded_Pre( Address pThis, DHookParam hParams )
{
    int iPlayer = TF2Util_GetPlayerFromSharedAddress( pThis );

    if ( g_aPlayerAttribs[ iPlayer ].IsControlling() && view_as< TFCond >( hParams.Get( 1 ) ) == TFCond_MVMBotRadiowave )
    {
        FakeBotStatus( iPlayer );
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayerShared_OnConditionAdded_Post

  Summary:  This function is called after every
            `CTFPlayerShared::OnConditionAdded` call and its purpose
            is to restore a human invader's player status after
            `TFCond_MVMBotRadiowave` was applied.

            Original function signature:
            `void CTFPlayerShared::OnConditionAdded( ETFCond eCond )`

  Args:     Address pThis
              Memory address of `CTFPlayerShared` object.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayerShared_OnConditionAdded_Post( Address pThis, DHookParam hParams )
{
    int iPlayer = TF2Util_GetPlayerFromSharedAddress( pThis );

    if ( g_aPlayerAttribs[ iPlayer ].IsControlling() && view_as< TFCond >( hParams.Get( 1 ) ) == TFCond_MVMBotRadiowave )
    {
        RestorePlayerStatus( iPlayer );
    }

    return MRES_Ignored;
}

// static float g_flPrevIntervalTo1stUpgrade;

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBotDeliverFlag_OnStart_Pre

  Summary:  This function is called before every
            `CTFBotDeliverFlag::OnStart` call and its purpose is to
            synchronize the class's `m_upgradeTimer` member
            variable with the next bomb upgrade time.

            Original function signature:
            `ActionResult< CTFBot > CTFBotDeliverFlag::OnStart( CTFBot *me, Action< CTFBot > *priorAction )`

  Args:     Address pThis
              Address of the calling `CTFBotDeliverFlag` class.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
// MRESReturn CTFBotDeliverFlag_OnStart_Pre( Address pThis, DHookReturn hReturn, DHookParam hParams )
// {
//     int iBot = hParams.Get( 1 );

//     /*--------------------------------------------------------------------
//       If the bot just started delivering the flag and it has
//       `bBlockFlagEvent` set, then this is the bot that got restored.
//     --------------------------------------------------------------------*/
//     if ( g_aBotAttribs[ iBot ].bBlockFlagEvent && !IsMiniBoss( iBot ) )
//     {
//         // Save the original value so we can restore it in the post hook
//         g_flPrevIntervalTo1stUpgrade = tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.FloatValue;

//         // Make `m_upgradeTimer` sychronize with the next upgrade time
//         tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.SetFloat( max( GetNextMvMBombUpgradeTime() - GetGameTime(), 0.0 ) );
//     }

//     return MRES_Ignored;
// }

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBotDeliverFlag_OnStart_Post

  Summary:  This function is called after every
            `CTFBotDeliverFlag::OnStart` call and its purpose is to
            synchronize the class's `m_upgradeLevel` member
            variable with current flag carrier upgrade level and
            restore the value of the `tf_mvm_bot_flag_carrier_interval_to_1st_upgrade`
            console variable.

            Original function signature:
            `ActionResult< CTFBot > CTFBotDeliverFlag::OnStart( CTFBot *me, Action< CTFBot > *priorAction )`

  Args:     Address pThis
              Address of the calling `CTFBotDeliverFlag` class.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
/*MRESReturn CTFBotDeliverFlag_OnStart_Post( Address pThis, DHookReturn hReturn, DHookParam hParams )
{
    int iBot = hParams.Get( 1 );
    if ( g_aBotAttribs[ iBot ].bBlockFlagEvent && !IsMiniBoss( iBot ) )
    {
        // Copy over the upgrade level
        StoreToAddress( pThis + view_as< Address >( g_CTFBotDeliverFlag_upgradeLevel_Offset ), GetFlagCarrierUpgradeLevel(), NumberType_Int32 );

        // Restore the value to whatever it was before we changed it
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.SetFloat( g_flPrevIntervalTo1stUpgrade );
    }

    return MRES_Ignored;
}*/
