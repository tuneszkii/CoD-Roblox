-- AchievementService: achievements (Achievements.luau) and weapon mastery (Mastery.luau), tracked on the server, saved in the profile.
--   Achievements.Add(plr, key, n) / .Max(plr, key, value)   progress events from the other services (see the KEY list in Achievements.luau)
--   Achievements.CheckMastery(plr, weapon)                  after a weapon kill: pays every newly reached mastery tier
--   GetAchievements()  -> { Progress = { [key] = n }, Done = { [id] = unix time } }   (definitions are shared: Achievements.List)
--   GetMastery()       -> { { Weapon, Kills, HeadKills, Level, Tier, TierName, Next, Claimed }, ... } best first
--   AchievementEvent (server -> client): ("Achievement", { Id, Name, Desc, Text }) / ("Mastery", { Weapon, Tier, TierName, Camo, Text })
-- Rewards: XP and credits through DataService, titles / emblems put in the player's owned cosmetics (reward-only items in Cosmetics.luau).
-- Saved fields (DataService): AchProgress[key], AchDone[id], Mastery[weapon] = highest tier paid.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local FPS = RS:WaitForChild("FPS")
local Config = require(FPS:WaitForChild("Config"))
local Achievements = require(FPS:WaitForChild("Achievements"))
local Mastery = require(FPS:WaitForChild("Mastery"))
local Cosmetics = require(FPS:WaitForChild("Cosmetics"))

local A = {}
local ctx
local lastCall = {}

local function data(plr)
	local d = ctx.Data.Get(plr)
	if not d then return nil end
	if type(d.AchProgress) ~= "table" then d.AchProgress = {} end
	if type(d.AchDone) ~= "table" then d.AchDone = {} end
	if type(d.Mastery) ~= "table" then d.Mastery = {} end
	return d
end

-- put a reward-only cosmetic in the player's owned list. Returns its name when it was new
local function grantCosmetic(plr, d, cat, id)
	local def = id and Cosmetics.Get(cat, id)
	if not def then return nil end
	if type(d.Cosmetics) ~= "table" then d.Cosmetics = Cosmetics.Sanitize(d.XP, d.Cosmetics) end
	local key = Cosmetics.Key(cat, id)
	if d.Cosmetics.Owned[key] then return nil end
	d.Cosmetics.Owned[key] = true
	ctx.Data.MarkDirty(plr)
	return def.Name
end

local function payOut(plr, d, r)
	if r.XP then ctx.Data.AddXP(plr, r.XP) end
	if r.Credits then ctx.Data.AddCredits(plr, r.Credits) end
	return grantCosmetic(plr, d, "Title", r.Title), grantCosmetic(plr, d, "Emblem", r.Emblem)
end

local function rewardText(r, title, emblem)
	local t = Achievements.RewardText({ XP = r.XP, Credits = r.Credits, Title = title, Emblem = emblem }) -- only what was actually new
	return t
end

-- ---------------------------------------------------------------- achievements
local function complete(plr, d, def)
	if d.AchDone[def.Id] then return end
	d.AchDone[def.Id] = os.time()
	ctx.Data.MarkDirty(plr)
	local title, emblem = payOut(plr, d, def.Reward)
	ctx.Remotes.AchievementEvent:FireClient(plr, "Achievement", { Id = def.Id, Name = def.Name, Desc = def.Desc, Text = rewardText(def.Reward, title, emblem) })
	A.Add(plr, "Achievements", 1)
end

local function bump(plr, key, value, isMax)
	local defs = Achievements.ByKey[key]
	if not ctx or not defs or type(value) ~= "number" then return end
	local d = data(plr)
	if not d then return end
	local cur = d.AchProgress[key] or 0
	local new = isMax and math.max(cur, value) or cur + value
	if new == cur then return end
	d.AchProgress[key] = new
	ctx.Data.MarkDirty(plr)
	for _, def in defs do
		if new >= def.Goal and not d.AchDone[def.Id] then complete(plr, d, def) end
	end
end

function A.Add(plr, key, n) bump(plr, key, n or 1, false) end
function A.Max(plr, key, value) bump(plr, key, value, true) end

-- ---------------------------------------------------------------- weapon mastery
function A.CheckMastery(plr, weapon)
	local d = ctx and data(plr)
	local cfg = Config.Weapons[weapon]
	local w = d and d.WeaponStats[weapon]
	if not d or not cfg or cfg.Class == "Melee" or not w then return end
	local reached = Mastery.TierReached(w.Kills or 0, w.HeadKills or 0, d.WeaponXP[weapon] or 0)
	local paid = d.Mastery[weapon] or 0
	while paid < reached do
		paid += 1
		d.Mastery[weapon] = paid
		ctx.Data.MarkDirty(plr)
		local tier = Mastery.Tiers[paid]
		local title, emblem = payOut(plr, d, tier) -- Title / Emblem are only new for the first weapon to reach the tier
		ctx.Remotes.AchievementEvent:FireClient(plr, "Mastery", {
			Weapon = weapon, Tier = tier.Id, TierName = tier.Name, Camo = tier.Camo,
			Text = rewardText(tier, title, emblem),
		})
		A.Add(plr, "Mastery:" .. tier.Id, 1)
	end
end

-- ---------------------------------------------------------------- remotes
local function throttled(plr, key, gap)
	local t = os.clock()
	local last = lastCall[plr] or {}
	lastCall[plr] = last
	if t - (last[key] or -10) < gap then return true end
	last[key] = t
	return false
end

function A.Init(c)
	ctx = c
	ctx.Remotes.GetAchievements.OnServerInvoke = function(plr)
		if throttled(plr, "Ach", 0.5) or not ctx.Data.Wait(plr, 15) then return nil end
		local d = data(plr)
		return d and { Progress = d.AchProgress, Done = d.AchDone } or nil
	end
	ctx.Remotes.GetMastery.OnServerInvoke = function(plr)
		if throttled(plr, "Mastery", 0.5) or not ctx.Data.Wait(plr, 15) then return nil end
		local d = data(plr)
		if not d then return nil end
		local rows = {}
		for weapon, w in d.WeaponStats do
			local cfg = Config.Weapons[weapon]
			if cfg and cfg.Class ~= "Melee" then
				local row = Mastery.Progress(weapon, w.Kills or 0, w.HeadKills or 0, d.WeaponXP[weapon] or 0)
				row.Claimed = d.Mastery[weapon] or 0
				table.insert(rows, row)
			end
		end
		table.sort(rows, function(a, b)
			if a.Tier ~= b.Tier then return a.Tier > b.Tier end
			if a.Kills ~= b.Kills then return a.Kills > b.Kills end
			return a.Weapon < b.Weapon
		end)
		return rows
	end
	Players.PlayerRemoving:Connect(function(plr) lastCall[plr] = nil end)
end

return A
