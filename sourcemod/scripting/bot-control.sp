/*+===================================================================
  File:    BOT-CONTROL.SP

  Summary: This plugin allows players to take control of robots
           in the Mann vs. Machine gamemode.

  Origin:  Created by Pelipoika on 14.05.2016
           Modified by Bintr on 05.05.2026
===================================================================+*/

#include <dhooks>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2attributes>
#include <tf2items>
#include <tf2_stocks>
#include <tf2utils>
#if defined( STEAMWORKS_SUPPORT )
#include <SteamWorks>
#endif
#include <stocksoup/tf/annotations>
#include <stocksoup/tf/client>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/weapon>
#include <stocksoup/color_literals>
#include <stocksoup/convars>
#include <stocksoup/entity>
#include <stocksoup/string>
#include <stocksoup/log_server>

#pragma newdecls required

public Plugin myinfo =
{
    name        = "[TF2] MvM Bot Control",
    author      = "Pelipoika (modified by Bintr)",
    description = "Allows players to take control of a robot in Mann vs. Machine",
    version     = "1.0",
    url         = "https://www.sourcemod.net/plugins.php?author=Pelipoika&search=1"
};

// Spectator Movement modes
enum
{
    OBS_MODE_NONE = 0,  // not in spectator mode
    OBS_MODE_DEATHCAM,  // special mode for death cam animation
    OBS_MODE_FREEZECAM, // zooms to a target, and freeze-frames on them
    OBS_MODE_FIXED,     // view from a fixed camera position
    OBS_MODE_IN_EYE,    // follow a player in first person view
    OBS_MODE_CHASE,     // follow a player in third person view
    OBS_MODE_POI,       // PASSTIME point of interest - game objective, big fight, anything interesting; added in the middle of the enum due to tons of hard-coded "<ROAMING" enum compares
    OBS_MODE_ROAMING,   // free roaming

    NUM_OBSERVER_MODES
};

//-----------------------------------------------------------------------------
// Particle attachment methods
//-----------------------------------------------------------------------------
enum ParticleAttachment_t
{
    PATTACH_ABSORIGIN = 0,      // Create at absorigin, but don't follow
    PATTACH_ABSORIGIN_FOLLOW,   // Create at absorigin, and update to follow the entity
    PATTACH_CUSTOMORIGIN,       // Create at a custom origin, but don't follow
    PATTACH_POINT,              // Create on attachment point, but don't follow
    PATTACH_POINT_FOLLOW,       // Create on attachment point, and update to follow the entity

    PATTACH_WORLDORIGIN,        // Used for control points that don't attach to an entity

    PATTACH_ROOTBONE_FOLLOW,    // Create at the root bone of the entity, and update to follow

    MAX_PATTACH_TYPES
};

enum AttributeType
{
    REMOVE_ON_DEATH             = 1 << 0,   // kick bot from server when killed
    AGGRESSIVE                  = 1 << 1,   // in MvM mode, push for the cap point
    IS_NPC                      = 1 << 2,   // a non-player support character
    SUPPRESS_FIRE               = 1 << 3,
    DISABLE_DODGE               = 1 << 4,
    BECOME_SPECTATOR_ON_DEATH   = 1 << 5,   // move bot to spectator team when killed
    QUOTA_MANANGED              = 1 << 6,   // managed by the bot quota in CTFBotManager
    RETAIN_BUILDINGS            = 1 << 7,   // don't destroy this bot's buildings when it disconnects
    SPAWN_WITH_FULL_CHARGE      = 1 << 8,   // all weapons start with full charge (ie: uber)
    ALWAYS_CRIT                 = 1 << 9,   // always fire critical hits
    IGNORE_ENEMIES              = 1 << 10,
    HOLD_FIRE_UNTIL_FULL_RELOAD = 1 << 11,  // don't fire our barrage weapon until it is full reloaded (rocket launcher, etc)
    PRIORITIZE_DEFENSE          = 1 << 12,  // bot prioritizes defending when possible
    ALWAYS_FIRE_WEAPON          = 1 << 13,  // constantly fire our weapon
    TELEPORT_TO_HINT            = 1 << 14,  // bot will teleport to hint target instead of walking out from the spawn point
    MINIBOSS                    = 1 << 15,  // is miniboss?
    USE_BOSS_HEALTH_BAR         = 1 << 16,  // should I use boss health bar?
    IGNORE_FLAG                 = 1 << 17,  // don't pick up flag/bomb
    AUTO_JUMP                   = 1 << 18,  // auto jump
    AIR_CHARGE_ONLY             = 1 << 19,  // demo knight only charge in the air
    PREFER_VACCINATOR_BULLETS   = 1 << 20,  // When using the vaccinator, prefer to use the bullets shield
    PREFER_VACCINATOR_BLAST     = 1 << 21,  // When using the vaccinator, prefer to use the blast shield
    PREFER_VACCINATOR_FIRE      = 1 << 22,  // When using the vaccinator, prefer to use the fire shield
    BULLET_IMMUNE               = 1 << 23,  // Has a shield that makes the bot immune to bullets
    BLAST_IMMUNE                = 1 << 24,  // "" blast
    FIRE_IMMUNE                 = 1 << 25,  // "" fire
    PARACHUTE                   = 1 << 26,  // demo/soldier parachute when falling
    PROJECTILE_SHIELD           = 1 << 27   // medic projectile shield
};

enum MissionType
{
    NO_MISSION = 0,
    MISSION_SEEK_AND_DESTROY,   // focus on finding and killing enemy players
    MISSION_DESTROY_SENTRIES,   // focus on finding and destroying enemy sentry guns (and buildings)
    MISSION_SNIPER,             // maintain teams of snipers harassing the enemy
    MISSION_SPY,                // maintain teams of spies harassing the enemy
    MISSION_ENGINEER,           // maintain engineer nests for harassing the enemy
    MISSION_REPROGRAMMED        // MvM: robot has been hacked and will do bad things to their team
};

enum WeaponRestrictionType
{
    ANY_WEAPON     = 0,
    MELEE_ONLY     = 0x0001,
    PRIMARY_ONLY   = 0x0002,
    SECONDARY_ONLY = 0x0004
};

// entity effects
enum
{
    EF_BONEMERGE          = 0x001,  // Performs bone merge on client side
    EF_BRIGHTLIGHT        = 0x002,  // DLIGHT centered at entity origin
    EF_DIMLIGHT           = 0x004,  // player flashlight
    EF_NOINTERP           = 0x008,  // don't interpolate the next frame
    EF_NOSHADOW           = 0x010,  // Don't cast no shadow
    EF_NODRAW             = 0x020,  // don't draw entity
    EF_NORECEIVESHADOW    = 0x040,  // Don't receive no shadow
    EF_BONEMERGE_FASTCULL = 0x080,  // For use with EF_BONEMERGE. If this is set, then it places this ent's origin at its
                                    // parent and uses the parent's bbox + the max extents of the aiment.
                                    // Otherwise, it sets up the parent's bones every frame to figure out where to place
                                    // the aiment, which is inefficient because it'll setup the parent's bones even if
                                    // the parent is not in the PVS.
    EF_ITEM_BLINK         = 0x100,  // blink an item so that the user notices it.
    EF_PARENT_ANIMATES    = 0x200,  // always assume that the parent entity is animating
    EF_MAX_BITS           = 10
};

#define EF_PARITY_BITS  3
#define EF_PARITY_MASK  ( ( 1 << EF_PARITY_BITS ) - 1 )

//-----------------------------------------------------------------------------
// TF FlagInfo State.
//-----------------------------------------------------------------------------
#define TF_FLAGINFO_HOME    0
#define TF_FLAGINFO_STOLEN  ( 1 << 0 )
#define TF_FLAGINFO_DROPPED ( 1 << 1 )

#define TF_TEAM_PVE_INVADERS	TFTeam_Blue // invading bot team in mann vs machine
#define TF_TEAM_PVE_DEFENDERS	TFTeam_Red  // defending player team in mann vs machine

// Used for displaying robot-related information on the client's HUD
Handle g_hHudInfo;
Handle g_hHudReload;

// SDKCalls
Handle g_hfnPlaySpecificSequence;
Handle g_hfnDispatchParticleEffect;
Handle g_hfnSetMission;
Handle g_hfnGetLeader;
Handle g_hfnGetMaxClip1;
// Handle g_hfnPickUp;
Handle g_hfnDrop;
Handle g_hfnRemoveObject;
Handle g_hfnHasTag;
Handle g_hfnWorldSpaceCenter;
Handle g_hfnLeaveSquad;
Handle g_hfnPostInventoryApplication;
Handle g_hfnShouldAutoJump;
Handle g_hfnZoomOut;
#if !defined( WIN32 )
Handle g_hfnGetPercentInvisible;
Handle g_hfnIsStealthed;
Handle g_hfnHasWeaponRestriction;
Handle g_hfnIsInASquad;
Handle g_hfnHasAttribute;
#endif

// DHooks
Handle g_hfnIsValidObserverTarget;
Handle g_hfnShouldGib;
Handle g_hfnShouldTransmit;
Handle g_hfnPassesFilterImpl;

// Detours
Handle g_hfnSelectPatient;
Handle g_hfnIsAllowedToHealTarget;

// Offsets
#if defined( WIN32 )
int g_flInvisibility_Offset;
int g_weaponRestrictionFlags_Offset;
int g_attributeFlags_Offset;
#endif
int g_squad_Offset;
int g_teleportWhereName_Offset;

// Players bot & player data
int   g_iPlayersBot[ MAXPLAYERS + 1 ];
float g_flControlEndTime[ MAXPLAYERS + 1 ];
float g_flCooldownEndTime[ MAXPLAYERS + 1 ];
float g_flNextInstructionTime[ MAXPLAYERS + 1 ];
bool  g_bControllingBot[ MAXPLAYERS + 1 ];
bool  g_bReloadingBarrage[ MAXPLAYERS + 1 ];
bool  g_bSkipInventory[ MAXPLAYERS + 1 ];
bool  g_bBlockRagdoll;    // Stolen from Stop that Tank

// Controlled bot data
bool g_bIsControlled[ MAXPLAYERS + 1 ];
int  g_iController[ MAXPLAYERS + 1 ];

// Bot data
bool  g_bIsSentryBuster[ MAXPLAYERS + 1 ];
bool  g_bDeploying[ MAXPLAYERS + 1 ];
float g_flSpawnTime[ MAXPLAYERS + 1 ];

// Bomb data
int   g_iFlagCarrierUpgradeLevel[ MAXPLAYERS + 1 ];
float g_flBombDeployTime[ MAXPLAYERS + 1 ];
float g_flNextBombUpgradeTime[ MAXPLAYERS + 1 ];

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginStart

  Summary:  Called when the plugin is fully initialized and all
            known external references are resolved. This is only
            called once in the lifetime of the plugin, and is
            paired with OnPluginEnd().

            If any run-time error is thrown during this callback,
            the plugin will be marked as failed.

            This function initializes all of our console variables,
            global SDK function vairables, DHooks, offsets, and
            more.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginStart()
{
    if ( GetEngineVersion() != Engine_TF2 )
    {
        SetFailState( "This plugin only works for the game Team Fotress 2." );
    }

    CreateVersionConVar( "sm_botcontrol_version", "[TF2] MvM Bot Control version" );

    GameData Conf = new GameData( "bot-control" );
    if ( !Conf )
    {
        SetFailState( "Could not find gamedata file \"bot-control.txt\"." );
    }

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!! SDK CALLS !!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    // This entity is used to get an entitys center position
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CBaseEntity::WorldSpaceCenter" );
    PrepSDKCall_SetReturnInfo( SDKType_Vector, SDKPass_ByRef );
    g_hfnWorldSpaceCenter = EndPrepSDKCall();
    if ( !g_hfnWorldSpaceCenter )
    {
        SetFailState( "Failed to create SDKCall for CBaseEntity::WorldSpaceCenter offset." );
    }

    // This call is used to set the deploy animation on the robots with the bomb
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::PlaySpecificSequence" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );  // const char* pSequenceName
    g_hfnPlaySpecificSequence = EndPrepSDKCall();
    if ( !g_hfnPlaySpecificSequence )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayer::PlaySpecificSequence signature." );
    }

    // This call is used to remove an objects owner
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::RemoveObject" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer ); // CBaseObject* pObject
    g_hfnRemoveObject = EndPrepSDKCall();
    if ( !g_hfnRemoveObject )
    {
        SetFailState( "Failed To create SDKCall for CTFPlayer::RemoveObject signature." );
    }

    // This call is used to (hopefully) fix wearable issues.
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::PostInventoryApplication" );
    g_hfnPostInventoryApplication = EndPrepSDKCall();
    if ( !g_hfnPostInventoryApplication )
    {
        SetFailState( "Failed To create SDKCall for CTFPlayer::PostInventoryApplication signature." );
    }

    // This call is used to make sentry busters behave nicely
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::SetMission" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );  // MissionType mission
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );          // bool resetBehaviorSystem
    g_hfnSetMission = EndPrepSDKCall();
    if ( !g_hfnSetMission )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::SetMission signature." );
    }

    // This call is used to get a bot's tag
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::HasTag" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );  // const char* tag
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnHasTag = EndPrepSDKCall();
    if ( !g_hfnHasTag )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasTag signature." );
    }

    // This call will make a bot leave their squad
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::LeaveSquad" );
    g_hfnLeaveSquad = EndPrepSDKCall();
    if ( !g_hfnLeaveSquad )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::LeaveSquad signature." );
    }

    // Used to determine whether we should auto jump
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::ShouldAutoJump" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnShouldAutoJump = EndPrepSDKCall();
    if ( !g_hfnShouldAutoJump )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::ShouldAutoJump signature." );
    }

    // Used to get a bot's squad leader
#if defined( WIN32 )
    /*--------------------------------------------------------------------
      There seems to be no way to get a direct signature to
      CTFBotSquad::GetLeader on Windows because it simply returns
      `m_leader` which is a `CHandle< CTFBot >`. Many functions that
      return a `CHandle` compile almost identically, so a byte signature
      is not unique.
    --------------------------------------------------------------------*/
    Address pCallGetLeader = Conf.GetMemSig( "CTFBotEscortSquadLeader::Update_call_GetLeader" );
    int     iRel           = LoadFromAddress( pCallGetLeader + view_as< Address >( 1 ), NumberType_Int32 );
    Address pGetLeader     = pCallGetLeader + view_as< Address >( 5 + iRel );

    StartPrepSDKCall( SDKCall_Raw );
    PrepSDKCall_SetAddress( pGetLeader );
    PrepSDKCall_SetReturnInfo( SDKType_CBasePlayer, SDKPass_Pointer );
    g_hfnGetLeader = EndPrepSDKCall();
#else
    StartPrepSDKCall( SDKCall_Raw );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBotSquad::GetLeader" );
    PrepSDKCall_SetReturnInfo( SDKType_CBasePlayer, SDKPass_Pointer );
    g_hfnGetLeader = EndPrepSDKCall();
#endif
    if ( !g_hfnGetLeader )
    {
        SetFailState( "Failed to create SDKCall for CTFBotSquad::GetLeader signature." );
    }

    // This call will play a particle effect
    StartPrepSDKCall( SDKCall_Static );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "DispatchParticleEffect" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );        // const char* pszParticleName
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );    // ParticleAttachment_t iAttachType
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );   // CBaseEntity* pEntity
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );        // const char* pszAttachmentName
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bResetAllParticlesOnEntity
    g_hfnDispatchParticleEffect = EndPrepSDKCall();
    if ( !g_hfnDispatchParticleEffect )
    {
        SetFailState( "Failed to create SDKCall for DispatchParticleEffect signature." );
    }

    // This call gets the maximum clip 1 of a weapon
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );   // int
    g_hfnGetMaxClip1 = EndPrepSDKCall();
    if ( !g_hfnGetMaxClip1 )
    {
        SetFailState( "Failed to create SDKCall for CTFWeaponBase::GetMaxClip1 offset." );
    }

    // This call forces a player to pick up the intel
    // FIXME: This just crashes the server no matter how much we wait after the bomb is dropped
    /*StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CCaptureFlag::PickUp" );
    PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );   // CTFPlayer* pPlayer
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bInvisible (unused)
    g_hfnPickUp = EndPrepSDKCall();
    if ( !g_hfnPickUp )
    {
        SetFailState( "Failed to create SDKCall for CCaptureFlag::PickUp offset." );
    }*/

    // This call forces a player to drop the intel
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CCaptureFlag::Drop" );
    PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );   // CTFPlayer *pPlayer
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bVisible
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bThrown
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bMessage
    g_hfnDrop = EndPrepSDKCall();
    if ( !g_hfnDrop )
    {
        SetFailState( "Failed to create SDKCall for CCaptureFlag::Drop offset." );
    }

    // We use this to unzoom sniper bots when mirroring them
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CTFSniperRifle::ZoomOut" );
    g_hfnZoomOut = EndPrepSDKCall();
    if ( !g_hfnZoomOut )
    {
        SetFailState( "Failed to create SDKCall for CTFSniperRifle::ZoomOut offset." );
    }

#if !defined( WIN32 )
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayerShared::GetPercentInvisible" );
    PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain );
    g_hfnGetPercentInvisible = EndPrepSDKCall();
    if ( !g_hfnGetPercentInvisible )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayerShared::GetPercentInvisible signature." );
    }

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayerShared::IsStealthed" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnIsStealthed = EndPrepSDKCall();
    if ( !g_hfnIsStealthed )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayerShared::IsStealthed signature." );
    }

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::HasWeaponRestriction" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnHasWeaponRestriction = EndPrepSDKCall();
    if ( !g_hfnHasWeaponRestriction )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasWeaponRestriction signature." );
    }

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::IsInASquad" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnIsInASquad = EndPrepSDKCall();
    if ( !g_hfnIsInASquad )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::IsInASquad signature." );
    }

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::HasAttribute" );
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnHasAttribute = EndPrepSDKCall();
    if ( !g_hfnHasAttribute )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasAttribute signature." );
    }
