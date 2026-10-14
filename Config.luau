local rad = math.rad
local Config = {}

Config.Debug = true

-- Default loadout (players can change it in the loadout menu, key L; applied on next spawn)
Config.Loadout = {
	Primary = "M4A1", Secondary = "M1911", Lethal = "Frag", Tactical = "Flash",
	Perks = { "DoubleTime", "QuickFix", "DeadSilence" }, -- one per slot (see Config.Perks)
}

Config.Keys = {
	Lethal = Enum.KeyCode.G, Tactical = Enum.KeyCode.Q, Melee = Enum.KeyCode.V,
	Plate = Enum.KeyCode.X, Detonate = Enum.KeyCode.H, Interact = Enum.KeyCode.E, Loadout = Enum.KeyCode.L, Breath = Enum.KeyCode.LeftShift,
	HitboxDebug = Enum.KeyCode.F8,
}

Config.Camera = {
	HipFov = 80, SprintFov = 3, TacFov = 4,
	Sensitivity = 0.0022,
	RecoilDelay = 0.12, RecoilRecover = 4,
	ScopeSway = 0.35,                    -- degrees of idle sway while scoped (0 when holding breath)
	-- Corner peek (Q / E while aiming down sights). The body leans about the hip: Angle = full lean (radians), Lever = eye -> hip
	-- distance (studs; stand = Eye.Stand + 1), so the head sweeps out sideways by about Lever * sin(Angle).
	-- Time = seconds to reach full lean, MinAds = how far into the ADS the peek is allowed (0..1),
	-- Clearance = gap (studs) kept between the camera and a wall so the view never clips into the corner.
	-- ThirdPerson.luau and Hitbox.luau lean the body / hitboxes by the same Angle, so what you peek is what gets shot.
	Peek = { Angle = rad(20), Lever = 2.6, Time = 0.16, MinAds = 0.35, Clearance = 0.5 },
}

-- Flinch: the camera + viewmodel jolt when you are shot (Hit) or a bullet cracks past your head (Suppress).
-- Both feed the camera Shake spring (so the "Camera shake" setting scales them). Pitch/Yaw/Roll are roughly radians of peak kick at Strength 1
-- (0.07 = ~4 degrees); the head snaps away from the side the shot came from.
--   Hit      = damage taken. Strength = damage / DamageRef (clamped Min..Max), so a 20 dmg graze is lighter than a 100 dmg shot.
--   Suppress = near miss. Strength = MinStrength..1 depending on how close the bullet passed. About 40% of a Hit at full strength.
--   Viewmodel = how hard the weapon jolts in the hands. Cooldown = minimum seconds between flinches of that kind.
--   AdsScale = multiplier while fully aiming down sights (the flinch is steadier when braced)
Config.Flinch = {
	Hit      = { Pitch = 0.07,  Yaw = 0.045, Roll = 0.05, DamageRef = 40, Min = 0.5, Max = 1.6, Viewmodel = 1.0, Cooldown = 0.05 },
	Suppress = { Pitch = 0.03,  Yaw = 0.018, Roll = 0.022, MinStrength = 0.4, Viewmodel = 0.35, Cooldown = 0.16 },
	AdsScale = 0.6,
	ExplosiveScale = 0.5, -- explosions already shake the camera hard; the damage flinch is halved on top of that
}

-- Near miss (server): a ballistic bullet that passes within Radius studs of an enemy's head / chest and was NOT a hit
-- sends that player a Suppress event. One event per bullet per player; shotgun pellets collapse into one per shot.
Config.Suppression = {
	Enabled = true,
	Radius = 6,        -- studs from the bullet path to the head
	MinSpeed = 700,    -- bullets slower than this (shotgun pellets far out) are too slow to crack
	Cooldown = 0.12,   -- seconds between events sent to the same player
}

