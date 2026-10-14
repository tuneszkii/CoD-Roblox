-- Armory: everything about what a player can own and equip. Pure data + logic, shared by the server (validation, purchases) and the
-- client (menu, gun building), so both sides always agree.
--
--   * Unlocks.  Weapons / equipment / perks / kill streaks / extra class slots unlock at a PLAYER level.
--               Attachments unlock at a WEAPON level (weapons earn XP from kills while you use them).
--   * Buy forward. Any locked item can be bought early with credits. The price scales with how far away the unlock still is:
--               price = missing XP * rate (clamped), so an item you are almost at costs next to nothing.
--   * Gunsmith. Attachments are stat modifiers (see Armory.Attachments); Armory.Build turns a weapon + attachments into the config
--               the gun really uses (server rules and client prediction both call it).
--   * Classes.  Ten custom class slots (5 at the start). A class is a full loadout: primary + secondary with attachments,
--               lethal, tactical, three perks and three kill streaks.
--
-- Everything tunable is in the tables at the top of this file.
local Config = require(script.Parent.Config)
local Progression = require(script.Parent.Progression)
local Ballistics = require(script.Parent.Ballistics)

local Armory = {}

-- Testing: true = every item is unlocked and free.
Armory.UnlockAll = false

Armory.Econ = {
	StartCredits = 300,
	CreditsPerXP = 0.1,       -- credits earned per XP point
	LevelUpBonus = 50,        -- extra credits on level up
	PlayerXPPrice = 0.12,     -- buy forward: credits per missing PLAYER XP
	WeaponXPPrice = 0.15,     -- buy forward: credits per missing WEAPON XP
	MinPrice = 50,
	MaxPrice = 20000,
	WeaponXPPerKill = 100,
	WeaponXPHeadshot = 50,
}

-- total weapon XP needed for weapon level 1..7
Armory.WeaponLevelXP = { 0, 500, 1200, 2200, 3500, 5200, 7500 }
Armory.MaxWeaponLevel = #Armory.WeaponLevelXP
Armory.MaxAttachments = 5

-- class slots: the first 5 are free, the rest unlock with player level
Armory.ClassLevels = { 1, 1, 1, 1, 1, 10, 15, 20, 25, 30 }
Armory.MaxClasses = #Armory.ClassLevels
Armory.ClassNameLen = 14

Armory.ClassLabels = { Pistol = "Pistol", Revolver = "Revolver", AR = "Assault Rifle", SMG = "SMG", Shotgun = "Shotgun", LMG = "Light Machine Gun",
	Marksman = "Marksman Rifle", Sniper = "Sniper Rifle", Launcher = "Launcher", Melee = "Melee" }

-- ================================================================ unlock levels
Armory.WeaponUnlock = {
	M1911 = 1, M19 = 6, G18 = 20,
	Revolver357 = 14, Revolver50 = 30,
	M4A1 = 1, AK47 = 4, Grau = 18,
	MP5 = 1, P90 = 9, UZI = 24,
	Model680 = 7, Origin12 = 16, R725 = 26,
	PKM = 12, M91 = 28,
	MK14 = 10, SKS = 22,
	Kar98k = 8, HDR = 25,
	RPG7 = 34, M79 = 40,
	CombatKnife = 1, Katana = 14, Sledgehammer = 20,
}

Armory.EquipUnlock = {
	Frag = 1, Flash = 1, Semtex = 5, Stun = 7, ThrowingKnife = 9, Smoke = 11, Claymore = 13, Stim = 16, Gas = 20, Heartbeat = 24, C4 = 28, Thermite = 32,
}
Armory.EquipDesc = {
	Frag = "Cookable fragmentation grenade. Hold to cook, release to throw.",
	Semtex = "Sticks to surfaces and players. Short fuse.",
	Thermite = "Sticks, then burns a small zone. Good for denying a spot.",
	ThrowingKnife = "Silent thrown blade. One hit from the right angle kills.",
	Claymore = "Plant it on a surface. Detonates when an enemy crosses its cone.",
	C4 = "Throw it, then detonate on demand with the detonate key.",
	Flash = "Blinds anyone looking at it.",
	Stun = "Slows and rattles anyone caught in the blast.",
	Smoke = "Blocks line of sight for 14 seconds.",
	Gas = "Choking cloud. Damages through armor, hurts less with Battle Hardened.",
	Stim = "Heals instantly and gives a short speed boost.",
	Heartbeat = "Pings nearby enemies on your compass. Ghost hides from it.",
}

Armory.PerkUnlock = {
	DoubleTime = 1, QuickFix = 1, DeadSilence = 1,
	FlakJacket = 8, FastHands = 12, Ghost = 15, Scavenger = 18, BattleHardened = 22, SteadyAim = 26, Amped = 30, Overkill = 35,
}

