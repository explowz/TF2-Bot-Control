/*+===================================================================
  File:    CONST.INC

  Summary: This file contains constants used by the bot control
           plugin.

  Origin:  Created by Bintr on 12.06.2026.
===================================================================+*/

#if defined _botcontrol_const_included
    #endinput
#endif
#define _botcontrol_const_included

#include <sourcemod>
#include <tf2>

#pragma newdecls required
#pragma semicolon 1

#define FLT_MAX 3.402823466e38

#define PTRSIZ              4
#define NumberType_Pointer  NumberType_Int32

#define MAX_ATTRIBUTES_PER_ITEM 20

#define MAXPLAYERS_ARRAY_SAFE   ( MAXPLAYERS + 1 )

#define TF_TEAM_PVE_INVADERS    TFTeam_Blue // invading bot team in mann vs machine
#define TF_TEAM_PVE_DEFENDERS   TFTeam_Red  // defending player team in mann vs machine

#define TF_BOT_TYPE 1337

// For use with some of the CTFBot functions
#define MY_CURRENT_GUN -1

#define TF_DEATH_ANIMATION_TIME 2.0

#define GAME_EVENT_PLAYER_DEATH "player_death"
#define GAME_EVENT_SAY_TEXT     "say_text"

enum TFNavAttributeType
{
    TF_NAV_INVALID                     = 0x00000000,

    // Also look for NAV_MESH_NAV_BLOCKER (w/ nav_debug_blocked ConVar).
    TF_NAV_BLOCKED                     = 0x00000001, // blocked for some TF-specific reason
    TF_NAV_SPAWN_ROOM_RED              = 0x00000002,
    TF_NAV_SPAWN_ROOM_BLUE             = 0x00000004,
    TF_NAV_SPAWN_ROOM_EXIT             = 0x00000008,
    TF_NAV_HAS_AMMO                    = 0x00000010,
    TF_NAV_HAS_HEALTH                  = 0x00000020,
    TF_NAV_CONTROL_POINT               = 0x00000040,

    TF_NAV_BLUE_SENTRY_DANGER          = 0x00000080, // sentry can potentially fire upon enemies in this area
    TF_NAV_RED_SENTRY_DANGER           = 0x00000100,

    TF_NAV_BLUE_SETUP_GATE             = 0x00000800, // this area is blocked until the setup period is over
    TF_NAV_RED_SETUP_GATE              = 0x00001000, // this area is blocked until the setup period is over
    TF_NAV_BLOCKED_AFTER_POINT_CAPTURE = 0x00002000, // this area becomes blocked after the first point is capped
    TF_NAV_BLOCKED_UNTIL_POINT_CAPTURE = 0x00004000, // this area is blocked until the first point is capped, then is unblocked
    TF_NAV_BLUE_ONE_WAY_DOOR           = 0x00008000,
    TF_NAV_RED_ONE_WAY_DOOR            = 0x00010000,

    TF_NAV_WITH_SECOND_POINT           = 0x00020000, // modifier for BLOCKED_*_POINT_CAPTURE
    TF_NAV_WITH_THIRD_POINT            = 0x00040000, // modifier for BLOCKED_*_POINT_CAPTURE
    TF_NAV_WITH_FOURTH_POINT           = 0x00080000, // modifier for BLOCKED_*_POINT_CAPTURE
    TF_NAV_WITH_FIFTH_POINT            = 0x00100000, // modifier for BLOCKED_*_POINT_CAPTURE

    TF_NAV_SNIPER_SPOT                 = 0x00200000, // this is a good place for a sniper to lurk
    TF_NAV_SENTRY_SPOT                 = 0x00400000, // this is a good place to build a sentry

    TF_NAV_ESCAPE_ROUTE                = 0x00800000, // for Raid mode
    TF_NAV_ESCAPE_ROUTE_VISIBLE        = 0x01000000, // all areas that have visibility to the escape route

    TF_NAV_NO_SPAWNING                 = 0x02000000, // don't spawn bots in this area

    TF_NAV_RESCUE_CLOSET               = 0x04000000, // for respawning friends in Raid mode

    TF_NAV_BOMB_CAN_DROP_HERE          = 0x08000000, // the bomb can be dropped here and reached by the invaders in MvM

    TF_NAV_DOOR_NEVER_BLOCKS           = 0x10000000,
    TF_NAV_DOOR_ALWAYS_BLOCKS          = 0x20000000,

    TF_NAV_UNBLOCKABLE                 = 0x40000000, // this area cannot be blocked

    // save/load these manually set flags, and don't clear them between rounds
    TF_NAV_PERSISTENT_ATTRIBUTES       = TF_NAV_SNIPER_SPOT | TF_NAV_SENTRY_SPOT | TF_NAV_NO_SPAWNING | TF_NAV_BLUE_SETUP_GATE | TF_NAV_RED_SETUP_GATE | TF_NAV_BLOCKED_AFTER_POINT_CAPTURE | TF_NAV_BLOCKED_UNTIL_POINT_CAPTURE | TF_NAV_BLUE_ONE_WAY_DOOR | TF_NAV_RED_ONE_WAY_DOOR | TF_NAV_DOOR_NEVER_BLOCKS | TF_NAV_DOOR_ALWAYS_BLOCKS | TF_NAV_UNBLOCKABLE | TF_NAV_WITH_SECOND_POINT | TF_NAV_WITH_THIRD_POINT | TF_NAV_WITH_FOURTH_POINT | TF_NAV_WITH_FIFTH_POINT | TF_NAV_RESCUE_CLOSET
}

// MOVEMENT INFO
enum
{
    PITCH = 0, // up / down
    YAW,       // left / right
    ROLL       // fall over
}