Config.Movement = {
	WalkSpeed = 12, CrouchSpeed = 6.5, SprintSpeed = 18, TacSpeed = 21.5,
	TacTime = 4, TacDoubleTap = 0.3,
	Accel = 90, Decel = 120,
	JumpHeight = 5.5,
	SlideMinSpeed = 15, SlideSpeed = 26,
	SlideBoost = 1.2, SlideMax = 34,
	SlideFriction = 19, SlideSlope = 55,
	SlideSteer = 0.8, SlideEndSpeed = 9, SlideCooldown = 0.45,
	SlideCancelDelay = 0.1,              -- a second crouch press ends the slide, but not within this many seconds of starting it (stops a double-tap cancelling by accident)
	CrawlSpeed = 3.2,
	-- prone (Prone key, or hold Crouch for ProneHoldTime). Jump / Sprint stand you up, Crouch drops you to a crouch.
	ProneSpeed = 3.6, ProneHoldTime = 0.45,
	-- dive to prone: Prone while sprinting. A short forward hop, then you land prone and skid a little.
	DiveMinSpeed = 14, DiveHeight = 2.2, DiveSpeed = 23, DiveCooldown = 0.6,
	ProneSlideSpeed = 14, ProneSlideFriction = 36, -- skid after a dive / slide-to-prone (capped at ProneSlideSpeed, bleeds off at Friction studs/s^2)
	-- drop shot: going prone while aiming or firing keeps the gun up, drops the eye much faster, and tightens spread for a moment
	DropShotTime = 0.6, DropShotEyeRate = 30, DropShotSpread = 0.55, DropShotRecoil = 0.7,
	ProneSpread = 0.6, ProneRecoil = 0.7, -- steady-prone multipliers on bullet spread / camera recoil
	Eye = { Stand = 1.65, Crouch = 0.45, Slide = -0.35, Prone = -1.55, Down = -1.7 },
	-- air strafing (Quake / CS style). In the air the Humanoid's own air control is replaced: holding a direction only accelerates you along it
	-- while your speed in that direction is below WishCap, so you cannot simply steer at full speed. Turn the camera into the direction you
	-- strafe (A + mouse left, D + mouse right) and the velocity keeps rotating while it picks up speed. That sideways gain is the strafe.
	AirStrafe = {
		Enabled = false,      -- OFF: normal Humanoid air control (you can nudge your direction a bit while airborne). true = Quake-style air strafing / bhop
		Accel = 8,           -- air acceleration, in multiples of your ground speed per second (studs/s^2 = Accel * current base speed)
		WishCap = 3.2,        -- studs/s: most speed one input can add along its own direction (small cap = strafing is what makes you fast)
		MaxSpeed = 32,        -- strafing never pushes your horizontal speed above this (a faster slide-hop / launch is left alone)
		Step = 1 / 60,        -- fixed step the air accel runs at, so the gain does not depend on frame rate
		Grace = 0.06,         -- seconds off the floor before air control takes over (ramps and stairs do not count)
		Bhop = true,          -- landing while Jump is held keeps your speed instead of braking, so strafe gains carry from jump to jump
		BhopWindow = 0.15,    -- seconds after landing during which the ground does not slow you (only when Jump is held)
		BhopLoss = 0.03,      -- fraction of horizontal speed lost per landing
	},
	-- mantling and vaulting: press Jump (or hold it) facing a ledge. Ledges taller than a step but within reach are climbed (mantle); low,
	-- thin obstacles (a wall, a fence, a counter) are hopped over without stopping (vault) when you are moving.
	Mantle = {
		Enabled = true,
		Reach = 2.6,          -- studs from the root to look for a wall (root centre to wall face; the body is ~1 stud wide each side)
		MinHeight = 2.6,      -- ledge top above your feet: lower than this is just a step / ordinary jump
		MaxHeight = 5.6,      -- ...and no higher than this above your feet (arms reach). Jump first for taller walls: mantling triggers at the apex
		VaultMaxHeight = 4.6, -- tallest obstacle that can be vaulted rather than climbed
		VaultMaxDepth = 3.6,  -- thickest obstacle (top surface, along your heading) that can be vaulted
		VaultMaxDrop = 4,     -- how far below the obstacle top the far side floor may be
		VaultMinSpeed = 7,    -- you have to be moving this fast toward the obstacle to vault it (slower = mantle on top, or nothing if it is too thin)
		VaultExitSpeed = 17,  -- minimum speed you leave a vault with (entry speed is kept if higher)
		VaultArc = 0.5,       -- how far your feet clear the obstacle top at the peak of the vault
		EndInset = 1.25,      -- studs onto the ledge the body ends up (root centre from the wall face): needs a ledge at least this deep
		MantleTime = { Min = 0.46, Max = 0.8, Base = 0.34, PerStud = 0.045 }, -- Dur = clamp(Base + height * PerStud, Min, Max)
		RiseShare = 0.55,     -- fraction of a mantle spent pulling up the wall; the rest is moving over the ledge
		VaultTime = { Min = 0.32, Max = 0.6 }, -- vault duration = path length / speed, clamped
		Angle = 0.5,          -- how head-on you have to face the wall (dot of facing and -wall normal)
		Cooldown = 0.35,      -- seconds after a mantle / vault before another can start
		ExitGlide = 0.5,      -- after a vault, seconds the floor brakes you at ExitDecel instead of the normal Decel
		ExitDecel = 35,       -- studs/s^2
		Buffer = 0.25,        -- a Jump press is remembered this long, so pressing a hair early still mantles
		MaxFallSpeed = 45,    -- you cannot grab a ledge while falling faster than this
	},
	-- ladders (Movement.luau): tag a Part "Ladder" (CollectionService) or use a TrussPart. Stand near it facing it and press Interact to climb.
	-- W / S (stick up / down) climb, Jump lets go, aiming or firing pulls the pistol and pauses the climb. The part must be upright; its
	-- height is the climbable range and its top should be level with the platform it leads to.
	Ladder = {
		Enabled = true,
		Tag = "Ladder",
		Reach = 3.2,          -- studs from the root to the face of the ladder to be offered the climb prompt
		SideSlack = 0.6,      -- studs beyond the ladder's width you may stand and still grab it
		FaceDot = 0.25,       -- how directly you must face the ladder to be offered the prompt (dot of facing and direction into the ladder)
		MountDist = 1.35,     -- root centre this far in front of the ladder face while climbing
		MountTime = 0.25,     -- seconds to step onto the ladder (the view also turns to face it over this time)
		YawLimit = math.rad(90), -- while climbing the view may swing this far either side of the ladder = 180 degrees in total
		ClimbSpeed = 8,       -- studs/s at full input
		Accel = 45,           -- studs/s^2 speeding up / stopping
		Deadzone = 0.15,
		TopGrab = 0.6,        -- reaching this far below the top of the ladder (feet) pulls you up onto the platform
		TopInset = 1.6,       -- studs past the ladder face where you stand after the top pull-up (needs floor there)
		TopRise = 3.5,        -- how far above the ladder top to look for that floor, and
		TopDrop = 2.5,        -- how far below it
		JumpOffSpeed = 6,     -- studs/s away from the ladder when you jump off
		JumpOffUp = 6,
		Cooldown = 0.35,      -- seconds after leaving a ladder before another can be grabbed (and a ledge mantled)
		SwayFreq = 0.9,       -- camera sway cycles per stud climbed
		SwayRoll = 0.8,       -- degrees of that sway
	},
	-- Collision capsule per stance. The standing R6 body is 5 studs tall (root centre 3 studs above the floor). Crouch / slide / prone /
	-- dive / downed swap it for ONE box (the HumanoidRootPart, resized) whose top sits EyeClearance above the camera, so you fit under low
	-- geometry and the camera never pokes through the ceiling. Movement.luau applies it, and refuses to stand up where there is no room.
	Capsule = {
		StandRootY = 3,        -- root centre above the floor while standing
		LegHeight = 2,         -- R6 leg length: it is what the Humanoid adds to HipHeight, so lowered stances cancel it with a negative HipHeight
		Girth = 1.8,           -- width and depth of the lowered box
		EyeClearance = 0.25,   -- studs of collider above the eye
	},
}

-- Derived: Config.Movement.Collider[stance] = { Height, RootY, RootDrop, Size }. RootDrop = how far lower the root sits than when standing.
do
	local M = Config.Movement
	local cap, eye = M.Capsule, M.Eye
	M.Collider = { Stand = { Height = 5, RootY = cap.StandRootY, RootDrop = 0, Size = Vector3.new(2, 2, 1) } }
	for name, eyeKey in { Crouch = "Crouch", Slide = "Slide", Prone = "Prone", Dive = "Prone", Downed = "Down" } do
		local h = cap.StandRootY + eye[eyeKey] + cap.EyeClearance
		M.Collider[name] = { Height = h, RootY = h / 2, RootDrop = cap.StandRootY - h / 2, Size = Vector3.new(cap.Girth, h, cap.Girth) }
	end
end

Config.Viewmodel = {
	UpperLen = 1.9, ForeLen = 1.9,
	RightShoulder = Vector3.new(0.95, -1.15, 0.45), LeftShoulder = Vector3.new(-0.95, -1.15, 0.45),
	RightHint = Vector3.new(2.4, -3, 1), LeftHint = Vector3.new(-1.8, -3.2, 0.6),
	Chest = Vector3.new(0, -1.15, 0.45), -- shoulder midpoint (camera space): origin for equipment animation tracks
	SleeveColor = Color3.fromRGB(48, 56, 42), GloveColor = Color3.fromRGB(22, 22, 24),
	EyeRelief = 0.9,

	Hip    = CFrame.new(0.55, -0.62, -1.55),
	Sprint = CFrame.new(0.40, -0.85, -1.15) * CFrame.Angles(rad(-22), rad(38), rad(10)),
	Tac    = CFrame.new(0.45, -1.00, -0.95) * CFrame.Angles(rad(-32), rad(46), rad(14)),
	Slide  = CFrame.new(0.25, -0.78, -1.20) * CFrame.Angles(rad(-8), rad(18), rad(-20)),
	Reload = CFrame.new(-0.10, 0.05, 0.15) * CFrame.Angles(rad(12), rad(-10), rad(-32)),
	Down   = CFrame.new(0.45, -0.95, -1.25) * CFrame.Angles(rad(6), rad(-6), rad(8)),
	Prone  = CFrame.new(0.52, -0.66, -1.45) * CFrame.Angles(rad(-3), rad(3), rad(-2)), -- gun held steady out in front while lying down
	Drop   = CFrame.new(0.35, -1.7, 0.8) * CFrame.Angles(rad(-55), rad(20), rad(-15)), -- gun lowered out of view
	Mantle = CFrame.new(0.20, -1.25, -0.60) * CFrame.Angles(rad(-38), rad(22), rad(-12)), -- gun tucked low and away while the hands grab the ledge
}

