/*+===================================================================
  File:      EXTENSION.CPP

  Summary:   This extension is a part of the [TF2] MvM Bot Control
             plugin and helps perform actions that otherwise cannot be
             accomplished in SourcePawn.

  Origin:    Written by Bintr on 27.07.2026.
===================================================================+*/

#include <cbase.h>
#include <icvar.h>
#include <tf/bot/tf_bot.h>
#include <tf_objective_resource.h>
#include <NextBot/NextBotBehavior.h>

#include <IGameConfigs.h>
#include <IPluginSys.h>
#include <iplayerinfo.h>
#include <CDetour/detours.h>
#include <smsdk_ext.h>

#include "extension.h"

#pragma region Globals

IBotControl g_BotControl; // Global singleton for extension's main interface
SMEXT_LINK( &g_BotControl );

IPlugin* g_pBotControlPl = nullptr;

CDetour* g_pCTFBotDeliverFlag_OnStart;

int g_CTFBotDeliverFlag_upgradeLevel_Offset;

const ConVar* sm_botcontrol_enabled                           = nullptr;
const ConVar* tf_deploying_bomb_delay_time                    = nullptr;
ConVar*       tf_mvm_bot_flag_carrier_interval_to_1st_upgrade = nullptr;

sp_pubvar_t* g_aBotAttribs;

#pragma endregion

DETOUR_DECL_MEMBER2( CTFBotDeliverFlag_OnStart, ActionResult< CTFBot >, CTFBot*, me, Action< CTFBot >*, priorAction )
{
    float flPrevIntervalTo1stUpgrade;

    if ( !sm_botcontrol_enabled->GetBool() )
    {
        return DETOUR_MEMBER_CALL( CTFBotDeliverFlag_OnStart )( me, priorAction );
    }

#pragma region Pre Hook

    int iBot = gamehelpers->EntityToBCompatRef( me );
    /*--------------------------------------------------------------------
      If the bot just started delivering the flag and it has
      `bBlockFlagEvent` set, then this is the bot that got restored.
    --------------------------------------------------------------------*/
    if ( static_cast< bool >( g_aBotAttribs->offs + ( iBot * ( sizeof( int ) + sizeof( bool ) ) ) + sizeof( int ) ) && !me->IsMiniBoss() )
    {
        // Save the original value so we can restore it in the post hook
        flPrevIntervalTo1stUpgrade = tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->GetFloat();

        // Make `m_upgradeTimer` sychronize with the next upgrade time
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->SetValue( Max< float>( TFObjectiveResource()->GetNextMvMBombUpgradeTime() - gpGlobals->curtime, 0.0 ) );
    }

#pragma endregion

    ActionResult< CTFBot > Result = DETOUR_MEMBER_CALL( CTFBotDeliverFlag_OnStart )( me, priorAction );

#pragma region Post Hook

    if ( static_cast< bool >( g_aBotAttribs->offs + ( iBot * ( sizeof( int ) + sizeof( bool ) ) ) + sizeof( int ) ) && !me->IsMiniBoss() )
    {
        void* pv;
#ifdef KE_ARCH_X86
        pv = this + g_CTFBotDeliverFlag_upgradeLevel_Offset;
#else
        pv = g_pSM->FromPseudoAddress( reinterpret_cast< uint32_t >( this ) + g_CTFBotDeliverFlag_upgradeLevel_Offset );
#endif

        // Copy over the upgrade level
        *reinterpret_cast< int* >( pv ) = TFObjectiveResource()->GetFlagCarrierUpgradeLevel();

        // Restore the value to whatever it was before we changed it
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->SetValue( flPrevIntervalTo1stUpgrade );
    }

#pragma endregion

    return Result;

#pragma endregion
}

bool SDK_OnLoad( char* pszError, size_t cch, bool bLate )
{
    IGameConfig* pGameConfig;
    if ( !gameconfs->LoadGameConfigFile( "botcontrol", &pGameConfig, pszError, cch ) )
    {
        return false;
    }

    pGameConfig->GetOffset( "CTFBotDeliverFlag::m_upgradeLevel", &g_CTFBotDeliverFlag_upgradeLevel_Offset );

    gameconfs->CloseGameConfigFile( pGameConfig );

    CDetourManager::Init( g_pSM->GetScriptingEngine(), pGameConfig );
    DETOUR_CREATE_MEMBER( CTFBotDeliverFlag_OnStart, "CTFBotDeliverFlag::OnStart" );

    tf_deploying_bomb_delay_time                    = g_pCVar->FindVar( "tf_deploying_bomb_delay_time" );
    tf_mvm_bot_flag_carrier_interval_to_1st_upgrade = g_pCVar->FindVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" );

    g_pShareSys->RegisterLibrary( myself, "botcontrol.ext" );
    return true;
}

void SDK_OnUnload( void )
{
    g_pCTFBotDeliverFlag_OnStart->Destroy();
}

bool QueryRunning( char* pszError, size_t cch )
{
    if ( !g_pBotControlPl || ( sm_botcontrol_enabled && !sm_botcontrol_enabled->GetBool() ) )
    {
        ke::SafeStrcpy( pszError, cch, "Bot Control plugin is not loaded or disabled." );
        return false;
    }

    return true;
}

bool SDK_OnMetamodLoad( ISmmAPI* ismm, char* error, size_t maxlen, bool bLate )
{
    GET_V_IFACE_CURRENT( GetEngineFactory, g_pCVar, ICvar, CVAR_INTERFACE_VERSION );
    gpGlobals = ismm->GetCGlobals();
}

void IPluginsListener_V1::OnPluginLoaded( IPlugin* pPlugin )
{
    if ( strcmp( pPlugin->GetPublicInfo()->name, "[TF2] MvM Bot Control" ) == 0 )
    {
        g_pBotControlPl = pPlugin;
        if ( !sm_botcontrol_enabled )
        {
            sm_botcontrol_enabled = g_pCVar->FindVar( "sm_botcontrol_enabled" );
        }

        // Find our `g_aBotAttribs` public variable
        uint32_t uIndex;
        pPlugin->GetRuntime()->FindPubvarByName( "g_aBotAttribs", &uIndex );
        pPlugin->GetRuntime()->GetPubvarByIndex( uIndex, &g_aBotAttribs );

        g_pCTFBotDeliverFlag_OnStart->EnableDetour();
    }
}

void IPluginsListener_V1::OnPluginUnloaded( IPlugin* pPlugin )
{
    if ( pPlugin == g_pBotControlPl )
    {
        g_pBotControlPl = nullptr;

        g_pCTFBotDeliverFlag_OnStart->DisableDetour();
    }
}
