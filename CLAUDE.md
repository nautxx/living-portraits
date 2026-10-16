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
| Circle problem | **Model behind the ring + vignette** (option B) | Mask textures can't clip Model frames. First in-game test (inscribed square above the ring) showed hard square cut lines and a small face. Now the model sits under Blizzard's border ring, which hides its corners, and a vignette hides its straight edges. Rejected: tuning only (cut lines stay visible), square portrait art (big restyle). |
| Touching Blizzard's portrait | **Hide only, never alter** | Hidden while the model shows, restored after. Never change its texture, alpha or color (Blizzard changes those itself). |
| Repo location | `~/GitHub/Main/bbf-animated-portraits`, symlinked into AddOns as `BBF_AnimatedPortraits` | The beta client folder is temporary. One repo can feed multiple clients. |

## Architecture (Core.lua)
- `PORTRAITS[unit]` is a function returning that unit's portrait texture. **Add new units here.** The layers are parented to `portrait:GetParent()`.
- `GROUPS` maps slash-command names (`player`, `target`, `focus`, `tot`, `party`) to units.
- **Layering (bottom to top)**, all created by `CreateLayers(unit)`:
  1. `bgFrame` (child of the unit frame root, level = container − 2): dark circle with its own mask (`TempPortraitAlphaMask`).
  2. `model` (child of root, level = container − 1): `PlayerModel` square sized `portrait × sizes[large|small].inset` (1.0). Its edges sit under the ring; its corners can poke a few px past the ring's outer edge if geometry reaches them.
  3. Blizzard's container: the 2D portrait (hidden while active), our `vignette` texture (same sublevel as the portrait, `media/vignette.tga`) and the border ring art (one sublevel up). The ring covers the model's corners; the vignette is a thin soft edge (clear to ~87% radius) blending the model into the ring.
- While active, Blizzard's portrait is hidden (`Hide()`), and a `hooksecurefunc(portrait, "Show")` re-hides it if anything re-shows it. It's restored on deactivate only if it was shown before. Neither Blizzard nor BBF shows or hides these portraits (Blizzard only does for boss frames), so the risk of fighting them is low. **Side effect:** BBF spec/class icon portraits are covered while the model shows (model wins).
- The layers are no longer inside the unit frame, so they follow it via `container:HookScript("OnShow"/"OnHide")`, and `Refresh` checks `container:IsVisible()`.
- Alpha mirrors `portrait:SetAlpha` (party out-of-range fade) onto bg, model and vignette.
- **Settings migration:** saved settings win over new defaults, so when a default must change for existing installs, bump `SETTINGS_VERSION` and reset those keys in `MigrateSettings()`.
- Camera: `SetPortraitZoom(db.zoom)` + `SetCamDistanceScale(sizes[size].cam)` (0.85, lower = bigger face). `SIZE_OF` maps units to `large` (player/target/focus) or `small` (ToT/party).
- `Refresh(unit)`: show or hide the layers and `SetUnit()`. It hides when disabled, when BBF's `HasNoPortrait(unit)` is true, or when the unit is missing, not visible or disconnected.
- `Tick()` (every 0.5s) compares `UnitState(unit)` (GUID + visible + connected) with the last refresh and refreshes only on change. This covers changes with no reliable event: ToT/FoT swaps, party members entering or leaving view range.
- `Safe(v)` drops "secret" values (`issecretvalue`) so comparisons and concatenation never error.
- Events: `PLAYER_ENTERING_WORLD` (0.5s delay so BBF finishes resizing; starts the ticker), `PLAYER_TARGET_CHANGED` (target + ToT), `PLAYER_FOCUS_CHANGED` (focus + FoT), `UNIT_TARGET` (ToT/FoT), `GROUP_ROSTER_UPDATE` (party), `UNIT_MODEL_CHANGED`, `UNIT_PORTRAIT_UPDATE`, `UNIT_CONNECTION`.
- SavedVariables: `BBFAnimatedPortraitsDB` (defaults merged on `ADDON_LOADED`).
- Slash: `/bap`.

## Blizzard / BBF frame paths (Camelot client 1.60.1.70374)