Config.Health = { Max = 150, RegenDelay = 5, RegenRate = 35 }

-- Warzone-style plates: each plate = 50 armor, up to 3 equipped, carry up to 5
Config.Armor = {
	PlateArmor = 50, MaxEquipped = 3, MaxCarried = 5, StartCarried = 2, StartArmor = 0,
	ApplyTime = 2.4, MoveMult = 0.85,
	Overflow = true,                     -- damage beyond remaining armor carries into health
	Absorb = { Bullet = 1, Melee = 1, Explosive = 1, Fire = 0.5, Gas = 0 }, -- fraction of damage armor can soak
}

Config.Perks = {
	DoubleTime = { Slot = 1, Desc = "Tactical sprint lasts twice as long." },
	FlakJacket = { Slot = 1, Desc = "Take 50% less explosive damage." },
	Scavenger = { Slot = 1, Desc = "Kills resupply ammo and equipment." },
	Overkill = { Slot = 1, Desc = "Carry two primary weapons." },
	QuickFix = { Slot = 2, Desc = "Faster plates, faster regen, kills heal you." },
	BattleHardened = { Slot = 2, Desc = "Flash, stun and gas effects reduced." },
	FastHands = { Slot = 2, Desc = "Reload 25% faster." },
	Amped = { Slot = 2, Desc = "Faster weapon swap and equipment use." },
	DeadSilence = { Slot = 3, Desc = "Silent footsteps." },
	Ghost = { Slot = 3, Desc = "Invisible to Heartbeat Sensors." },
	SteadyAim = { Slot = 3, Desc = "Tighter hip-fire spread." },
}
Config.PerkValues = {
	DoubleTime = 2, Flak = 0.5, ScavengeMag = 0.5, QuickFixPlate = 0.6, QuickFixDelay = 2, QuickFixRegen = 1.6, QuickFixKillHeal = 30,
	BattleHardened = 0.35, FastHands = 0.75, AmpedEquip = 0.6, AmpedUse = 0.7, SteadyAim = 0.8,
}
function Config.Has(perks, name) return perks ~= nil and perks[name] == true end

-- Melee used by the quick-melee key (V) with any gun
Config.QuickMelee = { Damage = 60, Back = 300, Range = 7, Radius = 1.3, Time = 0.55, HitAt = 0.35, Cooldown = 0.8 }

-- Downed state: a lethal hit puts a player down instead of killing them. They crawl, can only use a pistol / revolver and bleed out;
-- teammates (same Team) revive, enemies can finish them.
Config.Down = {
	Enabled = true,
	Health = 100,              -- "downed health": bleed-out timer and extra damage both drain it
	BleedTime = 30,            -- seconds to bleed out if nobody helps
	ReviveTime = 4, FinishTime = 2.5, InteractRange = 6,
	ReviveHealth = 60,         -- health after being revived (armor is lost)
	AllowFinish = true,        -- enemies can execute downed players
	AllowedClasses = { Pistol = true, Revolver = true },
}

-- Level curve: XP to go from level L to L+1 = BaseXP + PerLevel * (L - 1)
Config.Progression = { MaxLevel = 100, BaseXP = 800, PerLevel = 120 }

-- XP tags. Medal = true shows a big center banner. Edit XP / Label freely; add a tag here and award it with Score.Award(plr, "Tag").
Config.Scoring = {
	MultiWindow = 4,                 -- seconds between kills to keep a multi-kill chain going
	AssistWindow = 10,               -- damage older than this does not count toward assists
	AssistThreshold = 0.2,           -- fraction of the victim's max health you must deal to earn an Assist
	AssistKillThreshold = 0.5,       -- deal this much (but not the final blow) and it becomes an Assist Kill
	AssistKillCountsAsKill = true,   -- Assist Kills add to kills, multi-kill chains and streaks
	LongshotDistance = 150, PointBlankDistance = 6,
	Tags = {
		Kill = { XP = 100, Label = "KILL" },
		Headshot = { XP = 50, Label = "HEADSHOT" },
		Assist = { XP = 40, Label = "ASSIST" },
		AssistKill = { XP = 100, Label = "ASSIST KILL" },
		DoubleKill = { XP = 75, Label = "DOUBLE KILL", Medal = true },
		TripleKill = { XP = 150, Label = "TRIPLE KILL", Medal = true },
		QuadKill = { XP = 250, Label = "QUAD KILL", Medal = true },
		PentaKill = { XP = 400, Label = "PENTA KILL", Medal = true },
		Collateral = { XP = 100, Label = "COLLATERAL", Medal = true },
		Wallbang = { XP = 50, Label = "WALLBANG", Medal = true },
		KnockDown = { XP = 50, Label = "KNOCK DOWN", Medal = true },
		Revive = { XP = 100, Label = "REVIVE", Medal = true },
		Finisher = { XP = 75, Label = "FINISHER", Medal = true },
		ArmorBreak = { XP = 15, Label = "ARMOR BREAK" },
		Longshot = { XP = 50, Label = "LONGSHOT", Medal = true },
		PointBlank = { XP = 25, Label = "POINT BLANK" },
		Backstab = { XP = 75, Label = "BACKSTAB", Medal = true },
		Revenge = { XP = 50, Label = "REVENGE", Medal = true },
		FirstBlood = { XP = 100, Label = "FIRST BLOOD", Medal = true },
		Streak3 = { XP = 100, Label = "3 KILL STREAK", Medal = true },
		Streak5 = { XP = 200, Label = "5 KILL STREAK", Medal = true },
		Streak10 = { XP = 500, Label = "10 KILL STREAK", Medal = true },
		-- objective modes (ObjectiveService)
		Capture = { XP = 100, Label = "FLAG CAPTURED", Medal = true },
		Neutralize = { XP = 50, Label = "FLAG NEUTRALIZED" },
		HillHold = { XP = 25, Label = "HILL TIME" },
		Confirmed = { XP = 100, Label = "KILL CONFIRMED", Medal = true },
		Denied = { XP = 50, Label = "KILL DENIED", Medal = true },
	},
}

Config.Explosion = { SelfDamage = 0.5, Builtin = true }