enum Collision_Group_t
{
    COLLISION_GROUP_NONE  = 0,
    COLLISION_GROUP_DEBRIS,             // Collides with nothing but world and static stuff
    COLLISION_GROUP_DEBRIS_TRIGGER,     // Same as debris, but hits triggers
    COLLISION_GROUP_INTERACTIVE_DEBRIS, // Collides with everything except other interactive debris or debris
    COLLISION_GROUP_INTERACTIVE,        // Collides with everything except interactive debris or debris
    COLLISION_GROUP_PLAYER,
    COLLISION_GROUP_BREAKABLE_GLASS,
    COLLISION_GROUP_VEHICLE,
    COLLISION_GROUP_PLAYER_MOVEMENT,    // For HL2, same as Collision_Group_Player, for
                                        // TF2, this filters out other players and CBaseObjects
    COLLISION_GROUP_NPC,                // Generic NPC group
    COLLISION_GROUP_IN_VEHICLE,         // for any entity inside a vehicle
    COLLISION_GROUP_WEAPON,             // for any weapons that need collision detection
    COLLISION_GROUP_VEHICLE_CLIP,       // vehicle clip brush to restrict vehicle movement
    COLLISION_GROUP_PROJECTILE,         // Projectiles!
    COLLISION_GROUP_DOOR_BLOCKER,       // Blocks entities not permitted to get near moving doors
    COLLISION_GROUP_PASSABLE_DOOR,      // Doors that the player shouldn't collide with
    COLLISION_GROUP_DISSOLVING,         // Things that are dissolving are in this group
    COLLISION_GROUP_PUSHAWAY,           // Nonsolid on client and server, pushaway in player code

    COLLISION_GROUP_NPC_ACTOR,          // Used so NPCs in scripts ignore the player.
    COLLISION_GROUP_NPC_SCRIPTED,       // USed for NPCs in scripts that should not collide with each other

    LAST_SHARED_COLLISION_GROUP
}

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

// settings for m_takedamage
#define DAMAGE_NO           0
#define DAMAGE_EVENTS_ONLY  1 // Call damage functions, but don't modify health
#define DAMAGE_YES          2
#define DAMAGE_AIM          3

// Debug overlay bits
enum DebugOverlayBits_t
{
    OVERLAY_TEXT_BIT                 = 0x00000001, // show text debug overlay for this entity
    OVERLAY_NAME_BIT                 = 0x00000002, // show name debug overlay for this entity
    OVERLAY_BBOX_BIT                 = 0x00000004, // show bounding box overlay for this entity
    OVERLAY_PIVOT_BIT                = 0x00000008, // show pivot for this entity
    OVERLAY_MESSAGE_BIT              = 0x00000010, // show messages for this entity
    OVERLAY_ABSBOX_BIT               = 0x00000020, // show abs bounding box overlay
    OVERLAY_RBOX_BIT                 = 0x00000040, // show the rbox overlay
    OVERLAY_SHOW_BLOCKSLOS           = 0x00000080, // show entities that block NPC LOS
    OVERLAY_ATTACHMENTS_BIT          = 0x00000100, // show attachment points
    OVERLAY_AUTOAIM_BIT              = 0x00000200, // Display autoaim radius

    OVERLAY_NPC_SELECTED_BIT         = 0x00001000, // the npc is current selected
    OVERLAY_NPC_NEAREST_BIT          = 0x00002000, // show the nearest node of this npc
    OVERLAY_NPC_ROUTE_BIT            = 0x00004000, // draw the route for this npc
    OVERLAY_NPC_TRIANGULATE_BIT      = 0x00008000, // draw the triangulation for this npc
    OVERLAY_NPC_ZAP_BIT              = 0x00010000, // destroy the NPC
    OVERLAY_NPC_ENEMIES_BIT          = 0x00020000, // show npc's enemies
    OVERLAY_NPC_CONDITIONS_BIT       = 0x00040000, // show NPC's current conditions
    OVERLAY_NPC_SQUAD_BIT            = 0x00080000, // show npc squads
    OVERLAY_NPC_TASK_BIT             = 0x00100000, // show npc task details
    OVERLAY_NPC_FOCUS_BIT            = 0x00200000, // show line to npc's enemy and target
    OVERLAY_NPC_VIEWCONE_BIT         = 0x00400000, // show npc's viewcone
    OVERLAY_NPC_KILL_BIT             = 0x00800000, // kill the NPC, running all appropriate AI.

    OVERLAY_WC_CHANGE_ENTITY         = 0x01000000, // object changed during WC edit
    OVERLAY_BUDDHA_MODE              = 0x02000000, // take damage but don't die

    OVERLAY_NPC_STEERING_REGULATIONS = 0x04000000, // Show the steering regulations associated with the NPC

    OVERLAY_TASK_TEXT_BIT            = 0x08000000, // show task and schedule names when they start

    OVERLAY_PROP_DEBUG               = 0x10000000,

    OVERLAY_NPC_RELATION_BIT         = 0x20000000, // show relationships between target and all children

    OVERLAY_VIEWOFFSET               = 0x40000000, // show view offset
};

enum BombDeployingState_t
{
    TF_BOMB_DEPLOYING_NONE,
    TF_BOMB_DEPLOYING_DELAY,
    TF_BOMB_DEPLOYING_ANIMATING,
    TF_BOMB_DEPLOYING_COMPLETE,

    TF_BOMB_DEPLOYING_NOT_COUNT
}

enum PlayerAnimEvent_t
{
    PLAYERANIMEVENT_ATTACK_PRIMARY,
    PLAYERANIMEVENT_ATTACK_SECONDARY,
    PLAYERANIMEVENT_ATTACK_GRENADE,
    PLAYERANIMEVENT_RELOAD,
    PLAYERANIMEVENT_RELOAD_LOOP,
    PLAYERANIMEVENT_RELOAD_END,
    PLAYERANIMEVENT_JUMP,
    PLAYERANIMEVENT_SWIM,
    PLAYERANIMEVENT_DIE,
    PLAYERANIMEVENT_FLINCH_CHEST,
    PLAYERANIMEVENT_FLINCH_HEAD,
    PLAYERANIMEVENT_FLINCH_LEFTARM,
    PLAYERANIMEVENT_FLINCH_RIGHTARM,
    PLAYERANIMEVENT_FLINCH_LEFTLEG,
    PLAYERANIMEVENT_FLINCH_RIGHTLEG,
    PLAYERANIMEVENT_DOUBLEJUMP,