#endif

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!! DHOOK DETOURS !!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    g_hfnSelectPatient = DHookCreateDetour( Address_Null, CallConv_THISCALL, ReturnType_CBaseEntity, ThisPointer_Ignore );
    if ( !g_hfnSelectPatient )
    {
        SetFailState( "Failed to create detour for CTFBotMedicHeal::SelectPatient." );
    }
    if ( !DHookSetFromConf( g_hfnSelectPatient, Conf, SDKConf_Signature, "CTFBotMedicHeal::SelectPatient" ) )
    {
        SetFailState( "Failed to load CTFBotMedicHeal::SelectPatient signature from gamedata." );
    }
    DHookAddParam( g_hfnSelectPatient, HookParamType_CBaseEntity );   // CTFBot* me
    DHookAddParam( g_hfnSelectPatient, HookParamType_CBaseEntity );   // CTFPlayer* current
    if ( !DHookEnableDetour( g_hfnSelectPatient, false, CTFBotMedicHeal_SelectPatient ) )
    {
        SetFailState( "Failed to detour CTFBotMedicHeal::SelectPatient." );
    }
    if ( !DHookEnableDetour( g_hfnSelectPatient, true,  CTFBotMedicHeal_SelectPatient_Post ) )
    {
        SetFailState( "Failed to detour CTFBotMedicHeal::SelectPatient post." );
    }

    g_hfnIsAllowedToHealTarget = DHookCreateDetour( Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_CBaseEntity );
    if ( !g_hfnIsAllowedToHealTarget )
    {
        SetFailState( "Failed to setup detour for CWeaponMedigun::AllowedToHealTarget" );
    }
    if ( !DHookSetFromConf( g_hfnIsAllowedToHealTarget, Conf, SDKConf_Signature, "CWeaponMedigun::AllowedToHealTarget" ) )
    {
        SetFailState( "Failed to load CWeaponMedigun::AllowedToHealTarget signature from gamedata." );
    }
    DHookAddParam( g_hfnIsAllowedToHealTarget, HookParamType_CBaseEntity );   // CBaseEntity* pEntity
    if ( !DHookEnableDetour( g_hfnIsAllowedToHealTarget, false, CWeaponMedigun_IsAllowedToHealTarget ) )
    {
        SetFailState( "[BotControl] Failed to detour CWeaponMedigun::AllowedToHealTarget." );
    }
    if ( !DHookEnableDetour( g_hfnIsAllowedToHealTarget, true,  CWeaponMedigun_IsAllowedToHealTarget_Post ) )
    {
        SetFailState( "[BotControl] Failed to detour CWeaponMedigun::AllowedToHealTarget_Post." );
    }

    int iOffset = Conf.GetOffset( "CTFPlayer::ShouldGib" );
    if ( iOffset == -1 )
    {
        SetFailState( "Failed to get offset of CTFBot::ShouldGib" );
    }
    g_hfnShouldGib = DHookCreate( iOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, CTFPlayer_ShouldGib );
    DHookAddParam( g_hfnShouldGib, HookParamType_ObjectPtr, -1, DHookPass_ByRef );   // const CTakeDamageInfo& info

    iOffset = Conf.GetOffset( "CBaseEntity::ShouldTransmit" );
    if ( iOffset == -1 )
    {
        SetFailState( "Failed to get offset of CBaseEntity::ShouldTransmit");
    }
    g_hfnShouldTransmit = DHookCreate( iOffset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, CBaseEntity_ShouldTransmit );
    DHookAddParam( g_hfnShouldTransmit, HookParamType_ObjectPtr );    // const CCheckTransmitInfo* pInfo

    iOffset = Conf.GetOffset( "CTFPlayer::IsValidObserverTarget" );
    if ( iOffset == -1 )
    {
        SetFailState( "Failed to get offset of CTFPlayer::IsValidObserverTarget" );
    }
    g_hfnIsValidObserverTarget = DHookCreate( iOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, CTFPlayer_IsValidObserverTarget );
    DHookAddParam( g_hfnIsValidObserverTarget, HookParamType_CBaseEntity );   // CBaseEntity* target

    iOffset = Conf.GetOffset( "CFilterTFBotHasTag::PassesFilterImpl" );
    if ( iOffset == -1 )
    {
        SetFailState( "Failed to get offset of CFilterTFBotHasTag::PassesFilterImpl" );
    }
    g_hfnPassesFilterImpl = DHookCreate( iOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, CFilterTFBotHasTag_PassesFilterImpl );
    DHookAddParam( g_hfnPassesFilterImpl, HookParamType_CBaseEntity );    // CBaseEntity* pCaller
    DHookAddParam( g_hfnPassesFilterImpl, HookParamType_CBaseEntity );    // CBaseEntity* pEntity

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!! OFFSETS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/
#if defined( WIN32 )
    g_flInvisibility_Offset         = Conf.GetOffset( "CTFPlayerShared::m_flInvisibility" );
    g_weaponRestrictionFlags_Offset = Conf.GetOffset( "CTFBot::m_weaponRestrictionFlags" );
    g_attributeFlags_Offset         = Conf.GetOffset( "CTFBot::m_attributeFlags" );
#endif
    g_squad_Offset             = Conf.GetOffset( "CTFBot::m_squad" );
    g_teleportWhereName_Offset = Conf.GetOffset( "CTFBot::m_teleportWhereName" );

    delete Conf;

    int iEnt = -1;
    while ( ( iEnt = FindEntityByClassname( iEnt, "*" ) ) != -1 )
    {
        char szClassname[ 64 ];
        GetEntityClassname( iEnt, szClassname, sizeof( szClassname ) );
        OnEntityCreated( iEnt, szClassname );
    }

    g_hHudInfo   = CreateHudSynchronizer();
    g_hHudReload = CreateHudSynchronizer();

    AddCommandListener( Listener_Voice, "voicemenu" );
    AddCommandListener( Listener_Block, "autoteam" );
    AddCommandListener( Listener_Block, "kill" );
    AddCommandListener( Listener_Block, "explode" );
    AddCommandListener( Listener_Build, "build" );

    HookEvent( "teamplay_flag_event", Event_FlagEvent );
    HookEvent( "player_team", Event_PlayerTeam, EventHookMode_Pre );
    HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Pre );
    HookEvent( "player_spawn", Event_PlayerSpawn );
    HookEvent( "player_builtobject",Event_BuildObject );
    HookEvent( "teamplay_round_start", Event_ResetBots );
    HookEvent( "mvm_wave_complete", Event_ResetBots );
    HookEvent( "player_sapped_object", Event_SappedObject );

    RegConsoleCmd( "sm_debugbot", Command_Debug );

    for ( int iClient = 1; iClient <= MaxClients; iClient++ )
    {
        if ( IsClientInGame( iClient ) )
        {
            OnClientPutInServer( iClient );
        }
    }

    // Block announcer sound from being played to the invading team
    AddNormalSoundHook( BlockAnnouncer );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnPluginEnd

  Summary:  Called when the plugin is about to be unloaded.

            It is not necessary to close any handles or remove
            hooks in this function. SourceMod guarantees that
            plugin shutdown automatically and correctly releases
            all resources.

            This function frees all global handles used by this
            plugin.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnPluginEnd()
{
    delete g_hHudInfo;
    delete g_hHudReload;

    delete g_hfnDispatchParticleEffect;
    delete g_hfnGetMaxClip1;
    delete g_hfnGetLeader;
    delete g_hfnHasTag;
    delete g_hfnIsAllowedToHealTarget;
    delete g_hfnIsValidObserverTarget;
    delete g_hfnLeaveSquad;
    delete g_hfnPassesFilterImpl;
    // delete g_hfnPickUp;
    delete g_hfnPlaySpecificSequence;
    delete g_hfnPostInventoryApplication;
    delete g_hfnRemoveObject;
    delete g_hfnSelectPatient;
    delete g_hfnSetMission;
    delete g_hfnShouldAutoJump;
    delete g_hfnShouldGib;
    delete g_hfnShouldTransmit;
    delete g_hfnWorldSpaceCenter;
    delete g_hfnZoomOut;
}

public void OnMapStart()
{
    if ( !TF2_PlayingMannVsMachine() )
    {
#if defined( STEAMWORKS_SUPPORT )
        SteamWorks_SetGameDescription( "Team Fortress 2" );
#endif
        SetFailState( " Disabling for non Mann vs. Machine map." );
    }

#if defined( STEAMWORKS_SUPPORT )
    SteamWorks_SetGameDescription( ":: Bot Control ::" );
#endif

    PrecacheScriptSound( "MVM.Warning" );
    PrecacheScriptSound( "MVM.DeployBombGiant" );
    PrecacheScriptSound( "MVM.DeployBombSmall" );
    PrecacheScriptSound( "MVM.SentryBusterLoop" );
    PrecacheScriptSound( "MVM.GiantHeavyLoop" );
    PrecacheScriptSound( "MVM.GiantSoldierLoop" );
    PrecacheScriptSound( "MVM.GiantDemomanLoop" );
    PrecacheScriptSound( "MVM.GiantScoutLoop" );
    PrecacheScriptSound( "MVM.GiantPyroLoop" );
    PrecacheScriptSound( "MVM.Robot_Teleporter_Deliver" );
}

public void OnClientPutInServer( int iClient )
{
    // TODO: Create two separate methodmaps TFPlayer and TFBot (inherits TFPlayer)
    g_iPlayersBot[ iClient ]     = -1;
    g_bControllingBot[ iClient ] = false;
    g_bIsControlled[ iClient ]   = false;
    g_iController[ iClient ]     = -1;
    g_bIsSentryBuster[ iClient ] = false;
    g_bSkipInventory[ iClient ]  = false;

    g_flCooldownEndTime[ iClient ] = -1.0;
    g_flControlEndTime[ iClient ]  = -1.0;
    g_flSpawnTime[ iClient ]       = -1.0;

    g_bReloadingBarrage[ iClient ] = false;

    g_iFlagCarrierUpgradeLevel[ iClient ] = 0;
    g_flNextBombUpgradeTime[ iClient ]    = -1.0;
    g_bDeploying[ iClient ]               = false;
    g_flBombDeployTime[ iClient ]         = -1.0;

    DHookEntity( g_hfnShouldGib, true, iClient );
    DHookEntity( g_hfnIsValidObserverTarget, true, iClient );

    SDKHook( iClient, SDKHook_SetTransmit, Hook_SpyTransmit );
    SDKHook( iClient, SDKHook_OnTakeDamageAlivePost, Player_OnTakeDamageAlivePost );
}

public Action Command_Debug( int iClient, int argc )
{
    if ( !( 0 < iClient <= MaxClients ) || !IsClientInGame( iClient ) )
    {
        return Plugin_Stop;
    }

    int iTarget = iClient;
    if ( TF2_GetClientTeam( iClient ) == TFTeam_Spectator )
    {
        int iObserverTarget = GetEntPropEnt( iClient, Prop_Data, "m_hObserverTarget" );
        if ( 0 < iObserverTarget <= MaxClients && IsClientInGame( iObserverTarget ) )
        {
            iTarget = iObserverTarget;
        }
    }

    PrintToConsole( iClient, "\n----- \"%N\" #%i (%i) --------", iTarget, GetClientUserId( iTarget ), iTarget );

    PrintToConsole( iClient, "IsFakeClient = %s", IsFakeClient( iTarget ) ? "true" : "false" );

    PrintToConsole( iClient, "g_bIsControlled = %s", g_bIsControlled[ iTarget ] ? "true" : "false" );
    PrintToConsole( iClient, "g_iController = %i", GetClientOfUserId( g_iController[ iTarget ] ) );
    PrintToConsole( iClient, "g_bIsSentryBuster = %s", g_bIsSentryBuster[ iTarget ] ? "true" : "false" );
    PrintToConsole( iClient, "g_bSkipInventory = %i", g_bSkipInventory[ iTarget ] ? "true" : "false" );

    PrintToConsole( iClient, "g_flCooldownEndTime = %f", g_flCooldownEndTime[ iTarget ] );
    PrintToConsole( iClient, "g_flControlEndTime = %f", g_flControlEndTime[ iTarget ] );
    PrintToConsole( iClient, "g_flSpawnTime = %f", g_flSpawnTime[ iTarget ] );

    if ( IsFakeClient( iTarget ) )
    {
        Menu g_hMenuAttributes = new Menu( MenuAttributeHandler );
        g_hMenuAttributes.SetTitle( "Bot Attributes\n ");
        g_hMenuAttributes.AddItem( "0",  HasAttribute( iTarget, REMOVE_ON_DEATH )             ? "✅ REMOVE_ON_DEATH"             : "❌ REMOVE_ON_DEATH" );
        g_hMenuAttributes.AddItem( "1",  HasAttribute( iTarget, AGGRESSIVE )                  ? "✅ AGGRESSIVE"                  : "❌ AGGRESSIVE" );
        g_hMenuAttributes.AddItem( "2",  HasAttribute( iTarget, IS_NPC )                      ? "✅ IS_NPC"                      : "❌ IS_NPC" );
        g_hMenuAttributes.AddItem( "3",  HasAttribute( iTarget, SUPPRESS_FIRE )               ? "✅ SUPPRESS_FIRE"               : "❌ SUPPRESS_FIRE" );
        g_hMenuAttributes.AddItem( "4",  HasAttribute( iTarget, DISABLE_DODGE )               ? "✅ DISABLE_DODGE"               : "❌ DISABLEDODGE" );
        g_hMenuAttributes.AddItem( "5",  HasAttribute( iTarget, BECOME_SPECTATOR_ON_DEATH )   ? "✅ BECOME_SPECTATOR_ON_DEATH"   : "❌ BECOME_SPECTATOR_ON_DEATH" );
        g_hMenuAttributes.AddItem( "6",  HasAttribute( iTarget, QUOTA_MANANGED )              ? "✅ QUOTA_MANANGED"              : "❌ QUOTA_MANANGED" );
        g_hMenuAttributes.AddItem( "7",  HasAttribute( iTarget, RETAIN_BUILDINGS )            ? "✅ RETAIN_BUILDINGS"            : "❌ RETAIN_BUILDINGS" );
        g_hMenuAttributes.AddItem( "8",  HasAttribute( iTarget, SPAWN_WITH_FULL_CHARGE )      ? "✅ SPAWN_WITH_FULL_CHARGE"      : "❌ SPAWN_WITH_FULL_CHARGE" );
        g_hMenuAttributes.AddItem( "9",  HasAttribute( iTarget, ALWAYS_CRIT )                 ? "✅ ALWAYS_CRIT"                 : "❌ ALWAYS_CRIT" );
        g_hMenuAttributes.AddItem( "10", HasAttribute( iTarget, IGNORE_ENEMIES )              ? "✅ IGNORE_ENEMIES"              : "❌ IGNORE_ENEMIES" );
        g_hMenuAttributes.AddItem( "11", HasAttribute( iTarget, HOLD_FIRE_UNTIL_FULL_RELOAD ) ? "✅ HOLD_FIRE_UNTIL_FULL_RELOAD" : "❌ HOLD_FIRE_UNTIL_FULL_RELOAD" );
        g_hMenuAttributes.AddItem( "12", HasAttribute( iTarget, PRIORITIZE_DEFENSE )          ? "✅ PRIORITIZE_DEFENSE"          : "❌ PRIORITIZE_DEFENSE" );
        g_hMenuAttributes.AddItem( "13", HasAttribute( iTarget, ALWAYS_FIRE_WEAPON )          ? "✅ ALWAYS_FIRE_WEAPON"          : "❌ ALWAYS_FIRE_WEAPON" );
        g_hMenuAttributes.AddItem( "14", HasAttribute( iTarget, TELEPORT_TO_HINT )            ? "✅ TELEPORT_TO_HINT"            : "❌ TELEPORT_TO_HINT" );
        g_hMenuAttributes.AddItem( "15", HasAttribute( iTarget, MINIBOSS )                    ? "✅ MINIBOSS"                    : "❌ MINIBOSS" );
        g_hMenuAttributes.AddItem( "16", HasAttribute( iTarget, USE_BOSS_HEALTH_BAR )         ? "✅ USE_BOSS_HEALTH_BAR"         : "❌ USE_BOSS_HEALTH_BAR" );
        g_hMenuAttributes.AddItem( "17", HasAttribute( iTarget, IGNORE_FLAG )                 ? "✅ IGNORE_FLAG"                 : "❌ IGNORE_FLAG" );
        g_hMenuAttributes.AddItem( "18", HasAttribute( iTarget, AUTO_JUMP )                   ? "✅ AUTO_JUMP"                   : "❌ AUTO_JUMP" );
        g_hMenuAttributes.AddItem( "19", HasAttribute( iTarget, AIR_CHARGE_ONLY )             ? "✅ AIR_CHARGE_ONLY"             : "❌ AIR_CHARGE_ONLY" );
        g_hMenuAttributes.AddItem( "20", HasAttribute( iTarget, PREFER_VACCINATOR_BULLETS )   ? "✅ PREFER_VACCINATOR_BULLETS"   : "❌ PREFER_VACCINATOR_BULLETS" );
        g_hMenuAttributes.AddItem( "21", HasAttribute( iTarget, PREFER_VACCINATOR_BLAST )     ? "✅ PREFER_VACCINATOR_BLAST"     : "❌ PREFER_VACCINATOR_BLAST" );
        g_hMenuAttributes.AddItem( "22", HasAttribute( iTarget, PREFER_VACCINATOR_FIRE )      ? "✅ PREFER_VACCINATOR_FIRE"      : "❌ PREFER_VACCINATOR_FIRE" );
        g_hMenuAttributes.AddItem( "23", HasAttribute( iTarget, BULLET_IMMUNE )               ? "✅ BULLET_IMMUNE"               : "❌ BULLET_IMMUNE" );
        g_hMenuAttributes.AddItem( "24", HasAttribute( iTarget, BLAST_IMMUNE )                ? "✅ BLAST_IMMUNE"                : "❌ BLAST_IMMUNE" );
        g_hMenuAttributes.AddItem( "25", HasAttribute( iTarget, FIRE_IMMUNE )                 ? "✅ FIRE_IMMUNE"                 : "❌ FIRE_IMMUNE" );
        g_hMenuAttributes.AddItem( "26", HasAttribute( iTarget, PARACHUTE )                   ? "✅ PARACHUTE"                   : "❌ PARACHUTE" );
        g_hMenuAttributes.AddItem( "27", HasAttribute( iTarget, PROJECTILE_SHIELD )           ? "✅ PROJECTILE_SHIELD"           : "❌ PROJECTILE_SHIELD" );
        g_hMenuAttributes.Display( iClient, MENU_TIME_FOREVER );
    }

    PrintToConsole( iClient, "------------------------ END ------------------------\n" );

    return Plugin_Handled;
}