-- Equipment. Mode: Throw (hold to cook if Cook), Use (instant effect), Plant (claymore)
Config.Equipment = {
	-- ---- lethal
	Frag = { Kind = "Lethal", Label = "Frag Grenade", Count = 2, Mode = "Throw", Cook = true, Fuse = 3.5, Speed = 70, Radius = 16,
		Damage = { 170, 20 }, Item = "Grenade", Color = Color3.fromRGB(70, 86, 52), PullTime = 0.45, ThrowTime = 0.4 },
	Semtex = { Kind = "Lethal", Label = "Semtex", Count = 2, Mode = "Throw", Sticky = true, Fuse = 2.6, Speed = 62, Radius = 13,
		Damage = { 160, 20 }, Item = "Semtex", Color = Color3.fromRGB(190, 70, 50), PullTime = 0.4, ThrowTime = 0.4 },
	Thermite = { Kind = "Lethal", Label = "Thermite", Count = 2, Mode = "Throw", Sticky = true, Fuse = 1.4, Speed = 62, Radius = 6,
		Damage = { 40, 10 }, Fire = { Radius = 7, Duration = 6, Dps = 30 }, Item = "Grenade", Color = Color3.fromRGB(190, 120, 40), PullTime = 0.4, ThrowTime = 0.4 },
	ThrowingKnife = { Kind = "Lethal", Label = "Throwing Knife", Count = 2, Mode = "Throw", Item = "Knife", Color = Color3.fromRGB(190, 190, 195),
		Projectile = { Speed = 170, Gravity = 45, Damage = 200 }, PullTime = 0.25, ThrowTime = 0.35 },
	Claymore = { Kind = "Lethal", Label = "Claymore", Count = 2, Mode = "Plant", Max = 2, Radius = 14, Damage = { 150, 25 },
		Arm = 1.2, Range = 14, Angle = 55, Item = "Claymore", Color = Color3.fromRGB(70, 80, 60), UseTime = 1.1, UseAt = 0.6 },
	C4 = { Kind = "Lethal", Label = "C4", Count = 2, Mode = "Throw", Sticky = true, Detonator = true, Max = 4, Speed = 48, Radius = 15,
		Damage = { 180, 25 }, Item = "C4", Color = Color3.fromRGB(215, 205, 160), PullTime = 0.3, ThrowTime = 0.4 },
	-- ---- tactical
	Flash = { Kind = "Tactical", Label = "Flashbang", Count = 2, Mode = "Throw", Fuse = 1.6, Speed = 66, Effect = "Flash", Radius = 50,
		Duration = 4.5, Item = "Canister", Color = Color3.fromRGB(210, 210, 215), PullTime = 0.4, ThrowTime = 0.4 },
	Stun = { Kind = "Tactical", Label = "Stun Grenade", Count = 2, Mode = "Throw", Fuse = 1.6, Speed = 66, Effect = "Stun", Radius = 30,
		Duration = 4.5, Item = "Canister", Color = Color3.fromRGB(70, 90, 140), PullTime = 0.4, ThrowTime = 0.4 },
	Smoke = { Kind = "Tactical", Label = "Smoke Grenade", Count = 2, Mode = "Throw", Impact = true, Delay = 0.5, Speed = 66, Effect = "Smoke",
		Radius = 16, Duration = 14, Item = "Canister", Color = Color3.fromRGB(120, 125, 130), PullTime = 0.4, ThrowTime = 0.4 },
	Gas = { Kind = "Tactical", Label = "Gas Grenade", Count = 2, Mode = "Throw", Impact = true, Delay = 0.4, Speed = 62, Effect = "Gas",
		Radius = 13, Duration = 9, Dps = 14, Item = "Canister", Color = Color3.fromRGB(110, 150, 70), PullTime = 0.4, ThrowTime = 0.4 },
	Stim = { Kind = "Tactical", Label = "Stim Shot", Count = 2, Mode = "Use", Effect = "Stim", UseTime = 1.1, UseAt = 0.5, Heal = 60,
		SpeedMult = 1.15, Duration = 6, Item = "Syringe", Color = Color3.fromRGB(230, 70, 70) },
	Heartbeat = { Kind = "Tactical", Label = "Heartbeat Sensor", Count = 1, Mode = "Use", Effect = "Sensor", UseTime = 0.9, UseAt = 0.5,
		Radius = 60, Duration = 20, Item = "Sensor", Color = Color3.fromRGB(60, 60, 66) },
}

Config.ThirdPerson = {
	UpperArm = 1.1, ForeArm = 1.1, Thigh = 1.1, Shin = 1.1, Reach = 2.2,
	Sleeve = Color3.fromRGB(48, 56, 42), Pants = Color3.fromRGB(52, 54, 48), Boots = Color3.fromRGB(26, 26, 28), Vest = Color3.fromRGB(34, 38, 34),
	HipPose = CFrame.new(0.35, -0.2, -0.55),
	MeleePose = CFrame.new(0.5, -0.3, -0.7) * CFrame.Angles(rad(10), rad(-10), 0),
	SprintPose = CFrame.new(0.15, -0.55, -0.35) * CFrame.Angles(rad(-35), rad(30), 0),
	DownPose = CFrame.new(0.3, -0.5, -0.7),
	DropPose = CFrame.new(0.5, -1.1, 0.3) * CFrame.Angles(rad(-50), rad(20), rad(-15)),
	ReloadTilt = CFrame.new(-0.05, 0.02, 0.05) * CFrame.Angles(rad(10), rad(-8), rad(-25)),
	ShowLocal = false, -- build the third-person body for your own character too (debug)
	-- How far the torso drops (studs) and leans forward (radians) per stance. ThirdPerson.luau draws it and Hitbox.luau builds the
	-- server hitboxes from the same numbers, so what other players see and what bullets hit always match.
	StanceDrop = { Crouch = 0.9, Slide = 1.25, Sprint = 0.15, TacSprint = 0.3, Downed = 1.5, Prone = 1.5, Dive = 1.5 },
	StanceFwd = { Walk = 0.05, Sprint = 0.2, TacSprint = 0.35, Slide = -0.7, Downed = 1.45, Prone = 1.45, Dive = 1.45 },
}

-- Procedural mantle / vault poses (ClimbPose.luau). One solver feeds the first-person hands, the third-person body and the server hitboxes.
-- Every curve is { { t, value }, ... } sampled with Anim.SampleScalar (smoothstep between keys). t runs 0..1 over the whole climb.
-- Mantle curves are keyed on "climb time" where 0.55 is the moment the body hangs over the ledge, whatever Config.Movement.Mantle.RiseShare is.
--   Fwd = torso lean forward (rad)   Drop = torso lowered below the root (studs)   Roll = torso roll toward the planting hand (rad)
--   Yaw = share of the turn toward the wall   GunDrop = gun lowered out of the way (0..1)   HandW / FootW = how much the hand / foot is on the pose
--   (instead of on the gun / the floor)   HandSlide = hands move from the lip onto the top surface   FootR / FootL = hang (0) -> on the ledge (1)
--   Swing = legs swung sideways over the obstacle (rad)   Tuck = knees pulled up (0..1)
Config.Climb = {
	GripSpread = 0.6,   -- mantle: how far apart (sideways) the hands grip the lip
	VaultHand = "L",    -- vault: the hand that plants on the obstacle. "L" (support hand) leaves the gun in the right hand; "R" mirrors the vault
	Mantle = {
		Fwd = { { 0, 0.15 }, { 0.2, 0.4 }, { 0.4, 0.8 }, { 0.55, 1.05 }, { 0.75, 0.5 }, { 1, 0.05 } },
		Drop = { { 0, 0 }, { 0.2, 0.3 }, { 0.4, 1.0 }, { 0.55, 1.5 }, { 0.75, 0.8 }, { 1, 0 } },
		GunDrop = { { 0, 0 }, { 0.1, 1 }, { 0.85, 1 }, { 1, 0 } },
		HandW = { { 0, 0 }, { 0.14, 1 }, { 0.62, 1 }, { 0.8, 0 } },
		HandSlide = { { 0, 0 }, { 0.4, 0 }, { 0.62, 1 }, { 1, 1 } },
		FootW = { { 0, 0 }, { 0.2, 1 }, { 0.85, 1 }, { 1, 0 } },
		FootR = { { 0, 0 }, { 0.25, 0 }, { 0.55, 1 }, { 1, 1 } },
		FootL = { { 0, 0 }, { 0.4, 0 }, { 0.75, 1 }, { 1, 1 } },
	},
	Vault = {
		Fwd = { { 0, 0.2 }, { 0.25, 0.7 }, { 0.5, 0.55 }, { 0.75, 0.1 }, { 1, 0 } },
		Drop = { { 0, 0 }, { 0.25, 0.9 }, { 0.5, 1.2 }, { 0.75, 0.5 }, { 1, 0 } },
		Roll = { { 0, 0 }, { 0.25, 0.45 }, { 0.5, 0.85 }, { 0.75, 0.3 }, { 1, 0 } },
		Yaw = { { 0, 0.5 }, { 0.5, 1 }, { 1, 0.3 } },
		GunDrop = { { 0, 0 }, { 0.4, 0.25 }, { 1, 0 } },
		HandW = { { 0, 0 }, { 0.2, 1 }, { 0.55, 1 }, { 0.75, 0 } },
		FootW = { { 0, 0 }, { 0.2, 1 }, { 0.7, 1 }, { 0.92, 0 } },
		Swing = { { 0, 0 }, { 0.25, 0.5 }, { 0.5, 1.25 }, { 0.75, 0.5 }, { 1, 0 } },
		Tuck = { { 0, 0 }, { 0.3, 0.6 }, { 0.5, 1 }, { 0.8, 0.2 }, { 1, 0 } },
	},
}