    // Cancel.
    PLAYERANIMEVENT_CANCEL,
    PLAYERANIMEVENT_SPAWN,

    // Snap to current yaw exactly
    PLAYERANIMEVENT_SNAP_YAW,

    PLAYERANIMEVENT_CUSTOM, // Used to play specific activities
    PLAYERANIMEVENT_CUSTOM_GESTURE,
    PLAYERANIMEVENT_CUSTOM_SEQUENCE, // Used to play specific sequences
    PLAYERANIMEVENT_CUSTOM_GESTURE_SEQUENCE,

    // TF Specific. Here until there's a derived game solution to this.
    PLAYERANIMEVENT_ATTACK_PRE,
    PLAYERANIMEVENT_ATTACK_POST,
    PLAYERANIMEVENT_GRENADE1_DRAW,
    PLAYERANIMEVENT_GRENADE2_DRAW,
    PLAYERANIMEVENT_GRENADE1_THROW,
    PLAYERANIMEVENT_GRENADE2_THROW,
    PLAYERANIMEVENT_VOICE_COMMAND_GESTURE,
    PLAYERANIMEVENT_DOUBLEJUMP_CROUCH,
    PLAYERANIMEVENT_STUN_BEGIN,
    PLAYERANIMEVENT_STUN_MIDDLE,
    PLAYERANIMEVENT_STUN_END,
    PLAYERANIMEVENT_PASSTIME_THROW_BEGIN,
    PLAYERANIMEVENT_PASSTIME_THROW_MIDDLE,
    PLAYERANIMEVENT_PASSTIME_THROW_END,
    PLAYERANIMEVENT_CYOAPDA_BEGIN,
    PLAYERANIMEVENT_CYOAPDA_MIDDLE,
    PLAYERANIMEVENT_CYOAPDA_END,

    PLAYERANIMEVENT_ATTACK_PRIMARY_SUPER,

    PLAYERANIMEVENT_COUNT
}

enum AttributeType
{
    REMOVE_ON_DEATH             = 1 << 0,  // kick bot from server when killed
    AGGRESSIVE                  = 1 << 1,  // in MvM mode, push for the cap point
    IS_NPC                      = 1 << 2,  // a non-player support character
    SUPPRESS_FIRE               = 1 << 3,
    DISABLE_DODGE               = 1 << 4,
    BECOME_SPECTATOR_ON_DEATH   = 1 << 5,  // move bot to spectator team when killed
    QUOTA_MANANGED              = 1 << 6,  // managed by the bot quota in CTFBotManager
    RETAIN_BUILDINGS            = 1 << 7,  // don't destroy this bot's buildings when it disconnects
    SPAWN_WITH_FULL_CHARGE      = 1 << 8,  // all weapons start with full charge (ie: uber)
    ALWAYS_CRIT                 = 1 << 9,  // always fire critical hits
    IGNORE_ENEMIES              = 1 << 10,
    HOLD_FIRE_UNTIL_FULL_RELOAD = 1 << 11, // don't fire our barrage weapon until it is full reloaded (rocket launcher, etc)
    PRIORITIZE_DEFENSE          = 1 << 12, // bot prioritizes defending when possible
    ALWAYS_FIRE_WEAPON          = 1 << 13, // constantly fire our weapon
    TELEPORT_TO_HINT            = 1 << 14, // bot will teleport to hint target instead of walking out from the spawn point
    MINIBOSS                    = 1 << 15, // is miniboss?
    USE_BOSS_HEALTH_BAR         = 1 << 16, // should I use boss health bar?
    IGNORE_FLAG                 = 1 << 17, // don't pick up flag/bomb
    AUTO_JUMP                   = 1 << 18, // auto jump
    AIR_CHARGE_ONLY             = 1 << 19, // demo knight only charge in the air
    PREFER_VACCINATOR_BULLETS   = 1 << 20, // When using the vaccinator, prefer to use the bullets shield
    PREFER_VACCINATOR_BLAST     = 1 << 21, // When using the vaccinator, prefer to use the blast shield
    PREFER_VACCINATOR_FIRE      = 1 << 22, // When using the vaccinator, prefer to use the fire shield
    BULLET_IMMUNE               = 1 << 23, // Has a shield that makes the bot immune to bullets
    BLAST_IMMUNE                = 1 << 24, // "" blast
    FIRE_IMMUNE                 = 1 << 25, // "" fire
    PARACHUTE                   = 1 << 26, // demo/soldier parachute when falling
    PROJECTILE_SHIELD           = 1 << 27  // medic projectile shield
}

#define MISSION_DOESNT_RESET_BEHAVIOR_SYSTEM false
enum MissionType
{
    NO_MISSION = 0,
    MISSION_SEEK_AND_DESTROY, // focus on finding and killing enemy players
    MISSION_DESTROY_SENTRIES, // focus on finding and destroying enemy sentry guns (and buildings)
    MISSION_SNIPER,           // maintain teams of snipers harassing the enemy
    MISSION_SPY,              // maintain teams of spies harassing the enemy
    MISSION_ENGINEER,         // maintain engineer nests for harassing the enemy
    MISSION_REPROGRAMMED      // MvM: robot has been hacked and will do bad things to their team
}

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
}

enum EEconItemQuality
{
    AE_UNDEFINED = -1,

