-- Kills, assists, multi-kills, collaterals, knock downs, streaks and the XP they award.
-- DamageService / EquipmentService report events here; Config.Scoring holds the values.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("FPS"):WaitForChild("Config"))
local SC = Config.Scoring

local S = {}
local ctx
local damageLog = {}      -- [victim] = { [attacker] = { Dmg, Time } }
local chains = {}         -- [player] = { Count, Last }
local streaks = {}        -- [player] = kills since last death
local lastKiller = {}     -- [victim] = last player who killed them (for Revenge)
local lastShot = {}       -- [attacker] = { Id, Kills }  (Collateral)
local firstBlood = false
local shotCounter = 0

local MULTI = { "DoubleKill", "TripleKill", "QuadKill", "PentaKill" }

-- unique id for one trigger pull / one explosion (used to detect Collateral)
function S.NewShotId(plr)
	shotCounter += 1
	return ("%d:%d"):format(plr.UserId, shotCounter)
end

function S.Award(plr, tag)
	local def = SC.Tags[tag]
	if not def or not plr or not plr.Parent then return end
	local level = ctx.Data.AddXP(plr, def.XP)
	ctx.Data.AddMedal(plr, tag)
	if ctx.Achievements then ctx.Achievements.Add(plr, "Tag:" .. tag, 1) end
	ctx.Remotes.ScoreEvent:FireClient(plr, tag, def.XP, level)
end

function S.OnDamage(attacker, victim, amount)
	if not attacker or not victim or attacker == victim or amount <= 0 then return end
	local log = damageLog[victim]
	if not log then
		log = {}
		damageLog[victim] = log
	end
	local rec = log[attacker]
	local now = os.clock()
	if not rec or now - rec.Time > SC.AssistWindow then
		rec = { Dmg = 0, Time = now }
		log[attacker] = rec
	end
	rec.Dmg += amount
	rec.Time = now
end

function S.OnArmorBreak(attacker, victim)
	if attacker and victim and attacker ~= victim then S.Award(attacker, "ArmorBreak") end
end

function S.OnKnockDown(attacker, victim)
	if attacker and victim and attacker ~= victim then S.Award(attacker, "KnockDown") end
end

-- counts as a kill for stats, the multi-kill chain and the streak
local function registerKill(plr)
	ctx.Data.AddStat(plr, "Kills", 1)
	local now = os.clock()
	local c = chains[plr]
	if not c or now - c.Last > SC.MultiWindow then c = { Count = 0, Last = now } end
	c.Count += 1
	c.Last = now
	chains[plr] = c
	if c.Count >= 2 then S.Award(plr, MULTI[math.min(c.Count - 1, #MULTI)]) end

	local n = (streaks[plr] or 0) + 1
	streaks[plr] = n
	ctx.Data.SetMax(plr, "BestStreak", n)
	if ctx.Achievements then ctx.Achievements.Max(plr, "BestStreak", n) end
	if S.OnStreak then S.OnStreak(plr, n) end -- StreakService: earn kill streak rewards
	if n == 3 then S.Award(plr, "Streak3")
	elseif n == 5 then S.Award(plr, "Streak5")
	elseif n == 10 then S.Award(plr, "Streak10") end
end

-- victim: Player or nil (dummy). info: { Head, Dist, Shot, Backstab, Wallbang, Kind }
function S.OnKill(attacker, victim, info)
	info = info or {}
	local now = os.clock()

	if victim then -- assists first so they show up before the killer's tags
		local log = damageLog[victim]
		if log then
			local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
			local maxHp = hum and hum.MaxHealth or Config.Health.Max
			for other, rec in log do
				if other ~= attacker and other.Parent and now - rec.Time <= SC.AssistWindow then
					local frac = rec.Dmg / maxHp
					if frac >= SC.AssistKillThreshold and SC.AssistKillCountsAsKill then
						S.Award(other, "AssistKill")
						registerKill(other)
					elseif frac >= SC.AssistThreshold then
						S.Award(other, "Assist")
						ctx.Data.AddStat(other, "Assists", 1)
					end
				end
			end
			damageLog[victim] = nil
		end
	end

	S.Award(attacker, "Kill")
	registerKill(attacker)
	if S.OnWeaponKill then S.OnWeaponKill(attacker, info) end -- ArmoryService: weapon XP -> attachment unlocks
	if victim and S.OnMatchKill then S.OnMatchKill(attacker, victim, info) end -- MatchService: team / FFA score

	if info.Head then
		ctx.Data.AddStat(attacker, "Headshots", 1)
		S.Award(attacker, "Headshot")
	end
	if info.Kind == "Bullet" and info.Dist then
		if info.Dist >= SC.LongshotDistance then S.Award(attacker, "Longshot")
		elseif info.Dist <= SC.PointBlankDistance then S.Award(attacker, "PointBlank") end
	end
	if info.Backstab then S.Award(attacker, "Backstab") end
	if info.Wallbang then S.Award(attacker, "Wallbang") end -- the killing bullet went through a wall first
	if victim and not firstBlood then
		firstBlood = true
		S.Award(attacker, "FirstBlood")
	end
	if victim and lastKiller[attacker] == victim then
		lastKiller[attacker] = nil
		S.Award(attacker, "Revenge")
	end
	if victim then lastKiller[victim] = attacker end

	if info.Shot then -- two kills from one shot / one explosion
		local ls = lastShot[attacker]
		if ls and ls.Id == info.Shot then
			ls.Kills += 1
			if ls.Kills == 2 then S.Award(attacker, "Collateral") end
		else
			lastShot[attacker] = { Id = info.Shot, Kills = 1 }
		end
	end
end

function S.OnDeath(plr)
	streaks[plr], chains[plr], damageLog[plr] = 0, nil, nil
	if S.OnStreakReset then S.OnStreakReset(plr) end
	ctx.Data.AddStat(plr, "Deaths", 1)
end

function S.Init(c)
	ctx = c
	Players.PlayerRemoving:Connect(function(plr)
		damageLog[plr], chains[plr], streaks[plr], lastKiller[plr], lastShot[plr] = nil, nil, nil, nil, nil
		for _, log in damageLog do log[plr] = nil end
		for k, v in lastKiller do if v == plr then lastKiller[k] = nil end end
	end)
end

return S