-- Pose-aware hitboxes (Hitbox.luau). Bullets, melee, knives, rockets, explosions and claymores test boxes that follow the stance the
-- player is really in (crouch / slide / prone + downed / sprint lean / aim pitch) instead of the default standing R6 body.
Config.Hitbox = {
	Enabled = true,                      -- false = old behaviour (real R6 parts, always standing)
	Debug = false,                       -- draw the boxes on this client (F8 toggles it while Config.Debug is true)
	Size = { Head = Vector3.new(2, 1, 1), Torso = Vector3.new(2, 2, 1) },
	ArmThick = 1, LegThick = 1,
	HandR = Vector3.new(0.45, -0.55, -0.6), -- where the hands sit relative to the chest while holding a gun (arm boxes run shoulder -> hand)
	HandL = Vector3.new(0.2, -0.4, -1.5),
	LegLength = 2,                       -- R6 leg height; the ground sits (HipHeight + LegLength + root half-height) below the root
	BoundRadius = 6,                     -- cheap sphere around the torso used to skip far-away bodies
	Physical = true,                     -- thrown grenades / C4 / Semtex collide with and stick to the posed body (server proxy parts)
	PhysicalRange = 25,                  -- proxies only move while a thrown object is within this many studs of the player (saves bandwidth)
	-- the stance comes from the client, so it is sanity-checked against what the server sees:
	MinSlideSpeed = 5,                   -- "Slide" below this speed counts as crouching
	MaxCrouchSpeed = 12,                 -- "Crouch" above this speed counts as walking
	MaxProneSpeed = 16,                  -- "Prone" above this speed counts as walking (covers the post-dive skid, which is capped below this)
	-- "Dive" is the flying part of a dive-to-prone. It is the only lying pose allowed at sprint speed, so it is rationed: capped speed,
	-- a short window per dive, and a gap before the next one. (A real dive lasts ~0.5 s and lands as an ordinary, slow Prone.)
	MaxDiveSpeed = 27,                   -- above this a "Dive" counts as airborne (Movement.DiveSpeed is 23, plus slack)
	DiveMaxTime = 0.9,                   -- longest a single dive is believed (Movement gives up on a dive after 1.2 s, real ones land well before)
	DiveGap = 0.5,                       -- after a dive ends, a new one is not believed for this long
	-- "Mantle" / "Vault" are only believed for the replicated climb duration (Config.Movement.Mantle times, clamped) plus this slack,
	-- and a new one only starts after ClimbGap (a real climb is followed by Mantle.Cooldown). Past that the body counts as airborne.
	ClimbGrace = 0.4, ClimbGap = 0.5, ClimbMaxDist = 14,
	FloorRate = 0.1,                     -- seconds between the server's floor-distance checks (how low the root really sits)
}
Config.Footsteps = { Default = "", Volume = 0.5 } -- material name -> rbxassetid; "" = silent

-- ------------------------------------------------------------------ helpers for weapon data
local function pattern(up, side, n, phase)
	local t = {}
	for i = 1, n do t[i] = Vector2.new(up * math.max(0.55, 1 - i * 0.03), side * math.sin(i * 1.25 + (phase or 0))) end
	return t
end
local function rc(up, side, reset, adsMult, jitter, n)
	return { Pattern = pattern(up, side, n or 14), Reset = reset or 0.25, AdsMult = adsMult or 0.7, Jitter = jitter or 0.15 }
end
local function sp(hip, ads, mv, air, per, max, rec)
	return { Hip = hip, Ads = ads, Move = mv, Air = air, PerShot = per, MaxBloom = max, Recover = rec }
end

