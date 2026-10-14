-- Player data (DataStore): XP / level, lifetime stats, medal counts and the saved loadout.
-- Loads with retries, autosaves, saves on leave and on shutdown. If loading fails (e.g. Studio API access is off) the player plays with
-- temporary data and it is NEVER saved, so a failed load can't overwrite real progress.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("FPS"):WaitForChild("Config"))
local Progression = require(RS.FPS:WaitForChild("Progression"))
local Armory = require(RS.FPS:WaitForChild("Armory"))

local STORE_NAME = "CoDFPS_PlayerData_v1" -- change the suffix to wipe everyone's progress
local AUTOSAVE = 60
local HISTORY_MAX = 25 -- matches kept in Data.History (oldest dropped first)
local WEAPON_KILL_FIELDS = { Kills = true, HeadKills = true }

-- Armory fields: Credits (+ CreditBank = fractional credits not yet paid out), Bought = unlocks bought forward ("Weapon:AK47", "Att:M4A1:Drum"),
-- WeaponXP per weapon, Classes (custom classes, false = starter classes) and Selected (the class you spawn with).
-- Cosmetics = owned (bought early) + equipped operator / card / emblem / title / tracer / emotes; CosmeticsService fills it in (false = defaults).
-- Stats: Wins / Losses / Draws / MatchesPlayed, Shots / Hits / HeadHits (lifetime accuracy; one shot = one trigger pull, a hit = any pellet hit an enemy),
-- Headshots = kills with a headshot (older field), WeaponStats[weapon] = { Shots, Hits, HeadHits, Kills, HeadKills } and History = the last HISTORY_MAX matches.
-- D.Stats(plr) turns all of it into the numbers a stats page needs (K/D, win/loss, accuracy, headshot rate, best gun ...).
-- Loadout is the old single loadout; ArmoryService turns it into class 1 the first time.
local DEFAULT = { Version = 1, XP = 0, Kills = 0, Deaths = 0, Assists = 0, Headshots = 0, BestStreak = 0, Medals = {}, Loadout = false, Settings = false,
	Credits = Armory.Econ.StartCredits, CreditBank = 0, Bought = {}, WeaponXP = {}, Classes = false, Selected = 1,
	Cosmetics = false,
	Wins = 0, Losses = 0, Draws = 0, MatchesPlayed = 0, Shots = 0, Hits = 0, HeadHits = 0, WeaponStats = {}, History = {},
	AchProgress = {}, AchDone = {}, Mastery = {} } -- achievements + weapon mastery (AchievementService)

local D = {}
local ctx
local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles = {}

local function reconcile(data)
	for k, v in DEFAULT do
		if data[k] == nil then data[k] = type(v) == "table" and table.clone(v) or v end
	end
	return data
end

local function updateLeaderstats(plr)
	local p = profiles[plr]
	local ls = plr:FindFirstChild("leaderstats")
	if not p or not ls then return end
	local level = Progression.LevelFromXP(p.Data.XP)
	ls.Level.Value, ls.Kills.Value, ls.Deaths.Value = level, p.Data.Kills, p.Data.Deaths
end

function D.Summary(plr)
	local p = profiles[plr]
	if not p then return nil end
	local level, into, needed = Progression.LevelFromXP(p.Data.XP)
	return { XP = p.Data.XP, Level = level, Into = into, Needed = needed, Kills = p.Data.Kills, Deaths = p.Data.Deaths,
		Assists = p.Data.Assists, Headshots = p.Data.Headshots, BestStreak = p.Data.BestStreak, Credits = math.floor(p.Data.Credits),
		Wins = p.Data.Wins, Losses = p.Data.Losses }
end

local function load(plr)
	local key = "Player_" .. plr.UserId
	local data, persist = nil, false
	for attempt = 1, 4 do
		local ok, res = pcall(function() return store:GetAsync(key) end)
		if ok then
			data, persist = res, true
			break
		end
		warn(("[DataService] load failed for %s (attempt %d): %s"):format(plr.Name, attempt, tostring(res)))
		task.wait(0.5 * 2 ^ attempt)
		if not plr.Parent then return end
	end
	if not plr.Parent then return end
	if not persist then
		warn("[DataService] " .. plr.Name .. " is using temporary data (not saved). In Studio enable Game Settings > Security > Enable Studio Access to API Services.")
	end
	profiles[plr] = { Data = reconcile(type(data) == "table" and data or {}), Persist = persist, Dirty = false, Tally = { Shots = 0, Hits = 0, HeadHits = 0 } }

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in { "Level", "Kills", "Deaths" } do
		local v = Instance.new("IntValue")
		v.Name, v.Parent = n, ls
	end
	ls.Parent = plr
	updateLeaderstats(plr)
	ctx.Remotes.XPSync:FireClient(plr, D.Summary(plr), false)
	if ctx.Achievements then ctx.Achievements.Max(plr, "Level", (Progression.LevelFromXP(profiles[plr].Data.XP))) end
end

