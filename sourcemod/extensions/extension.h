/*+===================================================================
  File:      EXTENSION.H

  Summary:   This file contains the bot control extension's
             declaration.

  Origin:    Written by Bintr on 28.07.2026.
===================================================================+*/

#ifndef _INCLUDE_BOTCONTROL_EXTENSION_H_
#define _INCLUDE_BOTCONTROL_EXTENSION_H_

#include "smsdk_config.h"
#include <smsdk_ext.h>

#include <icvar.h>

extern int g_CTFBotDeliverFlag_upgradeLevel_Offset;

extern const ConVar* sm_botcontrol_enabled;
extern const ConVar* tf_deploying_bomb_delay_time;
extern ConVar* tf_mvm_bot_flag_carrier_interval_to_1st_upgrade;

/*C+C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C
  Class:    CBotControl

  Summary:  This class is used to implement various features
            that otherwise cannot be accomplished in SourcePawn.

  Methods:  SDK_OnLoad
              This function is called after the initial loading
              sequence has been processed.
            SDK_OnUnload
              This function is called right before the extension
              is unloaded.
            SDK_OnAllLoaded
              This function is called once all known extensions
              have been loaded. It is is a good idea to add
              natives here, if any are provided.
            SDK_OnPauseChange
              This function is called when the pause state is
              changed.
            QueryRunning
              This function is called when Core wants to know if
              the extension is working.
            SDK_OnMetamodLoad
              This function is called when Metamod is attached,
              before the extension version is called.
            SDK_OnMetamodPauseChange
              This function is called when Metamod's pause state
              is changing. By default this is blocked unless sent
              from SourceMod.
C---C---C---C---C---C---C---C---C---C---C---C---C---C---C---C---C-C*/
class CBotControl : public SDKExtension
{
public:
    virtual bool SDK_OnLoad( char* pszError, size_t cch, bool bLate );
    virtual void SDK_OnUnload( void );
    //virtual void SDK_OnAllLoaded( void );
    //virtual void SDK_OnPauseChange( bool bPaused );
    virtual bool QueryRunning( char* pszError, size_t cch );
public:
#if defined SMEXT_CONF_METAMOD
    virtual bool SDK_OnMetamodLoad( ISmmAPI* ismm, char* error, size_t maxlen, bool bLate );
    //virtual bool SDK_OnMetamodUnload( char* pszError, size_t cch );
    //virtual bool SDK_OnMetamodPauseChange( bool bPaused, char* pszError, size_t cch );
#endif
};

extern CBotControl g_BotControl;

#endif // _INCLUDE_BOTCONTROL_EXTENSION_H_
