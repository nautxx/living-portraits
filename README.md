# Living Portraits

Live 3D animated portraits for World of Warcraft unit frames. Your character breathes and idles like on the character screen. A companion addon for [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes).

> Formerly **BBF Animated Portraits**. Upgrading? Delete the old `BBF_AnimatedPortraits` folder from AddOns (if it's still enabled, Living Portraits offers to disable it for you); settings start fresh under the new name. `/bap` still works as an alias for `/lp`.

> **Status:** v0.3.0, public test release. Tested in game on the **WoW Forever beta**, with and without BetterBlizzFrames. See [CHANGELOG](CHANGELOG.md).

## Screenshots

Switching targets: the health and mana bars grow from empty, and each portrait is a live 3D model.

![Cycling targets: bars grow from empty and the portraits animate](docs/screenshots/target-grow.gif)

Square style with BetterBlizzFrames' Pixel Border mode:

| Player | Target and target-of-target |
|---|---|
| ![Player frame with an animated square portrait](docs/screenshots/player-square.png) | ![Target and target-of-target frames with animated square portraits](docs/screenshots/target-square.png) |

## How it works

Instead of the flat 2D portrait, a live `PlayerModel` of the unit is drawn inside the portrait circle, behind the frame's border ring, with a soft vignette so the model's square edges don't show. If the model can't load (unit out of range, offline, or a BBF "no portrait" mode is on), the addon steps aside and the normal portrait shows.

It **does not modify BetterBlizzFrames**. BBF is an optional dependency: when installed, this addon loads after it and follows BBF's portrait sizing automatically.

## Install

Download `LivingPortraits-<version>.zip` from the repo's Releases and unzip it into `World of Warcraft/<client>/Interface/AddOns/`.

Or from source:


1. Put this folder in `World of Warcraft/<client>/Interface/AddOns/`. **The folder must be named `LivingPortraits`** to match the `.toc`.
2. `/reload` or log in.

### Developing from a git checkout

Keep the repo elsewhere and symlink it into AddOns under the required name:

```sh
ln -s ~/GitHub/Main/living-portraits \
  "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/LivingPortraits"
```

(The WoW Forever beta installs into the `_classic_beta_` folder.)

## Settings

Open **Options → AddOns → Living Portraits** (or type `/lp options`) for style, frames, camera, bar grow and the square/circle tuning.

The square style needs BetterBlizzFrames' **No Portrait + Pixel Border** mode. The **Turn on** button under *BetterBlizzFrames* switches it on for every frame (your other BBF settings stay as they are) and reloads the UI; **Undo** puts back what you had.

## Commands

| Command | Effect |
|---|---|
| `/lp` | Show current settings |
| `/lp options` | Open the settings panel |
| `/lp bbfsetup` / `/lp bbfundo` | Turn on BBF's No Portrait + Pixel Border mode for every frame / put back your previous BBF settings (reload to apply) |
| `/lp toggle` | Turn animated portraits on/off |
| `/lp zoom 0-1` | Camera zoom (1 = head and shoulders, lower = more body) |
| `/lp inset 0.3-1.2 [large\|small]` | Model size relative to the portrait (0.72 keeps corners under the ring; the circle edge follows it) |
| `/lp cam 0.3-2 [large\|small]` | Camera distance (lower = closer, bigger face) |
| `/lp calibrate` | Circle: tint the circle edge red to line it up with the ring; toggle again to finish |
| `/lp offset <group> x y` | Circle: nudge the portrait inside its ring (groups: player, target, focus, tot, party) |
| `/lp grow` | Toggle the health and mana bars growing from empty when you pick a new target (`/lp grow debug` traces it in chat) |
| `/lp growtime 0.1-2` | How long the target bar grow takes, in seconds (default 0.35) |
| `/lp vignette` | Toggle the crisp circle edge that hides the model's square edges |
| `/lp style square\|circle` | Square box beside the bars (needs BBF No Portrait / Pixel Border) or round portrait |
| `/lp bg 0-1` | Square: opacity of the dark background behind the model (default 0 = none) |
| `/lp extend 0-30 [large\|small]` | Square: make the health+mana stack taller; the box grows with it and stays aligned (default large 10, small 6) |
| `/lp namerow 0-24 [large\|tot\|party]` | Square: height of the name + level row inside the box, above the health bar (default large 12, tot 9, party 0) |
| `/lp split 0.4-0.85` | Square: health bar's share of the stack (default 0.66, mana gets the rest) |
| `/lp alignmana` | Square: toggle lining up the mana bar with the health bar next to the box (undoes live) |
| `/lp gap 0-20` | Square: space between the box and the bars (1 = borders share one line) |
| `/lp barspacing 0-10` | Square: space between health and mana (0 = borders share one line) |
| `/lp unit <group>` | Toggle a frame group: `player`, `target`, `focus`, `tot`, `party` |
| `/lp reset` | Restore defaults |
| `/lp refresh` | Re-apply the layout now (e.g. after changing BBF settings) |
| `/lp debug [unit]` | Print the frame's real positions, for bug reports (default: target) |

## Supported clients

| Client | Interface | Status |
|---|---|---|
| WoW Forever beta | 16001 | Supported |
| Retail | 120105 | Not yet |

## Releasing

1. Bump `## Version` in the `.toc` and add a `CHANGELOG.md` entry.
2. Commit, then tag: `git tag -a v<version> -m "v<version>"`.
3. `tools/package.sh` builds `dist/LivingPortraits-<version>.zip` (only the files WoW needs).
4. `git push --follow-tags`, then attach the zip to a GitHub release.

## License

All Rights Reserved. Copyright (c) 2026 Jason Barnachea (nautxx). See [LICENSE](LICENSE).
Not affiliated with BetterBlizzFrames or Blizzard Entertainment.