local Classes = {
	Pistol = { Model = "Pistol", FireMode = "Semi", Pellets = 1, Range = 1200, HeadMult = 1.4, EquipTime = 0.3, ReloadStyle = "Mag",
		AdsTime = 0.14, AdsFov = 68, SprintOutTime = 0.08, MoveMult = 1.04, AdsMoveMult = 0.85, Kick = 0.8,
		Spread = sp(2.2, 0.15, 1.4, 2.5, 0.4, 1.4, 4), Recoil = rc(1.1, 0.2, 0.3, 0.8, 0.2, 8) },
	Revolver = { Model = "Revolver", FireMode = "Semi", Pellets = 1, Range = 1500, HeadMult = 1.6, EquipTime = 0.4, ReloadStyle = "Cylinder",
		AdsTime = 0.16, AdsFov = 66, SprintOutTime = 0.1, MoveMult = 1.02, AdsMoveMult = 0.8, Kick = 2.4,
		Spread = sp(2.4, 0.05, 1.4, 3, 0.8, 1.6, 3), Recoil = rc(3.2, 0.3, 0.5, 0.8, 0.3, 6) },
	AR = { Model = "Rifle", FireMode = "Auto", FireModes = { "Auto", "Semi" }, Pellets = 1, Range = 1500, HeadMult = 1.5, EquipTime = 0.45, ReloadStyle = "Mag",
		AdsTime = 0.2, AdsFov = 62, SprintOutTime = 0.15, MoveMult = 1, AdsMoveMult = 0.6, Kick = 1.0,
		Spread = sp(1.9, 0.12, 1.3, 2.5, 0.12, 1.2, 3), Recoil = rc(0.8, 0.3) },
	SMG = { Model = "SMG", FireMode = "Auto", FireModes = { "Auto", "Semi" }, Pellets = 1, Range = 1100, HeadMult = 1.4, EquipTime = 0.35, ReloadStyle = "Mag",
		AdsTime = 0.16, AdsFov = 66, SprintOutTime = 0.1, MoveMult = 1.06, AdsMoveMult = 0.72, Kick = 0.7,
		Spread = sp(1.6, 0.15, 0.9, 2.2, 0.1, 1.1, 3.5), Recoil = rc(0.55, 0.25) },
	Shotgun = { Model = "Shotgun", FireMode = "Semi", Range = 600, HeadMult = 1.2, EquipTime = 0.5, ReloadStyle = "Shell",
		AdsTime = 0.22, AdsFov = 64, SprintOutTime = 0.15, MoveMult = 0.97, AdsMoveMult = 0.65, Kick = 3.0,
		Spread = sp(4.5, 2.6, 1.2, 2, 0.5, 1.5, 3), Recoil = rc(3.5, 0.5, 0.6, 0.8, 0.4, 4) },
	LMG = { Model = "LMG", FireMode = "Auto", Pellets = 1, Range = 1800, HeadMult = 1.4, EquipTime = 0.7, ReloadStyle = "Mag",
		AdsTime = 0.3, AdsFov = 60, SprintOutTime = 0.22, MoveMult = 0.9, AdsMoveMult = 0.45, Kick = 1.3,
		Spread = sp(2.4, 0.2, 1.8, 3, 0.1, 1.4, 2.5), Recoil = rc(0.95, 0.4, 0.3, 0.65, 0.2, 18) },
	Marksman = { Model = "Marksman", FireMode = "Semi", Pellets = 1, Range = 2200, HeadMult = 1.6, EquipTime = 0.55, ReloadStyle = "Mag",
		AdsTime = 0.26, AdsFov = 52, SprintOutTime = 0.2, MoveMult = 0.93, AdsMoveMult = 0.55, Kick = 2.2,
		Spread = sp(2.4, 0.05, 1.6, 3, 0.5, 1.5, 4), Recoil = rc(2.4, 0.3, 0.4, 0.75, 0.3, 1) },
	Sniper = { Model = "Sniper", FireMode = "Semi", Pellets = 1, Range = 4000, HeadMult = 2, EquipTime = 0.7, ReloadStyle = "Mag",
		AdsTime = 0.32, AdsFov = 16, SprintOutTime = 0.25, MoveMult = 0.88, AdsMoveMult = 0.4, Kick = 3.2,
		Cycle = { Time = 1.15, DropAds = true }, Scope = { Overlay = true, Breath = 4.5 },
		Spread = sp(5, 0.02, 3, 6, 0, 0, 5), Recoil = rc(4.2, 0.5, 0.6, 0.8, 0.3, 1) },
	Launcher = { Model = "Launcher", FireMode = "Semi", Pellets = 1, Range = 3000, HeadMult = 1, EquipTime = 0.7, ReloadStyle = "Rocket",
		AdsTime = 0.3, AdsFov = 58, SprintOutTime = 0.25, MoveMult = 0.88, AdsMoveMult = 0.5, Kick = 4.5,
		Spread = sp(1.2, 0.05, 1.2, 2, 0, 0, 5), Recoil = rc(4, 0.6, 0.8, 0.8, 0.2, 1) },
	Melee = { Model = "Knife", FireMode = "Semi", Pellets = 1, Range = 0, HeadMult = 1, EquipTime = 0.35, ReloadStyle = "None",
		MagSize = 0, Reserve = 0, ReloadTime = 0, ReloadEmptyTime = 0, AdsTime = 0.2, AdsFov = 80, SprintOutTime = 0.05, MoveMult = 1.08,
		AdsMoveMult = 1, Kick = 0, Damage = { { 0, 0 } }, Spread = sp(0, 0, 0, 0, 0, 0, 1), Recoil = rc(0, 0, 0.2, 1, 0, 1) },
}

local function dmg(...) return { ... } end

