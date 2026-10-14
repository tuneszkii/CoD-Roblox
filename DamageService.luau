-- Central damage pipeline: friendly-fire rules, perks, armor plates (Warzone style), regen, kill rewards.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("FPS"):WaitForChild("Config"))
local PV = Config.PerkValues

local D = {}
local ctx

function D.Init(c) ctx = c end

function D.IsFriendly(attacker, victim)
	return attacker ~= nil and victim ~= nil and attacker ~= victim and attacker.Team ~= nil and attacker.Team == victim.Team
		and not (ctx and ctx.FriendlyFire) -- Hardcore: teammates can hurt each other
end

function D.SyncArmor(plr)
	local s = ctx.State[plr]
	if not s then return end
	ctx.Remotes.ArmorSync:FireClient(plr, s.Armor, s.Plates)
	local char = plr.Character
	if char then char:SetAttribute("Plates", math.ceil(s.Armor / Config.Armor.PlateArmor)) end
end

local function onKill(attacker)
	local s = ctx.State[attacker]
	local char = attacker.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not s or not hum or hum.Health <= 0 then return end
	if Config.Has(s.Perks, "QuickFix") then
		hum.Health = math.min(hum.MaxHealth, hum.Health + PV.QuickFixKillHeal)
		s.LastDamage = -1000 -- regen starts instantly
	end
	if Config.Has(s.Perks, "Scavenger") then
		local inv = s.Weapon and s.Inv[s.Weapon]
		local cfg = s.Weapon and (s.Cfgs[s.Weapon] or Config.Weapons[s.Weapon])
		if inv and cfg and cfg.MagSize > 0 then
			inv.Reserve += math.max(1, math.floor(cfg.MagSize * PV.ScavengeMag))
			ctx.SyncAmmo(attacker)
		end
		for _, slot in { s.Lethal, s.Tactical } do
			local def = Config.Equipment[slot.Name]
			if def and slot.Count < def.Count then slot.Count += 1 end
		end
		ctx.SyncEquip(attacker)
	end
end

-- ---------------------------------------------------------------- downed state
function D.IsDown(plr)
	local s = ctx.State[plr]
	return s ~= nil and s.Down ~= nil
end

local function charOf(plr)
	local char = plr.Character
	return char, char and char:FindFirstChildOfClass("Humanoid")
end

-- real death (finish, bleed-out, or a normal lethal hit on something that cannot be downed)
local function finalKill(victim, hum, attacker, kind, info)
	local s = victim and ctx.State[victim]
	if s then s.Down = nil end
	if victim and victim.Character then victim.Character:SetAttribute("Down", nil) end
	hum.Health = 0
	if attacker and attacker ~= victim then
		onKill(attacker)
		info = info or {}
		info.Kind = kind
		ctx.Score.OnKill(attacker, victim, info)
	end
end

local function enterDown(victim, hum, attacker)
	local s = ctx.State[victim]
	local Dn = Config.Down
	s.Down = { Health = Dn.Health, Drain = Dn.Health / Dn.BleedTime, By = attacker }
	s.Armor, s.Plating, s.Cook, s.Interact = 0, nil, nil, nil
	hum.Health = math.max(1, hum.MaxHealth * 0.15)
	if victim.Character then victim.Character:SetAttribute("Down", true) end
	D.SyncArmor(victim)
	ctx.Remotes.DownSync:FireClient(victim, true, s.Down.Health, s.Down.Drain)
	if attacker and attacker ~= victim then ctx.Score.OnKnockDown(attacker, victim) end
end

function D.Revive(target, by)
	local s = ctx.State[target]
	local char, hum = charOf(target)
	if not s or not s.Down or not hum or hum.Health <= 0 then return end
	s.Down = nil
	s.LastDamage = os.clock()
	if char then char:SetAttribute("Down", nil) end
	hum.Health = math.min(hum.MaxHealth, Config.Down.ReviveHealth)
	ctx.Remotes.DownSync:FireClient(target, false, 0, 0)
	if by then ctx.Score.Award(by, "Revive") end
end

function D.Finish(target, by)
	local s = ctx.State[target]
	local _, hum = charOf(target)
	if not s or not s.Down or not hum then return end
	finalKill(target, hum, by, "Finisher", {})
	ctx.Score.Award(by, "Finisher")
end

function D.StartInteract(plr, target)
	local s = ctx.State[plr]
	if not s or not s.Ready or s.Down or s.Interact or typeof(target) ~= "Instance" or not target:IsA("Player") then return end
	local ts = ctx.State[target]
	if not ts or not ts.Down or target == plr then return end
	local a, b = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart"), target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not a or not b or (a.Position - b.Position).Magnitude > Config.Down.InteractRange + 2 then return end
	local ally = plr.Team ~= nil and plr.Team == target.Team
	if ally then
		s.Interact = { Target = target, Kind = "Revive", Start = os.clock(), Dur = Config.Down.ReviveTime }
	elseif Config.Down.AllowFinish then
		s.Interact = { Target = target, Kind = "Finish", Start = os.clock(), Dur = Config.Down.FinishTime }
	end
end

function D.CancelInteract(plr)
	local s = ctx.State[plr]
	if s then s.Interact = nil end
end

