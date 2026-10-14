# CoD MW2019 / Warzone-style FPS for Roblox (Luau)

First-person gun + movement system with spring-driven procedural animation, two-bone IK arms, a full weapon roster,
lethal / tactical equipment, armor plates, perks and a procedural IK third-person rig. No assets needed (everything has a code-built placeholder).

## Install
**Rojo:** `rojo serve` with `default.project.json`.
**Manual (Studio):**
- `src/shared/*.luau` -> ModuleScripts inside `ReplicatedStorage > FPS` (Folder named `FPS`)
- `src/server/FPSServer.server.luau` -> Script in `ServerScriptService`; `DamageService`, `EquipmentService`, `DataService`, `ScoreService`, `MatchService`, `MapService`, `ObjectiveService` ... -> ModuleScripts next to it
- `src/client/FPSMain.client.luau` -> LocalScript in `StarterPlayer > StarterPlayerScripts`

## Controls (defaults, all rebindable in Settings > Keybinds; controller + touch supported)
WASD move - Mouse look - LMB fire - RMB ADS - R reload - T fire mode (auto / semi on select-fire guns) - 1/2 switch weapon - Shift sprint (double-tap = tactical sprint) - Q / E peek left / right while aiming (otherwise tactical / interact)
C / Ctrl crouch (while sprinting = slide, press again mid-slide to cancel it; hold = prone) - **P** prone (while sprinting = dive, while aiming / firing = drop shot) - **E** climb a ladder (W / S climb, Space lets go) - Space jump (near a ledge = mantle / vault, in the air + strafe keys + mouse turn = air strafe) - **G** lethal (hold to cook) - **Q** tactical - **V** quick melee
**X** armor plate (press again to cancel) - **H** detonate C4 - **E** (hold) revive / finish a downed player - **Shift while scoped** hold breath - **L** Armory - **3 / 4 / 5** kill streaks (**Z** or D-pad up = next ready)
Melee weapons: LMB light attack, RMB heavy / lunge.

## Weapons (`Config.Weapons`, class defaults in `Classes`)
- Pistol: M1911, M19, G18 (auto)  - Revolver: Revolver357, Revolver50  - AR: M4A1, AK47, Grau  - SMG: MP5, P90, UZI
- Shotgun: Model680 (pump), Origin12 (semi), R725 (double barrel)  - LMG: PKM, M91  - Marksman: MK14, SKS
- Sniper: Kar98k, HDR (bolt action, scope overlay, scope sway, hold breath)  - Launcher: RPG7 (rocket), M79 (arcing grenade)
- Melee: CombatKnife, Katana, Sledgehammer (light / heavy, backstab = instant kill)
Reload styles: magazine, cylinder / break-action, shell-by-shell (interruptible by firing), rocket. Cycling: bolt and pump animations.
Add a weapon = one entry in `Config.Weapons` with `Class` + the numbers you want (class defaults fill the rest).

## Prone, dive to prone, drop shot, slide cancel (`Config.Movement`, `Movement.luau`)
- **Prone:** `P` (rebindable, touch gets a PRONE button), or **hold Crouch** for `ProneHoldTime` (this is how a controller gets prone). Jump / Sprint stand you up, Crouch kneels, `P` again stands.
  Prone is slow (`ProneSpeed`), steadier (`ProneSpread` / `ProneRecoil`) and the eye drops to `Eye.Prone`. Other players see the same lying pose as a downed player but with the normal weapon aim,
  and server hitboxes follow it (`Hitbox` stance `Prone`, speed-checked by `MaxProneSpeed`).
