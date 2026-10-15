# Project notes: BBF Animated Portraits

Context for anyone (human or AI) picking up this project.

## Goal
Make Blizzard unit-frame portraits show a live 3D model with the idle "breathing"
animation, like the character screen, as a **companion addon** to BetterBlizzFrames (BBF).

## Key decisions
| Decision | Choice | Why |
|---|---|---|
| Fork BBF vs companion | **Companion addon** | BBF is "All Rights Reserved" (Bodify), so it can't be redistributed. Editing BBF directly is also wiped on every BBF update. |
| BBF dependency | `OptionalDeps` | Loads after BBF so we see its portrait resizing; still works without BBF. |
| Render approach | `PlayerModel` + `SetUnit()` + `SetPortraitZoom()` | Idle animation plays automatically. ModelScene (char screen) is heavier with no masking benefit. |
| Circle problem | **Inscribed square** (step 1) | Mask textures can't clip Model frames, so the model is square. Alternatives: full size + cover ring (only works on solid backgrounds), or square portrait art. Revisit after testing. |
| Touching BBF's portrait | **Never** | We add our own layers (masked bg texture + model) and hide them to fall back. Avoids fights with BBF spec/class/healer portraits. |
| Repo location | `~/GitHub/Main/bbf-animated-portraits`, symlinked into AddOns as `BBF_AnimatedPortraits` | The beta client folder is temporary. One repo can feed multiple clients. |

## Architecture (Core.lua)
- `GetPortraitInfo(unit)` returns `(container, portraitTexture, maskTexture)` for a unit. **Add new units here.**
- `CreateLayers(unit)`:
  - `bg`: a color texture on the portrait's draw layer +1 sublevel, masked by Blizzard's portrait mask (covers the 2D portrait).
  - `model`: a `PlayerModel` child of the container, centred on the portrait, sized `portrait * db.inset`.
- `Refresh(unit)`: show or hide the layers and `SetUnit()`. It hides when disabled, when BBF's `HasNoPortrait(unit)` is true, or when the unit is missing, not visible or disconnected.
- Events: `PLAYER_ENTERING_WORLD` (0.5s delay so BBF finishes resizing), `UNIT_MODEL_CHANGED`, `UNIT_PORTRAIT_UPDATE`, `UNIT_CONNECTION`.
- SavedVariables: `BBFAnimatedPortraitsDB` (defaults merged on `ADDON_LOADED`).
- Slash: `/bap`.

## Blizzard / BBF frame paths (Camelot client, BBF v2.1.7 `forever/` code path)
| Unit | Portrait | Mask |
|---|---|---|
| player | `PlayerFrame.PlayerFrameContainer.PlayerPortrait` | `...PlayerPortraitMask` |
| target | `TargetFrame.TargetFrameContainer.Portrait` | `...PortraitMask` |
| focus | `FocusFrame.TargetFrameContainer.Portrait` | `...PortraitMask` |
| ToT / FoT | `TargetFrame.totFrame.Portrait` / `FocusFrame.totFrame.Portrait` | (check) |

BBF code that touches portraits (read only, for compatibility):
- `forever/BetterBlizzFrames.lua` ~5143–5164: resizes portraits and masks (player 61, target/focus 56).
- `forever/modules/classicFrames.lua` ~343, ~660: the Classic Frames mode repositions portraits.
- `forever/modules/noPortrait.lua`: `BBF.HasNoPortrait(unit)`; we skip when true.
- `BBF.SpecPortraits()` (~5528) and `forever/modules/healer.lua` `UpdateSecretPortrait`: spec and healer icon portraits. **Open question:** should icons win over the model?

## Roadmap
- [x] Step 1: player frame, inscribed square, `/bap` tuning
- [ ] Test step 1 in game (screenshot, then tune zoom/inset defaults)
- [ ] Step 2: target + focus (`PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`)
- [ ] Step 3: party frames, ToT/FoT
- [ ] Decide final circle treatment (inscribed vs cover ring vs square art)
- [ ] Conflict rule with BBF spec/healer portraits
- [ ] Options panel (Settings API) to replace or complement `/bap`
- [ ] Retail support (`## Interface` list, verify frame paths)

## Test checklist
- [ ] Model appears and animates on the player frame after login and `/reload`
- [ ] No square corners poking outside the portrait ring
- [ ] Mount, shapeshift and gear changes update the model
- [ ] Vehicle / possess: no broken portrait
- [ ] `/bap toggle` restores the normal portrait cleanly
- [ ] BBF "no portrait" mode: the addon stays hidden
- [ ] Classic Frames mode in BBF: the model stays aligned
- [ ] No Lua errors (`/console scriptErrors 1`)

## Conventions
- One step per commit; test in game before starting the next step.
- Commit messages follow the rules in **Commit messages** below.
- **Don't commit without asking.** Leave changes uncommitted for Jason to review, then commit when he approves.
- Never edit BBF files. A clean backup of BBF v2.1.7 is at `_classic_beta_/Interface/AddOns_backup/`.
- Git author: Jason <jrbarnachea@gmail.com>. Remote: `github.com/nautxx/bbf-animated-portraits` (private).

## Commit messages

Put a Conventional Commits prefix on every commit title: `type: short imperative summary`.

- `feat`: new capability or behavior (a new unit frame, a new slash command, a new option)
- `fix`: bug fix
- `chore`: maintenance with no user-visible behavior change (TOC bumps, config, cleanup, license)
- `docs`: README, CLAUDE.md or comment-only changes
- `refactor`: code restructuring with no behavior change
- `test`: test-only changes
- `style`: formatting or whitespace, no logic change
- `perf`: performance improvement
- `revert`: reverts a previous commit

After the colon: lowercase, imperative mood ("add", not "added" or "adds"), no trailing period, ideally under ~70 characters. Example: `feat: add animated portraits to target and focus frames`.

When a commit touches only one thing, the title alone is enough, so skip the body. When a commit bundles several distinct changes, add a blank line after the title and a short bullet per change:

```
feat: add animated portraits to target and focus frames

- add target/focus entries to GetPortraitInfo()
- refresh on PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
- document new frame paths in CLAUDE.md
```