    AE_NORMAL           = 0,
    AE_RARITY1          = 1, // Genuine
    AE_RARITY2          = 2, // Customized (unused)
    AE_VINTAGE          = 3, // Vintage has to stay at 3 for backwards compatibility
    AE_RARITY3          = 4, // Artisan
    AE_UNUSUAL          = 5, // Unusual
    AE_UNIQUE           = 6,
    AE_COMMUNITY        = 7,
    AE_DEVELOPER        = 8,
    AE_SELFMADE         = 9,
    AE_CUSTOMIZED       = 10, // (unused)
    AE_STRANGE          = 11,
    AE_COMPLETED        = 12,
    AE_HAUNTED          = 13,
    AE_COLLECTORS       = 14,
    AE_PAINTKITWEAPON   = 15,

    AE_RARITY_DEFAULT   = 16,
    AE_RARITY_COMMON    = 17,
    AE_RARITY_UNCOMMON  = 18,
    AE_RARITY_RARE      = 19,
    AE_RARITY_MYTHICAL  = 20,
    AE_RARITY_LEGENDARY = 21,
    AE_RARITY_ANCIENT   = 22,

    AE_MAX_TYPES,
    AE_DEPRECATED_UNIQUE = 3
}

//--------------------------------------------------------------------------
// BUILDING
//--------------------------------------------------------------------------
// Build checks will return one of these for a player
enum
{
    CB_CAN_BUILD,      // Player is allowed to build this object
    CB_CANNOT_BUILD,   // Player is not allowed to build this object
    CB_LIMIT_REACHED,  // Player has reached the limit of the number of these objects allowed
    CB_NEED_RESOURCES, // Player doesn't have enough resources to build this object
    CB_NEED_ADRENALIN, // Commando doesn't have enough adrenalin to build a rally flag
    CB_UNKNOWN_OBJECT  // Error message, tried to build unknown object
}

//-----------------------------------------------------------------------------
// Ammo.
//-----------------------------------------------------------------------------
enum ETFAmmoType
{
    TF_AMMO_DUMMY = 0, // Dummy index to make the CAmmoDef indices correct for the other ammo types.
    TF_AMMO_PRIMARY,
    TF_AMMO_SECONDARY,
    TF_AMMO_METAL,
    TF_AMMO_GRENADES1,
    TF_AMMO_GRENADES2,
    TF_AMMO_GRENADES3, // Utility Slot Grenades
    TF_AMMO_COUNT
}

//-----------------------------------------------------------------------------
// Particle attachment methods
//-----------------------------------------------------------------------------
enum ParticleAttachment_t
{
    PATTACH_ABSORIGIN = 0,    // Create at absorigin, but don't follow
    PATTACH_ABSORIGIN_FOLLOW, // Create at absorigin, and update to follow the entity
    PATTACH_CUSTOMORIGIN,     // Create at a custom origin, but don't follow
    PATTACH_POINT,            // Create on attachment point, but don't follow
    PATTACH_POINT_FOLLOW,     // Create on attachment point, and update to follow the entity

    PATTACH_WORLDORIGIN,      // Used for control points that don't attach to an entity

    PATTACH_ROOTBONE_FOLLOW,  // Create at the root bone of the entity, and update to follow

    MAX_PATTACH_TYPES
}

//-----------------------------------------------------------------------------
// For entity_capture_flags to use when placed in the world
//-----------------------------------------------------------------------------
enum ETFFlagType
{
    TF_FLAGTYPE_CTF = 0,
    TF_FLAGTYPE_ATTACK_DEFEND,
    TF_FLAGTYPE_TERRITORY_CONTROL,
    TF_FLAGTYPE_INVADE,
    TF_FLAGTYPE_RESOURCE_CONTROL,
    TF_FLAGTYPE_ROBOT_DESTRUCTION,
    TF_FLAGTYPE_PLAYER_DESTRUCTION
}

//-----------------------------------------------------------------------------
// TF FlagInfo State.
//-----------------------------------------------------------------------------
#define TF_FLAGINFO_HOME    0
#define TF_FLAGINFO_STOLEN  ( 1 << 0 )
#define TF_FLAGINFO_DROPPED ( 1 << 1 )

// entity effects
enum
{
    EF_BONEMERGE          = 0x001, // Performs bone merge on client side
    EF_BRIGHTLIGHT        = 0x002, // DLIGHT centered at entity origin
    EF_DIMLIGHT           = 0x004, // player flashlight
    EF_NOINTERP           = 0x008, // don't interpolate the next frame
    EF_NOSHADOW           = 0x010, // Don't cast no shadow
    EF_NODRAW             = 0x020, // don't draw entity
    EF_NORECEIVESHADOW    = 0x040, // Don't receive no shadow
    EF_BONEMERGE_FASTCULL = 0x080, // For use with EF_BONEMERGE. If this is set, then it places this ent's origin at its
                                       // parent and uses the parent's bbox + the max extents of the aiment.
                                       // Otherwise, it sets up the parent's bones every frame to figure out where to place
                                       // the aiment, which is inefficient because it'll setup the parent's bones even if
                                       // the parent is not in the PVS.
    EF_ITEM_BLINK         = 0x100, // blink an item so that the user notices it.
    EF_PARENT_ANIMATE     = 0x200, // always assume that the parent entity is animating
    EF_MAX_BITS = 10
}

#define EF_PARITY_BITS  3
#define EF_PARITY_MASK  ( ( 1 << EF_PARITY_BITS ) - 1 )

// How many bits does the muzzle flash parity thing get?
#define EF_MUZZLEFLASH_BITS 2

//-----------------------------------------------------------------------------
// TF Concepts
//-----------------------------------------------------------------------------
#define MP_CONCEPT_NONE -1

