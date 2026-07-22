/*+===================================================================
  File:    BOTCONTROL.SP

  Summary: This plugin allows players to take control of robots
           in the Mann vs. Machine gamemode.

  Origin:  Created by Bintr on 12.06.2026.
===================================================================+*/

#if !defined _DEBUG
    #define LOG_SERVER_DISABLE
#endif /* !defined _DEBUG */

#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#include <testing>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#include <tf_econ_data>
#include <vscript>
#include <SteamWorks>
#include <pluginstatemanager>
#include <actions>
#include <stocksoup/log_server>
#include <stocksoup/string>
#include <stocksoup/tf/client>
#include <stocksoup/convars>
#include <stocksoup/entity>
#include <stocksoup/tf/voice_hook>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/weapon>
#include <stocksoup/tf/annotations>

#include "include/botcontrol/const"
#include "include/botcontrol/globals"
#include "include/botcontrol/stocks"
#include "include/botcontrol/dynamichooks"
#include "include/botcontrol/dynamicdetours"
#include "include/botcontrol/actionhooks"

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name        = "[TF2] MvM Bot Control",
    author      = "Bintr",
    description = "Allows players to take control of a robot in the Mann vs. Machine gamemode.",
    version     = "0.7",
    url         = "https://github.com/explowz/TF2-Bot-Control"
};

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: AskPluginLoad2

  Summary:  Called before OnPluginStart, in case the plugin wants
            to check for load failure. This is called even if the
            plugin type is "private." Any natives from modules are
            not available at this point. Thus, this forward should
            only be used for explicit pre-emptive things, such as
            adding dynamic natives, setting certain types of load
            filters (such as not loading the plugin for certain games).

  Args:     Handle hMyself
              Handle to the plugin.
            bool bLate
              Whether or not the plugin was loaded "late" (after map
              load).
            char[] szError
              Error message buffer in case load failed.
            int cch
              Maximum number of characters for error message buffer.

  Returns:  APLRes
              `APLRes_Success` for load success,
              `APLRes_Failure` or `APLRes_SilentFailure` otherwise.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] szError, int cch )
{
    LoadTranslations( "botcontrol.phrases" );

    if ( GetEngineVersion() != Engine_TF2 )
    {
        FormatEx( szError, cch, "%T", "Unsupported_Engine", LANG_SERVER );
        return APLRes_Failure;
    }

    if ( !IsDedicatedServer() )
    {
        FormatEx( szError, cch, "%T", "Unsupported_Server", LANG_SERVER );
        return APLRes_Failure;
    }

    RegPluginLibrary( "botcontrol" );

    return APLRes_Success;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginStart

  Summary:  Called when the plugin is fully initialized and all
            known external references are resolved. This is only
            called once in the lifetime of the plugin, and is
            paired with OnPluginEnd().

            If any run-time error is thrown during this callback,
            the plugin will be marked as failed.

            This function initializes all of our console variables,
            global variables, and more.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginStart()
{
    char szDescription[ 64 ];
    GetPluginInfo( null, PlInfo_Name, szDescription, sizeof( szDescription ) );
    StrCat( szDescription, sizeof( szDescription ), " version" );
    CreateVersionConVar( "sm_botcontrol_version", szDescription );

    GameData hConf = new GameData( "botcontrol" );
    if ( !hConf )
    {
        SetFailState( "%T", "Gamedata_Not_Found", LANG_SERVER );
    }

    sm_botcontrol_enabled = CreateConVar(
                                         "sm_botcontrol_enabled",
                                         "1",
                                         "Enables the plugin and allows players to control invader bots.",
                                         FCVAR_ARCHIVE | FCVAR_NOTIFY | FCVAR_NEVER_AS_STRING,
                                         true,
                                         0.0,
                                         true,
                                         1.0
                                        );

    char szName[ 32 ];
    sm_botcontrol_enabled.GetName( szName, sizeof( szName ) );

    PSM_Init( szName, hConf );
    PSM_AddShouldEnableCallback( IsMannVsMachineMode );
    PSM_AddPluginStateChangedHook( SetGameDescription );
    PSM_AddPluginStateChangedHook( RestoreAllBots );
    PSM_AddPluginStateChangedHook( ProcessAllEntities );

    char szMaxPlayers[ 4 ];
    IntToString( ( MAXPLAYERS - 1 ), szMaxPlayers, sizeof( szMaxPlayers ) );

    sm_botcontrol_premium_flags        = CreateConVar(
                                                      "sm_botcontrol_premium_flags",
                                                      "o",
                                                      "The required flags a player must have to be considered a premium player. " ...
                                                          "For more information, please refer to admin_levels.cfg.",
                                                      FCVAR_ARCHIVE
                                                     );
    sm_botcontrol_groupid              = CreateConVar(
                                                      "sm_botcontrol_groupid",
                                                      "571",
                                                      "The groupID32 of the group the user must be a member of to control bots with the \"group\" attribute.",
                                                      FCVAR_ARCHIVE | FCVAR_NEVER_AS_STRING,
                                                      true,
                                                      0.0
                                                     );
    sm_botcontrol_min_defenders        = CreateConVar(
                                                      "sm_botcontrol_min_defenders",
                                                      "0",
                                                      "The minimum amount of players on the defending team for a player to be allowed to control a bot.",
                                                      FCVAR_ARCHIVE | FCVAR_NOTIFY | FCVAR_NEVER_AS_STRING,
                                                      true,
                                                      0.0,
                                                      true,
                                                      float( MAXPLAYERS - 1 )
                                                     );
    sm_botcontrol_max_invaders         = CreateConVar(
                                                      "sm_botcontrol_max_invaders",
                                                      szMaxPlayers,
                                                      "The maximum amount of human players allowed on the invading team.",
                                                      FCVAR_ARCHIVE | FCVAR_NOTIFY | FCVAR_NEVER_AS_STRING,
                                                      true,
                                                      0.0,
                                                      true,
                                                      float( MAXPLAYERS - 1 )
                                                     );
    sm_botcontrol_instruction_interval = CreateConVar(
                                                      "sm_botcontrol_instruction_interval",
                                                      "40.0",
                                                      "The interval at which the plugin should update a controlling player's instrctions.",
                                                      FCVAR_ARCHIVE | FCVAR_NOTIFY | FCVAR_NEVER_AS_STRING,
                                                      true,
                                                      10.0 // Prevent spam
                                                     );
    sm_botcontrol_mirror_name          = CreateConVar(
                                                      "sm_botcontrol_mirror_name",
                                                      "0",
                                                      "Enables changing the controlling player's name to that of the bot for the duration the player controls the bot.",
                                                      FCVAR_ARCHIVE | FCVAR_NOTIFY | FCVAR_NEVER_AS_STRING,
                                                      true,
                                                      0.0,
                                                      true,
                                                      1.0
                                                     );
    sm_botcontrol_mirror_name.AddChangeHook( RestoreOriginalNames );

    spec_freeze_traveltime                          = FindConVar( "spec_freeze_traveltime" );
    spec_freeze_time                                = FindConVar( "spec_freeze_time" );
    tf_bot_fire_weapon_allowed                      = FindConVar( "tf_bot_fire_weapon_allowed" );
    tf_bot_always_full_reload                       = FindConVar( "tf_bot_always_full_reload" );
    tf_bot_force_jump                               = FindConVar( "tf_bot_force_jump" );
    tf_bot_engineer_mvm_building_health_multiplier  = FindConVar( "tf_bot_engineer_building_health_multiplier" );
    tf_mvm_bot_allow_flag_carrier_to_fight          = FindConVar( "tf_mvm_bot_allow_flag_carrier_to_fight" );
    tf_mvm_bot_flag_carrier_interval_to_1st_upgrade = FindConVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" );
    tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade = FindConVar( "tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade" );
    tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade = FindConVar( "tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade" );
    tf_mvm_bot_flag_carrier_health_regen            = FindConVar( "tf_mvm_bot_flag_carrier_health_regen" );
    tf_deploying_bomb_delay_time                    = FindConVar( "tf_deploying_bomb_delay_time" );
    tf_deploying_bomb_time                          = FindConVar( "tf_deploying_bomb_time" );

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!! SDK CALLS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFWeaponBuilder::SetSubType" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int iSubType
    g_hfnCTFWeaponBuilder_SetSubType = EndPrepSDKCall();
    if ( !g_hfnCTFWeaponBuilder_SetSubType )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFWeaponBuilder::SetSubType" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Static );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "GetPlayerClassData" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );  // unsigned int iClass
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // TFPlayerClassData_t*
    g_hfnGetPlayerClassData = EndPrepSDKCall();
    if ( !g_hfnGetPlayerClassData )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "GetPlayerClassData" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::ManageBuilderWeapons" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // TFPlayerClassData_t *pData
    g_hfnCTFPlayer_ManageBuilderWeapons = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_ManageBuilderWeapons )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::ManageBuilderWeapons" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::PostInventoryApplication" );
    g_hfnCTFPlayer_PostInventoryApplication = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_PostInventoryApplication )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::PostInventoryApplication" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::RemoveObject" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Plain ); // CBaseObject *pObject
    g_hfnCTFPlayer_RemoveObject = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_RemoveObject )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::RemoveObject" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

#if defined WIN32
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CObjectTeleporter::SetTeleportWhere" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // const CUtlStringList& teleportWhereName
    g_hfnCObjectTeleporter_SetTeleportWhere = EndPrepSDKCall();
    if ( !g_hfnCObjectTeleporter_SetTeleportWhere )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CObjectTeleporter::SetTeleportWhere" );
    }
#endif

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

#if !defined WIN32
    StartPrepSDKCall( SDKCall_Raw );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CUtlStringList::CopyAndAddToTail" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer ); // char const *pString
    g_hfnCUtlStringList_CopyAndAddToTail = EndPrepSDKCall();
    if ( !g_hfnCUtlStringList_CopyAndAddToTail )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CUtlStringList::CopyAndAddToTail" );
    }
