# boostfix

A [SourceMod](https://www.sourcemod.net/about.php) plugin for CS:GO servers which fixes buggy push triggers & prevents crouchboosting.

## Usage

- `boostfix_pushfix <0/1>` (default 1) - Enables the [original pushfix implementation](https://forums.alliedmods.net/showthread.php?t=267131)

- `boostfix_crouchboostfix <0/1>` (default 1) - Prevents crouchboosting on push triggers

## Notes

- **This plugin requires [EndTouchFix](https://github.com/rumourA/End-Touch-Fix) to work correctly**

- **This plugin requires [RNGFix](https://github.com/jason-e/rngfix) gamedata**

- **This plugin should NOT be used alongside pushfix.** If you're running [SurfTimer](https://github.com/surftimer/Surftimer-Official), pushfix is [built-in](https://github.com/surftimer/Surftimer-Official/blob/b6a71e9ebde21cb865464c932de116baec199bf6/addons/sourcemod/scripting/surftimer/hooks.sp#L713) and should be disabled for this plugin to work correctly.

- **This plugin prevents crouchboosting ONLY on push triggers.** The same functionality can be applied for trigger_multiple boosts (surf_whiteout b1) or any other trigger, but requires a more in-depth integration with the timer plugin being used.

## Technical Overview

"Crouchboosting" is the act of crouching/uncrouching while touching a trigger in order to exit and then immediately enter it again. In the case of push triggers, this results in unintentional speed boosts. Crouchboosting is easier on higher tickrates, and can be done pretty consistently on surf_cookiejar for example.

When a player starts touching a push trigger too soon after their last EndTouch, and either:

- their last EndTouch was caused by a mid-air duck, or
- this StartTouch was caused by a mid-air unduck

... this StartTouch is considered "invalid", and the plugin disables pushing so the player doesn't get boosted again.
