# TF2-Bot-Control
A Team Fortress 2 plugin that allows players to take control of a robot in Mann vs. Machine.

## Important note!
This plugin is still in beta and may contain bugs. If you find any, please open an issue.

## Dependencies
- [TF2Attributes](https://forums.alliedmods.net/showthread.php?t=210221)
- [TF2Items](https://forums.alliedmods.net/forumdisplay.php?f=146)
- [SM-TFUtils](https://github.com/nosoop/SM-TFUtils)
- [stocksoup](https://github.com/nosoop/stocksoup)
- [SteamWorks](https://github.com/alliedmodders/SM-SteamWorks)
- [VScript](https://github.com/FortyTwoFortyTwo/VScript)
- [SM-TFEconData](https://github.com/nosoop/SM-TFEconData)
- [SM-TFAttributeSupport](https://github.com/nosoop/SM-TFAttributeSupport)
- [PluginStateManager](https://github.com/Mikusch/PluginStateManager)

## Building
1. [Install SourceMod](https://wiki.alliedmods.net/Installing_SourceMod).
2. [Install all dependencies](#dependencies).
3. Clone this project and copy the `sourcemod` folder into your Team Fortress 2 Dedicated Servers's `addons` folder.
4. If building for Windows, `WIN32` must be defined.
```batch
.\spcomp64 .\botcontrol.sp -o .\..\plugins\botcontrol.smx WIN32=1
```
Otherwise no other defines are required:
```bash
./spcomp64 ./botcontrol.sp -o ./../plugins/botcontrol.smx
```

If you do not wish to compile the plugin yourself, you can find precompiled versions in the [Releases](https://github.com/explowz/TF2-Bot-Control/releases) tab.<br>
_Note: Dependencies must still be installed._

## Features
### Limiting number of players
This plugins supports limiting the minimum amount of players on the defending team and the maximum amount of controlling players on the invading team for a player to be able to take control of a bot through the console variables `sm_botcontrol_min_defenders` and `sm_botcontrol_max_invaders`.

### Bot restrictions
This plugin supports three types of bot restrictions:
1. "block": This restriction prevents all players from controlling this bot.
2. "premium": This restriction only allows players with the flags defined by `sm_botcontrol_premium_flags` to control this bot.
3. "group": This restriction only allows players that are members of the group with groupID32 defined by `sm_botcontrol_groupid` to control this bot.

These restrictions must be applied using the "custom desc attr" attribute placed inside the `CharacterAttributes` block.
```
TFBot
{
    ClassIcon   scout
    Health      125
    Name        Scout
    Class       Scout
    Skill       Normal
    CharacterAttributes
    {
        "custom desc attr"  block
    }
}
```
```
TFBot
{
    ClassIcon   pyro
    Health      175
    Name        Pyro
    Class       Pyro
    Skill       Normal
    CharacterAttributes
    {
        "custom desc attr"  premium
    }
}
```
```
TFBot
{
    ClassIcon   heavy
    Health      300
    Name        HeavyWeapons
    Class       Heavyweapons
    Skill       Normal
    CharacterAttributes
    {
        "custom desc attr"  group
    }
}
```

### Name mirroring
The console variable `sm_botcontrol_mirror_name` controls whether the plugin will also mirror the controlled bot's name. (Currently this only mirrors the networked name used by chat)

## Credits
- [Pelipoika](https://forums.alliedmods.net/member.php?u=181730) for the MvM bot control plugin after which this plugin was inspired.
- [Bovril](https://github.com/thisld) for his MvM bot control plugin from which the idea of restricting bots was taken.

## Special thanks
Special thanks to [nosoop](https://forums.alliedmods.net/member.php?u=252787), [Bakugo](https://github.com/bakugo), [Anonymous Player](https://github.com/caxanga334), [Mikusch](https://github.com/Mikusch), [Kenzzer](https://github.com/Kenzzer), Deathreus, and everybody else from AlliedModders for always answering my questions.
