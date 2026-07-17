/*+===================================================================
  File:    GLOBALS.INC

  Summary: This file contains global variables used by the bot
           control plugin.

  Origin:  Created by Bintr on 13.06.2026.
===================================================================+*/

#if defined _botcontrol_globals_included
    #endinput
#endif
#define _botcontrol_globals_included

#include <sourcemod>

#include "const"

#pragma newdecls required
#pragma semicolon 1

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!! CLIENT ATTRIBUTES !!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

PLAYERATTRIBUTES g_aPlayerAttribs[ MAXPLAYERS_ARRAY_SAFE ];
BOTATTRIBUTES    g_aBotAttribs[ MAXPLAYERS_ARRAY_SAFE ];

CARRIERATTRIBUTES g_CarrierAttribs;

int g_nDefenders;
int g_nInvaders;

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!! CONSOLE VARIABLES !!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

ConVar sm_botcontrol_premium_flags;
ConVar sm_botcontrol_groupid;
ConVar sm_botcontrol_min_defenders;
ConVar sm_botcontrol_max_invaders;
ConVar sm_botcontrol_mirror_name;

ConVar spec_freeze_traveltime;
ConVar spec_freeze_time;

ConVar tf_bot_fire_weapon_allowed;
ConVar tf_bot_always_full_reload;
ConVar tf_bot_force_jump;
ConVar tf_bot_engineer_mvm_building_health_multiplier;
ConVar tf_mvm_bot_allow_flag_carrier_to_fight;
ConVar tf_mvm_bot_flag_carrier_interval_to_1st_upgrade;
ConVar tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade;
ConVar tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade;
ConVar tf_mvm_bot_flag_carrier_health_regen;
ConVar tf_deploying_bomb_delay_time;
ConVar tf_deploying_bomb_time;

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!! SYNCHRONIZATION OBJECTS !!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

Handle g_hSyncObj;

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!! SDK CALLS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

Handle g_hfnCBaseEntity_WorldSpaceCenter;

Handle g_hfnCBaseObject_GetMaxHealthForCurrentLevel;

Handle g_hfnCMultiplayRules_HaveAllPlayersSpeakConceptIfAllowed;

Handle g_hfnCTeamplayRoundBasedRules_PlayThrottledAlert;

Handle g_hfnCTFGameRules_BroadcastSound;

#if defined WIN32
Handle g_hfnCObjectTeleporter_SetTeleportWhere;
#endif

Handle g_hfnCTFWeaponBuilder_SetSubType;

Handle g_hfnCTFSniperRifle_ZoomOut;

Handle g_hfnCWeaponMedigun_CycleResistType;
Handle g_hfnCWeaponMedigun_GetResistType;

Handle g_hfnCCaptureFlag_PickUp;

Handle g_hfnCCaptureZone_Capture;

Handle g_hfnCBasePlayer_UpdateClientData;
Handle g_hfnCBasePlayer_SnapEyeAngles;

Handle g_hfnCTFPlayer_RemoveAllWeapons;
Handle g_hfnCTFPlayer_ManageBuilderWeapons;
Handle g_hfnCTFPlayer_PostInventoryApplication;
Handle g_hfnCTFPlayer_RemoveObject;
Handle g_hfnCTFPlayer_HasTheFlag;
Handle g_hfnCTFPlayer_SetObserverTarget;
Handle g_hfnCTFPlayer_DropFlag;
Handle g_hfnCTFPlayer_HandleTauntCommand;
Handle g_hfnCTFPlayer_GetClosestCaptureZone;
Handle g_hfnCTFPlayer_PlaySpecificSequence;
Handle g_hfnCTFPlayer_DoAnimationEvent;

Handle g_hfnCTFPlayerShared_ResetRageBuffs;
Handle g_hfnCTFPlayerShared_IsStealthed;
Handle g_hfnCTFPlayerShared_IsAllowedToTaunt;

Handle g_hfnCTFBot_ShouldQuickBuild;
Handle g_hfnCTFBot_LeaveSquad;
Handle g_hfnCTFBot_SetAttribute;
Handle g_hfnCTFBot_ClearAttribute;
Handle g_hfnCTFBot_ClearAllAttributes;
Handle g_hfnCTFBot_HasAttribute;
Handle g_hfnCTFBot_SetMission;
Handle g_hfnCTFBot_SetPrevMission;
Handle g_hfnCTFBot_GetMission;
Handle g_hfnCTFBot_GetPrevMission;
Handle g_hfnCTFBot_HasMission;
Handle g_hfnCTFBot_IsOnAnyMission;
Handle g_hfnCTFBot_ShouldAutoJump;
Handle g_hfnCTFBot_IsWeaponRestricted;
Handle g_hfnCTFBot_IsBarrageAndReloadWeapon;
Handle g_hfnCTFBot_SetBehaviorFlag;
Handle g_hfnCTFBot_ClearBehaviorFlag;
Handle g_hfnCTFBot_IsBehaviorFlagSet;
Handle g_hfnCTFBot_SetMaxVisionRangeOverride;
Handle g_hfnCTFBot_GetMaxVisionRangeOverride;
Handle g_hfnCTFBot_StartIdleSound;
Handle g_hfnCTFBot_GetLastKnownArea;

Handle g_hfnCTFBotMvMEngineerHintFinder_FindHint;

Handle g_hfnCTFNavArea_HasAttributeTF;

#if !defined WIN32
Handle g_hfnCUtlStringList_CopyAndAddToTail;
#endif

Handle g_hfnGetPlayerClassData;
Handle g_hfnDispatchParticleEffect;

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!! OFFSETS !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

int g_CTFPlayer_nDeployingBombState_Offset;
int g_CTFPlayer_bIsMissionEnemy_Offset;
int g_CTFPlayer_bIsSupportEnemy_Offset;
int g_CTFPlayer_bIsLimitedSupportEnemy_Offset;
int g_CTFPlayer_flSpawnTime_Offset;
int g_CTFPlayer_aObjects_Offset;
int g_CTFPlayer_pWaveSpawnPopulator_Offset;

int g_CTFPlayerShared_flInvisibility_Offset;

int g_CTFBot_teleportWhereName_Offset;

int g_CObjectTeleporter_teleportWhereName_Offset;

int g_CBaseObject_bForceQuickBuild_Offset;

int g_CPopulationManager_canBotsAttackWhileInSpawnRoom_Offset;

int g_CTraceFilterSimple_pPassEnt_Offset;

// int g_CTFBotDeliverFlag_upgradeLevel_Offset;

/*--------------------------------------------------------------------
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!! GLOBAL ENTITIES !!!!!!!!!!!!!!!!!!!!!!!!!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--------------------------------------------------------------------*/

int g_iObjectiveResource;
int g_iPopulationManager;