enum
{
    MP_CONCEPT_FIREWEAPON = 0,               // "TLK_FIREWEAPON"
    MP_CONCEPT_HURT,                         // "TLK_HURT"
    MP_CONCEPT_PLAYER_EXPRESSION,            // "TLK_PLAYER_EXPRESSION"
    MP_CONCEPT_WINDMINIGUN,                  // "TLK_WINDMINIGUN"
    MP_CONCEPT_FIREMINIGUN,                  // "TLK_FIREMINIGUN"
    MP_CONCEPT_PLAYER_MEDIC,                 // "TLK_PLAYER_MEDIC"
    MP_CONCEPT_DETONATED_OBJECT,             // "TLK_DETONATED_OBJECT"
    MP_CONCEPT_KILLED_PLAYER,                // "TLK_KILLED_PLAYER"
    MP_CONCEPT_KILLED_OBJECT,                // "TLK_KILLED_OBJECT"
    MP_CONCEPT_PLAYER_PAIN,                  // "TLK_PLAYER_PAIN"
    MP_CONCEPT_PLAYER_ATTACKER_PAIN,         // "TLK_PLAYER_ATTACKER_PAIN"
    MP_CONCEPT_PLAYER_TAUNT,                 // "TLK_PLAYER_TAUNT"
    MP_CONCEPT_PLAYER_HELP,                  // "TLK_PLAYER_HELP"
    MP_CONCEPT_PLAYER_GO,                    // "TLK_PLAYER_GO"
    MP_CONCEPT_PLAYER_MOVEUP,                // "TLK_PLAYER_MOVEUP"
    MP_CONCEPT_PLAYER_LEFT,                  // "TLK_PLAYER_LEFT"
    MP_CONCEPT_PLAYER_RIGHT,                 // "TLK_PLAYER_RIGHT"
    MP_CONCEPT_PLAYER_YES,                   // "TLK_PLAYER_YES"
    MP_CONCEPT_PLAYER_NO,                    // "TLK_PLAYER_NO"
    MP_CONCEPT_PLAYER_INCOMING,              // "TLK_PLAYER_INCOMING"
    MP_CONCEPT_PLAYER_CLOAKEDSPY,            // "TLK_PLAYER_CLOAKEDSPY"
    MP_CONCEPT_PLAYER_SENTRYAHEAD,           // "TLK_PLAYER_SENTRYAHEAD"
    MP_CONCEPT_PLAYER_TELEPORTERHERE,        // "TLK_PLAYER_TELEPORTERHERE"
    MP_CONCEPT_PLAYER_DISPENSERHERE,         // "TLK_PLAYER_DISPENSERHERE"
    MP_CONCEPT_PLAYER_SENTRYHERE,            // "TLK_PLAYER_SENTRYHERE"
    MP_CONCEPT_PLAYER_ACTIVATECHARGE,        // "TLK_PLAYER_ACTIVATECHARGE"
    MP_CONCEPT_PLAYER_CHARGEREADY,           // "TLK_PLAYER_CHARGEREADY"
    MP_CONCEPT_PLAYER_TAUNTS,                // "TLK_PLAYER_TAUNTS"
    MP_CONCEPT_PLAYER_BATTLECRY,             // "TLK_PLAYER_BATTLECRY"
    MP_CONCEPT_PLAYER_CHEERS,                // "TLK_PLAYER_CHEERS"
    MP_CONCEPT_PLAYER_JEERS,                 // "TLK_PLAYER_JEERS"
    MP_CONCEPT_PLAYER_POSITIVE,              // "TLK_PLAYER_POSITIVE"
    MP_CONCEPT_PLAYER_NEGATIVE,              // "TLK_PLAYER_NEGATIVE"
    MP_CONCEPT_PLAYER_NICESHOT,              // "TLK_PLAYER_NICESHOT"
    MP_CONCEPT_PLAYER_GOODJOB,               // "TLK_PLAYER_GOODJOB"
    MP_CONCEPT_MEDIC_STARTEDHEALING,         // "TLK_MEDIC_STARTEDHEALING"
    MP_CONCEPT_MEDIC_CHARGEREADY,            // "TLK_MEDIC_CHARGEREADY"
    MP_CONCEPT_MEDIC_STOPPEDHEALING,         // "TLK_MEDIC_STOPPEDHEALING"
    MP_CONCEPT_MEDIC_CHARGEDEPLOYED,         // "TLK_MEDIC_CHARGEDEPLOYED"
    MP_CONCEPT_FLAGPICKUP,                   // "TLK_FLAGPICKUP"
    MP_CONCEPT_FLAGCAPTURED,                 // "TLK_FLAGCAPTURED"
    MP_CONCEPT_ROUND_START,                  // "TLK_ROUND_START"
    MP_CONCEPT_SUDDENDEATH_START,            // "TLK_SUDDENDEATH_START"
    MP_CONCEPT_ONFIRE,                       // "TLK_ONFIRE"
    MP_CONCEPT_STALEMATE,                    // "TLK_STALEMATE"
    MP_CONCEPT_BUILDING_OBJECT,              // "TLK_BUILDING_OBJECT"
    MP_CONCEPT_LOST_OBJECT,                  // "TLK_LOST_OBJECT"
    MP_CONCEPT_SPY_SAPPER,                   // "TLK_SPY_SAPPER"
    MP_CONCEPT_TELEPORTED,                   // "TLK_TELEPORTED"
    MP_CONCEPT_LOST_CONTROL_POINT,           // "TLK_LOST_CONTROL_POINT"
    MP_CONCEPT_CAPTURED_POINT,               // "TLK_CAPTURED_POINT"
    MP_CONCEPT_CAPTURE_BLOCKED,              // "TLK_CAPTURE_BLOCKED"
    MP_CONCEPT_HEALTARGET_STARTEDHEALING,    // "TLK_HEALTARGET_STARTEDHEALING"
    MP_CONCEPT_HEALTARGET_CHARGEREADY,       // "TLK_HEALTARGET_CHARGEREADY"
    MP_CONCEPT_HEALTARGET_STOPPEDHEALING,    // "TLK_HEALTARGET_STOPPEDHEALING"
    MP_CONCEPT_HEALTARGET_CHARGEDEPLOYED,    // "TLK_HEALTARGET_CHARGEDEPLOYED"
    MP_CONCEPT_MINIGUN_FIREWEAPON,           // "TLK_MINIGUN_FIREWEAPON"
    MP_CONCEPT_DIED,                         // "TLK_DIED"
    MP_CONCEPT_PLAYER_THANKS,                // "TLK_PLAYER_THANKS"
    MP_CONCEPT_CART_MOVING_FORWARD,          // "TLK_CART_MOVING_FORWARD"
    MP_CONCEPT_CART_MOVING_BACKWARD,         // "TLK_CART_MOVING_BACKWARD"
    MP_CONCEPT_CART_STOP,                    // "TLK_CART_STOP"
    MP_CONCEPT_ATE_FOOD,                     // "TLK_ATE_FOOD"
    MP_CONCEPT_DOUBLE_JUMP,                  // "TLK_DOUBLE_JUMP"
    MP_CONCEPT_DODGING,                      // "TLK_DODGING"
    MP_CONCEPT_DODGE_SHOT,                   // "TLK_DODGE_SHOT"
    MP_CONCEPT_GRAB_BALL,                    // "TLK_GRAB_BALL"
    MP_CONCEPT_REGEN_BALL,                   // "TLK_REGEN_BALL"
    MP_CONCEPT_DEFLECTED,                    // "TLK_DEFLECTED"
    MP_CONCEPT_BALL_MISSED,                  // "TLK_BALL_MISSED"
    MP_CONCEPT_STUNNED,                      // "TLK_STUNNED"
    MP_CONCEPT_STUNNED_TARGET,               // "TLK_STUNNED_TARGET"
    MP_CONCEPT_TIRED,                        // "TLK_TIRED"
    MP_CONCEPT_BAT_BALL,                     // "TLK_BAT_BALL"
    MP_CONCEPT_ACHIEVEMENT_AWARD,            // "TLK_ACHIEVEMENT_AWARD"
    MP_CONCEPT_JARATE_HIT,                   // "TLK_JARATE_HIT"
    MP_CONCEPT_JARATE_LAUNCH,                // "TLK_JARATE_LAUNCH"
    MP_CONCEPT_HIGHFIVE_SUCCESS,             // "TLK_HIGHFIVE_SUCCESS"
    MP_CONCEPT_HIGHFIVE_SUCCESS_FULL,        // "TLK_HIGHFIVE_SUCCESS_FULL"
    MP_CONCEPT_HIGHFIVE_FAILURE,             // "TLK_HIGHFIVE_FAILURE"
    MP_CONCEPT_HIGHFIVE_FAILURE_FULL,        // "TLK_HIGHFIVE_FAILURE_FULL"
    MP_CONCEPT_PLAYER_TAUNT2,                // "TLK_PLAYER_TAUNT2"
    MP_CONCEPT_PICKUP_BUILDING,              // "TLK_PICKUP_BUILDING"
    MP_CONCEPT_REDEPLOY_BUILDING,            // "TLK_REDEPLOY_BUILDING"
    MP_CONCEPT_CARRYING_BUILDING,            // "TLK_CARRYING_BUILDING"
    MP_CONCEPT_DUEL_REQUEST,                 // "TLK_REQUEST_DUEL"
    MP_CONCEPT_DUEL_TARGET_REJECT,           // "TLK_REJECT_DUEL"
    MP_CONCEPT_DUEL_REJECTED,                // "TLK_DUEL_WAS_REJECTED"
    MP_CONCEPT_DUEL_TARGET_ACCEPT,           // "TLK_ACCEPT_DUEL"
    MP_CONCEPT_DUEL_ACCEPTED,                // "TLK_DUEL_WAS_ACCEPTED"
    MP_CONCEPT_PLAYER_SHOW_ITEM_TAUNT,       // "TLK_PLAYER_SHOW_ITEM_TAUNT"
    MP_CONCEPT_TAUNT_REPLAY,                 // "TLK_TAUNT_REPLAY"
    MP_CONCEPT_TAUNT_LAUGH,                  // "TLK_TAUNT_LAUGH"
    MP_CONCEPT_TAUNT_HEROIC_POSE,            // "TLK_TAUNT_HEROIC_POSE"
    MP_CONCEPT_PARTNER_TAUNT_READY,          // "TLK_PARTNER_TAUNT_READY"
    MP_CONCEPT_HOLDTAUNT,                    // "TLK_PLAYER_HOLDTAUNT"
    MP_CONCEPT_TAUNT_PYRO_ARMAGEDDON,        // "TLK_TAUNT_PYRO_ARMAGEDDON"
    MP_CONCEPT_ROCKET_DESTOYED,              // "TLK_ROCKET_DESTOYED"
    MP_CONCEPT_MVM_BOMB_DROPPED,             // "TLK_MVM_BOMB_DROPPED"
    MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE1,    // "TLK_MVM_BOMB_CARRIER_UPGRADE1"
    MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE2,    // "TLK_MVM_BOMB_CARRIER_UPGRADE2"
    MP_CONCEPT_MVM_BOMB_CARRIER_UPGRADE3,    // "TLK_MVM_BOMB_CARRIER_UPGRADE3"
    MP_CONCEPT_MVM_DEFENDER_DIED,            // "TLK_MVM_DEFENDER_DIED"
    MP_CONCEPT_MVM_FIRST_BOMB_PICKUP,        // "TLK_MVM_FIRST_BOMB_PICKUP"
    MP_CONCEPT_MVM_BOMB_PICKUP,              // "TLK_MVM_BOMB_PICKUP"
    MP_CONCEPT_MVM_SENTRY_BUSTER,            // "TLK_MVM_SENTRY_BUSTER"
    MP_CONCEPT_MVM_SENTRY_BUSTER_DOWN,       // "TLK_MVM_SENTRY_BUSTER_DOWN"
    MP_CONCEPT_MVM_SNIPER_CALLOUT,           // "TLK_MVM_SNIPER_CALLOUT"
    MP_CONCEPT_MVM_LAST_MAN_STANDING,        // "TLK_MVM_LAST_MAN_STANDING"
    MP_CONCEPT_MVM_ENCOURAGE_MONEY,          // "TLK_MVM_ENCOURAGE_MONEY"
    MP_CONCEPT_MVM_MONEY_PICKUP,             // "TLK_MVM_MONEY_PICKUP"
    MP_CONCEPT_MVM_ENCOURAGE_UPGRADE,        // "TLK_MVM_ENCOURAGE_UPGRADE"
    MP_CONCEPT_MVM_UPGRADE_COMPLETE,         // "TLK_MVM_UPGRADE_COMPLETE"
    MP_CONCEPT_MVM_GIANT_CALLOUT,            // "TLK_MVM_GIANT_CALLOUT"
    MP_CONCEPT_MVM_GIANT_HAS_BOMB,           // "TLK_MVM_GIANT_HAS_BOMB"
    MP_CONCEPT_MVM_GIANT_KILLED,             // "TLK_MVM_GIANT_KILLED"
    MP_CONCEPT_MVM_GIANT_KILLED_TEAMMATE,    // "TLK_MVM_GIANT_KILLED_TEAMMATE"
    MP_CONCEPT_MVM_SAPPED_ROBOT,             // "TLK_MVM_SAPPED_ROBOT"
    MP_CONCEPT_MVM_CLOSE_CALL,               // "TLK_MVM_CLOSE_CALL"
    MP_CONCEPT_MVM_TANK_CALLOUT,             // "TLK_MVM_TANK_CALLOUT"
    MP_CONCEPT_MVM_TANK_DEAD,                // "TLK_MVM_TANK_DEAD"
    MP_CONCEPT_MVM_TANK_DEPLOYING,           // "TLK_MVM_TANK_DEPLOYING"
    MP_CONCEPT_MVM_ATTACK_THE_TANK,          // "TLK_MVM_ATTACK_THE_TANK"
    MP_CONCEPT_MVM_TAUNT,                    // "TLK_MVM_TAUNT"
    MP_CONCEPT_MVM_WAVE_START,               // "TLK_MVM_WAVE_START"
    MP_CONCEPT_MVM_WAVE_WIN,                 // "TLK_MVM_WAVE_WIN"
    MP_CONCEPT_MVM_WAVE_LOSE,                // "TLK_MVM_WAVE_LOSE"
    MP_CONCEPT_MVM_DEPLOY_RAGE,              // "TLK_MVM_DEPLOY_RAGE"
    MP_CONCEPT_MAGIC_BIGHEAD,                // "TLK_MAGIC_BIGHEAD"
    MP_CONCEPT_MAGIC_SMALLHEAD,              // "TLK_MAGIC_SMALLHEAD"
    MP_CONCEPT_MAGIC_GRAVITY,                // "TLK_MAGIC_GRAVITY"
    MP_CONCEPT_MAGIC_GOOD,                   // "TLK_MAGIC_GOOD"
    MP_CONCEPT_MAGIC_DANCE,                  // "TLK_MAGIC_DANCE"
    MP_CONCEPT_HALLOWEEN_LONGFALL,
    MP_CONCEPT_TAUNT_GUITAR_RIFF,            // "TLK_TAUNT_GUITAR_RIFF"