local W = {
	-- ---------------------------------------------------------------- pistols
	M1911 = { Class = "Pistol", Color = Color3.fromRGB(46, 46, 50), RPM = 380, Damage = dmg({ 0, 38 }, { 20, 35 }, { 50, 29 }, { 90, 23 }),
		MagSize = 8, Reserve = 40, ReloadTime = 1.5, ReloadEmptyTime = 2.0 },
	M19 = { Class = "Pistol", Color = Color3.fromRGB(40, 42, 46), RPM = 560, Damage = dmg({ 0, 28 }, { 25, 26 }, { 55, 21 }, { 100, 17 }),
		MagSize = 15, Reserve = 60, ReloadTime = 1.4, ReloadEmptyTime = 1.9 },
	G18 = { Class = "Pistol", Color = Color3.fromRGB(34, 34, 36), RPM = 1000, FireMode = "Auto", FireModes = { "Auto", "Semi" }, Damage = dmg({ 0, 20 }, { 20, 18 }, { 45, 14 }, { 80, 11 }),
		MagSize = 20, Reserve = 80, ReloadTime = 1.5, ReloadEmptyTime = 2.0, Kick = 0.6, Recoil = rc(0.7, 0.35, 0.2, 0.8, 0.3, 14) },
	-- ---------------------------------------------------------------- revolvers
	Revolver357 = { Class = "Revolver", Color = Color3.fromRGB(120, 120, 128), RPM = 170, Damage = dmg({ 0, 80 }, { 30, 72 }, { 60, 62 }, { 120, 52 }),
		MagSize = 6, Reserve = 24, ReloadTime = 2.7, ReloadEmptyTime = 2.7 },
	Revolver50 = { Class = "Revolver", Color = Color3.fromRGB(60, 60, 64), RPM = 110, HeadMult = 1.5, Damage = dmg({ 0, 115 }, { 30, 100 }, { 60, 85 }, { 120, 70 }),
		MagSize = 5, Reserve = 15, ReloadTime = 3.0, ReloadEmptyTime = 3.0, Kick = 3.4, Recoil = rc(5.2, 0.4, 0.6, 0.8, 0.3, 5) },
	-- ---------------------------------------------------------------- assault rifles
	M4A1 = { Class = "AR", Color = Color3.fromRGB(38, 38, 42), RPM = 785, Damage = dmg({ 0, 28 }, { 45, 26 }, { 90, 23 }, { 160, 19 }),
		MagSize = 30, Reserve = 150, ReloadTime = 2.0, ReloadEmptyTime = 2.8,
		Recoil = { Pattern = {
			Vector2.new(0.90, 0.05), Vector2.new(0.85, -0.10), Vector2.new(0.80, 0.15), Vector2.new(0.75, 0.25),
			Vector2.new(0.70, 0.20), Vector2.new(0.65, -0.10), Vector2.new(0.60, -0.30), Vector2.new(0.55, -0.35),
			Vector2.new(0.50, -0.20), Vector2.new(0.50, 0.10), Vector2.new(0.45, 0.30), Vector2.new(0.45, 0.35),
			Vector2.new(0.40, 0.10), Vector2.new(0.40, -0.25) }, Reset = 0.25, AdsMult = 0.7, Jitter = 0.15 } },
	AK47 = { Class = "AR", Color = Color3.fromRGB(86, 66, 46), RPM = 600, Damage = dmg({ 0, 34 }, { 40, 31 }, { 90, 27 }, { 160, 22 }),
		MagSize = 30, Reserve = 120, ReloadTime = 2.3, ReloadEmptyTime = 3.0, Kick = 1.4, Recoil = rc(1.15, 0.5, 0.3, 0.7, 0.25) },
	Grau = { Class = "AR", Color = Color3.fromRGB(56, 60, 52), RPM = 715, Damage = dmg({ 0, 30 }, { 50, 28 }, { 100, 25 }, { 170, 21 }),
		MagSize = 30, Reserve = 150, ReloadTime = 2.1, ReloadEmptyTime = 2.9, Recoil = rc(0.85, 0.35) },
	-- ---------------------------------------------------------------- SMGs
	MP5 = { Class = "SMG", Color = Color3.fromRGB(36, 36, 40), RPM = 800, Damage = dmg({ 0, 25 }, { 25, 23 }, { 60, 19 }, { 100, 15 }),
		MagSize = 30, Reserve = 150, ReloadTime = 1.8, ReloadEmptyTime = 2.4 },
	P90 = { Class = "SMG", Color = Color3.fromRGB(70, 74, 66), RPM = 900, Damage = dmg({ 0, 22 }, { 25, 20 }, { 55, 17 }, { 90, 13 }),
		MagSize = 50, Reserve = 200, ReloadTime = 2.4, ReloadEmptyTime = 3.0, Recoil = rc(0.5, 0.3) },
	UZI = { Class = "SMG", Color = Color3.fromRGB(44, 44, 48), RPM = 950, Damage = dmg({ 0, 21 }, { 22, 19 }, { 50, 16 }, { 85, 12 }),
		MagSize = 32, Reserve = 160, ReloadTime = 1.7, ReloadEmptyTime = 2.2, Kick = 0.9, Recoil = rc(0.6, 0.45) },
	-- ---------------------------------------------------------------- shotguns (Damage = per pellet)
	Model680 = { Class = "Shotgun", Model = "Pump", Color = Color3.fromRGB(60, 52, 44), RPM = 80, Pellets = 8,
		Damage = dmg({ 0, 19 }, { 12, 17 }, { 25, 9 }, { 45, 4 }), MagSize = 6, Reserve = 24, ReloadStyle = "Shell",
		ReloadStart = 0.45, ShellTime = 0.5, ReloadEnd = 0.45, ReloadTime = 0, ReloadEmptyTime = 0, Cycle = { Time = 0.55, DropAds = false } },
	Origin12 = { Class = "Shotgun", Color = Color3.fromRGB(40, 40, 44), RPM = 240, Pellets = 8, FireMode = "Semi",
		Damage = dmg({ 0, 14 }, { 12, 12 }, { 25, 7 }, { 45, 3 }), MagSize = 8, Reserve = 32, ReloadStyle = "Shell",
		ReloadStart = 0.4, ShellTime = 0.42, ReloadEnd = 0.4, ReloadTime = 0, ReloadEmptyTime = 0 },
	R725 = { Class = "Shotgun", Model = "Break", Color = Color3.fromRGB(76, 62, 48), RPM = 240, Pellets = 10,
		Damage = dmg({ 0, 15 }, { 14, 13 }, { 28, 7 }, { 50, 3 }), MagSize = 2, Reserve = 14, ReloadStyle = "Cylinder",
		ReloadTime = 2.3, ReloadEmptyTime = 2.3, Kick = 3.6 },
	-- ---------------------------------------------------------------- LMGs
	PKM = { Class = "LMG", Color = Color3.fromRGB(42, 44, 40), RPM = 650, Damage = dmg({ 0, 31 }, { 50, 29 }, { 100, 25 }, { 180, 21 }),
		MagSize = 100, Reserve = 200, ReloadTime = 5.4, ReloadEmptyTime = 6.2 },
	M91 = { Class = "LMG", Color = Color3.fromRGB(64, 56, 46), RPM = 520, Damage = dmg({ 0, 36 }, { 55, 33 }, { 110, 29 }, { 190, 24 }),
		MagSize = 75, Reserve = 150, ReloadTime = 4.8, ReloadEmptyTime = 5.5, Kick = 1.5, Recoil = rc(1.1, 0.5, 0.3, 0.65, 0.25, 18) },
	-- ---------------------------------------------------------------- marksman rifles
	MK14 = { Class = "Marksman", Color = Color3.fromRGB(86, 74, 58), RPM = 450, Damage = dmg({ 0, 52 }, { 80, 48 }, { 160, 40 }, { 300, 34 }),
		MagSize = 20, Reserve = 80, ReloadTime = 2.4, ReloadEmptyTime = 3.2 },
	SKS = { Class = "Marksman", Color = Color3.fromRGB(96, 70, 48), RPM = 330, AdsFov = 48, Damage = dmg({ 0, 62 }, { 90, 54 }, { 180, 46 }, { 300, 38 }),
		MagSize = 10, Reserve = 40, ReloadTime = 2.2, ReloadEmptyTime = 2.9, Kick = 2.6 },
	-- ---------------------------------------------------------------- sniper rifles (bolt)
	Kar98k = { Class = "Sniper", Color = Color3.fromRGB(88, 66, 44), RPM = 52, AdsFov = 18, Ballistics = { Speed = 3200 }, Damage = dmg({ 0, 140 }, { 250, 130 }, { 500, 115 }),
		MagSize = 5, Reserve = 20, ReloadTime = 3.2, ReloadEmptyTime = 3.4, Cycle = { Time = 1.1, DropAds = true } },
	HDR = { Class = "Sniper", Color = Color3.fromRGB(46, 50, 44), RPM = 48, AdsFov = 13, Ballistics = { Speed = 4000 }, Damage = dmg({ 0, 165 }, { 300, 155 }, { 600, 135 }),
		MagSize = 5, Reserve = 15, ReloadTime = 3.6, ReloadEmptyTime = 3.8, Cycle = { Time = 1.3, DropAds = true }, Kick = 3.8 },
	-- ---------------------------------------------------------------- launchers
	RPG7 = { Class = "Launcher", Color = Color3.fromRGB(78, 82, 70), RPM = 40, MagSize = 1, Reserve = 3, ReloadTime = 3.6, ReloadEmptyTime = 3.6,
		Projectile = { Speed = 110, Gravity = 8, Radius = 24, Damage = { 250, 60 }, Kind = "Rocket" } },
	M79 = { Class = "Launcher", Model = "Grenade", Color = Color3.fromRGB(80, 62, 44), RPM = 40, MagSize = 1, Reserve = 8, ReloadTime = 2.4, ReloadEmptyTime = 2.4,
		ReloadStyle = "Rocket", Kick = 3, Projectile = { Speed = 95, Gravity = 55, Radius = 14, Damage = { 180, 30 }, Kind = "Grenade" } },
	-- ---------------------------------------------------------------- melee weapons
	CombatKnife = { Class = "Melee", Model = "Knife", Color = Color3.fromRGB(190, 190, 195), OneHanded = true,
		Melee = { Light = { Damage = 55, Range = 7.5, Radius = 1.4, Time = 0.38, HitAt = 0.4 },
			Heavy = { Damage = 100, Range = 9, Radius = 1.4, Time = 0.7, HitAt = 0.5, Lunge = 24 }, Back = 300 } },
	Katana = { Class = "Melee", Model = "Katana", Color = Color3.fromRGB(205, 205, 212), MoveMult = 1.04,
		Melee = { Light = { Damage = 80, Range = 10, Radius = 1.6, Time = 0.5, HitAt = 0.45 },
			Heavy = { Damage = 130, Range = 12, Radius = 1.6, Time = 0.85, HitAt = 0.55, Lunge = 26 }, Back = 300 } },
	Sledgehammer = { Class = "Melee", Model = "Hammer", Color = Color3.fromRGB(110, 90, 66), MoveMult = 0.95,
		Melee = { Light = { Damage = 100, Range = 9, Radius = 1.8, Time = 0.8, HitAt = 0.55 },
			Heavy = { Damage = 150, Range = 10, Radius = 2.0, Time = 1.1, HitAt = 0.65, Lunge = 14 }, Back = 300 } },
}