public void MenuAttributeHandler( Menu m, MenuAction ma, int iParam1, int iParam2 )
{
    if ( ma == MenuAction_End )
    {
        delete m;
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: BlockAnnouncer

  Summary:  This hook function intercepts all sounds before they're
            emitted to clients and blocks announcer sounds from
            being played to the invading team.

  Args:     int aiClients[ MAXPLAYERS ]
              Array of clients to which the sound will be played.
            int& nClients
              Number of clients in the `aiClients` array.
            char szSample[ PLATFORM_MAX_PATH ]
              Path on disk to the sound that will be played
              relative to the "sound" folder.
            int& iEntity
              Entity emitting the sound.
            int& iChannel
              Channel emitting the sound.
            float& flVolume
              Sound volume.
            int& iLevel
              Sound level (aka attenuation).
            int& iPitch
              Sound pitch.
            int& iFlags.
              Sound flags.
            char szSoundEntry[ PLATFORM_MAX_PATH ]
              Game sound entry name.
            int& iSeed
              Sound seed.

  Returns:  Action
              Plugin_Continue to allow the sound to be played,
              Plugin_Stop to block it, Plugin_Changed when any
              parameter has been modified.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public Action BlockAnnouncer(
    int    aiClients[ MAXPLAYERS ],
    int&   nClients,
    char   szSample[ PLATFORM_MAX_PATH ],
    int&   iEntity,
    int&   iChannel,
    float& flVolume,
    int&   iLevel,
    int&   iPitch,
    int&   iFlags,
    char   szSoundEntry[ PLATFORM_MAX_PATH ],
    int&   iSeed
)
{
    if (
        StrContains( szSoundEntry, "Announcer." ) ||
        StrContains( szSoundEntry, "MVM.AttackDefend." )
        )
    {
        int n = 0;
        for ( int i = 0; i < sizeof( aiClients ); i++ )
        {
            int iClient = aiClients[ i ];
            if (
                0 < iClient <= MaxClients &&
                IsClientInGame( iClient ) &&
                TF2_GetClientTeam( iClient ) != TF_TEAM_PVE_INVADERS
                )
            {
                aiClients[ n++ ] = iClient;
            }
        }

        if ( n != nClients )
        {
            nClients = n;
            return Plugin_Changed;
        }
    }

    return Plugin_Continue;
}

public MRESReturn CFilterTFBotHasTag_PassesFilterImpl( int iThis, Handle hReturn, Handle hParams )
{
    if ( DHookIsNullParam( hParams, 1 ) || DHookIsNullParam( hParams, 2 ) )
    {
        return MRES_Ignored;
    }

    int iCaller = DHookGetParam( hParams, 2 );
    if ( !( 0 < iCaller <= MaxClients ) || !IsClientInGame( iCaller ) || IsFakeClient( iCaller ) )
    {
        return MRES_Ignored;
    }

    if ( !IsPlayerAlive( iCaller ) )
    {
        DHookSetReturn( hReturn, false );
        return MRES_Supercede;
    }

    // Don't care about players not controlling a bot
    if ( !g_bControllingBot[ iCaller ] )
    {
        return MRES_Ignored;
    }

    int iBot = GetClientOfUserId( g_iPlayersBot[ iCaller ] );
    if ( iBot <= 0 )
    {
        return MRES_Ignored;
    }

    char iszTags[ PLATFORM_MAX_PATH ];
    GetEntPropString( iThis, Prop_Data, "m_iszTags", iszTags, PLATFORM_MAX_PATH );
    bool bNegated = view_as< bool >( GetEntProp( iThis, Prop_Data, "m_bNegated" ) );
    // bool bRequireAllTags = view_as< bool >( GetEntProp( iFilter, Prop_Data, "m_bRequireAllTags" ) );    // Don't know of a map that uses this

    bool bHasTag = TF2_HasTag( iBot, iszTags );
    if ( bNegated )
    {
        bHasTag = !bHasTag;
    }

    int  iEntity = DHookGetParam( hParams, 1 );
    char szClassname[ 64 ];
    GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

    // We don't care about you
    if ( StrEqual( szClassname, "func_nav_prerequisite" ) )
    {
        return MRES_Ignored;
    }

    // These work the opposite way
    if ( StrEqual( szClassname, "trigger_add_tf_player_condition" ) )
    {
        bHasTag = !bHasTag;
    }

    // PrintToServer( "Filter %i on entity %s asks: HasTag %N %s ? %s", iFilter, szClassName, iBot, iszTags, bHasTag ? "Yes" : "No" );

    DHookSetReturn( hReturn, bHasTag );
    return MRES_Supercede;
}

public MRESReturn CTFPlayer_IsValidObserverTarget( int iThis, Handle hReturn, Handle hParams )
{
    if ( DHookIsNullParam( hParams, 1 ) )
    {
        return MRES_Ignored;
    }

    int iTarget = DHookGetParam( hParams, 1 );

    // Valid
    if ( !( 0 < iTarget <= MaxClients ) || !IsClientInGame( iThis ) || !IsClientInGame( iTarget ) )
    {
        return MRES_Ignored;
    }

    // We only care about spectating bots that are controlled
    if ( !IsFakeClient( iTarget ) || !g_bIsControlled[ iTarget ] )
    {
        return MRES_Ignored;
    }

    DHookSetReturn( hReturn, false );
    return MRES_Supercede;
}

public MRESReturn CTFPlayer_ShouldGib( int iThis, Handle hReturn, Handle hParams )
{
    if ( DHookIsNullParam( hParams, 1 ) || TF2_GetClientTeam( iThis ) != TF_TEAM_PVE_INVADERS )
    {
        return MRES_Ignored;
    }

    if (
         GetEntProp( iThis, Prop_Send, "m_bIsMiniBoss" ) ||
         GetEntPropFloat( iThis, Prop_Send, "m_flModelScale" ) > 1.0
        )
    {
        DHookSetReturn( hReturn, true );
        return MRES_Supercede;
    }

    switch ( TF2_GetPlayerClass( iThis ) )
    {
        case TFClass_Sniper, TFClass_Medic, TFClass_Spy, TFClass_Engineer:
        {
            DHookSetReturn( hReturn, false );
            return MRES_Supercede;
        }

        default:
        {
            return MRES_Ignored;
        }
    }
}

public MRESReturn CBaseEntity_ShouldTransmit( int iThis, Handle hReturn, Handle hParams )
{
    if ( IsValidEntity( iThis ) )
    {
        bool bNotPlaced = ( view_as< bool >( GetEntProp( iThis, Prop_Send, "m_bCarried" ) ) ||
                          view_as< bool >( GetEntProp( iThis, Prop_Send, "m_bPlacing") ) );
        if ( bNotPlaced )   // Let game decide
        {
            return MRES_Ignored;
        }

        DHookSetReturn( hReturn, FL_EDICT_ALWAYS );
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

public void OnClientDisconnect( int iClient )
{
    if ( !( 0 < iClient <= MaxClients ) || !IsClientInGame( iClient ) )
    {
        return;
    }

    TF2_RestoreBot( iClient );
}

public void OnEntityCreated( int iEntity, const char[] szClassName )
{
    if ( StrEqual( szClassName, "item_currencypack_custom" ) )
    {
        SDKHook( iEntity, SDKHook_SpawnPost, OnCurrencySpawnPost );
    }
    else if ( g_bBlockRagdoll && StrEqual( szClassName, "tf_ragdoll" ) )
    {
        AcceptEntityInput( iEntity, "Kill" );
        g_bBlockRagdoll = false;
    }
    else if ( StrEqual( szClassName, "filter_tf_bot_has_tag" ) )
    {
        SDKHook( iEntity, SDKHook_SpawnPost, OnFilterSpawnPos );
    }
    else if ( StrEqual( szClassName, "entity_revive_marker" ) )
    {
        SDKHook( iEntity, SDKHook_SpawnPost, OnReviveMarkerSpawnPost );
    }
    else if ( StrEqual( szClassName, "obj_teleporter" ) )
    {
        SDKHook( iEntity, SDKHook_SetTransmit, Hook_TeleporterTransmit );
    }
    else if( StrEqual( szClassName, "func_respawnroom" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnSpawnStartTouch );
        SDKHook( iEntity, SDKHook_EndTouch, OnSpawnEndTouch );
    }
    else if ( StrEqual( szClassName, "func_capturezone" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnHatchStartTouch );
        SDKHook( iEntity, SDKHook_EndTouch, OnHatchEndTouch );
    }
    else if ( StrEqual( szClassName, "item_teamflag" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnFlagTouch );
        SDKHook( iEntity, SDKHook_Touch, OnFlagTouch );
    }
}

public void OnFilterSpawnPos( int iEntity )
{
    DHookEntity( g_hfnPassesFilterImpl, true, iEntity );
}

public void OnReviveMarkerSpawnPost( int iEntity )
{
    if ( view_as< TFTeam >( GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ) == TF_TEAM_PVE_INVADERS )
    {
        // Remove the marker if it's from a robot player
        RemoveEntityNextFrame( iEntity );
    }
}

void Frame_SentryVision_Create( int iRef )
{
    int iSentry = EntRefToEntIndex( iRef );
    if ( iSentry <= MaxClients || view_as< TFTeam >( GetEntProp( iSentry, Prop_Send, "m_iTeamNum" ) ) != TF_TEAM_PVE_DEFENDERS )
    {
        return;
    }

    // Create sentry-vision glow
    int iSentryGlow = CreateEntityByName( "tf_taunt_prop" );
    if ( iSentryGlow <= MaxClients )
    {
        return;
    }

    // Make the sentry always transmit
    DHookEntity( g_hfnShouldTransmit, true, iSentry );

    float flModelScale = GetEntPropFloat( iSentry, Prop_Send, "m_flModelScale" );
    CopyEntProp( iSentry, iSentryGlow, Prop_Send, "m_nModelIndex" );

    char szModelName[ PLATFORM_MAX_PATH ];
    GetEntPropString( iSentry, Prop_Data, "m_ModelName", szModelName, sizeof( szModelName ) );
    SetEntityModel( iSentryGlow, szModelName );

    DispatchSpawn( iSentryGlow );
    ActivateEntity( iSentryGlow );

    SetEntityRenderMode( iSentryGlow, RENDER_TRANSCOLOR );
    SetEntityRenderColor( iSentryGlow, 0, 0, 0, 0 );
    SetEntProp( iSentryGlow, Prop_Send, "m_bGlowEnabled", true );
    SetEntPropFloat( iSentryGlow, Prop_Send, "m_flModelScale", flModelScale );
    SetEntProp(
        iSentryGlow,
        Prop_Send,
        "m_fEffects",
        GetEntProp( iSentryGlow, Prop_Send, "m_fEffects" ) |
            EF_BONEMERGE |
            EF_BONEMERGE_FASTCULL |
            EF_NOSHADOW |
            EF_NORECEIVESHADOW
    );

    SetVariantString( "!activator" );
    AcceptEntityInput( iSentryGlow, "SetParent", iSentry );

    SDKHook( iSentryGlow, SDKHook_SetTransmit, SentryVision_OnThink );
}

public Action SentryVision_OnThink( int iSentryGlow, int iClient )
{
    int moveparent = GetEntPropEnt( iSentryGlow, Prop_Send, "moveparent" );
    if ( moveparent > MaxClients )
    {
        // Safe check to know if I'm parented to the sentry and NOT carried! We don't want to put the glow on the blueprint!
        bool bNotPlaced = ( view_as< bool >( GetEntProp( moveparent, Prop_Send, "m_bCarried" ) ) ||
                          view_as< bool >( GetEntProp( moveparent, Prop_Send, "m_bPlacing" ) ) );
        if ( bNotPlaced )   // The sentry is carried, set my parent to the engie!
        {
            moveparent = TF2_GetObjectBuilder( moveparent );
        }
    }
    else if ( 0 < moveparent <= MaxClients ) // My parent is the engie
    {
        static int c_iRefCarriedObjects[ MAXPLAYERS + 1 ];    // Last carried object by the engie.

        bool bCarryingObject = view_as< bool >( GetEntProp( moveparent, Prop_Send, "m_bCarryingObject" ) );
        if ( bCarryingObject )
        {
            int iCarriedObject = GetEntPropEnt( moveparent, Prop_Send, "m_hCarriedObject" );
            // Save the building's index object, very important so we don't blindy loop across every sentry guns once it's placed,
            // and end up setting 2 glows on the same sentry (i.e 2 glows on an engie's mini-sentry)
            if ( iCarriedObject > MaxClients )
            {
                c_iRefCarriedObjects[ moveparent ] = EntIndexToEntRef( iCarriedObject );
            }
            else
            {
                RemoveEntity( iSentryGlow );
            }
        }
        // The sentry is no longer carried but I'm still parented to the player, move my parent to the sentry
        else
        {
            int iSentry = EntRefToEntIndex( c_iRefCarriedObjects[ moveparent ] );
            if ( iSentry > MaxClients )
            {
                moveparent = iSentry;
            }
            // The sentry has been destroyed, remove our glow
            else
            {
                RemoveEntity( iSentryGlow );
            }
        }
    }

    // Keep my model and parent infos up to date
    if ( moveparent > 0 )
    {
        int iOldParent = GetEntPropEnt( iSentryGlow, Prop_Send, "moveparent" );
        if ( moveparent != iOldParent )
        {
            // Unparent me from my old parent.
            AcceptEntityInput( iSentryGlow, "ClearParent" );

            float vecAbsOriginParent[3];
            GetEntPropVector( moveparent, Prop_Data, "m_vecAbsOrigin", vecAbsOriginParent );
            TeleportEntity( iSentryGlow, vecAbsOriginParent, NULL_VECTOR, NULL_VECTOR );

            // Parent me to the new entity.
            SetVariantString( "!activator" );
            AcceptEntityInput( iSentryGlow, "SetParent", moveparent );
        }

        if ( GetEntProp( iSentryGlow, Prop_Send, "m_nModelIndex" ) != GetEntProp( moveparent, Prop_Send, "m_nModelIndex" ) )
        {
            // Update my model
            char szModelName[ PLATFORM_MAX_PATH ];
            GetEntPropString( moveparent, Prop_Data, "m_ModelName", szModelName, sizeof( szModelName ) );

            if ( StrEmpty( szModelName ) )
            {
                SetEntityModel( iSentryGlow, szModelName );
                CopyEntProp( moveparent, iSentryGlow, Prop_Send, "m_nModelIndex" );
            }
        }
        // If the engie/sentry has been resized by another plugin, fix our glow
        if ( GetEntPropFloat( iSentryGlow, Prop_Send, "m_flModelScale" ) != GetEntPropFloat( moveparent, Prop_Send, "m_flModelScale" ) )
        {
            CopyEntProp( moveparent, iSentryGlow, Prop_Send, "m_flModelScale" );
        }
    }
    else
    {
        // No more parent
        RemoveEntity( iSentryGlow );
    }

    if ( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && g_bIsSentryBuster[ iClient ] )
    {
        // Allow the sentry buster to see the glow
        return Plugin_Continue;
    }

    // Do not allow other players to see the glow
    return Plugin_Handled;
}

public void Event_SappedObject( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient          = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    int iSapper          = hEvent.GetInt( "sapperid" );
    TFObjectType iObject = view_as< TFObjectType >( hEvent.GetInt( "object" ) );
    if (
        iObject == TFObject_Teleporter &&
        0 < iClient <= MaxClients      &&
        IsClientInGame( iClient )      &&
        TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS
        )
    {
        RemoveEntity( iSapper );
    }
}

public Action OnFlagTouch( int iEntity, int iOther )
{
    // If its not a client we don't care
    if ( !( 0 < iOther <= MaxClients ) )
    {
        return Plugin_Continue;
    }

    // Only care about invaders
    if ( TF2_GetClientTeam( iOther ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Handled;
    }

    // Controlled bots should never be able to pickup bomb
    if ( g_bIsControlled[ iOther ] )
    {
        return Plugin_Handled;
    }

    // Gatebots ignore bombs and only capture gates
    if ( TF2_HasTag( iOther, "bot_gatebot" ) )
    {
        return Plugin_Handled;
    }

    // Sentry busters shouldn't pick up the bomb
    if ( g_bIsSentryBuster[ iOther ] )
    {
        return Plugin_Handled;
    }

    if ( g_bControllingBot[ iOther ] )
    {
        int iBot = GetClientOfUserId( g_iPlayersBot[ iOther ] );
        if ( 0 < iBot <= MaxClients && IsInASquad( iBot ) )
        {
            if ( TF2_GetBotSquadLeader( iBot ) != iOther )
            {
                return Plugin_Handled;
            }
        }
    }

    return Plugin_Continue;
}

public Action OnHatchStartTouch( int iEntity, int iClient )
{
    if ( !( 0 < iClient <= MaxClients ) || IsFakeClient( iClient ) )
    {
        return Plugin_Continue;
    }

    if ( !TF2_HasBomb( iClient ) )
    {
        return Plugin_Handled;
    }

    if ( g_bDeploying[ iClient ] )
    {
        return Plugin_Continue;
    }

    if ( TF2_IsPlayerInCondition( iClient, TFCond_Charging ) )
    {
        TF2_RemoveCondition( iClient, TFCond_Charging );
    }
    if ( TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) )
    {
        TF2_RemoveCondition( iClient, TFCond_Taunting );
    }

    if ( TF2_IsGiant( iClient ) )
    {
        EmitGameSoundToAll( "MVM.DeployBombGiant", iClient );
    }
    else
    {
        EmitGameSoundToAll( "MVM.DeployBombSmall", iClient );
    }

    EmitGameSoundToAll( "Announcer.MVM_Bomb_Alert_Deploying", SOUND_FROM_WORLD );

    // Stop the player from sliding around
    TeleportEntity( iClient, NULL_VECTOR, NULL_VECTOR, { 0.0, 0.0, 0.0 } );

    SDKCall( g_hfnPlaySpecificSequence, iClient, "primary_deploybomb" );
    RequestFrame( DisableDeployBombAnimation, GetClientUserId( iClient ) );

    TF2_SetClientTauntCamMode( iClient, TauntCam_Enabled );

    g_flBombDeployTime[ iClient ] = GetGameTime() + FindConVar( "tf_deploying_bomb_time" ).FloatValue + 0.5;
    g_bDeploying[ iClient ]       = true;

    return Plugin_Continue;
}

public void DisableDeployBombAnimation( int iUserId )
{
    static int iCount = 0;

    int iClient = GetClientOfUserId( iUserId );
    if ( iClient == 0 )
    {
        return;
    }

    if ( iCount > 6 )
    {
        float vecClientAbsOrigin[ 3 ], vecTargetPos[ 3 ];
        GetClientAbsOrigin( iClient, vecClientAbsOrigin );

        vecTargetPos = TF2_GetBombHatchPosition();

        float vecResult[ 3 ], ang[ 3 ];
        SubtractVectors( vecTargetPos, vecClientAbsOrigin, vecResult );
        NormalizeVector( vecResult, vecResult );
        GetVectorAngles( vecResult, ang );

        ang[ 0 ] = 0.0;

        SetVariantString( "1" );
        AcceptEntityInput( iClient, "SetCustomModelRotates" );

        SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", false );

        char szVector[ 16 ];
        FormatEx( szVector, sizeof( szVector ), "0 %f 0", ang[ 1 ] );
        SetVariantString( szVector );
        AcceptEntityInput( iClient, "SetCustomModelRotation" );

        iCount = 0;
    }
    else
    {
        SDKCall( g_hfnPlaySpecificSequence, iClient, "primary_deploybomb" );
        RequestFrame( DisableDeployBombAnimation, iUserId );
        iCount++;
    }
}

public void OnHatchEndTouch( int iEntity, int iClient )
{
    if ( !( 0 < iClient <= MaxClients ) || IsFakeClient( iClient ) || !TF2_HasBomb( iClient ) )
    {
        return;
    }

    SetVariantString( "1" );
    AcceptEntityInput( iClient, "SetCustomModelRotates" );

    SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", true );

    TF2_SetClientTauntCamMode( iClient, TauntCam_Disabled );

    g_flBombDeployTime[ iClient ] = -1.0;
    g_bDeploying[ iClient ]       = false;
}

public void OnSpawnStartTouch( int iRespawnRoom, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iRespawnRoom, Prop_Send, "m_iTeamNum" ) );
    if (
        eTeam != TF_TEAM_PVE_INVADERS         ||
        !( 0 < iEntity <= MaxClients )        ||
        TF2_GetClientTeam( iEntity ) != eTeam ||
        IsFakeClient( iEntity )
        )
    {
        return;
    }

    TF2_AddCondition( iEntity, TFCond_UberchargedHidden );
    TF2_AddCondition( iEntity, TFCond_ImmuneToPushback );
    if ( TF2_HasBomb( iEntity ) )
    {
        RequestFrame( UpdateBombHud, GetClientUserId( iEntity ) );
    }
}

public void OnSpawnEndTouch( int iRespawnRoom, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iRespawnRoom, Prop_Send, "m_iTeamNum" ) );
    if (
        eTeam != TF_TEAM_PVE_INVADERS        ||
        !( 0 < iEntity <= MaxClients )        ||
        TF2_GetClientTeam( iEntity ) != eTeam ||
        IsFakeClient( iEntity )
        )
    {
        return;
    }

    TF2_RemoveCondition( iEntity, TFCond_UberchargedHidden );
    TF2_RemoveCondition( iEntity, TFCond_ImmuneToPushback );

    if ( TF2_HasBomb( iEntity ) )
    {
        switch( g_iFlagCarrierUpgradeLevel[ iEntity ] )
        {
            case 0: g_flNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" ).FloatValue;
            case 1: g_flNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade" ).FloatValue;
            case 2: g_flNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade" ).FloatValue;
        }
        // The bomb HUD needs to be updated BEFORE we add the spawn protection conditions again
        UpdateBombHud( GetClientUserId( iEntity ) );
    }

    TF2_AddCondition( iEntity, TFCond_UberchargedHidden, 1.0 );
    TF2_AddCondition( iEntity, TFCond_ImmuneToPushback, 1.0 );
}

