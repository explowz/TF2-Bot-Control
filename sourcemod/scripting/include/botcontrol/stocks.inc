/*+===================================================================
  File:    STOCKS.INC

  Summary: This file contains stock function used by the bot control
           plugin.

  Origin:  Created by Bintr on 14.06.2026.
===================================================================+*/

#if defined _botcontrol_stocks_included
    #endinput
#endif
#define _botcontrol_stocks_included

#include <sourcemod>
#include <dhooks>
#include <sdktools>
#include <tf2>
#include <tf2attributes>
#include <tf2items>
#include <tf_econ_data>
#include <tf2utils>
#include <pluginstatemanager>
#include <vscript>
#include <stocksoup/entity>
#include <stocksoup/tf/weapon>
#include <stocksoup/string>
#include <stocksoup/memory>
#include <stocksoup/tf/entity_prop_stocks>

#include "globals"
#include "const"

#pragma newdecls required
#pragma semicolon 1

#define DispatchKeyValueBool    DispatchKeyValueInt

#define SET_OFFSET_OR_ADDRESS(%1)              \
    if ( %1.Offset != -1 )                     \
    {                                          \
        PrepSDKCall_SetVirtual( %1.Offset );   \
    }                                          \
    else                                       \
    {                                          \
        PrepSDKCall_SetAddress( %1.Function ); \
    }

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: Sqr

  Summary:  This function-like macro calculates the square of a
            floating-point or integer value.

  Args:     float/int %1
              A floating-point or integer value.

  Returns:  float/int
              A floating-point or integer value representing the
              square of the value passed as `%1`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
#define Sqr(%1) ( ( %1 ) * ( %1 ) )

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsPlayerIndex

  Summary:  This function-like macro determines whether an entity
            index belongs to a `CTFPlayer` or `CTFBot` entity.

  Args:     int %1
              The entity index to be tested.

  Returns:  bool
              If the entity index belongs to a `CTFPlayer` or
              `CTFBot` entity, the return value is `true`.

              If the entity index does not belong to a `CTFPlayer`
              or `CTFBot` entity, the return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
#define IsPlayerIndex(%1) ( 0 < ( %1 ) <= MaxClients )

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CUtlVector_Count

  Summary:  This function-like macro gets the size of a `CUtlVector`.

  Args:     Address %1
              Memory address of the `CUtlVector` variable.

  Returns:  int
              Size of the vector.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
#define CUtlVector_Count(%1)    view_as< int >( LoadFromAddress( ( %1 ) + view_as< Address >( 12 ), NumberType_Int32 ) )