-- ------------------------------------------------------------------ bullet ballistics (Ballistics.luau, BulletService, BulletFX)
-- Guns fire REAL bullets like CoD: a muzzle velocity, bullet drop and air drag that bleeds speed off with flight time, instead of an
-- instant hitscan ray. Both systems stay available:
--   * Enabled = false                     -> every gun is hitscan again (the old behaviour)
--   * Classes.X.Hitscan = true            -> that whole class is hitscan
--   * Weapon `Hitscan = true`             -> that one weapon is hitscan
--   * Weapon `Ballistics = { Speed = ..., Gravity = ..., Drag = ... }` overrides the class numbers for that weapon
--   * Weapons with their own `Projectile` entry (RPG7, M79) and the thrown knife keep using the rocket / grenade projectile code.
-- Speed   = muzzle velocity in studs/s (attachments scale it through the `Velocity` mod)
-- Gravity = bullet drop in studs/s^2
-- Drag    = air resistance in 1/s: speed falls like e^(-Drag * seconds), so Drag 0.4 = ~33% of the speed gone after 1 s of flight
-- Damage falloff (the `Damage` tables) is still measured in studs travelled from the muzzle.
Config.Ballistics = {
	Enabled = true,
	MaxLifetime = 5,  -- seconds before an unspent bullet is removed (a bullet is also removed past the weapon's `Range`)
	TracerMax = 3,    -- tracers drawn per shot (shotguns fire every pellet on the server but only show this many)
	MaxLive = 400,    -- server cap on bullets in flight (oldest are dropped first)
	Classes = {
		Pistol   = { Speed = 1250, Gravity = 60, Drag = 0.9 },
		Revolver = { Speed = 1500, Gravity = 55, Drag = 0.7 },
		AR       = { Speed = 1900, Gravity = 45, Drag = 0.45 },
		SMG      = { Speed = 1350, Gravity = 55, Drag = 0.8 },
		Shotgun  = { Speed = 1100, Gravity = 65, Drag = 1.4 },
		LMG      = { Speed = 1950, Gravity = 42, Drag = 0.4 },
		Marksman = { Speed = 2500, Gravity = 35, Drag = 0.3 },
		Sniper   = { Speed = 3600, Gravity = 28, Drag = 0.2 },
	},
}

-- ------------------------------------------------------------------ bullet penetration (Penetration.luau)
-- Bullets punch through thin walls (wallbangs) and through bodies (collateral). A bullet carries Power = "studs of concrete it can still
-- cross". A wall costs  thickness * resistance(material);  every body costs BodyCost.  Damage after a wall is multiplied by
-- max(MinWallMult, 1 - cost / startPower), after each body by BodyDamage.
--   * Weapon:      `PenPower = n` replaces the class number, `NoPen = true` turns it off for that weapon. Attachments scale it with the `PenMult` mod.
--   * Map parts:   Attribute  NoPen = true  (part or any ancestor) = bullet proof,  PenResist = number  overrides the material (0 = free pass).
--   * Everything:  Enabled = false and every bullet stops on the first thing it hits again.
Config.Penetration = {
	Enabled = true,
	MaxHits = 8,         -- surfaces handled per bullet per step (safety cap)
	MaxWalls = 4,        -- walls one bullet can cross in total
	MaxBodies = 3,       -- bodies one bullet can go through (the third one it hits is the last)
	MaxThickness = 8,    -- studs: never measure a wall thicker than this
	Floors = false,      -- false: floors / ceilings / crate tops (surface normal pointing up or down) are solid
	FloorNormal = 0.8,   -- |normal.Y| above this counts as a floor / ceiling
	BodyCost = 0.3,      -- Power a body takes out of the bullet
	BodyDamage = 0.7,    -- damage multiplier for everything the bullet hits after a body
	MinWallMult = 0.35,  -- a wall can take away at most 65% of the damage
	Default = 1,         -- resistance of a material that is not listed
	Classes = {          -- starting Power per weapon class (studs of concrete)
		Pistol = 0.8, Revolver = 1.5, AR = 1.5, SMG = 1.0, Shotgun = 0.3, LMG = 2.0, Marksman = 2.4, Sniper = 3.6,
	},
	Materials = {        -- resistance per stud of thickness, concrete = 1
		[Enum.Material.ForceField] = 0, [Enum.Material.Glass] = 0.08, [Enum.Material.Fabric] = 0.05, [Enum.Material.Foil] = 0.15,
		[Enum.Material.Snow] = 0.1, [Enum.Material.Grass] = 0.12, [Enum.Material.LeafyGrass] = 0.12, [Enum.Material.Ice] = 0.2,
		[Enum.Material.Glacier] = 0.3, [Enum.Material.Plastic] = 0.3, [Enum.Material.SmoothPlastic] = 0.3, [Enum.Material.Neon] = 0.3,
		[Enum.Material.Wood] = 0.35, [Enum.Material.WoodPlanks] = 0.35, [Enum.Material.Sand] = 0.45, [Enum.Material.Mud] = 0.55,
		[Enum.Material.Ground] = 0.6, [Enum.Material.Salt] = 0.7, [Enum.Material.Brick] = 0.9, [Enum.Material.Sandstone] = 0.9,
		[Enum.Material.Pebble] = 0.9, [Enum.Material.Concrete] = 1, [Enum.Material.Pavement] = 1, [Enum.Material.Asphalt] = 1,
		[Enum.Material.Limestone] = 1, [Enum.Material.Cobblestone] = 1.1, [Enum.Material.Slate] = 1.1, [Enum.Material.Rock] = 1.2,
		[Enum.Material.Marble] = 1.2, [Enum.Material.CrackedLava] = 1.2, [Enum.Material.CorrodedMetal] = 1.2, [Enum.Material.Granite] = 1.25,
		[Enum.Material.Basalt] = 1.35, [Enum.Material.Metal] = 1.4, [Enum.Material.DiamondPlate] = 1.6,
	},
}

-- ------------------------------------------------------------------ fire modes (WeaponController:SwitchFireMode)
-- `FireMode` = the mode a gun starts in ("Auto" / "Semi"). `FireModes = { "Auto", "Semi" }` makes it select-fire: the FireMode key
-- (Settings > Keybinds > Combat, touch MODE button) cycles through that list in order. Set it on a whole class (Classes.X) or on one weapon,
-- e.g. a semi gun with a switch:  FireMode = "Semi", FireModes = { "Semi", "Auto" }.  A gun without `FireModes` is locked to its FireMode.
-- Bolt / pump guns (Cycle) and launchers (Projectile) never switch.
function Config.FireModesOf(cfg)
	if cfg.Cycle or cfg.Projectile or cfg.Class == "Melee" then return { cfg.FireMode } end
	return cfg.FireModes or { cfg.FireMode }
end

Config.Weapons = W
for name, w in W do
	w.Name = name
	for k, v in Classes[w.Class] do
		if w[k] == nil then w[k] = v end
	end
	w.Sounds = w.Sounds or { Fire = "" }
end

-- Weapon lists for the loadout menu (stable order)
Config.Classes = { "Pistol", "Revolver", "AR", "SMG", "Shotgun", "LMG", "Marksman", "Sniper", "Launcher", "Melee" }
function Config.WeaponsOf(classList)
	local out = {}
	for name, w in W do
		if table.find(classList, w.Class) then table.insert(out, name) end
	end
	table.sort(out)
	return out
end
function Config.IsPrimary(name)
	local w = W[name]
	return w ~= nil and w.Class ~= "Pistol" and w.Class ~= "Revolver" and w.Class ~= "Melee"
end

return Config