Verified against Blizzard's UI source: `github.com/Gethe/wow-ui-source`, branch **`forever`** (same build as the client). Camelot loads the Mainline ("Family") unit-frame XML.
Also exported locally from the client (`exportInterfaceFiles code`) to `_classic_beta_/BlizzardInterfaceCode/`. The unit-frame files match the mirror byte-for-byte (ignoring CRLF).

| Unit | Portrait (layer) | Mask | Border art (layer) |
|---|---|---|---|
| player | `PlayerFrame.PlayerFrameContainer.PlayerPortrait` (BACKGROUND 1) | `PlayerPortraitMask` | `FrameTexture` (BACKGROUND 2) |
| target / focus | `TargetFrame/FocusFrame.TargetFrameContainer.Portrait` (BACKGROUND 1) | `PortraitMask` (CircleMask) | `FrameTexture` (BACKGROUND 2) |
| targettarget / focustarget | `TargetFrame/FocusFrame.totFrame.Portrait` 37×37 (BACKGROUND 1) | `PortraitMask` (CircleMask) | `FrameTexture` (BACKGROUND 2) |
| party1–4 | `PartyFrame.MemberFrame1..4.Portrait` (BACKGROUND) | `PortraitMask` (CircleMask) | `Texture` (ARTWORK) |

**Findings that affect the design:**
- The border art sits only **one sublevel above** the portrait on player, target and ToT, so a texture at "portrait sublevel + 1" shares the border's sublevel (undefined draw order). **Fixed** by moving our layers into a separate holder frame with its own mask.
- Blizzard changes the portrait itself: party portraits fade with `SetAlpha` when out of range (`PartyMemberFrame.lua:399`) and get `SetVertexColor` tints (`:671-677`). The target portrait is greyed when tapped (`TargetFrame.lua:329`) and reset to alpha 1 (`:156`). **Don't hide the portrait via alpha**: Blizzard will overwrite it.
- Party member frames come from a frame pool (`PartyFrame.lua:56-59`) and are assigned as `MemberFrameN` on init.

BBF code that touches portraits (read only, for compatibility):
- `forever/BetterBlizzFrames.lua` ~5143–5164: resizes portraits and masks (player 61, target/focus 56).
- `forever/modules/classicFrames.lua` ~343, ~660: the Classic Frames mode repositions portraits.
- `forever/modules/noPortrait.lua`: `BBF.HasNoPortrait(unit)`; we skip when true.
- `BBF.SpecPortraits()` (~5528) and `forever/modules/healer.lua` `UpdateSecretPortrait`: spec and healer icon portraits. **Open question:** should icons win over the model?

## Roadmap
- [x] Step 1: player frame, inscribed square, `/bap` tuning
- [ ] Test step 1 in game (screenshot, then tune zoom/inset defaults)
- [x] Step 2: target + focus (`PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`), untested in game
- [x] Step 3: party frames, ToT/FoT, untested in game
- [ ] Per-group inset/zoom (small ToT/party portraits may need a larger inset)
- [ ] Decide final circle treatment (inscribed vs cover ring vs square art)
- [ ] Conflict rule with BBF spec/healer portraits
- [ ] Options panel (Settings API) to replace or complement `/bap`
- [ ] Retail support (`## Interface` list, verify frame paths)

## Test checklist
- [ ] Model appears and animates on the player frame after login and `/reload`
- [ ] Target / focus: model swaps when the target changes; NPC targets look reasonable
- [ ] ToT / FoT: model follows when your target changes its target
- [ ] Party: models appear; a member out of view range falls back to the 2D portrait and returns when in range
- [ ] `/bap unit tot` / `/bap unit party` toggle cleanly
- [ ] With BBF spec icons on: note which wins on target/focus (open question)
- [ ] No square corners poking outside the portrait ring
- [ ] Ring covers the model's corners; nothing pokes outside the ring (tune `/bap inset`)
- [ ] No straight cut lines visible inside the circle (vignette)
- [ ] Face size feels right on large and small frames (tune `/bap cam`)
- [ ] Level badge, rest/PvP/leader/combat icons still draw on top of the model
- [ ] `/bap toggle` brings back the normal 2D portrait
- [ ] Party members out of range fade like Blizzard's portrait
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
