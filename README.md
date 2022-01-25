# crouchboostfix

A [SourceMod](https://www.sourcemod.net/about.php) plugin that prevents crouchboosting.

"Crouchboosting" is the act of crouching/uncrouching while touching a trigger in order to exit and then immediately enter it again. In the case of push triggers, or triggers with `AddOutput basevelocity`, this results in unintentional speed boosts. Crouchboosting is easier on higher tickrates, and can be done pretty consistently on *surf_cookiejar*'s start for example.

## Usage

`crouchboostfix_enabled <0/1>` (default 1) - Enables/disables the plugin

## Installation

**[EndTouchFix](https://github.com/rumourA/End-Touch-Fix)** is required.

## Notes

Use **[PushFixDE](https://github.com/GAMMACASE/PushFixDE)** to fix client prediction errors in push triggers. This plugin is incompatible with any other [pushfix](https://forums.alliedmods.net/showthread.php?t=267131) implementation.

## Technical Overview

When a player starts touching a trigger too soon after their last EndTouch, and either:

- their last EndTouch was caused by a mid-air duck, or
- this StartTouch was caused by a mid-air unduck

... the player is considered to have crouchboosted.

In this case,

- For `trigger_multiple/trigger_push/trigger_gravity`, outputs are prevented from being queued (`OnStartTouch/OnEndTouch`) until after the next EndTouch
- For `trigger_push`, pushing is prevented until after the next EndTouch