    // TF Halloween 2013 shenanigans.
    MP_CONCEPT_PLAYER_CAST_FIREBALL,         // "TLK_PLAYER_CAST_FIREBALL"
    MP_CONCEPT_PLAYER_CAST_MERASMUS_ZAP,     // "TLK_PLAYER_CAST_MERASMUS_ZAP"
    MP_CONCEPT_PLAYER_CAST_SELF_HEAL,        // "TLK_PLAYER_CAST_SELF_HEAL"
    MP_CONCEPT_PLAYER_CAST_MIRV,             // "TLK_PLAYER_CAST_MIRV"
    MP_CONCEPT_PLAYER_CAST_BLAST_JUMP,       // "TLK_PLAYER_CAST_BLAST_JUMP"
    MP_CONCEPT_PLAYER_CAST_STEALTH,          // "TLK_PLAYER_CAST_STEALTH"
    MP_CONCEPT_PLAYER_CAST_TELEPORT,         // "TLK_PLAYER_CAST_TELEPORT"
    MP_CONCEPT_PLAYER_CAST_LIGHTNING_BALL,   // "TLK_PLAYER_CAST_LIGHTNING_BALL"
    MP_CONCEPT_PLAYER_CAST_MOVEMENT_BUFF,    // "TLK_PLAYER_CAST_MOVEMENT_BUFF"
    MP_CONCEPT_PLAYER_CAST_MONOCULOUS,       // "TLK_PLAYER_CAST_MONOCULOUS"
    MP_CONCEPT_PLAYER_CAST_METEOR_SWARM,     // "TLK_PLAYER_CAST_METEOR_SWARM"
    MP_CONCEPT_PLAYER_CAST_SKELETON_HORDE,   // "TLK_PLAYER_CAST_SKELETON_HORDE"
    MP_CONCEPT_PLAYER_CAST_BOMB_HEAD_CURSE,  // "TLK_PLAYER_CAST_BOMB_HEAD_CURSE"

