/*+===================================================================
  File:    ACTIONHOOKS.INC

  Summary: This file contains NextBot action hook callback functions
           used by the bot control plugin.

  Origin:  Created by Bintr on 20.07.2026.
===================================================================+*/

#if defined _botcontrol_actionhooks_included
    #endinput
#endif
#define _botcontrol_actionhooks_included

#include <sourcemod>
#include <actions>

#include "globals"

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: CTFBotMissionSuicideBomber_Update

  Summary:  This function is called before every
            `CTFBotMissionSuicideBomber::Update` call and its purpose
            is to prevent a controlled bot from detonating.

  Args:     BehaviorAction pThis
              Address of the calling `CTFBotDeliverFlag` class.
            int iBot
              `CTFBot` client index.
            float flInterval
              Interval at which this function is called.
            ActionResult Result
              Action result.

  Returns:  Action
              Action the NextBot should take or `Plugin_Continue`
              to let the game's function be executed.
-----------------------------------------------------------------F-F*/
Action CTFBotMissionSuicideBomber_Update( BehaviorAction pThis, int iBot, float flInterval, ActionResult Result )
{
    if ( g_aBotAttribs[ iBot ].IsControlled() )
    {
        return pThis.Continue();
    }

    return Plugin_Continue;
}

static float g_flPrevIntervalTo1stUpgrade;

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: CTFBotDeliverFlag_OnStart

  Summary:  This function is called before every
            `CTFBotDeliverFlag::OnStart` call and its purpose is to
            synchronize the class's `m_upgradeTimer` member
            variable with the next bomb upgrade time.

  Args:     BehaviorAction pThis
              Address of the calling `CTFBotDeliverFlag` class.
            int iBot
              `CTFBot` client index.
            BehaviorAction PriorAction
              Previous `BehaviorAction` the bot had.
            ActionResult Result
              Action result.

  Returns:  Action
              Action the NextBot should take or `Plugin_Continue`
              to let the game's function be executed.
-----------------------------------------------------------------F-F*/
Action CTFBotDeliverFlag_OnStart( BehaviorAction pThis, int iBot, BehaviorAction PriorAction, ActionResult Result )
{
    if ( g_aBotAttribs[ iBot ].bRestoredAsFlagCarrier && !IsMiniBoss( iBot ) )
    {
        // Save the original value so we can restore it in the post hook
        g_flPrevIntervalTo1stUpgrade = tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.FloatValue;

        // Make `m_upgradeTimer` sychronize with the next upgrade time
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.SetFloat( max( GetNextMvMBombUpgradeTime() - GetGameTime(), 0.0 ) );
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: CTFBotDeliverFlag_OnStartPost

  Summary:  This function is called after every
            `CTFBotDeliverFlag::OnStart` call and its purpose is to
            synchronize the class's `m_upgradeLevel` member
            variable with current flag carrier upgrade level and
            restore the value of the `tf_mvm_bot_flag_carrier_interval_to_1st_upgrade`
            console variable.

  Args:     BehaviorAction pThis
              Address of the calling `CTFBotDeliverFlag` class.
            int iBot
              `CTFBot` client index.
            BehaviorAction PriorAction
              Previous `BehaviorAction` the bot had.
            ActionResult Result
              Action result.

  Returns:  Action
              Action the NextBot should take or `Plugin_Continue`
              to let the game's function be executed.
-----------------------------------------------------------------F-F*/
Action CTFBotDeliverFlag_OnStartPost( BehaviorAction pThis, int iBot, BehaviorAction PriorAction, ActionResult Result )
{
    if ( g_aBotAttribs[ iBot ].bRestoredAsFlagCarrier && !IsMiniBoss( iBot ) )
    {
        // Copy over the upgrade level
        StoreToAddress( view_as< Address >( pThis ) + view_as< Address >( g_CTFBotDeliverFlag_upgradeLevel_Offset ), GetFlagCarrierUpgradeLevel(), NumberType_Int32 );

        // Restore the value to whatever it was before we changed it
        tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.SetFloat( g_flPrevIntervalTo1stUpgrade );
    }

    g_aBotAttribs[ iBot ].bRestoredAsFlagCarrier = false;

    return Plugin_Continue;
}
