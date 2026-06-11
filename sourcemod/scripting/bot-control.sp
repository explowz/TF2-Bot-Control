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
#include <vscript>
#include <SteamWorks>
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
#pragma semicolon 1

public Plugin myinfo =
{
    name        = "[TF2] MvM Bot Control",
    author      = "Pelipoika (modified by Bintr)",
    description = "Allows players to take control of a robot in Mann vs. Machine",
    version     = "1.0",
    url         = "https://www.sourcemod.net/plugins.php?author=Pelipoika&search=1"
};

#define FLT_MAX 3.402823466e38

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

enum OBJSOLIDTYPE
{
    SOLID_TO_PLAYER_USE_DEFAULT = 0,
    SOLID_TO_PLAYER_YES,
    SOLID_TO_PLAYER_NO,
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

enum BombDeployingState_t
{
	TF_BOMB_DEPLOYING_NONE,
	TF_BOMB_DEPLOYING_DELAY,
	TF_BOMB_DEPLOYING_ANIMATING,
	TF_BOMB_DEPLOYING_COMPLETE,

	TF_BOMB_DEPLOYING_NOT_COUNT
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

// settings for m_takedamage
#define	DAMAGE_NO           0
#define DAMAGE_EVENTS_ONLY  1   // Call damage functions, but don't modify health
#define	DAMAGE_YES          2
#define	DAMAGE_AIM          3

//----------------------------------------------------------------------------
// These must remain in sync with the bot_generator's spawnflags in tf.fgd:
#define TFBOT_IGNORE_ENEMY_SCOUTS       0x0001
#define TFBOT_IGNORE_ENEMY_SOLDIERS     0x0002
#define TFBOT_IGNORE_ENEMY_PYROS        0x0004
#define TFBOT_IGNORE_ENEMY_DEMOMEN      0x0008
#define TFBOT_IGNORE_ENEMY_HEAVIES      0x0010
#define TFBOT_IGNORE_ENEMY_MEDICS       0x0020
#define TFBOT_IGNORE_ENEMY_ENGINEERS    0x0040
#define TFBOT_IGNORE_ENEMY_SNIPERS      0x0080
#define TFBOT_IGNORE_ENEMY_SPIES        0x0100
#define TFBOT_IGNORE_ENEMY_SENTRY_GUNS  0x0200
#define TFBOT_IGNORE_SCENARIO_GOALS     0x0400

#define TFBOT_ALL_BEHAVIOR_FLAGS        0xFFFF

// Used for displaying robot-related information on the client's HUD
Handle g_hHudInfo;
Handle g_hHudReload;

// SDKCalls
Handle g_hfnPlaySpecificSequence;
Handle g_hfnDispatchParticleEffect;
// Handle g_hfnSetMission;
Handle g_hfnGetLeader;
Handle g_hfnPickUp;
Handle g_hfnDrop;
Handle g_hfnRemoveObject;
Handle g_hfnHasTag;
Handle g_hfnWorldSpaceCenter;
Handle g_hfnLeaveSquad;
Handle g_hfnPostInventoryApplication;
Handle g_hfnShouldAutoJump;
Handle g_hfnZoomOut;
Handle g_hfnIsBarrageAndReloadWeapon;
Handle g_hfnCapture;
Handle g_hfnGetClosestCaptureZone;
Handle g_hfnIsInASquad;
Handle g_hfnIsStealthed;
Handle g_hfnHasWeaponRestriction;
Handle g_hfnHasAttribute;
Handle g_hfnIsPlacingSapper;
Handle g_hfnIsBehaviorFlagSet;
#if !defined( WIN32 )
Handle g_hfnRemoveAllItems;
Handle g_hfnGetPercentInvisible;
#endif

// DHooks
DynamicHook g_hfnIsValidObserverTarget;
DynamicHook g_hfnShouldGib;
DynamicHook g_hfnShouldTransmit;
DynamicHook g_hfnPassesFilterImpl;
DynamicHook g_hfnJump;

// Detours
DynamicDetour g_hfnSelectPatient;
DynamicDetour g_hfnIsAllowedToHealTarget;
DynamicDetour g_hfnCreate;
DynamicDetour g_hfnCreateRagdollEntity;

// Offsets
#if defined( WIN32 )
int g_flInvisibility_Offset;
int g_leader_Offset;
#endif
int g_flSpawnTime_Offset;
int g_nDeployingBombState_Offset;   // TODO: Make the logic similar to the game's own logic
int g_squad_Offset;
int g_mission_Offset;
int g_teleportWhereName_Offset;

enum struct ATTRIBUTES
{
    // Human player attributes
    int   iBotSerial;
    float flControlEndTime;
    float flCooldownEndTime;
    float flNextInstructionTime;
    bool  bIsWaitingForFullReload;
    bool  bSkipInventory;
    bool  bBlockRagdoll;
    bool  bPendingSpawnProtectionRemoval;

    // Bot attributes
    int iPlayerSerial;

    /*M+M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M
      Method:   ATTRIBUTES::IsControlling

      Summary:  This function determines if a human player is controlling
                a bot.

      Returns:  bool
                  `true` if the player is currently controlling a bot,
                  otherwise false.
    M---M---M---M---M---M---M---M---M---M---M---M---M---M---M---M---M-M*/
    bool IsControlling()
    {
        return this.iBotSerial != 0;
    }

    /*M+M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M+++M
      Method:   ATTRIBUTES::IsControlled

      Summary:  This function determines if a bot is being controlled
                by a human player.

      Returns:  bool
                  `true` if the bot is currently being controlledby a
                  player, otherwise false.
    M---M---M---M---M---M---M---M---M---M---M---M---M---M---M---M---M-M*/
    bool IsControlled()
    {
        return this.iPlayerSerial != 0;
    }
}

ATTRIBUTES g_aAttributes[ MAXPLAYERS + 1 ];

// TODO: Remove these and only use the objective resource
// Bomb data
int   g_aiFlagCarrierUpgradeLevel[ MAXPLAYERS + 1 ];
float g_aflBombDeployTime[ MAXPLAYERS + 1 ];
float g_aflNextBombUpgradeTime[ MAXPLAYERS + 1 ];

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