-- ================================================================ kill streaks
-- Kills = consecutive kills (no deaths) needed. They are earned once per life and lost on death. Params are read by StreakService.
Armory.StreakOrder = { "UAV", "Resupply", "Airstrike", "ArmorCache", "Mortar", "ChemStrike" }
Armory.Streaks = {
	UAV = { Name = "UAV", Kind = "Recon", Kills = 3, Level = 1, Duration = 25,
		Desc = "Sweeps the minimap every 3 seconds for 25 seconds, showing every enemy's position and facing. Your whole team benefits." },
	Resupply = { Name = "Resupply", Kind = "Support", Kills = 4, Level = 4,
		Desc = "Instantly refills ammo for both weapons and your equipment, and gives you plates." },
	Airstrike = { Name = "Precision Airstrike", Kind = "Strike", Kills = 5, Level = 8, Delay = 2.4, Count = 7, Spacing = 11, Interval = 0.28, Radius = 16, Damage = { 160, 30 },
		Desc = "Aim at the ground and call it in. A line of bombs falls along your aim direction." },
	ArmorCache = { Name = "Armor Cache", Kind = "Support", Kills = 5, Level = 12,
		Desc = "Restores full health and full armor and refills your carried plates." },
	Mortar = { Name = "Mortar Barrage", Kind = "Strike", Kills = 6, Level = 16, Delay = 2.0, Count = 10, Spread = 30, Duration = 6, Radius = 13, Damage = { 130, 25 },
		Desc = "Aim at the ground. Shells rain on the area for six seconds." },
	ChemStrike = { Name = "Chemical Strike", Kind = "Strike", Kills = 7, Level = 22, Delay = 1.8, Count = 3, Spread = 14, Radius = 14, Duration = 12, Dps = 22,
		Desc = "Aim at the ground. Gas clouds that hurt through armor settle over the area." },
}

-- ================================================================ attachments
Armory.Slots = { "Optic", "Muzzle", "Barrel", "Underbarrel", "Magazine", "Ammo", "Stock" }
Armory.SlotLabels = { Optic = "OPTIC", Muzzle = "MUZZLE", Barrel = "BARREL", Underbarrel = "UNDERBARREL", Magazine = "MAGAZINE", Ammo = "AMMUNITION", Stock = "STOCK" }

--[[ Mods (all optional):
	Damage, Range, RPM, Mag, Reload, AdsTime, Kick, RecoilV, RecoilH, SpreadHip, SpreadAds, Equip, SprintOut, Velocity = multipliers
	Velocity multiplies the bullet muzzle velocity (faster bullets = less drop, less lead; Config.Ballistics)
	PenMult multiplies how much wall / body the bullet can punch through (Config.Penetration)
	Range multiplies the distances of the damage falloff table (longer = damage holds up further)
	MagAdd, Head, AdsFov, Move, AdsMove, ScopeBreath = added to the number
	ReloadEmpty multiplies only the empty-gun reload time (Reload multiplies both)
	Reserve multiplies the spare ammo you carry, ReserveAdd adds rounds to it
	PelletAdd = n adds pellets to every shot (shotguns)
	ArmorPierce = 0..1, the fraction of every hit that skips armor plates and goes straight to health
	Burn = { Dps, Time } sets targets on fire (damage over time, refreshed by every hit, never stacks)
	SetPellets = n replaces the pellet count, Suppressed = true (shots are only heard nearby), Scope = {...} replaces the scope table (overlay scope)
]]
local GUNS = { "Pistol", "Revolver", "AR", "SMG", "Shotgun", "LMG", "Marksman", "Sniper" }
local RIFLES = { "AR", "SMG", "LMG", "Marksman" }
local function A(id, slot, name, desc, classes, lvl, mods) return { Id = id, Slot = slot, Name = name, Desc = desc, Classes = classes, Lvl = lvl, Mods = mods } end

