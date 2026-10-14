-- Weapon mastery: long-term goals per weapon on top of weapon levels (Armory.WeaponLevelXP, which unlock attachments).
-- A tier needs ALL of: weapon level, kills with that weapon, headshot kills with that weapon. The server (AchievementService) checks after every
-- kill and pays each newly reached tier once per weapon: Credits + XP, plus a Title / Emblem the first time ANY weapon reaches that tier.
-- Camo is the name of the gun finish the tier unlocks. It is saved (Data.Mastery[weapon] = tier) and sent with GetMastery,
-- but no gun model uses it yet: read it where the gun is built (GunBuilder / Viewmodel) to paint it.
-- Add a tier = one line below (keep them in ascending order). Title / Emblem ids must exist in Cosmetics (reward-only items at the bottom of it).
local Armory = require(script.Parent.Armory)

local Mastery = {}

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

Mastery.Tiers = {
	{ Id = "Bronze",   Name = "BRONZE",   Level = 2, Kills = 25,  HeadKills = 5,   Camo = "Bronze Plate",   Color = C(205, 127, 50),  Credits = 400,  XP = 800,   Title = "Apprentice",    Emblem = "MasteryBronze" },
	{ Id = "Silver",   Name = "SILVER",   Level = 3, Kills = 75,  HeadKills = 20,  Camo = "Brushed Silver", Color = C(192, 198, 206), Credits = 800,  XP = 2000,  Title = "Adept",         Emblem = "MasterySilver" },
	{ Id = "Gold",     Name = "GOLD",     Level = 5, Kills = 200, HeadKills = 60,  Camo = "Gold Leaf",      Color = C(255, 205, 80),  Credits = 1600, XP = 4500,  Title = "Gold Standard", Emblem = "MasteryGold" },
	{ Id = "Platinum", Name = "PLATINUM", Level = 6, Kills = 450, HeadKills = 150, Camo = "Platinum Frost", Color = C(150, 220, 235), Credits = 3000, XP = 9000,  Title = "Platinum Hands", Emblem = "MasteryPlatinum" },
	{ Id = "Diamond",  Name = "DIAMOND",  Level = 7, Kills = 900, HeadKills = 350, Camo = "Diamond Cut",    Color = C(130, 190, 255), Credits = 6000, XP = 20000, Title = "Diamond Cutter", Emblem = "MasteryDiamond" },
}
Mastery.ById = {}
for i, t in Mastery.Tiers do
	t.Index = i
	Mastery.ById[t.Id] = t
end

-- highest tier index (0 = none) these numbers qualify for
function Mastery.TierReached(kills, headKills, weaponXP)
	local level = Armory.WeaponLevelFromXP(weaponXP or 0)
	local reached = 0
	for i, t in Mastery.Tiers do
		if level >= t.Level and (kills or 0) >= t.Kills and (headKills or 0) >= t.HeadKills then reached = i else break end
	end
	return reached
end

-- { Weapon, Kills, HeadKills, Level, Tier, TierName, Next = tier def or nil }
function Mastery.Progress(weapon, kills, headKills, weaponXP)
	local level = Armory.WeaponLevelFromXP(weaponXP or 0)
	local tier = Mastery.TierReached(kills, headKills, weaponXP)
	return {
		Weapon = weapon, Kills = kills or 0, HeadKills = headKills or 0, Level = level,
		Tier = tier, TierName = tier > 0 and Mastery.Tiers[tier].Name or "", Next = Mastery.Tiers[tier + 1],
	}
end

return Mastery
