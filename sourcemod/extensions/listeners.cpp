/*+===================================================================
  File:      LISTENERS.CPP

  Summary:   This file contains the implementation of the listener
             funtions.

  Classes:   CPluginsListener.

  Origin:    Written by Bintr on 30.07.2026.
===================================================================+*/

#include <CDetour/detours.h>

#include "extension.h"
#include "listeners.h"
#include "detours.h"

IPlugin* g_pBotControlPl = nullptr;

CPluginsListener g_PluginsListener;

void CPluginsListener::OnPluginLoaded( IPlugin* pPlugin )
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

void CPluginsListener::OnPluginUnloaded( IPlugin* pPlugin )
{
    if ( pPlugin == g_pBotControlPl )
    {
        g_pCTFBotDeliverFlag_OnStart->DisableDetour();

        g_pBotControlPl = nullptr;
    }
}
