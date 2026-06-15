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
#include <sdktools>

#include "globals"
#include "const"

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
#define IsPlayerIndex(%1) ( 0 < %1 <= MaxClients )

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
    return view_as< bool >( GameRules_GetProp( "m_bPlayingMannVsMachine" ) );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SetDeployingBombState

  Summary:  This function sets a player's bomb deploying state.

  Args:     int iClient
              Index of the client whose `m_nDeployingBombState`
              property must be set.
            BombDeployingState_t nDeployingBombState
              The value to which to set `iClient`'s
              `m_nDeployingBombState` property.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void SetDeployingBombState( int iClient, BombDeployingState_t nDeployingBombState )
{
    SetEntData( iClient, g_nDeployingBombState_Offset, nDeployingBombState );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: GetDeployingBombState

  Summary:  This function gets a player's bomb deploying state.

  Args:     int iClient
              Index of the client whose `m_nDeployingBombState`
              to get.

  Returns:  BombDeployingState_t
              The deploying bomb state the player is currently in.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock BombDeployingState_t GetDeployingBombState( int iClient )
{
    return view_as< BombDeployingState_t >( GetEntData( iClient, g_nDeployingBombState_Offset ) );
}