- **Dive to prone:** `P` while sprinting (>= `DiveMinSpeed`): a short hop (`DiveHeight`, `DiveSpeed`), no firing / ADS in the air, lands prone with a skid (`ProneSlideSpeed`, `ProneSlideFriction`). `DiveCooldown` between dives.
- **Drop shot:** go prone while aiming or firing: the gun stays up, the eye drops at `DropShotEyeRate`, and for `DropShotTime` spread / recoil use the tighter `DropShotSpread` / `DropShotRecoil`.
- **Slide cancel:** press Crouch again while sliding to drop into a crouch (works in Toggle and Hold crouch modes; ignored for the first `SlideCancelDelay` seconds so a double-tap can't cancel by accident). `P` during a slide goes prone with a skid instead.
- The physical collision capsule does not shrink (same as crouch), so prone does not let you fit under low geometry.

## Mantling, vaulting + air strafing (`Config.Movement.Mantle` / `.AirStrafe`, `Movement.luau`)
- **Mantle:** press (or hold) **Jump** facing a ledge between `MinHeight` and `MaxHeight` studs above your feet. You pull up the wall and roll onto it (`MantleTime`, `RiseShare`),
  ending `EndInset` studs in. Taller walls: jump first, the mantle triggers once the ledge is within reach on the way up. If the ceiling is too low to stand you end crouched.
- **Vault:** the same press on a low (`VaultMaxHeight`), thin (`VaultMaxDepth`) obstacle while moving at it (`VaultMinSpeed`) hops over without stopping and keeps your speed
  (`VaultExitSpeed`, `ExitGlide` / `ExitDecel` for the brake afterwards). Standing still next to it climbs on top instead.
- Both are refused unless the destination (and the peak of a vault) has room for the standing body, so you never end up inside geometry. While climbing, the body follows a path with
  its parts non-colliding; there is no firing / ADS, the gun tucks away (`Config.Viewmodel.Mantle`) and others see an airborne pose. `OnMantle` / `OnMantleEnd` hooks drive the camera kick.
- **Air strafing:** in the air your velocity is accelerated Quake-style instead of by the Humanoid. A direction only adds speed along itself up to `WishCap`, so strafing with the camera
  turning into the same direction (A + mouse left / D + mouse right) gains speed; plain W does not. `MaxSpeed` caps the gain. **Bunny hop:** landing with Jump held keeps your speed
  (`Bhop`, `BhopWindow`, `BhopLoss`) so gains carry from jump to jump.
- Air strafing is **off by default** (`AirStrafe.Enabled = false`): in the air you get the normal Humanoid air control, so you can steer a bit but cannot gain speed by strafing + turning. Set `AirStrafe.Enabled = true` to bring back the Quake-style behaviour (then from standing still you can add about `WishCap` studs/s in the air).
  `Mantle.Enabled = false` turns climbing off. Nothing is replicated beyond the existing stance sync (mantle / vault show as `Air`).

## Ladders (`Config.Movement.Ladder`, `Movement.luau`)
- **Make one:** tag an upright Part (or a Model of parts) `Ladder` with CollectionService, or just use a `TrussPart`. The part's height is the climbable range; put its top level with the platform it leads to.
  Every generated arena has a test ladder on a raised platform in the far corner (`MapService`).
- **Climb:** stand near it, facing it, and the prompt `[E] CLIMB LADDER` shows (Interact key / pad X / touch USE). Press it to step onto the ladder.
  **W / S** (or the move stick up / down) climb up / down. Reach the top and you pull up onto the platform (a mantle); reach the floor and you step off.
- **Let go:** press **Jump** to fall off the ladder (a small push away from it).
- **Aim / fire:** the gun is tucked away while climbing. Holding Aim or Fire pulls the **pistol** (the secondary; any gun if the loadout has no pistol) and **pauses the climb** while you aim, fire or reload.
  When you stop, climbing continues; when you leave the ladder the gun you were holding before comes back. Other actions (plates, equipment, melee, weapon switch) are ignored on a ladder.
- **View limit:** on a ladder the view can only swing 90 degrees either side of the ladder (180 total, `YawLimit`). The body faces the ladder, or follows the view while aiming.
- Others see a climbing player in the airborne pose (no dedicated ladder animation yet). Not done: starting a descent from the top of a ladder.
- Tune everything in `Config.Movement.Ladder` (`ClimbSpeed`, `Reach`, `MountDist`, `YawLimit`, `TopGrab`, `JumpOffSpeed` ...); `Enabled = false` turns it off.

## Flinch + suppression (`Config.Flinch`, `Config.Suppression`)

- **Hit flinch:** every `DamageFX` makes the camera snap (through the camera Shake spring, so the *Camera shake* setting scales it) and jolts the weapon in the hands.
  Strength follows the damage (`DamageRef`, clamped `Min..Max`), the head turns away from the side the shot came from, ADS is steadier (`AdsScale`).
  Fire / gas ticks never flinch; explosions are halved on top of their own shake (`ExplosiveScale`).
- **Near-miss flinch:** `BulletService` checks every ballistic bullet's flight segment against enemy heads / chests. A bullet that passes within `Suppression.Radius`
  without hitting fires `Remotes.Suppress(closeness, origin)` to that player (per-player `Cooldown`, so shotgun pellets give one crack). The client plays
  `Config.Flinch.Suppress`, roughly 40% of a hit at full strength, scaled by how close it passed.
- Tune: `Config.Flinch.Hit / Suppress` (`Pitch`, `Yaw`, `Roll`, `Viewmodel`, `Cooldown`), `Config.Suppression.Enabled / Radius / MinSpeed / Cooldown`.
  Hitscan weapons never cause near-miss flinch (there is no bullet in flight to pass you).

## Bullets: ballistic or hitscan (`Config.Ballistics`, `Ballistics.luau`, `server/BulletService`, `BulletFX.luau`)
Guns fire real bullets like CoD: a muzzle velocity, bullet drop and air drag that bleeds speed off with flight time. Hitscan is still fully supported.
- Path: `dv/dt = gravity - drag * v` solved in closed form (`Ballistics.Pos / Vel`), so speed falls like `e^(-Drag * seconds)`. Server and clients compute the same
  path from `(origin, velocity, fire time)`; nothing is replicated per frame. The shot only adds `ball = { Vels, G, K, T0, Range }` to `FireFX`.
- Server: `BulletService` steps every bullet each Heartbeat and casts a segment from last to new position against world + pose-aware hitboxes (no tunnelling at any speed).
  Damage falloff uses studs travelled. Hit markers are batched per frame (a shotgun blast = one marker). Accuracy stats are written when the last pellet lands or expires.
- Client: `BulletFX` flies the tracer along the same path and ends it on the real surface. Your own tracer starts at the barrel and slides onto the camera path.
- Tune per class in `Config.Ballistics.Classes` (`Speed` studs/s, `Gravity` studs/s^2, `Drag` 1/s). Per weapon: `Ballistics = { Speed = ... }` (see Kar98k / HDR) or `Hitscan = true`.
  Per class: `Classes.X.Hitscan = true`. Everything: `Config.Ballistics.Enabled = false`.
- Attachments: the `Velocity` mod scales muzzle velocity (High Velocity, Long / Short Barrel, Suppressor, Slugs). The gunsmith shows a Velocity bar.
- Launchers (RPG7, M79) and the thrown knife keep their own `Projectile` code in `EquipmentService.Launch`.
- Bullets are resolved against where players are on the server when the bullet passes (no lag compensation), so expect to lead moving targets at range.

## Bullet penetration: wallbangs + collateral (`Config.Penetration`, `Penetration.luau`)
Bullets no longer stop on the first thing they hit. Server (ballistic bullets in `BulletService`, hitscan in `FPSServer`) and clients (tracers / bullet holes in
`BulletFX` + `WeaponController`) all run the same `Penetration.Trace`, so what you see is what the server resolved.
- Power: every bullet carries Power = studs of concrete it can still cross (`Config.Penetration.Classes`: Pistol 0.8 ... Sniper 3.6, Shotgun pellets 0.3).
  Per weapon: `PenPower = n` or `NoPen = true`. Attachments scale it with the `PenMult` mod (new **Full Metal Jacket** ammo, **Slugs** punch further).
- Walls: the thickness along the bullet's direction is measured (a ray cast back from the far side of the part). Cost = thickness x material resistance
  (`Materials`: glass 0.08, wood 0.35, brick 0.9, concrete 1, metal 1.4 ...). Too thick / not enough Power = the bullet stops; otherwise it exits the other side with
  less Power and `damage x max(MinWallMult, 1 - cost / startPower)`. Floors, ceilings and crate tops stay solid (`Floors = false`). A bullet hole is drawn on both faces.
- Bodies: a bullet goes through up to `MaxBodies` players / dummies, paying `BodyCost` Power and `BodyDamage` x damage per body. Corpses cost nothing. Several kills from
  one bullet (or one shotgun blast) pay out the existing **Collateral** medal; a kill that came through a wall also pays **Wallbang** (+ the "Through the Wall" achievement).
  Teammates are passed through like anyone else (no damage unless friendly fire is on).
- Mappers: part Attribute `NoPen = true` (on the part or any ancestor) = bullet proof; `PenResist = number` overrides the material (0 = a free pass, e.g. an empty window).
  The generated arenas have a bullet-proof shell and a few thin wood / brick partition walls to try it on.
- The bullet's flight path is not bent or slowed by what it crosses, only its damage and Power are: that keeps the shared tracer maths exact.
- Turn it off: `Config.Penetration.Enabled = false` (every bullet stops on the first surface again).

## Equipment (`Config.Equipment`)
- Lethal: Frag (cookable), Semtex (sticky), Thermite (sticky, burn zone), Throwing Knife, Claymore (proximity cone), C4 (remote)
- Tactical: Flashbang, Stun, Smoke, Gas, Stim Shot, Heartbeat Sensor
Throws are real physics parts on the server; rockets / launcher grenades / knives follow an analytic path simulated on the server and drawn smoothly on clients.

## Armor plates (`Config.Armor`)
Warzone rules: each plate = 50 armor, up to 3 equipped, carry up to 5, ~2.4 s to apply (can be cancelled; no sprint / fire / ADS while applying).
Armor absorbs damage first; leftover carries into health. Gas ignores armor, fire is half absorbed. Health regenerates after a delay (`Config.Health`).
Plates are visible on the third-person vest.

## Perks (`Config.Perks`, one per slot)
Slot 1: DoubleTime, FlakJacket, Scavenger, Overkill - Slot 2: QuickFix, BattleHardened, FastHands, Amped - Slot 3: DeadSilence, Ghost, SteadyAim.
Pick them in the Armory (L); changes apply on the next spawn (or "Equip + Respawn").

## Third person (R6)
`ThirdPerson.luau` runs on every client for every other player: torso lean / crouch / slide poses, head pitch, custom two-bone IK arms
that hold the weapon (reload, bolt, pump, equipment, plates and melee play from the same animation data as first person), and
raycast foot-planting legs that step when a foot gets too far from the hip (slopes + stairs). The default `Animate` script is removed on R6 characters.
Pose state is replicated from the owning client through the server as character attributes (`StateSync`).
R15 characters are left on the default animations (not covered yet).

### Mantle / vault poses (`ClimbPose.luau`, `Config.Climb`)
`Movement.luau` still drives the body along the climb path; `ClimbPose.Solve(kind, t, rootCF, ledge, depth)` says what the body looks like on it.
One solver feeds three places, so what you see, what others see and what bullets hit agree:
- **First person** (`Viewmodel`): both hands reach for the lip, pull, then press on top of a mantle; the support (left) hand plants on a vault while the gun stays in the right hand.
- **Third person** (`ThirdPerson`): torso lean / drop / roll / yaw, hands planted on the ledge, feet scraping the wall then stepping onto it (mantle) or swung out sideways and tucked over the obstacle (vault), then handed back to the normal foot planting as the body lands.
- **Hitboxes** (`Hitbox`): same torso, arms and legs maths, plus a time limit so a client cannot hold a climb pose.
Replication: the client sends the ledge (a CFrame at the lip, looking into the wall), the obstacle depth and the climb time with `StateSync`; the server validates it
(NaN, distance to the player, rate limit) and writes `Stance = Mantle | Vault` plus `ClimbLedge / ClimbDepth / ClimbStart / ClimbDur` attributes. Everything else is derived from those.
Tuning: every curve is in `Config.Climb` (lean, torso drop, roll, hand / foot weights, leg swing, knee tuck). `VaultHand = "R"` mirrors the vault.

## UI (`Hud.luau`, `Theme.luau`)
Original dark-glass look with an amber accent (all colors / fonts in `Theme.luau`):
- Top: compass strip with heading. Center: crosshair that opens with spread, hitmarker (white / yellow headshot / red kill), directional damage indicators, toasts and progress bar.
- Bottom left: perk chips, three segmented armor plates (flash when hit), carried plates, health number + bar (pulses when low).
- Bottom right: lethal + tactical slots with key caps and count pips, weapon name, fire-mode chip, big ammo counter with magazine bar, low-ammo / reload hints.
- Armory (L, or the ARMORY tab of the main menu): see below.

## Data store + XP (`DataService.luau`, `ScoreService.luau`, `Config.Scoring`, `Config.Progression`)
- **Saved per player:** XP / level, kills, deaths, assists, headshots, best streak, medal counts and your loadout. Autosave every 60 s, on leave and on server shutdown.
  Loading retries 4 times; if it fails the player gets temporary data that is **never saved**, so a bad load can't overwrite real progress.
  In Studio turn on *Game Settings > Security > Enable Studio Access to API Services* or nothing will persist. Change `STORE_NAME` in `DataService.luau` to reset everyone.
- **Tags (all give XP, values in `Config.Scoring.Tags`):** Kill, Headshot, Assist, Assist Kill, Double / Triple / Quad / Penta Kill (4 s chain), Collateral
  (two kills from one shot or one explosion), Knock Down, Armor Break, Longshot, Point Blank, Backstab, Revenge, First Blood, 3 / 5 / 10 Kill Streak.
- **Assists:** deal 20% of the victim's max health within 10 s without the final blow = Assist. Deal 50% = **Assist Kill**, which counts as a kill
  (kill stat, multi-kill chain, streak). Both thresholds, and whether Assist Kills count, are in `Config.Scoring`.
- **Knock Down:** awarded when your hit puts a player into the downed state (see below). Revive and Finisher have their own tags.
- Level curve in `Config.Progression`. HUD: level + XP bar (bottom center), score feed, big banner for medals, level-up toast, `leaderstats` (Level / Kills / Deaths).
- Add your own tag: add it to `Config.Scoring.Tags`, then call `Score.Award(player, "YourTag")` from any server script that has the ScoreService.

### Stats and match history (`DataService.RecordShot / AddWeaponStat / RecordMatch / Stats`)
- **Tracked and saved with the profile:** wins / losses / draws / matches played, shots / hits / head hits (accuracy), headshot kills (`Headshots`, the older field), per-weapon `Shots, Hits, HeadHits, Kills, HeadKills` (`WeaponStats`) and the last 25 matches (`History`: time, mode, map, result, K / D / OBJ, shots, hits, head hits). Existing profiles pick up the new fields automatically.
- **Definitions:** one shot = one trigger pull (a shotgun blast is one shot, a hit if any pellet hit an enemy, a head hit if any pellet hit a head). Friendly hits, launchers, melee and equipment do not count towards accuracy. Weapon kills count guns and knife kills, like weapon XP.
- **Win / loss:** team modes = your team won; free-for-all = first place; no winner = draw. Players who leave mid-match, and matches that end empty, are not recorded.
- **Best gun** = the gun (not melee) with the most kills. `Stats.WinLoss` is wins / losses (equals your wins while you have no losses), `Accuracy` = hits / shots, `HeadshotRate` = headshot kills / kills.
- **Reading it:** `RemoteFunction GetStats` returns `DataService.Stats(plr)` (K/D, win/loss, win rate, accuracy, headshots, best gun, sorted weapon list, history newest first). There is no stats screen yet; build one on that remote.

### Spawn system (`server/SpawnService`, tuning in `Modes.Config.Spawn`)
- Every spawn point is scored: distance to the nearest enemy, a bonus for being near a teammate (team modes), minus enemies that can see it (raycast from their eyes, walls block it, more if they face it), recent deaths and enemy gunfire nearby and recently used spawns (also spreads a team that spawns together).
- Unsafe spawns are skipped: enemy too close, enemy with a clear view within 90 studs, somebody standing on it, solid geometry or no ground there. The best safe spawn wins.
- Spawn trapping prevention: dying within 6 s of spawning marks that spawn as a trap for 25 s, 3 quick spawn kills flag the killer as a camper (60 stud no-go radius around him), and a team spawn killed twice in 20 s may spawn anywhere safe on the map, enemy side included.
- Safe respawns: if nothing is safe the spawn waits up to 2 s (not in round modes), the pick is re-checked after the character loads, spawning anyway gives double spawn protection, and firing or meleeing ends spawn protection (so it cannot be used to shoot while invulnerable).

### Achievements and weapon mastery (`server/AchievementService`, data in `shared/Achievements` + `shared/Mastery`)
- ~50 achievements (combat, match, progress, mastery) driven by score tags, wins, streaks and level. Each pays XP / credits and some a title or emblem. Saved in `AchProgress` / `AchDone`.
- Mastery: Bronze / Silver / Gold / Platinum / Diamond per weapon, needing weapon level + kills + headshot kills with it. Each tier pays credits and XP once per weapon; the first weapon to reach a tier also grants a title and emblem. Saved in `Mastery[weapon]`.
- Reward-only cosmetics (`Reward` field in `Cosmetics.luau`) are not for sale; the Cosmetics page shows where to earn them.
- Remotes: `GetAchievements`, `GetMastery` (for a screen, none built yet), `AchievementEvent` (toasts). The tier's camo name is saved and sent but no gun model paints it yet.

## Downed state (`Config.Down`, `DamageService.luau`)
A hit that would kill a player puts them **down** instead (players only, not dummies; suicides and self-kills still kill).
- Downed players crawl (`CrawlSpeed`), can't jump / sprint / slide, can only use a pistol or revolver, and bleed out over `BleedTime`.
  Further hits drain the same bar; at 0 they die and the kill goes to whoever finished them (or to whoever downed them if they bled out).
- **Revive:** a teammate holds **E** next to them (`ReviveTime`). They come back with `ReviveHealth` and no armor. Needs `Player.Team` set and equal.
- **Finish:** an enemy holds **E** (`FinishTime`) to execute them. Set `AllowFinish = false` to turn it off.
- Interrupted if the reviver / finisher moves away, gets hurt, or is downed. Plates and equipment are cancelled when you go down.
- XP: Knock Down (the player who downs), Revive, Finisher, plus the normal Kill when they die.
- Third person shows a prone pose with legs trailing; first person shows a low camera, lowered sidearm and a red "YOU ARE DOWN" screen with the bleed-out bar.
- Hitboxes follow the prone pose (see Hitboxes). Without teams (`Player.Team == nil`) nobody can revive; everyone can only finish.
- Turn the whole thing off with `Config.Down.Enabled = false` (lethal hits kill as before).

## Hitboxes (`Hitbox.luau`, `Config.Hitbox`)
The server never sees crouch / slide / prone (they are drawn locally), so its R6 parts are always standing. `Hitbox.luau` rebuilds every R6 player as
six boxes (Head, Torso, both arms, both legs) from the same pose maths `ThirdPerson.luau` uses (`Config.ThirdPerson.StanceDrop` / `StanceFwd`, aim pitch,
strafe roll) and the `Stance` / `AimPitch` / `Down` character attributes, smoothed the same way, and tests rays against those instead.
- Used by: bullets (every pellet), melee sphere sweeps, thrown knives, rockets / launcher grenades, and the local tracers.
  Explosions, claymores and gas / fire zones measure from the posed chest (a prone player is low) and ignore standing phantom bodies for line of sight.
- Hits return the real part (`Head`, `Torso`, `Left Arm` ...) so damage multipliers and headshot checks work unchanged.
- Anti-cheat: `Downed` is only honoured when the server set the `Down` attribute, a `Slide` below `MinSlideSpeed` counts as a crouch, a `Crouch` above `MaxCrouchSpeed` counts as walking.
- **Physical objects:** thrown grenades, Semtex, C4 and thermite are put in a `Thrown` collision group. They collide with invisible proxy parts that follow the boxes
  (the real character parts ignore that group), and sticky items stick to the posed body part they hit and move with it. Proxies only move while a thrown object is within
  `Config.Hitbox.PhysicalRange` of the player, so there is no constant replication cost. For your own physics props: `Hitbox.TrackPhysical(part)` on the server.
  Other map parts (unanchored props) still collide with the real standing parts. Turn off with `Config.Hitbox.Physical = false`.
- Dummies, R15 characters and dead bodies fall back to their real parts. `Config.Hitbox.Enabled = false` restores the old behaviour.
- **F8** (while `Config.Debug` is true) draws the boxes on your client: red head, orange torso, yellow arms, blue legs. Tune sizes in `Config.Hitbox`.

## Own gun model
Put it in `ReplicatedStorage > FPS > Weapons` named like the weapon key. PrimaryPart `Body`, barrel along -Z, optional parts `Mag` / `Pump` / `Bolt`,
Attachments `RightGrip`, `LeftGrip` (omit = one-handed), `Aim`, `Muzzle`, `Eject`.

## Known limits
- Written without access to Studio: never run. Expect to tune numbers and fix small bugs; check the Output window first.
- Hitboxes are boxes rebuilt from the stance + aim pitch the client reports (sanity-checked, no lag compensation). Only parts tracked with `Hitbox.TrackPhysical` follow the pose; other physics props still hit the real standing R6 parts.
- Corner peek is client-driven: the server only accepts the reported lean while the player is aiming in an upright stance (Idle / Walk / Crouch) and clamps it to -1..1. The firing origin is the leaned camera, which stays inside the existing 12-stud origin check.
- Server trusts client aim direction (with origin / rate-of-fire checks). Harden for competitive games.
- Sounds are empty slots: `Config.Weapons.*.Sounds.Fire`, `Config.Footsteps`. Explosions use Roblox's built-in `Explosion` visual (pressure 0).
- Gyro aiming is not implemented. Aim assist is a simple slowdown over enemies (no rotation / magnetism).
- The menu, input and mobile layer is also untested in Studio (see Menu + Settings below).

## Main menu + Settings (`MainMenu`, `SettingsMenu`, `Settings`, `InputMap`, `MobileControls`, `Widgets`)
- **Menu key** (default M, controller VIEW, touch MENU button) opens the front end: Deploy, Armory and Cosmetics are built, Battle Pass / Store are placeholders
  (`MainMenu.RegisterPage("STORE", function(holder, menu) ... end)` replaces one). **Settings is complete.** LB / RB switch tabs, B goes back.
- **Settings pages:** Graphics, Keyboard & Mouse, Keybinds (keyboard/mouse and controller, swap-on-conflict, reset), Controller (presets, southpaw, per-axis sens,
  deadzones, response curve, trigger point, aim assist, vibration), Mobile, Interface (menu/HUD scale, crosshair, hitmarkers, compass, Xbox/PlayStation names), Audio, Gameplay (hold/toggle ADS, crouch, sprint mode).
- **Add an option:** one entry in `Settings.Pages` (Key, Type, Default, Min/Max...). The menu, defaults, saving and server validation pick it up. Read it with `Settings.Get("Section.Key")`,
  react with `Settings.OnChanged`.
- **Saving:** `Settings` -> `SaveSettings` remote -> `SettingsSchema.Sanitize` on the server (clamps, drops unknown keys) -> `DataService` profile (`Settings` field). Loaded on join via `GetSettings`.
- **Input:** gameplay code no longer reads keys. `InputMap.OnBegan("Fire", fn)`, `InputMap.IsDown("Jump")`, `InputMap.GetMoveVector()`, `InputMap.GetLook(...)`. Keyboard, mouse wheel, gamepad (analog triggers with
  your pull point) and touch all feed the same actions. The default Roblox control module is disabled; `Movement` drives the humanoid.
- **Mobile:** `MobileControls` = move stick (fixed/floating, push to sprint), look drag, hold buttons, sprint lock, optional second fire button, drag-while-firing aim.
  Settings > Mobile > *Customize touch layout* opens the editor: drag, size, opacity, hide/show, mirror (left-handed), reset, save/cancel. Layout is saved with your settings.
- **Audio:** sliders drive SoundGroups under `SoundService.Master` (SFX / Music / Voice / UI). Assign sounds with `sound.SoundGroup = Settings.SoundGroup("SFX")`.
- **Graphics:** quality level (pcall, Roblox may ignore it), FOV, brightness/contrast, shadows, bloom / sun rays / depth of field toggles, head bob + camera shake scaling, FPS / ping overlay.
- Changes to existing files: `Movement`, `WeaponController`, `CameraRig`, `Hud` (scaled root, crosshair options, dynamic key chips), `DataService` (Settings field), `FPSServer` (2 remotes), `FPSMain`.
  `Config.Keys` is now only used for the F8 hitbox debug key.

## Match flow: voting, deploy, modes (`MatchService`, `MapService`, `Modes`, `DeployPage`, `MatchClient`, `MatchHud`)
`Voting (30 s) -> Match -> Results (12 s) -> Voting ...` Everything is server-driven and replicated through attributes on `ReplicatedStorage.FPS.MatchState`.
- **Voting:** the DEPLOY tab lists every mode and 3 random maps; click to vote (live counts, plurality wins, ties random). DEPLOY = ready (tap again to cancel).
  The match starts when the timer ends and at least one player is ready, or 5 s after everybody is ready.
- **Match:** players are balanced onto two teams (or free for all), spawn on the map (farthest spawn from enemies, 2.5 s spawn protection) and respawn after a delay.
  Players who join mid-match press DEPLOY and spawn straight in. The menu closes when you spawn; **M** reopens it.
- **Modes** (`Modes.List`): Team Deathmatch (50 kills), Free For All (25), Hardcore TDM (30 health, no armor, friendly fire), Down and Out (elimination rounds, no respawns,
  downed / revive on, first to 3 rounds). **Domination**, **Kill Confirmed** and **Hardpoint** are objective modes (see below). Extraction and DMZ are listed as LOCKED until they are built. Downed state is only on in Down and Out.
- **Results:** victory / defeat / draw screen with the top 8 players; characters are removed (not killed, so no fake deaths) and the map is unloaded.
- **Maps** (`Modes.Maps`): four arenas are generated from code (high above the baseplate), so it plays immediately. For your own map put a Model named like the map id in
  `ServerStorage > Maps` with a Folder `Spawns` of parts that have a `Team` attribute (`Alpha`, `Bravo` or `Any`); the part's facing is the spawn facing.
- **Setup notes:** the server sets `Players.CharacterAutoLoads = false`, so nobody spawns until the match puts them in. Teams `Alpha` / `Bravo` are created automatically.
- Solo testing: team scores only count player kills (dummies don't score). Use two clients (Studio > Test > Local Server, 2 players) to see a match end.

## Armory: classes, gunsmith, unlocks, buy forward, perks, equipment, kill streaks (`Armory`, `ArmoryPage`, `ArmoryClient`, `ArmoryService`, `StreakService`)
Open it with **L** or the ARMORY tab. Three columns: your 10 classes | the slots of the class (or the list you are picking from) | details with stat bars.
- **Classes:** 10 custom classes (5 at the start, 6-10 unlock at levels 10 / 15 / 20 / 25 / 30). A class = primary + secondary (with attachments), lethal, tactical, 3 perks, 3 kill streaks, and a name.
  SELECT CLASS = the class you spawn with (applies on the next spawn). EQUIP + RESPAWN shows while you are in a match; the server only allows it right after spawning.
  Old saved loadouts become class 1 (anything not unlocked falls back to the starter item).
- **Gunsmith:** 7 slots (optic, muzzle, barrel, underbarrel, magazine, ammunition, stock), max 5 attachments, 44 attachments in `Armory.Attachments`. Stat bars show the change (green / red) before you equip.
  Attachments are stat modifiers (`Mods`: damage, range, rpm, mag, reload, ADS time / fov, move speed, recoil up / side, spread, suppressed, overlay scope, slugs...).
  **Magazines** (slot 5): Extended Mag, Fast Mag, Drum Mag, Dual Mags (fast empty reload), Lightweight Mag, Extended Belt Box (LMG), Stripper Clip (sniper), Speedloader / Extended Cylinder (revolver),
  Extended Tube / Shell Carrier (shotgun), and the Ammo Bandolier (+50% spare ammo, any gun). Mods `Reserve` / `ReserveAdd` change `Reserve`, `ReloadEmpty` only the empty-reload time.
  **Ammunition** (slot 6): High Velocity, Full Metal Jacket, Overpressured, Hollow Point (more damage, almost no wall penetration), Subsonic (quiet, slow), Armor Piercing (`ArmorPierce` = share of each hit that skips plates,
  `DamageService.Apply` reads `info.ArmorPierce`), Incendiary (`Burn = { Dps, Time }`, `DamageService.Burn`: fire damage over time, refreshed not stacked), Slugs, Flechette (`PelletAdd`), Dragon's Breath (shotgun, burns).
  **Trade-offs:** no attachment is a free upgrade. Every one buys something and costs something, and the costs are big enough to feel. Weight and bulk (long barrel, drum, belt box, bipod, heavy stock, bandolier)
  slow `AdsTime`, `Move` and the new `SprintOut` mod (multiplies `SprintOutTime`, how long after sprinting you must wait before firing); light parts (short barrel, skeleton / no stock, lightweight mag) do the opposite but cost range, recoil control or rounds.
  Examples: Long Barrel = +22% range / +15% bullet speed but 14% slower ADS, -4% move speed, 20% slower sprint out, wilder hip fire. Extended Mag = +40% rounds but slower reload, aim and sprint out. Drum = double rounds, 35% slower reload, -5% move.
  The Handling stat bar now counts both ADS time (70%) and sprint-out time (30%).
  The weapon detail also has a Reserve bar now. Magazine attachments are drawn on the gun (`AttachmentVisuals`); ammo types have no model, their effect shows in the stats / notes.
  `Armory.Build(weapon, attachments)` produces the config the gun really uses: the server uses it for damage / ammo / reload / rate of fire, the client for recoil, spread, scope and animation, so both agree.
  Suppressed shots are only seen and heard within 45 studs. Attachments are drawn on the gun (first person, third person) by `AttachmentVisuals.luau`.
- **Unlocks:** weapons, equipment, perks, kill streaks and class slots unlock at a player level (tables at the top of `Armory.luau`). Attachments unlock at a weapon level:
  every kill with a weapon gives weapon XP (100, +50 headshot; `Armory.WeaponLevelXP` = 7 levels), and you get a toast when something unlocks.
- **Buy forward:** any locked item can be bought with credits. Price = missing XP x rate, clamped (`Armory.Econ`), so the closer you are the cheaper it gets. Locked items show a progress bar.
  Credits come from XP (`CreditsPerXP`) plus a level-up bonus, you start with 300. The price is computed on the server (`ArmoryService`), the client only displays it.
  `Armory.UnlockAll = true` unlocks everything for testing.
- **Perks / equipment:** same pickers with unlock levels and descriptions (the effects already existed). Overkill still allows two primaries.
- **Kill streaks** (`StreakService`, params in `Armory.Streaks`): earned by consecutive kills, one use each per life, lost on death. Keys 3 / 4 / 5 (rebindable, Settings > Keybinds > Kill streaks), touch STREAK button, D-pad up.
  UAV (3 kills, your team's minimap sweeps the enemies; no through-wall highlight), Resupply (4), Precision Airstrike (5, aim at the ground), Armor Cache (5), Mortar Barrage (6, aim), Chemical Strike (7, aim). Chips above the XP bar show progress / READY.
  Add one: an entry in `Armory.Streaks` + `Armory.StreakOrder` and a `Run.YourStreak` function in `StreakService`.
- **Saved data** (`DataService` profile): Credits, Bought, WeaponXP, Classes, Selected. Server remotes: `GetArmory`, `ArmoryBuy`, `ArmorySave`, `ArmorySelect` (all re-validate; see `Armory.SanitizeClass`).
- Not done: weapon camos / reticles, perk packages, a streak announcer sound, in-match class switching without respawn.

## Cosmetics: operators, player cards, emblems, titles, emotes, tracers (`Cosmetics`, `CosmeticsPage`, `CosmeticsService`, `Emotes`, `TracerFX`, `PlayerCard`, `RigPreview`, `EmoteClient`)
The COSMETICS tab has the same three-column layout as the Armory: categories | item grid | live preview + details. Unlocks work like the Armory: every item has a player
level; reach it or buy it early with credits (price drops as you get closer, rarer items cost more; `Armory.UnlockAll = true` unlocks everything for testing).
- **Operators:** placeholder colored rigs (`Cosmetics.luau`, colors per body part + a visor band). "Your Avatar" leaves the Roblox avatar alone. Applied on spawn by `CosmeticsService`
  (BodyColors, clothes / accessories removed, band part), mirrored on the procedural third-person limbs / vest (`ThirdPerson.applyOperator`) and the first-person sleeves (`Viewmodel:SetColors`).
  Swap in real models later by reading the `Operator` character attribute.
- **Player cards / emblems / titles:** `PlayerCard.Build` draws the banner (gradient + pattern, emblem, name, title, level). Everyone's choices are player attributes
  (`CosCard`, `CosEmblem`, `CosTitle`), shown for the top player on the results screen (`PlayerCard.Options(player)` gives you any player's card anywhere else, e.g. a kill cam).
- **Emotes:** 8 procedural emotes (`Emotes.luau`, no animation assets), 6 wheel slots. Press **B** (rebindable, touch EMOTE button) to open the wheel while standing still,
  pick with mouse / touch or 1-6. The camera swings in front of you (`CameraRig.OrbitOn`) and your own body is shown for the length of the emote. Moving, shooting, jumping or taking damage cancels it.
  The server validates the emote is equipped and that you are idle (`CosmeticsService`).
- **Tracers:** 9 styles (`TracerFX.luau`: color, width, length, speed, glow trail, sparks, rainbow). The style is the shooter's `CosTracer` attribute, so everybody sees it; impact sparks match the color.
- **Add an item:** one `add(...)` line in `Cosmetics.luau` (emotes also need a pose in `Emotes.luau`).
- **Saved data:** `Cosmetics` field in the profile (owned + equipped). Remotes `GetCosmetics`, `CosmeticsBuy`, `CosmeticsEquip`, `Emote`; all re-validated server side.
- Changed files: `ThirdPerson`, `CameraRig`, `WeaponController` (tracers), `Viewmodel`, `Settings` (Emote key + touch button), `MatchHud`, `DataService`, `FPSServer`, `FPSMain`.
- Untested in Studio like the rest: check the Output window first. Not done: in-match emote sounds, finishers / kill effects, real operator models.

## Objective modes (`ObjectiveService`, `ObjectiveClient`, `Modes.List` entries with `Objective = ...`)
Team score comes from the objective, not from kills (kills still count for stats, XP and streaks). Everything is server-authoritative; the client only draws attributes on `MatchState`.
- **Domination** (200 pts): flags A / B / C. Stand in a flag to push its bar to your team; both teams inside = contested. Neutral to owned takes `CaptureTime` (8 s) for one player (2-3 players are faster).
  Enemy progress first neutralises, then captures. Each owned flag = 1 point every `ScoreInterval` (5 s). "Under attack" warnings, Capture / Neutralize XP.
- **Kill Confirmed** (65 pts): every death drops a dog tag (`TagLife` 25 s, `MaxTags` 36). An enemy collecting it = **Confirmed** (+1 team point), a teammate collecting it = **Denied**. Red tags = confirm, blue = deny.
- **Hardpoint** (250 pts): one hill at a time, 1 point per second for the team alone inside. It moves every `HillTime` (60 s); the next hill is shown `HillPreview` (10 s) early, with a `HillGap` pause. XP every 5 s on the hill.
- **Objective positions:** the generated arenas place them automatically (cover is kept off the flag poles). For your own map add `Objectives` to the map model: parts with attributes `Kind = "Flag"` + `Label = "A"`, or
  `Kind = "Hill"` + `Order = 1..n` (optional `Radius`). Without that folder the positions are derived from the team spawns.
- New XP tags in `Config.Scoring.Tags`: Capture, Neutralize, HillHold, Confirmed, Denied. A new objective mode = a `start...` function in `ObjectiveService` + a `Modes.List` entry.

## Match presentation (`MatchPresentation`, `DeathPresentation`, `CineCam`, `ScreenFX`, `UISound`)
All client side, driven by `MatchEvent` messages from `MatchService` (see its header). Timings live in `Modes.Config` (`IntroTime`, `CountdownTime`, `EndPresentTime`, `ResultsTime`).
- **Match start:** fade from black, map flyover (sweeps across the flags / hills), title card (mode, map, your team, objective `Brief`), then 3-2-1 and FIGHT. Everybody is anchored at spawn, cannot fire (`WeaponController:SetLocked`)
  and cannot be hurt until it ends; the match clock starts at FIGHT. Players deploying mid-match get a short banner instead.
- **Match end:** cinematic bars, VICTORY / DEFEAT / DRAW with the reason (score limit, time limit ...) and score, camera orbits your operator, then the scoreboard slides in and the screen fades out before the next vote.
- **Death:** red edges, desaturate + blur, you fall, then a **killcam** through the killer's eyes with their player card, weapon, distance and headshot, respawn bar, fade to black. No killer = orbit your body. Modes without respawns spectate teammates (Fire = next).
- **Spawn:** fade in, colour returns, blue glow + SPAWN PROTECTION bar for the invulnerability window.
- `CineCam.Play({ Update = function(t, dt) return CFrame end, fov = 70, In = .5, Out = .5 })` runs any scripted shot on top of the first-person rig. `ScreenFX` has fade / letterbox / vignette / flash / grade.
- **Sounds** are empty slots like the weapons: `UISound.Slots.Tick = "rbxassetid://..."` (Intro, Tick, Fight, Victory, Defeat, Death, Respawn, Capture, Lost, Confirm, Deny, Warn).
- Killcam is a live view of the killer, not a replay of the last seconds. The respawn "Respawn" MatchEvent was replaced by "Death" (carries `Delay`).
- Untested in Studio like the rest: expect to tune camera heights / timings; check Output first.

## Minimap, full map, scoreboard (`Radar`, `Scoreboard`)
- **Minimap** (top left, rotates with your view; Settings > Interface: on/off, size, range). **Allies** are always shown with a facing tick. **Enemies** are only shown when "known":
  - **UAV** (the existing kill streak, `Armory.Streaks.UAV`): every 3 s the radar sweeps and snapshots every enemy (position + facing); dots stay where the sweep saw them and fade until the next sweep. The whole team benefits, the countdown shows under the map,
    and the Ghost perk hides you from the UAV. There is no through-wall highlight: the UAV is minimap-only.
  - **Gunfire**: an enemy firing an unsuppressed weapon shows for 2 s where the server saw them stand (suppressed shots from attachments never ping; max one ping per 0.2 s per shooter).
  - Flags (lettered squares coloured by owner), the active hill (ring) + next hill (dim ring) and dog tags (red = confirm, blue = deny) are shown too; off-range objectives stick to the edge.
- **Full map** (**N**, touch MAP button): north-up view of the whole arena. It draws the arena bounds and markers, not the geometry, so it works on any map.
- **Scoreboard** (hold **Tab**, touch SCORES button): both teams (or a ranked free-for-all list) with kills, deaths and OBJ in objective modes. Roblox's own player list is turned off.
  Per-player data is replicated as attributes `MatchKills`, `MatchDeaths`, `MatchObj`; the map bounds as `MapCenter` / `MapSize` on `MatchState`.
- Both keys are rebindable (Settings > Keybinds > Interface).
- **Server-sided enemy info** (`server/RadarService`, remote `RadarSync`): UAV state is kept on the server only (the old `UAVUntil` player attribute is gone), the server builds each sweep and gunfire ping and sends it only to the players who should see it, and `Radar` merely draws what it receives. A client can no longer fake a UAV or a ping. Allies are still drawn from their replicated characters.
  Limit: Roblox still replicates every character to every client, so an exploiter can read enemy positions from the world itself. Closing that needs StreamingEnabled-style interest management or custom replication, which this project does not do.