public void TF2_OnConditionAdded( int iClient, TFCond eCond )
{
    if ( IsFakeClient( iClient ) )
    {
        if ( g_bIsControlled[ iClient ] && HasEntProp( iClient, Prop_Send, "moveparent" ) )
        {
            TF2_RemoveCondition( iClient, eCond );
        }
        return;
    }

    TF2_RemoveCondition( iClient, TFCond_SpawnOutline );

    // Gate stun
    if ( eCond == TFCond_MVMBotRadiowave )
    {
        TF2_StunPlayer(
            iClient,
            TF2Util_GetPlayerConditionDuration( iClient, TFCond_MVMBotRadiowave ),
            1.0,
            TF_STUNFLAG_BONKSTUCK | TF_STUNFLAG_NOSOUNDOREFFECT,
            TF2Util_GetPlayerConditionProvider( iClient, eCond )
            );
    }
}

public void OnCurrencySpawnPost( int iCurrency )
{
    int iOwnerEntity = TF2_GetEntityOwner( iCurrency );   // The bot who dropped the money
    if ( !( 0 < iOwnerEntity <= MaxClients ) || !g_bIsControlled[ iOwnerEntity ] )
    {
        return;
    }

    int iController = GetClientOfUserId( g_iController[ iOwnerEntity ] );   // The bot's controller player
    int iBot        = GetClientOfUserId( g_iPlayersBot[ iController ] );    // The bot of the controller

    if ( iBot != 0 && IsFakeClient( iBot ) && iController != 0 && iBot == iOwnerEntity && g_bControllingBot[ iController ] )
    {
        float vecAbsOrigin[ 3 ];
        GetClientAbsOrigin( iController, vecAbsOrigin );
        vecAbsOrigin[ 2 ] += 32.0;

        TeleportEntity( iCurrency, vecAbsOrigin, NULL_VECTOR, NULL_VECTOR );
    }
}

public Action OnPlayerRunCmd(
    int   iClient,
    int&  iButtons,
    int&  iImpulse,
    float vecVelocity[ 3 ],
    float angView[ 3 ],
    int&  iWeapon,
    int&  iSubtype,
    int&  iCmdnum,
    int&  iTickCount,
    int&  iSeed,
    int   vecMouse[ 2 ]
    )
{
    if ( IsFakeClient( iClient ) )
    {
        if ( g_bIsControlled[ iClient ] )
        {
            iImpulse = 0;
            iButtons = 0;
            return Plugin_Changed;
        }

        return Plugin_Continue;
    }

    if ( g_bControllingBot[ iClient ] && IsPlayerAlive( iClient ) && TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS )
    {
        int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );

        SetEntPropFloat( iClient, Prop_Send, "m_flCloakMeter", 100.0 );

        if ( SDKCall( g_hfnShouldAutoJump, iBot ) )
        {
            iButtons |= IN_JUMP;
        }

        if ( TF2_GetPlayerClass( iClient ) == TFClass_DemoMan && HasAttribute( iBot, AIR_CHARGE_ONLY ) )
        {
            if ( !GetEntProp( iClient, Prop_Send, "m_bJumping" ) )
            {
                iButtons &= ~IN_ATTACK2;
            }
        }

        int iActiveWeapon = TF2_GetClientActiveWeapon( iClient );
        if ( IsValidEntity( iActiveWeapon ) )
        {
            if ( TF2_IsPlayerInCondition( iClient, TFCond_UberchargedHidden ) && TF2_IsPlayerInCondition( iClient, TFCond_ImmuneToPushback ) )
            {
                if ( !( TF2_GetPlayerClass( iClient ) == TFClass_Medic && GetPlayerWeaponSlot( iClient, TFWeaponSlot_Secondary ) == iActiveWeapon ) )
                {
                    //Allow medic to heal in spawn if they have their medigun out.
                    SetEntPropFloat( iClient, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 0.5 );
                }

                // Disallow crouching in spawn so when you lose control of your bot the bot wont spawn inside ground.
                iButtons &= ~IN_DUCK;
            }

            if ( HasAttribute( iBot, HOLD_FIRE_UNTIL_FULL_RELOAD ) )
            {
                int iClip1 = GetEntProp( iActiveWeapon, Prop_Send, "m_iClip1" );

                if ( iClip1 <= 0 )
                {
                    g_bReloadingBarrage[ iClient ] = true;

                    SetHudTextParams( -1.0, -0.55, 0.75, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0 );
                    ShowSyncHudText( iClient, g_hHudReload, "RELOADING BARRAGE!" );
                }
                else if ( g_bReloadingBarrage[ iClient ] )
                {
                    int iMaxClip1 = SDKCall( g_hfnGetMaxClip1, iActiveWeapon );

                    SetHudTextParams( -1.0, -0.55, 0.25, 255, 150, 0, 255, 0, 0.0, 0.0, 0.0 );
                    ShowSyncHudText( iClient, g_hHudReload, "RELOADING... (%i / %i)", iClip1, iMaxClip1 );

                    // Allows reloading even if the user is holding attack, although it looks weird on their screen.
                    iButtons &= ~( IN_ATTACK | IN_ATTACK2 );
                    SetEntPropFloat( iClient, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 0.25 );

                    if ( iClip1 >= iMaxClip1 )
                    {
                        SetHudTextParams( -1.0, -0.55, 1.75, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0 );
                        ShowSyncHudText( iClient, g_hHudReload, "READY TO FIRE! (%i / %i)", iClip1, iMaxClip1 );

                        g_bReloadingBarrage[ iClient ] = false;
                    }
                }
            }

            if ( HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) && !g_bReloadingBarrage[ iClient ] )
            {
                iButtons |= IN_ATTACK;
            }
        }

        // TODO: Is the `IsFakeClient` check necessary here? Doesn't `g_bControllingBot[ iClient ]` imply that this must be a real player?
        if ( iBot != 0 && IsFakeClient( iBot ) )
        {
            SetHudTextParams( 1.0, 0.0, 0.1, 88, 133, 162, 0, 0, 0.0, 0.0, 0.0 );
            ShowSyncHudText( iClient, g_hHudInfo, "Playing as %N", iBot );
            // TODO: Use SuppressFire instead of doing this
            SetEntPropFloat( iBot, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 0.5 ); // Don't allow the bot to attack

            // FIXME: Doesn't work
            // TF2_InstructPlayer( iClient );

            if ( TF2_IsPlayerInCondition( iClient, TFCond_UberchargedHidden ) && TF2_IsPlayerInCondition( iClient, TFCond_ImmuneToPushback ) )
            {
                if ( g_flControlEndTime[ iClient ] <= GetGameTime() )
                {
                    PrintColoredChat( iClient, COLOR_RED ... "You have lost control of " ... COLOR_BLUE ... "%N" ... COLOR_RED ... " and received a 30 second cooldown from playing as a robot for staying in spawn too long", iBot );

                    g_bControllingBot[ iClient ] = false;

                    TF2_RestoreBot( iClient );
                    TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

                    g_flCooldownEndTime[ iClient ] = GetGameTime() + 30.0;

                    return Plugin_Continue;
                }
                else if ( g_flControlEndTime[ iClient ] > GetGameTime() )
                {
                    float flTimeLeft = g_flControlEndTime[ iClient ] - GetGameTime();

                    if ( flTimeLeft <= 15.0 )
                    {
                        SetHudTextParams( -1.0, -0.8, 0.1, 255, 0, 0, 0, 0, 0.0, 0.0, 0.0 );
                        ShowSyncHudText( iClient, g_hHudInfo, "You have %.0f seconds to leave spawn or you will lose control of your bot", flTimeLeft );
                    }
                }
            }

            if ( g_bIsSentryBuster[ iClient ] && HasEntProp( iClient, Prop_Data, "m_hGroundEntity" ) )
            {
                float vecOrigin[ 3 ], angEyeAngles[ 3 ];
                GetClientAbsOrigin( iClient, vecOrigin );
                GetClientEyeAngles( iClient, angEyeAngles );

                // Disable the use of the sentry buster's caber
                SetEntPropFloat( iClient, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 0.5 );

                // Detonate buster if the player is pressing M1 or taunting
                if( ( iButtons & IN_ATTACK || TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) ) && !HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) )
                {
                    TF2_RestoreBot( iClient );
                    TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
                }

                // Sentry Buster: Check for engineers carrying buildings nearby
                for ( int i = 1; i <= MaxClients; i++ )
                {
                    if (
                        !IsClientInGame( i )                                   ||
                        TF2_GetClientTeam( i ) == TF2_GetClientTeam( iClient ) ||
                        !GetEntProp( i, Prop_Send, "m_bCarryingObject" )       ||
                        i == iClient
                        )
                    {
                        continue;
                    }

                    float vecEntOrigin[ 3 ];
                    GetClientAbsOrigin( i, vecEntOrigin );

                    if ( GetVectorDistance( vecOrigin, vecEntOrigin ) <= 100.0 )
                    {
                        TF2_RestoreBot( iClient );
                        TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
                    }
                }
            }
            else
            {
                CopyEntProp( iClient, iBot, Prop_Send, "m_iHealth" );
            }
        }

        if ( TF2_HasBomb( iClient ) )
        {
            if ( g_bDeploying[ iClient ] )
            {
                if ( g_flBombDeployTime[ iClient ] <= GetGameTime() )
                {
                    if ( iBot > 0 && IsFakeClient( iBot ) )
                    {
                        PrintColoredChatAll( COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " playing as " ... COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " deployed the " ... COLOR_UNIQUE ... "BOMB" ... COLOR_DEFAULT ... " with " ... COLOR_RED ... "%i HP" ... COLOR_DEFAULT ... "!", iClient, iBot, GetClientHealth( iClient ) );
                    }
                    else
                    {
                        PrintColoredChatAll( COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " deployed the " ... COLOR_UNIQUE ... "BOMB" ... COLOR_DEFAULT ... " with " ... COLOR_RED ... "%i HP" ... COLOR_DEFAULT ... "!", iClient, GetClientHealth( iClient ) );
                    }

                    g_bBlockRagdoll         = true;
                    g_bDeploying[ iClient ] = false;

                    TF2_RobotsWin();

                    g_flCooldownEndTime[ iClient ] = GetGameTime() + 10.0;

                    EmitGameSoundToAll( "Announcer.MVM_Robots_Planted", SOUND_FROM_WORLD );
                }

                iButtons   &= ~( IN_JUMP | IN_ATTACK | IN_ATTACK2 | IN_ATTACK3 );
                vecVelocity = { 0.0, 0.0, 0.0 };

                return Plugin_Changed;
            }

            if (
                !TF2_IsPlayerInCondition( iClient, TFCond_Taunting )          &&
                !TF2_IsPlayerInCondition( iClient, TFCond_UberchargedHidden ) &&
                !TF2_IsPlayerInCondition( iClient, TFCond_ImmuneToPushback )  &&
                !g_bDeploying[ iClient ]
                )
            {
                iButtons &= ~IN_JUMP;

                if ( !TF2_IsGiant( iClient ) )
                {
                    if ( g_iFlagCarrierUpgradeLevel[ iClient ] > 0 )
                    {
                        float vecOrigin[ 3 ];
                        GetClientAbsOrigin( iClient, vecOrigin );

                        for ( int i = 1; i <= MaxClients; i++ )
                        {
                            if (
                                !IsClientInGame( i )                                   ||
                                TF2_GetClientTeam( i ) != TF2_GetClientTeam( iClient ) ||
                                g_iFlagCarrierUpgradeLevel[ iClient ] < 1              ||
                                i == iClient
                                )
                            {
                                continue;
                            }

                            float vecEntOrigin[ 3 ];
                            GetClientAbsOrigin( i, vecEntOrigin );

                            if ( GetVectorDistance( vecOrigin, vecEntOrigin ) <= 450.0 )
                            {
                                TF2_AddCondition( i, TFCond_DefenseBuffNoCritBlock, 0.125 );
                            }
                        }
                    }

                    if ( g_flNextBombUpgradeTime[ iClient ] <= GetGameTime() && g_iFlagCarrierUpgradeLevel[ iClient ] < 3 && HasEntProp( iClient, Prop_Send, "m_hGroundEntity" ) )
                    {
                        FakeClientCommandThrottled( iClient, "taunt" );

                        if ( TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) )
                        {
                            g_iFlagCarrierUpgradeLevel[ iClient ]++;

                            switch ( g_iFlagCarrierUpgradeLevel[ iClient ] )
                            {
                                case 1:
                                {
                                    g_flNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade" ).FloatValue;
                                    TF2_AddCondition( iClient, TFCond_DefenseBuffNoCritBlock );

                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup1", PATTACH_POINT_FOLLOW, iClient, "head", 0 );
                                }
                                case 2:
                                {
                                    g_flNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade" ).FloatValue;

                                    Address pHealthRegen = TF2Attrib_GetByName( iClient, "health regen" );
                                    float   flRegen      = 0.0;
                                    if ( pHealthRegen != Address_Null )
                                    {
                                        flRegen = TF2Attrib_GetValue( pHealthRegen );
                                    }

                                    TF2Attrib_SetByName( iClient, "health regen", flRegen + 45.0 );
                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup2", PATTACH_POINT_FOLLOW, iClient, "head", 0 );
                                }
                                case 3:
                                {
                                    TF2_AddCondition( iClient, TFCond_CritOnWin );
                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup3", PATTACH_POINT_FOLLOW, iClient, "head", 0 );
                                }
                            }
                            EmitGameSoundToAll( "MVM.Warning", SOUND_FROM_WORLD );
                            RequestFrame( UpdateBombHud, GetClientUserId( iClient ) );
                        }
                    }
                }
                else if ( g_iFlagCarrierUpgradeLevel[ iClient ] != 4 )
                {
                    g_iFlagCarrierUpgradeLevel[ iClient ] = 4;
                    RequestFrame( UpdateBombHud, GetClientUserId( iClient ) );
                }
            }
        }
    }
    else
    {
        int iObserved = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

        if ( TF2_ObservedIsValidClient( iClient ) )
        {
            SetHudTextParams( 1.0, 0.0, 0.1, 126, 126, 126, 0, 0, 0.0, 0.0, 0.0 );
            ShowSyncHudText( iClient, g_hHudInfo, "Call for MEDIC! to play as %N", iObserved );
        }
        else if ( 0 < iObserved <= MaxClients && IsFakeClient( iObserved ) )
        {
            int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
            if ( iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE )
            {
                SetHudTextParams( 1.0, 0.0, 0.1, 255, 0, 0, 0, 0, 0.0, 0.0, 0.0 );
                ShowSyncHudText( iClient, g_hHudInfo, "Cannot play as %N", iObserved );
            }
        }
    }

    return Plugin_Continue;
}

