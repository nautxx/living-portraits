# BBF Animated Portraits

Live 3D animated portraits for World of Warcraft unit frames. Your character breathes and idles like on the character screen. A companion addon for [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes).

> **Status:** early development, untested in game. Player, target, focus, target-of-target, focus-target and party frames.

## How it works

Instead of the flat 2D portrait, a live `PlayerModel` of the unit is drawn inside the portrait circle, behind the frame's border ring, with a soft vignette so the model's square edges don't show. If the model can't load (unit out of range, offline, or a BBF "no portrait" mode is on), the addon steps aside and the normal portrait shows.

It **does not modify BetterBlizzFrames**. BBF is an optional dependency: when installed, this addon loads after it and follows BBF's portrait sizing automatically.

## Install

1. Put this folder in `World of Warcraft/<client>/Interface/AddOns/`. **The folder must be named `BBF_AnimatedPortraits`** to match the `.toc`.
2. `/reload` or log in.

### Developing from a git checkout

Keep the repo elsewhere and symlink it into AddOns under the required name:

```sh
ln -s ~/GitHub/Main/bbf-animated-portraits \
  "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/BBF_AnimatedPortraits"
```

## Commands

| Command | Effect |
|---|---|
| `/bap` | Show current settings |
| `/bap toggle` | Turn animated portraits on/off |
| `/bap zoom 0-1` | Camera zoom (1 = head and shoulders, lower = more body) |
| `/bap inset 0.3-1.2 [large\|small]` | Model size relative to the portrait (0.72 keeps corners under the ring; the circle edge follows it) |
| `/bap cam 0.3-2 [large\|small]` | Camera distance (lower = closer, bigger face) |
| `/bap vignette` | Toggle the crisp circle edge that hides the model's square edges |
| `/bap style square\|circle` | Square box beside the bars (needs BBF No Portrait / Pixel Border) or round portrait |
| `/bap extend 0-30 [large\|small]` | Square: make the health+mana stack taller; the box grows with it and stays aligned (default large 10, small 6) |
| `/bap namerow 0-24 [large\|small]` | Square: height of the name + level row inside the box, above the health bar (default large 12, small 0) |
| `/bap split 0.4-0.85` | Square: health bar's share of the stack (default 0.66, mana gets the rest) |
| `/bap alignmana` | Square: toggle lining up the mana bar with the health bar next to the box (undoes live) |
| `/bap gap 0-20` | Square: space between the box and the bars |
| `/bap unit <group>` | Toggle a frame group: `player`, `target`, `focus`, `tot`, `party` |
| `/bap reset` | Restore defaults |

## Supported clients

| Client | Interface | Status |
|---|---|---|
| Classic beta ("Camelot") | 16001 | Target |
| Retail | 120105 | Not yet |

## License

All Rights Reserved. Copyright (c) 2026 Jason Barnachea (nautxx). See [LICENSE](LICENSE).
Not affiliated with BetterBlizzFrames or Blizzard Entertainment.
