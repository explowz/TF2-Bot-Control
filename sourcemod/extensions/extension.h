/*+===================================================================
  File:      EXTENSION.H

  Summary:   This file contains the bot control extension's
             declaration.

  Origin:    Written by Bintr on 28.07.2026.
===================================================================+*/

#ifndef _INCLUDE_SOURCEMOD_EXTENSION_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_H_

#include "smsdk_config.h"
#include "smsdk_ext.h"

/*I+I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I+++I
  Interface: IBotControl

  Summary:   This interface is used to implement various features
             that otherwise cannot be accomplished in SourcePawn.

  Methods:   bool SDK_OnLoad
               This function is called after the initial loading
               sequence has been processed.
             void SDK_OnUnload
               This function is called right before the extension
               is unloaded.
             void SDK_OnAllLoaded
               This function is called once all known extensions
               have been loaded. It is is a good idea to add
               natives here, if any are provided.
             void SDK_OnPauseChange
               This function is called when the pause state is
               changed.
             bool QueryRunning
               This function is called when Core wants to know if
               the extension is working.
             bool SDK_OnMetamodLoad
               This function is called when Metamod is attached,
               before the extension version is called.
             bool SDK_OnMetamodUnload
               This function is called when Metamod is detaching,
               after the extension version is called. By default
               this is blocked unless sent from SourceMod.
             bool SDK_OnMetamodPauseChange
               This function is called when Metamod's pause state
               is changing. By default this is blocked unless sent
               from SourceMod.
I---I---I---I---I---I---I---I---I---I---I---I---I---I---I---I---I-I*/
class IBotControl : public SDKExtension
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

#endif // _INCLUDE_SOURCEMOD_EXTENSION_H_