stock bool FakeClientCommandThrottled( int iClient, const char[] szCommand )
{
    static float c_flNextCommandTime[ MAXPLAYERS + 1 ] = { 0.0, ... };

    if ( c_flNextCommandTime[ iClient ] > GetGameTime() )
    {
        return false;
    }

    FakeClientCommand( iClient, szCommand );

    c_flNextCommandTime[ iClient ] = GetGameTime() + 0.4;

    return true;
}

public void Player_OnTakeDamageAlivePost(
    int         iVictim,
    int         iAttacker,
    int         iInflictor,
    float       flDamage,
    int         iDamageType,
    int         iWeapon,
    const float vecDamageForce[ 3 ],
    const float vecDamagePosition[ 3 ],
    int         iDamageCustom
    )
{
    if ( !( 0 < iVictim <= MaxClients ) || !( 0 < iAttacker <= MaxClients ) )
    {
        return;
    }

    if ( !TF2_IsGiant( iVictim ) )
    {
        return;
    }

    if ( GetRandomInt( 0, 100 ) > FindConVar( "tf_bot_notice_backstab_chance" ).IntValue )
    {
        return;
    }

    if ( ( iDamageCustom == TF_CUSTOM_BACKSTAB ) && ( iDamageType & DMG_CRIT ) )
    {
        // Indicate to the giant that he is getting backstabbed.
        EmitGameSoundToClient( iVictim, "Player.Spy_Shield_Break" );
        PrintCenterText( iVictim, "!!!!!! YOU WERE BACKSTABBED !!!!!!" );
    }

    return;
}

stock void TF2_InstructPlayer( int iClient )
{
    if ( g_flNextInstructionTime[ iClient ] > GetGameTime() )
    {
        return;
    }

    LogServer( "Trying to instruct %L...", iClient );

    int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
    if ( iBot == 0 )
    {
        return;
    }

    if ( TF2_HasBomb( iClient ) )
    {
        LogServer( "%N has the bomb. Instructing him to deploy it...", iClient );

        TF2_ShowPositionalAnnotationToClient(
            iClient,
            TF2_GetBombHatchPosition(),
            "Deploy the bomb!",
            _,
            "coach/coach_attack_here.wav",
            6.0
            );
    }
    else
    {
        LogServer( "%N does't have the bomb. Instructing him to do something else...", iClient );

        int iLeader = TF2_GetBotSquadLeader( iBot );
        if ( 0 < iLeader <= MaxClients && IsClientInGame( iLeader ) && IsPlayerAlive( iLeader ) && iLeader != iClient )
        {
            // We're in a squad, so tell the player to focus on making sure the squad leader
            // successfully deploys the bomb.
            char szMsg[ 32 ];
            if ( TF2_GetPlayerClass( iClient ) == TFClass_Medic )
            {
                LogServer( "%N is a Medic.", iClient );

                int iWepSecondary = GetPlayerWeaponSlot( iClient, TFWeaponSlot_Secondary );
                if ( iWepSecondary > MaxClients && GetEntPropEnt( iWepSecondary, Prop_Send, "m_hHealingTarget" ) != iLeader )
                {
                    LogServer( "Instructing %N to heal their squad leader.", iClient );
                    strcopy( szMsg, sizeof( szMsg ), "Heal your squad leader!" );
                }
                else if ( iWepSecondary == -1 )
                {
                    LogServer( "Instructing %N to protect their squad leader.", iClient );
                    strcopy( szMsg, sizeof( szMsg ), "Protect your squad leader!" );
                }
            }
            else
            {
                LogServer( "%N is not a Medic.", iClient );
                strcopy( szMsg, sizeof( szMsg ), "Protect your squad leader!" );
            }

            TF2_ShowFollowingAnnotationToClient(
                iClient,
                iLeader,
                szMsg,
                _,
                "coach/coach_defend_here.wav",
                6.0
            );
        }
        else
        {
            // We're not in a squad, so tell the player to focus on other important
            // stuff like capturing gates and picking up the bomb.

            LogServer( "%N is not is a squad.", iClient );

            // If they're a gatebot tell them to capture the next available gate.
            if ( TF2_HasTag( iBot, "bot_gatebot" ) )
            {
                LogServer( "%N is a gatebot. Trying to find a timer door...", iClient );

                int iTrigger = -1;
                while ( ( iTrigger = FindEntityByClassname( iTrigger, "trigger_timer_door" ) ) != -1 )
                {
                    if ( !view_as< bool >( GetEntProp( iTrigger, Prop_Data, "m_bDisabled") ) )
                    {
                        TF2_ShowPositionalAnnotationToClient(
                            iClient,
                            WorldSpaceCenter( iTrigger ),
                            "Capture!",
                            _,
                            "coach/coach_attack_here.wav",
                            8.0
                        );
                        break;
                    }
                }
            }
            else
            {
                // Not a gatebot; get or escort the bomb
                LogServer( "%N is not a gatebot. Trying to find the bomb...", iClient );

                int iBomb = -1;
                while ( ( iBomb = FindEntityByClassname( iBomb, "item_teamflag" ) ) != -1 )
                {
                    /*--------------------------------------------------------------------
                      Ignore inactive bombs and ones that are not our team's. In MvM, if
                      a bomb's status is `TF_FLAGINFO_HOME`, then it's not in play. In
                      all official maps bots basically spawn on top of it, so it ends
                      up always having the `TF_FLAGINFO_DROPPED` flag, but custom maps
                      may implement some logic where the bomb is is not in play.
                    --------------------------------------------------------------------*/
                    if ( GetEntProp( iBomb, Prop_Send, "m_nFlagStatus" ) == TF_FLAGINFO_HOME ||
                         view_as< TFTeam >( GetEntProp( iBomb, Prop_Send, "m_iTeamNum" ) ) != TF_TEAM_PVE_INVADERS )
                    {
                        continue;
                    }

                    int moveparent = GetEntPropEnt( iBomb, Prop_Send, "moveparent" );
                    if ( 0 < moveparent <= MaxClients )
                    {
                        LogServer( "Bomb is already picked up by %N. Telling %N to escort.", moveparent, iClient );

                        TF2_ShowFollowingAnnotationToClient(
                            iClient,
                            moveparent,
                            "Escort the bomb carrier!",
                            _,
                            "coach/coach_defend_here.wav",
                            6.0
                        );
                    }
                    else
                    {
                        LogServer( "Bomb is on the group. Instructing %N to pick it up.", iClient );

                        TF2_ShowFollowingAnnotationToClient(
                            iClient,
                            iBomb,
                            "Pick up the bomb!",
                            _,
                            "coach/coach_go_here.wav",
                            6.0
                        );
                    }
                }
            }
        }
    }

    g_flNextInstructionTime[ iClient ] = GetGameTime() + 30.0; // TODO: make CVar for this
}

public void Event_FlagEvent( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient    = hEvent.GetInt( "player" );
    int iEventType = hEvent.GetInt( "eventtype" );

    if ( !( 0 < iClient <= MaxClients ) || !IsClientInGame( iClient ) || iEventType == TF_FLAGEVENT_DEFENDED )
    {
        return;
    }

    if ( iEventType == TF_FLAGEVENT_PICKEDUP )
    {
        if ( !IsFakeClient( iClient ) )
        {
            if ( TF2_IsGiant( iClient ) )   // Giants have max flag level and can't receive buffs
            {
                g_iFlagCarrierUpgradeLevel[ iClient ] = 4;
                g_flNextBombUpgradeTime[ iClient ]    = GetGameTime();
            }
            else if ( g_iFlagCarrierUpgradeLevel[ iClient ] == 0 )  // Start upgrading from the beginning
            {
                g_flNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" ).FloatValue;
            }
            else if ( !TF2_IsGiant( iClient ) ) // Add existing buffs
            {
                if ( g_iFlagCarrierUpgradeLevel[ iClient ] >= 1 )
                {
                    TF2_AddCondition( iClient, TFCond_DefenseBuffNoCritBlock );
                }
                if ( g_iFlagCarrierUpgradeLevel[ iClient ] == 3 )
                {
                    TF2_AddCondition( iClient, TFCond_CritOnWin );
                }
            }

            RequestFrame( UpdateBombHud, GetClientUserId( iClient ) );
        }
    }
    else
    {
        if ( !IsFakeClient( iClient ) )
        {
            TF2_RemoveCondition( iClient, TFCond_DefenseBuffNoCritBlock );
            TF2_RemoveCondition( iClient, TFCond_CritOnWin );

            Address pHealthRegen = TF2Attrib_GetByName( iClient, "health regen" );
            if ( pHealthRegen != Address_Null )
            {
                float flRegen = TF2Attrib_GetValue( pHealthRegen );
                if ( flRegen > 45.0 )
                {
                    TF2Attrib_SetValue( pHealthRegen, flRegen - 45.0 );
                    TF2Attrib_ClearCache( iClient );
                }
                else
                {
                    TF2Attrib_RemoveByName( iClient, "health regen" );
                }
            }
        }

        g_iFlagCarrierUpgradeLevel[ iClient ] = 0;
        g_flNextBombUpgradeTime[ iClient ]    = GetGameTime();
    }
}

stock float[] TF2_GetBombHatchPosition()
{
    float vecOrigin[ 3 ];

    int iHole = -1;
    if ( ( iHole = FindEntityByClassname( iHole, "func_capturezone" ) ) != -1 )
    {
        vecOrigin = WorldSpaceCenter( iHole );
    }

    return vecOrigin;
}

public void UpdateBombHud( int iUserId )
{
    int iClient = GetClientOfUserId( iUserId );
    if ( iClient <= 0 )
    {
        return;
    }

    int iResource = FindEntityByClassname( -1, "tf_objective_resource" );
    SetEntProp( iResource, Prop_Send, "m_nFlagCarrierUpgradeLevel", g_iFlagCarrierUpgradeLevel[ iClient ] );

    bool bInSpawn = TF2_IsPlayerInCondition( iClient, TFCond_UberchargedHidden ) && TF2_IsPlayerInCondition( iClient, TFCond_ImmuneToPushback );
    SetEntPropFloat( iResource, Prop_Send, "m_flMvMBaseBombUpgradeTime", bInSpawn ? -1.0 : GetGameTime() );
    SetEntPropFloat( iResource, Prop_Send, "m_flMvMNextBombUpgradeTime", bInSpawn ? -1.0 : g_flNextBombUpgradeTime[ iClient ] );
}

public void Event_ResetBots( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    for ( int iClient = 1; iClient <= MaxClients; iClient++ )
    {
        if (
            !IsClientInGame( iClient ) ||
            IsFakeClient( iClient )    ||
            !g_bControllingBot[ iClient ]
            )
        {
            continue;
        }

        ForcePlayerSuicide( iClient );
    }
}

public void Event_PlayerSpawn( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );

    if ( !( 0 < iClient <= MaxClients ) || !IsClientInGame( iClient ) )
    {
        return;
    }

    g_flSpawnTime[ iClient ] = GetGameTime();

    if ( !IsFakeClient( iClient ) )
    {
        if ( g_bSkipInventory[ iClient ] )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

            g_bSkipInventory[ iClient ] = false;
        }
    }

    bool bTeleportToHint = IsFakeClient( iClient )
                               ? HasAttribute( iClient, TELEPORT_TO_HINT )
                               : HasAttribute( GetClientOfUserId( g_iPlayersBot[ iClient ] ), TELEPORT_TO_HINT );
    if ( TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS && TF2_GetPlayerClass( iClient ) != TFClass_Spy && bTeleportToHint )
    {
        int iTeleporter = TF2_FindTeleNearestToBombHole();
        if ( !IsValidEntity( iTeleporter ) )
        {
            return;
        }

        float vecOrigin[ 3 ];
        GetEntPropVector( iTeleporter, Prop_Send, "m_vecOrigin", vecOrigin );
        vecOrigin[ 2 ] += 15.0;

        TF2_RemoveCondition( iClient, TFCond_UberchargedHidden );

        float flUberTime = FindConVar( "tf_mvm_engineer_teleporter_uber_duration" ).FloatValue;
        TF2_AddCondition( iClient, TFCond_Ubercharged, flUberTime );
        TF2_AddCondition( iClient, TFCond_UberchargeFading, flUberTime );

        int iBuilder = TF2_GetObjectBuilder( iTeleporter );
        if ( 0 < iBuilder <= MaxClients && IsClientInGame( iBuilder ) && !IsFakeClient( iBuilder ) )
        {
            TeleportEntity( iClient, vecOrigin, NULL_VECTOR, NULL_VECTOR );

            // Don't spam sounds
            static float flLastTeleSoundTime = 0.0;
            float        flGameTime          = GetGameTime();
            float        flTimeSinceSpawn    = flGameTime - flLastTeleSoundTime;
            if ( flTimeSinceSpawn >= 1.0 )
            {
                EmitGameSoundToAll( "MVM.Robot_Teleporter_Deliver", iTeleporter );
            }
            flLastTeleSoundTime = flGameTime;
        }
    }
}

public Action Event_PlayerDeath( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    Action Result = Plugin_Continue;

    int iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );

    g_bIsControlled[ iClient ] = false;
    g_iController[ iClient ]   = -1;

    if ( IsFakeClient( iClient ) && g_bIsControlled[ iClient ] )
    {
        bDontBroadcast  = true;
        g_bBlockRagdoll = true;

        Result = Plugin_Changed;
    }

    SetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar", false );
    TF2_StopSounds( iClient );

    if ( !IsFakeClient( iClient ) && g_bControllingBot[ iClient ] )
    {
        int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );

        if ( iBot != 0 && IsFakeClient( iBot ) )
        {
            if ( g_bIsSentryBuster[ iClient ] )
            {
                TF2_DetonateBuster( iClient );
                TF2_ClearBot( iClient, false );
                TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
            }
            else
            {
                int iAttacker = GetClientOfUserId( hEvent.GetInt( "attacker" ) );
                TF2_KillBot( iClient, ( iAttacker != 0 && TF2_GetPlayerClass( iAttacker ) == TFClass_Sniper ) ? iAttacker : -1 );
            }
        }
    }

    g_bIsControlled[ iClient ] = false;
    g_iController[ iClient ]   = -1;

    return Result;
}

