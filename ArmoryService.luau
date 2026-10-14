-- ArmoryService: the server side of the Armory menu.
--   GetArmory()                  -> snapshot (credits, XP, weapon XP, buy-forward purchases, classes, selected class)
--   ArmoryBuy(kind, id, weapon)  -> buy an unlock early. The price comes from Armory.Progress, never from the client.
--   ArmorySave(index, class)     -> validate + store a class (anything not unlocked / illegal is replaced, see Armory.SanitizeClass)
--   ArmorySelect(index)          -> choose the class you spawn with
-- It also pays out weapon XP for kills (Score.OnWeaponKill) and builds the loadout a player spawns with (A.Loadout).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("FPS"):WaitForChild("Config"))
local Armory = require(RS.FPS:WaitForChild("Armory"))

local A = {}
local ctx
local lastCall = {}

local KINDS = { Weapon = true, Equip = true, Perk = true, Streak = true, Class = true, Att = true }

-- first load: fill in the class list. A saved single loadout from before the Armory existed becomes class 1.
local function ensureClasses(plr, d)
	if type(d.Classes) ~= "table" then
		local list = {}
		for i = 1, Armory.MaxClasses do list[i] = Armory.DefaultClass(i) end
		local L = d.Loadout
		if type(L) == "table" then
			local perks = {}
			if type(L.Perks) == "table" then
				for _, n in L.Perks do
					local def = type(n) == "string" and Config.Perks[n]
					if def then perks[def.Slot] = n end
				end
			end
			list[1] = Armory.SanitizeClass(d, { Name = "CLASS 1", Primary = { Id = L.Primary, Att = {} }, Secondary = { Id = L.Secondary, Att = {} },
				Lethal = L.Lethal, Tactical = L.Tactical, Perks = perks, Streaks = { "UAV", "", "" } }, list[1])
		end
		d.Classes = list
		ctx.Data.MarkDirty(plr)
	end
	for i = 1, Armory.MaxClasses do
		if type(d.Classes[i]) ~= "table" then d.Classes[i] = Armory.DefaultClass(i) end
	end
	if type(d.Selected) ~= "number" or d.Selected < 1 or d.Selected > Armory.MaxClasses or d.Selected % 1 ~= 0 then d.Selected = 1 end
end

local function dataFor(plr, wait)
	local d = wait and ctx.Data.Wait(plr, 15) or ctx.Data.Get(plr)
	if not d then return nil end
	ensureClasses(plr, d)
	return d
end

local function snapshot(d)
	return { XP = d.XP, WeaponXP = d.WeaponXP, Bought = d.Bought, Credits = math.floor(d.Credits), Classes = d.Classes, Selected = d.Selected,
		UnlockAll = Armory.UnlockAll }
end

local function throttled(plr, key, gap)
	local t = os.clock()
	local last = lastCall[plr] or {}
	lastCall[plr] = last
	if t - (last[key] or 0) < gap then return true end
	last[key] = t
	return false
end

-- ---------------------------------------------------------------- loadout used when a character spawns
function A.Loadout(plr)
	local d = dataFor(plr, false)
	if not d then return Armory.ToLoadout(Armory.DefaultClass(1)) end
	local c = d.Classes[d.Selected]
	if not Armory.ClassUnlocked(d, d.Selected) then
		d.Selected = 1
		c = d.Classes[1]
	end
	return Armory.ToLoadout(Armory.SanitizeClass(d, c, c))
end

-- ---------------------------------------------------------------- weapon XP
local function onKill(attacker, info)
	local s = ctx.State[attacker]
	local weapon = s and s.Weapon
	local cfg = weapon and Config.Weapons[weapon]
	if not cfg or not info then return end
	local counts = info.Kind == "Bullet" or (info.Kind == "Melee" and cfg.Class == "Melee")
	if not counts then return end
	ctx.Data.AddWeaponStat(attacker, weapon, "Kills", 1) -- stats page: kills / headshot kills per weapon
	if info.Head then ctx.Data.AddWeaponStat(attacker, weapon, "HeadKills", 1) end
	local E = Armory.Econ
	local before, after = ctx.Data.AddWeaponXP(attacker, weapon, E.WeaponXPPerKill + (info.Head and E.WeaponXPHeadshot or 0))
	if before and after > before then
		local unlocked = {}
		for _, id in Armory.AttachmentsFor(weapon) do
			local lvl = Armory.Attachments[id].Lvl
			if lvl > before and lvl <= after then table.insert(unlocked, Armory.Attachments[id].Name) end
		end
		ctx.Remotes.ArmoryEvent:FireClient(attacker, "WeaponLevel", weapon, after, unlocked)
	end
	if ctx.Achievements then ctx.Achievements.CheckMastery(attacker, weapon) end -- weapon mastery tiers (kills / headshot kills / weapon level)
end

-- ---------------------------------------------------------------- remotes
local function buy(plr, kind, id, weapon)
	if throttled(plr, "Buy", 0.25) then return false, "SLOW DOWN" end
	if not KINDS[kind] or (type(id) ~= "string" and type(id) ~= "number") then return false, "INVALID" end
	if kind == "Class" then
		id = tonumber(id)
		if not id or id % 1 ~= 0 then return false, "INVALID" end
	end
	if kind == "Att" then
		if type(id) ~= "string" or type(weapon) ~= "string" or not Config.Weapons[weapon] or not Armory.AttachmentFits(id, weapon) then return false, "INVALID" end
	else
		weapon = nil
	end
	local d = dataFor(plr, true)
	if not d then return false, "NO DATA" end
	if kind == "Att" and not Armory.IsUnlocked(d, "Weapon", weapon) then return false, "UNLOCK THE WEAPON FIRST" end
	local p = Armory.Progress(d, kind, id, weapon)
	if not p.Exists then return false, "INVALID" end
	if p.Unlocked then return false, "ALREADY UNLOCKED" end
	if math.floor(d.Credits) < p.Price then return false, "NOT ENOUGH CREDITS" end
	if not ctx.Data.SpendCredits(plr, p.Price) then return false, "NOT ENOUGH CREDITS" end
	d.Bought[Armory.Key(kind, id, weapon)] = true
	ctx.Data.MarkDirty(plr)
	return true, snapshot(d)
end

local function save(plr, index, class)
	if throttled(plr, "Save", 0.15) then return false end
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > Armory.MaxClasses then return false end
	local d = dataFor(plr, true)
	if not d or not Armory.ClassUnlocked(d, index) then return false end
	local clean = Armory.SanitizeClass(d, class, d.Classes[index])
	d.Classes[index] = clean
	ctx.Data.MarkDirty(plr)
	return clean
end

local function selectClass(plr, index)
	if throttled(plr, "Select", 0.15) then return false end
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > Armory.MaxClasses then return false end
	local d = dataFor(plr, true)
	if not d or not Armory.ClassUnlocked(d, index) then return false end
	d.Selected = index
	ctx.Data.MarkDirty(plr)
	return index
end

function A.Init(c)
	ctx = c
	local R = ctx.Remotes
	R.GetArmory.OnServerInvoke = function(plr)
		local d = dataFor(plr, true)
		return d and snapshot(d) or false
	end
	R.ArmoryBuy.OnServerInvoke = buy
	R.ArmorySave.OnServerInvoke = save
	R.ArmorySelect.OnServerInvoke = selectClass
	ctx.Score.OnWeaponKill = onKill
	Players.PlayerRemoving:Connect(function(plr) lastCall[plr] = nil end)
end

return A
