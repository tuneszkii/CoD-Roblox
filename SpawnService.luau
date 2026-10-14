-- SpawnService: where a player appears. Every candidate spawn point is scored and checked, unsafe ones are skipped.
--   Safety (a spawn is UNSAFE, and only used when nothing else is safe):
--     * an enemy closer than MinEnemyDistance (CamperDistance around a player who has been spawn killing)
--     * an enemy within LosHardDistance that has a clear line of sight to it (raycast from his eyes to the spawn, walls block it)
--     * somebody standing on it, solid geometry where the body would be, no ground below, or a spawn somebody used a moment ago
--   Score (higher is better): distance to the nearest enemy, a bonus for being about AllyIdeal studs from a teammate (team modes),
--     minus: enemies that can see it (more if they face it), recent deaths nearby, recent enemy gunfire nearby, recently used spawns.
--   Spawn trapping prevention: dying soon after spawning marks that spawn as a trap (a long-lived hot spot), a player who gets CamperKills
--     spawn kills quickly is flagged as a camper (bigger no-go radius around him), and a team that keeps getting spawn killed (FlipAfter)
--     may spawn anywhere on the map, enemy side included, as long as it is safe.
--   Safe respawns: MatchService re-checks the spawn after the character has loaded (the world moves), waits up to MaxWait for a safe spawn
--     when there is none, and gives double spawn protection if it has to spawn anyway. Spawn protection ends when you fire.
-- Pick(plr, info) -> CFrame, unsafe.  info = { Team, Enemies, Allies, Primary, Fallback }; Enemies / Allies = { { Player, Pos, Look }, ... },
-- Primary / Fallback = lists of spawn CFrames (see MapService.SpawnLists). Tuning: Modes.Config.Spawn.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Modes = require(RS:WaitForChild("FPS"):WaitForChild("Modes"))
local CFG = Modes.Config.Spawn

local S = {}

local recentUse = {}   -- { Pos, T, Player }
local events = {}      -- hot spots: { Pos, T, W, Life, Team }
local fires = {}       -- recent gunfire: { Pos, T, Team, Shooter }
local lastFire = {}    -- [shooter] = os.clock()
local lastSpawn = {}   -- [player] = { Pos, T }
local spawnKills = {}  -- [killer] = { os.clock() of each spawn kill }
local camperUntil = {} -- [player] = os.clock() until which he counts as a spawn camper
local trapHits = {}    -- [teamName or ""] = { os.clock() of each spawn kill against that team }

local function teamKey(t) return t or "" end

local function rayParams()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.IgnoreWater = true
	rp.RespectCanCollide = true -- decorations you can walk through never block a view
	local ex = {}
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ex, p.Character) end
	end
	rp.FilterDescendantsInstances = ex
	return rp
end

local function clearView(from, to, rp)
	return workspace:Raycast(from, to - from, rp) == nil
end

-- the spawn point's real position: on the ground below it, with room for a body. nil = unusable
local function resolve(base, rp)
	local hit = workspace:Raycast(base.Position + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), rp)
	if not hit then return nil end
	local pos = hit.Position + Vector3.new(0, CFG.Height, 0)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = rp.FilterDescendantsInstances
	op.RespectCanCollide = true
	if #workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(3, 5, 3), op) > 0 then return nil end
	return CFrame.new(pos) * base.Rotation
end

local function trapCount(team, now)
	local list = trapHits[teamKey(team)]
	if not list then return 0 end
	for i = #list, 1, -1 do
		if now - list[i] > CFG.TrapWindow then table.remove(list, i) end
	end
	return #list
end

-- score + whether the spawn is unsafe
local function evaluate(cf, info, rp, now)
	local pos = cf.Position
	local eye = pos + Vector3.new(0, 1.5, 0)
	local score, hard = 0, false
	local nearest = math.huge

	for _, e in info.Enemies do
		local off = e.Pos - pos
		local d = off.Magnitude
		nearest = math.min(nearest, d)
		local camper = (camperUntil[e.Player] or 0) > now
		if d < (camper and CFG.CamperDistance or CFG.MinEnemyDistance) then hard = true end
		if d <= CFG.LosRange then
			local from = e.Pos + Vector3.new(0, 1.5, 0)
			if clearView(from, eye, rp) or clearView(from, pos, rp) then
				if d < CFG.LosHardDistance then hard = true end
				local w = CFG.LosPenalty * (1 - d / CFG.LosRange)
				local flat = Vector3.new(-off.X, 0, -off.Z)
				if e.Look and flat.Magnitude > 0.1 and e.Look:Dot(flat.Unit) > CFG.FacingDot then w *= 1.6 end -- he is looking right at it
				score -= w
			end
		end
	end
	score += CFG.DistWeight * math.min(nearest, CFG.IdealEnemyDistance) / CFG.IdealEnemyDistance

	if #info.Allies > 0 then
		local a = math.huge
		for _, al in info.Allies do a = math.min(a, (al.Pos - pos).Magnitude) end
		score += CFG.AllyBonus * math.clamp(1 - math.abs(a - CFG.AllyIdeal) / CFG.AllyIdeal, 0, 1)
	end
	for _, list in { info.Enemies, info.Allies } do -- somebody standing on it
		for _, o in list do
			if (o.Pos - pos).Magnitude < CFG.OccupiedRadius then hard = true end
		end
	end

	for _, ev in events do -- recent deaths / spawn kills near it
		local age = now - ev.T
		if age < ev.Life then
			local d = (ev.Pos - pos).Magnitude
			if d < CFG.HeatRadius then
				local w = ev.W * (1 - d / CFG.HeatRadius) * (1 - age / ev.Life)
				score -= ev.Team == info.Team and w or w * 0.4
			end
		end
	end
	for _, f in fires do -- recent enemy gunfire near it
		local age = now - f.T
		if age < CFG.FireLife and f.Shooter ~= info.Player and not (info.Team ~= nil and f.Team == info.Team) then
			local d = (f.Pos - pos).Magnitude
			if d < CFG.FireRadius then score -= CFG.FirePenalty * (1 - d / CFG.FireRadius) * (1 - age / CFG.FireLife) end
		end
	end
	for _, u in recentUse do -- spawns used a moment ago (also spreads a whole team that spawns at once)
		local age = now - u.T
		if u.Player ~= info.Player and age < CFG.ReuseTime then
			local d = (u.Pos - pos).Magnitude
			if d < CFG.ReuseRadius then
				score -= CFG.ReusePenalty * (1 - age / CFG.ReuseTime)
				if d < CFG.OccupiedRadius and age < 2 then hard = true end
			end
		end
	end
	return score + math.random() * CFG.Noise, hard