public Action Event_PlayerTeam( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int    iClient  = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    TFTeam eTeam    = view_as< TFTeam >( hEvent.GetInt( "team" ) );
    TFTeam eOldTeam = view_as< TFTeam >( hEvent.GetInt( "oldteam" ) );

    if ( eTeam == TFTeam_Spectator )
    {
        if( g_bControllingBot[ iClient ] )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
            TF2_RespawnPlayer( iClient );   //No gibs/ragdoll

            g_flCooldownEndTime[ iClient ] = GetGameTime() + 10.0;
        }
    }

    // Don't show joining spectator from blue team or joining blue team
    if ( !IsFakeClient( iClient ) )
    {
        SetEntProp( iClient, Prop_Data, "m_bPredictWeapons", true );

        if ( eOldTeam == TF_TEAM_PVE_INVADERS || eTeam == TF_TEAM_PVE_INVADERS )
        {
            hEvent.SetInt( "silent", 1 );

            return Plugin_Changed;
        }
    }

    return Plugin_Continue;
}

public Action Event_BuildObject( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );

    if ( !IsFakeClient( iClient ) && g_bControllingBot[ iClient ] && TF2_GetPlayerClass( iClient ) == TFClass_Engineer )
    {
        TFObjectType eObjectType = view_as< TFObjectType >( hEvent.GetInt( "object" ) );
        int iEnt = hEvent.GetInt( "index" );

        if ( eObjectType == TFObject_Teleporter )
        {
            SetEntProp( iEnt, Prop_Send, "m_iUpgradeMetalRequired", -5000 );

            int iMaxHealth = TF2Util_GetEntityMaxHealth( iEnt ) * FindConVar( "tf_bot_engineer_building_health_multiplier" ).IntValue;
            SetEntProp( iEnt, Prop_Data, "m_iMaxHealth", iMaxHealth );
            SetVariantInt( iMaxHealth );
            AcceptEntityInput( iEnt, "SetHealth" );

            SDKHook( iEnt, SDKHook_GetMaxHealth, OnObjectThink );
        }
        else
        {
            DispatchKeyValue( iEnt, "defaultupgrade", "2" );
        }
    }

    if ( IsClientInGame( iClient ) && TF2_GetPlayerClass( iClient ) == TFClass_Engineer && TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_DEFENDERS )
    {
        TFObjectType eObjectType = view_as< TFObjectType >( hEvent.GetInt( "object" ) );
        if ( eObjectType == TFObject_Sentry )
        {
            int iEnt = hEvent.GetInt( "index" );
            RequestFrame( Frame_SentryVision_Create, EntIndexToEntRef( iEnt ) );
        }
    }

    return Plugin_Continue;
}

public void OnObjectThink( int iEnt )
{
    TFObjectType eObjectType = TF2_GetObjectType( iEnt );

    if ( GetEntPropFloat( iEnt, Prop_Send, "m_flPercentageConstructed" ) == 1.0 )
    {
        if ( eObjectType == TFObject_Teleporter )
        {
            AddParticle( iEnt, "teleporter_mvm_bot_persist" );
            SDKUnhook( iEnt, SDKHook_GetMaxHealth, OnObjectThink );
        }
    }
}

public Action Listener_Build( int iClient, char[] szCommand, int argc )
{
    // Must be alive, in the game, and controlling a bot
    if ( !IsClientInGame( iClient ) || !g_bControllingBot[ iClient ] || !IsPlayerAlive( iClient ) )
    {
        return Plugin_Continue;
    }

    // Must be on invading team
    if ( TF2_GetClientTeam( iClient ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Continue;
    }

    // Must be an engineer
    if ( TF2_GetPlayerClass( iClient ) != TFClass_Engineer )
    {
        return Plugin_Continue;
    }

    char szArg1[ 8 ], szArg2[ 8 ];
    GetCmdArg( 1, szArg1, sizeof( szArg1 ) );
    GetCmdArg( 2, szArg2, sizeof( szArg2 ) );

    TFObjectType eObjectType = view_as< TFObjectType >( StringToInt( szArg1 ) );
    TFObjectMode eObjectMode = view_as< TFObjectMode >( StringToInt( szArg2 ) );

    // Don't allow building more than 1 of each object
    if ( TF2_GetObjectCount( iClient, eObjectType ) >= 1 )
    {
        return Plugin_Handled;
    }

    // Don't allow building teleporter entrances
    if ( eObjectType == TFObject_Teleporter && eObjectMode == TFObjectMode_Entrance )
    {
        return Plugin_Handled;
    }

    // Don't allow building any teleporters at all
    // if the engineer doesn't have a TeleportWhere location
    if ( eObjectType == TFObject_Teleporter && !IsAllowedToBuildTeleporter( iClient ) )
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

stock bool IsAllowedToBuildTeleporter( int iClient )
{
    int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
    if ( iBot <= 0 )
    {
        return false;
    }

    return view_as< Address >( GetEntData( iBot, g_teleportWhereName_Offset ) ) != Address_Null &&
           FindEntityByClassname( MAXPLAYERS + 1, "bot_hint_teleporter_exit" ) != -1;
}

int g_iLastHealer = -1;

public MRESReturn CTFBotMedicHeal_SelectPatient( Handle hReturn, Handle hParams )
{
    g_iLastHealer = !DHookIsNullParam( hParams, 1 ) ? DHookGetParam( hParams, 1 ) : -1;

    return MRES_Ignored;
}

public MRESReturn CTFBotMedicHeal_SelectPatient_Post( Handle hReturn, Handle hParams )
{
    int iPatient = DHookGetReturn( hReturn );

    if ( g_iLastHealer != -1 )
    {
        if ( IsInASquad( g_iLastHealer ) )
        {
            int iLeader = SDKCall( g_hfnGetLeader, GetSquad( g_iLastHealer ) );
            if ( 0 < iLeader <= MaxClients && IsClientInGame( iLeader ) )
            {
                iPatient = iLeader;
            }

            int iLeader2 = TF2_GetBotSquadLeader( g_iLastHealer );
            if ( 0 < iLeader2 <= MaxClients && IsClientInGame( iLeader2 ) )
            {
                iPatient = iLeader2;
            }
        }
    }


    // Scuffed way to fix error
    if ( iPatient == -1 )
    {
        return MRES_Ignored;
    }

    DHookSetReturn( hReturn, iPatient );
    return MRES_Supercede;
}

int g_iLastMedigun       = -1;
int g_iLastMedigunTarget = -1;

public MRESReturn CWeaponMedigun_IsAllowedToHealTarget( int iThis, Handle hReturn, Handle hParams )
{
    g_iLastMedigun       = iThis;
    g_iLastMedigunTarget = !DHookIsNullParam( hParams, 1 ) ? DHookGetParam( hParams, 1 ) : -1;

    return MRES_Ignored;
}

public MRESReturn CWeaponMedigun_IsAllowedToHealTarget_Post( int iThis, Handle hReturn, Handle hParams )
{
    // Save the original result
    bool bResult = DHookGetReturn( hReturn );

    int iOwner = TF2_GetEntityOwner( g_iLastMedigun );

    // Controlled bots aren't allowed to heal
    if ( IsFakeClient( iOwner ) && g_bIsControlled[ iOwner ] )
    {
        DHookSetReturn( hReturn, false );
        return MRES_Supercede;
    }

    if ( !IsFakeClient( iOwner ) && g_bControllingBot[ iOwner ] )
    {
        int iBot = GetClientOfUserId( g_iPlayersBot[ iOwner ] );
        if ( 0 < iBot <= MaxClients && IsPlayerAlive( iBot ) )
        {
            int iLeader = TF2_GetBotSquadLeader( iBot );

            // If the player is controlling the squad leader then we don't need to restrict their heal target.
            if ( 0 < iLeader <= MaxClients && IsClientInGame( iLeader ) && IsPlayerAlive( iLeader ) && iLeader != iBot)
            {
                bResult = ( g_iLastMedigunTarget == iLeader );
            }
        }
    }

    // PrintToServer("CWeaponMedigun_IsAllowedToHealTarget_Post %i %i", g_iLastMedigunTarget, bOriginalResult);

    DHookSetReturn( hReturn, bResult );
    return MRES_Supercede;
}

stock int TF2_GetObjectCount( int iClient, TFObjectType eObjectType )
{
    int iObject = -1, iCount = 0;
    while ( ( iObject = FindEntityByClassname( iObject, "obj_*" ) ) != -1 )
    {
        TFObjectType iObjType = TF2_GetObjectType( iObject );
        if ( TF2_GetObjectBuilder( iObject  ) == iClient && iObjType == eObjectType )
        {
            iCount++;
        }
    }

    return iCount;
}

public Action Listener_Block( int iClient, char[] szCommand, int argc )
{
    if ( IsClientInGame( iClient ) && TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS )
    {
        if ( !g_bIsSentryBuster[ iClient ] )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
            TF2_RespawnPlayer( iClient );   // No gibs/ragdoll

            g_flCooldownEndTime[ iClient ] = GetGameTime() + 10.0;
        }
        else if ( g_bIsSentryBuster[ iClient ] && GetEntPropEnt( iClient, Prop_Data, "m_hGroundEntity" ) != -1 )
        {
            TF2_RestoreBot( iClient );
            TF2_RespawnPlayer( iClient );   //No gibs/ragdoll
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

            g_flCooldownEndTime[ iClient ] = GetGameTime() + 10.0;
        }
    }

    return Plugin_Continue;
}

public Action Listener_Voice( int iClient, char[] szCommand, int argc )
{
    if ( IsClientInGame( iClient ) && TF2_GetClientTeam( iClient ) == TFTeam_Spectator && TF2_ObservedIsValidClient( iClient ) && !g_bControllingBot[ iClient ] )
    {
        char szArgs[ 4 ];
        GetCmdArgString( szArgs, sizeof( szArgs ) );

        if ( StrEqual( szArgs, "0 0" ) )
        {
            if ( g_flCooldownEndTime[ iClient ] <= GetGameTime() )
            {
                int iObserverTarget = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );
                TF2_MirrorRobot( iObserverTarget, iClient );
                PrintColoredChatAll( COLOR_GRAY ... "%N" ... COLOR_DEFAULT ... " is now playing as " ... COLOR_BLUE ... "%N", iClient, iObserverTarget );
            }
            else
            {
                float flCooldown = g_flCooldownEndTime[ iClient ] - GetGameTime();
                PrintColoredChat(iClient, COLOR_RED ... "Cannot play as a bot for %.0f more seconds", flCooldown);
            }
        }
    }

    return Plugin_Continue;
}

public Action Hook_TeleporterTransmit( int iEntity, int iOther )
{
    // Bots don't go after teleporters to destroy them so neither should player bots
    if ( 0 < iOther <= MaxClients && IsClientInGame( iOther ) && !IsFakeClient( iOther ) )
    {
        if ( view_as< TFTeam >( GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ) == TF_TEAM_PVE_DEFENDERS &&
             TF2_GetClientTeam( iOther ) == TF_TEAM_PVE_INVADERS )
        {
            return Plugin_Handled;  // Don't transmit
        }
    }

    return Plugin_Continue; //Transmit
}

