/*+===================================================================
  File:      EXTENSION.CPP

  Summary:   This extension is a part of the [TF2] MvM Bot Control
             plugin and helps perform actions that otherwise cannot
             be accomplished in SourcePawn.

  Origin:    Written by Bintr on 27.07.2026.
===================================================================+*/

#include "extension.h"

#include <icvar.h>
#include <iplayerinfo.h>
#include <detours.h>
#include <smsdk_ext.h>

#include "listeners.h"
#include "detours.h"

CBotControl g_BotControl; // Global singleton for extension's main interface
SMEXT_LINK( &g_BotControl );

int g_CTFBotDeliverFlag_upgradeLevel_Offset;

const ConVar* sm_botcontrol_enabled = nullptr;
const ConVar* tf_deploying_bomb_delay_time = nullptr;
ConVar* tf_mvm_bot_flag_carrier_interval_to_1st_upgrade = nullptr;

bool CBotControl::SDK_OnLoad( char* pszError, size_t cch, bool bLate )
{
    IGameConfig* pGameConfig;
    if ( !gameconfs->LoadGameConfigFile( "botcontrol", &pGameConfig, pszError, cch ) )
    {
        return false;
    }

    pGameConfig->GetOffset( "CTFBotDeliverFlag::m_upgradeLevel", &g_CTFBotDeliverFlag_upgradeLevel_Offset );

    CDetourManager::Init( g_pSM->GetScriptingEngine(), pGameConfig );
    g_pCTFBotDeliverFlag_OnStart = DETOUR_CREATE_MEMBER( CTFBotDeliverFlag_OnStart, "CTFBotDeliverFlag::OnStart" );

    gameconfs->CloseGameConfigFile( pGameConfig );

    plsys->AddPluginsListener_V1( &g_PluginsListener );

    tf_deploying_bomb_delay_time                    = g_pCVar->FindVar( "tf_deploying_bomb_delay_time" );
    tf_mvm_bot_flag_carrier_interval_to_1st_upgrade = g_pCVar->FindVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" );

    g_pShareSys->RegisterLibrary( myself, "botcontrol.ext" );
    return true;
}

void CBotControl::SDK_OnUnload( void )
{
    plsys->RemovePluginsListener_V1( &g_PluginsListener );
    g_pCTFBotDeliverFlag_OnStart->Destroy();
}

bool CBotControl::QueryRunning( char* pszError, size_t cch )
{
    if ( !g_pBotControlPl || ( sm_botcontrol_enabled && !sm_botcontrol_enabled->GetBool() ) )
    {
        ke::SafeStrcpy( pszError, cch, "Bot Control plugin is not loaded or disabled." );
        return false;
    }

    return true;
}

bool CBotControl::SDK_OnMetamodLoad( ISmmAPI* ismm, char* error, size_t maxlen, bool bLate )
{
    GET_V_IFACE_CURRENT( GetEngineFactory, g_pCVar, ICvar, CVAR_INTERFACE_VERSION );
    gpGlobals = ismm->GetCGlobals();

    return true;
}