local list = {
	-- optics
	A("RedDot", "Optic", "Red Dot Sight", "Clean sight picture. Slightly slower to raise.", { "Pistol", "Revolver", "AR", "SMG", "Shotgun", "LMG", "Marksman" }, 2, { AdsFov = -4, AdsTime = 1.04 }),
	A("Holo", "Optic", "Holographic Sight", "Wider reticle, a touch more zoom. Slower to raise.", { "AR", "SMG", "Shotgun", "LMG", "Marksman" }, 3, { AdsFov = -7, AdsTime = 1.07, RecoilV = 0.98 }),
	A("Hybrid", "Optic", "Hybrid 3.5x", "Medium zoom for mid range fights. Slower to raise and slower while aiming.", RIFLES, 4, { AdsFov = -16, AdsTime = 1.14, AdsMove = -0.05 }),
	A("Scope6", "Optic", "6x Scope", "Full scope overlay. Great at distance, slow to raise, slow while aiming and awkward up close.", { "AR", "LMG", "Marksman" }, 6,
		{ AdsFov = -34, AdsTime = 1.25, AdsMove = -0.08, SpreadHip = 1.08, Scope = { Overlay = true, Breath = 3.5 } }),
	A("SniperShort", "Optic", "Short-Range Scope", "Less zoom, much faster to bring up.", { "Sniper" }, 3, { AdsFov = 14, AdsTime = 0.88 }),
	A("SniperLong", "Optic", "Long-Range Scope", "More zoom and a steadier hold, slower to raise.", { "Sniper" }, 5, { AdsFov = -5, AdsTime = 1.12, ScopeBreath = 1.5 }),
	-- muzzles
	A("Suppressor", "Muzzle", "Suppressor", "Only players near you hear the shot. Costs damage range, bullet speed and a little aim speed.", { "Pistol", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 3,
		{ Range = 0.86, Kick = 0.95, Suppressed = true, Velocity = 0.9, AdsTime = 1.04 }),
	A("Compensator", "Muzzle", "Compensator", "Pulls the muzzle down. Vertical recoil down, but it drifts sideways and aims slower.", { "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 4,
		{ RecoilV = 0.84, Kick = 0.9, RecoilH = 1.08, AdsTime = 1.04 }),
	A("MuzzleBrake", "Muzzle", "Muzzle Brake", "Tames sideways recoil. Loud blast kicks the gun up a bit and slows aiming.", { "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman" }, 6,
		{ RecoilH = 0.68, RecoilV = 1.03, Kick = 0.95, AdsTime = 1.04 }),
	A("Choke", "Muzzle", "Full Choke", "Tighter spread, longer reach. More kick and slower to aim.", { "Shotgun" }, 2, { SpreadHip = 0.85, SpreadAds = 0.75, Range = 1.18, Kick = 1.1, AdsTime = 1.05 }),
	-- barrels
	A("LongBarrel", "Barrel", "Long Barrel", "Damage holds much further out and bullets fly faster. Noticeably slower to aim, sprint out and move with, and wilder from the hip.",
		{ "Pistol", "Revolver", "AR", "SMG", "Shotgun", "LMG", "Marksman", "Sniper" }, 3,
		{ Range = 1.22, Velocity = 1.15, AdsTime = 1.14, Move = -0.04, SprintOut = 1.2, SpreadHip = 1.08, Equip = 1.1 }),
	A("ShortBarrel", "Barrel", "Short Barrel", "Quick to aim, sprint out and move with. Much shorter damage range, slower bullets and a snappier kick.",
		{ "Pistol", "Revolver", "AR", "SMG", "Shotgun", "Marksman" }, 5,
		{ Range = 0.82, Velocity = 0.88, AdsTime = 0.86, Move = 0.03, SprintOut = 0.8, SpreadHip = 0.92, Kick = 1.08, SpreadAds = 1.06 }),
	A("Reinforced", "Barrel", "Reinforced Barrel", "Better headshot damage and range. More kick, heavier to aim and move with.", { "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 7,
		{ Head = 0.1, Range = 1.1, Kick = 1.08, AdsTime = 1.06, Move = -0.02 }),
	-- underbarrel
	A("Vertical", "Underbarrel", "Vertical Foregrip", "Reduces vertical recoil. Slower to aim and sprint out.", { "AR", "SMG", "Shotgun", "LMG", "Marksman" }, 2,
		{ RecoilV = 0.9, AdsTime = 1.06, Kick = 0.95, SprintOut = 1.1 }),
	A("Laser", "Underbarrel", "Laser Sight", "Tighter hip fire. Slower to raise and a touch slower to aim.", { "Pistol", "Revolver", "AR", "SMG", "Shotgun", "LMG", "Marksman" }, 2,
		{ SpreadHip = 0.82, AdsTime = 1.03, Equip = 1.1 }),
	A("Bipod", "Underbarrel", "Bipod", "Much steadier fire. Slow to aim, slow to sprint out and heavy to carry.", { "LMG", "Marksman", "Sniper" }, 3,
		{ RecoilV = 0.82, Kick = 0.8, AdsTime = 1.14, Move = -0.04, SprintOut = 1.25 }),
	A("Angled", "Underbarrel", "Angled Foregrip", "Faster aim and hip fire. More sideways recoil and a little vertical kick.", { "AR", "SMG", "Shotgun", "LMG" }, 4,
		{ AdsTime = 0.92, SpreadHip = 0.88, RecoilH = 1.1, RecoilV = 1.03 }),
	A("Folding", "Underbarrel", "Folding Grip", "Controls sideways recoil. Slower to aim and a little heavier.", { "AR", "SMG", "LMG" }, 6,
		{ RecoilH = 0.78, RecoilV = 0.97, Move = -0.015, AdsTime = 1.05 }),
	-- magazines
	A("ExtMag", "Magazine", "Extended Mag", "40% more rounds. Slower reload, aim and sprint out, a little heavier.", { "Pistol", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 2,
		{ Mag = 1.4, Reload = 1.15, AdsTime = 1.04, Move = -0.015, SprintOut = 1.08 }),
	A("FastMag", "Magazine", "Fast Mag", "Much faster reloads, noticeably fewer rounds.", { "Pistol", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 4, { Reload = 0.78, Mag = 0.88 }),
	A("Drum", "Magazine", "Drum Mag", "Double the rounds. Heavy: slow to reload, raise, aim and sprint out, and slower on your feet.", { "AR", "SMG" }, 6,
		{ Mag = 2.0, Reload = 1.35, Move = -0.05, AdsTime = 1.1, AdsMove = -0.04, SprintOut = 1.25, Equip = 1.15 }),
	A("Speedloader", "Magazine", "Speedloader", "Fast cylinder reload. Slower to raise.", { "Revolver" }, 2, { Reload = 0.7, Equip = 1.15 }),
	A("ExtCylinder", "Magazine", "Extended Cylinder", "One extra chamber. Slower to reload and aim.", { "Revolver" }, 4, { MagAdd = 1, Reload = 1.08, AdsTime = 1.04 }),
	A("ExtTube", "Magazine", "Extended Tube", "Two more shells. Slower to load and aim, heavier.", { "Shotgun" }, 2, { MagAdd = 2, Reload = 1.08, AdsTime = 1.04, Move = -0.015 }),
	A("ShellCarrier", "Magazine", "Shell Carrier", "Shells strapped to the gun: faster loading and more spare shells. A bit heavier.", { "Shotgun" }, 4,
		{ Reload = 0.8, Reserve = 1.25, Move = -0.02, AdsTime = 1.04 }),
	A("StripperClip", "Magazine", "Stripper Clip", "Loads the whole magazine in one push. Much faster reloads, slower to raise, fewer spare rounds.", { "Sniper" }, 4,
		{ Reload = 0.75, Equip = 1.15, Reserve = 0.9 }),
	A("BoxExt", "Magazine", "Extended Belt Box", "Half again as many rounds. Heavy: slow to reload, aim and sprint out.", { "LMG" }, 4,
		{ Mag = 1.5, Reload = 1.2, Move = -0.04, AdsTime = 1.08, SprintOut = 1.15 }),
	A("DualMag", "Magazine", "Dual Mags", "Two mags taped together: a very fast reload on an empty gun, fewer rounds, bulky to aim.", { "AR", "SMG", "Marksman" }, 5,
		{ ReloadEmpty = 0.7, Mag = 0.9, Move = -0.01, AdsTime = 1.04, SprintOut = 1.1 }),
	A("LightMag", "Magazine", "Lightweight Mag", "Polymer mag. Quicker to raise and a little faster on your feet, fewer rounds and a hotter reload.", { "Pistol", "AR", "SMG", "Marksman" }, 3,
		{ Equip = 0.85, Move = 0.015, Mag = 0.82, Reload = 0.97, SprintOut = 0.9 }),
	A("Bandolier", "Magazine", "Ammo Bandolier", "Carry 50% more spare ammo. Weighs you down and slows sprint out.", GUNS, 3, { Reserve = 1.5, Move = -0.03, SprintOut = 1.1 }),
	-- ammunition
	A("HighVel", "Ammo", "High Velocity", "Damage holds out much further and bullets fly much faster. A little less damage and a harsher kick.", GUNS, 3,
		{ Range = 1.25, Damage = 0.97, Velocity = 1.25, Kick = 1.08, RecoilV = 1.05 }),
	A("FMJ", "Ammo", "Full Metal Jacket", "Bullets punch through walls and bodies far more easily. Less damage and a weaker headshot bonus.",
		{ "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 4, { Damage = 0.94, PenMult = 1.8, Head = -0.05 }),
	A("Overpressure", "Ammo", "Overpressured Rounds", "More damage and range, but harsh recoil and fewer spare rounds.", GUNS, 5,
		{ Damage = 1.1, RecoilV = 1.15, RecoilH = 1.08, Kick = 1.12, Range = 1.05, Reserve = 0.85 }),
	A("Slugs", "Ammo", "Slugs", "One heavy projectile instead of pellets. Tight and long ranged, but a miss is a miss and you carry fewer.", { "Shotgun" }, 4,
		{ SetPellets = 1, Damage = 5.5, Range = 1.9, SpreadHip = 0.3, SpreadAds = 0.15, Head = 0.3, Velocity = 1.3, PenMult = 2.2, Reserve = 0.8 }),
	A("HollowPoint", "Ammo", "Hollow Point", "Expands on impact: more damage and a headshot bonus, but it will not punch through walls.",
		{ "Pistol", "Revolver", "AR", "SMG", "Marksman" }, 3, { Damage = 1.08, Head = 0.1, PenMult = 0.3, Range = 0.95 }),
	A("Subsonic", "Ammo", "Subsonic Rounds", "Slow, quiet rounds: shots are only heard nearby and recoil is softer. Heavy bullet drop and less range.",
		{ "Pistol", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 5, { Suppressed = true, Velocity = 0.65, RecoilV = 0.92, Kick = 0.92, Range = 0.9, Damage = 0.97 }),
	A("ArmorPiercing", "Ammo", "Armor Piercing", "Hard core rounds: 40% of every hit ignores armor plates. A little less raw damage, better penetration.",
		{ "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 6, { Damage = 0.94, PenMult = 1.4, ArmorPierce = 0.4 }),
	A("Incendiary", "Ammo", "Incendiary Rounds", "Sets targets on fire for 3 seconds. Less range and punch through cover.",
		{ "Pistol", "Revolver", "AR", "SMG", "LMG", "Marksman", "Sniper" }, 7, { Damage = 0.92, Range = 0.9, PenMult = 0.7, Burn = { Dps = 9, Time = 3 } }),
	A("Flechette", "Ammo", "Flechette", "Three extra pellets in a tighter, penetrating pattern. Each pellet hits softer.",
		{ "Shotgun" }, 3, { PelletAdd = 3, Damage = 0.8, SpreadHip = 0.85, SpreadAds = 0.85, PenMult = 1.6 }),
	A("DragonBreath", "Ammo", "Dragon's Breath", "Burning magnesium shot ignites whoever it hits. Short range and a wide pattern.",
		{ "Shotgun" }, 6, { Damage = 0.85, Range = 0.8, SpreadHip = 1.15, SpreadAds = 1.15, Burn = { Dps = 11, Time = 3 } }),
	-- stocks
	A("Skeleton", "Stock", "Skeleton Stock", "Lighter and quicker to sprint out and aim. Less recoil control.", { "AR", "SMG", "LMG", "Shotgun" }, 2,
		{ Move = 0.03, AdsTime = 0.95, SprintOut = 0.88, RecoilV = 1.08, RecoilH = 1.05 }),
	A("NoStock", "Stock", "No Stock", "Fastest aim and movement, kicks hard and sways when aimed.", { "AR", "SMG", "Marksman" }, 3,
		{ AdsTime = 0.86, Move = 0.04, SprintOut = 0.8, RecoilV = 1.12, RecoilH = 1.12, SpreadAds = 1.1 }),
	A("CheekPad", "Stock", "Cheek Pad", "Holds breath longer. Slower to aim and a bit heavier.", { "Sniper", "Marksman" }, 4, { ScopeBreath = 1.5, AdsTime = 1.05, Move = -0.015 }),
	A("HeavyStock", "Stock", "Heavy Stock", "Steady but slow: much slower to aim, move with and sprint out.", { "AR", "SMG", "LMG", "Marksman", "Sniper", "Shotgun" }, 5,
		{ RecoilV = 0.88, RecoilH = 0.92, AdsTime = 1.12, Move = -0.04, SprintOut = 1.2 }),
}
Armory.Attachments = {}
for _, a in list do Armory.Attachments[a.Id] = a end

local slotIndex = {}
for i, s in Armory.Slots do slotIndex[s] = i end

function Armory.AttachmentFits(id, weapon)
	local a, w = Armory.Attachments[id], Config.Weapons[weapon]
	return a ~= nil and w ~= nil and table.find(a.Classes, w.Class) ~= nil
end

-- every attachment that fits `weapon`, grouped by slot and sorted by unlock level
function Armory.AttachmentsFor(weapon, slot)
	local out = {}
	for _, a in list do
		if (slot == nil or a.Slot == slot) and Armory.AttachmentFits(a.Id, weapon) then table.insert(out, a.Id) end
	end
	table.sort(out, function(x, y)
		local ax, ay = Armory.Attachments[x], Armory.Attachments[y]
		if ax.Lvl ~= ay.Lvl then return ax.Lvl < ay.Lvl end
		return x < y
	end)
	return out
end

-- ================================================================ building a weapon with attachments
local function deepWeapon(base)
	local c = table.clone(base)
	local dmg = {}
	for i, e in base.Damage do dmg[i] = { e[1], e[2] } end
	c.Damage = dmg
	c.Spread = table.clone(base.Spread)
	local rec = table.clone(base.Recoil)
	local pat = {}
	for i, v in base.Recoil.Pattern do pat[i] = v end
	rec.Pattern = pat
	c.Recoil = rec
	if base.Scope then c.Scope = table.clone(base.Scope) end
	return c
end

local function applyMods(c, m)
	if m.Damage then for _, e in c.Damage do e[2] *= m.Damage end end
	if m.Range then for _, e in c.Damage do e[1] *= m.Range end end
	if m.Velocity then c.VelMult = (c.VelMult or 1) * m.Velocity end
	if m.PenMult then c.PenMult = (c.PenMult or 1) * m.PenMult end
	if m.Head then c.HeadMult += m.Head end
	if m.RPM then c.RPM *= m.RPM end
	if m.SetPellets then c.Pellets = m.SetPellets end
	if m.Mag then c.MagSize = math.max(1, math.floor(c.MagSize * m.Mag + 0.5)) end
	if m.MagAdd then c.MagSize += m.MagAdd end
	if m.Reserve then c.Reserve = math.max(0, math.floor(c.Reserve * m.Reserve + 0.5)) end
	if m.ReserveAdd then c.Reserve += m.ReserveAdd end
	if m.PelletAdd then c.Pellets = (c.Pellets or 1) + m.PelletAdd end
	if m.ArmorPierce then c.ArmorPierce = math.clamp((c.ArmorPierce or 0) + m.ArmorPierce, 0, 1) end
	if m.Burn then c.Burn = { Dps = m.Burn.Dps, Time = m.Burn.Time } end
	if m.ReloadEmpty and c.ReloadEmptyTime then c.ReloadEmptyTime *= m.ReloadEmpty end
	if m.Reload then
		for _, k in { "ReloadTime", "ReloadEmptyTime", "ShellTime", "ReloadStart", "ReloadEnd" } do
			if c[k] then c[k] *= m.Reload end
		end
	end
	if m.AdsTime then c.AdsTime *= m.AdsTime end
	if m.AdsFov then c.AdsFov = math.max(8, c.AdsFov + m.AdsFov) end
	if m.Move then c.MoveMult += m.Move end
	if m.AdsMove then c.AdsMoveMult += m.AdsMove end
	if m.Equip then c.EquipTime *= m.Equip end
	if m.SprintOut then c.SprintOutTime *= m.SprintOut end
	if m.Kick then c.Kick *= m.Kick end
	if m.RecoilV or m.RecoilH then
		for i, v in c.Recoil.Pattern do
			c.Recoil.Pattern[i] = Vector2.new(v.X * (m.RecoilV or 1), v.Y * (m.RecoilH or 1))
		end
	end
	if m.SpreadHip then c.Spread.Hip *= m.SpreadHip end
	if m.SpreadAds then c.Spread.Ads *= m.SpreadAds end
	if m.Scope then c.Scope = table.clone(m.Scope) end
	if m.ScopeBreath and c.Scope then c.Scope.Breath = (c.Scope.Breath or 0) + m.ScopeBreath end
	if m.Suppressed then c.Suppressed = true end
end

local buildCache = {}
-- Returns the weapon config with attachments applied. Never mutates Config.Weapons. Results are cached (do not modify them).
function Armory.Build(weapon, ids)
	local base = Config.Weapons[weapon]
	if not base then return nil end
	if not ids or #ids == 0 or base.Class == "Melee" then return base end
	local key = weapon .. "|" .. table.concat(ids, ",")
	local hit = buildCache[key]
	if hit then return hit end
	local c = deepWeapon(base)
	for _, id in ids do
		local a = Armory.Attachments[id]
		if a and Armory.AttachmentFits(id, weapon) then applyMods(c, a.Mods) end
	end
	c.Attachments = ids
	buildCache[key] = c
	return c
end

-- Stat bars (0..1) for the UI. Higher is always better.
function Armory.Stats(cfg)
	local function c(v) return math.clamp(v, 0, 1) end
	if cfg.Class == "Melee" then
		local L = cfg.Melee.Light
		return { { "Damage", c(L.Damage / 150) }, { "Speed", c(1 / L.Time / 3) }, { "Reach", c(L.Range / 12) }, { "Mobility", c((cfg.MoveMult - 0.85) / 0.25) } }
	end
	local dmg = cfg.Projectile and cfg.Projectile.Damage[1] / 300 or cfg.Damage[1][2] * (cfg.Pellets or 1) / 150
	local range = cfg.Projectile and 0.9 or cfg.Damage[#cfg.Damage][1] / 400
	local bal = Ballistics.For(cfg)
	local velocity = bal and bal.Speed / 4000 or cfg.Projectile and cfg.Projectile.Speed / 4000 or 1 -- hitscan = instant
	local pat = cfg.Recoil.Pattern
	local sum, n = 0, math.min(#pat, 8)
	for i = 1, n do sum += math.abs(pat[i].X) end
	local recoil = (n > 0 and sum / n or 0) * (0.6 + cfg.Kick * 0.25)
	return {
		{ "Damage", c(dmg) }, { "Fire rate", c(cfg.RPM / 1000) }, { "Range", c(range) }, { "Velocity", c(velocity) },
		{ "Accuracy", c(1 - (cfg.Spread.Hip - 1) / 5) }, { "Control", c(1 - recoil / 5) },
		{ "Handling", c(0.7 * (1 - (cfg.AdsTime - 0.1) / 0.3) + 0.3 * (1 - ((cfg.SprintOutTime or 0.15) - 0.05) / 0.25)) }, { "Mobility", c((cfg.MoveMult - 0.85) / 0.25) }, { "Magazine", c(cfg.MagSize / 60) },
		{ "Reserve", c((cfg.Reserve or 0) / 300) },
	}
end

-- ================================================================ unlock state
-- `data` = { XP = number, WeaponXP = { [weapon] = xp }, Bought = { [key] = true }, Credits = number }
function Armory.Key(kind, id, weapon)
	if kind == "Att" then return ("Att:%s:%s"):format(weapon or "?", id) end
	return kind .. ":" .. tostring(id)
end

function Armory.WeaponLevelFromXP(xp)
	xp = math.max(0, xp or 0)
	local lvl = 1
	for i = 2, Armory.MaxWeaponLevel do
		if xp >= Armory.WeaponLevelXP[i] then lvl = i end
	end
	local nextXP = Armory.WeaponLevelXP[lvl + 1]
	return lvl, xp, nextXP -- level, total xp, xp for the next level (nil at max)
end

-- What an item needs: { Track = "Player" | "Weapon", Level, Need (xp), Weapon? }
function Armory.Requirement(kind, id, weapon)
	local level
	if kind == "Weapon" then level = Armory.WeaponUnlock[id]
	elseif kind == "Equip" then level = Armory.EquipUnlock[id]
	elseif kind == "Perk" then level = Armory.PerkUnlock[id]
	elseif kind == "Streak" then level = Armory.Streaks[id] and Armory.Streaks[id].Level
	elseif kind == "Class" then level = Armory.ClassLevels[tonumber(id) or 0]
	elseif kind == "Att" then
		local a = Armory.Attachments[id]
		if not a then return nil end
		return { Track = "Weapon", Level = a.Lvl, Need = Armory.WeaponLevelXP[a.Lvl] or math.huge, Weapon = weapon }
	end
	if not level then return nil end
	return { Track = "Player", Level = level, Need = Progression.XPForLevel(level) }
end

-- Full picture for one item: Unlocked, Have / Need / Remaining (xp), Frac (0..1), Price (credits, nil when unlocked), Bought
function Armory.Progress(data, kind, id, weapon)
	local req = Armory.Requirement(kind, id, weapon)
	if not req then return { Exists = false, Unlocked = false } end
	local E = Armory.Econ
	local have = 0
	local rate = E.PlayerXPPrice
	if req.Track == "Player" then
		have = data and data.XP or 0
	else
		have = data and data.WeaponXP and data.WeaponXP[weapon] or 0
		rate = E.WeaponXPPrice
	end
	local bought = data and data.Bought and data.Bought[Armory.Key(kind, id, weapon)] == true
	local remaining = math.max(0, req.Need - have)
	local unlocked = Armory.UnlockAll or bought or remaining <= 0
	local p = { Exists = true, Track = req.Track, Level = req.Level, Need = req.Need, Have = math.min(have, req.Need), Remaining = remaining,
		Frac = req.Need > 0 and math.clamp(have / req.Need, 0, 1) or 1, Unlocked = unlocked, Bought = bought }
	if not unlocked then p.Price = math.clamp(math.ceil(remaining * rate), E.MinPrice, E.MaxPrice) end
	return p
end

function Armory.IsUnlocked(data, kind, id, weapon)
	if Armory.UnlockAll then return true end
	local p = Armory.Progress(data, kind, id, weapon)
	return p.Exists and p.Unlocked
end

-- Items of a kind, ordered by unlock level then name. kind: Weapon | Equip | Perk | Streak
function Armory.Ids(kind, filter)
	local out = {}
	if kind == "Weapon" then
		for n in Config.Weapons do table.insert(out, n) end
	elseif kind == "Equip" then
		for n, d in Config.Equipment do if d.Kind == filter then table.insert(out, n) end end
	elseif kind == "Perk" then
		for n, d in Config.Perks do if d.Slot == filter then table.insert(out, n) end end
	elseif kind == "Streak" then
		out = table.clone(Armory.StreakOrder)
	end
	local function lvl(n)
		local r = Armory.Requirement(kind, n)
		return r and r.Level or 999
	end
	table.sort(out, function(a, b)
		local la, lb = lvl(a), lvl(b)
		if la ~= lb then return la < lb end
		return a < b
	end)
	return out
end

-- Credits earned for XP (the server keeps the fractional remainder)
function Armory.CreditsForXP(xp) return xp * Armory.Econ.CreditsPerXP end

-- Attachment list for a weapon: only real, fitting, unlocked ids, one per slot, at most MaxAttachments
function Armory.CleanAttachments(weapon, ids, data)
	local out, used = {}, {}
	if type(ids) ~= "table" then return out end
	for _, id in ids do
		local a = type(id) == "string" and Armory.Attachments[id]
		if a and not used[a.Slot] and #out < Armory.MaxAttachments and Armory.AttachmentFits(id, weapon)
			and (data == nil or Armory.IsUnlocked(data, "Att", id, weapon)) then
			used[a.Slot] = true
			table.insert(out, id)
		end
	end
	table.sort(out, function(x, y) return slotIndex[Armory.Attachments[x].Slot] < slotIndex[Armory.Attachments[y].Slot] end)
	return out
end

-- ================================================================ classes
local function cls(name, primary, secondary, lethal, tactical, perks, streaks)
	return { Name = name, Primary = { Id = primary, Att = {} }, Secondary = { Id = secondary, Att = {} }, Lethal = lethal, Tactical = tactical,
		Perks = perks, Streaks = streaks }
end

function Armory.DefaultClass(i)
	local perks = { "DoubleTime", "QuickFix", "DeadSilence" }
	local streaks = { "UAV", "", "" }
	local name = ("CLASS %d"):format(i)
	if i == 1 then return cls("ASSAULT", "M4A1", "M1911", "Frag", "Flash", perks, streaks)
	elseif i == 2 then return cls("CQB", "MP5", "M1911", "Frag", "Flash", perks, streaks)
	elseif i == 3 then return cls("RUSHER", "MP5", "CombatKnife", "Frag", "Flash", perks, streaks) end
	return cls(name, "M4A1", "M1911", "Frag", "Flash", perks, streaks)
end

function Armory.DefaultClasses()
	local out = {}
	for i = 1, 5 do out[i] = Armory.DefaultClass(i) end
	return out
end

function Armory.ClassUnlocked(data, i)
	return Armory.IsUnlocked(data, "Class", i)
end

local function cleanName(s, fallback)
	if type(s) ~= "string" then return fallback end
	s = s:gsub("[^%w %-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	s = s:sub(1, Armory.ClassNameLen):upper()
	if s == "" then return fallback end
	return s
end

local function sanitizeWeapon(data, entry, fb, wantPrimary, overkill, otherId)
	local id = type(entry) == "table" and entry.Id
	local w = type(id) == "string" and Config.Weapons[id]
	local ok = w and Armory.IsUnlocked(data, "Weapon", id) and id ~= otherId
	if ok then
		if wantPrimary then ok = w.Class ~= "Melee" and (Config.IsPrimary(id) or overkill)
		else ok = not Config.IsPrimary(id) or overkill end
	end
	if not ok then
		id = fb.Id
		entry = fb
	end
	return { Id = id, Att = Armory.CleanAttachments(id, entry.Att, data) }
end

-- Returns a clean class. Anything invalid (not unlocked, wrong slot, unknown) falls back to `old`, then to the starter class.
function Armory.SanitizeClass(data, c, old)
	local base = Armory.DefaultClass(1)
	old = type(old) == "table" and old or base
	c = type(c) == "table" and c or {}
	local out = { Name = cleanName(c.Name, old.Name or base.Name) }

	local perks = {}
	local raw = type(c.Perks) == "table" and c.Perks or {}
	for slot = 1, 3 do
		local p = raw[slot]
		local def = type(p) == "string" and Config.Perks[p]
		if def and def.Slot == slot and Armory.IsUnlocked(data, "Perk", p) then perks[slot] = p
		elseif p == "" then perks[slot] = ""
		else perks[slot] = (old.Perks and old.Perks[slot]) or base.Perks[slot] end
	end
	out.Perks = perks
	local overkill = perks[1] == "Overkill"

	local defPrimary, defSecondary = { Id = Config.Loadout.Primary, Att = {} }, { Id = Config.Loadout.Secondary, Att = {} }
	local oldPrimary = old.Primary and Armory.IsUnlocked(data, "Weapon", old.Primary.Id) and old.Primary or defPrimary
	local oldSecondary = old.Secondary and Armory.IsUnlocked(data, "Weapon", old.Secondary.Id) and old.Secondary or defSecondary
	out.Primary = sanitizeWeapon(data, c.Primary, oldPrimary, true, overkill, nil)
	-- if the old fallback is not legal any more (Overkill was removed) use the starter weapon
	local p = Config.Weapons[out.Primary.Id]
	if not (p and p.Class ~= "Melee" and (Config.IsPrimary(out.Primary.Id) or overkill)) then out.Primary = { Id = defPrimary.Id, Att = {} } end
	out.Secondary = sanitizeWeapon(data, c.Secondary, oldSecondary, false, overkill, out.Primary.Id)
	if out.Secondary.Id == out.Primary.Id or (Config.IsPrimary(out.Secondary.Id) and not overkill) then out.Secondary = { Id = defSecondary.Id, Att = {} } end

	for _, k in { { "Lethal", "Lethal" }, { "Tactical", "Tactical" } } do
		local field, kind = k[1], k[2]
		local v = c[field]
		local def = type(v) == "string" and Config.Equipment[v]
		if def and def.Kind == kind and Armory.IsUnlocked(data, "Equip", v) then out[field] = v
		else
			local ov = old[field]
			local od = ov and Config.Equipment[ov]
			out[field] = (od and od.Kind == kind and Armory.IsUnlocked(data, "Equip", ov)) and ov or base[field]
		end
	end

	local streaks, seen = {}, {}
	local rawS = type(c.Streaks) == "table" and c.Streaks or {}
	local oldS = type(old.Streaks) == "table" and old.Streaks or {}
	for i = 1, 3 do
		local s = rawS[i]
		if not (type(s) == "string" and (s == "" or (Armory.Streaks[s] and Armory.IsUnlocked(data, "Streak", s)))) then
			s = oldS[i] or ""
			if s ~= "" and not (Armory.Streaks[s] and Armory.IsUnlocked(data, "Streak", s)) then s = "" end
		end
		if s ~= "" and seen[s] then s = "" end
		if s ~= "" then seen[s] = true end
		streaks[i] = s
	end
	out.Streaks = streaks
	return out
end

-- The shape FPSServer / WeaponController work with
function Armory.ToLoadout(c)
	local perks = {}
	for slot = 1, 3 do
		if c.Perks[slot] and c.Perks[slot] ~= "" then table.insert(perks, c.Perks[slot]) end
	end
	local attach = { [c.Primary.Id] = c.Primary.Att, [c.Secondary.Id] = c.Secondary.Att }
	return { Primary = c.Primary.Id, Secondary = c.Secondary.Id, Lethal = c.Lethal, Tactical = c.Tactical, Perks = perks,
		Attach = attach, Streaks = table.clone(c.Streaks), Name = c.Name }
end

return Armory