    MP_CONCEPT_PLAYER_SPELL_FIREBALL,        // "TLK_PLAYER_SPELL_FIREBALL"
    MP_CONCEPT_PLAYER_SPELL_MERASMUS_ZAP,    // "TLK_PLAYER_SPELL_MERASMUS_ZAP"
    MP_CONCEPT_PLAYER_SPELL_SELF_HEAL,       // "TLK_PLAYER_SPELL_SELF_HEAL"
    MP_CONCEPT_PLAYER_SPELL_MIRV,            // "TLK_PLAYER_SPELL_MIRV"
    MP_CONCEPT_PLAYER_SPELL_BLAST_JUMP,      // "TLK_PLAYER_SPELL_BLAST_JUMP"
    MP_CONCEPT_PLAYER_SPELL_STEALTH,         // "TLK_PLAYER_SPELL_STEALTH"
    MP_CONCEPT_PLAYER_SPELL_TELEPORT,        // "TLK_PLAYER_SPELL_TELEPORT"
    MP_CONCEPT_PLAYER_SPELL_LIGHTNING_BALL,  // "TLK_PLAYER_SPELL_LIGHTNING_BALL"
    MP_CONCEPT_PLAYER_SPELL_MOVEMENT_BUFF,   // "TLK_PLAYER_SPELL_MOVEMENT_BUFF"
    MP_CONCEPT_PLAYER_SPELL_MONOCULOUS,      // "TLK_PLAYER_SPELL_MONOCULOUS"
    MP_CONCEPT_PLAYER_SPELL_METEOR_SWARM,    // "TLK_PLAYER_SPELL_METEOR_SWARM"
    MP_CONCEPT_PLAYER_SPELL_SKELETON_HORDE,  // "TLK_PLAYER_SPELL_SKELETON_HORDE"
    MP_CONCEPT_PLAYER_SPELL_BOMB_HEAD_CURSE, // "TLK_PLAYER_SPELL_BOMB_HEAD_CURSE"