public Action Hook_SpyTransmit( int iEntity, int iOther )
{
    // Bots don't know where players are when they are disguised so neither should player bots
    if ( !( 0 < iOther <= MaxClients ) || iEntity == iOther )
    {
        return Plugin_Continue;
    }

    if ( !IsClientInGame( iOther ) )
    {
        return Plugin_Continue;
    }

    // Ignore bots
    if ( IsFakeClient( iOther ) )
    {
        return Plugin_Continue;
    }

    // Ignore everything but spies
    if ( TF2_GetPlayerClass( iEntity ) != TFClass_Spy )
    {
        return Plugin_Continue;
    }

    // Always transmit invader spies
    if ( TF2_GetClientTeam( iOther ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Continue;
    }

    if ( !ShouldSpyTransmit( iEntity ) )
    {
        return Plugin_Handled;  // Don't transmit
    }

    return Plugin_Continue; // Transmit
}

stock bool ShouldSpyTransmit( int iClient )
{
    // Players who are burning/jarated/bleeding, or who are cloaked and bump into something, are not ignored
    if (
         TF2_IsPlayerInCondition( iClient, TFCond_CloakFlicker ) ||
         TF2_IsPlayerInCondition( iClient, TFCond_Bleeding )     ||
         TF2_IsPlayerInCondition( iClient, TFCond_Jarated )      ||
         TF2_IsPlayerInCondition( iClient, TFCond_Milked )       ||
         TF2_IsPlayerInCondition( iClient, TFCond_OnFire )       ||
         TF2_IsPlayerInCondition( iClient, TFCond_Gas )
        )
    {
        return true;
    }

    // Spies are only ignored when more than 75% cloaked
    if ( IsStealthed( iClient ) )
    {
        return ( GetPercentInvisible( iClient ) <= 0.75 );
    }

    // Spies who are not fully disguised are not ignored
    if (
        !TF2_IsPlayerInCondition( iClient, TFCond_Disguised ) ||
        TF2_IsPlayerInCondition( iClient, TFCond_Disguising )
        )
    {
        return true;
    }

    return false;
}

stock bool IsStealthed( int iClient )
{
#if defined( WIN32 )
    return TF2_IsPlayerInCondition( iClient, TFCond_Cloaked )   ||
           TF2_IsPlayerInCondition( iClient, TFCond_Stealthed ) ||
           TF2_IsPlayerInCondition( iClient, TFCond_StealthedUserBuffFade );
#else
    return SDKCall( g_hfnIsStealthed, iClient );
#endif
}

stock float GetPercentInvisible( int iClient )
{
#if defined( WIN32 )
    return GetEntDataFloat( iClient, g_flInvisibility_Offset );
#else
    return SDKCall( g_hfnGetPercentInvisible, iClient );
#endif
}

stock void TF2_RestoreBot( int iClient )
{
    int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
    if ( iBot != 0 && IsFakeClient( iBot ) )
    {
        float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
        GetClientAbsOrigin( iClient, vecOrigin );
        GetClientEyeAngles( iClient, angEyeAngles );
        GetEntPropVector( iClient, Prop_Data, "m_vecVelocity", vecVelocity );

        if ( TF2_HasBomb( iClient ) )
        {
            int iBomb = TF2_DropBomb( iClient );
            if ( IsValidEntity( iBomb ) )
            {
                TeleportEntity( iBomb, vecOrigin );
            }
        }

        if ( TF2_GetPlayerClass( iBot ) == TFClass_Engineer )
        {
            TF2_TakeOverBuildings( iClient, iBot );
        }

        if ( g_bIsSentryBuster[ iClient ] )
        {
            TF2_DetonateBuster( iClient );
        }

        // Copy medigun data
        if ( TF2_GetPlayerClass( iBot ) == TFClass_Medic )
        {
            int iPlayerMedigun = GetPlayerWeaponSlot( iClient, view_as< int >( TFWeaponSlot_Secondary ) );
            int iBotMedigun    = GetPlayerWeaponSlot( iBot, view_as< int >( TFWeaponSlot_Secondary ) );
            if (
                IsValidEntity( iPlayerMedigun ) && IsValidEntity( iBotMedigun ) &&
                EntityClassEquals( iPlayerMedigun, "tf_weapon_medigun" )        &&
                EntityClassEquals( iBotMedigun, "tf_weapon_medigun" )
                )
            {
                CopyEntPropFloat( iPlayerMedigun, iBotMedigun, Prop_Send, "m_flChargeLevel" );
                CopyEntPropEnt( iPlayerMedigun, iBotMedigun, Prop_Send, "m_hHealingTarget" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_nChargeResistType" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bAttacking" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bHealing" );
                CopyEntProp( iPlayerMedigun, iBotMedigun, Prop_Send, "m_bChargeRelease" );
            }
        }

        TF2_MirrorConditions( iClient, iBot );

        TeleportEntity( iBot, vecOrigin, angEyeAngles, vecVelocity );
        SetEntityMoveType( iBot, MOVETYPE_WALK );

        OnClientPutInServer( iBot );

        g_bBlockRagdoll       = true;
        g_flSpawnTime[ iBot ] = GetGameTime();
    }

    TF2_ClearBot( iClient, false );
}

void TF2_MirrorConditions( int iTarget, int iRecipient )
{
    // Mirror conditions
    TFCond eLastCond = TF2Util_GetLastCondition();
    for ( TFCond eCond = TFCond_Slowed; eCond <= eLastCond; eCond++ )
    {
        switch ( eCond )
        {
            case TFCond_Ubercharged, TFCond_CloakFlicker, TFCond_UberchargedHidden, TFCond_ImmuneToPushback:
            {
                continue;
            }
        }

        if ( !TF2_IsPlayerInCondition( iTarget, eCond ) )
        {
            continue;
        }

        int   iProvider      = TF2Util_GetPlayerConditionProvider( iTarget, eCond );
        float flCondDuration = TF2Util_GetPlayerConditionDuration( iTarget, eCond );

        if ( iProvider != INVALID_ENT_REFERENCE && flCondDuration != 0.0 )
        {
            TF2_AddCondition( iRecipient, eCond, flCondDuration, iProvider );
        }
    }
}

stock void TF2_ClearBot( int iClient, bool bKillBot )
{
    SetEntityFlags( iClient, GetEntityFlags( iClient ) & ~FL_FAKECLIENT );
    TF2_StopSounds( iClient );
    if ( TF2_HasBomb( iClient ) )
    {
        TF2_DropBomb( iClient );
    }

    if ( bKillBot )
    {
        TF2_KillBot( iClient );
    }

    SetEntProp( iClient, Prop_Send, "m_bIsABot", false );
    SetEntProp( iClient, Prop_Send, "m_bIsMiniBoss", false );

    SetVariantString( "" );
    AcceptEntityInput( iClient, "SetCustomModel" );

    TF2Attrib_RemoveAll( iClient );
    TF2Attrib_ClearCache( iClient );

    OnClientPutInServer( iClient );
}

stock void TF2_KillBot( int iClient, int iAttacker = -1 )
{
    int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
    if ( iBot == 0 || !IsFakeClient( iBot ) )
    {
        return;
    }

    if ( iAttacker == -1 )
    {
        iAttacker = iBot;
    }

    SetEntityMoveType( iBot, MOVETYPE_WALK );
    TF2_RemoveAllConditions( iBot );

    int iWeapon = iBot;

    if ( 0 < iAttacker <= MaxClients && iAttacker != iBot )
    {
        // If the bot was controlled, and killed by a red sniper, this will fix the money not being auto-distribued
        iWeapon = TF2_GetClientActiveWeapon( iAttacker );

        if ( iWeapon != -1 )
        {
            iWeapon = iAttacker;
        }
    }

    SDKHooks_TakeDamage( iBot, iWeapon, iAttacker, 99999999.0, _, iWeapon );

    SetEntProp( iBot, Prop_Send, "m_bUseBossHealthBar", false );
    SetEntProp( iBot, Prop_Send, "m_bIsMiniBoss", false );

    g_bIsControlled[ iBot ] = false;
    g_iController[ iBot ]   = -1;

    OnClientPutInServer( iBot );
}

stock void TF2_MirrorRobot( int iRobot, int iClient )
{
    float vecOrigin[ 3 ], angEyeAngles[ 3 ];
    GetClientAbsOrigin( iRobot, vecOrigin );
    GetClientEyeAngles( iRobot, angEyeAngles );
    angEyeAngles[ 2 ] = 0.0;

    // Set up player
    SetEntityFlags( iClient, GetEntityFlags( iClient ) | FL_FAKECLIENT );
    TF2_ChangeClientTeam( iClient, TF2_GetClientTeam( iRobot ) );
    SetEntityFlags( iClient, GetEntityFlags( iClient ) & ~FL_FAKECLIENT );
    TF2_SetPlayerClass( iClient, TF2_GetPlayerClass( iRobot ) );
    TF2_RespawnPlayer( iClient );
    TF2_RegeneratePlayer( iClient );
    TF2_RemoveAllWearables( iClient );
    TF2Attrib_RemoveAll( iClient );
    TF2Attrib_ClearCache( iClient );

    // New hot technology
    g_flControlEndTime[ iClient ]      = GetGameTime() + 35.0;
    g_flNextInstructionTime[ iClient ] = GetGameTime() + 3.0;

    // Set health
    CopyEntProp( iRobot, iClient, Prop_Send, "m_iHealth" );

    // Set model
    char szModelName[ PLATFORM_MAX_PATH ];
    GetEntPropString( iRobot, Prop_Data, "m_ModelName", szModelName, PLATFORM_MAX_PATH );
    SetVariantString( szModelName );
    AcceptEntityInput( iClient, "SetCustomModel" );
    SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", true );

    // Set ModelScale
    char szModelScale[ 8 ];
    FloatToString( GetEntPropFloat( iRobot, Prop_Send, "m_flModelScale" ), szModelScale, sizeof( szModelScale ) );
    SetVariantString( szModelScale );
    AcceptEntityInput( iClient, "SetModelScale" );

    // Is target sentry buster?
    if ( StrContains( szModelName, "bot_sentry_buster.mdl" ) != -1 )
    {
        SDKCall( g_hfnSetMission, iRobot, NO_MISSION, 0 );

        g_bIsSentryBuster[ iClient ] = true;

        TF2Attrib_SetByName( iClient, "cannot pick up intelligence", 1.0 );

        // A little delay
        SetEntPropFloat( iClient, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 1.25 );
    }

    // Get & Set some props
    CopyEntPropFloat( iRobot, iClient, Prop_Send, "m_flRageMeter" );
    CopyEntProp( iRobot, iClient, Prop_Send, "m_nNumHealers" );
    CopyEntProp( iRobot, iClient, Prop_Send, "m_bIsABot" ); // Isn't this always true?
    CopyEntProp( iRobot, iClient, Prop_Send, "m_bIsMiniBoss" );
    // This can be either `BLOOD_COLOR_MECH` or `BLOOD_COLOR_RED` depending on
    // whether Halloween mode is on or off, so we can't hardcode it.
    CopyEntProp( iRobot, iClient, Prop_Data, "m_bloodColor" );

    // Set gatebot on player if target is gatebot
    if ( TF2_HasTag( iRobot, "bot_gatebot" ) )
    {
        TF2Attrib_SetByName( iClient, "cannot pick up intelligence", 1.0 );
    }

    // Engineers cant carry buildings
    if ( TF2_GetPlayerClass( iRobot ) == TFClass_Engineer )
    {
        TF2_TakeOverBuildings( iRobot, iClient );
        TF2Attrib_SetByName( iClient, "cannot pick up buildings", 1.0 );
    }

    /*--------------------------------------------------------------------
      Only checking for the `TFCond_Zoomed` condition should not cause
      a crash unless some other plugin applies this condition on a bot
      that's not a Sniper for some reason.
    --------------------------------------------------------------------*/
    if ( TF2_IsPlayerInCondition( iRobot, TFCond_Zoomed ) )
    {
        // Zoom out of the sniper rifle so the lazer disappears and doesn't cause problems
        SDKCall( g_hfnZoomOut, TF2_GetClientActiveWeapon( iRobot ) );
    }

    // Start the engines
    if ( TF2_IsGiant( iRobot ) )
    {
        if ( g_bIsSentryBuster[ iClient ] )
        {
            EmitSoundToAll( "MVM.SentryBusterLoop", iClient );
        }
        else
        {
            switch ( TF2_GetPlayerClass( iRobot ) )
            {
                case TFClass_Scout:   EmitSoundToAll( "MVM.GiantScoutLoop", iClient );
                case TFClass_Soldier: EmitSoundToAll( "MVM.GiantSoldierLoop", iClient );
                case TFClass_DemoMan: EmitSoundToAll( "MVM.GiantDemomanLoop", iClient );
                case TFClass_Heavy:   EmitSoundToAll( "MVM.GiantHeavyLoop", iClient );
                case TFClass_Pyro:    EmitSoundToAll( "MVM.GiantPyroLoop", iClient );
            }
        }
    }

    TF2_RemoveAllConditions( iClient );

    // Fix some bugs...
    TF2_RemoveCondition( iClient, TFCond_Zoomed );
    TF2_RemoveCondition( iClient, TFCond_Slowed );

    // Mirror conditions
    TF2_MirrorConditions( iRobot, iClient );

    if ( IsInASquad( iRobot ) )
    {
        Address pTargetSquad = GetSquad( iRobot );
        int     iLeader      = SDKCall( g_hfnGetLeader, pTargetSquad );

        // Everyone but medics leave the targets squad
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( !IsClientInGame( i ) || !IsFakeClient( i ) || i == iRobot || i == iLeader )
            {
                continue;
            }

            if ( TF2_GetPlayerClass( i ) != TFClass_Medic )
            {
                if ( GetSquad( i ) == pTargetSquad )
                {
                    SDKCall( g_hfnLeaveSquad, i );
                //    PrintToChatAll("Bye %N", i);
                }
            }
        }
    }

    if ( HasAttribute( iRobot, ALWAYS_FIRE_WEAPON ) )
    {
        // Fix client visuals
        SetEntProp( iClient, Prop_Data, "m_bPredictWeapons", false );
    }
    if ( HasAttribute( iRobot, IGNORE_FLAG ) )
    {
        TF2Attrib_SetByName( iClient, "cannot pick up intelligence", 1.0 );
    }
    if ( HasAttribute( iRobot, ALWAYS_CRIT ) )
    {
        TF2_AddCondition( iClient, TFCond_CritCanteen );
    }
    if ( HasAttribute( iRobot, BULLET_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_BulletImmune );
    }
    if ( HasAttribute( iRobot, BLAST_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_BlastImmune );
    }
    if ( HasAttribute( iRobot, FIRE_IMMUNE ) )
    {
        TF2_AddCondition( iClient, TFCond_FireImmune );
    }

    // FIXME: Is this needed?
    // SetEntData( iClient, g_iOffsetMissionBot,     1, _, true );  // Makes player death not decrement wave bot count
    // SetEntData( iClient, g_iOffsetSupportLimited, 0, _, true );  // Makes player death not decrement wave bot count

    // Teleport player to bots position
    float vecVelocity[ 3 ];
    GetEntPropVector( iRobot, Prop_Data, "m_vecVelocity", vecVelocity );

    SetEntityMoveType( iRobot, MOVETYPE_NONE );
    TeleportEntity( iClient, vecOrigin, angEyeAngles, vecVelocity );
    TeleportEntity( iRobot, { 0.0, 0.0, 9999.0 }, NULL_VECTOR, NULL_VECTOR );

    g_iPlayersBot[ iClient ]     = GetClientUserId( iRobot );
    g_iController[ iRobot ]      = GetClientUserId( iClient );
    g_bControllingBot[ iClient ] = true;
    g_bIsControlled[ iRobot ]    = true;
    g_bSkipInventory[ iClient ]  = true;

    // Delay a frame or two to replace the players weapons.
    CreateTimer( 0.1, Timer_ReplaceWeapons, GetClientUserId( iClient ), TIMER_FLAG_NO_MAPCHANGE );
}

public Action Timer_ReplaceWeapons( Handle hTimer, int iUserId )
{
    // Check to see if the player is valid and is still controlling bot
    int iPlayer = GetClientOfUserId( iUserId );
    if ( !( 0 < iPlayer <= MaxClients ) || !IsClientInGame( iPlayer ) )
    {
        return Plugin_Handled;
    }

    LogServer( "Trying to replace weapons for %N.", iPlayer );

    if ( !g_bControllingBot[ iPlayer ] )
    {
        return Plugin_Handled;
    }

    if ( !IsPlayerAlive( iPlayer ) )
    {
        return Plugin_Handled;
    }

    int iBot = GetClientOfUserId( g_iPlayersBot[ iPlayer ] );
    if ( iBot <= 0 )
    {
        LogServer( "Player has no bot! Cannot copy weapons..." );
        return Plugin_Handled;
    }

    if ( !IsPlayerAlive( iBot ) )
    {
        return Plugin_Handled;
    }

    TF2_MirrorItems( iBot, iPlayer );
    LogServer( "Done mirroring items from %N to %N.", iBot, iPlayer );

    if ( TF2_HasBomb( iBot ) )
    {
        LogServer( "%N has the bomb. Making him drop it...", iBot );
        int iBomb = TF2_DropBomb( iBot );
        if ( IsValidEntity( iBomb ) )
        {
            LogServer( "%N dropped the bomb. Making %N pick it up...", iBot, iPlayer );
            float vecOrigin[ 3 ];
            GetClientAbsOrigin( iPlayer, vecOrigin );
            TeleportEntity( iBomb, vecOrigin );
            LogServer( "Teleported bomb to %N's position. He should now have it.", iPlayer );

            // Copy bomb carrier upgrade level
            int iResource = FindEntityByClassname( -1, "tf_objective_resource" );
            g_iFlagCarrierUpgradeLevel[ iPlayer ] = GetEntProp( iResource, Prop_Send, "m_nFlagCarrierUpgradeLevel" );
            g_flNextBombUpgradeTime[ iPlayer ]    = GetEntPropFloat( iResource, Prop_Send, "m_flMvMNextBombUpgradeTime" );
            LogServer( "Done copying bomb carrier upgrade levels to %N...", iPlayer );
        }
        else
        {
            LogServer( "Bomb is not a valid entity..." );
        }
    }

    // Copy medigun data
    if ( TF2_GetPlayerClass( iBot ) == TFClass_Medic )
    {
        int iBotMedigun    = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Secondary );
        int iPlayerMedigun = GetPlayerWeaponSlot( iPlayer, TFWeaponSlot_Secondary );

        if (
            IsValidEntity( iBotMedigun ) && IsValidEntity( iPlayerMedigun ) &&
            EntityClassEquals( iBotMedigun, "tf_weapon_medigun" )           &&
            EntityClassEquals( iPlayerMedigun, "tf_weapon_medigun" )
            )
        {
            CopyEntPropFloat( iBotMedigun, iPlayerMedigun, Prop_Send, "m_flChargeLevel" );
            CopyEntPropEnt( iBotMedigun, iPlayerMedigun, Prop_Send, "m_hHealingTarget" );
            CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_nChargeResistType" );
            CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bAttacking" );
            CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bHealing" );
            CopyEntProp( iBotMedigun, iPlayerMedigun, Prop_Send, "m_bChargeRelease" );

            SetEntPropFloat( iBotMedigun, Prop_Send, "m_flChargeLevel", 0.0 );  // Hide the medigun effect
            SetEntPropEnt( iBotMedigun, Prop_Send, "m_hHealingTarget", -1 );    // Remove the medigun beam
            SetEntProp( iBotMedigun, Prop_Send, "m_bHealing", false );
        }
    }

    // Disguise after we have received our disguise items
    if ( TF2_GetPlayerClass( iBot ) == TFClass_Spy )
    {
        TFClassType eDisguiseClass  = TF2_GetPlayerDisguiseClass( iBot );
        int         iDisguiseTarget = GetEntProp( iBot, Prop_Send, "m_iDisguiseTargetIndex" );

        if ( eDisguiseClass != TFClass_Unknown )
        {
            if ( 0 < iDisguiseTarget <= MaxClients && IsClientInGame( iDisguiseTarget ) )
            {
                TF2_DisguisePlayer( iPlayer, TF_TEAM_PVE_DEFENDERS, eDisguiseClass, iDisguiseTarget );
            }
            else
            {
                TF2_DisguisePlayer( iPlayer, TF_TEAM_PVE_DEFENDERS, eDisguiseClass );
            }
        }
    }

    return Plugin_Handled;
}

stock bool EntityClassEquals( int iEntity, const char[] szClassname )
{
    char sz[ 64 ];
    GetEntityClassname( iEntity, sz, sizeof( sz ) );
    return StrEqual( sz, szClassname );
}

stock void TF2_MirrorItems( int iBot, int iPlayer )
{
    int     aiAttributes[ 20 ];
    float   aflAttribValues[ 20 ];
    Address pAttribute;
    int     iEntity = -1;

    // This is stupid, but it's how TF2 itself does it
    if ( HasWeaponRestriction( iBot, MELEE_ONLY ) )
    {
        iEntity = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Melee );
    }
    else if ( HasWeaponRestriction( iBot, PRIMARY_ONLY ) )
    {
        iEntity = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Primary );
    }
    else if ( HasWeaponRestriction( iBot, SECONDARY_ONLY ) )
    {
        iEntity = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Secondary );
    }

    if ( iEntity == -1 )
    {
        for ( int iSlot = 0; iSlot <= TFWeaponSlot_PDA; iSlot++ )
        {
            iEntity = GetPlayerWeaponSlot( iBot, iSlot );
            if ( IsValidEntity( iEntity ) )
            {
                char szClassname[ 64 ];
                GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

                int iItemDefinitionIndex = GetEntProp( iEntity, Prop_Send, "m_iItemDefinitionIndex" );

                int nAttributes = TF2Attrib_ListDefIndices( iEntity, aiAttributes );
                for ( int i = 0; i < nAttributes; i++ )
                {
                    pAttribute           = TF2Attrib_GetByDefIndex( iEntity, aiAttributes[ i ] );
                    aflAttribValues[ i ] = TF2Attrib_GetValue( pAttribute );
                }

                GiveItem(
                    iPlayer,
                    iItemDefinitionIndex,
                    szClassname,
                    sizeof( szClassname ),
                    nAttributes,
                    aiAttributes,
                    aflAttribValues,
                    TF2_GetClientActiveWeapon( iBot ) == iEntity
                );
            }
        }
    }
    else
    {
        // Mirror unrestricted weapon + utility weapons
        if ( IsValidEntity( iEntity ) )
        {
            char szClassname[ 64 ];
            GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

            int iItemDefinitionIndex = GetEntProp( iEntity, Prop_Send, "m_iItemDefinitionIndex" );

            int nAttributes = TF2Attrib_ListDefIndices( iEntity, aiAttributes );
            for ( int i = 0; i < nAttributes; i++ )
            {
                pAttribute           = TF2Attrib_GetByDefIndex( iEntity, aiAttributes[ i ] );
                aflAttribValues[ i ] = TF2Attrib_GetValue( pAttribute );
            }

            GiveItem(
                iPlayer,
                iItemDefinitionIndex,
                szClassname,
                sizeof( szClassname ),
                nAttributes,
                aiAttributes,
                aflAttribValues,
                TF2_GetClientActiveWeapon( iBot ) == iEntity
            );
        }

        // Always mirror the "utility" weapons
        for ( int iSlot = TFWeaponSlot_Grenade; iSlot <= TFWeaponSlot_PDA; iSlot++ )
        {
            iEntity = GetPlayerWeaponSlot( iBot, iSlot );

            if ( IsValidEntity( iEntity ) )
            {
                char szClassname[ 64 ];
                GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

                int iItemDefinitionIndex = GetEntProp( iEntity, Prop_Send, "m_iItemDefinitionIndex" );

                int nAttributes = TF2Attrib_ListDefIndices( iEntity, aiAttributes );
                for ( int i = 0; i < nAttributes; i++ )
                {
                    pAttribute           = TF2Attrib_GetByDefIndex( iEntity, aiAttributes[ i ] );
                    aflAttribValues[ i ] = TF2Attrib_GetValue( pAttribute );
                }

                GiveItem(
                    iPlayer,
                    iItemDefinitionIndex,
                    szClassname,
                    sizeof( szClassname ),
                    nAttributes,
                    aiAttributes,
                    aflAttribValues,
                    TF2_GetClientActiveWeapon( iBot ) == iEntity
                );
            }
        }
    }

    // Mirror wearables
    int iWearable = -1;
    while ( ( iWearable = FindEntityByClassname( iWearable, "tf_wearable*" ) ) != -1 )
    {
        if ( GetEntProp( iWearable, Prop_Send, "m_bDisguiseWearable" ) || TF2_GetEntityOwner( iWearable ) != iBot )
        {
            continue;
        }

        char szClassname[ 64 ];
        GetEntityClassname( iWearable, szClassname, sizeof( szClassname ) );

        int iItemDefinitionIndex = GetEntProp( iWearable, Prop_Send, "m_iItemDefinitionIndex" );

        int nAttirbutes = TF2Attrib_ListDefIndices( iWearable, aiAttributes );
        for ( int i = 0; i < nAttirbutes; i++ )
        {
            pAttribute           = TF2Attrib_GetByDefIndex( iWearable, aiAttributes[ i ] );
            aflAttribValues[ i ] = TF2Attrib_GetValue( pAttribute );
        }

        GiveItem(
            iPlayer,
            iItemDefinitionIndex,
            szClassname,
            sizeof( szClassname ),
            nAttirbutes,
            aiAttributes,
            aflAttribValues,
            false
        );
    }

    // Mirror player attributes
    int nAttributes = TF2Attrib_ListDefIndices( iBot, aiAttributes );
    for ( int i = 0; i < nAttributes; i++ )
    {
        pAttribute           = TF2Attrib_GetByDefIndex( iBot, aiAttributes[ i ] );
        aflAttribValues[ i ] = TF2Attrib_GetValue( pAttribute );

        TF2Attrib_SetByDefIndex( iPlayer, aiAttributes[ i ], aflAttribValues[ i ] );
    }

    BfWrite hMsg = UserMessageToBfWrite( StartMessageOne( "PlayerLoadoutUpdated", iPlayer, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS ) );
    hMsg.WriteByte( iPlayer );
    if ( hMsg )
    {
        EndMessage();
    }

    hMsg = UserMessageToBfWrite( StartMessageOne( "PlayerPickupWeapon", iPlayer, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS ) );
    if ( hMsg )
    {
        EndMessage();
    }

    // Finally
    SDKCall( g_hfnPostInventoryApplication, iPlayer );
}