    // This call is used to set the deploy animation on the robots with the bomb
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::PlaySpecificSequence" );
    PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );  // const char* pSequenceName
    g_hfnPlaySpecificSequence = EndPrepSDKCall();
    if ( !g_hfnPlaySpecificSequence )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayer::PlaySpecificSequence signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // This call is used to remove an objects owner
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::RemoveObject" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer ); // CBaseObject* pObject
    g_hfnRemoveObject = EndPrepSDKCall();
    if ( !g_hfnRemoveObject )
    {
        SetFailState( "Failed To create SDKCall for CTFPlayer::RemoveObject signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // This call is used to (hopefully) fix wearable issues.
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::PostInventoryApplication" );
    g_hfnPostInventoryApplication = EndPrepSDKCall();
    if ( !g_hfnPostInventoryApplication )
    {
        SetFailState( "Failed To create SDKCall for CTFPlayer::PostInventoryApplication signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

#if !defined( WIN32 )
    // Used to get a bot's squad leader
    StartPrepSDKCall( SDKCall_Raw );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBotSquad::GetLeader" );
    PrepSDKCall_SetReturnInfo( SDKType_CBasePlayer, SDKPass_Pointer );
    g_hfnGetLeader = EndPrepSDKCall();
    if ( !g_hfnGetLeader )
    {
        SetFailState( "Failed to create SDKCall for CTFBotSquad::GetLeader signature." );
    }
#endif

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    /*--------------------------------------------------------------------
      We cannot use the VScript function in this case, since it uses the
      simplified version of `DispatchParticleEffect`
    --------------------------------------------------------------------*/

    // Dispatches a one-off particle system
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

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Used to check if we should hold until a full reload
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFBot::IsBarrageAndReloadWeapon" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );   // CTFWeaponBase* weapon
    PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
    g_hfnIsBarrageAndReloadWeapon = EndPrepSDKCall();
    if ( !g_hfnIsBarrageAndReloadWeapon )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::IsBarrageAndReloadWeapon signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // This call forces a player to pick up the intel
    // FIXME: This just crashes the server no matter how much we wait after the bomb is dropped
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CCaptureFlag::PickUp" );
    PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );   // CTFPlayer* pPlayer
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );            // bool bInvisible (unused)
    g_hfnPickUp = EndPrepSDKCall();
    if ( !g_hfnPickUp )
    {
        SetFailState( "Failed to create SDKCall for CCaptureFlag::PickUp offset." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    /*--------------------------------------------------------------------
      The `DropFlag` VScript function creates a teamplay_flag_event,
      which we do not want. Therefore, we cannot use it.
    --------------------------------------------------------------------*/

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

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // We use this to unzoom sniper bots when mirroring them
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Virtual, "CTFSniperRifle::ZoomOut" );
    g_hfnZoomOut = EndPrepSDKCall();
    if ( !g_hfnZoomOut )
    {
        SetFailState( "Failed to create SDKCall for CTFSniperRifle::ZoomOut offset." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // We use this to capture the defenders' control point (aka bomb hatch)
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CCaptureZone::Capture" );
    PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );   // CBaseEntity *pOther
    g_hfnCapture = EndPrepSDKCall();
    if ( !g_hfnCapture )
    {
        SetFailState( "Failed to create SDKCall for CCaptureZone::Capture signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // We use this to get the control point entity when we're deploying the bomb
    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::GetClosestCaptureZone" );
    PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
    g_hfnGetClosestCaptureZone = EndPrepSDKCall();
    if ( !g_hfnGetClosestCaptureZone )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayer::GetClosestCaptureZone signature." );
    }

#if !defined( WIN32 )
    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayer::RemoveAllItems" );
    g_hfnRemoveAllItems = EndPrepSDKCall();
    if ( !g_hfnRemoveAllItems )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayer::RemoveAllItems signature." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    StartPrepSDKCall( SDKCall_Player );
    PrepSDKCall_SetFromConf( Conf, SDKConf_Signature, "CTFPlayerShared::GetPercentInvisible" );
    PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain );
    g_hfnGetPercentInvisible = EndPrepSDKCall();
    if ( !g_hfnGetPercentInvisible )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayerShared::GetPercentInvisible signature." );
    }
#endif

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!! DHOOK DETOURS !!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    g_hfnSelectPatient = DynamicDetour.FromConf( Conf, "CTFBotMedicHeal::SelectPatient" );
    if ( !g_hfnSelectPatient )
    {
        SetFailState( "Failed to create dynamic detour for CTFBotMedicHeal::SelectPatient." );
    }

    if ( !g_hfnSelectPatient.Enable( Hook_Pre, CTFBotMedicHeal_SelectPatient ) )
    {
        SetFailState( "Failed to enable CTFBotMedicHeal::SelectPatient dynamic detour." );
    }

    if ( !g_hfnSelectPatient.Enable( Hook_Post, CTFBotMedicHeal_SelectPatient_Post ) )
    {
        SetFailState( "Failed to enable CTFBotMedicHeal_SelectPatient_Post dynamic detour." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnIsAllowedToHealTarget = DynamicDetour.FromConf( Conf, "CWeaponMedigun::AllowedToHealTarget" );
    if ( !g_hfnIsAllowedToHealTarget )
    {
        SetFailState( "Failed to create dynamic detour for CWeaponMedigun::AllowedToHealTarget." );
    }

    if ( !g_hfnIsAllowedToHealTarget.Enable( Hook_Pre, CWeaponMedigun_IsAllowedToHealTarget ) )
    {
        SetFailState( "Failed to enable CWeaponMedigun::AllowedToHealTarget dynamic detour." );
    }

    if ( !g_hfnIsAllowedToHealTarget.Enable( Hook_Post, CWeaponMedigun_IsAllowedToHealTarget_Post ) )
    {
        SetFailState( "Failed to enable CWeaponMedigun::AllowedToHealTarget_Post dynamic detour." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnCreate = DynamicDetour.FromConf( Conf, "CTFReviveMarker::Create" );
    if ( !g_hfnCreate )
    {
        SetFailState( "Failed to create dynamic detour for CTFReviveMarker::Create." );
    }

    if ( !g_hfnCreate.Enable( Hook_Pre, CTFReviveMarker_Create ) )
    {
        SetFailState( "Failed to enable CTFReviveMarker::Create dynamic detour." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnCreateRagdollEntity = DynamicDetour.FromConf( Conf, "CTFPlayer::CreateRagdollEntity" );
    if ( !g_hfnCreateRagdollEntity )
    {
        SetFailState( "Failed to create dynamic detour for CTFPlayer::CreateRagdollEntity." );
    }

    if ( !g_hfnCreateRagdollEntity.Enable( Hook_Pre, CTFPlayer_CreateRagdollEntity ) )
    {
        SetFailState( "Failed to enable CTFPlayer::CreateRagdollEntity dynamic detour." );
    }

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!! DHOOKS !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/

    g_hfnShouldGib = DynamicHook.FromConf( Conf, "CTFPlayer::ShouldGib" );
    if ( !g_hfnShouldGib )
    {
        SetFailState( "Failed to get create CTFPlayer::ShouldGib dynamic hook." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnShouldTransmit = DynamicHook.FromConf( Conf, "CBaseEntity::ShouldTransmit" );
    if ( !g_hfnShouldTransmit )
    {
        SetFailState( "Failed to get create CBaseEntity::ShouldTransmit dynamic hook." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnIsValidObserverTarget = DynamicHook.FromConf( Conf, "CTFPlayer::IsValidObserverTarget" );
    if ( !g_hfnIsValidObserverTarget )
    {
        SetFailState( "Failed to get create CTFPlayer::IsValidObserverTarget dynamic hook." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnPassesFilterImpl = DynamicHook.FromConf( Conf, "CFilterTFBotHasTag::PassesFilterImpl" );
    if ( !g_hfnPassesFilterImpl )
    {
        SetFailState( "Failed to get create CFilterTFBotHasTag::PassesFilterImpl dynamic hook." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnJump = DynamicHook.FromConf( Conf, "CBasePlayer::Jump" );
    if ( !g_hfnPassesFilterImpl )
    {
        SetFailState( "Failed to get create CBasePlayer::Jump dynamic hook." );
    }

    /*--------------------------------------------------------------------
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!! OFFSETS !!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --------------------------------------------------------------------*/
#if defined( WIN32 )
    g_flInvisibility_Offset = Conf.GetOffset( "CTFPlayerShared::m_flInvisibility" );
    g_leader_Offset         = Conf.GetOffset( "CTFBotSquad::m_leader" );
#endif
    g_flSpawnTime_Offset         = Conf.GetOffset( "CTFPlayer::m_flSpawnTime" );
    g_nDeployingBombState_Offset = Conf.GetOffset( "CTFPlayer::m_nDeployingBombState" );
    g_squad_Offset               = Conf.GetOffset( "CTFBot::m_squad" );
    g_mission_Offset             = Conf.GetOffset( "CTFBot::m_mission" );
    g_teleportWhereName_Offset   = Conf.GetOffset( "CTFBot::m_teleportWhereName" );

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

    HookEvent( "teamplay_flag_event", Event_FlagEvent, EventHookMode_Post );
    HookEvent( "player_team", Event_PlayerTeam, EventHookMode_Pre );
    HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Pre );
    HookEvent( "player_spawn", Event_PlayerSpawn, EventHookMode_Post );
    HookEvent( "player_builtobject",Event_BuildObject, EventHookMode_Post );
    HookEvent( "teamplay_round_start", Event_ResetBots, EventHookMode_Post );
    HookEvent( "mvm_wave_complete", Event_ResetBots, EventHookMode_Post );
    HookEvent( "player_sapped_object", Event_SappedObject, EventHookMode_Post );

    for ( int iClient = 1; iClient <= MaxClients; iClient++ )
    {
        if ( IsClientInGame( iClient ) )
        {
            ResetGlobals( iClient );
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnAllPluginsLoaded

  Summary:  Called after all plugins have been loaded. This is
            called once for every plugin. If a plugin late loads,
            it will be called immediately after OnPluginStart().

            This function initializes all SDK calls created from
            VScript functions. This must be done after all plugins
            have been loaded due to variables that need to be
            initialized by the VScript plugin.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnAllPluginsLoaded()
{
    // Get vector to center of object - absolute coords
    g_hfnWorldSpaceCenter = VScript_GetClassFunction( "CBaseEntity", "GetCenter" ).CreateSDKCall();
    if ( !g_hfnWorldSpaceCenter )
    {
        SetFailState( "Failed to create SDKCall for CBaseEntity::WorldSpaceCenter from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Set this bot's current mission to the given mission
    /*g_hfnSetMission = VScript_GetClassFunction( "CTFBot", "SetMission" ).CreateSDKCall();
    if ( !g_hfnSetMission )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::SetMission from VScript function." );
    }*/

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Checks if this TFBot has the given bot tag
    g_hfnHasTag = VScript_GetClassFunction( "CTFBot", "HasBotTag" ).CreateSDKCall();
    if ( !g_hfnHasTag )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasTag from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Checks if we are in a squad
    g_hfnIsInASquad = VScript_GetClassFunction( "CTFBot", "IsInASquad" ).CreateSDKCall();
    if ( !g_hfnIsInASquad )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::IsInASquad from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // This call will make a bot leave their squad
    g_hfnLeaveSquad = VScript_GetClassFunction( "CTFBot", "LeaveSquad" ).CreateSDKCall();
    if ( !g_hfnLeaveSquad )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::LeaveSquad from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Returns if the bot should automatically jump
    g_hfnShouldAutoJump = VScript_GetClassFunction( "CTFBot", "ShouldAutoJump" ).CreateSDKCall();
    if ( !g_hfnShouldAutoJump )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::ShouldAutoJump from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    g_hfnIsStealthed = VScript_GetClassFunction( "CTFPlayer", "IsStealthed" ).CreateSDKCall();
    if ( !g_hfnIsStealthed )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayerShared::IsStealthed from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Checks if this TFBot has the given weapon restriction flag
    g_hfnHasWeaponRestriction = VScript_GetClassFunction( "CTFBot", "HasWeaponRestriction" ).CreateSDKCall();
    if ( !g_hfnHasWeaponRestriction )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasWeaponRestriction from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Checks if this TFBot has the given attributes
    g_hfnHasAttribute = VScript_GetClassFunction( "CTFBot", "HasBotAttribute" ).CreateSDKCall();
    if ( !g_hfnHasAttribute )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::HasAttribute from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Return true if the given behavior flag(s) are set for this bot
    g_hfnIsBehaviorFlagSet = VScript_GetClassFunction( "CTFBot", "IsBehaviorFlagSet" ).CreateSDKCall();
    if ( !g_hfnIsBehaviorFlagSet )
    {
        SetFailState( "Failed to create SDKCall for CTFBot::IsBehaviorFlagSet from VScript function." );
    }

    /* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NEW SETUP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

    // Returns true if we placed a sapper in the last few moments
    g_hfnIsPlacingSapper = VScript_GetClassFunction( "CTFPlayer", "IsPlacingSapper" ).CreateSDKCall();
    if ( !g_hfnIsPlacingSapper )
    {
        SetFailState( "Failed to create SDKCall for CTFPlayer::IsPlacingSapper from VScript function." );
    }
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

    delete g_hfnCapture;
    delete g_hfnCreate;
    delete g_hfnCreateRagdollEntity;
    delete g_hfnDispatchParticleEffect;
    delete g_hfnDrop;
    delete g_hfnGetLeader;
    delete g_hfnHasAttribute;
    delete g_hfnHasTag;
    delete g_hfnHasWeaponRestriction;
    delete g_hfnIsAllowedToHealTarget;
    delete g_hfnIsBarrageAndReloadWeapon;
    delete g_hfnIsBehaviorFlagSet;
    delete g_hfnIsInASquad;
    delete g_hfnIsPlacingSapper;
    delete g_hfnIsStealthed;
    delete g_hfnIsValidObserverTarget;
    delete g_hfnJump;
    delete g_hfnLeaveSquad;
    delete g_hfnPassesFilterImpl;
    delete g_hfnPickUp;
    delete g_hfnPlaySpecificSequence;
    delete g_hfnPostInventoryApplication;
    delete g_hfnRemoveObject;
    delete g_hfnSelectPatient;
    // delete g_hfnSetMission;
    delete g_hfnShouldAutoJump;
    delete g_hfnShouldGib;
    delete g_hfnShouldTransmit;
    delete g_hfnWorldSpaceCenter;
    delete g_hfnZoomOut;
    delete g_hfnGetClosestCaptureZone;
#if !defined( WIN32 )
    delete g_hfnGetPercentInvisible;
    delete g_hfnRemoveAllItems;
#endif
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnMapStart

  Summary:  Called when the map is loaded. This function disables
            the plugin if the current map is not a Mann vs. Machine
            map. It also precaches game sounds we emit throughout
            this plugin.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnMapStart()
{
    if ( !IsMannVsMachineMode() )
    {
        char szDescription[ 64 ];
        GetGameDescription( szDescription, sizeof( szDescription ), true );
        SteamWorks_SetGameDescription( szDescription );
        SetFailState( "Disabling for non Mann vs. Machine map." );
    }

    SteamWorks_SetGameDescription( ":: Bot Control ::" );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: ResetGlobals

  Summary:  This function resets a player's global values.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
stock void ResetGlobals( int iClient )
{
    g_aAttributes[ iClient ].iBotSerial                     = 0;
    g_aAttributes[ iClient ].iPlayerSerial                  = 0;
    g_aAttributes[ iClient ].bSkipInventory                 = false;
    g_aAttributes[ iClient ].bBlockRagdoll                  = false;
    g_aAttributes[ iClient ].flCooldownEndTime              = -1.0;
    g_aAttributes[ iClient ].flControlEndTime               = -1.0;
    g_aAttributes[ iClient ].bPendingSpawnProtectionRemoval = false;
    g_aAttributes[ iClient ].bIsWaitingForFullReload        = false;

    g_aiFlagCarrierUpgradeLevel[ iClient ] = 0;
    g_aflNextBombUpgradeTime[ iClient ]    = -1.0;
    g_aflBombDeployTime[ iClient ]         = -1.0;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnClientPutInServer

  Summary:  Called when a client is entering the game.
            Whether a client has a steamid is undefined until
            OnClientAuthorized is called, which may occur either
            before or after OnClientPutInServer. Similarly, use
            OnClientPostAdminCheck() if you need to verify whether
            connecting players are admins.
            GetClientCount() will include clients as they are passed
            through this function, as clients are already in game
            at this point.

            This function hooks the necessary callbacks to player
            entities.

  Args:     int iClient
              Client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnClientPutInServer( int iClient )
{
    ResetGlobals( iClient );

    // TODO: Dynamically hook and unhook these
    if ( IsFakeClient( iClient ) )
    {
        g_hfnIsValidObserverTarget.HookEntity( Hook_Post, iClient, CTFPlayer_IsValidObserverTarget );
    }
    else
    {
        // Mimic gibbing logic for human invaders
        g_hfnShouldGib.HookEntity( Hook_Post, iClient, CTFPlayer_ShouldGib );

        // Apply smoke to feet when human invaders jump (if applicable)
        g_hfnJump.HookEntity( Hook_Post, iClient, CBasePlayer_Jump );

        // Fix problems related to switching weapons while we're supposed to fully reload
        SDKHook( iClient, SDKHook_WeaponSwitchPost, UpdateForcedReloadingVars );

        SDKHook( iClient, SDKHook_SetTransmit, IsIgnored );
        SDKHook( iClient, SDKHook_OnTakeDamageAlivePost, Player_OnTakeDamageAlivePost );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFReviveMarker_Create

  Summary:  This function is used to block the creation of revive
            markers for human invaders.

            Original function signature:
            `CTFReviveMarker *CTFReviveMarker::Create( CTFPlayer *pOwner )`

  Args:     DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CTFReviveMarker_Create( DHookReturn hReturn, DHookParam hParams )
{
    if ( !hParams.IsNull( 1 ) )
    {
        int iOwner = hParams.Get( 1 );
        if ( TF2_GetClientTeam( iOwner ) == TF_TEAM_PVE_INVADERS )
        {
            // FIXME: Directly switching teams from invaders to defenders drops a marker
            hReturn.Value = -1;
            return MRES_Supercede;
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CFilterTFBotHasTag_PassesFilterImpl

  Summary:  This function is an implementation of
            `CFilterTFBotHasTag::PassesFilterImpl`, but for human
            players.

            Original function signature:
            `bool PassesFilterImpl( CBaseEntity *pCaller, CBaseEntity *pEntity )`

  Args:     int iThis
              The calling CFilterTFBotHasTag entity.
            DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CFilterTFBotHasTag_PassesFilterImpl( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( hParams.IsNull( 1 ) || hParams.IsNull( 2 ) )
    {
        return MRES_Ignored;
    }

    int iCaller = hParams.Get( 2 );
    if ( !IsPlayerIndex( iCaller ) || !IsClientInGame( iCaller ) || IsFakeClient( iCaller ) )
    {
        return MRES_Ignored;
    }

    if ( !IsPlayerAlive( iCaller ) )
    {
        hReturn.Value = false;
        return MRES_Supercede;
    }

    // Don't care about players not controlling a bot
    if ( !g_aAttributes[ iCaller ].IsControlling() )
    {
        return MRES_Ignored;
    }

    int  iEntity = hParams.Get( 1 );
    char szClassname[ 64 ];
    GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

    // We don't care about you
    if ( StrEqual( szClassname, "func_nav_prerequisite" ) )
    {
        return MRES_Ignored;
    }

    char iszTags[ 512 ];
    GetEntPropString( iThis, Prop_Data, "m_iszTags", iszTags, sizeof( iszTags ) );
    // bool bRequireAllTags = view_as< bool >( GetEntProp( iThis, Prop_Data, "m_bRequireAllTags" ) );    // Don't know of a map that uses this

    bool bHasTag = HasTag( GetClientFromSerial( g_aAttributes[ iCaller ].iBotSerial ), iszTags );
    if ( GetEntProp( iThis, Prop_Data, "m_bNegated" ) )
    {
        bHasTag = !bHasTag;
    }

    // These work the opposite way
    if ( StrEqual( szClassname, "trigger_add_tf_player_condition" ) )
    {
        bHasTag = !bHasTag;
    }

    // PrintToServer( "Filter %i on entity %s asks: HasTag %N %s ? %s", iThis, szClassName, iBot, iszTags, bHasTag ? "Yes" : "No" );

    hReturn.Value = bHasTag;
    return MRES_Supercede;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_IsValidObserverTarget

  Summary:  This function blocks players from spectating controlled
            bots.

            Original function signature:
            `bool CTFPlayer::IsValidObserverTarget( CBaseEntity * target )`

  Args:     int iThis
              The calling CTFPlayer entity.
            DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CTFPlayer_IsValidObserverTarget( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( hParams.IsNull( 1 ) )
    {
        return MRES_Ignored;
    }

    int iTarget = hParams.Get( 1 );
    if ( !IsPlayerIndex( iTarget ) || !IsClientInGame( iThis ) || !IsClientInGame( iTarget ) )
    {
        return MRES_Ignored;
    }

    if ( !g_aAttributes[ iTarget ].IsControlled() )
    {
        return MRES_Ignored;
    }

    hReturn.Value = false;
    return MRES_Supercede;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_ShouldGib

  Summary:  This function implements robots' gibbing logic for human
            invading players.

            Original function signature:
            `bool CTFPlayer::ShouldGib( const CTakeDamageInfo &info )`

  Args:     int iThis
              The calling CTFPlayer entity.
            DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CTFPlayer_ShouldGib( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( TF2_GetClientTeam( iThis ) != TF_TEAM_PVE_INVADERS )
    {
        return MRES_Ignored;
    }

    if ( IsMiniBoss( iThis ) || GetEntPropFloat( iThis, Prop_Send, "m_flModelScale" ) > 1.0 )
    {
        hReturn.Value = true;
        return MRES_Supercede;
    }

    switch ( TF2_GetPlayerClass( iThis ) )
    {
        case TFClass_Sniper, TFClass_Medic, TFClass_Spy, TFClass_Engineer:
        {
            hReturn.Value = false;
            return MRES_Supercede;
        }

        default:
        {
            return MRES_Ignored;
        }
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CBasePlayer_Jump

  Summary:  This function applies the smoke effect to human
            invaders' feet when they jump if the bot they're
            controlling has the necessary atribute.

            Original function signature:
            `void CBasePlayer::Jump()`

  Args:     int iThis
              The calling CTFPlayer entity.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CBasePlayer_Jump( int iThis )
{
    if ( g_aAttributes[ iThis ].IsControlling() )
    {
        Address pCustomJumpParticle = TF2Attrib_GetByName( GetClientFromSerial( g_aAttributes[ iThis ].iBotSerial ), "bot custom jump particle" );
        if ( !pCustomJumpParticle )
        {
            return MRES_Ignored;
        }

        int iCustomJumpParticle = view_as< int >( TF2Attrib_GetValue( pCustomJumpParticle ) );
        if ( iCustomJumpParticle )
        {
            SDKCall( g_hfnDispatchParticleEffect, "rocketjump_smoke", PATTACH_POINT_FOLLOW, iThis, "foot_L", false );
            SDKCall( g_hfnDispatchParticleEffect, "rocketjump_smoke", PATTACH_POINT_FOLLOW, iThis, "foot_R", false );

            return MRES_Handled;
        }
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CTFPlayer_CreateRagdollEntity

  Summary:  This function blocks ragdolls from spawning if we've
            marked player accordingly.

            Original function signature:
            `void CTFPlayer::CreateRagdollEntity( bool bGib, bool bBurning, bool bElectrocuted, bool bOnGround, bool bCloakedCorpse, bool bGoldRagdoll, bool bIceRagdoll, bool bBecomeAsh, int iDamageCustom, bool bCritOnHardHit )`

  Args:     int iThis
              The calling CTFPlayer entity.
            DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CTFPlayer_CreateRagdollEntity( int iThis, DHookParam hParams )
{
    if ( g_aAttributes[ iThis ].bBlockRagdoll )
    {
        g_aAttributes[ iThis ].bBlockRagdoll = false;
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: CBaseEntity_ShouldTransmit

  Summary:  Original function signature:
            `int CBaseEntity::ShouldTransmit( const CCheckTransmitInfo *pInfo )`

  Args:     int iThis
              The calling CBaseEntity entity.
            DHookReturn hReturn
              Handle to the return value of the function.
            DHookParam hParams
              Handle to the parameters of the called function.

  Returns:  MRESReturn
              DHook return action.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public MRESReturn CBaseEntity_ShouldTransmit( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    if ( IsCarried( iThis ) || IsPlacing( iThis ) )
    {
        // Let game decide
        return MRES_Ignored;
    }

    hReturn.Value = FL_EDICT_ALWAYS;
    return MRES_Supercede;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnClientDisconnect

  Summary:  Called when a client is disconnecting from the server.
            This function restores an invader bot if the controlling
            player disconnects.

  Args:     int iClient
              Disconnecting client index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnClientDisconnect( int iClient )
{
    if ( !IsPlayerIndex( iClient ) || !IsClientInGame( iClient ) || IsFakeClient( iClient ) )
    {
        return;
    }

    TF2_RestoreBot( iClient );
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnEntityCreated

  Summary:  This function is called when an entity is created. It
            hooks functions onto specific entities.

  Args:     int iEntity
              Entity index.
            const char[] szClassname
              String representing the entity's class.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnEntityCreated( int iEntity, const char[] szClassname )
{
    if ( StrEqual( szClassname, "item_currencypack_custom" ) )
    {
        SDKHook( iEntity, SDKHook_SpawnPost, OnCurrencySpawnPost );
    }
    else if ( StrEqual( szClassname, "filter_tf_bot_has_tag" ) )
    {
        SDKHook( iEntity, SDKHook_SpawnPost, OnFilterSpawnPos );
    }
    else if ( StrEqual( szClassname, "obj_sentrygun" )  ||
              StrEqual( szClassname, "obj_minisentry" ) ||
              StrEqual( szClassname, "obj_teleporter" ) )
    {
        SDKHook( iEntity, SDKHook_SetTransmit, IsIgnored );
    }
    else if( StrEqual( szClassname, "func_respawnroom" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnSpawnStartTouch );
        SDKHook( iEntity, SDKHook_EndTouch, OnSpawnEndTouch );
    }
    else if ( StrEqual( szClassname, "func_capturezone" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnHatchStartTouch );
        SDKHook( iEntity, SDKHook_EndTouch, OnHatchEndTouch );
    }
    else if ( StrEqual( szClassname, "item_teamflag" ) )
    {
        SDKHook( iEntity, SDKHook_StartTouch, OnFlagTouch );
        SDKHook( iEntity, SDKHook_Touch, OnFlagTouch );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnFilterSpawnPos

  Summary:  This function hooks the `PassesFilterImpl` function
            on an entity after it has spawned.

  Args:     int iEntity
              Entity index.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnFilterSpawnPos( int iEntity )
{
    g_hfnPassesFilterImpl.HookEntity( Hook_Post, iEntity, CFilterTFBotHasTag_PassesFilterImpl );
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
    g_hfnShouldTransmit.HookEntity( Hook_Post, iSentry, CBaseEntity_ShouldTransmit );

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
        if ( IsCarried( moveparent ) || IsPlacing( moveparent ) )   // The sentry is carried, set my parent to the engie!
        {
            moveparent = TF2_GetObjectBuilder( moveparent );
        }
    }
    else if ( IsPlayerIndex( moveparent ) ) // My parent is the engie
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

            float vecAbsOriginParent[ 3 ];
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

    if ( IsPlayerIndex( iClient ) && IsClientInGame( iClient ) && IsSentryBuster( iClient ) )
    {
        // Allow the sentry buster to see the glow
        return Plugin_Continue;
    }

    // Do not allow other players to see the glow
    return Plugin_Handled;
}

public void Event_SappedObject( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int          iClient = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    TFObjectType iObject = view_as< TFObjectType >( hEvent.GetInt( "object" ) );
    if (
        iObject == TFObject_Teleporter &&
        IsPlayerIndex( iClient )       &&
        IsClientInGame( iClient )      &&
        TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS
        )
    {
        RemoveEntity( hEvent.GetInt( "sapperid" ) );
    }
}

public Action OnFlagTouch( int iEntity, int iOther )
{
    // If its not a client we don't care
    if ( !IsPlayerIndex( iOther ) )
    {
        return Plugin_Continue;
    }

    // Only care about invaders
    if ( TF2_GetClientTeam( iOther ) != TF_TEAM_PVE_INVADERS )
    {
        return Plugin_Handled;
    }

    // Controlled bots should never be able to pickup bomb
    if ( g_aAttributes[ iOther ].IsControlled() )
    {
        return Plugin_Handled;
    }

    // Gatebots ignore bombs and only capture gates
    if ( HasTag( iOther, "bot_gatebot" ) )
    {
        return Plugin_Handled;
    }

    // Sentry busters shouldn't pick up the bomb
    if ( IsSentryBuster( iOther ) )
    {
        return Plugin_Handled;
    }

    if ( g_aAttributes[ iOther ].IsControlling() )
    {
        int iBot = GetClientFromSerial( g_aAttributes[ iOther ].iBotSerial );
        if ( IsInASquad( iBot ) )
        {
            if ( GetLeader( GetSquad( iBot ) ) != iOther )
            {
                return Plugin_Handled;
            }
        }
    }

    return Plugin_Continue;
}

public Action OnHatchStartTouch( int iEntity, int iClient )
{
    if ( !IsPlayerIndex( iClient ) || IsFakeClient( iClient ) )
    {
        return Plugin_Continue;
    }

    if ( !TF2_HasBomb( iClient ) )
    {
        return Plugin_Handled;
    }

    if ( GetDeployingBombState( iClient ) != TF_BOMB_DEPLOYING_NONE )
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

    if ( IsMiniBoss( iClient ) )
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
    TF2_AddCondition( iClient, TFCond_FreezeInput );

    SDKCall( g_hfnPlaySpecificSequence, iClient, "primary_deploybomb" );
    RequestFrame( DisableDeployBombAnimation, GetClientSerial( iClient ) );

    TF2_SetClientTauntCamMode( iClient, TauntCam_Enabled );

    g_aflBombDeployTime[ iClient ] = GetGameTime() + FindConVar( "tf_deploying_bomb_time" ).FloatValue + 0.5;
    SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_ANIMATING );

    return Plugin_Continue;
}

public void DisableDeployBombAnimation( int iClientSerial )
{
    static int iCount = 0;

    int iClient = GetClientFromSerial( iClientSerial );
    if ( iClient == 0 )
    {
        return;
    }

    if ( iCount > 6 )
    {
        SetVariantBool( true );
        AcceptEntityInput( iClient, "SetCustomModelRotates" );

        SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", false );

        float vecClientAbsOrigin[ 3 ], vecTargetPos[ 3 ];
        GetClientAbsOrigin( iClient, vecClientAbsOrigin );

        vecTargetPos = TF2_GetBombHatchPosition();

        float vecResult[ 3 ];
        SubtractVectors( vecTargetPos, vecClientAbsOrigin, vecResult );
        NormalizeVector( vecResult, vecResult );

        vecResult[ 0 ] = vecResult[ 2 ] = 0.0;

        SetVariantVector3D( vecResult );
        AcceptEntityInput( iClient, "SetCustomModelRotation" );

        iCount = 0;
    }
    else
    {
        SDKCall( g_hfnPlaySpecificSequence, iClient, "primary_deploybomb" );
        RequestFrame( DisableDeployBombAnimation, iClientSerial );
        iCount++;
    }
}

public void OnHatchEndTouch( int iEntity, int iClient )
{
    if ( !IsPlayerIndex( iClient ) || IsFakeClient( iClient ) || !TF2_HasBomb( iClient ) )
    {
        return;
    }

    TF2_RemoveCondition( iClient, TFCond_FreezeInput );

    SetVariantString( "1" );
    AcceptEntityInput( iClient, "SetCustomModelRotates" );

    SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", true );

    TF2_SetClientTauntCamMode( iClient, TauntCam_Disabled );

    g_aflBombDeployTime[ iClient ] = -1.0;
    SetDeployingBombState( iClient, TF_BOMB_DEPLOYING_NONE );
}

public void OnSpawnStartTouch( int iRespawnRoom, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iRespawnRoom, Prop_Send, "m_iTeamNum" ) );
    if (
        eTeam != TF_TEAM_PVE_INVADERS         ||
        !IsPlayerIndex( iEntity )             ||
        TF2_GetClientTeam( iEntity ) != eTeam ||
        IsFakeClient( iEntity )
        )
    {
        return;
    }

    // Invaders with the `ALWAYS_FIRE_WEAPON` attribute can attack in spawn
    if ( !HasAttribute( GetClientFromSerial( g_aAttributes[ iEntity ].iBotSerial ), ALWAYS_FIRE_WEAPON ) )
    {
        // Otherwise they can't attack in spawn
        TF2Attrib_SetByName( iEntity, "no_attack", 1.0 );
    }

    /*--------------------------------------------------------------------
      Invaders cannot be hurt or pushed around while in spawn. These
      conditions are the exact same the game itself applies to bots.
    --------------------------------------------------------------------*/
    TF2_AddCondition( iEntity, TFCond_Ubercharged );
    TF2_AddCondition( iEntity, TFCond_UberchargedHidden );
    TF2_AddCondition( iEntity, TFCond_UberchargeFading );
    TF2_AddCondition( iEntity, TFCond_ImmuneToPushback );

    if ( TF2_HasBomb( iEntity ) )
    {
        RequestFrame( UpdateBombHud, GetClientSerial( iEntity ) );
    }
}

public void OnSpawnEndTouch( int iRespawnRoom, int iEntity )
{
    TFTeam eTeam = view_as< TFTeam >( GetEntProp( iRespawnRoom, Prop_Send, "m_iTeamNum" ) );
    if (
        eTeam != TF_TEAM_PVE_INVADERS         ||
        !IsPlayerIndex( iEntity )             ||
        TF2_GetClientTeam( iEntity ) != eTeam ||
        IsFakeClient( iEntity )
        )
    {
        return;
    }

    if ( TF2_HasBomb( iEntity ) )
    {
        switch( g_aiFlagCarrierUpgradeLevel[ iEntity ] )
        {
            case 0: g_aflNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" ).FloatValue;
            case 1: g_aflNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade" ).FloatValue;
            case 2: g_aflNextBombUpgradeTime[ iEntity ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade" ).FloatValue;
        }
        // The bomb HUD needs to be updated BEFORE we add the spawn protection conditions again
        UpdateBombHud( GetClientSerial( iEntity ) );
    }

    /*--------------------------------------------------------------------
      Remove the spawn protection conditions as soon as the player has
      a valid ground entity after exiting spawn. This prevents fall
      damage from large drops at spawn exits.
    --------------------------------------------------------------------*/
    g_aAttributes[ iEntity ].bPendingSpawnProtectionRemoval = true;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: OnGameFrame

  Summary:  Called before every server frame. Note that you should
            avoid doing expensive computations or declaring large
            local arrays.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void OnGameFrame()
{
    for ( int i = 1; i <= MaxClients; i++ )
    {
        if ( !g_aAttributes[ i ].bPendingSpawnProtectionRemoval )
        {
            continue;
        }

        if ( !IsClientInGame( i ) || !IsPlayerAlive( i ) )
        {
            g_aAttributes[ i ].bPendingSpawnProtectionRemoval = false;
            continue;
        }

        /*--------------------------------------------------------------------
          The way the game itself applies these spawn protection conditions
          is not by vector location, but by the last nav area the bot stepped
          onto. This makes it so that if the invading team has a large drop
          when exiting spawn, these conditions will stay applied until the
          bot lands on the ground, preventing fall damage. `CTFPlayer`
          doesn't have a `GetLastKnownArea` member function, and this is
          much better than manually keeping track of the last nav area we
          walked on.
        --------------------------------------------------------------------*/
        if ( GetEntityFlags( i ) & FL_ONGROUND )
        {
            // `OnPlayerRunCmd` decides when players with the `HOLD_FIRE_UNTIL_FULL_RELOAD` attribute can attack
            if ( !HasAttribute( GetClientFromSerial( g_aAttributes[ i ].iBotSerial ), HOLD_FIRE_UNTIL_FULL_RELOAD ) )
            {
                TF2Attrib_RemoveByName( i, "no_attack" );
            }

            TF2_RemoveCondition( i, TFCond_Ubercharged );
            TF2_RemoveCondition( i, TFCond_UberchargedHidden );
            TF2_RemoveCondition( i, TFCond_UberchargeFading );
            TF2_RemoveCondition( i, TFCond_ImmuneToPushback );

            g_aAttributes[ i ].bPendingSpawnProtectionRemoval = false;
        }
    }
}

public void TF2_OnConditionAdded( int iClient, TFCond eCond )
{
    if ( IsFakeClient( iClient ) )
    {
        if ( g_aAttributes[ iClient ].IsControlled() && GetEntPropEnt( iClient, Prop_Send, "moveparent" ) != -1 )
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
    if ( !IsPlayerIndex( iOwnerEntity ) || !g_aAttributes[ iOwnerEntity ].IsControlled() )
    {
        return;
    }

    int iPlayer = GetClientFromSerial( g_aAttributes[ iOwnerEntity ].iPlayerSerial );   // The bot's controller player
    int iBot    = GetClientFromSerial( g_aAttributes[ iPlayer ].iBotSerial );           // The bot of the controller

    if ( iBot != 0 && IsFakeClient( iBot ) && iPlayer != 0 && iBot == iOwnerEntity && g_aAttributes[ iPlayer ].IsControlling() )
    {
        float vecAbsOrigin[ 3 ];
        GetClientAbsOrigin( iPlayer, vecAbsOrigin );
        vecAbsOrigin[ 2 ] += 32.0;

        TeleportEntity( iCurrency, vecAbsOrigin, NULL_VECTOR, NULL_VECTOR );
    }
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: UpdateForcedReloadingVars

  Summary:  This callback function is called after every weapon
            switch and is used to reset the per-client value of
            the array used by the forced full reload logic to
            determine whether we should prevent the client from
            firing their weapon until fully reloading.

  Args:     int iClient
              Index of client that switched weapons.
            int iWeapon
              Index of the weapon the client switched to.

  Returns:  void
              No return value.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public void UpdateForcedReloadingVars( int iClient, int iWeapon )
{
    if ( !g_aAttributes[ iClient ].IsControlling() )
    {
        return;
    }

    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
    if ( iBot == 0 )
    {
        return;
    }

    if ( !HasAttribute( iBot, HOLD_FIRE_UNTIL_FULL_RELOAD ) && !FindConVar( "tf_bot_always_full_reload" ).BoolValue )
    {
        return;
    }

    /*--------------------------------------------------------------------
      FIXME: Right now we force a full reload no matter the amount of
      ammo we have in our clip, but we should only force it if we had
      <= 0 when we started reloading.
    --------------------------------------------------------------------*/
    g_aAttributes[ iClient ].bIsWaitingForFullReload = SDKCall( g_hfnIsBarrageAndReloadWeapon, iBot, iWeapon );
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
        if ( g_aAttributes[ iClient ].IsControlled() )
        {
            iImpulse = 0;
            iButtons = 0;
            return Plugin_Changed;
        }

        return Plugin_Continue;
    }

    if ( g_aAttributes[ iClient ].IsControlling() && IsPlayerAlive( iClient ) && TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS )
    {
        float vecOrigin[ 3 ];
        GetClientAbsOrigin( iClient, vecOrigin );

        bool bInSpawn = TF2Util_IsPointInRespawnRoom( vecOrigin, iClient, true );

        SetEntPropFloat( iClient, Prop_Send, "m_flCloakMeter", 100.0 );

        int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
        if ( SDKCall( g_hfnShouldAutoJump, iBot ) )
        {
            iButtons |= IN_JUMP;
        }

        int iActiveWeapon = TF2_GetClientActiveWeapon( iClient );
        if ( iActiveWeapon != -1 )
        {
            if (
                HasAttribute( iBot, AIR_CHARGE_ONLY )                &&
                TF2_GetPlayerClass( iClient ) == TFClass_DemoMan     &&
                !TF2_IsPlayerInCondition( iClient, TFCond_Charging ) &&
                GetEntProp( iClient, Prop_Send, "m_bShieldEquipped" )
                )
            {
                if ( GetEntPropEnt( iClient, Prop_Send, "m_hGroundEntity" ) == -1 && vecVelocity[ 2 ] <= 0.0 )
                {
                    // FIXME: Find a way to only charge when at the top of our jump
                    iButtons |= IN_ATTACK2;
                }
                else
                {
                    // If we shouldn't charge, then don't allow the player to manually do so either
                    iButtons &= ~IN_ATTACK2;
                }
            }

            if ( SDKCall( g_hfnIsBarrageAndReloadWeapon, iBot, iActiveWeapon ) )
            {
                if ( HasAttribute( iBot, HOLD_FIRE_UNTIL_FULL_RELOAD ) || FindConVar( "tf_bot_always_full_reload" ).BoolValue )
                {
                    int iClip1 = GetEntProp( iActiveWeapon, Prop_Send, "m_iClip1" );
                    if ( iClip1 <= 0 )
                    {
                        g_aAttributes[ iClient ].bIsWaitingForFullReload = true;
                    }

                    if ( g_aAttributes[ iClient ].bIsWaitingForFullReload )
                    {
                        int iMaxClip1 = TF2Util_GetWeaponMaxClip( iActiveWeapon );
                        if ( iClip1 < iMaxClip1 )
                        {
                            TF2Attrib_SetByName( iClient, "no_attack", 1.0 );
                            /*--------------------------------------------------------------------
                              A player can pause reloading by holding their attack button down,
                              so we manually unpress that button.
                            --------------------------------------------------------------------*/
                            iButtons &= ~IN_ATTACK;

                            SetHudTextParams( -1.0, -0.55, 0.25, 255, 150, 0, 255, 0, 0.0, 0.0, 0.0 );
                            ShowSyncHudText( iClient, g_hHudReload, "RELOADING... (%d / %d)", iClip1, iMaxClip1 );
                        }
                        else
                        {
                            g_aAttributes[ iClient ].bIsWaitingForFullReload = false;
                        }
                    }
                    else
                    {
                        // Don't remove the attribute if we're still in spawn
                        if ( !bInSpawn )
                        {
                            TF2Attrib_RemoveByName( iClient, "no_attack" );
                        }

                        SetHudTextParams( -1.0, -0.55, 1.75, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0 );
                        ShowSyncHudText( iClient, g_hHudReload, "READY TO FIRE!" );
                    }
                }
            }

            if ( HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) && !g_aAttributes[ iClient ].bIsWaitingForFullReload )
            {
                // Remove this in case the player switched weapons mid-reload
                TF2Attrib_RemoveByName( iClient, "no_attack" );

                /*--------------------------------------------------------------------
                  A player can pause auto-firing by holding down their attack2 key,
                  so we manually unpress that button.
                --------------------------------------------------------------------*/
                iButtons &= ~IN_ATTACK2;

                iButtons |= IN_ATTACK;
            }
        }

        SetHudTextParams( 1.0, 0.0, 0.1, 88, 133, 162, 0, 0, 0.0, 0.0, 0.0 );
        ShowSyncHudText( iClient, g_hHudInfo, "Playing as %N", iBot );

        // FIXME: Doesn't work
        // TF2_InstructPlayer( iClient );

        if ( bInSpawn )
        {
            if ( g_aAttributes[ iClient ].flControlEndTime <= GetGameTime() )
            {
                PrintColoredChat( iClient, COLOR_RED ... "You have lost control of " ... COLOR_BLUE ... "%N" ... COLOR_RED ... " and received a 30 second cooldown from playing as a robot for staying in spawn too long", iBot );

                g_aAttributes[ iClient ].iBotSerial = 0;

                TF2_RestoreBot( iClient );
                TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

                g_aAttributes[ iClient ].flCooldownEndTime = GetGameTime() + 30.0;

                return Plugin_Continue;
            }
            else if ( g_aAttributes[ iClient ].flControlEndTime > GetGameTime() )
            {
                float flTimeLeft = g_aAttributes[ iClient ].flControlEndTime - GetGameTime();

                if ( flTimeLeft <= 15.0 )
                {
                    SetHudTextParams( -1.0, -0.8, 0.1, 255, 0, 0, 0, 0, 0.0, 0.0, 0.0 );
                    ShowSyncHudText( iClient, g_hHudInfo, "You have %.0f seconds to leave spawn or you will lose control of your bot", flTimeLeft );
                }
            }
        }

        if ( IsSentryBuster( iClient ) && GetEntPropEnt( iClient, Prop_Send, "m_hGroundEntity" ) != -1 )
        {
            // Disable the use of the sentry buster's caber
            SetEntPropFloat( iClient, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 0.5 );

            // Detonate buster if the player is pressing M1 or taunting
            if ( ( iButtons & IN_ATTACK || TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) ) && !HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) )
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

        if ( TF2_HasBomb( iClient ) )
        {
            if ( GetDeployingBombState( iClient ) != TF_BOMB_DEPLOYING_NONE )
            {
                if ( g_aflBombDeployTime[ iClient ] <= GetGameTime() )
                {
                    if ( iBot > 0 && IsFakeClient( iBot ) )
                    {
                        PrintColoredChatAll( COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " playing as " ... COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " deployed the " ... COLOR_UNIQUE ... "BOMB" ... COLOR_DEFAULT ... " with " ... COLOR_RED ... "%i HP" ... COLOR_DEFAULT ... "!", iClient, iBot, GetClientHealth( iClient ) );
                    }
                    else
                    {
                        PrintColoredChatAll( COLOR_BLUE ... "%N" ... COLOR_DEFAULT ... " deployed the " ... COLOR_UNIQUE ... "BOMB" ... COLOR_DEFAULT ... " with " ... COLOR_RED ... "%i HP" ... COLOR_DEFAULT ... "!", iClient, GetClientHealth( iClient ) );
                    }

                    g_aAttributes[ iClient ].bBlockRagdoll = true;

                    int iAreaTrigger = SDKCall( g_hfnGetClosestCaptureZone, iClient );

                    SDKCall( g_hfnCapture, iAreaTrigger, iClient );
                    g_aAttributes[ iClient ].flCooldownEndTime = GetGameTime() + 10.0;
                    EmitGameSoundToAll( "Announcer.MVM_Robots_Planted", SOUND_FROM_WORLD );
                    SDKHooks_TakeDamage( iClient, iClient, iClient, 99999.9, DMG_CRUSH );
                }

                return Plugin_Changed;
            }

            if ( !TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) && GetDeployingBombState( iClient ) == TF_BOMB_DEPLOYING_NONE )
            {
                if ( !IsMiniBoss( iClient ) )
                {
                    if ( g_aiFlagCarrierUpgradeLevel[ iClient ] > 0 )
                    {
                        for ( int i = 1; i <= MaxClients; i++ )
                        {
                            if (
                                !IsClientInGame( i )                                   ||
                                TF2_GetClientTeam( i ) != TF2_GetClientTeam( iClient ) ||
                                g_aiFlagCarrierUpgradeLevel[ iClient ] < 1             ||
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

                    if ( g_aflNextBombUpgradeTime[ iClient ] <= GetGameTime() && g_aiFlagCarrierUpgradeLevel[ iClient ] < 3 && GetEntPropEnt( iClient, Prop_Send, "m_hGroundEntity" ) != -1 )
                    {
                        // Why do we need to throttle this? Doesn't this happen right away, plus the first check guards this?
                        FakeClientCommandThrottled( iClient, "taunt" );

                        // Is this check needed?
                        if ( TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) )
                        {
                            g_aiFlagCarrierUpgradeLevel[ iClient ]++;

                            switch ( g_aiFlagCarrierUpgradeLevel[ iClient ] )
                            {
                                case 1:
                                {
                                    g_aflNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_2nd_upgrade" ).FloatValue;
                                    TF2_AddCondition( iClient, TFCond_DefenseBuffNoCritBlock );

                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup1", PATTACH_POINT_FOLLOW, iClient, "head", false );
                                }
                                case 2:
                                {
                                    g_aflNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_3rd_upgrade" ).FloatValue;

                                    Address pHealthRegen = TF2Attrib_GetByName( iClient, "health regen" );
                                    float   flRegen      = 0.0;
                                    if ( pHealthRegen != Address_Null )
                                    {
                                        flRegen = TF2Attrib_GetValue( pHealthRegen );
                                    }

                                    TF2Attrib_SetByName( iClient, "health regen", flRegen + 45.0 );
                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup2", PATTACH_POINT_FOLLOW, iClient, "head", false );
                                }
                                case 3:
                                {
                                    TF2_AddCondition( iClient, TFCond_CritOnWin );
                                    SDKCall( g_hfnDispatchParticleEffect, "mvm_levelup3", PATTACH_POINT_FOLLOW, iClient, "head", false );
                                }
                            }
                            EmitGameSoundToAll( "MVM.Warning", SOUND_FROM_WORLD );
                            RequestFrame( UpdateBombHud, GetClientSerial( iClient ) );
                        }
                    }
                }
                else if ( g_aiFlagCarrierUpgradeLevel[ iClient ] != 4 )
                {
                    g_aiFlagCarrierUpgradeLevel[ iClient ] = 4;
                    RequestFrame( UpdateBombHud, GetClientSerial( iClient ) );
                }
            }
        }
    }
    else
    {
        int iObserverTarget = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );

        if ( TF2_ObservedIsValidClient( iClient ) )
        {
            SetHudTextParams( 1.0, 0.0, 0.1, 126, 126, 126, 0, 0, 0.0, 0.0, 0.0 );
            ShowSyncHudText( iClient, g_hHudInfo, "Call for MEDIC! to play as %N", iObserverTarget );
        }
        else if ( IsPlayerIndex( iObserverTarget ) && IsFakeClient( iObserverTarget ) )
        {
            int iObserverMode = GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
            if ( iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE )
            {
                SetHudTextParams( 1.0, 0.0, 0.1, 255, 0, 0, 0, 0, 0.0, 0.0, 0.0 );
                ShowSyncHudText( iClient, g_hHudInfo, "Cannot play as %N", iObserverTarget );
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
    if ( !IsPlayerIndex( iVictim ) || !IsPlayerIndex( iAttacker ) )
    {
        return;
    }

    if ( !IsMiniBoss( iVictim ) )
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
    if ( g_aAttributes[ iClient ].flNextInstructionTime > GetGameTime() )
    {
        return;
    }

    LogServer( "Trying to instruct %L...", iClient );

    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
    if ( iBot == 0 )
    {
        LogServer( "Cannot instruct %N because they are not controling a bot." );
        return;
    }

    if ( TF2_HasBomb( iClient ) )
    {
        LogServer( "%N has the bomb. Instructing them to deploy it...", iClient );

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
        LogServer( "%N does't have the bomb. Instructing them to do something else...", iClient );

        int iLeader = GetLeader( GetSquad( iBot ) );
        if ( IsPlayerIndex( iLeader ) && IsClientInGame( iLeader ) && IsPlayerAlive( iLeader ) && iLeader != iClient )
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
            if ( HasTag( iBot, "bot_gatebot" ) )
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
                    if ( IsPlayerIndex( moveparent ) )
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

    g_aAttributes[ iClient ].flNextInstructionTime = GetGameTime() + 30.0; // TODO: make CVar for this
}

public void Event_FlagEvent( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int iClient    = hEvent.GetInt( "player" );
    int iEventType = hEvent.GetInt( "eventtype" );

    if ( !IsPlayerIndex( iClient ) || !IsClientInGame( iClient ) || iEventType == TF_FLAGEVENT_DEFENDED )
    {
        return;
    }

    if ( iEventType == TF_FLAGEVENT_PICKEDUP )
    {
        if ( !IsFakeClient( iClient ) )
        {
            if ( IsMiniBoss( iClient ) )   // Giants have max flag level and can't receive buffs
            {
                g_aiFlagCarrierUpgradeLevel[ iClient ] = 4;
                g_aflNextBombUpgradeTime[ iClient ]    = GetGameTime();
            }
            else if ( g_aiFlagCarrierUpgradeLevel[ iClient ] == 0 )  // Start upgrading from the beginning
            {
                g_aflNextBombUpgradeTime[ iClient ] = GetGameTime() + FindConVar( "tf_mvm_bot_flag_carrier_interval_to_1st_upgrade" ).FloatValue;
            }
            else if ( !IsMiniBoss( iClient ) ) // Add existing buffs
            {
                if ( g_aiFlagCarrierUpgradeLevel[ iClient ] >= 1 )
                {
                    TF2_AddCondition( iClient, TFCond_DefenseBuffNoCritBlock );
                }
                if ( g_aiFlagCarrierUpgradeLevel[ iClient ] == 3 )
                {
                    TF2_AddCondition( iClient, TFCond_CritOnWin );
                }
            }

            RequestFrame( UpdateBombHud, GetClientSerial( iClient ) );
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

        g_aiFlagCarrierUpgradeLevel[ iClient ] = 0;
        g_aflNextBombUpgradeTime[ iClient ]    = GetGameTime();
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

public void UpdateBombHud( int iClientSerial )
{
    int iClient = GetClientFromSerial( iClientSerial );
    if ( iClient == 0 )
    {
        return;
    }

    int iResource = FindEntityByClassname( -1, "tf_objective_resource" );
    SetEntProp( iResource, Prop_Send, "m_nFlagCarrierUpgradeLevel", g_aiFlagCarrierUpgradeLevel[ iClient ] );

    float vecOrigin[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );

    bool bInSpawn = TF2Util_IsPointInRespawnRoom( vecOrigin, iClient, true );
    SetEntPropFloat( iResource, Prop_Send, "m_flMvMBaseBombUpgradeTime", bInSpawn ? -1.0 : GetGameTime() );
    SetEntPropFloat( iResource, Prop_Send, "m_flMvMNextBombUpgradeTime", bInSpawn ? -1.0 : g_aflNextBombUpgradeTime[ iClient ] );
}

public void Event_ResetBots( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    for ( int iClient = 1; iClient <= MaxClients; iClient++ )
    {
        if (
            !IsClientInGame( iClient ) ||
            IsFakeClient( iClient )    ||
            !g_aAttributes[ iClient ].IsControlling()
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

    if ( !IsPlayerIndex( iClient ) || !IsClientInGame( iClient ) )
    {
        return;
    }

    if ( !IsFakeClient( iClient ) )
    {
        if ( g_aAttributes[ iClient ].bSkipInventory )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

            g_aAttributes[ iClient ].bSkipInventory = false;
        }
    }

    bool bTeleportToHint;
    if ( IsFakeClient( iClient ) )
    {
        bTeleportToHint = HasAttribute( iClient, TELEPORT_TO_HINT );
    }
    else
    {
        bTeleportToHint = HasAttribute( GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial ), TELEPORT_TO_HINT );
    }

    if ( TF2_GetClientTeam( iClient ) == TF_TEAM_PVE_INVADERS && TF2_GetPlayerClass( iClient ) != TFClass_Spy && bTeleportToHint )
    {
        int iTeleporter = TF2_FindTeleNearestToBombHole();
        if ( iTeleporter == -1 )
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
        if ( IsPlayerIndex( iBuilder ) && IsClientInGame( iBuilder ) && !IsFakeClient( iBuilder ) )
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

    int iClient = hEvent.GetInt( "victim_entindex" );

    if ( IsFakeClient( iClient ) && g_aAttributes[ iClient ].IsControlled() )
    {
        bDontBroadcast                         = true;
        g_aAttributes[ iClient ].bBlockRagdoll = true;
        g_aAttributes[ iClient ].iPlayerSerial = 0;

        Result = Plugin_Changed;
    }

    SetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar", false );
    TF2_StopSounds( iClient );

    char szWeapon[ 64 ];
    hEvent.GetString( "weapon", szWeapon, sizeof( szWeapon ) );

    bool bSuicide = StrEqual( szWeapon, "world" ) && hEvent.GetInt( "weaponid" ) == 0 && hEvent.GetInt( "customkill" ) == 6;

    if ( !bSuicide && !IsFakeClient( iClient ) && g_aAttributes[ iClient ].IsControlling() )
    {
        int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
        if ( iBot != 0 )
        {
            if ( IsSentryBuster( iClient ) )
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

    g_aAttributes[ iClient ].iBotSerial = 0;

    return Result;
}

public Action Event_PlayerTeam( Event hEvent, const char[] szName, bool bDontBroadcast )
{
    int    iClient  = GetClientOfUserId( hEvent.GetInt( "userid" ) );
    TFTeam eTeam    = view_as< TFTeam >( hEvent.GetInt( "team" ) );
    TFTeam eOldTeam = view_as< TFTeam >( hEvent.GetInt( "oldteam" ) );

    if ( eTeam == TFTeam_Spectator )
    {
        if ( g_aAttributes[ iClient ].IsControlling() )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
            TF2_RespawnPlayer( iClient );   // No gibs/ragdoll

            g_aAttributes[ iClient ].flCooldownEndTime = GetGameTime() + 10.0;
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

    if ( !IsFakeClient( iClient ) && g_aAttributes[ iClient ].IsControlling() && TF2_GetPlayerClass( iClient ) == TFClass_Engineer )
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
            DispatchKeyValueInt( iEnt, "defaultupgrade", 2 );
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

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: Listener_Build

  Summary:  This hook function prevents human invader engineers
            from building teleporter entrances or from building
            any buildings at all depending on if the bot has an
            existing `m_teleportWhereName` and if the map has a
            `bot_hint_teleporter_exit` entity.

  Args:     int iClient
              Index of client that initiated a "build" command.
            char[] szCommand
              Command name, lowercase. To get name as typed by
              the client, use GetCmdArg() and set `argnum` to `0`.
            int argc
              Argument count.

  Returns:  MyReturnType
              Description.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public Action Listener_Build( int iClient, char[] szCommand, int argc )
{
    // Must be alive, in the game, and controlling a bot
    if ( !IsClientInGame( iClient ) || !g_aAttributes[ iClient ].IsControlling() || !IsPlayerAlive( iClient ) )
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

    TFObjectType eObjectType = view_as< TFObjectType >( GetCmdArgInt( 1 ) );
    TFObjectMode eObjectMode = view_as< TFObjectMode >( GetCmdArgInt( 2 ) );

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
    if ( eObjectType == TFObject_Teleporter && !CanBuildTeleporterExit( iClient ) )
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

/*F+F+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Function: IsAllowedToBuildTeleporter

  Summary:  This function determines if a human invader engineer is
            allowed to build a teleporter exit. This is determined
            from the controlled bot's `m_teleportWhereName` member
            variable and if the map has a "bot_hint_teleporter_exit"
            entity.

  Args:     int iClient
              Human client index.

  Returns:  bool
              `true` if the client can build a teleporter exit.
              `false` otherwise.
-----------------------------------------------------------------F-F*/
stock bool CanBuildTeleporterExit( int iClient )
{
    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
    if ( iBot == 0 )
    {
        return false;
    }

    return view_as< Address >( GetEntData( iBot, g_teleportWhereName_Offset ) ) != Address_Null &&
           FindEntityByClassname( MAXPLAYERS + 1, "bot_hint_teleporter_exit" ) != -1;
}

int g_iLastHealer = -1;

public MRESReturn CTFBotMedicHeal_SelectPatient( DHookReturn hReturn, DHookParam hParams )
{
    g_iLastHealer = !hParams.IsNull( 1 ) ? hParams.Get( 1 ) : -1;
    return MRES_Ignored;
}

public MRESReturn CTFBotMedicHeal_SelectPatient_Post( DHookReturn hReturn, DHookParam hParams )
{
    if ( g_iLastHealer != -1 )
    {
        if ( IsInASquad( g_iLastHealer ) )
        {
            int iLeader = GetLeader( GetSquad( g_iLastHealer ) );
            if ( IsPlayerIndex( iLeader ) && IsClientInGame( iLeader ) && g_aAttributes[ iLeader ].IsControlled() )
            {
                hReturn.Value = g_aAttributes[ iLeader ].iPlayerSerial;
                return MRES_Supercede;
            }
        }
    }

    return MRES_Ignored;
}

int g_iLastMedigun       = -1;
int g_iLastMedigunTarget = -1;

public MRESReturn CWeaponMedigun_IsAllowedToHealTarget( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    g_iLastMedigun       = iThis;
    g_iLastMedigunTarget = !hParams.IsNull( 1 ) ? hParams.Get( 1 ) : -1;

    return MRES_Ignored;
}

public MRESReturn CWeaponMedigun_IsAllowedToHealTarget_Post( int iThis, DHookReturn hReturn, DHookParam hParams )
{
    int iOwner = TF2_GetEntityOwner( g_iLastMedigun );

    // Controlled bots aren't allowed to heal
    if ( IsFakeClient( iOwner ) && g_aAttributes[ iOwner ].IsControlled() )
    {
        hReturn.Value = false;
        return MRES_Supercede;
    }

    if ( !IsFakeClient( iOwner ) && g_aAttributes[ iOwner ].IsControlling() )
    {
        int iBot = GetClientFromSerial( g_aAttributes[ iOwner ].iBotSerial );
        if ( IsPlayerIndex( iBot ) && IsPlayerAlive( iBot ) )
        {
            int iLeader = GetLeader( GetSquad( iBot ) );
            // If the player is controlling the squad leader then we don't need to restrict their heal target
            if ( IsPlayerIndex( iLeader ) && IsClientInGame( iLeader ) && IsPlayerAlive( iLeader ) && iLeader != iBot )
            {
                hReturn.Value = ( g_iLastMedigunTarget == iLeader );
                return MRES_Supercede;
            }
        }
    }

    return MRES_Ignored;
}

stock int TF2_GetObjectCount( int iBuilder, TFObjectType eObjectType )
{
    int iObject = -1, iCount = 0;
    while ( ( iObject = FindEntityByClassname( iObject, "obj_*" ) ) != -1 )
    {
        if ( TF2_GetObjectBuilder( iObject  ) == iBuilder && TF2_GetObjectType( iObject ) == eObjectType )
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
        if ( !IsSentryBuster( iClient ) )
        {
            TF2_RestoreBot( iClient );
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );
            TF2_RespawnPlayer( iClient );   // No gibs/ragdoll

            g_aAttributes[ iClient ].flCooldownEndTime = GetGameTime() + 10.0;
        }
        else if ( IsSentryBuster( iClient ) && GetEntPropEnt( iClient, Prop_Send, "m_hGroundEntity" ) != -1 )
        {
            TF2_RestoreBot( iClient );
            TF2_RespawnPlayer( iClient );   // No gibs/ragdoll
            TF2_ChangeClientTeam( iClient, TFTeam_Spectator );

            g_aAttributes[ iClient ].flCooldownEndTime = GetGameTime() + 10.0;
        }
    }

    return Plugin_Continue;
}

public Action Listener_Voice( int iClient, char[] szCommand, int argc )
{
    if ( IsClientInGame( iClient ) && TF2_GetClientTeam( iClient ) == TFTeam_Spectator && TF2_ObservedIsValidClient( iClient ) && !g_aAttributes[ iClient ].IsControlling() )
    {
        char szArgs[ 4 ];
        GetCmdArgString( szArgs, sizeof( szArgs ) );

        if ( StrEqual( szArgs, "0 0" ) )
        {
            if ( g_aAttributes[ iClient ].flCooldownEndTime <= GetGameTime() )
            {
                int iObserverTarget = GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );
                PlayerMirrorBot( iClient, iObserverTarget );
                PrintColoredChatAll( COLOR_GRAY ... "%N" ... COLOR_DEFAULT ... " is now playing as " ... COLOR_BLUE ... "%N", iClient, iObserverTarget );
            }
            else
            {
                float flCooldown = g_aAttributes[ iClient ].flCooldownEndTime - GetGameTime();
                PrintColoredChat( iClient, COLOR_RED ... "Cannot play as a bot for %.0f more seconds", flCooldown );
            }
        }
    }

    return Plugin_Continue;
}

/*F+F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F+++F
  Function: IsIgnored

  Summary:  This function determines whether an entity should be
            hidden from controlling players. It matches a CTFBot's
            behavior according to functions `CTFBotVision::IsIgnored`
            and `CTFBotVision::IsVisibleEntityNoticed`.

  Args:     int iEntity
              Entity index which should or should not be transmitted.
            int iClient
              Client index to which `iEntity` should or should not
              be transmitted.

  Returns:  Action
              Specifies what to do after a hook completes.
F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F---F-F*/
public Action IsIgnored( int iEntity, int iClient )
{
#define TRUE  Plugin_Handled
#define FALSE Plugin_Continue
    // we only care about human invaders
    if ( !g_aAttributes[ iClient ].IsControlling() )
    {
        return FALSE;
    }

    if ( !TF2_IsEnemyTeam(
                          TF2_GetClientTeam( iClient ),
                          view_as< TFTeam >( GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) )
                          ) )
    {
        // don't ignore friends
        return FALSE;
    }

    if ( IsPlayerIndex( iEntity ) )
    {
        // test for designer-defined ignorance
        switch ( TF2_GetPlayerClass( iEntity ) )
        {
        case TFClass_Medic:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_MEDICS ) )
            {
                return TRUE;
            }

        case TFClass_Engineer:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_ENGINEERS ) )
            {
                return TRUE;
            }

        case TFClass_Sniper:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_SNIPERS ) )
            {
                return TRUE;
            }

        case TFClass_Scout:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_SCOUTS ) )
            {
                return TRUE;
            }

        case TFClass_Spy:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_SPIES ) )
            {
                return TRUE;
            }

        case TFClass_DemoMan:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_DEMOMEN ) )
            {
                return TRUE;
            }

        case TFClass_Soldier:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_SOLDIERS ) )
            {
                return TRUE;
            }

        case TFClass_Heavy:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_HEAVIES ) )
            {
                return TRUE;
            }

        case TFClass_Pyro:
            if ( IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_PYROS ) )
            {
                return TRUE;
            }
        }

        if ( TF2_IsPlayerInCondition( iEntity, TFCond_OnFire )       ||
             TF2_IsPlayerInCondition( iEntity, TFCond_Jarated )      ||
             TF2_IsPlayerInCondition( iEntity, TFCond_CloakFlicker ) ||
             TF2_IsPlayerInCondition( iEntity, TFCond_Bleeding ) )
        {
            // always notice players with these conditions
            return FALSE;
        }

        // An upgrade in MvM grants AE stealth where the player can fire
		// while in stealth, and for a short period after it drops
        if ( TF2_IsPlayerInCondition( iEntity, TFCond_StealthedUserBuffFade ) )
        {
            return TRUE;
        }

        if ( IsStealthed( iEntity ) && GetPercentInvisible( iEntity ) < 0.75 )
        {
            // spy is partially cloaked, and therefore attracts our attention
            return FALSE;
        }

        // According to `CTFBotVision::IsVisibleEntityNoticed` we should ignore them
        /*if ( IsPlacingSapper( iEntity ) )
        {
            return FALSE;
        }*/

        if ( TF2_IsPlayerInCondition( iEntity, TFCond_Disguising ) )
        {
            return FALSE;
        }

        if ( TF2_IsPlayerInCondition( iEntity, TFCond_Disguised ) && TF2_GetClientDisguiseTeam( iEntity ) == TF2_GetClientTeam( iClient ) )
        {
            // spy is disguised as a member of my team
            return TRUE;
        }
    }
    else
    {
        if ( TF2_GetObjectType( iEntity ) == TFObject_Teleporter )
        {
            return TRUE;
        }

        if ( TF2_GetObjectType( iEntity ) == TFObject_Sentry && IsBehaviorFlagSet( iClient, TFBOT_IGNORE_ENEMY_SENTRY_GUNS ) )
        {
            return TRUE;
        }
    }

    return FALSE;
#undef TRUE
#undef FALSE
}

stock bool IsStealthed( int iClient )
{
    return SDKCall( g_hfnIsStealthed, iClient );
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
    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
    if ( iBot != 0 && IsFakeClient( iBot ) )
    {
        float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
        GetClientAbsOrigin( iClient, vecOrigin );
        GetClientEyeAngles( iClient, angEyeAngles );
        GetEntPropVector( iClient, Prop_Data, "m_vecVelocity", vecVelocity );

        if ( TF2_HasBomb( iClient ) )
        {
            int iBomb = TF2_DropBomb( iClient );
            if ( iBomb != -1 )
            {
                SDKCall( g_hfnPickUp, iBomb, iBot, false );
            }
        }

        if ( TF2_GetPlayerClass( iBot ) == TFClass_Engineer )
        {
            TF2_TakeOverBuildings( iClient, iBot );
        }

        if ( IsSentryBuster( iClient ) )
        {
            TF2_DetonateBuster( iClient );
        }

        // Copy medigun data
        if ( TF2_GetPlayerClass( iBot ) == TFClass_Medic )
        {
            int iPlayerMedigun = GetPlayerWeaponSlot( iClient, TFWeaponSlot_Secondary );
            int iBotMedigun    = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Secondary );
            if ( iPlayerMedigun != -1                                       &&
                 iBotMedigun != -1                                          &&
                 TF2Util_GetWeaponID( iPlayerMedigun ) == TF_WEAPON_MEDIGUN &&
                 TF2Util_GetWeaponID( iBotMedigun ) == TF_WEAPON_MEDIGUN )
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

        ResetGlobals( iBot );

        g_aAttributes[ iBot ].bBlockRagdoll = true;
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
            // Don't mirror spawn protection conditions. We manually add and remove these
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
    SetEntProp( iClient, Prop_Send, "m_nBotSkill", -1 );
    SetIsMiniBoss( iClient, false );

    SetVariantString( "" );
    AcceptEntityInput( iClient, "SetCustomModel" );

    TF2Attrib_RemoveAll( iClient );
    TF2Attrib_ClearCache( iClient );

    ResetGlobals( iClient );
}

stock void TF2_KillBot( int iClient, int iAttacker = -1 )
{
    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
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

    if ( IsPlayerIndex( iAttacker ) && iAttacker != iBot )
    {
        // If the bot was controlled, and killed by a red sniper, this will fix the money not being auto-distribued
        iWeapon = TF2_GetClientActiveWeapon( iAttacker );

        if ( iWeapon != -1 )
        {
            iWeapon = iAttacker;
        }
    }

    SDKHooks_TakeDamage( iBot, iWeapon, iAttacker, FLT_MAX, _, iWeapon );

    SetEntProp( iBot, Prop_Send, "m_bUseBossHealthBar", false );
    SetIsMiniBoss( iBot, false );

    ResetGlobals( iBot );
}

stock void PlayerMirrorBot( int iPlayer, int iBot )
{
    float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
    GetClientAbsOrigin( iBot, vecOrigin );
    GetClientEyeAngles( iBot, angEyeAngles );
    GetEntPropVector( iBot, Prop_Data, "m_vecVelocity", vecVelocity );

    // Joining the invading team on MvM requires us to have the fakeclient flag set
    SetEntityFlags( iPlayer, GetEntityFlags( iPlayer ) | FL_FAKECLIENT );
    TF2_ChangeClientTeam( iPlayer, TF2_GetClientTeam( iBot ) );
    SetEntityFlags( iPlayer, GetEntityFlags( iPlayer ) & ~FL_FAKECLIENT );

    // We set the class after spawning the player in to avoid setting m_iDesiredPlayerClass
    TF2_RespawnPlayer( iPlayer );
    TF2_RegeneratePlayer( iPlayer );

    if ( TF2_GetPlayerClass( iBot ) != TF2_GetPlayerClass( iPlayer ) )
    {
        /*--------------------------------------------------------------------
          We don't want to make it persistent in case the player wants to
          join denfeders mid-round and continue playing as the class they
          were last playing as.
        --------------------------------------------------------------------*/
        TF2_SetPlayerClass( iPlayer, TF2_GetPlayerClass( iBot ), _, false );
    }

    RemoveAllItems( iPlayer );
    TF2Attrib_RemoveAll( iPlayer );

    // New hot technology
    g_aAttributes[ iPlayer ].flControlEndTime      = GetGameTime() + 35.0;
    g_aAttributes[ iPlayer ].flNextInstructionTime = GetGameTime() + 3.0;

    // FIXME: Player ends up with 1 HP less than they should due
    // to `m_iMaxHealth` not being updated as fast as `m_iHealth`

    // Set health
    CopyEntProp( iBot, iPlayer, Prop_Data, "m_iMaxHealth" );
    CopyEntProp( iBot, iPlayer, Prop_Send, "m_iHealth" );

    // Set model
    char szModelName[ PLATFORM_MAX_PATH ];
    GetEntPropString( iBot, Prop_Data, "m_ModelName", szModelName, PLATFORM_MAX_PATH );
    SetVariantString( szModelName );
    AcceptEntityInput( iPlayer, "SetCustomModelWithClassAnimations" );

    // Set ModelScale
    float vecScale[ 3 ] = { 0.0, ... };
    vecScale[ 0 ] = GetEntPropFloat( iBot, Prop_Send, "m_flModelScale" );
    SetVariantVector3D( vecScale );
    AcceptEntityInput( iPlayer, "SetModelScale" );

    // Is target sentry buster?
    if ( IsSentryBuster( iBot ) )
    {
        // SDKCall( g_hfnSetMission, iRobot, NO_MISSION, false );

        TF2Attrib_SetByName( iPlayer, "cannot pick up intelligence", 1.0 );

        // A little delay
        SetEntPropFloat( iPlayer, Prop_Send, "m_flStealthNoAttackExpire", GetGameTime() + 1.25 );
    }

    // Get & Set some props
    CopyEntPropFloat( iBot, iPlayer, Prop_Send, "m_flRageMeter" );
    CopyEntProp( iBot, iPlayer, Prop_Send, "m_nNumHealers" );
    SetEntProp( iPlayer, Prop_Send, "m_bIsABot", true );
    CopyEntProp( iBot, iPlayer, Prop_Send, "m_nBotSkill" ); // Sets the robot eye glow color
    CopyEntProp( iBot, iPlayer, Prop_Send, "m_bIsMiniBoss" );
    /*--------------------------------------------------------------------
      This can be either `BLOOD_COLOR_MECH` or `BLOOD_COLOR_RED`
      depending on whether Halloween mode is on or off, so we can't
      hardcode it.
    --------------------------------------------------------------------*/
    CopyEntProp( iBot, iPlayer, Prop_Data, "m_bloodColor" );

    // Set gatebot on player if target is gatebot
    if ( HasTag( iBot, "bot_gatebot" ) )
    {
        TF2Attrib_SetByName( iPlayer, "cannot pick up intelligence", 1.0 );
    }

    // Engineers can't carry buildings
    if ( TF2_GetPlayerClass( iBot ) == TFClass_Engineer )
    {
        TF2_TakeOverBuildings( iBot, iPlayer );
        TF2Attrib_SetByName( iPlayer, "cannot pick up buildings", 1.0 );
    }

    /*--------------------------------------------------------------------
      Only checking for the `TFCond_Zoomed` condition should not cause
      a crash unless some other plugin applies this condition on a bot
      that's not a Sniper for some reason.
    --------------------------------------------------------------------*/
    if ( TF2_IsPlayerInCondition( iBot, TFCond_Zoomed ) )
    {
        // Zoom out of the sniper rifle so the lazer disappears and doesn't cause problems
        SDKCall( g_hfnZoomOut, TF2_GetClientActiveWeapon( iBot ) );
    }

    // Start the engines
    if ( IsMiniBoss( iBot ) )
    {
        if ( IsSentryBuster( iPlayer ) )
        {
            EmitSoundToAll( "MVM.SentryBusterLoop", iPlayer );
        }
        else
        {
            switch ( TF2_GetPlayerClass( iBot ) )
            {
                case TFClass_Scout:   EmitSoundToAll( "MVM.GiantScoutLoop", iPlayer );
                case TFClass_Soldier: EmitSoundToAll( "MVM.GiantSoldierLoop", iPlayer );
                case TFClass_DemoMan: EmitSoundToAll( "MVM.GiantDemomanLoop", iPlayer );
                case TFClass_Heavy:   EmitSoundToAll( "MVM.GiantHeavyLoop", iPlayer );
                case TFClass_Pyro:    EmitSoundToAll( "MVM.GiantPyroLoop", iPlayer );
            }
        }
    }

    TF2_RemoveAllConditions( iPlayer );

    // Fix some bugs...
    TF2_RemoveCondition( iPlayer, TFCond_Zoomed );
    TF2_RemoveCondition( iPlayer, TFCond_Slowed );

    // Mirror conditions
    TF2_MirrorConditions( iBot, iPlayer );

    if ( IsInASquad( iBot ) )
    {
        Address pSquad  = GetSquad( iBot );
        int     iLeader = GetLeader( pSquad );

        // Everyone but medics leave the robot's squad
        for ( int i = 1; i <= MaxClients; i++ )
        {
            if ( !IsClientInGame( i ) || !IsFakeClient( i ) || i == iBot || i == iLeader )
            {
                continue;
            }

            if ( TF2_GetPlayerClass( i ) != TFClass_Medic )
            {
                if ( GetSquad( i ) == pSquad )
                {
                    SDKCall( g_hfnLeaveSquad, i );
                }
            }
        }
    }

    if ( HasAttribute( iBot, ALWAYS_FIRE_WEAPON ) )
    {
        // Fix client visuals
        SetEntProp( iPlayer, Prop_Data, "m_bPredictWeapons", false );
    }
    if ( HasAttribute( iBot, IGNORE_FLAG ) )
    {
        TF2Attrib_SetByName( iPlayer, "cannot pick up intelligence", 1.0 );
    }
    if ( HasAttribute( iBot, ALWAYS_CRIT ) )
    {
        TF2_AddCondition( iPlayer, TFCond_CritCanteen );
    }
    if ( HasAttribute( iBot, BULLET_IMMUNE ) )
    {
        TF2_AddCondition( iPlayer, TFCond_BulletImmune );
    }
    if ( HasAttribute( iBot, BLAST_IMMUNE ) )
    {
        TF2_AddCondition( iPlayer, TFCond_BlastImmune );
    }
    if ( HasAttribute( iBot, FIRE_IMMUNE ) )
    {
        TF2_AddCondition( iPlayer, TFCond_FireImmune );
    }

    // Teleport player to bots position
    SetEntityMoveType( iBot, MOVETYPE_NONE );
    TeleportEntity( iPlayer, vecOrigin, angEyeAngles, vecVelocity );

    TeleportEntity( iBot, { 0.0, 0.0, 9999.0 }, NULL_VECTOR, NULL_VECTOR );

    g_aAttributes[ iPlayer ].iBotSerial     = GetClientSerial( iBot );
    g_aAttributes[ iBot ].iPlayerSerial     = GetClientSerial( iPlayer );
    g_aAttributes[ iPlayer ].bSkipInventory = true;

    // Delay a frame or two to replace the players weapons.
    CreateTimer( 0.1, Timer_ReplaceWeapons, GetClientSerial( iPlayer ), TIMER_FLAG_NO_MAPCHANGE );
}

stock void RemoveAllItems( int iClient )
{
#if defined( WIN32 )
    // Nuke items
    TF2_RemoveAllWeapons( iClient );

    // Nuke wearables
    for ( int i = TF2Util_GetPlayerWearableCount( iClient ) - 1; i >= 0; i-- )
    {
        int iWearable = TF2Util_GetPlayerWearable( iClient, i );
        if ( iWearable == -1 )
        {
            continue;
        }

        TF2_RemoveWearable( iClient, iWearable );
    }
#else
    SDKCall( g_hfnRemoveAllItems, iClient );
#endif
}

public Action Timer_ReplaceWeapons( Handle hTimer, int iClientSerial )
{
    // Check to see if the player is valid and is still controlling bot
    int iPlayer = GetClientFromSerial( iClientSerial );
    if ( iPlayer == 0 || !IsClientInGame( iPlayer ) )
    {
        return Plugin_Handled;
    }

    LogServer( "Trying to replace weapons for %N.", iPlayer );

    if ( !g_aAttributes[ iPlayer ].IsControlling() )
    {
        return Plugin_Handled;
    }

    if ( !IsPlayerAlive( iPlayer ) )
    {
        return Plugin_Handled;
    }

    int iBot = GetClientFromSerial( g_aAttributes[ iPlayer ].iBotSerial );
    if ( iBot == 0 )
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
        LogServer( "%N has the bomb. Making them drop it...", iBot );
        int iBomb = TF2_DropBomb( iBot );
        if ( iBomb != -1 )
        {
            LogServer( "%N dropped the bomb. Making %N pick it up...", iBot, iPlayer );
            SDKCall( g_hfnPickUp, iBomb, iPlayer, false );
            LogServer( "Forced %N to pick up the bomb.", iPlayer );

            // Copy bomb carrier upgrade level
            int iResource = FindEntityByClassname( -1, "tf_objective_resource" );
            g_aiFlagCarrierUpgradeLevel[ iPlayer ] = GetEntProp( iResource, Prop_Send, "m_nFlagCarrierUpgradeLevel" );
            g_aflNextBombUpgradeTime[ iPlayer ]    = GetEntPropFloat( iResource, Prop_Send, "m_flMvMNextBombUpgradeTime" );
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

        if ( iBotMedigun != -1                                       &&
             iPlayerMedigun != -1                                    &&
             TF2Util_GetWeaponID( iBotMedigun ) == TF_WEAPON_MEDIGUN &&
             TF2Util_GetWeaponID( iPlayerMedigun ) == TF_WEAPON_MEDIGUN )
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
            if ( IsPlayerIndex( iDisguiseTarget ) && IsClientInGame( iDisguiseTarget ) )
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
    float   aflValues[ 20 ];
    Address pAttribute;
    int     iBotWeapon = -1;

    // This is stupid, but it's how TF2 itself does it
    if ( HasWeaponRestriction( iBot, MELEE_ONLY ) )
    {
        iBotWeapon = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Melee );
    }
    else if ( HasWeaponRestriction( iBot, PRIMARY_ONLY ) )
    {
        iBotWeapon = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Primary );
    }
    else if ( HasWeaponRestriction( iBot, SECONDARY_ONLY ) )
    {
        iBotWeapon = GetPlayerWeaponSlot( iBot, TFWeaponSlot_Secondary );
    }

    if ( iBotWeapon == -1 )
    {
        for ( int iSlot = 0; iSlot <= TFWeaponSlot_PDA; iSlot++ )
        {
            iBotWeapon = GetPlayerWeaponSlot( iBot, iSlot );
            if ( iBotWeapon != -1 )
            {
                char szClassname[ 64 ];
                GetEntityClassname( iBotWeapon, szClassname, sizeof( szClassname ) );

                int iItemDefinitionIndex = GetEntProp( iBotWeapon, Prop_Send, "m_iItemDefinitionIndex" );

                int nAttributes = TF2Attrib_ListDefIndices( iBotWeapon, aiAttributes );
                for ( int i = 0; i < nAttributes; i++ )
                {
                    pAttribute     = TF2Attrib_GetByDefIndex( iBotWeapon, aiAttributes[ i ] );
                    aflValues[ i ] = TF2Attrib_GetValue( pAttribute );
                }

                int iPlayerWeapon = GiveItem(
                                             iPlayer,
                                             iItemDefinitionIndex,
                                             szClassname,
                                             sizeof( szClassname ),
                                             nAttributes,
                                             aiAttributes,
                                             aflValues,
                                             TF2_GetClientActiveWeapon( iBot ) == iBotWeapon
                                            );

                TF2_SetWeaponAmmo( iPlayerWeapon, TF2_GetWeaponAmmo( iBotWeapon ) );
            }
        }
    }
    else
    {
        // Mirror unrestricted weapon + utility weapons
        if ( iBotWeapon != -1 )
        {
            char szClassname[ 64 ];
            GetEntityClassname( iBotWeapon, szClassname, sizeof( szClassname ) );

            int iItemDefinitionIndex = GetEntProp( iBotWeapon, Prop_Send, "m_iItemDefinitionIndex" );

            int nAttributes = TF2Attrib_ListDefIndices( iBotWeapon, aiAttributes );
            for ( int i = 0; i < nAttributes; i++ )
            {
                pAttribute     = TF2Attrib_GetByDefIndex( iBotWeapon, aiAttributes[ i ] );
                aflValues[ i ] = TF2Attrib_GetValue( pAttribute );
            }

            int iPlayerWeapon = GiveItem(
                                         iPlayer,
                                         iItemDefinitionIndex,
                                         szClassname,
                                         sizeof( szClassname ),
                                         nAttributes,
                                         aiAttributes,
                                         aflValues,
                                         TF2_GetClientActiveWeapon( iBot ) == iBotWeapon
                                        );

            TF2_SetWeaponAmmo( iPlayerWeapon, TF2_GetWeaponAmmo( iBotWeapon ) );
        }

        // Always mirror the "utility" weapons
        for ( int iSlot = TFWeaponSlot_Grenade; iSlot <= TFWeaponSlot_PDA; iSlot++ )
        {
            iBotWeapon = GetPlayerWeaponSlot( iBot, iSlot );

            if ( iBotWeapon != -1 )
            {
                char szClassname[ 64 ];
                GetEntityClassname( iBotWeapon, szClassname, sizeof( szClassname ) );

                int iItemDefinitionIndex = GetEntProp( iBotWeapon, Prop_Send, "m_iItemDefinitionIndex" );

                int nAttributes = TF2Attrib_ListDefIndices( iBotWeapon, aiAttributes );
                for ( int i = 0; i < nAttributes; i++ )
                {
                    pAttribute     = TF2Attrib_GetByDefIndex( iBotWeapon, aiAttributes[ i ] );
                    aflValues[ i ] = TF2Attrib_GetValue( pAttribute );
                }

                GiveItem(
                         iPlayer,
                         iItemDefinitionIndex,
                         szClassname,
                         sizeof( szClassname ),
                         nAttributes,
                         aiAttributes,
                         aflValues,
                         TF2_GetClientActiveWeapon( iBot ) == iBotWeapon
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
            pAttribute     = TF2Attrib_GetByDefIndex( iWearable, aiAttributes[ i ] );
            aflValues[ i ] = TF2Attrib_GetValue( pAttribute );
        }

        GiveItem(
                 iPlayer,
                 iItemDefinitionIndex,
                 szClassname,
                 sizeof( szClassname ),
                 nAttirbutes,
                 aiAttributes,
                 aflValues,
                 false
                );
    }

    // Mirror player attributes
    int nAttributes = TF2Attrib_ListDefIndices( iBot, aiAttributes );
    for ( int i = 0; i < nAttributes; i++ )
    {
        pAttribute           = TF2Attrib_GetByDefIndex( iBot, aiAttributes[ i ] );
        aflValues[ i ] = TF2Attrib_GetValue( pAttribute );

        TF2Attrib_SetByDefIndex( iPlayer, aiAttributes[ i ], aflValues[ i ] );
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

stock bool IsMiniBoss( int iClient )
{
    return view_as< bool >( GetEntProp( iClient, Prop_Send, "m_bIsMiniBoss" ) );
}

stock void SetIsMiniBoss( int iClient, bool bIsMiniBoss )
{
    SetEntProp( iClient, Prop_Send, "m_bIsMiniBoss", bIsMiniBoss );
}

stock bool TF2_HasBomb( int iClient )
{
    int iBomb = GetEntPropEnt( iClient, Prop_Send, "m_hItem" );
    return iBomb != -1 && GetEntPropEnt( iBomb, Prop_Send, "moveparent" ) == iClient;
}

stock int TF2_DropBomb( int iClient )
{
    int iBomb = GetEntPropEnt( iClient, Prop_Send, "m_hItem" );
    SDKCall( g_hfnDrop, iBomb, iClient, true, true, false );

    return iBomb;
}

stock bool HasTag( int iClient, const char[] szTag )
{
    if ( IsFakeClient( iClient ) )
    {
        return SDKCall( g_hfnHasTag, iClient, szTag );
    }
    else
    {
        int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
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
        int iObserverTarget = GetEntPropEnt( iObserver, Prop_Send, "m_hObserverTarget" );
        if (
            IsPlayerIndex( iObserverTarget )  &&
            IsClientInGame( iObserverTarget ) &&
            IsFakeClient( iObserverTarget )   &&
            IsPlayerAlive( iObserverTarget )  &&
            !g_aAttributes[ iObserverTarget ].IsControlled()
            )
        {
            if ( !TF2_IsPlayerInCondition( iObserverTarget, TFCond_MVMBotRadiowave ) && !TF2_IsPlayerInCondition( iObserverTarget, TFCond_Taunting ) )
            {
                if ( GetEntProp( iObserverTarget, Prop_Data, "m_takedamage" ) != DAMAGE_NO )
                {
                    float flTimeSinceSpawn = GetGameTime() - GetSpawnTime( iObserverTarget );
                    if ( TF2_GetPlayerClass( iObserverTarget ) != TFClass_Spy && flTimeSinceSpawn >= 1.0 )  // Allow the bots some time to spawn
                    {
                        return true;
                    }
                    else if ( TF2_GetPlayerClass( iObserverTarget ) == TFClass_Spy && flTimeSinceSpawn >= 5.0 ) // Spies need extra time to teleport
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
    int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
    if ( iBot == 0 || !IsFakeClient( iBot ) )
    {
        return;
    }

    TF2_StopSounds( iClient );

    float vecOrigin[ 3 ], angEyeAngles[ 3 ], vecVelocity[ 3 ];
    GetClientAbsOrigin( iClient, vecOrigin );
    GetClientEyeAngles( iClient, angEyeAngles );
    GetEntPropVector( iClient, Prop_Send, "m_vecVelocity", vecVelocity );

    SetEntityMoveType( iBot, MOVETYPE_WALK );
    TeleportEntity( iBot, vecOrigin, angEyeAngles, vecVelocity );

    // SDKCall( g_hfnSetMission, iBot, MISSION_DESTROY_SENTRIES, true );

    SetEntityHealth( iBot, 1 );
    SetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget", iBot );
}

stock int TF2_FindTeleNearestToBombHole()
{
    float vecHatchPos[ 3 ];
    vecHatchPos = TF2_GetBombHatchPosition();

    float flBestDistance = FLT_MAX;
    int   iBestEntity    = -1;

    int iEnt = -1;
    while ( ( iEnt = FindEntityByClassname( iEnt, "obj_teleporter" ) ) != -1 )
    {
        if (
            view_as< TFTeam >( GetEntProp( iEnt, Prop_Send, "m_iTeamNum" ) ) == TF_TEAM_PVE_INVADERS &&
            !HasSapper( iEnt )                                                                       &&
            !GetEntProp( iEnt, Prop_Send, "m_bBuilding" )                                            &&
            !IsPlacing( iEnt )                                                                       &&
            !GetEntProp( iEnt, Prop_Send, "m_bDisabled" )
        )
        {
            float vecTeleporterOrigin[ 3 ];
            GetEntPropVector( iEnt, Prop_Send, "m_vecOrigin", vecTeleporterOrigin );

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
                DispatchKeyValueInt( iObject, "SolidToPlayer", SOLID_TO_PLAYER_USE_DEFAULT );
                SetBuilder( iObject, iTarget );
            }
        }
    }
}

stock void SetBuilder( int iObject, int iClient )
{
    int iBuilder = TF2_GetObjectBuilder( iObject );
    if ( IsPlayerIndex( iBuilder ) && IsClientInGame( iBuilder ) )
    {
        SDKCall( g_hfnRemoveObject, iBuilder, iObject );
    }

    SetEntPropEnt( iObject, Prop_Send, "m_hBuilder", -1 );
    AcceptEntityInput( iObject, "SetBuilder", iClient );
}

stock bool IsValidBuilding( int iBuilding )
{
    return iBuilding != -1 && !IsPlacing( iBuilding ) && !IsCarried( iBuilding );
}

public int GiveItem(
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

    if ( iItem == -1 )
    {
        LogError( "Unable to give item '%d' for %N. Skipping...", iItemDefinitionIndex, iClient );
        return -1;
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

    if ( TF2Util_IsEntityWeapon( iItem ) )
    {
        EquipPlayerWeapon( iClient, iItem );

        if ( bSetActive )
        {
            TF2Util_SetPlayerActiveWeapon( iClient, iItem );
        }
    }
    else
    {
        TF2Util_EquipPlayerWearable( iClient, iItem );
    }

    return iItem;
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

stock bool IsSentryBuster( int iClient )
{
    if ( IsFakeClient( iClient ) )
    {
        return GetMission( iClient ) == MISSION_DESTROY_SENTRIES;
    }
    else
    {
        return GetMission( GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial ) ) == MISSION_DESTROY_SENTRIES;
    }
}

stock bool IsPlayerIndex( int i )
{
    return 0 < i <= MaxClients;
}

stock bool IsMannVsMachineMode()
{
    return view_as< bool >( GameRules_GetProp( "m_bPlayingMannVsMachine" ) );
}

stock bool HasSapper( int iObject )
{
    return view_as< bool >( GetEntProp( iObject, Prop_Send, "m_bHasSapper" ) );
}

stock bool IsPlacing( int iObject )
{
    return view_as< bool >( GetEntProp( iObject, Prop_Send, "m_bPlacing" ) );
}

stock bool IsCarried( int iObject )
{
    return view_as< bool >( GetEntProp( iObject, Prop_Send, "m_bCarried" ) );
}

stock bool HasWeaponRestriction( int iBot, WeaponRestrictionType eRestriction )
{
    return SDKCall( g_hfnHasWeaponRestriction, iBot, view_as< int >( eRestriction ) );
}

stock bool HasAttribute( int iBot, AttributeType eAttribute )
{
    return SDKCall( g_hfnHasAttribute, iBot, view_as< int >( eAttribute ) );
}

stock Address GetSquad( int iBot )
{
    return view_as< Address >( GetEntData( iBot, g_squad_Offset ) );
}

stock bool IsInASquad( int iBot )
{
    return SDKCall( g_hfnIsInASquad, iBot );
}

stock int GetLeader( Address pSquad )
{
#if defined( WIN32 )
    return LoadEntityFromHandleAddress( pSquad + view_as< Address >( g_leader_Offset ) );
#else
    return SDKCall( g_hfnGetLeader, pSquad );
#endif
}

stock MissionType GetMission( int iBot )
{
    return view_as< MissionType >( GetEntData( iBot, g_mission_Offset ) );
}

stock void SetDeployingBombState( int iClient, BombDeployingState_t nDeployingBombState )
{
    SetEntData( iClient, g_nDeployingBombState_Offset, nDeployingBombState );
}

stock BombDeployingState_t GetDeployingBombState( int iClient )
{
    return view_as< BombDeployingState_t >( GetEntData( iClient, g_nDeployingBombState_Offset ) );
}

stock float GetSpawnTime( int iClient )
{
    return GetEntDataFloat( iClient, g_flSpawnTime_Offset );
}

stock bool IsPlacingSapper( int iClient )
{
    return SDKCall( g_hfnIsPlacingSapper, iClient );
}

stock bool IsBehaviorFlagSet( int iClient, int iFlags )
{
    if ( IsFakeClient( iClient ) )
    {
        return SDKCall( g_hfnIsBehaviorFlagSet, iClient, iFlags );
    }
    else
    {
        int iBot = GetClientFromSerial( g_aAttributes[ iClient ].iBotSerial );
        return SDKCall( g_hfnIsBehaviorFlagSet, iBot, iFlags );
    }
}