local function save(plr)
	local p = profiles[plr]
	if not p or not p.Persist or not p.Dirty then return end
	p.Dirty = false
	local snapshot = table.clone(p.Data)
	local ok, err = pcall(function()
		store:UpdateAsync("Player_" .. plr.UserId, function() return snapshot end)
	end)
	if not ok then
		p.Dirty = true
		warn(("[DataService] save failed for %s: %s"):format(plr.Name, tostring(err)))
	end
end

-- yields until the profile is loaded (or timeout). Returns the data table or nil.
function D.Wait(plr, timeout)
	local t0 = os.clock()
	while not profiles[plr] and plr.Parent and os.clock() - t0 < (timeout or 10) do task.wait(0.1) end
	return profiles[plr] and profiles[plr].Data
end

function D.Get(plr)
	return profiles[plr] and profiles[plr].Data
end

-- returns the new level if the player leveled up
function D.AddXP(plr, amount)
	local p = profiles[plr]
	if not p or amount <= 0 then return nil end
	local before = Progression.LevelFromXP(p.Data.XP)
	p.Data.XP += amount
	p.Dirty = true
	local after = Progression.LevelFromXP(p.Data.XP)
	D.AddCredits(plr, Armory.CreditsForXP(amount) + (after - before) * Armory.Econ.LevelUpBonus, true)
	updateLeaderstats(plr)
	ctx.Remotes.XPSync:FireClient(plr, D.Summary(plr), after > before)
	if after > before and ctx.Achievements then ctx.Achievements.Max(plr, "Level", after) end
	return after > before and after or nil
end

-- credits can be fractional (XP * rate); the fraction is kept in CreditBank so nothing is lost
function D.AddCredits(plr, amount, silent)
	local p = profiles[plr]
	if not p or amount <= 0 then return end
	p.Data.CreditBank += amount
	local whole = math.floor(p.Data.CreditBank)
	p.Data.CreditBank -= whole
	p.Data.Credits += whole
	p.Dirty = true
	if not silent then D.SyncProfile(plr) end
end

function D.SpendCredits(plr, amount)
	local p = profiles[plr]
	if not p or amount < 0 or math.floor(p.Data.Credits) < amount then return false end
	p.Data.Credits -= amount
	p.Dirty = true
	D.SyncProfile(plr)
	return true
end

function D.MarkDirty(plr)
	local p = profiles[plr]
	if p then p.Dirty = true end
end

-- re-send level / XP / credits to the player (the menu header and the HUD listen to this)
function D.SyncProfile(plr, leveledUp)
	if profiles[plr] then ctx.Remotes.XPSync:FireClient(plr, D.Summary(plr), leveledUp or false) end
end

-- returns oldLevel, newLevel (weapon levels, see Armory.WeaponLevelXP)
function D.AddWeaponXP(plr, weapon, amount)
	local p = profiles[plr]
	if not p or amount <= 0 or type(weapon) ~= "string" then return nil end
	local before = p.Data.WeaponXP[weapon] or 0
	p.Data.WeaponXP[weapon] = before + amount
	p.Dirty = true
	return (Armory.WeaponLevelFromXP(before)), (Armory.WeaponLevelFromXP(before + amount))
end

function D.AddStat(plr, name, n)
	local p = profiles[plr]
	if not p or type(p.Data[name]) ~= "number" then return end
	p.Data[name] += n or 1
	p.Dirty = true
	updateLeaderstats(plr)
end

function D.SetMax(plr, name, value)
	local p = profiles[plr]
	if p and value > (p.Data[name] or 0) then
		p.Data[name] = value
		p.Dirty = true
	end
end

function D.AddMedal(plr, tag)
	local p = profiles[plr]
	if not p then return end
	p.Data.Medals[tag] = (p.Data.Medals[tag] or 0) + 1
	p.Dirty = true
end

-- ---------------------------------------------------------------- shooting stats / match history
-- one trigger pull with a gun. hit = any pellet hit an enemy, head = any pellet hit an enemy's head. Server-validated by FPSServer's Fire handler.
function D.RecordShot(plr, weapon, hit, head)
	local p = profiles[plr]
	if not p or type(weapon) ~= "string" then return end
	local d, t = p.Data, p.Tally
	local w = d.WeaponStats[weapon]
	if not w then
		w = {}
		d.WeaponStats[weapon] = w
	end
	d.Shots += 1
	t.Shots += 1
	w.Shots = (w.Shots or 0) + 1
	if hit then
		d.Hits += 1
		t.Hits += 1
		w.Hits = (w.Hits or 0) + 1
	end
	if head then
		d.HeadHits += 1
		t.HeadHits += 1
		w.HeadHits = (w.HeadHits or 0) + 1
	end
	p.Dirty = true
end