#endif

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CBaseObject::GetMaxHealthForCurrentLevel" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // int
    g_hfnCBaseObject_GetMaxHealthForCurrentLevel = EndPrepSDKCall();
    if ( !g_hfnCBaseObject_GetMaxHealthForCurrentLevel )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CBaseObject::GetMaxHealthForCurrentLevel" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Static );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "DispatchParticleEffect(const char*, ParticleAttachment_t, CBaseEntity*, const char*, bool)" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );      // const char* pszParticleName
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );  // ParticleAttachment_t iAttachType
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer ); // CBaseEntity* pEntity
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );      // const char* pszAttachmentName
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );          // bool bResetAllParticlesOnEntity
    g_hfnDispatchParticleEffect = EndPrepSDKCall();
    if ( !g_hfnDispatchParticleEffect )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "DispatchParticleEffect" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFSniperRifle::ZoomOut" );
    g_hfnCTFSniperRifle_ZoomOut = EndPrepSDKCall();
    if ( !g_hfnCTFSniperRifle_ZoomOut )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFSniperRifle::ZoomOut" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::HasTheFlag" );
    // BUGBUG: There's actually no way to pass an array from SourceMod, nor pass `NULL` for a POD data type
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // ETFFlagType exceptionTypes[]
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int nNumExceptions
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFPlayer_HasTheFlag = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_HasTheFlag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::HasTheFlag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CCaptureFlag::PickUp" );
    PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer ); // CTFPlayer* pPlayer
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );          // bool bInvisible
    g_hfnCCaptureFlag_PickUp = EndPrepSDKCall();
    if ( !g_hfnCCaptureFlag_PickUp )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CCaptureFlag::PickUp" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CBasePlayer::UpdateClientData" );
    g_hfnCBasePlayer_UpdateClientData = EndPrepSDKCall();
    if ( !g_hfnCBasePlayer_UpdateClientData )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CBasePlayer::UpdateClientData" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFPlayer::SetObserverTarget" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer ); // CBaseEntity *target
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );         // bool
    g_hfnCTFPlayer_SetObserverTarget = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_SetObserverTarget )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::SetObserverTarget" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayerShared::ResetRageBuffs" );
    g_hfnCTFPlayerShared_ResetRageBuffs = EndPrepSDKCall();
    if ( !g_hfnCTFPlayerShared_ResetRageBuffs )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayerShared::ResetRageBuffs" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_GameRules );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFGameRules::BroadcastSound" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );                          // int iTeam
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );                              // const char *sound
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );                          // int iAdditionalSoundFlags
    PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL ); // CBasePlayer *pPlayer
    g_hfnCTFGameRules_BroadcastSound = EndPrepSDKCall();
    if ( !g_hfnCTFGameRules_BroadcastSound )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFGameRules::BroadcastSound" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Static );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFBotMvMEngineerHintFinder::FindHint" );
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );         // bool bShouldCheckForBlockingObjects
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );         // bool bAllowOutOfRangeNest
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // CHandle< CTFBotHintEngineerNest >* pFoundNest
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFBotMvMEngineerHintFinder_FindHint = EndPrepSDKCall();
    if ( !g_hfnCTFBotMvMEngineerHintFinder_FindHint )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFBotMvMEngineerHintFinder::FindHint" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_GameRules );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CMultiplayRules::HaveAllPlayersSpeakConceptIfAllowed" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );                     // int iConcept
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );                     // int iTeam
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL ); // const char *modifiers
    g_hfnCMultiplayRules_HaveAllPlayersSpeakConceptIfAllowed = EndPrepSDKCall();
    if ( !g_hfnCMultiplayRules_HaveAllPlayersSpeakConceptIfAllowed )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CMultiplayRules::HaveAllPlayersSpeakConceptIfAllowed" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFBot::IsBarrageAndReloadWeapon" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL ); // CTFWeaponBase *weapon
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );                                 // bool
    g_hfnCTFBot_IsBarrageAndReloadWeapon = EndPrepSDKCall();
    if ( !g_hfnCTFBot_IsBarrageAndReloadWeapon )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFBot::IsBarrageAndReloadWeapon" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CWeaponMedigun::CycleResistType" );
    g_hfnCWeaponMedigun_CycleResistType = EndPrepSDKCall();
    if ( !g_hfnCWeaponMedigun_CycleResistType )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CWeaponMedigun::CycleResistType" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CWeaponMedigun::GetResistType" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // medigun_resist_types_t
    g_hfnCWeaponMedigun_GetResistType = EndPrepSDKCall();
    if ( !g_hfnCWeaponMedigun_GetResistType )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CWeaponMedigun::GetResistType" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::GetClosestCaptureZone" );
    PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL ); // CCaptureZone*
    g_hfnCTFPlayer_GetClosestCaptureZone = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_GetClosestCaptureZone )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::GetClosestCaptureZone" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::PlaySpecificSequence" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer ); // const char *pAnimationName
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );    // bool
    g_hfnCTFPlayer_PlaySpecificSequence = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_PlaySpecificSequence )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::PlaySpecificSequence" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_GameRules );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTeamplayRoundBasedRules::PlayThrottledAlert" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int iTeam
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );     // const char *sound
    PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );        // float fDelayBeforeNext
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTeamplayRoundBasedRules_PlayThrottledAlert = EndPrepSDKCall();
    if ( !g_hfnCTeamplayRoundBasedRules_PlayThrottledAlert )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTeamplayRoundBasedRules::PlayThrottledAlert" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CCaptureZone::Capture" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer ); //CBaseEntity *pOther
    g_hfnCCaptureZone_Capture = EndPrepSDKCall();
    if ( !g_hfnCCaptureZone_Capture )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CCaptureZone::Capture" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFPlayer::RemoveAllWeapons" );
    g_hfnCTFPlayer_RemoveAllWeapons = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_RemoveAllWeapons )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::RemoveAllWeapons" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::DoAnimationEvent" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // PlayerAnimEvent_t event
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int nData
    g_hfnCTFPlayer_DoAnimationEvent = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_DoAnimationEvent )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::DoAnimationEvent" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFBot::StartIdleSound" );
    g_hfnCTFBot_StartIdleSound = EndPrepSDKCall();
    if ( !g_hfnCTFBot_StartIdleSound )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFBot::StartIdleSound" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Virtual, "CTFBot::GetLastKnownArea" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // CTFNavArea*
    g_hfnCTFBot_GetLastKnownArea = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetLastKnownArea )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFBot::GetLastKnownArea" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFPlayer::IsCapturingPoint" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFPlayer_IsCapturingPoint = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_IsCapturingPoint )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFPlayer::IsCapturingPoint" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( hConf, SDKConf_Signature, "CTFBot::GetMyControlPoint" );
    PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
    g_hfnCTFBot_GetMyControlPoint = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetMyControlPoint )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed", LANG_SERVER, "CTFBot::GetMyControlPoint" );
    }

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!! DYNAMIC HOOKS !!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    PSM_AddDynamicHookFromConf( "CBasePlayer::GetBotType" );
    PSM_AddDynamicHookFromConf( "CObjectTeleporter::StartBuilding" );
    PSM_AddDynamicHookFromConf( "CObjectTeleporter::FinishedBuilding" );
    PSM_AddDynamicHookFromConf( "CObjectSentrygun::StartBuilding" );
    PSM_AddDynamicHookFromConf( "CFilterTFBotHasTag::PassesFilterImpl" );
    PSM_AddDynamicHookFromConf( "CTriggerBotTag::Touch" );
    PSM_AddDynamicHookFromConf( "CTFPlayer::ShouldTransmit" );
    PSM_AddDynamicHookFromConf( "CTFPlayer::ShouldGib" );
    PSM_AddDynamicHookFromConf( "CTFPlayer::IsAllowedToPickUpFlag" );
    PSM_AddDynamicHookFromConf( "CCaptureFlag::PickUp" );
    PSM_AddDynamicHookFromConf( "CTFPlayer::Event_Killed" );

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!! DYNAMIC DETOURS !!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    PSM_AddDynamicDetourFromConf( "CTFPlayer::CanBuild", CTFPlayer_CanBuild_Pre );
    PSM_AddDynamicDetourFromConf( "CTFPlayer::HandleCommand_JoinTeam", CTFPlayer_HandleCommand_JoinTeam_Pre );
    PSM_AddDynamicDetourFromConf( "CTraceFilterObject::ShouldHitEntity", CTraceFilterObject_ShouldHitEntity_Pre );
    PSM_AddDynamicDetourFromConf( "CTFPlayerShared::OnConditionAdded", CTFPlayerShared_OnConditionAdded_Pre, CTFPlayerShared_OnConditionAdded_Post );
    // FIXME: Use an extension to detour this because the return data type doesn't fit any presets
    // PSM_AddDynamicDetourFromConf( "CTFBotDeliverFlag::OnStart", CTFBotDeliverFlag_OnStart_Pre, CTFBotDeliverFlag_OnStart_Post );

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!! OFFSETS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    g_CTFPlayer_aObjects_Offset                               = FindSendPropInfo( "CTFPlayer", "m_flMvMLastDamageTime" ) + hConf.GetOffset( "CTFPlayer::m_aObjects" );
    g_CTFPlayer_flSpawnTime_Offset                            = g_CTFPlayer_aObjects_Offset + hConf.GetOffset( "CTFPlayer::m_flSpawnTime" );
    g_CTFPlayer_nDeployingBombState_Offset                    = FindSendPropInfo( "CTFPlayer", "m_nCurrency" ) + hConf.GetOffset( "CTFPlayer::m_nDeployingBombState" );
    g_CTFPlayer_bIsMissionEnemy_Offset                        = g_CTFPlayer_nDeployingBombState_Offset + hConf.GetOffset( "CTFPlayer::m_bIsMissionEnemy" );
    g_CTFPlayer_bIsSupportEnemy_Offset                        = g_CTFPlayer_bIsMissionEnemy_Offset + hConf.GetOffset( "CTFPlayer::m_bIsSupportEnemy" );
    g_CTFPlayer_bIsLimitedSupportEnemy_Offset                 = g_CTFPlayer_bIsSupportEnemy_Offset + hConf.GetOffset( "CTFPlayer::m_bIsLimitedSupportEnemy" );
    g_CTFPlayerShared_flInvisibility_Offset                   = FindSendPropInfo( "CTFPlayer", "m_flInvisChangeCompleteTime" ) + hConf.GetOffset( "CTFPlayerShared::m_flInvisibility" );
    g_CTFBot_teleportWhereName_Offset                         = hConf.GetOffset( "CTFBot::m_teleportWhereName" );
    g_CObjectTeleporter_teleportWhereName_Offset              = hConf.GetOffset( "CObjectTeleporter::m_teleportWhereName" );
    g_CBaseObject_bForceQuickBuild_Offset                     = FindSendPropInfo( "CBaseObject", "m_bServerOverridePlacement" ) + hConf.GetOffset( "CBaseObject::m_bForceQuickBuild" );
    // g_CTFBotDeliverFlag_upgradeLevel_Offset                   = hConf.GetOffset( "CTFBotDeliverFlag::m_upgradeLevel" );
    g_CPopulationManager_canBotsAttackWhileInSpawnRoom_Offset = hConf.GetOffset( "CPopulationManager::m_canBotsAttackWhileInSpawnRoom" );
    g_CTFPlayer_pWaveSpawnPopulator_Offset                    = FindSendPropInfo( "CTFPlayer", "m_bMatchSafeToLeave" ) + hConf.GetOffset( "CTFPlayer::m_pWaveSpawnPopulator" );
    g_CTraceFilterSimple_pPassEnt_Offset                      = hConf.GetOffset( "CTraceFilterSimple::m_pPassEnt" );

    delete hConf;

    LogServer( "CTFPlayer::m_aObjects offset: %d", g_CTFPlayer_aObjects_Offset );
    LogServer( "CTFPlayer::m_flSpawnTime offset: %d", g_CTFPlayer_flSpawnTime_Offset );
    LogServer( "CTFPlayer::m_nDeployingBombState offset: %d", g_CTFPlayer_nDeployingBombState_Offset );
    LogServer( "CTFPlayer::m_bIsMissionEnemy offset: %d", g_CTFPlayer_bIsMissionEnemy_Offset );
    LogServer( "CTFPlayer::m_bIsSupportEnemy offset: %d", g_CTFPlayer_bIsSupportEnemy_Offset );
    LogServer( "CTFPlayer::m_bIsLimitedSupportEnemy offset: %d", g_CTFPlayer_bIsLimitedSupportEnemy_Offset );
    LogServer( "CTFPlayer::m_pWaveSpawnPopulator offset: %d", g_CTFPlayer_pWaveSpawnPopulator_Offset );
    LogServer( "CTFPlayerShared::m_flInvisibility offset: %d", g_CTFPlayerShared_flInvisibility_Offset );
    LogServer( "CBaseObject::m_bForceQuickBuild offset: %d", g_CBaseObject_bForceQuickBuild_Offset );

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!! COMMAND LISTENERS !!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    RegisterVoiceCommandCallback( Voice_Medic, PlayerControlBot );
    PSM_AddCommandListener( VoiceMenuListener, "voicemenu" );

    PSM_AddCommandListener( HandleTaunt, "taunt" );
    PSM_AddCommandListener( HandleTaunt, "weapon_taunt" );

    PSM_AddEventHook( "player_team", HandlePlayerTeamEvent_Pre, EventHookMode_Pre );
    PSM_AddEventHook( "player_spawn", HandlePlayerSpawnEvent_Pre, EventHookMode_Pre );
    // Apparently this is unneeded
    // PSM_AddEventHook( GAME_EVENT_PLAYER_DEATH, HandlePlayerDeathEvent_Pre, EventHookMode_Pre );
    PSM_AddEventHook( "teamplay_flag_event", HandleTeamplayFlagEvent_Pre, EventHookMode_Pre );

    // HUD messages are taken care of in `OnPlayerRunCmdPost`
    g_hSyncObj = CreateHudSynchronizer();

    g_hShowInstrctions = new Cookie( "botcontrol_show_instructions", "MvM Bot Control Instructions", CookieAccess_Public );
    g_hShowInstrctions.SetPrefabMenu( CookieMenu_OnOff_Int, "Bot Control Instructions" );

    // NOTE: PSM takes care of late-loading through its state change hooks

    // Request our clients' group affiliation status every 30 seconds
    CreateTimer( 30.0, UpdateUsersGroupStatus, _, TIMER_REPEAT );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnAllPluginsLoaded

  Summary:  Called after all plugins have been loaded. This is
            called once for every plugin. If a plugin late loads,
            it will be called immediately after OnPluginStart().

            This function initializes all VScript-related SDK calls
            and DHooks.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnAllPluginsLoaded()
{
    /*--------------------------------------------------------------------
      Make sure the user has the dependencies installed. We cannot check
      for all of them because not all register a library name.
    --------------------------------------------------------------------*/

    if ( !LibraryExists( "nosoop_tf2utils" ) )
    {
        SetFailState( "%T", "Missing_Library", LANG_SERVER, "TF2 Utils", "nosoop" );
    }

    if ( !LibraryExists( "tf2attributes" ) )
    {
        SetFailState( "%T", "Missing_Library", LANG_SERVER, "[TF2] TF2Attributes", "FlaminSarge" );
    }

    if ( !LibraryExists( "vscript" ) )
    {
        SetFailState( "%T", "Missing_Library", LANG_SERVER, "VScript", "42" );
    }

    if ( !LibraryExists( "tf_econ_data" ) )
    {
        SetFailState( "%T", "Missing_Library", LANG_SERVER, "[TF2] Econ Data", "nosoop" );
    }

    if ( !LibraryExists( "actionslib" ) )
    {
        SetFailState( "%T", "Missing_Library", LANG_SERVER, "Actions", "BHaType" );
    }

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!! SDK CALLS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    /*--------------------------------------------------------------------
      Don't use `CreateSDKCall()`, `CreateDetour`, or `CreateHook` becaus
      they often set up the SDK call/detour/hook incorrectly, resulting
      in crashes or unexpected behavior!
    --------------------------------------------------------------------*/

    VScriptFunction fn;

    fn = VScript_GetClassFunction( "CTFBot", "LeaveSquad" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    g_hfnCTFBot_LeaveSquad = EndPrepSDKCall();
    if ( !g_hfnCTFBot_LeaveSquad )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::LeaveSquad" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "AddBotAttribute" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int attributeFlag
    g_hfnCTFBot_SetAttribute = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetAttribute )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetAttribute" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "RemoveBotAttribute" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int attributeFlag
    g_hfnCTFBot_ClearAttribute = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ClearAttribute )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ClearAttribute" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "ClearAllBotAttributes" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    g_hfnCTFBot_ClearAllAttributes = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ClearAllAttributes )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ClearAllAttributes" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "HasBotAttribute" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int attributeFlag
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFBot_HasAttribute = EndPrepSDKCall();
    if ( !g_hfnCTFBot_HasAttribute )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::HasAttribute" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "AddBotTag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer ); // const char *tag
    g_hfnCTFBot_AddTag = EndPrepSDKCall();
    if ( !g_hfnCTFBot_AddTag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::AddTag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "RemoveBotTag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer ); // const char *tag
    g_hfnCTFBot_RemoveTag = EndPrepSDKCall();
    if ( !g_hfnCTFBot_RemoveTag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::RemoveTag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "ClearAllBotTags" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    g_hfnCTFBot_ClearTags = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ClearTags )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ClearTags" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "HasBotTag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer ); // const char *tag
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );    // bool
    g_hfnCTFBot_HasTag = EndPrepSDKCall();
    if ( !g_hfnCTFBot_HasTag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::HasTag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "GetAllBotTags" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // HSCRIPT hTable
    g_hfnCTFBot_ScriptGetAllTags = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ScriptGetAllTags )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ScriptGetAllTags" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "SetMission" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // MissionType mission
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );         // bool resetBehaviorSystem
    g_hfnCTFBot_SetMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "SetPrevMission" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // MissionType mission
    g_hfnCTFBot_SetPrevMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetPrevMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetPrevMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "GetMission" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // bool
    g_hfnCTFBot_GetMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::GetMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "GetPrevMission" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // MissionType
    g_hfnCTFBot_GetPrevMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetPrevMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::GetPrevMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "HasMission" );
    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // MissionType mission
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFBot_HasMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_HasMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::HasMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "IsOnAnyMission" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFBot_IsOnAnyMission = EndPrepSDKCall();
    if ( !g_hfnCTFBot_IsOnAnyMission )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::IsOnAnyMission" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "SetMissionTarget" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
    g_hfnCTFBot_SetMissionTarget = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetMissionTarget )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetMissionTarget" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "GetMissionTarget" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
    g_hfnCTFBot_GetMissionTarget = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetMissionTarget )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::GetMissionTarget" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "ShouldQuickBuild" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFBot_ShouldQuickBuild = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ShouldQuickBuild )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ShouldQuickBuild" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "IsWeaponRestricted" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // HSCRIPT script
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFBot_IsWeaponRestricted = EndPrepSDKCall();
    if ( !g_hfnCTFBot_IsWeaponRestricted )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::IsWeaponRestricted" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFPlayer", "DropFlag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain ); // bool bSilent
    g_hfnCTFPlayer_DropFlag = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_DropFlag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFPlayer::DropFlag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFPlayer", "HandleTauntCommand" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int iTauntSlot
    g_hfnCTFPlayer_HandleTauntCommand = EndPrepSDKCall();
    if ( !g_hfnCTFPlayer_HandleTauntCommand )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFPlayer::HandleTauntCommand" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "ShouldAutoJump" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFBot_ShouldAutoJump = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ShouldAutoJump )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ShouldAutoJump" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "SetBehaviorFlag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int flags
    g_hfnCTFBot_SetBehaviorFlag = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetBehaviorFlag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetBehaviorFlag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "ClearBehaviorFlag" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int flags
    g_hfnCTFBot_ClearBehaviorFlag = EndPrepSDKCall();
    if ( !g_hfnCTFBot_ClearBehaviorFlag )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::ClearBehaviorFlag" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "IsBehaviorFlagSet" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int flags
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFBot_IsBehaviorFlagSet = EndPrepSDKCall();
    if ( !g_hfnCTFBot_IsBehaviorFlagSet )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::IsBehaviorFlagSet" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFPlayer", "IsStealthed" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFPlayerShared_IsStealthed = EndPrepSDKCall();
    if ( !g_hfnCTFPlayerShared_IsStealthed )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFPlayerShared::IsStealthed" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "SetMaxVisionRangeOverride" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain ); // float range
    g_hfnCTFBot_SetMaxVisionRangeOverride = EndPrepSDKCall();
    if ( !g_hfnCTFBot_SetMaxVisionRangeOverride )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::SetMaxVisionRangeOverride" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFBot", "GetMaxVisionRangeOverride" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain ); // float
    g_hfnCTFBot_GetMaxVisionRangeOverride = EndPrepSDKCall();
    if ( !g_hfnCTFBot_GetMaxVisionRangeOverride )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFBot::GetMaxVisionRangeOverride" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFPlayer", "IsAllowedToTaunt" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain ); // bool
    g_hfnCTFPlayerShared_IsAllowedToTaunt = EndPrepSDKCall();
    if ( !g_hfnCTFPlayerShared_IsAllowedToTaunt )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFPlayerShared::IsAllowedToTaunt" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CBaseEntity", "GetCenter" );

    StartPrepSDKCall( SDKCall_Entity );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_SetReturnInfo( SDKType_Vector, SDKPass_ByRef ); // const Vector&
    g_hfnCBaseEntity_WorldSpaceCenter = EndPrepSDKCall();
    if ( !g_hfnCBaseEntity_WorldSpaceCenter )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CBaseEntity::WorldSpaceCenter" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CBasePlayer", "SnapEyeAngles" );

    StartPrepSDKCall( SDKCall_Player );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_QAngle, SDKPass_ByRef ); // const QAngle &viewAngles
    g_hfnCBasePlayer_SnapEyeAngles = EndPrepSDKCall();
    if ( !g_hfnCBasePlayer_SnapEyeAngles )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CBasePlayer::SnapEyeAngles" );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    fn = VScript_GetClassFunction( "CTFNavArea", "HasAttributeTF" );

    StartPrepSDKCall( SDKCall_Raw );
    SET_OFFSET_OR_ADDRESS( fn )
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int flags
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );        // bool
    g_hfnCTFNavArea_HasAttributeTF = EndPrepSDKCall();
    if ( !g_hfnCTFNavArea_HasAttributeTF )
    {
        SetFailState( "%T", "SDKCall_Prep_Failed_VScript", LANG_SERVER, "CTFNavArea::HasAttributeTF" );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnConfigsExecuted

  Summary:  Called when the map has loaded, servercfgfile (server.cfg)
            has been executed, and all plugin configs are done
            executing. This is the best place to initialize plugin
            functions which are based on cvar data.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnConfigsExecuted()
{
    PSM_TogglePluginState();
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginEnd

  Summary:  Called when the plugin is about to be unloaded.

            It is not necessary to close any handles or remove
            hooks in this function. SourceMod guarantees that
            plugin shutdown automatically and correctly releases
            all resources.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginEnd()
{
    PSM_SetPluginState( false );

    // Make sure we don't leave any HUD text on clients' screens
    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame( i ) && !IsFakeClient( i ) )
        {
            ClearSyncHud( i, g_hSyncObj );
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: RestoreOriginalNames

  Summary:  This callback function is called each time the
            sm_botcontrol_mirror_name is changed. It restores every
            human invader's name back to their original one as to
            not leave them stuck with a changed name once they stop
            controlling a bot.

  Args:     ConVar hMirrorName
              Handle to the sm_botcontrol_mirror_name console
              variable.
            const char[] szOldValue
              A string representing the console variable's old
              value.
            const char[] szNewValue
              A string representing the console variable's new
              value.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void RestoreOriginalNames( ConVar hMirrorName, const char[] szOldValue, const char[] szNewValue )
{
    if ( StringToInt( szOldValue ) != 0 && hMirrorName.BoolValue )
    {
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( g_aPlayerAttribs[ i ].IsControlling() && !StrEmpty( g_aPlayerAttribs[ i ].szOriginalName ) )
            {
                SetPlayerName( i, g_aPlayerAttribs[ i ].szOriginalName );
                g_aPlayerAttribs[ i ].szOriginalName[ 0 ] = EOS;
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: SteamWorks_OnClientGroupStatus

  Summary:  This callback function is called by the
            `RequestUserGroupStatus` Steamworks function
            (`SteamWorks_GetUserGroupStatus` and
            `SteamWorks_GetUserGroupStatusAuthID` in our case)
            and contains the result of the user's group status.

  Args:     int iAuthId
              The Steam account ID of the user for which the group
              status was requested.
            int iGroupId
              The group ID for which `iAuthId`'s group status was
              requested.
            bool bIsMember
              This parameter will be `true` if the user with Steam
              ID `iAuthId` is a member of the group with group ID
              `iGroupId`. Otherwise, this parameter will be `false`.
            bool bIsOfficer
              This parameter will be `true` if the user with Steam
              ID `iAuthId` is a group officer of the group with
              group ID `iGroupId`. Otherwise, this parameter will
              be `false`.

              NOTE: This parameter cannot be `true` if `bIsMember`
              is `false`.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void SteamWorks_OnClientGroupStatus( int iAuthId, int iGroupId, bool bIsMember, bool bIsOfficer )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( iGroupId != sm_botcontrol_groupid.IntValue )
    {
        // Not the group we care about
        return;
    }

    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( !IsClientAuthorized( i ) )
        {
            continue;
        }

        if ( GetSteamAccountID( i ) == iAuthId )
        {
            g_aPlayerAttribs[ i ].bIsGroupMember = bIsMember;
            return;
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: UpdateUsersGroupStatus

  Summary:  This function initiates a group status update for all
            players connected to the server. The status is returned
            in the `SteamWorks_OnClientGroupStatus` callback function.

  Args:     Handle hTimer
              A handle to the timer that called this function. If
              the function was not called by a timer, this value
              will be `null`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void UpdateUsersGroupStatus( Handle hTimer )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( !IsServerProcessing() )
    {
        return;
    }

    if ( !SteamWorks_IsConnected() )
    {
        LogMessage( "%T", "Server_Not_Connected", LANG_SERVER );
        return;
    }

    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientAuthorized( i ) && !IsFakeClient( i ) )
        {
            if ( !SteamWorks_GetUserGroupStatus( i, sm_botcontrol_groupid.IntValue ) )
            {
                char szUserInfo[ 256 ];
                FormatEx( szUserInfo, sizeof( szUserInfo ), "%L", i );
                LogError( "%T", "Group_Status_Request_Failed", LANG_SERVER, szUserInfo );
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnGameFrame

  Summary:  Called before every server frame. Note that you should
            avoid doing expensive computations or declaring large
            local arrays.

            We use this function to keep track of the number of
            defending and invading players.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnGameFrame()
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    g_nDefenders = 0;
    g_nInvaders  = 0;

    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( IsClientInGame( i ) )
        {
            if ( TF2_GetClientTeam( i ) == TF_TEAM_PVE_DEFENDERS )
            {
                g_nDefenders++;
            }
            else if ( g_aPlayerAttribs[ i ].IsControlling() )
            {
                g_nInvaders++;
            }
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnEntityCreated

  Summary:  This function is called every time an entity is created.
            We use it for hooking entities.

  Args:     int iEntity
              Index of the entity that was created.
            const char[] szClassname
              A string repesenting `iEntity`'s classname.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnEntityCreated( int iEntity, const char[] szClassname )
{
    if ( StrContains( szClassname, "tf_projectile" ) == 0 )
    {
        PSM_SDKHook( iEntity, SDKHook_SetTransmit, SetTransmit );
    }
    else if ( StrEqual( szClassname, "obj_sentrygun" ) )
    {
        PSM_DHookEntityByName( "CObjectSentrygun::StartBuilding", Hook_Pre, iEntity, CObjectSentrygun_StartBuilding_Pre );

        PSM_SDKHook( iEntity, SDKHook_SetTransmit, SetTransmit );
    }
    else if ( StrEqual( szClassname, "obj_dispenser" ) )
    {
        PSM_SDKHook( iEntity, SDKHook_SetTransmit, SetTransmit );
    }
    else if ( StrEqual( szClassname, "obj_teleporter" ) )
    {
        PSM_DHookEntityByName( "CObjectTeleporter::StartBuilding", Hook_Pre, iEntity, CObjectTeleporter_StartBuilding_Pre );
        PSM_DHookEntityByName( "CObjectTeleporter::StartBuilding", Hook_Post, iEntity, CObjectTeleporter_StartBuilding_Post );
        PSM_DHookEntityByName( "CObjectTeleporter::FinishedBuilding", Hook_Post, iEntity, CObjectTeleporter_FinishedBuilding_Post );

        PSM_SDKHook( iEntity, SDKHook_SetTransmit, SetTransmit );
    }
    else if ( StrEqual( szClassname, "filter_tf_bot_has_tag" ) )
    {
        PSM_DHookEntityByName( "CFilterTFBotHasTag::PassesFilterImpl", Hook_Pre, iEntity, CFilterTFBotHasTag_PassesFilterImpl_Pre );
    }
    else if ( StrEqual( szClassname, "trigger_bot_tag" ) )
    {
        PSM_DHookEntityByName( "CTriggerBotTag::Touch", Hook_Pre, iEntity, CTriggerBotTag_Touch_Pre );
    }
    else if ( StrEqual( szClassname, "func_respawnroom" ) )
    {
        PSM_SDKHook( iEntity, SDKHook_StartTouchPost, RespawnRoom_StartTouchPost );
    }
    else if ( StrEqual( szClassname, "item_teamflag" ) )
    {
        PSM_DHookEntityByName( "CCaptureFlag::PickUp", Hook_Post, iEntity, CCaptureFlag_PickUp_Post );

        PSM_SDKHook( iEntity, SDKHook_SetTransmit, SetTransmit );
    }
    else if ( StrEqual( szClassname, "func_capturezone" ) )
    {
        PSM_SDKHook( iEntity, SDKHook_StartTouchPost, CaptureZone_StartTouchPost );
    }
    else if ( StrEqual( szClassname, "tf_objective_resource" ) )
    {
        g_iObjectiveResource = iEntity;
    }
    else if ( StrEqual( szClassname, "info_populator" ) )
    {
        g_iPopulationManager = iEntity;
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnClientPutInServer

  Summary:  Called when a client is entering the game.  Whether a
            client has a steamid is undefined until
            OnClientAuthorized is called, which may occur either
            before or after OnClientPutInServer. Similarly, use
            OnClientPostAdminCheck() if you need to verify whether
            connecting players are admins. GetClientCount() will
            include clients as they are passed through this
            function, as clients are already in game at this point.

            We use this function for SDKHooks to reset clients'
            globals.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnClientPutInServer( int iClient )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    ResetGlobals( iClient );

    PSM_SDKHook( iClient, SDKHook_SetTransmit, SetTransmit );

    PSM_DHookEntityByName( "CTFPlayer::Event_Killed", Hook_Pre, iClient, CTFPlayer_Event_Killed_Pre );
    PSM_DHookEntityByName( "CTFPlayer::Event_Killed", Hook_Post, iClient, CTFPlayer_Event_Killed_Post );
    if ( !IsFakeClient( iClient ) )
    {
        PSM_DHookEntityByName( "CTFPlayer::ShouldTransmit", Hook_Pre, iClient, CTFPlayer_ShouldTransmit_Pre );
        PSM_DHookEntityByName( "CTFPlayer::ShouldGib", Hook_Pre, iClient, CTFPlayer_ShouldGib_Pre );
        PSM_DHookEntityByName( "CTFPlayer::IsAllowedToPickUpFlag", Hook_Post, iClient, CTFPlayer_IsAllowedToPickUpFlag_Post );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnClientCookiesCached

  Summary:  Called once a client's saved cookies have been loaded
            from the database.

            We use this function to determine whether to
            automatically enable instructions for a player.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnClientCookiesCached( int iClient )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( IsFakeClient( iClient ) )
    {
        return;
    }

    // Check if this is the first time this client joined the server
    if ( g_hShowInstrctions.GetInt( iClient, 2 ) == 2 )
    {
        if ( SteamWorks_HasLicenseForApp( iClient, 459 ) == k_EUserHasLicenseResultHasLicense )
        {
            g_hShowInstrctions.SetInt( iClient, 0 );
        }
        else
        {
            /*--------------------------------------------------------------------
              The client doesn't own "Team Fortress 2 - Premium DLC", so we can
              assume that this player is new to the game, doesn't fully
              understand how Mann vs. Machine works, and needs instructions.
            --------------------------------------------------------------------*/
            g_hShowInstrctions.SetInt( iClient, 1 );
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnClientDisconnect

  Summary:  This function is called when a client is disconnecting
            from the server.

            We use this function to reset clients' globals.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnClientDisconnect( int iClient )
{
    if ( g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        RestoreBot( iClient );
    }
    else if ( g_aBotAttribs[ iClient ].IsControlled() )
    {
        // The bot got kicked; let's avoid crashes
        RestoreBot( GetClientFromSerial( g_aBotAttribs[ iClient ].iPlayerSerial ) );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnActionCreated

  Summary:  This function is called when a NextBot entity's action
            changes.

  Args:     BehaviorAction BotAction
              Action being created.
            int iClient
              NextBot entity index whose action changed.
            const char[] szName
              Action name.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnActionCreated( BehaviorAction BotAction, int iClient, const char[] szName )
{
    if ( StrEqual( szName, "MissionSuicideBomber" ) )
    {
        BotAction.Update = CTFBotMissionSuicideBomber_Update;
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPlayerRunCmdPre

  Summary:  This function is called when a clients movement buttons
            are being processed. (Read Only)

            This function takes care of miscellanious player-specific
            logic.

  Args:     int iClient
              Client index.
            int iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int iImpulse
              The current impulse command.
            const float vecVelocity[ 3 ]
              Player's velocity.
            const float angEyeAngles[ 3 ]
              Player's view angles.
            int iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int iSubtype
              Weapon subtype when selected from a menu.
            int iCmdNum
              Command number. Increments from the first command sent.
            int iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            const int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPlayerRunCmdPre(
    int         iClient,
    int         iButtons,
    int         iImpulse,
    const float vecVelocity[ 3 ],
    const float angEyeAngles[ 3 ],
    int         iWeapon,
    int         iSubType,
    int         iCmdNum,
    int         iTickCount,
    int         iSeed,
    const int   posMouse[ 2 ]
    )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( !g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        return;
    }

    GivePlayerAmmo( iClient, 100, TF_AMMO_METAL, true );
    SetEntPropFloat( iClient, Prop_Send, "m_flCloakMeter", 100.0 );

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    /*--------------------------------------------------------------------
      `bInSpawn` gets set to `true` once the player touches the invading
      team's `func_respawnroom` entity and we must set it to `false`
      manually.
    --------------------------------------------------------------------*/
    if ( g_aPlayerAttribs[ iClient ].bInSpawn )
    {
        /*--------------------------------------------------------------------
          The way the game itself determines if a bot is in the respawn room
          is not by vector location, but by the last nav area the bot stepped
          onto. This makes it so that if the invading team has a large drop
          when exiting spawn, the bot will still be considered as being in
          the respawn room until it lands on the ground. `CTFPlayer` doesn't
          have a `GetLastKnownArea` member function, and this is much better
          than manually keeping track of the last nav area we walked on.
        --------------------------------------------------------------------*/
        float vecOrigin[ 3 ];
        GetClientAbsOrigin( iClient, vecOrigin );
        if ( !TF2Util_IsPointInRespawnRoom( vecOrigin, iClient, true ) && ( GetEntityFlags( iClient ) & FL_ONGROUND ) )
        {
            // Player just stepped onto the ground outside the respawn room
            g_aPlayerAttribs[ iClient ].bInSpawn = false;
        }
    }

    if ( HasAttribute( iBot, ALWAYS_CRIT ) && !TF2_IsPlayerInCondition( iClient, TFCond_CritCanteen ) )
    {
        TF2_AddCondition( iClient, TFCond_CritCanteen );
    }

    if ( g_aPlayerAttribs[ iClient ].bInSpawn )
    {
        // Invading players get uber while they leave their spawn so they don't drop their cash where players can't pick it up
        TF2_AddCondition( iClient, TFCond_Ubercharged, 0.5 );
        TF2_AddCondition( iClient, TFCond_UberchargedHidden, 0.5 );
        TF2_AddCondition( iClient, TFCond_UberchargeFading, 0.5 );
        TF2_AddCondition( iClient, TFCond_ImmuneToPushback, 1.0 );
    }

    if ( TF2_GetPlayerClass( iClient ) == TFClass_Medic )
    {
        int iActiveWeapon = TF2_GetClientActiveWeapon( iClient );
        if ( TF2Util_GetWeaponID( iActiveWeapon ) == TF_WEAPON_MEDIGUN )
        {
            if ( GetMedigunType( iActiveWeapon ) == MEDIGUN_RESIST )
            {
                // If I'm a Vaccinnator medic and am told to prefer a certain type of resist, then cycle to that resist
                while ( HasAttribute( iBot, PREFER_VACCINATOR_BULLETS ) && GetResistType( iActiveWeapon ) != MEDIGUN_BULLET_RESIST ||
                        HasAttribute( iBot, PREFER_VACCINATOR_BLAST )   && GetResistType( iActiveWeapon ) != MEDIGUN_BLAST_RESIST  ||
                        HasAttribute( iBot, PREFER_VACCINATOR_FIRE )    && GetResistType( iActiveWeapon ) != MEDIGUN_FIRE_RESIST )
                {
                    CycleResistType( iActiveWeapon );
                }
            }
        }
    }

    if ( HasMission( iBot, MISSION_DESTROY_SENTRIES ) )
    {
        // Prevent other plugins from unsetting this flag
        DebugOverlayBits_t fDebugOverlays = view_as< DebugOverlayBits_t >( GetEntProp( iClient, Prop_Data, "m_debugOverlays" ) );
        if ( !( fDebugOverlays & OVERLAY_BUDDHA_MODE ) )
        {
            SetEntProp( iClient, Prop_Data, "m_debugOverlays", fDebugOverlays | OVERLAY_BUDDHA_MODE );
        }

        // This handles the bug described in https://developer.valvesoftware.com/wiki/Buddha
        if ( GetClientHealth( iClient ) == 1 && HasMission( iBot, MISSION_DESTROY_SENTRIES ) )
        {
            // Prevent the player from getting kicked for spamming commands
            if ( IsAllowedToTaunt( iClient ) )
            {
                FakeClientCommand( iClient, "taunt" );
            }
        }

        if ( GetGameTime() > g_aPlayerAttribs[ iClient ].flTalkTimer )
        {
            g_aPlayerAttribs[ iClient ].flTalkTimer = GetGameTime() + 4.0;
            EmitGameSoundToAll( "MVM.SentryBusterIntro", iClient );
        }

        int nSentries        = 0;
        int iObjectSentrygun = -1;
        while ( ( iObjectSentrygun = FindEntityByClassname( iObjectSentrygun, "obj_sentrygun" ) ) != -1 )
        {
            if ( view_as< TFTeam >( GetEntProp( iObjectSentrygun, Prop_Send, "m_iTeamNum" ) ) == TF_TEAM_PVE_DEFENDERS )
            {
                nSentries++;
            }
        }

        if ( nSentries == 0 )
        {
            // Blow up right where we are if there are no more enemy sentries
            SDKHooks_TakeDamage( iClient, iClient, iClient, FLT_MAX, DMG_PREVENT_PHYSICS_FORCE );
        }
    }

    if ( GetDeployingBombState( iClient ) == TF_BOMB_DEPLOYING_NONE )
    {
        if ( HasTheFlag( iClient ) )
        {
            /*--------------------------------------------------------------------
              TODO: Maybe keep track of the flag carrier in
              `HandleTeamplayFlagEvent_Pre` and move this logic to `OnGameFrame`?
            --------------------------------------------------------------------*/
            if ( UpgradeOverTime( iClient ) )
            {
                // Force the player to taunt
                g_aPlayerAttribs[ iClient ].bPendingTaunt = true;
            }
        }
    }

    // Instruct the player on what to do
    ShowInstruction( iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPlayerRunCmd

  Summary:  This function is called when a clients movement buttons
            are being processed.

            This function shows our HUD messages realted to taking
            control of a bot to clients spectating an invaing bot.

  Args:     int iClient
              Client index.
            int& iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int& iImpulse
              The current impulse command.
            float vecVelocity[ 3 ]
              Player's velocity.
            float angEyeAngles[ 3 ]
              Player's view angles.
            int& iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int& iSubtype
              Weapon subtype when selected from a menu.
            int& iCmdNum
              Command number. Increments from the first command sent.
            int& iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int& iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  Action
              `Plugin_Handled` to block the commands from being
              processed, `Plugin_Continue` otherwise.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public Action OnPlayerRunCmd(
    int   iClient,
    int&  iButtons,
    int&  iImpulse,
    float vecVelocity[ 3 ],
    float angEyeAngles[ 3 ],
    int&  iWeapon,
    int&  iSubType,
    int&  iCmdNum,
    int&  iTickCount,
    int&  iSeed,
    int   posMouse[ 2 ]
    )
{
    if ( !g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        return Plugin_Continue;
    }

    int iOrigButtons = iButtons; // Save the original commands

    HandleMovement( iClient, iButtons, iImpulse, vecVelocity, angEyeAngles, iWeapon, iSubType, iCmdNum, iTickCount, iSeed, posMouse );
    HandleAttack( iClient, iButtons, iImpulse, vecVelocity, angEyeAngles, iWeapon, iSubType, iCmdNum, iTickCount, iSeed, posMouse );

    BombDeployingState_t eBombDeployingState = GetDeployingBombState( iClient );
    if ( eBombDeployingState != TF_BOMB_DEPLOYING_NONE )
    {
        // No moving or attacking while deploying
        iButtons   &= ~( IN_ATTACK   | IN_ATTACK2  | IN_ATTACK3 |
                         IN_JUMP     | IN_DUCK     | IN_FORWARD |
                         IN_BACK     | IN_LEFT     | IN_RIGHT   |
                         IN_MOVELEFT | IN_MOVERIGHT );
        vecVelocity = { 0.0, 0.0, 0.0 };

        int iCaptureZone = -1;

        if ( eBombDeployingState != TF_BOMB_DEPLOYING_COMPLETE )
        {
            iCaptureZone = GetClosestCaptureZone( iClient );
            if ( iCaptureZone == -1 )
            {
                return Plugin_Continue;
            }

            // If we've been moved, give up and go back to normal behavior
            const float flMovedRange = 20.0;
            if ( IsRangeGreaterThanVec( iClient, g_CarrierAttribs.vecAnchorPos, flMovedRange ) )
            {
                // TODO: Send an "mvm_bomb_deploy_reset_by_player" event

                if ( eBombDeployingState == TF_BOMB_DEPLOYING_ANIMATING )
                {
                    // Reset the in-progress deploy animation
                    DoAnimationEvent( iClient, PLAYERANIMEVENT_SPAWN );
                }

                if ( IsMiniBoss( iClient ) )
                {
                    // Minibosses can be pushed again
                    TF2Attrib_RemoveByName( iClient, "airblast vertical vulnerability multiplier" );
                }

                // See comment in `CaptureZone_StartTouchPost`
                // SetEntityFlags( iClient, GetEntityFlags( iClient ) & ~FL_FROZEN );
                // TF2_RemoveCondition( iClient, TFCond_FreezeInput );
                // SetEntityMoveType( iClient, MOVETYPE_WALK );
                // TF2_SetClientTauntCamMode( iClient, TauntCam_Disabled );

                SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_NONE );
                return Plugin_Continue;
            }

            // Slam facing towards bomb hole
            float vec[ 3 ];
            SubtractVectors( WorldSpaceCenter( iCaptureZone ), WorldSpaceCenter( iClient ), vec );
            NormalizeVector( vec, vec );

            float angDesiredAngles[ 3 ];
            GetVectorAngles( vec, angDesiredAngles );

            SnapEyeAngles( iClient, angDesiredAngles );
        }

        switch ( eBombDeployingState )
        {
        case TF_BOMB_DEPLOYING_DELAY:
        {
            if ( GetGameTime() > g_CarrierAttribs.flDeployTimer )
            {
                PlaySpecificSequence( iClient, "primary_deploybomb" );
                g_CarrierAttribs.flDeployTimer = GetGameTime() + tf_deploying_bomb_time.FloatValue;
                SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_ANIMATING );

                char szSoundName[ 32 ];
                if ( IsMiniBoss( iClient ) )
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.DeployBombGiant" );
                }
                else
                {
                    strcopy( szSoundName, sizeof( szSoundName ), "MVM.DeployBombSmall" );
                }
                EmitGameSoundToAll( szSoundName, iClient );

                PlayThrottledAlert( 255, "Announcer.MVM_Bomb_Alert_Deploying", 5.0 );
            }
        }

        case TF_BOMB_DEPLOYING_ANIMATING:
        {
            if ( GetGameTime() > g_CarrierAttribs.flDeployTimer )
            {
                if ( iCaptureZone != -1 )
                {
                    Capture( iCaptureZone, iClient );
                }

                g_CarrierAttribs.flDeployTimer = GetGameTime() + 2.0;
                BroadcastSound( 255, "Announcer.MVM_Robots_Planted" );
                SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_COMPLETE );
                SetEntProp( iClient, Prop_Data, "m_takedamage", DAMAGE_NO );
                AddEffects( iClient, EF_NODRAW );
                RemoveAllWeapons( iClient );
            }
        }

        case TF_BOMB_DEPLOYING_COMPLETE:
        {
            if ( GetGameTime() > g_CarrierAttribs.flDeployTimer )
            {
                SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_NONE );
                SetEntProp( iClient, Prop_Data, "m_takedamage", DAMAGE_YES );
                SDKHooks_TakeDamage( iClient, iClient, iClient, 99999.9, DMG_CRUSH );
            }
        }
        }
    }

    // Stop the client-side attack animations
    int iActiveWeapon = TF2_GetClientActiveWeapon( iClient );
    if ( iActiveWeapon != -1 )
    {
        // We manually blocked IN_ATTACK
        if ( ( iOrigButtons & IN_ATTACK ) && !( iButtons & IN_ATTACK ) )
        {
            SetEntPropFloat( iActiveWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.5 );
        }

        // We manually blocked IN_ATTACK2
        if ( ( iOrigButtons & IN_ATTACK2 ) && !( iButtons & IN_ATTACK2 ) )
        {
            SetEntPropFloat( iActiveWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 0.5 );
        }
    }

    return Plugin_Continue;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPlayerRunCmdPost

  Summary:  This function is called alled after a clients movement
            buttons were processed.

            This function shows our HUD messages realted to taking
            control of a bot to clients spectating an invaing bot.

  Args:     int iClient
              Client index.
            int iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int iImpulse
              The current impulse command.
            const float vecVelocity[ 3 ]
              Player's velocity.
            const float angEyeAngles[ 3 ]
              Player's view angles.
            int iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int iSubtype
              Weapon subtype when selected from a menu.
            int iCmdNum
              Command number. Increments from the first command sent.
            int iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            const int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPlayerRunCmdPost(
    int         iClient,
    int         iButtons,
    int         iImpulse,
    const float vecVelocity[ 3 ],
    const float angEyeAngles[ 3 ],
    int         iWeapon,
    int         iSubType,
    int         iCmdNum,
    int         iTickCount,
    int         iSeed,
    const int   posMouse[ 2 ]
    )
{
    if ( !PSM_IsEnabled() )
    {
        return;
    }

    if ( IsFakeClient( iClient ) )
    {
        // Bots can't control other bots
        return;
    }

    if ( TF2_GetClientTeam( iClient ) != TFTeam_Spectator )
    {
        /*--------------------------------------------------------------------
          A player must choose the bot they wish to take control of by
          spectating them.
        --------------------------------------------------------------------*/
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( GameRules_GetRoundState() != RoundState_RoundRunning )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
    if ( iObserverMode != OBS_MODE_IN_EYE && iObserverMode != OBS_MODE_CHASE )
    {
        /*--------------------------------------------------------------------
          Only allow a player to control a bot if they're specifically
          spectating it, not just free roaming around the map.
        --------------------------------------------------------------------*/
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    static int c_iPrevObserverTargetSerial = 0;
    int        iObserverTarget             = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

    /*--------------------------------------------------------------------
      This check is needed because NextBots such as skeletons and
      Merasmus are also fake clients, but do not inherit `CTFPlayer`.
    --------------------------------------------------------------------*/
    if ( !IsPlayerIndex( iObserverTarget ) )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( !IsFakeClient( iObserverTarget ) )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_GetClientTeam( iObserverTarget ) != TF_TEAM_PVE_INVADERS )
    {
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( !IsPlayerAlive( iObserverTarget ) )
    {
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( g_nDefenders < sm_botcontrol_min_defenders.IntValue )
    {
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( g_nInvaders >= sm_botcontrol_max_invaders.IntValue  )
    {
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
    {
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Charging ) )
    {
        /*--------------------------------------------------------------------
          Disallow taking control of a bot while it's charging, so we don't
          have to implement logic to force a charge with a non-full charge
          meter.
        --------------------------------------------------------------------*/
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    // TODO: Allow players to take control of stunned bots
    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) )
    {
        /*--------------------------------------------------------------------
          For now just disallow taking control of stunned bots. Making this
          work correctly is a bit of a hassle. We'll just do it sometime in
          the future.
        --------------------------------------------------------------------*/
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( GetDeployingBombState( iObserverTarget ) != TF_BOMB_DEPLOYING_NONE )
    {
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( HasMission( iObserverTarget, MISSION_DESTROY_SENTRIES ) && GetClientHealth( iObserverTarget ) == 1 )
    {
        // Sentry buster is already detonating; can't control it anymore
        c_iPrevObserverTargetSerial = 0; // Force redraw
        ClearSyncHud( iClient, g_hSyncObj );
        return;
    }

    if ( TF2_GetPlayerClass( iObserverTarget ) == TFClass_Spy || HasAttribute( iObserverTarget, TELEPORT_TO_HINT ) )
    {
        // The game needs to teleport these bots out of their spawn room
        if ( TF2_IsPlayerInSpawnRoom( iObserverTarget ) )
        {
            c_iPrevObserverTargetSerial = 0; // Force redraw
            ClearSyncHud( iClient, g_hSyncObj );
            return;
        }
    }
    else
    {
        // Upon spawning, it takes the game one second to decide whether to give a bot the bomb
        if ( GetGameTime() - GetSpawnTime( iObserverTarget ) <= 1.0 )
        {
            c_iPrevObserverTargetSerial = 0; // Force redraw
            ClearSyncHud( iClient, g_hSyncObj );
            return;
        }
    }

    // Don't continuously redraw the HUD message if the target hasn't changed
    int iObserverTargetSerial = GetClientSerial( iObserverTarget );
    if ( iObserverTargetSerial == c_iPrevObserverTargetSerial )
    {
        return;
    }
    c_iPrevObserverTargetSerial = iObserverTargetSerial;

    // Shove it in the middle-ish of their screens
    SetHudTextParams( -1.0, 0.4, FLT_MAX, 255, 255, 0, 255 );

    // Check if the bot has any custom description set
    Address pCustomDesc = TF2Attrib_GetByName( iObserverTarget, "custom desc attr" );
    if ( pCustomDesc )
    {
        char szDesc[ 8 ] = "";
        TF2Attrib_UnsafeGetStringValue( TF2Attrib_GetValue( pCustomDesc ), szDesc, sizeof( szDesc ) );

        if ( StrEqual( szDesc, "block", false ) )
        {
            // Players can't control this bot
            ShowSyncHudText( iClient, g_hSyncObj, "%t", "Bot_Block" );
            return;
        }
        else if ( StrEqual( szDesc, "premium", false ) )
        {
            char szFlags[ 32 ];
            sm_botcontrol_premium_flags.GetString( szFlags, sizeof( szFlags ) );
            if ( !( GetUserFlagBits( iClient ) & ReadFlagString( szFlags ) ) )
            {
                // Only players with the required flag(s) can control this bot
                ShowSyncHudText( iClient, g_hSyncObj, "%t", "Bot_Premium" );
                return;
            }
        }
        else if ( StrEqual( szDesc, "group", false ) )
        {
            if ( !g_aPlayerAttribs[ iClient ].bIsGroupMember )
            {
                // Only players that are members of the Steam group can control this bot
                ShowSyncHudText( iClient, g_hSyncObj, "%t", "Bot_Group" );
                return;
            }
        }
    }

    ShowSyncHudText( iClient, g_hSyncObj, "%t", "Control_Bot" );
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: PlayerControlBot

  Summary:  This callback function is called every time a player
            calls for a medic. If the player is a spectator, and
            their observer target is a bot, it shelves the bot and
            spawns the client with the index `iClient` into the
            exact state the bot was, exactly mirroring its position,
            weapons, conditions, etc.

  Args:     int iClient
              Client index of the client that called for a medic.
            TFVoiceCommand eVoiceCommand
              The type of voice command. In the case of this callback,
              this parameter will always be `Voice_Medic`.

  Returns:  Action
              `Plugin_Continue` to continue the forward calls,
              `Plugin_Handled` to stop the calling chain,
              `Plugin_Stop` to block the voice command.
-----------------------------------------------------------------F-F*/
Action PlayerControlBot( int iClient, TFVoiceCommand eVoiceCommand )
{
    if ( iClient == 0 )
    {
        /*--------------------------------------------------------------------
          The server should never execute "voicemenu" as it doens't do
          anything, but let's avoid a crash.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    if ( !IsClientInGame( iClient ) )
    {
        /*--------------------------------------------------------------------
          Again, clients not yet in the game have no reason to execute
          "voicemenu", but we guard against this too.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    if ( IsFakeClient( iClient ) )
    {
        // Bots can't control other bots
        return Plugin_Continue;
    }

    /*--------------------------------------------------------------------
      A player must choose the bot they wish to take control of by
      spectating them.
    --------------------------------------------------------------------*/
    if ( TF2_GetClientTeam( iClient ) != TFTeam_Spectator )
    {
        return Plugin_Continue;
    }

    if ( GameRules_GetRoundState() != RoundState_RoundRunning )
    {
        return Plugin_Continue;
    }

    int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
    if ( iObserverMode != OBS_MODE_IN_EYE && iObserverMode != OBS_MODE_CHASE )
    {
        /*--------------------------------------------------------------------
          Only allow a player to control a bot if they're specifically
          spectating it, not just free roaming around the map.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    int iObserverTarget = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

    /*--------------------------------------------------------------------
      This check is needed because NextBots such as skeletons and
      Merasmus are also fake clients, but do not inherit `CTFPlayer`.
    --------------------------------------------------------------------*/
    if ( !IsPlayerIndex( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

    if ( !IsFakeClient( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

    if ( TF2_GetClientTeam( iObserverTarget ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Continue;
    }

    if ( !IsPlayerAlive( iObserverTarget ) )
    {
        return Plugin_Continue;
    }

    if ( g_nDefenders < sm_botcontrol_min_defenders.IntValue )
    {
        PrintHintText( iClient, "%t", "Cannot_Control_Insufficient_Defenders", g_nDefenders, sm_botcontrol_min_defenders.IntValue );
        return Plugin_Continue;
    }

    if ( g_nInvaders >= sm_botcontrol_max_invaders.IntValue  )
    {
        PrintHintText( iClient, "%t", "Cannot_Control_Maximum_Invaders", g_nInvaders, sm_botcontrol_max_invaders.IntValue );
        return Plugin_Continue;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
    {
        PrintHintText( iClient, "%t", "Cannot_Control_Taunting" );
        return Plugin_Continue;
    }

    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Charging ) )
    {
        /*--------------------------------------------------------------------
          Disallow taking control of a bot while it's charging so we don't
          have to implement logic to force a charge with a non-full charge
          meter.
        --------------------------------------------------------------------*/
        PrintHintText( iClient, "%t", "Cannot_Control_Charging" );
        return Plugin_Continue;
    }

    // TODO: Allow players to take control of stunned bots
    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) )
    {
        /*--------------------------------------------------------------------
          For now just disallow taking control of stunned bots. Making this
          work correctly is a bit of a hassle. We'll just do it sometime in
          the future.
        --------------------------------------------------------------------*/
        PrintHintText( iClient, "%t", "Cannot_Control_Stunned" );
        return Plugin_Continue;
    }

    if ( GetDeployingBombState( iObserverTarget ) != TF_BOMB_DEPLOYING_NONE )
    {
        return Plugin_Continue;
    }

    if ( HasMission( iObserverTarget, MISSION_DESTROY_SENTRIES ) && GetClientHealth( iObserverTarget ) == 1 )
    {
        // Sentry buster is already detonating; can't control it anymore
        return Plugin_Continue;
    }

    TFClassType eBotClass = TF2_GetPlayerClass( iObserverTarget );
    if ( eBotClass == TFClass_Spy || HasAttribute( iObserverTarget, TELEPORT_TO_HINT ) )
    {
        // The game needs to teleport these bots out of their spawn room
        if ( TF2_IsPlayerInSpawnRoom( iObserverTarget ) )
        {
            PrintHintText( iClient, "%t", "Cannot_Control_In_Spawn" );
            return Plugin_Continue;
        }
    }
    else
    {
        // Upon spawning, it takes the game one second to decide whether to give a bot the bomb
        if ( GetGameTime() - GetSpawnTime( iObserverTarget ) <= 1.0 )
        {
            return Plugin_Continue;
        }
    }

    // Check if the bot has any custom description set
    Address pCustomDesc = TF2Attrib_GetByName( iObserverTarget, "custom desc attr" );
    if ( pCustomDesc )
    {
        char szDesc[ 8 ] = "";
        TF2Attrib_UnsafeGetStringValue( TF2Attrib_GetValue( pCustomDesc ), szDesc, sizeof( szDesc ) );

        if ( StrEqual( szDesc, "block", false ) )
        {
            // Players can't control this bot
            return Plugin_Continue;
        }
        else if ( StrEqual( szDesc, "premium", false ) )
        {
            char szFlags[ 32 ];
            sm_botcontrol_premium_flags.GetString( szFlags, sizeof( szFlags ) );
            if ( !( GetUserFlagBits( iClient ) & ReadFlagString( szFlags ) ) )
            {
                // Only players with the required flag(s) can control this bot
                return Plugin_Continue;
            }
        }
        else if ( StrEqual( szDesc, "group", false ) )
        {
            if ( !g_aPlayerAttribs[ iClient ].bIsGroupMember )
            {
                // Only players that are members of the group can control this bot
                return Plugin_Continue;
            }
        }
    }

    /*--------------------------------------------------------------------
      Our observer target passes all checks. From here on down we mirror
      the bot, shelve it, and drop the player in its place.
    --------------------------------------------------------------------*/

    /*--------------------------------------------------------------------
      We save the player's currency amount from before they took control
      of the bot because `m_nCurrency` is overwritten when the game
      tries to determine how much currency the invader should drop.
    --------------------------------------------------------------------*/
    g_aPlayerAttribs[ iClient ].nInitialCurrency = GetCurrency( iClient );

    /*--------------------------------------------------------------------
      Only checking for the `TFCond_Zoomed` condition should not cause
      a crash unless some other plugin applies this condition on a bot
      that's not a Sniper for some reason.
    --------------------------------------------------------------------*/
    if ( TF2_IsPlayerInCondition( iObserverTarget, TFCond_Zoomed ) )
    {
        // Zoom out of the sniper rifle so the lazer disappears and doesn't cause problems
        ZoomOut( TF2_GetClientActiveWeapon( iObserverTarget ) );
    }

    // The `FL_FAKECLIENT` flag must be set for a client to join the invading team
    FakeBotStatus( iClient );
    TF2_ChangeClientTeam( iClient, TF_TEAM_PVE_INVADERS );
    RestorePlayerStatus( iClient );

    /*--------------------------------------------------------------------
      These have to be set AFTER changing teams, but BEFORE spawning the
      player. For the reason, see the "player_spawn" and "player_team"
      event handlers.
    --------------------------------------------------------------------*/
    g_aPlayerAttribs[ iClient ].iBotSerial         = GetClientSerial( iObserverTarget );
    g_aBotAttribs[ iObserverTarget ].iPlayerSerial = GetClientSerial( iClient );

    // Spawn the player so we can give them their weapons, wearables, model, and so on
    TF2_RespawnPlayer( iClient );

    if ( eBotClass != TF2_GetPlayerClass( iClient ) )
    {
        /*--------------------------------------------------------------------
          We don't want to make it persistent in case the player wants to
          join denfeders mid-round and continue playing as the class they
          were last playing as.
        --------------------------------------------------------------------*/
        TF2_SetPlayerClass( iClient, eBotClass, _, false );
    }

    // Strip everything
    RemoveAllItems( iClient );
    TF2Attrib_RemoveAll( iClient );
    TF2_RemoveCondition( iClient, TFCond_SpawnOutline );

    // FIXME: This only changes the player's name in chat
    if ( sm_botcontrol_mirror_name.BoolValue )
    {
        // Save the name so we can restore it after the player is done controlling the bot
        strcopy( g_aPlayerAttribs[ iClient ].szOriginalName, sizeof( g_aPlayerAttribs[ iClient ].szOriginalName ), GetPlayerName( iClient ) );

        SetPlayerName( iClient, GetPlayerName( iObserverTarget ) );
    }

    /*--------------------------------------------------------------------
      `m_bIsABot` can stay spoofed the whole time as the game has no
      paths where it tries to access `CTFBot` properties on the entity
      when it's `true`. `m_bIsABot` makes the `IsABot()` client call
      return `true`, which takes care of creating the recently teleported
      particle effect, forces entities attached to the player to always
      be validated, and applies the radiowave effect on bots.
    --------------------------------------------------------------------*/
    SetEntProp( iClient, Prop_Send, "m_bIsABot", true );

    CopyEntProp( iObserverTarget, iClient, Prop_Send, "m_nBotSkill" ); // Sets the bot eye glow color
    CopyEntProp( iObserverTarget, iClient, Prop_Send, "m_bIsMiniBoss" );
    CopyEntProp( iObserverTarget, iClient, Prop_Send, "m_bUseBossHealthBar" );
    CopyEntProp( iObserverTarget, iClient, Prop_Data, "m_bloodColor" );
    ModifyMaxHealth( iClient, TF2Util_GetEntityMaxHealth( iObserverTarget ), false, false );
    CopyEntProp( iObserverTarget, iClient, Prop_Send, "m_iHealth" );
    // TODO: Uncomment the line below when we've got a working squad implementation
    // CopyEntProp( iObserverTarget, iClient, Prop_Send, "m_nNumHealers" );
    CopyEntPropFloat( iObserverTarget, iClient, Prop_Send, "m_flRageMeter" );

    // Turn this off on the bot, so we don't end up with 2 health bars on the screen
    ClearAttribute( iObserverTarget, USE_BOSS_HEALTH_BAR ); // Prevents entity from always transmitting
    SetUseBossHealthBar( iObserverTarget, false );

    // Mimic currency drop amount
    SetWaveSpawnPopulator( iClient, view_as< Address >( GetEntData( iObserverTarget, g_CTFPlayer_pWaveSpawnPopulator_Offset, PTRSIZ ) ) );

    if ( IsMissionEnemy( iObserverTarget ) )
    {
        MarkAsMissionEnemy( iClient );
    }

    // Let the bot take care of decrementing the wave class count
    MarkAsSupportEnemy( iClient );

    // Mirror the bot's conditions
    TFCond eLastCond = TF2Util_GetLastCondition();
    for ( TFCond eCond = TFCond_Slowed; eCond <= eLastCond; eCond++ )
    {
        int   iProvider;
        float flDuration;
        switch ( eCond )
        {
        /*--------------------------------------------------------------------
          Don't mirror spawn protection conditions, since we apply them in a
          different way compared to how the game does it.
        --------------------------------------------------------------------*/
        case TFCond_Ubercharged, TFCond_CloakFlicker, TFCond_UberchargedHidden, TFCond_ImmuneToPushback:
        {
            continue;
        }

        /*--------------------------------------------------------------------
          Burning and bleeding need to be handled separately due to how the
          game itself handles them.
        --------------------------------------------------------------------*/
        case TFCond_OnFire:
        {
            iProvider  = TF2Util_GetPlayerConditionProvider( iObserverTarget, eCond );
            flDuration = TF2Util_GetPlayerBurnDuration( iObserverTarget );
            // TODO: Find a way to get the weapon that ignited the player
            if ( flDuration != 0.0 )
            {
                TF2Util_IgnitePlayer( iClient, iProvider, flDuration );
            }
        }

        case TFCond_Bleeding:
        {
            int nBleedCount = TF2Util_GetPlayerActiveBleedCount( iObserverTarget );
            for ( int i = 0; i < nBleedCount; i++ )
            {
                iProvider         = TF2Util_GetPlayerBleedAttacker( iObserverTarget, i );
                int iWeapon       = TF2Util_GetPlayerBleedWeapon( iObserverTarget, i );
                flDuration        = TF2Util_GetPlayerBleedDuration( iObserverTarget, i );
                int iDamage       = TF2Util_GetPlayerBleedDamage( iObserverTarget, i );
                int iDamageCustom = TF2Util_GetPlayerBleedCustomDamageType( iObserverTarget, i );
                TF2Util_MakePlayerBleed( iClient, iProvider, flDuration, iWeapon, iDamage, iDamageCustom );
            }
        }

        default:
        {
            iProvider  = TF2Util_GetPlayerConditionProvider( iObserverTarget, eCond );
            flDuration = TF2Util_GetPlayerConditionDuration( iObserverTarget, eCond );
            if ( iProvider != INVALID_ENT_REFERENCE && flDuration != 0.0 )
            {
                TF2_AddCondition( iClient, eCond, flDuration, iProvider );
            }
        }
        }
    }

    // Mirror the bot's attributes
    if ( HasAttribute( iObserverTarget, BULLET_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_BulletImmune );
    }

    if ( HasAttribute( iObserverTarget, BLAST_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_BlastImmune );
    }

    if ( HasAttribute( iObserverTarget, FIRE_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_FireImmune );
    }

    if ( HasAttribute( iObserverTarget, IGNORE_FLAG ) )
    {
        TF2Attrib_SetByName( iClient, "cannot pick up intelligence", 1.0 );
    }

    // TODO: Allow invader engineers to pick up their buildings
    if ( TF2_GetPlayerClass( iObserverTarget ) == TFClass_Engineer )
    {
        /*--------------------------------------------------------------------
          We don't let invader engineers pick up their buildings because
          we'd have to take care of manually starting, stopping, and
          destroying the teleporter beam particle. Right now we parent the
          teleporter beam particle to the teleporter so it gets removed with
          it, but if a player picks up their teleporter, the beam follows them.
          Moreover, since we apply the beam on `CObjectTeleporter::FinishedBuilding`,
          we'd end up with multiple beams being created every time the
          teleporter exit gets placed down and finishes building.
        --------------------------------------------------------------------*/
        TF2Attrib_SetByName( iClient, "cannot pick up buildings", 1.0 );
    }

    if ( HasMission( iObserverTarget, MISSION_DESTROY_SENTRIES ) )
    {
        // Sentry busters don't use their weapons and don't pick up the bomb
        TF2Attrib_SetByName( iClient, "no_attack", 1.0 );
        TF2Attrib_SetByName( iClient, "cannot pick up intelligence", 1.0 );

        // Sentry busters don't die, they detonate
        DebugOverlayBits_t fDebugOverlays = view_as< DebugOverlayBits_t >( GetEntProp( iClient, Prop_Data, "m_debugOverlays" ) );
        SetEntProp( iClient, Prop_Data, "m_debugOverlays", fDebugOverlays | OVERLAY_BUDDHA_MODE );
    }

    // Mirror the character attributes
    int aiAttributeDefinitionIndices[ MAX_ATTRIBUTES_PER_ITEM ];
    int nAttribs = TF2Attrib_ListDefIndices( iObserverTarget, aiAttributeDefinitionIndices, sizeof( aiAttributeDefinitionIndices ) );
    for ( int i = 0; i < nAttribs; i++ )
    {
        TF2Attrib_SetByDefIndex(
                                iClient,
                                aiAttributeDefinitionIndices[ i ],
                                TF2Attrib_GetValue( TF2Attrib_GetByDefIndex( iObserverTarget, aiAttributeDefinitionIndices[ i ] ) )
                               );
    }

    // Mirror the bot's weapons
    for ( int i = 0; i <= TFWeaponSlot_PDA; i++ )
    {
        int iWeapon = GetPlayerWeaponSlot( iObserverTarget, i );
        if ( iWeapon == -1 )
        {
            continue;
        }

        int iNewWeapon = CopyItem( iWeapon, iClient );
        if ( iNewWeapon == -1 )
        {
            continue;
        }

        if ( TF2Util_GetWeaponID( iNewWeapon ) == TF_WEAPON_BUILDER )
        {
            SetSubType( iNewWeapon, GetEntProp( iWeapon, Prop_Send, "m_aBuildableObjectTypes", 1, 0 ) );
        }

        EquipPlayerWeapon( iClient, iNewWeapon );

        TF2_SetWeaponAmmo( iNewWeapon, TF2_GetWeaponAmmo( iWeapon ) );

        /*--------------------------------------------------------------------
          Force the player to switch to this weapon if we mirrored the bot's
          current active weapon.
        --------------------------------------------------------------------*/
        if ( TF2_GetClientActiveWeapon( iObserverTarget ) == iWeapon )
        {
            TF2Util_SetPlayerActiveWeapon( iClient, iNewWeapon );
        }
    }

    if ( eBotClass == TFClass_Medic )
    {
        int iPlayerMedigun = GetPlayerWeaponSlot( iClient, TFWeaponSlot_Secondary );
        int iBotMedigun    = GetPlayerWeaponSlot( iObserverTarget, TFWeaponSlot_Secondary );
        /*--------------------------------------------------------------------
          Both the player and bot have the same weapons and its not possible
          for the bot's weapon entity to have been deleted since the for loop
          above.
        --------------------------------------------------------------------*/
        if ( iPlayerMedigun != -1 )
        {
            if ( TF2Util_GetWeaponID( iPlayerMedigun ) == TF_WEAPON_MEDIGUN )
            {
                CopyEntPropFloat( iBotMedigun, iPlayerMedigun, Prop_Send, "m_flChargeLevel" );
                CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_nChargeResistType" );
                CopyEntPropEnt( iBotMedigun, iPlayerMedigun, Prop_Send, "m_hHealingTarget" );
                CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bAttacking" );
                CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bHealing" );
                CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bChargeRelease" );

                SetEntPropFloat( iBotMedigun, Prop_Send, "m_flChargeLevel", 0.0 ); // Hide the medigun effect
                SetEntPropEnt( iBotMedigun, Prop_Send, "m_hHealingTarget", -1 );   // Remove the medigun beam
                SetEntProp( iBotMedigun, Prop_Send, "m_bAttacking", false );
                SetEntProp( iBotMedigun, Prop_Send, "m_bHealing", false );
            }
        }
    }

    Address pData = GetPlayerClassData( eBotClass ); // Both the player and bot have the same class
    if ( pData )
    {
        ManageBuilderWeapons( iClient, pData );
    }

    // Mirror weapon restriction
    PSM_SDKHook( iClient, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo );

    if ( eBotClass == TFClass_Engineer )
    {
        // Change ownership of the bot's buildings
        for ( int i = GetObjectCount( iObserverTarget ) - 1; i >= 0; i-- )
        {
            int iObject = GetObject( iObserverTarget, i );
            if ( iObject != -1 )
            {
                TransferObject( iObject, iClient );
            }
        }
    }

    // Mirror the bot's wearables
    int nWearables = TF2Util_GetPlayerWearableCount( iObserverTarget );
    for ( int i = 0; i < nWearables; i++ )
    {
        int iWearable = TF2Util_GetPlayerWearable( iObserverTarget, i );
        if ( iWearable == -1 )
        {
            continue;
        }

        // Don't mirror wearables that belong to the player we're disguised as
        if ( GetEntProp( iWearable, Prop_Send, "m_bDisguiseWearable" ) )
        {
            continue;
        }

        int iNewWearable = CopyItem( iWearable, iClient );
        if ( iNewWearable == -1 )
        {
            continue;
        }

        TF2Util_EquipPlayerWearable( iClient, iNewWearable );
    }

    // Tell the client to update the cached server loadout items
    BfWrite hMsg = UserMessageToBfWrite( StartMessageOne( "PlayerLoadoutUpdated", iClient, USERMSG_BLOCKHOOKS ) );
    hMsg.WriteByte( iClient );
    EndMessage();

    PostInventoryApplication( iClient );

    // Mirror the bot's model
    SetCustomModelWithClassAnimations( iClient, GetModelName( iObserverTarget ) );
    SetModelScale( iClient, GetModelScale( iObserverTarget ), 0.0 );

    if ( eBotClass == TFClass_Spy )
    {
        // Mirror the bot's disguise
        TFClassType eDisguiseClass = TF2_GetPlayerDisguiseClass( iObserverTarget );
        if ( eDisguiseClass != TFClass_Unknown )
        {
            int iDisguiseTarget = GetDisguiseTarget( iObserverTarget );
            if ( iDisguiseTarget != -1 && IsClientInGame( iDisguiseTarget ) && TF2_GetClientTeam( iDisguiseTarget ) == TF_TEAM_PVE_DEFENDERS )
            {
                TF2_DisguisePlayer( iClient, TF_TEAM_PVE_DEFENDERS, eDisguiseClass, iDisguiseTarget );
            }
            else
            {
                // The player the bot was disguised as disconnected
                TF2_DisguisePlayer( iClient, TF_TEAM_PVE_DEFENDERS, eDisguiseClass );
            }
        }
    }

    // TODO: Find a way to insert the player into the squad
    LeaveSquad( iObserverTarget );
    RemoveTag( iObserverTarget, "bot_squad_member" );

    if ( HasTheFlag( iObserverTarget ) )
    {
        g_aPlayerAttribs[ iClient ].bBlockFlagEvent      = true;
        g_aBotAttribs[ iObserverTarget ].bBlockFlagEvent = true;

        // Save these so we can restore them after the bomb swap
        int   nFlagCarrierUpgradeLevel = GetFlagCarrierUpgradeLevel();
        float flMvMBaseBombUpgradeTime = GetBaseMvMBombUpgradeTime();
        float flMvMNextBombUpgradeTime = GetNextMvMBombUpgradeTime();

        // Give the bomb to the player
        int iBomb = GetItem( iObserverTarget );
        DropFlag( iObserverTarget, true );
        /*--------------------------------------------------------------------
          BUGBUG: The player's HUD doesn't get updated and always points to
          the bomb on the player's back instead of the bomb hole.
        --------------------------------------------------------------------*/
        PickUp( iBomb, iClient, false );

        SetFlagCarrierUpgradeLevel( nFlagCarrierUpgradeLevel );
        SetBaseMvMBombUpgradeTime( flMvMBaseBombUpgradeTime );
        SetNextMvMBombUpgradeTime( flMvMNextBombUpgradeTime );

        // We need to manually set this because `bBlockFlagEvent` skips it
        if ( IsMiniBoss( iObserverTarget ) )
        {
            g_CarrierAttribs.iUpgradeLevel = DONT_UPGRADE;
        }
        else
        {
            g_CarrierAttribs.iUpgradeLevel = nFlagCarrierUpgradeLevel;
        }

        ApplyPreviousUpgrades( iClient );
    }

    /*--------------------------------------------------------------------
      Human invaders get just enough respawn time to watch the death
      animation and freezecam.
    --------------------------------------------------------------------*/
    float flTimeInFreeze = spec_freeze_traveltime.FloatValue + spec_freeze_time.FloatValue;
    TF2Util_SetPlayerRespawnTimeOverride( iClient, TF_DEATH_ANIMATION_TIME + flTimeInFreeze );

    // Stop the bot's idle sound because it can still be heard
    StopIdleSound( iObserverTarget );

    Address pNavArea = GetLastKnownArea( iObserverTarget );

    // Get the bot's current position
    float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
    GetClientAbsOrigin( iObserverTarget, vecOrigin );
    GetClientEyeAngles( iObserverTarget, angEyeAngles );
    GetEntPropVector( iObserverTarget, Prop_Data, "m_vecVelocity", vecVelocity );

    // Get the bot out of the playable area
    TeleportEntity( iObserverTarget, { 0.0, 0.0, 9999.0 } );
    LockPlayerInPlace( iObserverTarget );
    AddEffects( iObserverTarget, EF_NODRAW ); // Prevents the bot from being spectated

    // Teleport the player in its place
    TeleportEntity( iClient, vecOrigin, angEyeAngles, vecVelocity );

    StartIdleSound( iClient );

    PSM_SDKHook( iClient, SDKHook_OnTakeDamage, OnTakeDamage );

    if ( pNavArea && HasAttributeTF( pNavArea, TF_NAV_SPAWN_ROOM_BLUE ) && !( GetEntityFlags( iObserverTarget ) & FL_ONGROUND ) )
    {
        /*--------------------------------------------------------------------
          The player took control of the bot right after it exited the spawn
          room and there is a drop which would normally cause fall damage.
          We mark the player as being in spawn until they land on the ground
          to prevent any fall damage.
        --------------------------------------------------------------------*/
        g_aPlayerAttribs[ iClient ].bInSpawn = true;
    }

    // The game doesn't show the annotation if we do it too soon after spawning
    g_aPlayerAttribs[ iClient ].flLastInstructionTime = ( GetGameTime() - sm_botcontrol_instruction_interval.FloatValue + 1.0 );

    return Plugin_Handled;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandleTaunt

  Summary:  This function is called every time a player tries to
            taunt. It blocks all custom taunts for invading players
            and also takes care of detonating sentry busters.

  Args:     int iClient
              Index of client that sent the command.
            const char[] szCommand
              Name of the command as typed by the client. To get name
              as typed, use GetCmdArg() and specify argument 0.
            int argc
              Argument count.

  Returns:  Action
              `Plugin_Continue` to allow the server to process the
              command, `Plugin_Handled` or `Plugin_Stop` to block
              the command from being processed.
-----------------------------------------------------------------F-F*/
Action HandleTaunt( int iClient, const char[] szCommand, int argc )
{
    if ( iClient == 0 )
    {
        /*--------------------------------------------------------------------
          The server should never execute "taunt" as it doens't do anything,
          but let's avoid a crash.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    if ( !IsClientInGame( iClient ) )
    {
        /*--------------------------------------------------------------------
          Again, clients not yet in the game have no reason to execute
          "taunt", but we guard against this too.
        --------------------------------------------------------------------*/
        return Plugin_Continue;
    }

    if ( g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        if ( !IsAllowedToTaunt( iClient ) )
        {
            return Plugin_Continue;
        }

        if ( GetDeployingBombState( iClient ) != TF_BOMB_DEPLOYING_NONE )
        {
            // No taunting while deploying the bomb
            return Plugin_Stop;
        }

        if ( argc == 1 && ( 1 <= GetCmdArgInt( 1 ) <= 8 ) )
        {
            // Block custom taunts
            return Plugin_Stop;
        }

        int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );
        if ( HasMission( iBot, MISSION_DESTROY_SENTRIES ) )
        {
            RestoreBot( iClient );
            /*--------------------------------------------------------------------
              Have the player spectate the sentry buster as it detonates so the
              transition feels smoother instead of being assinged a random
              observer target.
            --------------------------------------------------------------------*/
            SetObserverTarget( iClient, iBot );
            // TODO: Manually call `CTFBotMissionSuicideBomber::StartDetonate` and manage the parameters
            SetEntityHealth( iBot, 1 );
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandleTeamplayFlagEvent_Pre

  Summary:  This function is called before every "teamplay_flag_event"
            event gets fired. Its main purpose is to handle pick up
            and drop events for human invaders.

  Args:     Event hEvent
              Handle to event.
            const char[] szName
              A string representing the name of the event. In the
              case of this function this will always be "teamplay_flag_event".
            bool bDontBroadcast
              If this variable is `true`, the event was not broadcast
              to clients. If this variable is `false`, the event was
              broadcast to clients.
              May not correspond to the real value. Use the property
              BroadcastDisabled.

  Returns:  Action
              `Plugin_Continue` to allow the event to be fired,
              `Plugin_Handled` to block the event.
-----------------------------------------------------------------F-F*/
Action HandleTeamplayFlagEvent_Pre( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iPlayer = hEvent.GetInt( "player" );

    if ( IsFakeClient( iPlayer ) )
    {
        // Check if this is the bot the player just took control of
        if ( g_aBotAttribs[ iPlayer ].bBlockFlagEvent )
        {
            g_aBotAttribs[ iPlayer ].bBlockFlagEvent = false;
            return Plugin_Handled;
        }

        // We don't want to do anything else to bots
        return Plugin_Continue;
    }

    if ( !g_aPlayerAttribs[ iPlayer ].IsControlling() )
    {
        return Plugin_Continue;
    }

    if ( g_aPlayerAttribs[ iPlayer ].bBlockFlagEvent )
    {
        g_aPlayerAttribs[ iPlayer ].bBlockFlagEvent = false;
        return Plugin_Handled;
    }

    int iEventType = hEvent.GetInt( "eventtype" );
    if ( iEventType == TF_FLAGEVENT_PICKEDUP )
    {
        if ( !tf_mvm_bot_allow_flag_carrier_to_fight.BoolValue )
        {
            TF2Attrib_SetByName( iPlayer, "no_attack", 1.0 );
        }

        // Mini-bosses don't upgrade - they are already tough
        if ( IsMiniBoss( iPlayer ) )
        {
            g_CarrierAttribs.iUpgradeLevel = DONT_UPGRADE;
        }
        else
        {
            g_CarrierAttribs.iUpgradeLevel = 0;
        }
        /*--------------------------------------------------------------------
          NOTE: Updating the objective resource happens in the
          `CCaptureFlag::PickUp` dynamic post hook because "teamplay_flag_event"
          is fired before the objective resource is updated.
        --------------------------------------------------------------------*/
    }
    else if ( iEventType == TF_FLAGEVENT_DROPPED )
    {
        TF2Attrib_RemoveByName( iPlayer, "no_attack" );

        ResetRageBuffs( iPlayer );
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandlePlayerTeamEvent_Pre

  Summary:  This function is called before every "player_team"
            event gets fired. Its main purpose is restore the bot
            of a human invader in case the player changes teams.

  Args:     Event hEvent
              Handle to event.
            const char[] szName
              A string representing the name of the event. In the
              case of this function this will always be "player_team".
            bool bDontBroadcast
              If this variable is `true`, the event was not broadcast
              to clients. If this variable is `false`, the event was
              broadcast to clients.
              May not correspond to the real value. Use the property
              BroadcastDisabled.

  Returns:  Action
              `Plugin_Continue` to allow the event to be fired,
              `Plugin_Handled` to block the event.
-----------------------------------------------------------------F-F*/
Action HandlePlayerTeamEvent_Pre( Event hEvent, const char[] szName, bool dDontBroadcast )
{
    int iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    if ( iClient != 0 && g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        RestoreBot( iClient );
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandlePlayerDeathEvent_Pre

  Summary:  This function is called before every "player_death"
            event gets fired and its purpose is to block controlled
            bot deaths from appearing in the killfeed.

  Args:     Event hEvent
              Handle to event.
            const char[] szName
              A string representing the name of the event. In the
              case of this function this will always be "player_death".
            bool bDontBroadcast
              If this variable is `true`, the event was not broadcast
              to clients. If this variable is `false`, the event was
              broadcast to clients.
              May not correspond to the real value. Use the property
              BroadcastDisabled.

  Returns:  Action
              `Plugin_Continue` to allow the event to be fired,
              `Plugin_Handled` to block the event.
-----------------------------------------------------------------F-F*/
/*Action HandlePlayerDeathEvent_Pre( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iVictim = hEvent.GetInt( "victim_entindex" );

    if ( g_aBotAttribs[ iVictim ].IsControlled() )
    {
        hEvent.SetBool( "silent_kill", true );
    }

    return Plugin_Continue;
}*/

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandlePlayerSpawnEvent_Pre

  Summary:  This function is called before every "player_spawn"
            event gets fired and its purpose is to change the team
            of human invaders that died and were respawned to
            spectators.

  Args:     Event hEvent
              Handle to event.
            const char[] szName
              A string representing the name of the event. In the
              case of this function this will always be "player_spawn".
            bool bDontBroadcast
              If this variable is `true`, the event was not broadcast
              to clients. If this variable is `false`, the event was
              broadcast to clients.
              May not correspond to the real value. Use the property
              BroadcastDisabled.

  Returns:  Action
              `Plugin_Continue` to allow the event to be fired,
              `Plugin_Handled` to block the event.
-----------------------------------------------------------------F-F*/
Action HandlePlayerSpawnEvent_Pre( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    if ( !IsFakeClient( iClient ) && !g_aPlayerAttribs[ iClient ].IsControlling() && view_as< TFTeam >( hEvent.GetInt( "team" ) ) == TF_TEAM_PVE_INVADERS )
    {
        TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: WeaponCanSwitchTo

  Summary:  This function is called every time a human invader tries
            to switch weapons and determines whether they are allowed
            to do so based on the weapon restrictions of the bot
            they're controlling.

  Args:     int iClient
              Index of client controlling a bot.
            int iWeapon
              Index of weapon the client wants to switch to.

  Returns:  Action
              `Plugin_Continue` to allow the client to switch to
              the desired weapon, `Plugin_Handled` or `Plugin_Stop`
              to deny the weapon switch.
-----------------------------------------------------------------F-F*/
Action WeaponCanSwitchTo( int iClient, int iWeapon )
{
    if ( !g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        return Plugin_Continue;
    }

    int     iBot    = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );
    HSCRIPT hScript = VScript_EntityToHScript( iWeapon );
    return IsWeaponRestricted( iBot, hScript ) ? Plugin_Stop : Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: SetTransmit

  Summary:  This function is called every time a hooked entity tries
            to determine whether to transmit itself to a client. We
            use this function to mimic bots' behavior by hiding
            certain entities from human invaders.

  Args:     int iEntity
              Entity index that wants to transmit itself.
            int iClient
              Client index to which the entity wants to transmit
              itself.

  Returns:  Action
              `Plugin_Continue` to let the game decide if the entity
              should be transmitted. `Plugin_Handled` or `Plugin_Stop`
              to block the enitity from being transmitted.
-----------------------------------------------------------------F-F*/
Action SetTransmit( int iEntity, int iClient )
{
    if ( !g_aPlayerAttribs[ iClient ].IsControlling() )
    {
        // We only care about transmitting to human invaders
        return Plugin_Continue;
    }

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    if ( IsPlayerIndex( iEntity ) )
    {
        if ( !TF2_IsEnemyTeam( TF2_GetClientTeam( iEntity ), TF2_GetClientTeam( iClient ) ) )
        {
            // Allow transmitting to teammates
            return Plugin_Continue;
        }

        if ( HasAttribute( iBot, IGNORE_ENEMIES ) )
        {
            return Plugin_Stop;
        }

        // Test for designer-defined ignorance
        switch ( TF2_GetPlayerClass( iEntity ) )
        {
        case TFClass_Medic:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_MEDICS ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Engineer:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_ENGINEERS ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Sniper:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_SNIPERS ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Scout:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_SCOUTS ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Spy:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_SPIES ) )
            {
                return Plugin_Stop;
            }

        case TFClass_DemoMan:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_DEMOMEN ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Soldier:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_SOLDIERS ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Heavy:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_HEAVIES ) )
            {
                return Plugin_Stop;
            }

        case TFClass_Pyro:
            if ( IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_PYROS ) )
            {
                return Plugin_Stop;
            }
        }

        float flRange = GetMaxVisionRangeOverride( iBot );
        if ( flRange > 0.0 )
        {
            if ( IsRangeGreaterThan( iEntity, iClient, flRange ) )
            {
                // We're too far for them to see us
                return Plugin_Stop;
            }
        }

        if ( TF2_IsPlayerInCondition( iEntity, TFCond_OnFire )       ||
             TF2_IsPlayerInCondition( iEntity, TFCond_Jarated )      ||
             TF2_IsPlayerInCondition( iEntity, TFCond_CloakFlicker ) ||
             TF2_IsPlayerInCondition( iEntity, TFCond_Bleeding ) )
        {
            // Allow transmitting if we have these conditions
            return Plugin_Continue;
        }

        // Don't force stealthed-related bot behavior on real players!

        /*--------------------------------------------------------------------
          An upgrade in MvM grants AE stealth where the player can fire
          while in stealth, and for a short period after it drops.
        --------------------------------------------------------------------*/
        /*if ( TF2_IsPlayerInCondition( iEntity, TFCond_StealthedUserBuffFade ) )
        {
            return Plugin_Stop;
        }

        if ( IsStealthed( iEntity ) && GetPercentInvisible( iEntity ) < 0.75 )
        {
            // We're partially cloaked, and therefore should transmit
            return Plugin_Continue;
        }*/

        // According to `CTFBotVision::IsVisibleEntityNoticed` we shouldn't transmit ourselves in MvM mode
        /*if ( IsPlacingSapper( iEntity ) )
        {
            return Plugin_Continue;
        }*/

        if ( TF2_IsPlayerDisguisedFromClient( iEntity, iClient ) )
        {
            // We're disguised as a member of their team
            return Plugin_Stop;
        }
    }
    else
    {
        bool bIsEnemy = TF2_IsEnemyTeam( view_as< TFTeam >( GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ), TF2_GetClientTeam( iClient ) );

        char szClassname[ 64 ];
        GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );
        if ( StrContains( szClassname, "tf_projectile" ) == 0 )
        {
            if ( !bIsEnemy )
            {
                // Always transmit projectiles to teammates
                return Plugin_Continue;
            }

            if ( HasAttribute( iBot, DISABLE_DODGE ) )
            {
                // They shouldn't dodge projectiles, so don't transmit ourselves
                return Plugin_Stop;
            }
        }
        else if ( StrContains( szClassname, "obj_" ) == 0 )
        {
            if ( !bIsEnemy )
            {
                // Always transmit buildings to teammates
                return Plugin_Continue;
            }

            if ( TF2_GetObjectType( iEntity ) == TFObject_Teleporter )
            {
                // Invaders don't care about teleporters
                return Plugin_Stop;
            }

            if ( TF2_GetObjectType( iEntity ) == TFObject_Sentry && IsBehaviorFlagSet( iBot, TFBOT_IGNORE_ENEMY_SENTRY_GUNS ) )
            {
                return Plugin_Stop;
            }

            float flRange = GetMaxVisionRangeOverride( iBot );
            if ( flRange > 0.0 )
            {
                if ( IsRangeGreaterThan( iEntity, iClient, flRange ) )
                {
                    // We're too far for them to see us
                    return Plugin_Stop;
                }
            }
        }
        else if ( StrEqual( szClassname, "item_teamflag" ) )
        {
            if ( bIsEnemy )
            {
                // Always transmit flags to enemies
                return Plugin_Continue;
            }

            if ( IsStolen( iEntity ) )
            {
                // Transmit stolen flags, otherwise they don't appear on the players' backs
                return Plugin_Continue;
            }

            if ( HasAttribute( iBot, IGNORE_FLAG ) )
            {
                // They should ignore the flag, so don't transmit ourselves
                return Plugin_Stop;
            }

            if ( TF2_GetPlayerClass( iClient ) == TFClass_Engineer )
            {
                // Engineers should not prioritize the bomb
                return Plugin_Stop;
            }

            if ( IsOnAnyMission( iBot ) )
            {
                // Mission bots can't pick up the flag
                return Plugin_Stop;
            }

            if ( HasMission( iBot, MISSION_DESTROY_SENTRIES ) )
            {
                return Plugin_Stop;
            }
        }
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: OnTakeDamage

  Summary:  This function is called before every `OnTakeDamage` call
            on the hooked entity. Its main purpose is apply the
            sentry buster explosion damage override for mini bosses.

  Args:     int iVictim
              Entity index that took damage.
            int& iAttacker
              Entity index of the attacker.
            int& iInflictor
              Entity index of the inflictor
            float& flDamage
              Amount of damage applied to `iVictim`.
            int& iDamageType
              Type of damage applied to `iVictim`.
            int& iWeapon
              Weapon index that dealt the damage to `iVictim`. If
              unspecified, this value is `-1`.
            float vecDamageForce[ 3 ]
              Vector representing the velocity of the damage applied
              to `iVictim`.
            float vecDamagePosition[ 3 ]
              Vector representing the origin of the damage applied
              to `iVictim`.
            int iDamageCustom
              Custom kill identifier.

  Returns:  Action
              `Plugin_Continue` to allow the game to determine the
              damage, `Plugin_Changed` to change the parameter
              values and let the game use the changed values when
              determining the damage, `Plugin_Handled` or
              `Plugin_Stop` to block the game's function from running.
-----------------------------------------------------------------F-F*/
Action OnTakeDamage(
    int    iVictim,
    int&   iAttacker,
    int&   iInflictor,
    float& flDamage,
    int&   iDamageType,
    int&   iWeapon,
    float  vecDamageForce[ 3 ],
    float  vecDamagePosition[ 3 ],
    int    iDamageCustom
    )
{
    if ( !g_aPlayerAttribs[ iVictim ].IsControlling() )
    {
        return Plugin_Continue;
    }

    /*--------------------------------------------------------------------
      Sentry Busters hurt teammates when they explode. Force damage value
      when the victim is a giant.
    --------------------------------------------------------------------*/
    if ( IsPlayerIndex( iAttacker )                                                       &&
         IsFakeClient( iAttacker )                                                        &&
         GetPrevMission( iAttacker ) == MISSION_DESTROY_SENTRIES                          &&
         !TF2_IsEnemyTeam( TF2_GetClientTeam( iVictim ), TF2_GetClientTeam( iAttacker ) ) &&
         IsMiniBoss( iVictim ) )
    {
        flDamage = 600.0;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: RespawnRoom_StartTouchPost

  Summary:  This function is called after an entity touches a
            func_respawnroom entity.

  Args:     int iRespawnRoom
              Respawn room entity index.
            int iEntity
              Index of entity that touched `iRespawnRoom`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void RespawnRoom_StartTouchPost( int iRespawnRoom, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iRespawnRoom, Prop_Send, "m_iTeamNum" ) );
    if ( eTeam != TF_TEAM_PVE_INVADERS )
    {
        // We don't care about the defenders' respawn room
        return;
    }

    if ( !IsPlayerIndex( iEntity ) )
    {
        return;
    }

    if ( !g_aPlayerAttribs[ iEntity ].IsControlling() )
    {
        return;
    }

    g_aPlayerAttribs[ iEntity ].bInSpawn = true;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: CaptureZone_StartTouchPost

  Summary:  This function is called after an entity touches a
            func_capturezone entity.

  Args:     int iCaptureZone
              Capture zone entity index.
            int iEntity
              Index of entity that touched `iCaptureZone`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void CaptureZone_StartTouchPost( int iCaptureZone, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iCaptureZone, Prop_Send, "m_iTeamNum" ) );
    if ( eTeam != TF_TEAM_PVE_INVADERS )
    {
        // We only care about the invaders' capture zone
        return;
    }

    if ( !IsPlayerIndex( iEntity ) )
    {
        return;
    }

    if ( !g_aPlayerAttribs[ iEntity ].IsControlling() )
    {
        return;
    }

    if ( GetEntProp( iCaptureZone, Prop_Send, "m_bDisabled" ) )
    {
        return;
    }

    if ( !HasTheFlag( iEntity ) )
    {
        return;
    }

    if ( GetDeployingBombState( iEntity ) != TF_BOMB_DEPLOYING_NONE )
    {
        // We're already deploying
        return;
    }

    if ( TF2_IsPlayerInCondition( iEntity, TFCond_Charging ) )
    {
        TF2_RemoveCondition( iEntity, TFCond_Charging );
    }

    if ( TF2_IsPlayerInCondition( iEntity, TFCond_Taunting ) )
    {
        TF2_RemoveCondition( iEntity, TFCond_Taunting );
    }

    SetDeployingBombState( iEntity, TF_BOMB_DEPLOYING_DELAY );
    g_CarrierAttribs.flDeployTimer = GetGameTime() + tf_deploying_bomb_delay_time.FloatValue;

    // Remember where we start deploying
    GetClientAbsOrigin( iEntity, g_CarrierAttribs.vecAnchorPos );

    /*--------------------------------------------------------------------
      TODO: Manually block movement and attacking, but allow the
      thirdperson camera to orbit locally.
    --------------------------------------------------------------------*/

    /*--------------------------------------------------------------------
      FIXME: `FL_FROZEN` and `TFCond_FreezeInput` block us from changing
      the player's view angles, and `MOVETYPE_NONE` prevents the player
      from being pushed once they start deploying.
    --------------------------------------------------------------------*/
    // SetEntityFlags( iEntity, GetEntityFlags( iEntity ) | FL_FROZEN );
    // TF2_AddCondition( iEntity, TFCond_FreezeInput );
    // SetEntityMoveType( iEntity, MOVETYPE_NONE );
    // TF2_SetClientTauntCamMode( iEntity, TauntCam_Enabled );  // Uncomment when we find a way to stop movement
    TeleportEntity( iEntity, _, _, { 0.0, 0.0, 0.0 } );

    if ( IsMiniBoss( iEntity ) )
    {
        // Minibosses can't be pushed once they start deploying
        TF2Attrib_SetByName( iEntity, "airblast vertical vulnerability multiplier", 0.0 );
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: UpgradeOverTime

  Summary:  This function is called every frame and takes care of
            the flag carrier upgrades.

  Args:     int iClient
              Client index of bomb carrier.

  Returns:  bool
              If the bomb carrier upgraded this frame, the return
              value is `true`.

              If the bomb carrier has not upgraded this frame, the
              return value is `false`.
-----------------------------------------------------------------F-F*/
bool UpgradeOverTime( int iClient )
{
    if ( g_CarrierAttribs.iUpgradeLevel == DONT_UPGRADE )
    {
        return false;
    }

    if ( g_aPlayerAttribs[ iClient ].bInSpawn )
    {
        // Don't start counting down until we leave the spawn
        SetBaseMvMBombUpgradeTime( GetGameTime() );
        SetNextMvMBombUpgradeTime( GetGameTime() + tf_mvm_bot_flag_carrier_interval_to_1st_upgrade.FloatValue );
    }

    // Do defensive buff effect ourselves (since we're not a soldier)
    if ( g_CarrierAttribs.iUpgradeLevel > 0 && GetGameTime() > g_CarrierAttribs.flBuffPulseTimer )
    {
        g_CarrierAttribs.flBuffPulseTimer = GetGameTime() + 1.0;

        const float flBuffRadius = 450.0;
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( IsClientInGame( i ) && IsPlayerAlive( i ) && TF2_GetClientTeam( i ) == TF_TEAM_PVE_INVADERS )
            {
                if ( IsRangeLessThan( iClient, i, flBuffRadius ) )
                {
                    TF2_AddCondition( i, TFCond_DefenseBuffNoCritBlock, 1.2 );
                }
            }
        }
    }

    // The flag carrier gets stronger the longer he holds the flag
    if ( GetGameTime() > GetNextMvMBombUpgradeTime() )
    {
        const int iMaxLevel = 3;
        if ( g_CarrierAttribs.iUpgradeLevel < iMaxLevel )
        {
            g_CarrierAttribs.iUpgradeLevel++;

            BroadcastSound( 255, "MVM.Warning" );

            switch ( g_CarrierAttribs.iUpgradeLevel )
            {
            case 1:
            {
                // Permanent buff banner effect (handled above)

                // Update the objective resource so clients have the information
                SetFlagCarrierUpgradeLevel( 1 );
                SetBaseMvMBombUpgradeTime( GetGameTime() );
                SetNextMvMBombUpgradeTime( GetGameTime() + tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade.FloatValue );
                HaveAllPlayersSpeakConceptIfAllowed( MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE1, TF_TEAM_PVE_DEFENDERS );
                DispatchParticleEffect( "mvm_levelup1", PATTACH_POINT_FOLLOW, iClient, "head" );
            }

            case 2:
            {
                TF2Attrib_SetByName( iClient, "health regen", tf_mvm_bot_flag_carrier_health_regen.FloatValue );

                // Update the objective resource so clients have the information
                SetFlagCarrierUpgradeLevel( 2 );
                SetBaseMvMBombUpgradeTime( GetGameTime() );
                SetNextMvMBombUpgradeTime( GetGameTime() + tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade.FloatValue );
                HaveAllPlayersSpeakConceptIfAllowed( MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE2, TF_TEAM_PVE_DEFENDERS );
                DispatchParticleEffect( "mvm_levelup2", PATTACH_POINT_FOLLOW, iClient, "head" );
            }

            case 3:
            {
                // Add critz
                TF2_AddCondition( iClient, TFCond_Kritzkrieged );

                // Update the objective resource so clients have the information
                SetFlagCarrierUpgradeLevel( 3 );
                SetBaseMvMBombUpgradeTime( -1.0 );
                SetNextMvMBombUpgradeTime( -1.0 );
                HaveAllPlayersSpeakConceptIfAllowed( MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE3, TF_TEAM_PVE_DEFENDERS );
                DispatchParticleEffect( "mvm_levelup3", PATTACH_POINT_FOLLOW, iClient, "head" );
            }
            }

            return true;
        }
    }

    return false;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: ApplyPreviousUpgrades

  Summary:  This function applies all previous (aka missed) MvM bomb
            upgrades to a client based on the current flag carrier
            upgrade level.

  Args:     int iClient
              Client index of bomb carrier.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void ApplyPreviousUpgrades( int iClient )
{
    if ( IsMiniBoss( iClient ) )
    {
        // Mini-bosses don't upgrade
        return;
    }

    int iUpgradeLevel = GetFlagCarrierUpgradeLevel();
    if ( iUpgradeLevel >= 2 )
    {
        TF2Attrib_SetByName( iClient, "health regen", tf_mvm_bot_flag_carrier_health_regen.FloatValue );
    }

    if ( iUpgradeLevel == 3 )
    {
        // Add critz
        TF2_AddCondition( iClient, TFCond_Kritzkrieged );
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandleMovement

  Summary:  This function handles the movement of controlling
            players.

  Args:     int iClient
              Client index.
            int& iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int& iImpulse
              The current impulse command.
            float vecVelocity[ 3 ]
              Player's velocity.
            float angEyeAngles[ 3 ]
              Player's view angles.
            int& iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int& iSubtype
              Weapon subtype when selected from a menu.
            int& iCmdNum
              Command number. Increments from the first command sent.
            int& iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int& iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void HandleMovement(
    int   iClient,
    int&  iButtons,
    int&  iImpulse,
    float vecVelocity[ 3 ],
    float angEyeAngles[ 3 ],
    int&  iWeapon,
    int&  iSubType,
    int&  iCmdNum,
    int&  iTickCount,
    int&  iSeed,
    int   posMouse[ 2 ]
    )
{
#pragma unused iImpulse
#pragma unused vecVelocity
#pragma unused angEyeAngles
#pragma unused iWeapon
#pragma unused iSubType
#pragma unused iCmdNum
#pragma unused iTickCount
#pragma unused iSeed
#pragma unused posMouse

    if ( g_aPlayerAttribs[ iClient ].bPendingTaunt )
    {
        // No more jumping until we taunt
        iButtons &= ~IN_JUMP;

        if ( TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) )
        {
            g_aPlayerAttribs[ iClient ].bPendingTaunt = false;
        }
        else
        {
            /*--------------------------------------------------------------------
              Continuously sending the "taunt" command causes the server to kick
              the player for spamming commands, so we call the handler function
              directly, just like the game itself does.
            --------------------------------------------------------------------*/
            HandleTauntCommand( iClient );
        }

        return;
    }

    if ( tf_bot_force_jump.BoolValue )
    {
        if ( !IsJumping( iClient ) )
        {
            iButtons |= IN_JUMP;
            return;
        }
    }

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    if ( ShouldAutoJump( iBot ) )
    {
        iButtons |= IN_JUMP;
        return;
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: HandleAttack

  Summary:  This function handles the attacking for human invaders.

  Args:     int iClient
              Client index.
            int& iButtons
              The current commands (as bitflags - see
              entity_prop_stocks.inc).
            int& iImpulse
              The current impulse command.
            float vecVelocity[ 3 ]
              Player's velocity.
            float angEyeAngles[ 3 ]
              Player's view angles.
            int& iWeapon
              Entity index of the new weapon if player switches
              weapons, 0 otherwise.
            int& iSubtype
              Weapon subtype when selected from a menu.
            int& iCmdNum
              Command number. Increments from the first command sent.
            int& iTickCount
              A client's prediction based on the server's
              `GetGameTickCount` value.
            int& iSeed
              Random seed. Used to determine weapon recoil, spread,
              and other predicted elements.
            int posMouse[ 2 ]
              Mouse position (x, y).

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void HandleAttack(
    int   iClient,
    int&  iButtons,
    int&  iImpulse,
    float vecVelocity[ 3 ],
    float angEyeAngles[ 3 ],
    int&  iWeapon,
    int&  iSubType,
    int&  iCmdNum,
    int&  iTickCount,
    int&  iSeed,
    int   posMouse[ 2 ]
    )
{
#pragma unused iImpulse
#pragma unused angEyeAngles
#pragma unused iWeapon
#pragma unused iSubType
#pragma unused iCmdNum
#pragma unused iTickCount
#pragma unused iSeed
#pragma unused posMouse

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    if ( TF2_GetPlayerClass( iClient ) == TFClass_DemoMan && IsShieldEquipped( iClient ) )
    {
        if ( HasAttribute( iBot, AIR_CHARGE_ONLY ) )
        {
            iButtons |= IN_ATTACK2;
            if ( GetGroundEntity( iClient ) != -1 || vecVelocity[ 2 ] > 0.0 )
            {
                // Don't charge unless we're in the air and at maximum height
                iButtons &= ~IN_ATTACK2;
            }
        }
    }

    if ( TF2_GetPlayerClass( iClient ) == TFClass_Medic && !HasAttribute( iBot, PROJECTILE_SHIELD ) )
    {
        iButtons &= ~IN_ATTACK3;
    }

    if ( HasAttribute( iBot, SUPPRESS_FIRE ) )
    {
        iButtons &= ~IN_ATTACK;
        return;
    }

    if ( HasAttribute( iBot, IGNORE_ENEMIES ) )
    {
        iButtons &= ~IN_ATTACK;
        return;
    }

    if ( !tf_bot_fire_weapon_allowed.BoolValue )
    {
        iButtons &= ~IN_ATTACK;
        return;
    }

    // We apply the "no_attack" attribute the these players
    /*if ( HasMission( iBot, MISSION_DESTROY_SENTRIES ) ) )
    {
        // Sentry busters don't attack
        iButtons &= ~IN_ATTACK;
        return;
    }*/

    int iActiveWeapon = TF2_GetClientActiveWeapon( iClient );

    if ( IsBarrageAndReloadWeapon( iBot, iActiveWeapon ) )
    {
        if ( HasAttribute( iBot, HOLD_FIRE_UNTIL_FULL_RELOAD ) || tf_bot_always_full_reload.BoolValue )
        {
            int iClip1 = GetEntProp( iActiveWeapon, Prop_Send, "m_iClip1" );
            if ( iClip1 <= 0 )
            {
                g_aPlayerAttribs[ iClient ].bIsWaitingForFullReload = true;
            }

            if ( g_aPlayerAttribs[ iClient ].bIsWaitingForFullReload )
            {
                if ( iClip1 < TF2Util_GetWeaponMaxClip( iActiveWeapon ) )
                {
                    iButtons &= ~IN_ATTACK;
                    return;
                }

                // We are fully reloaded
                g_aPlayerAttribs[ iClient ].bIsWaitingForFullReload = false;
            }
        }
    }

    if ( HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) )
    {
        iButtons |= IN_ATTACK;
        return;
    }

    if ( g_aPlayerAttribs[ iClient ].bInSpawn )
    {
        if ( !CanBotsAttackWhileInSpawnRoom() )
        {
            iButtons &= ~IN_ATTACK;
            return;
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: ShowInstruction

  Summary:  This function takes care of showing instructions to a
            controlling player based on the type of bot they're
            controlling and their current state.

  Args:     int iClient
              Client index. **Must be a controlling player!**

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void ShowInstruction( int iClient )
{
    if ( !g_hShowInstrctions.GetInt( iClient ) )
    {
        return;
    }

    if ( ( GetGameTime() - g_aPlayerAttribs[ iClient ].flLastInstructionTime ) < sm_botcontrol_instruction_interval.FloatValue )
    {
        return;
    }

    char szText[ 64 ];

    if ( HasTheFlag( iClient ) )
    {
        int iCaptureZone = GetClosestCaptureZone( iClient );
        if ( iCaptureZone != -1 )
        {
            FormatEx( szText, sizeof( szText ), "%T", "Instruction_Deploy_Bomb", iClient );

            TF2_ShowPositionalAnnotationToClient(
                                                 iClient,
                                                 WorldSpaceCenter( iCaptureZone ),
                                                 szText,
                                                 iClient,
                                                 "coach/coach_attack_here.wav",
                                                 10.0
                                                );

            g_aPlayerAttribs[ iClient ].flLastInstructionTime = GetGameTime();
            return;
        }
    }

    int iBot = GetClientFromSerial( g_aPlayerAttribs[ iClient ].iBotSerial );

    if ( HasMission( iBot, MISSION_DESTROY_SENTRIES ) )
    {
        int iTarget = VScript_HScriptToEntity( GetMissionTarget( iBot ) );
        if ( iTarget != -1 && IsValidEntity( iTarget ) )
        {
            FormatEx( szText, sizeof( szText ), "%T", "Instruction_Destroy_Sentry", iClient );

            TF2_ShowFollowingAnnotationToClient(
                                                iClient,
                                                iTarget,
                                                szText,
                                                iClient,
                                                "coach/coach_attack_here.wav",
                                                10.0
                                               );

            g_aPlayerAttribs[ iClient ].flLastInstructionTime = GetGameTime();
            return;
        }
    }

    if ( HasTag( iBot, "bot_gatebot" ) && !IsCapturingPoint( iClient ) )
    {
        int iTeamControlPoint = GetMyControlPoint( iBot );
        if ( iTeamControlPoint != -1 )
        {
            FormatEx( szText, sizeof( szText ), "%T", "Instruction_Capture_Gate", iClient );

            TF2_ShowPositionalAnnotationToClient(
                                                 iClient,
                                                 WorldSpaceCenter( iTeamControlPoint ),
                                                 szText,
                                                 iClient,
                                                 "coach/coach_attack_here.wav",
                                                 10.0
                                                );

            g_aPlayerAttribs[ iClient ].flLastInstructionTime = GetGameTime();
            return;
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: SetGameDescription

  Summary:  This function is called every time the plugin's state
            is changed. Based on `bEnabled`, it changes the game
            description to either our custom one or the original one.

  Args:     bool bEnabled
              If the plugin has been enabled, this variable will be
              `true`.

              If the plugin has been disabled, this variable will be
              `false`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void SetGameDescription( bool bEnabled )
{
    if ( bEnabled )
    {
        SteamWorks_SetGameDescription( ":: Bot Control ::" );
    }
    else
    {
        char szDescription[ k_cbMaxGameServerGameDescription ];
        GetGameDescription( szDescription, sizeof( szDescription ), true );
        SteamWorks_SetGameDescription( szDescription );
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: RestoreAllBots

  Summary:  This function is called every time the plugin's state
            is changed. If the plugin has been turned off, this
            function will restore all controlled bots.

  Args:     bool bEnabled
              If the plugin has been enabled, this variable will be
              `true`.

              If the plugin has been disabled, this variable will be
              `false`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void RestoreAllBots( bool bEnabled )
{
    if ( !bEnabled )
    {
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( g_aPlayerAttribs[ i ].IsControlling() )
            {
                RestoreBot( i );
            }
        }
    }
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: ProcessAllEntities

  Summary:  This function is called every time the plugin's state
            is changed. If the plugin has just been turned on, the
            function calls `OnClientPutInServer` for every client
            in game, and `OnEntityCreated` for all entities.

  Args:     bool bEnabled
              If the plugin has been enabled, this variable will be
              `true`.

              If the plugin has been disabled, this variable will be
              `false`.

  Returns:  void
              No return value.
-----------------------------------------------------------------F-F*/
void ProcessAllEntities( bool bEnabled )
{
    if ( bEnabled )
    {
        // Process all clients
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( IsClientInGame( i ) )
            {
                OnClientPutInServer( i );

                if ( AreClientCookiesCached( i ) )
                {
                    OnClientCookiesCached( i );
                }
            }
        }

        // Process all entities
        int iEntity = -1;
        while ( ( iEntity = FindEntityByClassname( iEntity, "*" ) ) != -1 )
        {
            char szClassname[ 64 ];
            GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );
            OnEntityCreated( iEntity, szClassname );
        }
    }
}