-- kind: Bullet | Melee | Explosive | Fire | Gas | Finisher. Returns true if the hit killed.
-- info (optional): { Head, Dist, Shot, Backstab } is forwarded to scoring on a kill
function D.Apply(hum, dmg, attacker, kind, fromPos, info)
	if not hum or hum.Health <= 0 or dmg <= 0 then return false end
	if ctx.MatchFrozen then return false end -- results screen / round intermission: nobody can be hurt
	local victim = Players:GetPlayerFromCharacter(hum.Parent)
	if victim and attacker ~= victim and D.IsFriendly(attacker, victim) then return false end
	local raw = dmg
	local s = victim and ctx.State[victim]
	local scoring = attacker ~= nil and attacker ~= victim

	if s and s.Down then -- already down: hits drain the downed health, running out = death
		s.Down.Health -= dmg
		ctx.Remotes.DamageFX:FireClient(victim, fromPos or Vector3.zero, raw, kind)
		if scoring then ctx.Score.OnDamage(attacker, victim, dmg) end
		if s.Down.Health <= 0 then
			finalKill(victim, hum, attacker, kind, info)
			return true
		end
		ctx.Remotes.DownSync:FireClient(victim, true, s.Down.Health, s.Down.Drain)
		return false
	end

	local applied, armorBefore = 0, 0
	if s then
		armorBefore = s.Armor
		if kind == "Explosive" and Config.Has(s.Perks, "FlakJacket") then dmg *= PV.Flak end
		if kind == "Gas" and Config.Has(s.Perks, "BattleHardened") then dmg *= 0.5 end
		local pierce = info and info.ArmorPierce or 0 -- armor piercing ammo: this fraction of the hit skips the plates
		local toArmor = dmg * (Config.Armor.Absorb[kind] or 1) * (1 - pierce)
		local toHealth = dmg - toArmor
		if s.Armor > 0 and toArmor > 0 then
			local taken = math.min(s.Armor, toArmor)
			s.Armor -= taken
			if Config.Armor.Overflow then toHealth += toArmor - taken end
		else
			toHealth += toArmor
		end
		dmg = toHealth
		applied = (armorBefore - s.Armor) + math.min(dmg, hum.Health)
		s.LastDamage, s.LastAttacker = os.clock(), attacker
		D.SyncArmor(victim)
		ctx.Remotes.DamageFX:FireClient(victim, fromPos or Vector3.zero, raw, kind)
		if scoring then
			ctx.Score.OnDamage(attacker, victim, applied)
			if armorBefore > 0 and s.Armor <= 0 then ctx.Score.OnArmorBreak(attacker, victim) end
		end
		if Config.Down.Enabled and scoring and hum.Health - dmg <= 0 then -- lethal hit: go down instead of dying
			enterDown(victim, hum, attacker)
			return false
		end
	end
	if dmg > 0 then hum:TakeDamage(dmg) end
	if hum.Health <= 0 then
		if scoring then
			onKill(attacker)
			info = info or {}
			info.Kind = kind
			ctx.Score.OnKill(attacker, victim, info)
		end
		return true
	end
	return false
end

-- Incendiary ammo: sets a humanoid on fire (cfg.Burn = { Dps, Time }). A new hit refreshes the burn instead of stacking another one.
-- Ticks are "Fire" damage (armor soaks half of it, like thermite) credited to the shooter.
local burning = {} -- [humanoid] = { Until, Dps, By, From }
function D.Burn(hum, attacker, burn, fromPos)
	if not burn or not hum or hum.Health <= 0 then return end
	local victim = Players:GetPlayerFromCharacter(hum.Parent)
	if victim and attacker ~= victim and D.IsFriendly(attacker, victim) then return end
	local now = os.clock()
	local b = burning[hum]
	if b then
		b.Until, b.Dps, b.By = math.max(b.Until, now + burn.Time), math.max(b.Dps, burn.Dps), attacker
		return
	end
	b = { Until = now + burn.Time, Dps = burn.Dps, By = attacker, From = fromPos }
	burning[hum] = b
	task.spawn(function()
		while hum.Parent and hum.Health > 0 and os.clock() < b.Until do
			task.wait(0.5)
			if not (hum.Parent and hum.Health > 0) then break end
			if b.By and not b.By.Parent then b.By = nil end -- shooter left: still burns, nobody scores it
			D.Apply(hum, b.Dps * 0.5, b.By, "Fire", b.From)
		end
		burning[hum] = nil
	end)
end

-- per-frame: health regen, bleed-out and revive / finish progress
function D.Regen(dt)
	local now = os.clock()
	for plr, s in ctx.State do
		local char, hum = charOf(plr)
		if hum and hum.Health > 0 then
			if s.Down then
				s.Down.Health -= s.Down.Drain * dt
				if s.Down.Health <= 0 then finalKill(plr, hum, s.Down.By, "Bleed", {}) end
			elseif hum.Health < hum.MaxHealth then
				local qf = Config.Has(s.Perks, "QuickFix")
				local delay = qf and PV.QuickFixDelay or Config.Health.RegenDelay
				if now - s.LastDamage > delay then
					hum.Health = math.min(hum.MaxHealth, hum.Health + Config.Health.RegenRate * (qf and PV.QuickFixRegen or 1) * dt)
				end
			end
		end
		local it = s.Interact
		if it then
			local ts = ctx.State[it.Target]
			local a = char and char:FindFirstChild("HumanoidRootPart")
			local b = it.Target.Character and it.Target.Character:FindFirstChild("HumanoidRootPart")
			if s.Down or not hum or hum.Health <= 0 or not ts or not ts.Down or not a or not b
				or (a.Position - b.Position).Magnitude > Config.Down.InteractRange + 3 or s.LastDamage > it.Start then
				s.Interact = nil
			elseif now - it.Start >= it.Dur * 0.95 then
				s.Interact = nil
				if it.Kind == "Revive" then D.Revive(it.Target, plr) else D.Finish(it.Target, plr) end
			end
		end
	end
end

return D
