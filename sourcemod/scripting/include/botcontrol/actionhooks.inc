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

  Summary:  This hook function prevents a controlled bot from
            detonating.

  Args:     BehaviorAction BotAction
              NextBot action.
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
Action CTFBotMissionSuicideBomber_Update( BehaviorAction BotAction, int iBot, float flInterval, ActionResult Result )
{
    if ( g_aBotAttribs[ iBot ].IsControlled() )
    {
        return BotAction.Continue();
    }

    return Plugin_Continue;
}