stock void TF2_RemoveAllWearables( int iClient )
{
    TF2_RemoveAllWeapons( iClient );

    int iEntity = -1;
    while ( ( iEntity = FindEntityByClassname( iEntity, "tf_wearable*" ) ) != -1 )
    {
        if ( TF2_GetEntityOwner( iEntity ) == iClient )
        {
            TF2_RemoveWearable( iClient, iEntity );
        }
    }

    while ( ( iEntity = FindEntityByClassname( iEntity, "vgui_screen" ) ) != -1 )
    {
        if ( TF2_GetEntityOwner( iEntity ) == iClient )
        {
            AcceptEntityInput( iEntity, "Kill" );
        }
    }

    while ( ( iEntity = FindEntityByClassname( iEntity, "tf_powerup_bottle" ) ) != -1 )
    {
        if ( TF2_GetEntityOwner( iEntity ) == iClient )
        {
            TF2_RemoveWearable( iClient, iEntity );
        }
    }

    while ( ( iEntity = FindEntityByClassname( iEntity, "tf_weapon_spellbook" ) ) != -1 )
    {
        if ( TF2_GetEntityOwner( iEntity ) == iClient )
        {
            TF2_RemoveWearable( iClient, iEntity );
        }
    }
}

stock bool TF2_IsGiant( int iClient )
{
    return view_as< bool >( GetEntProp( iClient, Prop_Send, "m_bIsMiniBoss" ) );
}

stock bool TF2_HasBomb( int iClient )
{
    int iBomb = GetEntPropEnt( iClient, Prop_Send, "m_hItem" );
    return iBomb != INVALID_ENT_REFERENCE && GetEntPropEnt( iBomb, Prop_Send, "moveparent" ) == iClient;
}

stock int TF2_DropBomb( int iClient )
{
    int iBomb = GetEntPropEnt( iClient, Prop_Send, "m_hItem" );
    SDKCall( g_hfnDrop, iBomb, iClient, false, true, false );

    return iBomb;
}

// Gets a bots tag and does checking for real bots
stock bool TF2_HasTag( int iClient, const char[] szTag )
{
    if ( IsFakeClient( iClient ) )
    {
        return SDKCall( g_hfnHasTag, iClient, szTag );
    }
    else
    {
        int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
        if ( iBot != 0 )
        {
            return SDKCall( g_hfnHasTag, iBot, szTag );
        }
    }

    return false;
}

stock float[] WorldSpaceCenter( int iEntity )
{
    float vecOrigin[ 3 ];
    SDKCall( g_hfnWorldSpaceCenter, iEntity, vecOrigin );
    return vecOrigin;
}

public void Frame_TF2_PickupBomb( DataPack dp )
{
    dp.Reset();
    int iFlag   = EntRefToEntIndex( dp.ReadCell() );
    int iClient = GetClientOfUserId( dp.ReadCell() );

    if ( !IsPlayerAlive( iClient ) )
    {
        return;
    }

    if ( IsValidEntity( iFlag ) && GetEntPropEnt( iFlag, Prop_Send, "moveparent" ) == iClient && 0 < iClient <= MaxClients )
    {
        SetEntPropEnt( iClient, Prop_Send, "m_hItem", iFlag );
        if ( !IsFakeClient( iClient ) )
        {
            SetEntityFlags( iClient, GetEntityFlags( iClient ) | FL_FAKECLIENT );
        }
    }
}

stock void TF2_RobotsWin()
{
    int iEntity = -1;
    while ( ( iEntity = FindEntityByClassname( iEntity, "logic_relay" ) ) != -1 )
    {
        // This is a `string_t` internally
        char iName[ 32 ];
        GetEntPropString( iEntity, Prop_Data, "m_iName", iName, sizeof( iName ) );

        if ( StrEqual( iName, "boss_deploy_relay", false ) )
        {
            AcceptEntityInput( iEntity, "Trigger" );
        }
    }
}

stock void TF2_StopSounds( int iClient )
{
    EmitGameSoundToAll( "MVM.SentryBusterLoop", iClient, SND_STOP );
    EmitGameSoundToAll( "MVM.GiantHeavyLoop", iClient, SND_STOP );
    EmitGameSoundToAll( "MVM.GiantSoldierLoop", iClient, SND_STOP );
    EmitGameSoundToAll( "MVM.GiantDemomanLoop", iClient, SND_STOP );
    EmitGameSoundToAll( "MVM.GiantScoutLoop", iClient, SND_STOP );
    EmitGameSoundToAll( "MVM.GiantPyroLoop", iClient, SND_STOP );
}

stock void TF2_RemoveAllConditions( int iClient )
{
    TFCond eLastCond = TF2Util_GetLastCondition();
    for ( TFCond eCond = TFCond_Slowed; eCond <= eLastCond; eCond++ )
    {
        TF2_RemoveCondition( iClient, eCond );
    }
}

stock bool TF2_ObservedIsValidClient( int iObserver )
{
    int iObserverMode = GetEntProp( iObserver, Prop_Send, "m_iObserverMode" );

    if ( iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE )
    {
        int iObserverTarget = GetEntPropEnt(iObserver, Prop_Send, "m_hObserverTarget");
        if (
            0 < iObserverTarget <= MaxClients &&
            IsClientInGame( iObserverTarget ) &&
            IsFakeClient( iObserverTarget )   &&
            IsPlayerAlive( iObserverTarget )  &&
            !g_bIsControlled[ iObserverTarget ]
            )
        {
            if ( !TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) && !TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
            {
                if ( GetEntProp( iObserverTarget, Prop_Data, "m_takedamage" ) != 0 )
                {
                    float flSpawnedAgo = GetGameTime() - g_flSpawnTime[ iObserverTarget ];
                    if ( TF2_GetPlayerClass( iObserverTarget ) != TFClass_Spy && flSpawnedAgo >= 1.5 )  // Allow the bots some time to spawn
                    {
                        return true;
                    }
                    else if ( TF2_GetPlayerClass( iObserverTarget ) == TFClass_Spy && flSpawnedAgo >= 5.0 ) // Spies need extra time to teleport
                    {
                        return true;
                    }
                }
            }
        }
    }

    return false;
}

stock void TF2_DetonateBuster( int iClient )
{
    int iBot = GetClientOfUserId( g_iPlayersBot[ iClient ] );
    if ( iBot == 0 || !IsFakeClient( iBot ) )
    {
        return;
    }

    TF2_StopSounds( iClient );

    float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );
    GetClientEyeAngles( iClient, angEyeAngles );
    GetEntPropVector( iClient, Prop_Data, "m_vecVelocity", vecVelocity );

    SetEntityMoveType( iBot, MOVETYPE_WALK );
    TeleportEntity( iBot, vecOrigin, angEyeAngles, vecVelocity );

    SDKCall( g_hfnSetMission, iBot, MISSION_DESTROY_SENTRIES, 1 );

    SetEntProp( iBot, Prop_Send, "m_iHealth", 1 );
    SetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget", iBot );
}

stock int TF2_FindTeleNearestToBombHole()
{
    float vecHatchPos[ 3 ];
    vecHatchPos = TF2_GetBombHatchPosition();

    float flBestDistance = 9.9e32;  // No FLT_MAX, but this is large enough
    int   iBestEntity    = -1;

    int iEnt = -1;
    while ( ( iEnt = FindEntityByClassname( iEnt, "obj_teleporter" ) ) != -1 )
    {
        if (
            view_as< TFTeam >( GetEntProp( iEnt, Prop_Send, "m_iTeamNum" ) ) == TF_TEAM_PVE_INVADERS &&
            !GetEntProp( iEnt, Prop_Send, "m_bHasSapper" )                                           &&
            !GetEntProp( iEnt, Prop_Send, "m_bBuilding" )                                            &&
            !GetEntProp( iEnt, Prop_Send, "m_bPlacing" )                                             &&
            !GetEntProp( iEnt, Prop_Send, "m_bDisabled" )
        )
        {
            float vecTeleporterOrigin[ 3 ];
            GetEntPropVector( iEnt, Prop_Data, "m_vecOrigin", vecTeleporterOrigin );

            float flDistance = GetVectorDistance( vecHatchPos, vecTeleporterOrigin, true );
            if ( flDistance <= flBestDistance )
            {
                flBestDistance = flDistance;
                iBestEntity    = iEnt;
            }
        }
    }

    return iBestEntity;
}

stock int TF2_GetSquadLeader( Address pSquad )
{
    int iLeader = SDKCall( g_hfnGetLeader, pSquad );
    if ( 0 < iLeader <= MaxClients && IsFakeClient( iLeader ) && g_bIsControlled[ iLeader ] )
    {
        return GetClientOfUserId( g_iController[ iLeader ] );
    }

    return iLeader;
}

stock int TF2_GetBotSquadLeader( int iBot )
{
    if ( IsInASquad( iBot ) )
    {
        return TF2_GetSquadLeader( GetSquad( iBot ) );
    }

    return -1;
}

stock void TF2_TakeOverBuildings( int iReceiver, int iTarget )
{
    int iObject = -1;
    while ( ( iObject = FindEntityByClassname( iObject, "obj_*" ) ) != -1 )
    {
        if ( IsValidBuilding( iObject ) )
        {
            int iBuilder = TF2_GetObjectBuilder( iObject );
            if ( iBuilder == iReceiver )
            {
                DispatchKeyValue( iObject, "SolidToPlayer", "0" );
                SetBuilder( iObject, iTarget );
            }
        }
    }
}

stock void SetBuilder( int iObject, int iClient )
{
    int iBuilder = TF2_GetObjectBuilder( iObject );
    if ( 0 < iBuilder <= MaxClients && IsClientInGame( iBuilder ) )
    {
        SDKCall( g_hfnRemoveObject, iBuilder, iObject );
    }

    SetEntPropEnt( iObject, Prop_Send, "m_hBuilder", -1 );
    AcceptEntityInput( iObject, "SetBuilder", iClient );
    SetEntPropEnt( iObject, Prop_Send, "m_hBuilder", iClient );

    SetVariantString( "3" );
    AcceptEntityInput( iObject, "SetTeam" );
}

stock bool IsValidBuilding( int iBuilding )
{
    return IsValidEntity( iBuilding )                        &&
           !GetEntProp( iBuilding, Prop_Send, "m_bPlacing" ) &&
           !GetEntProp( iBuilding, Prop_Send, "m_bCarried" );
}

public void GiveItem(
    int    iClient,
    int    iItemDefinitionIndex,
    char[] szClassname,
    int    cb,
    int    nAttributes,
    int    aiAttribs[ 20 ],
    float  aflAttribValues[ 20 ],
    bool   bSetActive
    )
{
    Handle hItem;

    if ( StrEqual( szClassname, "saxxy" ) || StrEqual( szClassname, "tf_weapon_shotgun" ) )
    {
        hItem = TF2Items_CreateItem( OVERRIDE_ALL | PRESERVE_ATTRIBUTES );
    }
    else
    {
        hItem = TF2Items_CreateItem( OVERRIDE_ALL | FORCE_GENERATION | PRESERVE_ATTRIBUTES );
    }

    TF2_TranslateWeaponEntForClass( TF2_GetPlayerClass( iClient ), szClassname, cb );

    TF2Items_SetClassname( hItem, szClassname );
    TF2Items_SetItemIndex( hItem, iItemDefinitionIndex );
    TF2Items_SetLevel( hItem, 100 );

    for ( int i = 0; i < nAttributes; i++ )
    {
        TF2Items_SetAttribute( hItem, i, aiAttribs[ i ], aflAttribValues[ i ] );
    }

    TF2Items_SetNumAttributes( hItem, nAttributes );

    int iItem = TF2Items_GiveNamedItem( iClient, hItem );
    delete hItem;

    if ( !IsValidEntity( iItem ) )
    {
        LogError( "Unable to give item '%d' for %N. Skipping...", iItemDefinitionIndex, iClient );
        return;
    }

    // Why do we do this instead of a simple if-else if with the two class names?
    // Can a Spy have a TF_WEAPON_BUILDER and vice versa?
    if ( StrEqual( szClassname, "tf_weapon_builder" ) || StrEqual( szClassname, "tf_weapon_sapper" ) )
    {
        if ( TF2_GetPlayerClass( iClient ) == TFClass_Spy )
        {
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 0 );
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 1 );
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 2 );
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 0, _, 3 );

            SetEntProp( iItem, Prop_Send, "m_iObjectType", 3 );
            SetEntProp( iItem, Prop_Data, "m_iSubType", 3 );
        }
        else
        {
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 0 ); // Dispenser
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 1 ); // Teleporter
            SetEntProp( iItem, Prop_Send, "m_aBuildableObjectTypes", 1, _, 2 ); // Sentry
        }
    }

    bool bIsWeapon = StrContains( szClassname, "tf_weapon" ) != -1;
    if ( !bIsWeapon )
    {
        TF2Util_EquipPlayerWearable( iClient, iItem );
    }
    else
    {
        EquipPlayerWeapon( iClient, iItem );
    }

    if ( bSetActive && bIsWeapon )
    {
        FakeClientCommand( iClient, "use %s", szClassname );
        SetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon", iItem );
    }
}

stock void AddParticle( int iBuilding, const char[] szEffectName )
{
    float vecOrigin[ 3 ];
    GetEntPropVector( iBuilding, Prop_Send, "m_vecOrigin", vecOrigin );

    int iParticle = CreateEntityByName( "info_particle_system" );
    DispatchKeyValueVector( iParticle, "origin", vecOrigin );
    DispatchKeyValue( iParticle, "effect_name", szEffectName );
    DispatchSpawn( iParticle );

    SetVariantString( "!activator" );
    AcceptEntityInput( iParticle, "SetParent", iBuilding );
    ActivateEntity( iParticle );

    AcceptEntityInput( iParticle, "start" );
}

stock bool TF2_PlayingMannVsMachine()
{
    return view_as< bool >( GameRules_GetProp( "m_bPlayingMannVsMachine" ) );
}

stock bool HasWeaponRestriction( int iBot, WeaponRestrictionType eRestriction )
{
#if defined( WIN32 )
    return GetEntData( iBot, g_weaponRestrictionFlags_Offset ) & view_as< int >( eRestriction );
#else
    return SDKCall( g_hfnHasWeaponRestriction, iBot, view_as< int >( eRestriction ) );
#endif
}

stock bool HasAttribute( int iBot, AttributeType eAttribute )
{
#if defined( WIN32 )
    return GetEntData( iBot, g_attributeFlags_Offset ) & view_as< int >( eAttribute );
#else
    return SDKCall( g_hfnHasAttribute, iBot, view_as< int >( eAttribute ) );
#endif
}

stock Address GetSquad( int iBot )
{
    return view_as< Address >( GetEntData( iBot, g_squad_Offset ) );
}

stock bool IsInASquad( int iBot )
{
#if defined( WIN32 )
    return view_as< Address >( GetEntData( iBot, g_squad_Offset ) ) != Address_Null;
#else
    return SDKCall( g_hfnIsInASquad, iBot );
#endif
}
