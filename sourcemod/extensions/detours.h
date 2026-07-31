/*+===================================================================
  File:      DETOURS.H

  Summary:   This file contains the implementation of detour
             functions. Due to how detours are implemented, we
             cannot have a separate cpp file for them.

  Origin:    Written by Bintr on 30.07.2026.
===================================================================+*/

#ifndef _INCLUDE_BOTCONTROL_DETOURS_H_
#define _INCLUDE_BOTCONTROL_DETOURS_H_

#include "extension.h"

#include <CDetour/detours.h>

#include <cbase.h>
#include <tf/bot/tf_bot.h>
#include <tf_objective_resource.h>
#include <NextBot/NextBotBehavior.h>

extern CDetour* g_pCTFBotDeliverFlag_OnStart;

extern sp_pubvar_t* g_aBotAttribs;
typedef struct _BOTATTRIBUTES
{
    int  iPlayerSerial;
    bool bBlockFlagEvent;
} BOTATTRIBUTES, *PBOTATTRIBUTES;

DETOUR_DECL_MEMBER2( CTFBotDeliverFlag_OnStart, ActionResult< CTFBot >, CTFBot*, me, Action< CTFBot >*, priorAction )
{
    if ( !sm_botcontrol_enabled->GetBool() )
    {
        return DETOUR_MEMBER_CALL( CTFBotDeliverFlag_OnStart )( me, priorAction );
    }

    float flPrevIntervalTo1stUpgrade;

#pragma region Pre Hook

    int  iBot                     = gamehelpers->EntityToBCompatRef( me );
    PBOTATTRIBUTES pBotAttributes = reinterpret_cast< PBOTATTRIBUTES >( g_aBotAttribs->offs );

    /*--------------------------------------------------------------------
      If the bot just started delivering the flag and it has
      `bBlockFlagEvent` set, then this is the bot that got restored.
    --------------------------------------------------------------------*/
    if ( pBotAttributes[ iBot ].bBlockFlagEvent && !me->IsMiniBoss() )
    {
        // Save the original value so we can restore it in the post hook
        flPrevIntervalTo1stUpgrade = tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->GetFloat();

        // Make `m_upgradeTimer` sychronize with the next upgrade time
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->SetValue( Max< float >( TFObjectiveResource()->GetNextMvMBombUpgradeTime() - gpGlobals->curtime, 0.f ) );
    }

#pragma endregion

    ActionResult< CTFBot > Result = DETOUR_MEMBER_CALL( CTFBotDeliverFlag_OnStart )( me, priorAction );

#pragma region Post Hook

    if ( pBotAttributes[ iBot ].bBlockFlagEvent && !me->IsMiniBoss() )
    {
        // Copy over the upgrade level
        *reinterpret_cast< int* >( this + g_CTFBotDeliverFlag_upgradeLevel_Offset ) = TFObjectiveResource()->GetFlagCarrierUpgradeLevel();

        // Restore the value to whatever it was before we changed it
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade->SetValue( flPrevIntervalTo1stUpgrade );
    }

#pragma endregion

    return Result;
}

#endif // _INCLUDE_BOTCONTROL_DETOURS_H_
