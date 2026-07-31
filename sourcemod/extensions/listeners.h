/*+===================================================================
  File:      LISTENERS.H

  Summary:   This file contains the listener functions.

  Origin:    Written by Bintr on 30.07.2026.
===================================================================+*/

#ifndef _INCLUDE_BOTCONTROL_LISTENERS_H_
#define _INCLUDE_BOTCONTROL_LISTENERS_H_

#include <smsdk_ext.h>

/*C+C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C+++C
  Class:    CPluginsListener

  Summary:  This class listenes for SourceMod plugin loads and
            unloads.

  Methods:  OnPluginLoaded
              This function is called when a plugin's required
              dependencies and natives have been bound. Plugins at
              this phase may be in any state Failed or lower. This
              is invoked immediately before OnPluginStart, and
              sometime after OnPluginCreated.
            OnPluginUnloaded
              Called when a plugin is about to be unloaded. This is
              called for any plugin for which OnPluginLoaded was
              called, and is invoked immediately after OnPluginEnd().
              The plugin may be in any state Failed or lower.
C---C---C---C---C---C---C---C---C---C---C---C---C---C---C---C---C-C*/
class CPluginsListener : public IPluginsListener_V1
{
    void OnPluginLoaded( IPlugin* pPlugin );
    void OnPluginUnloaded( IPlugin* pPlugin );
};

extern IPlugin* g_pBotControlPl;

extern CPluginsListener g_PluginsListener;

#endif // _INCLUDE_BOTCONTROL_LISTENERS_H_