-- field: "Kills" or "HeadKills" (called by ArmoryService when a gun / knife gets a kill)
function D.AddWeaponStat(plr, weapon, field, n)
	local p = profiles[plr]
	if not p or type(weapon) ~= "string" or not WEAPON_KILL_FIELDS[field] then return end
	local w = p.Data.WeaponStats[weapon]
	if not w then
		w = {}
		p.Data.WeaponStats[weapon] = w
	end
	w[field] = (w[field] or 0) + (n or 1)
	p.Dirty = true
end

-- a new match starts for this player: the per-match shooting tally starts from zero
function D.ResetTally(plr)
	local p = profiles[plr]
	if p then p.Tally = { Shots = 0, Hits = 0, HeadHits = 0 } end
end

-- the match is over. info = { Result = "Win" | "Loss" | "Draw", Mode, ModeId, Map, K, D, O }; shots / hits come from the tally
function D.RecordMatch(plr, info)
	local p = profiles[plr]
	if not p or type(info) ~= "table" then return end
	local d, t = p.Data, p.Tally
	if info.Result == "Win" then d.Wins += 1
	elseif info.Result == "Loss" then d.Losses += 1
	else d.Draws += 1 end
	d.MatchesPlayed += 1
	table.insert(d.History, {
		T = os.time(), Mode = info.Mode, ModeId = info.ModeId, Map = info.Map, Result = info.Result,
		K = info.K or 0, D = info.D or 0, O = info.O or 0, Shots = t.Shots, Hits = t.Hits, HeadHits = t.HeadHits,
	})
	while #d.History > HISTORY_MAX do table.remove(d.History, 1) end
	p.Tally = { Shots = 0, Hits = 0, HeadHits = 0 }
	p.Dirty = true
	D.SyncProfile(plr)
	local ach = ctx.Achievements
	if ach then
		ach.Add(plr, "Matches", 1)
		if info.Result == "Win" then
			ach.Add(plr, "Wins", 1)
			if (info.D or 0) == 0 then ach.Add(plr, "Flawless", 1) end
		end
		ach.Max(plr, "MatchKills", info.K or 0)
	end
end

local function ratio(a, b) return b > 0 and a / b or 0 end

-- everything a stats page needs, computed from the saved counters
function D.Stats(plr)
	local p = profiles[plr]
	if not p then return nil end
	local d = p.Data
	local weapons, best = {}, nil
	for name, w in d.WeaponStats do
		local row = {
			Name = name, Kills = w.Kills or 0, HeadKills = w.HeadKills or 0, Shots = w.Shots or 0, Hits = w.Hits or 0, HeadHits = w.HeadHits or 0,
		}
		row.Accuracy, row.HeadshotRate = ratio(row.Hits, row.Shots), ratio(row.HeadKills, row.Kills)
		table.insert(weapons, row)
	end
	table.sort(weapons, function(a, b)
		if a.Kills ~= b.Kills then return a.Kills > b.Kills end
		if a.Hits ~= b.Hits then return a.Hits > b.Hits end
		return a.Name < b.Name
	end)
	for _, row in weapons do -- best gun = most kills, melee does not count as a gun
		local cfg = Config.Weapons[row.Name]
		if row.Kills > 0 and not (cfg and cfg.Class == "Melee") then
			best = row
			break
		end
	end
	local history = {}
	for i = #d.History, 1, -1 do table.insert(history, d.History[i]) end -- newest first
	return {
		Kills = d.Kills, Deaths = d.Deaths, KD = d.Deaths > 0 and d.Kills / d.Deaths or d.Kills, Assists = d.Assists, BestStreak = d.BestStreak,
		Headshots = d.Headshots, HeadHits = d.HeadHits, HeadshotRate = ratio(d.Headshots, d.Kills), -- kills that were headshots / all kills
		Shots = d.Shots, Hits = d.Hits, Accuracy = ratio(d.Hits, d.Shots),
		Wins = d.Wins, Losses = d.Losses, Draws = d.Draws, MatchesPlayed = d.MatchesPlayed,
		WinLoss = d.Losses > 0 and d.Wins / d.Losses or d.Wins, WinRate = ratio(d.Wins, d.MatchesPlayed),
		BestGun = best, Weapons = weapons, History = history,
	}
end

function D.SetLoadout(plr, loadout)
	local p = profiles[plr]
	if p then
		p.Data.Loadout = loadout
		p.Dirty = true
	end
end

-- player options (see Settings.luau); the blob is validated by Settings.Sanitize before it gets here
function D.GetSettings(plr)
	local p = profiles[plr]
	return p and p.Data.Settings or nil
end

function D.SetSettings(plr, blob)
	local p = profiles[plr]
	if p then
		p.Data.Settings = blob
		p.Dirty = true
	end
end

function D.Init(c)
	ctx = c
	local function onPlayer(plr) task.spawn(load, plr) end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in Players:GetPlayers() do onPlayer(plr) end

	Players.PlayerRemoving:Connect(function(plr)
		save(plr)
		profiles[plr] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for plr in profiles do task.spawn(save, plr) end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for plr in profiles do
			pending += 1
			task.spawn(function()
				save(plr)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
	end)
end

return D
