/*+===================================================================
  File:      SMSDK_CONFIG.H

  Summary:   This file contains macros for configuring basic extension
             information.

  Origin:    Written by Bintr on 28.07.2026.
===================================================================+*/

#ifndef _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_

// Basic information exposed publicly
#define SMEXT_CONF_NAME        "Bot Control Helper"
#define SMEXT_CONF_DESCRIPTION "Extension providing features that otherwise cannot be done in SourcePawn"
#define SMEXT_CONF_VERSION     "1.0"
#define SMEXT_CONF_AUTHOR      "Bintr"
#define SMEXT_CONF_URL         "https://github.com/explowz/TF2-Bot-Control"
#define SMEXT_CONF_LOGTAG      "BOTCONTROL"
#define SMEXT_CONF_LICENSE     "GPL"
#define SMEXT_CONF_DATESTRING  __DATE__

// This macro exposes a plugin's main interface
#define SMEXT_LINK( pExtensionIface ) SDKExtension* g_pExtensionIface = pExtensionIface;

/*--------------------------------------------------------------------
  Sets whether or not this plugin required Metamod. Uncomment to
  enable, comment to disable.
--------------------------------------------------------------------*/
#define SMEXT_CONF_METAMOD

// Enable interfaces you want to use here by uncommenting lines
//#define SMEXT_ENABLE_FORWARDSYS
//#define SMEXT_ENABLE_HANDLESYS
//#define SMEXT_ENABLE_PLAYERHELPERS
//#define SMEXT_ENABLE_DBMANAGER
#define SMEXT_ENABLE_GAMECONF
//#define SMEXT_ENABLE_MEMUTILS
#define SMEXT_ENABLE_GAMEHELPERS
//#define SMEXT_ENABLE_TIMERSYS
//#define SMEXT_ENABLE_THREADER
//#define SMEXT_ENABLE_LIBSYS
//#define SMEXT_ENABLE_MENUS
//#define SMEXT_ENABLE_ADTFACTORY
#define SMEXT_ENABLE_PLUGINSYS
//#define SMEXT_ENABLE_ADMINSYS
//#define SMEXT_ENABLE_TEXTPARSERS
//#define SMEXT_ENABLE_USERMSGS
//#define SMEXT_ENABLE_TRANSLATOR
//#define SMEXT_ENABLE_ROOTCONSOLEMENU

#endif // _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