    // Events.
    MP_CONCEPT_PLAYER_SPELL_PICKUP_COMMON,   // "TLK_PLAYER_SPELL_PICKUP_COMMON"
    MP_CONCEPT_PLAYER_SPELL_PICKUP_RARE,     // "TLK_PLAYER_SPELL_PICKUP_RARE"
    MP_CONCEPT_PLAYER_HELLTOWER_MIDNIGHT,    // "TLK_PLAYER_HELLTOWER_MIDNIGHT"
    MP_CONCEPT_PLAYER_SKELETON_KING_APPEAR,  // "TLK_PLAYER_SKELETON_KING_APPEAR"

    MP_CONCEPT_MANNHATTAN_GATE_ATK,          // "TLK_MANNHATTAN_GATE_ATK"
    MP_CONCEPT_MANNHATTAN_GATE_TAKE,         // "TLK_MANNHATTAN_GATE_TAKE"
    MP_CONCEPT_RESURRECTED,                  // "TLK_RESURRECTED"
    MP_CONCEPT_MVM_LOOT_COMMON,              // "TLK_MVM_LOOT_COMMON"
    MP_CONCEPT_MVM_LOOT_RARE,                // "TLK_MVM_LOOT_RARE"
    MP_CONCEPT_MVM_LOOT_ULTRARARE,           // "TLK_MVM_LOOT_ULTRARARE"
    MP_CONCEPT_MEDIC_HEAL_SHIELD,            // "TLK_MEDIC_HEAL_SHIELD"

    MP_CONCEPT_TAUNT_EUREKA_EFFECT_TELEPORT, // "TLK_TAUNT_EUREKA_EFFECT"

    MP_CONCEPT_COMBO_KILLED,                 // "TLK_COMBO_KILLED"

    MP_CONCEPT_PLAYER_ASK_FOR_BALL,          // "TLK_PLAYER_ASK_FOR_BALL"

    MP_CONCEPT_ROUND_START_COMP,             // "TLK_ROUND_START_COMP"
    MP_CONCEPT_GAME_OVER_COMP,               // "TLK_GAME_OVER_COMP"
    MP_CONCEPT_MATCH_OVER_COMP,              // "TLK_MATCH_OVER_COMP"

    MP_TF_CONCEPT_COUNT

    // Other MP_CONCEPT_* start he using MP_TF_CONCEPT_COUNT + 1 as start.
}

enum medigun_weapontypes_t
{
    MEDIGUN_STANDARD = 0,
    MEDIGUN_UBER,
    MEDIGUN_QUICKFIX,
    MEDIGUN_RESIST,
}

enum medigun_resist_types_t
{
    MEDIGUN_BULLET_RESIST = 0,
    MEDIGUN_BLAST_RESIST,
    MEDIGUN_FIRE_RESIST,
    MEDIGUN_NUM_RESISTS
}

//
// Max size (in bytes of UTF-8 data, not in characters) of server fields, including null terminator.
//
const int k_cbMaxGameServerGameDir         = 32;
const int k_cbMaxGameServerMapName         = 32;
const int k_cbMaxGameServerGameDescription = 64;
const int k_cbMaxGameServerName            = 64;
const int k_cbMaxGameServerTags            = 128;
const int k_cbMaxGameServerGameData        = 2048;

enum struct PLAYERATTRIBUTES
{
    int   iBotSerial;
    int   iGetBotTypeHookId;
    float flTalkTimer; // Used for sentry busters
    bool  bIsGroupMember;
    bool  bBlockFlagEvent;
    bool  bInSpawn;
    bool  bPendingTaunt;
    bool  bIsWaitingForFullReload;
    char  szOriginalName[ MAX_NAME_LENGTH ];

    bool IsControlling()
    {
        return this.iBotSerial != 0;
    }
}

enum struct BOTATTRIBUTES
{
    int  iPlayerSerial;
    bool bBlockFlagEvent;

    bool IsControlled()
    {
        return this.iPlayerSerial != 0;
    }
}

#define DONT_UPGRADE -1
enum struct CARRIERATTRIBUTES
{
    int   iUpgradeLevel;
    float flBuffPulseTimer;
    float flDeployTimer;
    float vecAnchorPos[ 3 ];
}