end

-- best usable candidate of a list: returns safeCF, safeScore, anyCF, anyScore
local function bestOf(list, info, rp, now)
	local safeCF, safeScore, anyCF, anyScore
	for _, base in list do
		local cf = resolve(base, rp)
		if cf then
			local score, hard = evaluate(cf, info, rp, now)
			if not hard and (not safeScore or score > safeScore) then safeCF, safeScore = cf, score end
			if not anyScore or score > anyScore then anyCF, anyScore = cf, score end
		end
	end
	return safeCF, safeScore, anyCF, anyScore
end

function S.Pick(plr, info)
	local now = os.clock()
	local rp = rayParams()
	info.Player = plr
	local primary, fallback = info.Primary or {}, info.Fallback or {}

	local lists
	if trapCount(info.Team, now) >= CFG.FlipAfter then -- the team keeps getting spawn killed: any safe spot on the map will do
		local all = table.clone(primary)
		for _, cf in fallback do table.insert(all, cf) end
		lists = { all }
	else
		lists = { primary, fallback }
	end

	local bestAny, bestAnyScore
	for _, list in lists do
		local safeCF, _, anyCF, anyScore = bestOf(list, info, rp, now)
		if safeCF then return safeCF, false end
		if anyCF and (not bestAnyScore or anyScore > bestAnyScore) then bestAny, bestAnyScore = anyCF, anyScore end
	end
	if bestAny then return bestAny, true end
	local base = primary[1] or fallback[1] or CFrame.new(0, 5, 0) -- nothing usable (no ground?): the spawn part itself
	return base + Vector3.new(0, CFG.Height, 0), true
end

-- is a spawn we picked earlier still safe? (after the character loaded: the situation may have changed)
function S.StillSafe(plr, cf, enemies, allies)
	local _, hard = evaluate(cf, { Player = plr, Enemies = enemies, Allies = allies or {} }, rayParams(), os.clock())
	return not hard
end

-- remember the spawn so the next one is spread out from it (also what a spawn kill is measured against)
function S.Mark(plr, cf)
	local now = os.clock()
	for i = #recentUse, 1, -1 do
		if now - recentUse[i].T > CFG.ReuseTime then table.remove(recentUse, i) end
	end
	table.insert(recentUse, { Pos = cf.Position, T = now, Player = plr })
	lastSpawn[plr] = { Pos = cf.Position, T = now }
end

function S.NoteFire(shooter, pos, teamName)
	local now = os.clock()
	if now - (lastFire[shooter] or -10) < 0.35 then return end
	lastFire[shooter] = now
	table.insert(fires, { Pos = pos, T = now, Team = teamName, Shooter = shooter })
	while #fires > 60 do table.remove(fires, 1) end
end

-- victim died at pos on team teamName; killer may be nil
function S.NoteDeath(victim, killer, pos, teamName)
	local now = os.clock()
	for i = #events, 1, -1 do
		if now - events[i].T > events[i].Life then table.remove(events, i) end
	end
	table.insert(events, { Pos = pos, T = now, W = CFG.DeathHeat, Life = CFG.DeathLife, Team = teamName })
	local ls = lastSpawn[victim]
	if ls and now - ls.T <= CFG.SpawnKillWindow then -- a spawn kill: that spawn is a trap
		table.insert(events, { Pos = ls.Pos, T = now, W = CFG.SpawnKillHeat, Life = CFG.SpawnKillLife, Team = teamName })
		local hits = trapHits[teamKey(teamName)] or {}
		trapHits[teamKey(teamName)] = hits
		table.insert(hits, now)
		if killer and killer ~= victim and killer.Parent then
			local list = spawnKills[killer] or {}
			spawnKills[killer] = list
			table.insert(list, now)
			for i = #list, 1, -1 do
				if now - list[i] > CFG.CamperWindow then table.remove(list, i) end
			end
			if #list >= CFG.CamperKills then camperUntil[killer] = now + CFG.CamperLife end
		end
		lastSpawn[victim] = nil
	end
end

-- a new match: forget everything
function S.Reset()
	recentUse, events, fires, lastFire, lastSpawn, spawnKills, camperUntil, trapHits = {}, {}, {}, {}, {}, {}, {}, {}
end

Players.PlayerRemoving:Connect(function(plr)
	lastFire[plr], lastSpawn[plr], spawnKills[plr], camperUntil[plr] = nil, nil, nil, nil
end)

return S
