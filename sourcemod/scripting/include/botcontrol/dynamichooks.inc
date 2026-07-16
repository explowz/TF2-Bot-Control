/*+===================================================================
  File:    DYNAMICHOOKS.INC

  Summary: This file contains dynamic hook callback functions used
           by the bot control plugin.

  Origin:  Created by Bintr on 15.06.2026.
===================================================================+*/

#if defined _botcontrol_dynamichooks_included
    #endinput
#endif
#define _botcontrol_dynamichooks_included

#include <sourcemod>
#include <dhooks>
#include <sdktools>
#include <stocksoup/log_server>

#include "globals"
#include "const"
#include "stocks"

#pragma newdecls required
#pragma semicolon 1

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CBasePlayer_GetBotType_Pre

  Summary:  This function is called before every
            `CBasePlayer::GetBotType` call on a hooked entity and
            fakes its bot type.

            Original function signature:
            `int CBasePlayer::GetBotType( void )`

  Args:     int iThis
              Calling client index.
            DHookReturn hReturn
              Handle to the return value.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CBasePlayer_GetBotType_Pre( int iThis, DHookReturn hReturn )
{
    hReturn.Value = TF_BOT_TYPE;
    return MRES_Supercede;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_StartBuilding_Pre

  Summary:  This function is called before every
            `CObjectTeleporter::StartBuilding` call on a hooked
            entity and replicates the behavior of an MvM engineer
            bot when building its teleporter exit.

            Original function signature:
            `bool CObjectTeleporter::StartBuilding( CBaseEntity *pBuilder )`

  Args:     int iThis
              Index of calling `CObjectTeleporter` entity.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CObjectTeleporter_StartBuilding_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( !hParams.IsNull( 1 ) )
    {
        /*--------------------------------------------------------------------
          Because we block building teleporter entrances there's no need to
          check for the object mode.
        --------------------------------------------------------------------*/
        int iBuilder = hParams.Get( 1 );
        if ( g_aPlayerAttribs[ iBuilder ].IsControlling() )
        {
            int iBot = GetClientFromSerial( g_aPlayerAttribs[ iBuilder ].iBotSerial );

            CObjectTeleporter_SetTeleportWhere( iThis, CTFBot_GetTeleportWhere( iBot ) );

            if ( CTFBot_ShouldQuickBuild( iBot ) )
            {
                ForceQuickBuild( iThis );
            }
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_StartBuilding_Pre

  Summary:  This function is called after every
            `CObjectTeleporter::StartBuilding` call on a hooked
            entity and replicates the behavior of an MvM engineer
            bot when building its teleporter exit.

            Original function signature:
            `bool CObjectTeleporter::StartBuilding( CBaseEntity *pBuilder )`

  Args:     int iThis
              Index of calling `CObjectTeleporter` entity.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CObjectTeleporter_StartBuilding_Post( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( !hParams.IsNull( 1 ) )
    {
        /*--------------------------------------------------------------------
          Because we block building teleporter entrances there's no need to
          check for the object mode.
        --------------------------------------------------------------------*/
        int iBuilder = hParams.Get( 1 );
        if ( g_aPlayerAttribs[ iBuilder ].IsControlling() )
        {
            /*--------------------------------------------------------------------
              The game assigns a `float` value to an `int` variable, so to
              replicate the behavior we need to truncate, not round to nearest.
            --------------------------------------------------------------------*/
            int iHealth = RoundToZero( GetMaxHealthForCurrentLevel( iThis ) * tf_bot_engineer_mvm_building_health_multiplier.FloatValue );
            SetEntProp( iThis, Prop_Data, "m_iMaxHealth", iHealth );
            SetEntityHealth( iThis, iHealth );

            EmitGameSoundToAll( "Engineer.MVM_AutoBuildingTeleporter02", iBuilder );
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_FinishedBuilding_Post

  Summary:  This function is called after every
            `CObjectTeleporter::FinishedBuilding` call on a hooked
            entity and replicates the behavior of an MvM engineer
            bot when building its teleporter exit.

            Original function signature:
            `void CObjectTeleporter::FinishedBuilding( void )`

  Args:     int iThis
              Index of calling `CObjectTeleporter` entity.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CObjectTeleporter_FinishedBuilding_Post( int iThis )
{
    int iBuilder = TF2_GetObjectBuilder( iThis );
    if ( iBuilder != -1 && g_aPlayerAttribs[ iBuilder ].IsControlling() )
    {
        int iParticleSystem = CreateEntityByName( "info_particle_system" );

        DispatchKeyValueBool( iParticleSystem, "start_active", true );
        DispatchKeyValue( iParticleSystem, "effect_name", "teleporter_mvm_bot_persist" );
        DispatchSpawn( iParticleSystem );

        float vecOrigin[ 3 ];
        GetEntPropVector( iThis, Prop_Send, "m_vecOrigin", vecOrigin );
        TeleportEntity( iParticleSystem, vecOrigin );

        SetVariantString( "!activator" );
        AcceptEntityInput( iParticleSystem, "SetParent", iThis );

        ActivateEntity( iParticleSystem );
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectSentrygun_StartBuilding_Pre

  Summary:  This function is called before every
            `CObjectSentrygun::StartBuilding` call on a hooked
            entity and replicates the behavior of an MvM engineer
            bot when building its sentrygun.

            Original function signature:
            `bool CObjectSentrygun::StartBuilding( CBaseEntity *pBuilder )`

  Args:     int iThis
              Index of calling `CObjectSentrygun` entity.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CObjectSentrygun_StartBuilding_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( !hParams.IsNull( 1 ) )
    {
        int iBuilder = hParams.Get( 1 );
        if ( g_aPlayerAttribs[ iBuilder ].IsControlling() )
        {
            DispatchKeyValueInt( iThis, "defaultupgrade", 2 );
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CFilterTFBotHasTag_PassesFilterImpl_Pre

  Summary:  This function is called before every
            `CFilterTFBotHasTag::PassesFilterImpl` call on a
            hooked entity and its purpose is to replace the tested
            entity with the its controlled bot.

            Original function signature:
            `bool CFilterTFBotHasTag::PassesFilterImpl( CBaseEntity *pCaller, CBaseEntity *pEntity )`

  Args:     int iThis
              Index of calling entity.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CFilterTFBotHasTag_PassesFilterImpl_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( !hParams.IsNull( 2 ) )
    {
        int iEntity = hParams.Get( 2 );
        if ( IsPlayerIndex( iEntity ) && g_aPlayerAttribs[ iEntity ].IsControlling() )
        {
            // Ask the function to test our bot instead of us
            hParams.Set( 2, GetClientFromSerial( g_aPlayerAttribs[ iEntity ].iBotSerial ) );
            return MRES_ChangedHandled;
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_ShouldTransmit_Pre

  Summary:  This function is called before every
            `CTFPlayer::ShouldTransmit` call on a hooked entity and
            its purpose is to mimic bot transmit logic.

            Original function signature:
            `int	CTFPlayer::ShouldTransmit( const CCheckTransmitInfo *pInfo )`

  Args:     int iThis
              Calling client index.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_ShouldTransmit_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() && GetEntProp( iThis, Prop_Send, "m_bUseBossHealthBar" ) )
    {
        hReturn.Value = FL_EDICT_ALWAYS;
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_ShouldGib_Pre

  Summary:  This function is called before every
            `CTFPlayer::ShouldGib` call on a hooked entity and its
            purpose is to mimic bot gibbing logic.

            Original function signature:
            `bool CTFPlayer::ShouldGib( const CTakeDamageInfo &info )`

  Args:     int iThis
              Calling client index.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_ShouldGib_Pre( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() && ( IsMiniBoss( iThis ) || GetModelScale( iThis ) > 1.0 ) )
    {
        hReturn.Value = true;
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_IsAllowedToPickUpFlag_Post

  Summary:  This function is called after every
            `CTFPlayer::IsAllowedToPickUpFlag` call on a hooked
            entity and its purpose is to mimic bot flag logic.

            Original function signature:
            `bool CTFPlayer::IsAllowedToPickUpFlag( void )`

  Args:     int iThis
              Calling client index.
            DHookReturn hReturn
              Handle to the return value.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_IsAllowedToPickUpFlag_Post( int iThis, DHookReturn hReturn )
{
    if ( !g_aPlayerAttribs[ iThis ].IsControlling() )
    {
        // We only care about human invaders
        return MRES_Ignored;
    }

    if ( hReturn.Value == false )
    {
        // Game already decided the player can't pick up the flag
        return MRES_Ignored;
    }

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iThis ].iBotSerial );

    // TODO: Add squad check once we've got a working squad implementation

    // Mission bots can't pick up the flag
    hReturn.Value = !IsOnAnyMission( iBot ); // We add "cannot pick up intelligence" to human sentry busters
    return MRES_Supercede;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CCaptureFlag_PickUp_Post

  Summary:  This function is called after every
            `CCaptureFlag::Drop` call on a hooked entity and its
            purpose is to handle updating the objective resource.

            Original function signature:
            `bool CTFPlayer::ShouldGib( const CTakeDamageInfo &info )`

  Args:     int iThis
              Index of calling client.
            DHookReturn hReturn
              Handle to the return value.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CCaptureFlag_PickUp_Post( int iThis, DHookParam hParams )
{
    int iPlayer = hParams.Get( 1 );

    if ( g_aPlayerAttribs[ iPlayer ].IsControlling() )
    {
        int iBot = GetClientFromSerial( g_aPlayerAttribs[ iPlayer ].iBotSerial );
        if ( IsPlayerLockedInPlace( iBot ) )
        {
            /*--------------------------------------------------------------------
              `CCaptureFlag::PickUp` already sets the upgrade level to `0` and
              the base and next upgrade times to `-1` for us.
            --------------------------------------------------------------------*/
            if ( IsMiniBoss( iPlayer ) )
            {
                // Set threat level to max
                SetFlagCarrierUpgradeLevel( 4 );
            }
            else
            {
                SetBaseMvMBombUpgradeTime( GetGameTime() );
                SetNextMvMBombUpgradeTime( GetGameTime() + tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.FloatValue );
            }
        }
        /*--------------------------------------------------------------------
          NOTE: If the player's bot is not locked in place yet, then this is
          the player that just took control of the current flag carrier and
          `PlayerControlBot` takes care of updating the objective resource.
        --------------------------------------------------------------------*/
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_Event_Killed_Pre

  Summary:  This function is called before every
            `CTFPlayer::Event_Killed` call on a hooked entity and
            its purpose is fake a human invader's bot status so that
            the `CTFPlayer::Event_Killed` function's logic mimcs a
            bot's death.

            Original function signature:
            `void CTFPlayer::Event_Killed( const CTakeDamageInfo &info )`

  Args:     int iThis
              Calling client index.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_Event_Killed_Pre( int iThis, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() )
    {
        FakeBotStatus( iThis );
    }
    else if ( g_aBotAttribs[ iThis ].IsControlled() )
    {
        /*--------------------------------------------------------------------
          We need to unlock the bot, otherwise the game will keep it locked
          for one more respawn.
        --------------------------------------------------------------------*/
        UnlockPlayer( iThis );

        // Prevent the bot from dropping currency
        MarkAsMissionEnemy( iThis );
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_Event_Killed_Post

  Summary:  This function is called after every
            `CTFPlayer::Event_Killed` call on a hooked entity and
            its main purpose is to kill a player's controlled bot
            once the controlling player dies.

            Original function signature:
            `void CTFPlayer::Event_Killed( const CTakeDamageInfo &info )`

  Args:     int iThis
              Calling client index.
            DHookParam hParams
              Handle to the function's parameters.

  Returns:  MRESReturn
              Tells SourceMod what action to take.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
MRESReturn CTFPlayer_Event_Killed_Post( int iThis, DHookParam hParams )
{
    if ( g_aPlayerAttribs[ iThis ].IsControlling() )
    {
        RestorePlayerStatus( iThis );

        StopIdleSound( iThis );

        int iBot = GetClientFromSerial( g_aPlayerAttribs[ iThis ].iBotSerial );

        // This doesn't get cleared upon spawning, so we must manually null it
        SetEntData( iThis, g_CTFPlayer_pWaveSpawnPopulator_Offset, Address_Null, PTRSIZ );

        // Restore the player's original name
        if ( !StrEmpty( g_aPlayerAttribs[ iThis ].szOriginalName ) )
        {
            SetPlayerName( iThis, g_aPlayerAttribs[ iThis ].szOriginalName );
        }

        ResetGlobals( iThis );

        // The controlling player died, so also kill the bot
        ForcePlayerSuicide( iBot );
    }
    else if ( g_aBotAttribs[ iThis ].IsControlled() )
    {
        int iPlayer = GetClientFromSerial( g_aBotAttribs[ iThis ].iPlayerSerial );

        ResetGlobals( iThis );

        // The controlled bot died, so also kill the player
        ForcePlayerSuicide( iPlayer );
    }

    return MRES_Ignored;
}