/*--------------------------------------------------------------------
  Include files that use macros defined in this file must come after
  the macro definitions. If this is moved before, we get an undefined
  symbol error. If it's removed, then it compiles, since in
  botcontrol.sp we order them, but then this file is full of erronous
  undefined symbol errors from the linter and it annoys me.
--------------------------------------------------------------------*/
#include "dynamichooks"

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: max

  Summary:  This function compares two values and returns the
            larger one. The data type can be any numeric data type
            The data type of the arguments and the return value is
            the same.

  Args:     any a
              Specifies the first of two values.
            any b
              Specifies the second of two values.

  Returns:  any
              The return value is the greater of the two specified
              values.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock any max( any a, any b )
{
    return a > b ? a : b;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: min

  Summary:  This function compares two values and returns the
            smaller one. The data type can be any numeric data type
            The data type of the arguments and the return value is
            the same.

  Args:     any a
              Specifies the first of two values.
            any b
              Specifies the second of two values.

  Returns:  any
              The return value is the smaller of the two specified
              values.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock any min( any a, any b )
{
    return a < b ? a : b;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RestoreBot

  Summary:  This function restores the bot of a controlling player,
            mirroring the player's last position, active conditions,
            bomb carrier status, etc.

  Args:     int iClient
              Index of controlling player.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RestoreBot( int iClient )
{
    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    if ( !StrEmpty( g_aPlayerAttribs[ iClient ].szOriginalName ) )
    {
        SetPlayerName( iClient, g_aPlayerAttribs[ iClient ].szOriginalName );
    }

    // The idle sound must be stopped before resetting globals
    StopIdleSound( iClient );

    // Reset these as soon as possible so we don't enter some infinite loop
    ResetGlobals( iClient );
    ResetGlobals( iBot );

    // Copy back properties that could've changed
    CopyEntProp( iClient, iBot, Prop_Send, "m_iHealth" );
    CopyEntPropFloat( iClient, iBot, Prop_Send, "m_flRageMeter" );

    /*--------------------------------------------------------------------
      We specifically turn this off for the bot to avoid double health
      bars, so now restore it.
    --------------------------------------------------------------------*/
    if ( GetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar" ) )
    {
        SetAttribute( iBot, USE_BOSS_HEALTH_BAR );
    }
    CopyEntProp( iClient, iBot, Prop_Send, "m_bUseBossHealthBar" );

    // Set these to `false` so they won't cause problems
    SetEntProp( iClient, Prop_Send, "m_bIsABot", false );
    SetIsMiniBoss( iClient, false );
    SetUseBossHealthBar( iClient, false );

    // This doesn't get cleared upon spawning, so we must manually null it
    SetWaveSpawnPopulator( iClient, Address_Null );

    // Mirror the player's conditions
    TFCond eLastCond = TF2Util_GetLastCondition();
    for ( TFCond eCond = TFCond_Slowed; eCond <= eLastCond; eCond++ )
    {
        int   iProvider;
        float flDuration;
        switch ( eCond )
        {
        /*--------------------------------------------------------------------
          Don't mirror spawn protection conditions, since we apply them in a
          different way compared to how the game does it.
        --------------------------------------------------------------------*/
        case TFCond_Ubercharged, TFCond_CloakFlicker, TFCond_UberchargedHidden, TFCond_ImmuneToPushback:
        {
            continue;
        }

        /*--------------------------------------------------------------------
          Burning and bleeding need to be handled separately due to how the
          game itself handles them.
        --------------------------------------------------------------------*/
        case TFCond_OnFire:
        {
            iProvider  = TF2Util_GetPlayerConditionProvider( iClient, eCond );
            flDuration = TF2Util_GetPlayerBurnDuration( iClient );
            // TODO: Find a way to get the weapon that ignited the player
            if ( flDuration != 0.0 )
            {
                TF2Util_IgnitePlayer( iBot, iProvider, flDuration );
            }
        }

        case TFCond_Bleeding:
        {
            int nBleedCount = TF2Util_GetPlayerActiveBleedCount( iClient );
            for ( int i = 0; i < nBleedCount; i++ )
            {
                iProvider         = TF2Util_GetPlayerBleedAttacker( iClient, i );
                int iWeapon       = TF2Util_GetPlayerBleedWeapon( iClient, i );
                flDuration        = TF2Util_GetPlayerBleedDuration( iClient, i );
                int iDamage       = TF2Util_GetPlayerBleedDamage( iClient, i );
                int iDamageCustom = TF2Util_GetPlayerBleedCustomDamageType( iClient, i );
                TF2Util_MakePlayerBleed( iBot, iProvider, flDuration, iWeapon, iDamage, iDamageCustom );
            }
        }

        default:
        {
            iProvider  = TF2Util_GetPlayerConditionProvider( iClient, eCond );
            flDuration = TF2Util_GetPlayerConditionDuration( iClient, eCond );
            if ( iProvider != INVALID_ENT_REFERENCE && flDuration != 0.0 )
            {
                TF2_AddCondition( iBot, eCond, flDuration, iProvider );
            }
        }
        }
    }

    // Mirror the player's ammo and active weapon
    for ( int i = 0; i <= TFWeaponSlot_PDA; i++ )
    {
        int iWeapon = GetPlayerWeaponSlot( iClient, i );
        if ( iWeapon == -1 )
        {
            continue;
        }

        int iBotWeapon = GetPlayerWeaponSlot( iBot, i );
        if ( iBotWeapon != -1 )
        {
            // Some other plugin most likely removed the bot's weapon
            continue;
        }

        TF2_SetWeaponAmmo( iBotWeapon, TF2_GetWeaponAmmo( iWeapon ) );

        /*--------------------------------------------------------------------
          Force the bot to switch to this weapon if this is what the player
          was last using
        --------------------------------------------------------------------*/
        if ( TF2_GetClientActiveWeapon( iClient ) == iWeapon )
        {
            TF2Util_SetPlayerActiveWeapon( iBot, iBotWeapon );
        }
    }

    switch ( TF2_GetPlayerClass( iClient ) )
    {
    case TFClass_Medic:
    {
        int iPlayerMedigun = GetPlayerWeaponSlot( iClient, TFWeaponSlot_Secondary );
        int iBotMedigun    = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Secondary );

        // Make sure the bot's secondary weapon wasn't removed while it was shelved
        if ( iPlayerMedigun != -1 && iBotMedigun != -1 )
        {
            // Make sure that the bot's secondary weapon is still a medigun
            if ( TF2Util_GetWeaponID( iPlayerMedigun ) == TF_WEAPON_MEDIGUN &&
                 TF2Util_GetWeaponID( iBotMedigun )    == TF_WEAPON_MEDIGUN )
            {
                // Mirror the player's medigun properties
                CopyEntPropFloat( iPlayerMedigun, iBotMedigun, Prop_Send, "m_flChargeLevel" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_nChargeResistType" );
                CopyEntPropEnt( iPlayerMedigun, iBotMedigun, Prop_Send, "m_hHealingTarget" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bAttacking" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bHealing" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bChargeRelease" );
            }
        }
    }

    case TFClass_Engineer:
    {
        // Change ownership of the player's buildings
        for ( int i = GetObjectCount( iClient ) - 1; i >= 0; i-- )
        {
            int iObject = GetObject( iClient, i );
            if ( iObject != -1 )
            {
                TransferObject( iObject, iBot );
            }
        }
    }

    case TFClass_Spy:
    {
        // Mirror the player's disguise
        TFClassType eDisguiseClass = TF2_GetPlayerDisguiseClass( iClient );
        if ( eDisguiseClass != TFClass_Unknown )
        {
            int iDisguiseTarget = GetDisguiseTarget( iClient );
            if ( iDisguiseTarget != -1 && IsClientInGame( iDisguiseTarget ) && TF2_GetClientTeam( iDisguiseTarget ) == TF_TEAM_PVE_DEFENDERS )
            {
                TF2_DisguisePlayer( iBot, TF_TEAM_PVE_DEFENDERS, eDisguiseClass, iDisguiseTarget );
            }
            else
            {
                // The player the human invader was disguised as disconnected or changed teams
                TF2_DisguisePlayer( iBot, TF_TEAM_PVE_DEFENDERS, eDisguiseClass );
            }
        }
    }
    }

    if ( HasTheFlag( iClient ) )
    {
        g_aPlayerAttribs[ iClient ].bBlockFlagEvent = true;
        g_aBotAttribs[ iBot ].bBlockFlagEvent       = true;

        /*--------------------------------------------------------------------
          TODO: Write an extension to detour `CTFBotDeliverFlag::OnStart`.
          For now the bot bomb carrier just will have to start upgrading
          from zero when restored.
        --------------------------------------------------------------------*/

        // Save these so we can restore them after the bomb swap
        /*int   nFlagCarrierUpgradeLevel = GetFlagCarrierUpgradeLevel();
        float flMvMBaseBombUpgradeTime = GetBaseMvMBombUpgradeTime();
        float flMvMNextBombUpgradeTime = GetNextMvMBombUpgradeTime();*/

        // Give the bomb to the bot
        int iBomb = GetItem( iClient );
        DropFlag( iClient, true );
        PickUp( iBomb, iBot, false );

        /*SetFlagCarrierUpgradeLevel( nFlagCarrierUpgradeLevel );
        SetBaseMvMBombUpgradeTime( flMvMBaseBombUpgradeTime );
        SetNextMvMBombUpgradeTime( flMvMNextBombUpgradeTime );

        ApplyPreviousUpgrades( iBot );*/
    }

    if ( GetPrevMission( iBot ) == MISSION_DESTROY_SENTRIES )
    {
        // Remove buddha so the player doesn't remain immortal
        DebugOverlayBits_t fDebugOverlays = view_as< DebugOverlayBits_t >( GetEntProp( iClient, Prop_Data, "m_debugOverlays" ) );
        SetEntProp( iClient, Prop_Data, "m_debugOverlays", fDebugOverlays & ~OVERLAY_BUDDHA_MODE );

        SetMission( iBot, MISSION_DESTROY_SENTRIES );
    }

    TF2Attrib_RemoveAll( iClient );

    float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );
    GetClientEyeAngles( iClient, angEyeAngles );
    GetEntPropVector( iClient, Prop_Data, "m_vecVelocity", vecVelocity );

    // Send the player to spectate
    TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

    // Teleport the bot in the player's place
    TeleportEntity( iBot, vecOrigin, angEyeAngles, vecVelocity );
    UnlockPlayer( iBot );
    RemoveEffects( iBot, EF_NODRAW ); // Make the bot spectatable again

    // Start the bot's idle sound (if any)
    StartIdleSound( iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ResetGlobals

  Summary:  This function resets a client's global variables.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
void ResetGlobals( int iClient )
{
    g_aPlayerAttribs[ iClient ].iBotSerial              = 0;
    g_aPlayerAttribs[ iClient ].iGetBotTypeHookId       = INVALID_HOOK_ID;
    g_aPlayerAttribs[ iClient ].nInitialCurrency        = 0;
    g_aPlayerAttribs[ iClient ].bIsGroupMember          = false;
    g_aPlayerAttribs[ iClient ].bBlockFlagEvent         = false;
    g_aPlayerAttribs[ iClient ].bInSpawn                = false;
    g_aPlayerAttribs[ iClient ].bPendingTaunt           = false;
    g_aPlayerAttribs[ iClient ].bIsWaitingForFullReload = false;
    g_aPlayerAttribs[ iClient ].szOriginalName[ 0 ]     = EOS;

    g_aBotAttribs[ iClient ].iPlayerSerial   = 0;
    g_aBotAttribs[ iClient ].bBlockFlagEvent = false;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: WorldSpaceCenter

  Summary:  This function gets the center point of an entity.

  Args:     int iEntity
              Entity index.

  Returns:  float[]
              Vector representing the center point of `iEntity`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float[] WorldSpaceCenter( int iEntity )
{
    float vec[ 3 ];
    SDKCall( g_hfnCBaseEntity_WorldSpaceCenter, iEntity, vec );
    return vec;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetPlayerName

  Summary:  This function gets a player's networked name.

  Args:     int iClient
              Client index.

  Returns:  char[]
              A string representing the client's networked name.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock char[] GetPlayerName( int iClient )
{
    char szNetname[ MAX_NAME_LENGTH ];
    GetEntPropString( iClient, Prop_Data, "m_szNetname", szNetname, sizeof( szNetname ) );

    return szNetname;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetPlayerName

  Summary:  This function sets a player's networked name.

  Args:     int iClient
              Client index.
            char[] szNetname
              A string representing the player's new name.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetPlayerName( int iClient, char[] szNetname )
{
    SetEntPropString( iClient, Prop_Data, "m_szNetname", szNetname );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: FakeBotStatus

  Summary:  This function sets the `FL_FAKECLIENT` on `iPlayer` and
            hooks a `CBasePlayer::GetBotType` dynamic detour which
            fakes the player's bot type.

  Args:     int iPlayer
              Client index of a `CTFPlayer` entity.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void FakeBotStatus( int iPlayer )
{
    SetEntityFlags( iPlayer, GetEntityFlags( iPlayer ) | FL_FAKECLIENT );
    g_aPlayerAttribs[ iPlayer ].iGetBotTypeHookId = PSM_DHookEntityByName( "CBasePlayer::GetBotType", Hook_Pre, iPlayer, CBasePlayer_GetBotType_Pre );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RestorePlayerStatus

  Summary:  This function removes the `FL_FAKECLIENT` on `iPlayer`
            and unhooks the `CBasePlayer::GetBotType` dynamic detour
            which fakes the player's bot type.

  Args:     int iPlayer
              Client index of a `CTFPlayer` entity.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RestorePlayerStatus( int iPlayer )
{
    SetEntityFlags( iPlayer, GetEntityFlags( iPlayer ) & ~FL_FAKECLIENT );
    DynamicHook.RemoveHook( g_aPlayerAttribs[ iPlayer ].iGetBotTypeHookId );
    g_aPlayerAttribs[ iPlayer ].iGetBotTypeHookId = INVALID_HOOK_ID;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetCustomModelWithClassAnimations

  Summary:  This function changes a client's model and specifies
            that the model uses class animations.

  Args:     int iClient
              Client index.
            const char[] szModel
              A string representing the model name.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetCustomModelWithClassAnimations( int iClient, const char[] szModel )
{
    SetVariantString( szModel );
    AcceptEntityInput( iClient, "SetCustomModelWithClassAnimations" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetCustomModelRotates

  Summary:  This function sets whether a custom model should is
            allowed to be rotated.

  Args:     int iClient
              Client index.
            bool bRotates
              If `true`, the custom model will be allowed to rotate.

              If `false`, the custom model will not be allowed to
              rotate.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetCustomModelRotates( int iClient, bool bRotates )
{
    SetVariantBool( bRotates );
    AcceptEntityInput( iClient, "SetCustomModelRotates" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetCustomModelRotation

  Summary:  This function sets a client's custom model rotation.

  Args:     int iClient
              Client index.
            float ang[ 3 ]
              Rotation angle.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetCustomModelRotation( int iClient, float ang[ 3 ] )
{
    SetVariantVector3D( ang );
    AcceptEntityInput( iClient, "SetCustomModelRotation" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetModelName

  Summary:  This function gets a client's model name.

  Args:     int iClient
              Client index.

  Returns:  char[]
              Null-terminated string representing the model name.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock char[] GetModelName( int iClient )
{
    char szModelName[ PLATFORM_MAX_PATH ];
    GetEntPropString( iClient, Prop_Data, "m_ModelName", szModelName, sizeof( szModelName ) );

    return szModelName;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetModelScale

  Summary:  This function sets a client's model scale.

  Args:     int iClient
              Client index.
            float flScale
              Model scale.
            float flChangeDuration
              The amount of time over which the scaling will be
              performed.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetModelScale( int iClient, float flScale, float flChangeDuration )
{
    /*--------------------------------------------------------------------
      `SetModelScale` takes a vector whose x axis represents the model's
      scale and y axis represents the duration the scaling should be
      performed over. The z axis is ignored.
    --------------------------------------------------------------------*/
    float vec[ 3 ] = { 0.0, ... };

    vec[ 0 ] = flScale;
    vec[ 1 ] = flChangeDuration;

    SetVariantVector3D( vec );
    AcceptEntityInput( iClient, "SetModelScale" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetModelScale

  Summary:  This function gets a player's model scale.

  Args:     int iClient
              Client index.

  Returns:  float
              Model scale.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetModelScale( int iClient )
{
    return GetEntPropFloat( iClient, Prop_Send, "m_flModelScale" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CopyItem

  Summary:  This function creates an _almost_ identical copy of an
            item (weapon or wearable). The item's level will not
            be mirrored, and instead will be randomized.

  Args:     int iItem
              Entity index of the item to copy.
            int iClient
              Client index of of the entity that becomes the
              copied item's owner.

  Returns:  int
              Entity index of the created item. If copying the
              item failed, the return value is `-1`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int CopyItem( int iItem, int iClient )
{
    int iItemDefinitionIndex = GetEntProp( iItem, Prop_Send, "m_iItemDefinitionIndex" );
    if ( iItemDefinitionIndex == 0xFFFF )
    {
        // Weapon wearables which are applied automatically
        return -1;
    }

    char szClassname[ 64 ];
    GetEntityClassname( iItem, szClassname, sizeof( szClassname ) );

    int aiAttributeDefinitionIndices[ MAX_ATTRIBUTES_PER_ITEM ];
    int nAttribs = TF2Attrib_ListDefIndices( iItem, aiAttributeDefinitionIndices, sizeof( aiAttributeDefinitionIndices ) );

    Handle hNewItem = TF2Items_CreateItem( OVERRIDE_ALL | PRESERVE_ATTRIBUTES );
    TF2Items_SetClassname( hNewItem, szClassname );
    TF2Items_SetItemIndex( hNewItem, iItemDefinitionIndex );
    TF2Items_SetQuality( hNewItem, TF2Econ_GetItemQuality( iItemDefinitionIndex ) );
    int iMinLevel, iMaxLevel;
    TF2Econ_GetItemLevelRange( iItemDefinitionIndex, iMinLevel, iMaxLevel );
    TF2Items_SetLevel( hNewItem, GetRandomInt( iMinLevel, iMaxLevel ) );

    TF2Items_SetNumAttributes( hNewItem, nAttribs );
    for ( int i = 0; i < nAttribs; i++ )
    {
        TF2Items_SetAttribute(
                              hNewItem,
                              i,
                              aiAttributeDefinitionIndices[ i ],
                              TF2Attrib_GetValue( TF2Attrib_GetByDefIndex( iItem, aiAttributeDefinitionIndices[ i ] ) )
                             );
    }

    int iNewItem = TF2Items_GiveNamedItem( iClient, hNewItem );
    delete hNewItem;

    return iNewItem;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ModifyMaxHealth

  Summary:  This function modifies the maximum health of a
            `CTFPlayer` entity.

  Args:     int iClient
              Entity index of a `CTFPlayer` entity whose max health
              to change.
            int nNewMaxHealth
              An integer representing the new maximum health
              `iClient` should have.
            bool bSetCurrentHealth
              If `bSetCurrentHealth` is `true`, `iClient`'s current
              health will be set to `nNewMaxHealth`.
            bAllowModelScaling
              Unused.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ModifyMaxHealth( int iClient, int nNewMaxHealth, bool bSetCurrentHealth = true, bool bAllowModelScaling = true )
{
#pragma unused bAllowModelScaling

    int iMaxHealth = TF2Util_GetEntityMaxHealth( iClient );
    if ( iMaxHealth != nNewMaxHealth )
    {
        TF2Attrib_SetByName( iClient, "hidden maxhealth non buffed", float( nNewMaxHealth - iMaxHealth ) );
    }

    if ( bSetCurrentHealth )
    {
        SetEntityHealth( iClient, nNewMaxHealth );
    }

    // TODO: Implement logic for `bAllowModelScaling` sometime in the future,
    // although it's not trivial for the way this function is used in this plugin.
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RemoveAllItems

  Summary:  This function removes all weapons and wearables from
            a client.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RemoveAllItems( int iClient )
{
    // Nuke items
    TF2_RemoveAllWeapons( iClient );

    // Nuke wearables
    for ( int i = TF2Util_GetPlayerWearableCount( iClient ) - 1; i >= 0; i-- )
    {
        int iWearable = TF2Util_GetPlayerWearable( iClient, i );
        if ( iWearable == -1 )
        {
            continue;
        }

        TF2_RemoveWearable( iClient, iWearable );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RemoveAllWeapons

  Summary:  This function removes all weapons and wearables from
            a client. The difference between this function and
            `RemoveAllItems` is that this function also removes
            disguise wearables.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RemoveAllWeapons( int iClient )
{
    SDKCall( g_hfnCTFPlayer_RemoveAllWeapons, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HasTheFlag

  Summary:  This determines whether a client is currently carrying
            the capture flag.

  Args:     int iClient
              Client index to test.
            ETFFlagType[] aeExceptionTypes
              Array of flag types that should be ignored.
            int nNumExceptions
              Size of `aExceptionTypes` array.

  Returns:  bool
              If the player is carrying the flag, the return value
              is `true`.

              If the player is not carrying the flag, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool HasTheFlag( int iClient, ETFFlagType[] aeExceptionTypes = { view_as< ETFFlagType >( -1 ) }, int nNumExceptions = 0 )
{
#pragma unused aeExceptionTypes
#pragma unused nNumExceptions

    return SDKCall( g_hfnCTFPlayer_HasTheFlag, iClient, 0, 0 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: PickUp

  Summary:  This function forces a `CTFPlayer` entity to pick up
            the capture flag.

  Args:     int iCaptureFlag
              Entity index of the flag `iPlayer` should pick up.
            int iPlayer
              Client index of the player that the capture flag will
              be given to.
            bool bInvisible
              Unused. `CCaptureFlag::PickUp` always passes `false`
              as the `bInvisible` argument when calling the base
              class function.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void PickUp( int iCaptureFlag, int iPlayer, bool bInvisible )
{
    SDKCall( g_hfnCCaptureFlag_PickUp, iCaptureFlag, iPlayer, bInvisible );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: DropFlag

  Summary:  This function forces a `CTFPlayer` entity to drop the
            capture flag.

  Args:     int iPlayer
              Client index.
            bool bSilent
              If `bSilent` is `false`, all players will receive
              a HUD notification and/or sound cue.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void DropFlag( int iPlayer, bool bSilent = false )
{
    SDKCall( g_hfnCTFPlayer_DropFlag, iPlayer, bSilent );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RemoveObject

  Summary:  This function removes an object from a `CTFPlayer`'s
            `m_aObjects` array of owned objects.

  Args:     int iClient
              Client index from which to remove `iObject`.
            int iObject
              Object index to remove from the player.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RemoveObject( int iClient, int iObject )
{
    SDKCall( g_hfnCTFPlayer_RemoveObject, iClient, iObject );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: TransferObject

  Summary:  This function transfers a built object from one player
            to another.

  Args:     int iObject
              Index of building object to transfer.
            int iNewBuilder
              Client index of the player that becomes `iBuilding`'s
              new owner.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void TransferObject( int iObject, int iNewBuilder )
{
    int iOldBuilder = TF2_GetObjectBuilder( iObject );
    if ( iOldBuilder == iNewBuilder )
    {
        return;
    }

    if ( iOldBuilder != -1 )
    {
        SetEntPropEnt( iObject, Prop_Send, "m_hBuilder", -1 );
        RemoveObject( iOldBuilder, iObject );
    }

    AcceptEntityInput( iObject, "SetBuilder", iNewBuilder );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: LeaveSquad

  Summary:  This function makes a `CTFBot` entity leave their
            current squad (if any).

  Args:     int iBot
              Client index of the bot that should leave their squad.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void LeaveSquad( int iBot )
{
    SDKCall( g_hfnCTFBot_LeaveSquad, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetAttribute

  Summary:  This function sets a bot's attribute.

  Args:     int iBot
              `CTFBot` client index.
            AttributeType eAttributeFlag
              Attribute to set.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetAttribute( int iBot, AttributeType eAttributeFlag )
{
    SDKCall( g_hfnCTFBot_SetAttribute, iBot, eAttributeFlag );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ClearAttribute

  Summary:  This function clear a bot's attribute.

  Args:     int iBot
              `CTFBot` client index.
            AttributeType eAttributeFlag
              Attribute to clear.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ClearAttribute( int iBot, AttributeType eAttributeFlag )
{
    SDKCall( g_hfnCTFBot_ClearAttribute, iBot, eAttributeFlag );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ClearAllAttributes

  Summary:  This function clear all attributes of a bot.

  Args:     int iBot
              `CTFBot` client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ClearAllAttributes( int iBot )
{
    SDKCall( g_hfnCTFBot_ClearAllAttributes, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HasAttribute

  Summary:  This function checks if this TFBot has the given
            attributes.

  Args:     int iBot
              Client index of the bot whose attributes to check.
            AttributeType eAttributeFlag
              Attribute to test.

  Returns:  bool
              If the bot has the given attributes, the return value
              will be `true`. Otherwise it will be `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool HasAttribute( int iBot, AttributeType eAttributeFlag )
{
    return SDKCall( g_hfnCTFBot_HasAttribute, iBot, eAttributeFlag );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetMission

  Summary:  This function sets a bot's current mission to the given
            mission.

  Args:     int iBot
              `CTFBot` entity index.
            MissionType eMission
              Mission type.
            bool bResetBehaviorSystem
              If `true`, the bot's behavior system will be reset.
              If `false`, the bot's behavior system will not be
              reset.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetMission( int iBot, MissionType eMission, bool bResetBehaviorSystem = true )
{
    SDKCall( g_hfnCTFBot_SetMission, iBot, eMission, bResetBehaviorSystem );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetPrevMission

  Summary:  This function sets a bot's previous mission to the given
            mission.

  Args:     int iBot
              `CTFBot` entity index.
            MissionType eMission
              Mission type.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetPrevMission( int iBot, MissionType eMission )
{
    SDKCall( g_hfnCTFBot_SetPrevMission, iBot, eMission );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetMission

  Summary:  This function gets a bot's current mission.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  bool
              A `MissionType` value representing `iBot`'s current
              mission.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock MissionType GetMission( int iBot )
{
    return SDKCall( g_hfnCTFBot_GetMission, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetPrevMission

  Summary:  This function gets a bot's previous mission.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  bool
              A `MissionType` value representing `iBot`'s previous
              mission.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock MissionType GetPrevMission( int iBot )
{
    return SDKCall( g_hfnCTFBot_GetPrevMission, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HasMission

  Summary:  This function checks if a mission is the bot's current
            mission.

  Args:     int iBot
              `CTFBot` entity index.
            MissionType eMission
              Mission type.

  Returns:  bool
              If the bot's current mission is `eMission`, the return
              value is `true`.

              If the bot's current mission is not `eMisison`, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool HasMission( int iBot, MissionType eMission )
{
    return SDKCall( g_hfnCTFBot_HasMission, iBot, eMission );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsOnAnyMission

  Summary:  This function determines whether a bot has a current
            mission.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  bool
              If the bot has a current mission, the return value
              is `true`.

              If the bot doesn't have a current mission, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsOnAnyMission( int iBot )
{
    return SDKCall( g_hfnCTFBot_IsOnAnyMission, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetSubType

  Summary:  This function sets the subtype of a builder entity.

  Args:     int iBuilder
              Builder weapon entity index whose subtype to set.
            int iSubType
              The subtype of the builder weapon.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetSubType( int iBuilder, int iSubType )
{
    SDKCall( g_hfnCTFWeaponBuilder_SetSubType, iBuilder, iSubType );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetPlayerClassData

  Summary:  This function gets the address in memory of the
            `TFPlayerClassData_t` struct containing the default
            information of a player class.

  Args:     TFClassType eClass
              The player class type of which to get the
              `TFPlayerClassData_t` address of.

  Returns:  Address
              Memory address of the player class's
              `TFPlayerClassData_t` struct.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock Address GetPlayerClassData( TFClassType eClass )
{
    return SDKCall( g_hfnGetPlayerClassData, eClass );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ManageBuilderWeapons

  Summary:  This function validates a player's builder weapons and
            sets the type of objects it can build.

  Args:     int iClient
              Index of `CTFPlayer` entity whose builder items to
              validate and set up.
            Address pData
              Pointer to a `TFPlayerClassData_t` struct.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ManageBuilderWeapons( int iClient, Address pData )
{
    SDKCall( g_hfnCTFPlayer_ManageBuilderWeapons, iClient, pData );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: PostInventoryApplication

  Summary:  This function notifies `iClient` about a loadout change
            and applies any skin override provided by an item.

  Args:     int iClient
              Index of `CTFPlayer` entity whose items were changed.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void PostInventoryApplication( int iClient )
{
    SDKCall( g_hfnCTFPlayer_PostInventoryApplication, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsStealthed

  Summary:  This function determines whether a client is stealthed.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client is stealthed, the return value is `true`.

              If the client is not stealthed, the return value is
              `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsStealthed( int iClient )
{
    return SDKCall( g_hfnCTFPlayerShared_IsStealthed, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetPercentInvisible

  Summary:  This function gets a client's invisibility percentage.

  Args:     int iClient
              Client index.

  Returns:  float
              A floating-point value representing the client's
              invisibility percentage.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetPercentInvisible( int iClient )
{
    return GetEntDataFloat( iClient, g_CTFPlayerShared_flInvisibility_Offset );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: FindHint

  Summary:  This function searches for active engineer nest hints
            on the map.

  Args:     bool bShouldCheckForBlockingObjects
              If `true`, the function will only search for hints
              that are not blocked by any players or objects.
            bool bAllowOutOfRangeNest
              If `true`, the function will be less strict when
              deciding if a nest is considered out of range.
            Address pFoundNest
              This parameter is reserved and must be `Address_Null`.

  Returns:  bool
              If the current map contains an active engineer nest
              hint, the return value is `true`.

              If the current map doesn't contain an active engineer
              nest hint, the return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool FindHint( bool bShouldCheckForBlockingObjects, bool bAllowOutOfRangeNest, Address pFoundNest = Address_Null )
{
    return SDKCall( g_hfnCTFBotMvMEngineerHintFinder_FindHint, bShouldCheckForBlockingObjects, bAllowOutOfRangeNest, pFoundNest );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsMannVsMachineMode

  Summary:  This function determines if the current map is a Mann
            vs. Machine map.

  Returns:  bool
              If the current map is a Mann vs. Machine map, the
              return value is `true`.

              If the current map is not a Mann vs. Machine map,
              the return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsMannVsMachineMode()
{
    return GameRules_GetProp( "m_bPlayingMannVsMachine" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsMiniBoss

  Summary:  This function determines if a player is a mini boss.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client is a mini boss, the return value is `true`.

              If the client is not a mini boss, the return value
              is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsMiniBoss( int iClient )
{
    return GetEntProp( iClient, Prop_Send, "m_bIsMiniBoss" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetIsMiniBoss

  Summary:  This function sets whether a client is a mini boss.

  Args:     int iClient
              Client index.
            bool bUseBossHealthBar
              `true` to mark the client as a mini boss.

              `false` to mark the client as not a mini boss.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetIsMiniBoss( int iClient, bool bIsMiniBoss )
{
    SetEntProp( iClient, Prop_Send, "m_bIsMiniBoss", bIsMiniBoss );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetUseBossHealthBar

  Summary:  This function sets whether a client should have a boss
            health bar.

  Args:     int iClient
              Client index.
            bool bUseBossHealthBar
              `true` to make the client use a boss health bar.

              `false` to make the client not use a boss health bar.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetUseBossHealthBar( int iClient, bool bUseBossHealthBar )
{
    SetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar", bUseBossHealthBar );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetDeployingBombState

  Summary:  This function sets a client's bomb deploying state.

  Args:     int iClient
              Client index.
            BombDeployingState_t nDeployingBombState
              The value to which to set `iClient`'s
              `m_nDeployingBombState` property.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetDeployingBombState( int iClient, BombDeployingState_t nDeployingBombState )
{
    SetEntData( iClient, g_CTFPlayer_nDeployingBombState_Offset, nDeployingBombState, 4 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetDeployingBombState

  Summary:  This function gets a client's bomb deploying state.

  Args:     int iClient
              Client index.

  Returns:  BombDeployingState_t
              The deploying bomb state the player is currently in.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock BombDeployingState_t GetDeployingBombState( int iClient )
{
    return view_as< BombDeployingState_t >( GetEntData( iClient, g_CTFPlayer_nDeployingBombState_Offset, 4 ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsMissionEnemy

  Summary:  This function determines whether a client is a mission
            enemy.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client is a mission enemy, the return value is
              `true`.

              If the client is not a mission enemy, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsMissionEnemy( int iClient )
{
    return GetEntData( iClient, g_CTFPlayer_bIsMissionEnemy_Offset, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: MarkAsMissionEnemy

  Summary:  This function marks a client as a mission enemy.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void MarkAsMissionEnemy( int iClient )
{
    SetEntData( iClient, g_CTFPlayer_bIsMissionEnemy_Offset, true, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsSupportEnemy

  Summary:  This function determines whether a client is a support
            enemy.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client is a support enemy, the return value is
              `true`.

              If the client is not a support enemy, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsSupportEnemy( int iClient )
{
    return GetEntData( iClient, g_CTFPlayer_bIsSupportEnemy_Offset, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: MarkAsSupportEnemy

  Summary:  This function marks a client as a support enemy.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void MarkAsSupportEnemy( int iClient )
{
    SetEntData( iClient, g_CTFPlayer_bIsSupportEnemy_Offset, true, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: MarkAsLimitedSupportEnemy

  Summary:  This function marks a client as a limited support enemy.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void MarkAsLimitedSupportEnemy( int iClient )
{
    SetEntData( iClient, g_CTFPlayer_bIsLimitedSupportEnemy_Offset, true, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetWaveSpawnPopulator

  Summary:  This function sets a client's wave spawn populator.

  Args:     int iClient
              Client index.
            Address pWave
              Memory address of a `CWaveSpawnPopulator` variable.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetWaveSpawnPopulator( int iClient, Address pWave )
{
    SetEntData( iClient, g_CTFPlayer_pWaveSpawnPopulator_Offset, pWave, PTRSIZ );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetCurrency

  Summary:  This function gets a client's currency amount.

  Args:     int iClient
              Client index.

  Returns:  int
              `iClient`'s currency amount.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetCurrency( int iClient )
{
    return GetEntProp( iClient, Prop_Send, "m_nCurrency" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetCurrency

  Summary:  This function sets a client's currency amount.

  Args:     int iClient
              Client index.
            int nAmount
              Currency amount.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetCurrency( int iClient, int nAmount )
{
    SetEntProp( iClient, Prop_Send, "m_nCurrency", nAmount );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetCustomCurrencyWorth

  Summary:  This function sets the amount of money a client is worth
            when killed. We reuse `m_nCurrency` because invaders
            don't collect currency. This function is practically
            identical to `SetCurrency`.

  Args:     int iClient
              Client index.
            int nAmount
              Currency amount.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetCustomCurrencyWorth( int iClient, int nAmount )
{
    SetEntProp( iClient, Prop_Send, "m_nCurrency", nAmount );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsShieldEquipped

  Summary:  This function determines whether a player has a shield
            equipped.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client has a shield equipped, the return value
              is `true`.

              If the client does not have a shield equipped, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsShieldEquipped( int iClient )
{
    return GetEntProp( iClient, Prop_Send, "m_bShieldEquipped" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsJumping

  Summary:  This function determines whether a player is currently
            jumping.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the client is currently jumping, the return value
              is `true`.

              If the client is not currently jumping, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsJumping( int iClient )
{
    return GetEntProp( iClient, Prop_Send, "m_bJumping" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsDropped

  Summary:  This function determines a capture flag is currently
            dropped.

  Args:     int iCaptureFlag
              `CCaptureFlag` entity index.

  Returns:  bool
              If the capture flag is currently dropped, the return
              value is `true`.

              If the capture flag is not currently dropped, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsDropped( int iCaptureFlag )
{
    return ( GetEntProp( iCaptureFlag, Prop_Send, "m_nFlagStatus" ) == TF_FLAGINFO_DROPPED );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsHome

  Summary:  This function determines a capture flag is currently
            home (aka has not been picked up yet).

  Args:     int iCaptureFlag
              `CCaptureFlag` entity index.

  Returns:  bool
              If the capture flag is currently home, the return
              value is `true`.

              If the capture flag is not currently home, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsHome( int iCaptureFlag )
{
    return ( GetEntProp( iCaptureFlag, Prop_Send, "m_nFlagStatus" ) == TF_FLAGINFO_HOME );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsStolen

  Summary:  This function determines a capture flag is currently
            stolen.

  Args:     int iCaptureFlag
              `CCaptureFlag` entity index.

  Returns:  bool
              If the capture flag is currently stolen, the return
              value is `true`.

              If the capture flag is not currently stolen, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsStolen( int iCaptureFlag )
{
    return ( GetEntProp( iCaptureFlag, Prop_Send, "m_nFlagStatus" ) == TF_FLAGINFO_STOLEN );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetGroundEntity

  Summary:  This function retrieves the entity the client is
            currently standing on.

  Args:     int iClient
              Client index.

  Returns:  int
              An integer value representing the entity index of
              the entity the client is currently standing on.

              If the client is not standing on anything, the return
              value is `-1`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetGroundEntity( int iClient )
{
    return GetEntPropEnt( iClient, Prop_Send, "m_hGroundEntity" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HasItem

  Summary:  This function determines whether a player is currently
            carrying an item.

  Args:     int iClient
              Client index to be tested.

  Returns:  bool
              If the player is carrying an item, the return value is
              `true`.

              If the player is not carrying an item, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool HasItem( int iClient )
{
    return GetItem( iClient ) != -1;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetItem

  Summary:  This function get the item a client is currently
            carrying.

  Args:     int iClient
              Client index.

  Returns:  int
              Index of item entity the client is carrying.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetItem( int iClient )
{
    return GetEntPropEnt( iClient, Prop_Send, "m_hItem" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetSpawnTime

  Summary:  This function gets a player's spawn time.

  Args:     int iClient
              Index of the client whose spawn time to get.

  Returns:  float
              Float value representing time game time `iClient`
              spawned.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetSpawnTime( int iClient )
{
    return GetEntDataFloat( iClient, g_CTFPlayer_flSpawnTime_Offset );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetObject

  Summary:  This function returns an object from a player's owned
            objects array.

  Args:     int iClient
              Client index.
            int i
              Array index.

  Returns:  int
              Object index at stored at `i` in `iClient`'s
              `m_aObjects` array.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetObject( int iClient, int i )
{
    Address aObjects = view_as< Address >( GetEntData( iClient, g_CTFPlayer_aObjects_Offset, PTRSIZ ) );
    return LoadEntityFromHandleAddress( aObjects + view_as< Address >( i * PTRSIZ ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetObjectCount

  Summary:  This function gets the number of objects a player owns.

  Args:     int iClient
              Index of the client whose number of owned objects to
              get.

  Returns:  int
              Integer value representing the number of objects a
              player owns.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetObjectCount( int iClient )
{
    return CUtlVector_Count( view_as< Address >( GetEntData( iClient, g_CTFPlayer_aObjects_Offset, PTRSIZ ) ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBot_GetTeleportWhere

  Summary:  This function returns the memory address at which
            `iBot`'s `m_teleportWhereName` array resides.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  Address
              Memory address at which `iBot`'s `m_teleportWhereName`
              array resides.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock Address CTFBot_GetTeleportWhere( int iBot )
{
    return GetEntityAddress( iBot ) + view_as< Address >( g_CTFBot_teleportWhereName_Offset );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBot_GetTeleportWhereElement

  Summary:  This function gets a string value from a `CTFBot`'s
            `m_teleportWhereName` array.

  Args:     int iBot
              `CTFBot` entity index.
            int i
              Array index.

  Returns:  char[]
              String residing at `m_teleportWhereName[ i ]`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock char[] CTFBot_GetTeleportWhereElement( int iBot, int i )
{
    Address pTeleportWhereName = view_as< Address >( GetEntData( iBot, g_CTFBot_teleportWhereName_Offset, PTRSIZ ) );
    Address psz                = DereferencePointer( pTeleportWhereName + view_as< Address >( i * PTRSIZ ) );

    char sz[ 64 ];
    LoadStringFromAddress( psz, sz, sizeof( sz ) );
    return sz;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBot_GetTeleportWhereCount

  Summary:  This function returns the number of entries in a
            `CTFBot`'s `m_teleportWhereName` array.

  Args:     int iBot
              Index of the `CTFBot` entity whose number of entries
              in their `m_teleportWhereName` string array to get.

  Returns:  int
              Integer value representing the number of `TeleportWhere`
              string values `iBot` has.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int CTFBot_GetTeleportWhereCount( int iBot )
{
    return CUtlVector_Count( CTFBot_GetTeleportWhere( iBot ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_GetTeleportWherePtr

  Summary:  This function returns the memory address at which
            `iObjectTeleporter`'s `m_teleportWhereName` array resides.

  Args:     int iObjectTeleporter
              `CObjectTeleporter` entity index.

  Returns:  Address
              Memory address at which `iObjectTeleporter`'s
              `m_teleportWhereName` array resides.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock Address CObjectTeleporter_GetTeleportWhere( int iObjectTeleporter )
{
    return GetEntityAddress( iObjectTeleporter ) + view_as< Address >( g_CObjectTeleporter_teleportWhereName_Offset );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_GetTeleportWhereElement

  Summary:  This function gets a string value from a `CObjectTeleporter`'s
            `m_teleportWhereName` array.

  Args:     int iObjectTeleporter
              `CObjectTeleporter` entity index.
            int i
              Array index.

  Returns:  char[]
              String residing at `m_teleportWhereName[ i ]`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock char[] CObjectTeleporter_GetTeleportWhereElement( int iObjectTeleporter, int i )
{
    Address pTeleportWhereName = view_as< Address >( GetEntData( iObjectTeleporter, g_CObjectTeleporter_teleportWhereName_Offset, PTRSIZ ) );
    Address psz                = DereferencePointer( pTeleportWhereName  + view_as< Address >( i * PTRSIZ ) );

    char sz[ 64 ];
    LoadStringFromAddress( psz, sz, sizeof( sz ) );
    return sz;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_GetTeleportWhereCount

  Summary:  This function returns the number of entries in a
            `CObjectTeleporter`'s `m_teleportWhereName` array.

  Args:     int iObjectTeleporter
              Index of the `CObjectTeleporter` entity whose number
              of entries in their `m_teleportWhereName` string
              array to get.

  Returns:  int
              Integer value representing the number of `TeleportWhere`
              string values `iObjectTeleporter` has.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int CObjectTeleporter_GetTeleportWhereCount( int iObjectTeleporter )
{
    return CUtlVector_Count( CObjectTeleporter_GetTeleportWhere( iObjectTeleporter ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CObjectTeleporter_SetTeleportWhere

  Summary:  This function set's a `CObjectTeleporter` entity's
            `m_teleportWhereName`.

  Args:     int iObjectTeleporter
              `CObjectTeleporter` entity index.
            Address CTFBot_pTeleportWhereName
              Memory address at which a `CTFBot`'s `m_teleportWhereName`
              array resides.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void CObjectTeleporter_SetTeleportWhere( int iObjectTeleporter, Address CTFBot_pTeleportWhereName )
{
#if defined WIN32
    SDKCall( g_hfnCObjectTeleporter_SetTeleportWhere, iObjectTeleporter, CTFBot_pTeleportWhereName );
#else
#pragma unused CTFBot_pTeleportWhereName

    int iBuilder = TF2_GetObjectBuilder( iObjectTeleporter );
    int iBot     = GetClientFromSerial( g_aPlayerAttribs[ iBuilder ].iBotSerial );

    Address CObjectTeleporter_pTeleportWhereName = CObjectTeleporter_GetTeleportWhere( iObjectTeleporter );

    int n = CTFBot_GetTeleportWhereCount( iBot );
    for ( int i = 0; i < n; i++ )
    {
        CopyAndAddToTail( CObjectTeleporter_pTeleportWhereName, CTFBot_GetTeleportWhereElement( iBot, i ) );
    }
#endif
}

#if !defined WIN32
/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CopyAndAddToTail

  Summary:  This function appends a string to a `CUtlStringList`
            variable.

  Args:     Address pThis
              `CUtlStringList` variable memory address.
            const char[] sz
              A string value to append to the list.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void CopyAndAddToTail( Address pThis, const char[] sz )
{
    SDKCall( g_hfnCUtlStringList_CopyAndAddToTail, pThis, sz );
}
#endif

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFBot_ShouldQuickBuild

  Summary:  This function gets a `CTFBot` entity's `m_bForceQuickBuild`
            value.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  bool
              If the bot should quick build, the return value will
              be `true`.

              If the bot shouldn't quick build, the return value
              will be `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool CTFBot_ShouldQuickBuild( int iBot )
{
    return SDKCall( g_hfnCTFBot_ShouldQuickBuild, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ForceQuickBuild

  Summary:  This function sets an object entity's `m_bForceQuickBuild`
            member variable to `true`.

  Args:     int iObject
              `CBaseObject` entity index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ForceQuickBuild( int iObject )
{
    SetEntData( iObject, g_CBaseObject_bForceQuickBuild_Offset, true, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetMaxHealthForCurrentLevel

  Summary:  This function returns the maximum health a building can
            have depending on its current level.

  Args:     int iObject
              `CBaseObject` entity index.

  Returns:  int
              Maximum health the building can have depending on its
              current level.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetMaxHealthForCurrentLevel( int iObject )
{
    return SDKCall( g_hfnCBaseObject_GetMaxHealthForCurrentLevel, iObject );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ZoomOut

  Summary:  This function forces a `CTFSniperRifle` weapon entity
            to zoom out.

  Args:     int iSniperRifle
              `CTFSniperRifle` entity index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ZoomOut( int iSniperRifle )
{
    SDKCall( g_hfnCTFSniperRifle_ZoomOut, iSniperRifle );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: DispatchParticleEffect

  Summary:  This function creates and attaches a particle effect to
            an entity.

  Args:     const char[] szParticleName
              String representing the name of the particle.
            ParticleAttachment_t iAttachType
              Particle attachment method.
            int iEntity
              Entity index to which to attach the particle.
            const char[] szAttachmentName
              String representing the attachment point.
            bool bResetAllParticlesOnEntity
              If `true`, all other particles attached to the entity
              will be reset.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void DispatchParticleEffect(
    const char[]         szParticleName,
    ParticleAttachment_t iAttachType,
    int                  iEntity,
    const char[]         szAttachmentName,
    bool                 bResetAllParticlesOnEntity = false
    )
{
    SDKCall( g_hfnDispatchParticleEffect, szParticleName, iAttachType, iEntity, szAttachmentName, bResetAllParticlesOnEntity );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetEffects

  Summary:  This function retrieves an entity's effect flags.

  Args:     int iEntity
              Entity index.

  Returns:  int
              A bit field of the active effects on the entity.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetEffects( int iEntity )
{
    return GetEntProp( iEntity, Prop_Send, "m_fEffects" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: AddEffects

  Summary:  This function adds one or more effects to an entity.

  Args:     int iEntity
              Entity index.
            int nEffects
              A bitmask of effects to add to the entity.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void AddEffects( int iEntity, int nEffects )
{
    SetEntProp( iEntity, Prop_Send, "m_fEffects", ( GetEffects( iEntity ) | nEffects ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: RemoveEffects

  Summary:  This function removes one or more effects from an entity.

  Args:     int iEntity
              Entity index.
            int nEffects
              A bitmask of effects to remove from the entity.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void RemoveEffects( int iEntity, int nEffects )
{
    SetEntProp( iEntity, Prop_Send, "m_fEffects", ( GetEffects( iEntity ) & ~nEffects ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ClearEffects

  Summary:  This function removes all effects from an entity.

  Args:     int iEntity
              Entity index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ClearEffects( int iEntity )
{
    SetEntProp( iEntity, Prop_Send, "m_fEffects", 0 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsEffectActive

  Summary:  This function determines whether one or more effects
            are active on an entity.

  Args:     int iEntity
              Entity index.
            int nEffects
              A bitmask of effects to test against.

  Returns:  bool
              If the effect(s) are active, the return value is
              `true`.

              If the effect(s) are not active, the return value is
              `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsEffectActive( int iEntity, int nEffects )
{
    return ( GetEffects( iEntity ) & nEffects );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: UpdateClientData

  Summary:  This function resends any changed player HUD info to
            the client.

  Args:     int iEntity
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void UpdateClientData( int iClient )
{
    SDKCall( g_hfnCBasePlayer_UpdateClientData, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SnapEyeAngles

  Summary:  This function changes a client's view angles.

  Args:     int iClient
              Client index.
            float angViewAngles[ 3 ]
              New view angles.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SnapEyeAngles( int iClient, float angViewAngles[ 3 ] )
{
    SDKCall( g_hfnCBasePlayer_SnapEyeAngles, iClient, angViewAngles );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ForcePlayerViewAngles

  Summary:  This function forces a client's view angles to change.

  Args:     int iClient
              Client index.
            float angTeleportAngles[ 3 ]
              New view angles.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ForcePlayerViewAngles( int iClient, float angTeleportAngles[ 3 ] )
{
    BfWrite hMsg = UserMessageToBfWrite( StartMessageOne( "ForcePlayerViewAngles", iClient, USERMSG_BLOCKHOOKS ) );
    hMsg.WriteByte( 0x01 ); // Reserved space for flags.
    hMsg.WriteByte( iClient );
    hMsg.WriteAngles( angTeleportAngles );
    EndMessage();
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetObserverTarget

  Summary:  This function sets a player's observer target.

  Args:     int iClient
              Client index.
            int iTarget
              Target entity index.

  Returns:  bool
              If the client's observer target has been successfully
              set, the return value is `true`.

              If the client's observer target failed to be set, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool SetObserverTarget( int iClient, int iTarget )
{
    return SDKCall( g_hfnCTFPlayer_SetObserverTarget, iClient, iTarget );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: PlaySpecificSequence

  Summary:  This function forces a player to play a specific
            animation.

  Args:     int iClient
              Client index.
            const char[] szAnimationName
              A string representing an activity or sequence.

  Returns:  bool
              If the animation was found and played, the return
              value is `true`.

              If the animation was not found and player, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool PlaySpecificSequence( int iClient, const char[] szAnimationName )
{
    return SDKCall( g_hfnCTFPlayer_PlaySpecificSequence, iClient, szAnimationName );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: DoAnimationEvent

  Summary:  This function initiates an animation event on a client.

  Args:     int iClient
              Client index.
            PlayerAnimEvent_t eEvent
              Animation event.
            int nData
              Animation event data.

  Returns:  bool
              If the animation was found and played, the return
              value is `true`.

              If the animation was not found and player, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void DoAnimationEvent( int iClient, PlayerAnimEvent_t eEvent, int nData = 0 )
{
    SDKCall( g_hfnCTFPlayer_DoAnimationEvent, iClient, eEvent, nData );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetClosestCaptureZone

  Summary:  This function tries to find the closest `CCaptureZone`
            entity from the client.

  Args:     int iClient
              Client index.

  Returns:  int
              If the function succeeds to find a `CCaptureZone`
              entity, the return value is the entity's index.

              If the function failed to find a `CCaptureZone`
              entity, the return value is `-1`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetClosestCaptureZone( int iClient )
{
    return SDKCall( g_hfnCTFPlayer_GetClosestCaptureZone, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: LockPlayerInPlace

  Summary:  This function locks a player to the spot; they can't
            move, shoot, or be hurt.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void LockPlayerInPlace( int iClient )
{
    if ( GetEntProp( iClient, Prop_Data, "m_iPlayerLocked" ) )
    {
        return;
    }

    SetEntityFlags( iClient, GetEntityFlags( iClient ) | FL_GODMODE | FL_FROZEN );
    SetEntityMoveType( iClient, MOVETYPE_NONE );
    SetEntProp( iClient, Prop_Data, "m_iPlayerLocked", true );

    /*--------------------------------------------------------------------
      Force a client data update, so that anything that has been done to
      this player previously this frame won't get delayed in being sent.
    --------------------------------------------------------------------*/
    UpdateClientData( iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: UnlockPlayer

  Summary:  This function unlocks a previously locked player.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void UnlockPlayer( int iClient )
{
    if ( !GetEntProp( iClient, Prop_Data, "m_iPlayerLocked" ) )
    {
        return;
    }

    SetEntityFlags( iClient, GetEntityFlags( iClient ) & ~( FL_GODMODE | FL_FROZEN ) );
    SetEntityMoveType( iClient, MOVETYPE_WALK );
    SetEntProp( iClient, Prop_Data, "m_iPlayerLocked", false );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsPlayerLockedInPlace

  Summary:  This function determines whether a player is locked in
            place.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the player is locked in place, the return value
              is `true`.

              If the player is not locked in place, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsPlayerLockedInPlace( int iClient )
{
    return GetEntProp( iClient, Prop_Data, "m_iPlayerLocked" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsWeaponRestricted

  Summary:  This function determines whether a `CTFBot` entity is
            allowed to use a certain weapon.

  Args:     int iBot
              `CTFBot` entity index.
            HSCRIPT hScript
              HSCRIPT address of the weapon entity to test.

  Returns:  bool
              If the bot is not allowed to use the weapon, the
              return value is `true`.

              If the bot is allowed to use the weapon, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsWeaponRestricted( int iBot, HSCRIPT hScript )
{
    return SDKCall( g_hfnCTFBot_IsWeaponRestricted, iBot, hScript );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsBarrageAndReloadWeapon

  Summary:  This function determines if a weapon has a small clip
            and long reload cost (ie: rocket launcher, etc).

  Args:     int iBot
              `CTFBot` entity index.
            int iWeapon
              Weapon entity index. To test the bot's current weapon,
              pass `MY_CURRENT_GUN`.

  Returns:  bool
              If the weapon has a small clip and long reload cost
              (ie: rocket launcher, etc), the return value is `true`.

              If the weapon doesn't have a small clip and long
              reload cost (ie: rocket launcher, etc), the return
              value is `true`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsBarrageAndReloadWeapon( int iBot, int iWeapon )
{
    return SDKCall( g_hfnCTFBot_IsBarrageAndReloadWeapon, iBot, iWeapon );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ShouldAutoJump

  Summary:  This function determines whether a `CTFBot` entity
            should initiate an automatic jump.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  bool
              If the bot should automatically jump, the return
              value is `true`.

              If the bot shouldn't automatically jump, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool ShouldAutoJump( int iBot )
{
    return SDKCall( g_hfnCTFBot_ShouldAutoJump, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetBehaviorFlag

  Summary:  This function sets a bot's behavior flags.

  Args:     int iBot
              `CTFBot` entity index.
            int iFlags
              Behavior flags.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetBehaviorFlag( int iBot, int iFlags )
{
    SDKCall( g_hfnCTFBot_SetBehaviorFlag, iBot, iFlags );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ClearBehaviorFlag

  Summary:  This function unsets a bot's behavior flags.

  Args:     int iBot
              `CTFBot` entity index.
            int iFlags
              Behavior flags.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ClearBehaviorFlag( int iBot, int iFlags )
{
    SDKCall( g_hfnCTFBot_ClearBehaviorFlag, iBot, iFlags );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsBehaviorFlagSet

  Summary:  This function determines whether a behavior flag is set
            on a bot.

  Args:     int iBot
              `CTFBot` entity index.
            int iFlags
              Behavior flags to test.

  Returns:  bool
              If the behavior flags are set on the bot, the return
              value is `true`.

              If the behavior flags are not set on the bot, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsBehaviorFlagSet( int iBot, int iFlags )
{
    return SDKCall( g_hfnCTFBot_IsBehaviorFlagSet, iBot, iFlags );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetFlagCarrierUpgradeLevel

  Summary:  This function sets the global flag carrier upgrade level.

  Args:     int nLevel
              Flag carrier upgrade level.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetFlagCarrierUpgradeLevel( int nLevel )
{
    SetEntProp( g_iObjectiveResource, Prop_Send, "m_nFlagCarrierUpgradeLevel", nLevel );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetFlagCarrierUpgradeLevel

  Summary:  This function gets the global flag carrier upgrade level.

  Returns:  int
              Flag carrier upgrade level.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetFlagCarrierUpgradeLevel()
{
    return GetEntProp( g_iObjectiveResource, Prop_Send, "m_nFlagCarrierUpgradeLevel" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetBaseMvMBombUpgradeTime

  Summary:  This function sets the global base bomb upgrade time.

  Args:     float flTime
              Base bomb upgrade time.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetBaseMvMBombUpgradeTime( float flTime )
{
    SetEntPropFloat( g_iObjectiveResource, Prop_Send, "m_flMvMBaseBombUpgradeTime", flTime );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetBaseMvMBombUpgradeTime

  Summary:  This function gets the global base bomb upgrade time.

  Returns:  float
              Base bomb upgrade time.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetBaseMvMBombUpgradeTime()
{
    return GetEntPropFloat( g_iObjectiveResource, Prop_Send, "m_flMvMBaseBombUpgradeTime" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetNextMvMBombUpgradeTime

  Summary:  This function sets the global next bomb upgrade time.

  Args:     float flTime
              Next bomb upgrade time.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetNextMvMBombUpgradeTime( float flTime )
{
    SetEntPropFloat( g_iObjectiveResource, Prop_Send, "m_flMvMNextBombUpgradeTime", flTime );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetNextMvMBombUpgradeTime

  Summary:  This function gets the global next bomb upgrade time.

  Returns:  float
              Next bomb upgrade time.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetNextMvMBombUpgradeTime()
{
    return GetEntPropFloat( g_iObjectiveResource, Prop_Send, "m_flMvMNextBombUpgradeTime" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CanBotsAttackWhileInSpawnRoom

  Summary:  This function determines whether the current mission
            allows invaders to attack while in spawn.

  Returns:  bool
              If invaders can attack while in spawn, the return
              value is `true`.

              If invaders cannot attack while in spawn, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool CanBotsAttackWhileInSpawnRoom()
{
    return GetEntData( g_iPopulationManager, g_CPopulationManager_canBotsAttackWhileInSpawnRoom_Offset, 1 );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ResetRageBuffs

  Summary:  This function resets a client's rage buffs.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ResetRageBuffs( int iClient )
{
    SDKCall( g_hfnCTFPlayerShared_ResetRageBuffs, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetDisguiseTarget

  Summary:  This function gets a client's disguise target.

  Args:     int iClient
              Client index.

  Returns:  int
              Client index of the entity `iClient` is disguised as.

              If `iClient` is not disguised, the return value is `-1`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock int GetDisguiseTarget( int iClient )
{
    return GetEntPropEnt( iClient, Prop_Send, "m_hDisguiseTarget" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsRangeLessThan

  Summary:  This function determines whether the range between two
            entities is less than a specified value.

  Args:     int iEntity1
              Entity index.
            int iEntity1
              Entity index.
            float flRange
              A float value against which to compare the computed
              range between the two entities.

  Returns:  bool
              If the range between the two entities is less than
              `flRange`, the return value is `true`.

              If the range between the two entities is greater than
              or equal to `flRange`, the return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsRangeLessThan( int iEntity1, int iEntity2, float flRange )
{
    float vecCenter1[ 3 ], vecCenter2[ 3 ];
    vecCenter1 = WorldSpaceCenter( iEntity1 );
    vecCenter2 = WorldSpaceCenter( iEntity2 );

    return GetVectorDistance( vecCenter1, vecCenter2, true ) < Sqr( flRange );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsRangeLessThanVec

  Summary:  This function determines whether the range between a
            client and a position vector is less than a specified
            value.

  Args:     int iClient
              Client index.
            const float vecPosition[ 3 ]
              Position vector.
            float flRange
              A float value against which to compare the computed
              range between the client and position vector.

  Returns:  bool
              If the range between the the client and position
              vector is less than `flRange`, the return value is
              `true`.

              If the range between the the client and position
              vector is greater than `flRange`, the return value is
              `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsRangeLessThanVec( int iClient, const float vecPosition[ 3 ], float flRange )
{
    float vecOrigin[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );

    return GetVectorDistance( vecOrigin, vecPosition, true ) < Sqr( flRange );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsRangeGreaterThan

  Summary:  This function determines whether the range between two
            entities is greater than a specified value.

  Args:     int iEntity1
              Entity index.
            int iEntity2
              Entity index.
            float flRange
              A float value against which to compare the computed
              range between the two entities.

  Returns:  bool
              If the range between the two entities is greater than
              `flRange`, the return value is `true`.

              If the range between the two entities is less than
              or equal to `flRange`, the return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsRangeGreaterThan( int iEntity1, int iEntity2, float flRange )
{
    float vecCenter1[ 3 ], vecCenter2[ 3 ];
    vecCenter1 = WorldSpaceCenter( iEntity1 );
    vecCenter2 = WorldSpaceCenter( iEntity2 );

    return GetVectorDistance( vecCenter1, vecCenter2, true ) > Sqr( flRange );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsRangeGreaterThanVec

  Summary:  This function determines whether the range between a
            client and a position vector is greater than a specified
            value.

  Args:     int iClient
              Client index.
            const float vecPosition[ 3 ]
              Position vector.
            float flRange
              A float value against which to compare the computed
              range between the client and position vector.

  Returns:  bool
              If the range between the the client and position
              vector is greater than `flRange`, the return value is
              `true`.

              If the range between the the client and position
              vector is less than `flRange`, the return value is
              `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsRangeGreaterThanVec( int iClient, const float vecPosition[ 3 ], float flRange )
{
    float vecOrigin[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );

    return GetVectorDistance( vecOrigin, vecPosition, true ) > Sqr( flRange );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: PlayThrottledAlert

  Summary:  This function plays an alert, taking into consideration
            the delay since the previous alert.

  Args:     int iTeam
              Team number. To broadcast to every client pass `255`.
            const char[] szSound
              A string representing a game sound.
            float flDelayBeforeNext
              Value representing in how many seconds should a new
              alert be allowed to be played

  Returns:  bool
              If the alert was played, the return value is `true`.

              If the alert was not played, the return value is
              `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool PlayThrottledAlert( int iTeam, const char[] szSound, float flDelayBeforeNext )
{
    return SDKCall( g_hfnCTeamplayRoundBasedRules_PlayThrottledAlert, iTeam, szSound, flDelayBeforeNext );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: BroadcastSound

  Summary:  This function broadcasts a sound to all the players of
            a team.

  Args:     int iTeam
              Team number. To broadcast to every client pass `255`.
            const char[] szSound
              A string representing a game sound.
            int iAdditionalSoundFlags
              Additional sound flags.
            int iPlayer
              Index of client broadcasting the sound.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void BroadcastSound( int iTeam, const char[] szSound, int iAdditionalSoundFlags = 0, int iPlayer = -1 )
{
    SDKCall( g_hfnCTFGameRules_BroadcastSound, iTeam, szSound, iAdditionalSoundFlags, iPlayer );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HaveAllPlayersSpeakConceptIfAllowed

  Summary:  This function will have all the players of a given team
            speak a concept if they are allowed.

  Args:     int iConcept
              An integer value representing the concept.
            int iTeam
              Team number.
            const char[] szModifiers
              A string representing sound modifiers.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void HaveAllPlayersSpeakConceptIfAllowed( int iConcept, int iTeam = TFTeam_Unassigned, const char[] szModifiers = NULL_STRING )
{
    SDKCall( g_hfnCMultiplayRules_HaveAllPlayersSpeakConceptIfAllowed, iConcept, iTeam, szModifiers );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsAllowedToTaunt

  Summary:  This function determines whether a player is allowed
            to initiate a taunt this frame.

  Args:     int iClient
              Client index.

  Returns:  bool
              If the player is allowed to initiate a taunt, the
              return value is `true`.

              If the player is not allowed to initiate a taunt, the
              return value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool IsAllowedToTaunt( int iClient )
{
    return SDKCall( g_hfnCTFPlayerShared_IsAllowedToTaunt, iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HandleTauntCommand

  Summary:  This function will try to make a player perform an
            equipped taunt.

  Args:     int iClient
              Client index.
            int iTauntSlot
              Taunt inventory slot.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void HandleTauntCommand( int iClient, int iTauntSlot = 0 )
{
    SDKCall( g_hfnCTFPlayer_HandleTauntCommand, iClient, iTauntSlot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CycleResistType

  Summary:  This function cycles a medigun's resist type.

  Args:     int iWeaponMedigun
              Medigun index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void CycleResistType( int iWeaponMedigun )
{
    SDKCall( g_hfnCWeaponMedigun_CycleResistType, iWeaponMedigun );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetResistType

  Summary:  This function gets a medigun's resist type.

  Args:     int iWeaponMedigun
              Medigun index.

  Returns:  medigun_resist_types_t
              A value representing the medigun's resist type.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock medigun_resist_types_t GetResistType( int iWeaponMedigun )
{
    return SDKCall( g_hfnCWeaponMedigun_GetResistType, iWeaponMedigun );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetMedigunType

  Summary:  This function gets a medigun's weapon type.

  Args:     int iWeaponMedigun
              Medigun index.

  Returns:  medigun_weapontypes_t
              A value representing the medigun's weapon type.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock medigun_weapontypes_t GetMedigunType( int iWeaponMedigun )
{
    int iMode = 0;
    iMode     = TF2Attrib_HookValueInt( iMode, "set_weapon_mode", iWeaponMedigun );
    return view_as< medigun_weapontypes_t >( iMode );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetMaxVisionRangeOverride

  Summary:  This function sets a bot's maximum vision range.

  Args:     int iBot
              `CTFBot` entity index.
            float flRange
              Maximum vision range.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetMaxVisionRangeOverride( int iBot, float flRange )
{
    SDKCall( g_hfnCTFBot_SetMaxVisionRangeOverride, iBot, flRange );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetMaxVisionRangeOverride

  Summary:  This function gets a bot's maximum vision range.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  float
              `iBot`'s maximum vision range.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock float GetMaxVisionRangeOverride( int iBot )
{
    return SDKCall( g_hfnCTFBot_GetMaxVisionRangeOverride, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetLastKnownArea

  Summary:  This function get's a bot's last known nav area.

  Args:     int iBot
              `CTFBot` entity index.

  Returns:  Address
              Memory address of a `CTFNavArea` object.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock Address GetLastKnownArea( int iBot )
{
    return SDKCall( g_hfnCTFBot_GetLastKnownArea, iBot );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: HasAttributeTF

  Summary:  This function determines whether a nav area has one or
            more flags.

  Args:     Address pNavArea
              Memory address of a `CTFNavArea` object.
            int iFlags
              Bitmask of `TFNavAttributeType` values.

  Returns:  bool
              If the nav area has `iFlags` set, the return value
              is `true`.

              If the nav area does not have `iFlags` set, the return
              value is `false`.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock bool HasAttributeTF( Address pNavArea, int iFlags )
{
    return SDKCall( g_hfnCTFNavArea_HasAttributeTF, pNavArea, iFlags );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: Capture

  Summary:  This function tries to capture a control zone. If the
            capturing entity `iOther` is not a player, does not
            have the flag, or the flag cannot be captured, this
            function does not do anything.

  Args:     int iCaptureZone
              `CCaptureZone` entity index.
            int iOther
              Index of entity capturing.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void Capture( int iCaptureZone, int iOther )
{
    SDKCall( g_hfnCCaptureZone_Capture, iCaptureZone, iOther );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: StartIdleSound

  Summary:  This function starts the appropriate idle sound on a
            client.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void StartIdleSound( int iClient )
{
    if ( IsFakeClient( iClient ) )
    {
        SDKCall( g_hfnCTFBot_StartIdleSound, iClient );
    }
    else
    {
        StopIdleSound( iClient );

        if ( IsMiniBoss( iClient ) )
        {
            int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

            char szSoundName[ 32 ] = "";
            switch ( TF2_GetPlayerClass( iClient ) )
            {
            case TFClass_Heavy:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantHeavyLoop" );

            case TFClass_Soldier:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantSoldierLoop" );

            case TFClass_DemoMan:
                if ( GetPrevMission( iBot ) == MISSION_DESTROY_SENTRIES )
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.SentryBusterLoop" );
                }
                else
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantDemomanLoop" );
                }

            case TFClass_Scout:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantScoutLoop" );

            case TFClass_Pyro:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantPyroLoop" );
            }

            if ( !StrEmpty( szSoundName ) )
            {
                EmitGameSoundToAll( szSoundName, iClient );
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: StopIdleSound

  Summary:  This function stops the appropriate idle sound on a
            client.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void StopIdleSound( int iClient )
{
    if ( IsFakeClient( iClient ) )
    {
        // `!TFGameRules()->IsMannVsMachineMode()` triggers an early return after stopping the idle sound
        GameRules_SetProp( "m_bPlayingMannVsMachine", false, 1 );
        StartIdleSound( iClient );
        GameRules_SetProp( "m_bPlayingMannVsMachine", true, 1 );
    }
    else
    {
        if ( IsMiniBoss( iClient ) )
        {
            int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

            char szSoundName[ 32 ] = "";
            switch ( TF2_GetPlayerClass( iClient ) )
            {
            case TFClass_Heavy:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantHeavyLoop" );

            case TFClass_Soldier:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantSoldierLoop" );

            case TFClass_DemoMan:
                if ( GetPrevMission( iBot ) == MISSION_DESTROY_SENTRIES )
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.SentryBusterLoop" );
                }
                else
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantDemomanLoop" );
                }

            case TFClass_Scout:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantScoutLoop" );

            case TFClass_Pyro:
                strcopy( szSoundName, sizeof( szSoundName ), "MVM.GiantPyroLoop" );
            }

            if ( !StrEmpty( szSoundName ) )
            {
                EmitGameSoundToAll( szSoundName, iClient, SND_STOP );
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetPassEntity

  Summary:  This function gets the memory address of a filter's
            pass entity.

  Args:     Address pFilter
              Filter memory address.

  Returns:  Address
              Pointer to an `IHandleEntity` object.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock Address GetPassEntity( Address pFilter )
{
    return LoadFromAddress( pFilter + view_as< Address >( g_CTraceFilterSimple_pPassEnt_Offset ), NumberType_Pointer );
}
