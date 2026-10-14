-- MatchService: the game loop.   Voting -> Match -> Results -> Voting ...
--   Voting : everyone picks a mode + a map (plurality wins, ties random). Players press DEPLOY ("ready"); the match starts when the timer ends
--            (sooner if everybody is ready).
--   Match  : players are put on teams (or free for all), spawn on the map, respawn after a delay (or fight elimination rounds in Down and Out).
--            Late joiners can DEPLOY at any time.
--   Results: scoreboard for a few seconds, characters are removed, map unloaded.
-- Public state is replicated as attributes on ReplicatedStorage.FPS.MatchState (+ Deployed / Ready / MatchKills on each Player).
-- Presentation (all client side, driven by MatchEvent):
--   "Intro" (info)    once per player when they deploy: mode / map / team / objective card, flyover data, countdown timing
--   "Go"              the countdown ended, the match is live
--   "Death" (info)    sent to the victim: killer, weapon, distance, respawn delay (false = no respawn this mode)
--   "Spawned" (secs)  the player was placed on the map; secs = spawn protection
--   "Results" (data)  match over (data.Reason = ScoreLimit | TimeLimit | Rounds | Empty)
--   "Message" (text, tone)  announcement; tone = Good | Bad | Warn | nil
--   "TagFX" (pos, outcome, team)  Kill Confirmed pickup / expiry
-- Objective modes (Modes.List[i].Objective) hand their scoring to ObjectiveService.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Debris = game:GetService("Debris")
local FPS = RS:WaitForChild("FPS")
local Config = require(FPS:WaitForChild("Config"))
local Modes = require(FPS:WaitForChild("Modes"))
local Maps = require(script.Parent:WaitForChild("MapService"))
local Objectives = require(script.Parent:WaitForChild("ObjectiveService"))
local Spawns = require(script.Parent:WaitForChild("SpawnService"))
local MC = Modes.Config

local M = {}
local ctx, Remotes, folder
local phase = "Voting"
local modeDef, mapDef
local candidates = {}                       -- map ids offered this vote
local votes = { Map = {}, Mode = {} }       -- [plr] = id
local ready, deployed, team, stats = {}, {}, {}, {}
local spawning, spawnTime = {}, {}
local teamScore = { Alpha = 0, Bravo = 0 }
local roundWins = { Alpha = 0, Bravo = 0 }
local roundActive = false
local endRequest                            -- set by kill hooks when a score limit is reached: { Winner = ... }
local teamInstances = {}
local introActive, introStart, introEnd = false, 0, 0   -- match start: everybody is frozen while the title card and countdown play
local anchored = {}                             -- [plr] = HumanoidRootPart anchored for the countdown / results
local deathInfo = {}                            -- [victim] = { Killer, Kind, Head, Dist, Weapon }, filled by OnKill, read when the humanoid dies
local warned = { Alpha = false, Bravo = false } -- "nearing victory" announcement already made

local defaults = {
	Health = Config.Health.Max, StartArmor = Config.Armor.StartArmor, StartCarried = Config.Armor.StartCarried, Down = Config.Down.Enabled,
}

local function now() return workspace:GetServerTimeNow() end
local function set(k, v) folder:SetAttribute(k, v) end
local function message(text, plr, tone)
	if plr then Remotes.MatchEvent:FireClient(plr, "Message", text, tone) else Remotes.MatchEvent:FireAllClients("Message", text, tone) end
end

local function alive(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function count(t)
	local n = 0
	for _ in t do n += 1 end
	return n
end

-- text for one team (forTeam) and / or everybody else (forOthers). Tones: Good (default for the team), Bad (default for the others), Warn
local function teamMessage(teamName, forTeam, forOthers, toneTeam, toneOthers)
	for plr in deployed do
		if plr.Parent then
			if team[plr] == teamName then
				if forTeam then message(forTeam, plr, toneTeam or "Good") end
			elseif forOthers then
				message(forOthers, plr, toneOthers or "Bad")
			end
		end
	end
end

-- ---------------------------------------------------------------- config per mode
local function applyMode(def)
	Config.Health.Max = def.Health or defaults.Health
	Config.Armor.StartArmor = def.StartArmor or defaults.StartArmor
	Config.Armor.StartCarried = def.StartPlates or defaults.StartCarried
	Config.Down.Enabled = def.Down == true
	ctx.FriendlyFire = def.FriendlyFire == true
end

local function restoreConfig()
	Config.Health.Max, Config.Armor.StartArmor, Config.Armor.StartCarried = defaults.Health, defaults.StartArmor, defaults.StartCarried
	Config.Down.Enabled = defaults.Down
	ctx.FriendlyFire = false
end

-- ---------------------------------------------------------------- voting
local function recount()
	for k in folder:GetAttributes() do
		if k:sub(1, 4) == "Vote" then folder:SetAttribute(k, nil) end
	end
	for _, def in Modes.List do
		if def.Enabled then set("VoteMode_" .. def.Id, 0) end
	end
	for _, id in candidates do set("VoteMap_" .. id, 0) end
	for kind, byPlayer in votes do
		for plr, id in byPlayer do
			if plr.Parent then
				local key = "Vote" .. kind .. "_" .. id
				set(key, (folder:GetAttribute(key) or 0) + 1)
			end
		end
	end
end

local function winner(kind, options)
	local tally, best, top = {}, {}, -1
	for plr, id in votes[kind] do
		if plr.Parent then tally[id] = (tally[id] or 0) + 1 end
	end
	for _, id in options do
		local n = tally[id] or 0
		if n > top then best, top = { id }, n
		elseif n == top then table.insert(best, id) end
	end
	return best[math.random(1, #best)]
end

local function enabledModeIds()
	local ids = {}
	for _, def in Modes.List do
		if def.Enabled then table.insert(ids, def.Id) end
	end
	return ids
end

local function setReady(plr, on)
	ready[plr] = on or nil
	plr:SetAttribute("Ready", on or false)
end

-- ---------------------------------------------------------------- teams + spawning
local function ensureTeams()
	local colors = { Alpha = BrickColor.new("Bright blue"), Bravo = BrickColor.new("Bright orange") }
	for _, name in MC.TeamNames do
		local tm = Teams:FindFirstChild(name) or Instance.new("Team")
		tm.Name, tm.TeamColor, tm.AutoAssignable = name, colors[name], false
		tm.Parent = Teams
		teamInstances[name] = tm
	end
end

local function pickTeam()
	local a, b = 0, 0
	for plr, t in team do
		if deployed[plr] then
			if t == "Alpha" then a += 1 else b += 1 end
		end
	end
	return a <= b and "Alpha" or "Bravo"
end

-- everybody else who is alive and deployed, split into enemies / allies: { { Player, Pos, Look }, ... } (SpawnService reads these)
local function snapshot(plr)
	local enemies, allies = {}, {}
	for other in deployed do
		if other ~= plr and alive(other) then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local l = root.CFrame.LookVector
				local entry = { Player = other, Pos = root.Position, Look = Vector3.new(l.X, 0, l.Z) }
				if modeDef.Teams and team[other] == team[plr] then table.insert(allies, entry) else table.insert(enemies, entry) end
			end
		end
	end
	return enemies, allies
end

-- what killed the player, as a short key the client prettifies ("M4A1", "CombatKnife", "Explosive", "Finisher", "Bleed" ...)
local function weaponLabel(attacker, info)
	local kind = info and info.Kind or ""
	local s = ctx.State[attacker]
	if kind == "Bullet" then return s and s.Weapon or "" end
	if kind == "Melee" then
		local w = s and s.Weapon and Config.Weapons[s.Weapon]
		return (w and w.Class == "Melee") and s.Weapon or "Melee"
	end
	if kind == "Explosive" then return "Explosive" end
	return kind -- Fire / Gas / Finisher / Bleed
end

local function sendDeath(plr, info, delay)
	local payload = { Delay = delay or false, Kind = info and info.Kind or "" }
	local killer = info and info.Killer
	if killer and killer ~= plr and killer.Parent then
		payload.KillerId, payload.KillerName = killer.UserId, killer.DisplayName
		payload.KillerTeam = team[killer]
		payload.Weapon = info.Weapon
		payload.Dist = info.Dist and math.floor(info.Dist + 0.5) or nil
		payload.Head = info.Head == true
	end
	Remotes.MatchEvent:FireClient(plr, "Death", payload)
end

local function onDeath(plr)
	local s = stats[plr]
	if s then
		s.D += 1
		plr:SetAttribute("MatchDeaths", s.D) -- scoreboard
	end
	if phase ~= "Match" or not modeDef then return end
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	local pos = root and root.Position
	local tname = team[plr]
	local delay = modeDef.Respawn
	task.defer(function() -- the kill scoring runs right after the damage that caused the death; let it fill deathInfo first
		local info = deathInfo[plr]
		deathInfo[plr] = nil
		if phase ~= "Match" or not plr.Parent then return end
		if pos then Spawns.NoteDeath(plr, info and info.Killer, pos, tname) end -- hot spots, spawn kills, campers
		if modeDef.Objective and pos then Objectives.OnDeath(plr, team[plr], pos) end
		sendDeath(plr, info, delay)
	end)
	if not delay then return end
	task.delay(delay, function()
		if phase == "Match" and deployed[plr] and plr.Parent and not alive(plr) then M.Spawn(plr) end
	end)
end

function M.Spawn(plr)
	if phase ~= "Match" or not deployed[plr] or not plr.Parent or spawning[plr] then return end
	spawning[plr] = true
	local tname = team[plr]
	plr.Team = tname and teamInstances[tname] or nil
	if not tname then plr.Neutral = true end
	local primary, fallback = Maps.SpawnLists(tname)
	local function pick()
		local enemies, allies = snapshot(plr)
		local cf, unsafe = Spawns.Pick(plr, { Team = tname, Enemies = enemies, Allies = allies, Primary = primary, Fallback = fallback })
		Spawns.Mark(plr, cf) -- reserved right away so players spawning together are spread out
		return cf, unsafe
	end
	local spawnCF, unsafe = pick()
	local waited = 0
	while unsafe and waited < MC.Spawn.MaxWait and not introActive and not modeDef.Rounds and phase == "Match" and plr.Parent do
		task.wait(0.5) -- no safe spawn right now: give the situation a moment to change
		waited += 0.5
		spawnCF, unsafe = pick()
	end
	if phase ~= "Match" or not plr.Parent then
		spawning[plr] = nil
		return
	end
	plr:LoadCharacter()
	spawning[plr] = nil
	local char = plr.Character
	if not char or phase ~= "Match" then return end
	local hum, root = char:WaitForChild("Humanoid", 5), char:WaitForChild("HumanoidRootPart", 5)
	if not hum or not root then return end
	if not introActive then -- safe respawn: the world moved while the character loaded, so look again before placing it
		local enemies, allies = snapshot(plr)
		if not Spawns.StillSafe(plr, spawnCF, enemies, allies) then spawnCF, unsafe = pick() end
	end
	char:PivotTo(spawnCF)
	Spawns.Mark(plr, spawnCF) -- the real spawn time / place (a spawn kill is measured from here)
	local protection = MC.SpawnProtection * (unsafe and MC.Spawn.UnsafeProtectionMult or 1)
	local ff = Instance.new("ForceField")
	ff.Name, ff.Visible = "SpawnProtection", false
	ff.Parent = char
	Debris:AddItem(ff, protection)
	if introActive then -- the countdown holds everybody at their spawn point
		root.Anchored = true
		anchored[plr] = root
	end
	spawnTime[plr] = os.clock()
	plr:SetAttribute("Deployed", true)
	hum.Died:Once(function() onDeath(plr) end)
	Remotes.MatchEvent:FireClient(plr, "Spawned", protection)
end

-- firing / meleeing ends spawn protection, so it cannot be used to shoot while invulnerable
function M.BreakProtection(plr)
	if not MC.Spawn.BreakProtectionOnFire then return end
	local ff = plr.Character and plr.Character:FindFirstChild("SpawnProtection")
	if ff then
		ff:Destroy()
		Remotes.MatchEvent:FireClient(plr, "ProtectionEnd")
	end
end

-- the match start card (mode, map, team, objective) + data for the map flyover. late = joined a running match: short card, no flyover / countdown
local function sendIntro(plr, late)
	local info = Maps.Info()
	local focus = {}
	local obj = Maps.Objectives()
	if modeDef.Objective == "Domination" then
		for _, f in obj.Flags do table.insert(focus, f.Pos) end
	elseif modeDef.Objective == "Hardpoint" then
		for _, h in obj.Hills do table.insert(focus, h.Pos) end
	end
	Remotes.MatchEvent:FireClient(plr, "Intro", {
		ModeId = modeDef.Id, Mode = modeDef.Name, Map = mapDef.Name, MapDesc = mapDef.Desc,
		Brief = modeDef.Brief or modeDef.Desc or "", Team = team[plr], Objective = modeDef.Objective, Rounds = modeDef.Rounds == true,
		Late = late, IntroStart = introStart, IntroEnd = introEnd, Countdown = MC.CountdownTime, LateTime = MC.LateIntroTime,
		Center = info.Center, Size = info.Size, Focus = focus,
	})
end

-- late join / ready: put a player into the running match
local function deploy(plr)
	if phase ~= "Match" or deployed[plr] then return end
	deployed[plr] = true
	if not stats[plr] then ctx.Data.ResetTally(plr) end -- fresh match: the per-match accuracy tally starts at zero
	stats[plr] = stats[plr] or { K = 0, D = 0, O = 0 }
	plr:SetAttribute("MatchKills", stats[plr].K)
	plr:SetAttribute("MatchDeaths", stats[plr].D)
	plr:SetAttribute("MatchObj", stats[plr].O)
	plr:SetAttribute("Deployed", true)
	if modeDef.Teams then team[plr] = team[plr] or pickTeam() end
	sendIntro(plr, not introActive)
	if modeDef.Rounds then -- round modes spawn everybody together at the start of each round
		if roundActive then message("YOU SPAWN NEXT ROUND", plr) end
		return
	end
	task.spawn(M.Spawn, plr)
end

-- "Save + respawn" in the loadout menu: only right after spawning, never in round modes
function M.RequestRespawn(plr)
	if phase ~= "Match" or not deployed[plr] or modeDef.Rounds or not alive(plr) then return false end
	if os.clock() - (spawnTime[plr] or 0) > 10 then return false end
	task.spawn(M.Spawn, plr)
	return true
end

-- ---------------------------------------------------------------- scoring (called by ScoreService on every player kill)
local function finishScoreRace(winnerKey)
	if not endRequest then endRequest = { Winner = winnerKey } end
end

-- team points from kills (TDM) or from an objective (ObjectiveService)
local function addScore(t, n)
	if not t or not modeDef or phase ~= "Match" or introActive or endRequest or teamScore[t] == nil then return end
	teamScore[t] += n
	set("Score" .. t, teamScore[t])
	local limit = modeDef.ScoreLimit
	if not limit then return end
	if teamScore[t] >= limit then
		finishScoreRace(t)
	elseif not warned[t] and teamScore[t] >= limit * 0.9 then
		warned[t] = true
		teamMessage(t, "YOUR TEAM IS NEARING VICTORY", "THE ENEMY TEAM IS NEARING VICTORY", "Warn", "Warn")
	end
end

function M.OnKill(attacker, victim, info)
	if phase ~= "Match" or not modeDef or not attacker or not victim then return end
	if not deployed[attacker] or not deployed[victim] then return end
	deathInfo[victim] = { Killer = attacker, Kind = info and info.Kind, Head = info and info.Head, Dist = info and info.Dist, Weapon = weaponLabel(attacker, info) }
	local s = stats[attacker]
	if s then
		s.K += 1
		attacker:SetAttribute("MatchKills", s.K)
	end
	if modeDef.Rounds or modeDef.Objective then return end -- round modes are decided by elimination, objective modes score through ObjectiveService
	if modeDef.Teams then
		if team[attacker] == team[victim] then return end -- team kill: no point
		addScore(team[attacker], 1)
	else
		local lead, leadScore = nil, -1
		for plr, st in stats do
			if deployed[plr] and st.K > leadScore then lead, leadScore = plr, st.K end
		end
		set("LeaderName", lead and lead.DisplayName or "")
		set("LeaderScore", leadScore)
		if s and s.K >= modeDef.ScoreLimit then finishScoreRace(attacker) end
	end
end

-- ---------------------------------------------------------------- phases
local function clearAttributes(prefixes)
	for k in folder:GetAttributes() do
		for _, p in prefixes do
			if k:sub(1, #p) == p then folder:SetAttribute(k, nil) end
		end
	end
end

local function cleanupMatch()
	Objectives.Stop()
	ctx.MatchFrozen = false
	roundActive, introActive = false, false
	anchored, deathInfo = {}, {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then plr.Character:Destroy() end -- destroyed (not killed) so no deaths are counted
		plr.Team = nil
		plr.Neutral = true
		plr:SetAttribute("Deployed", false)
		plr:SetAttribute("MatchKills", 0)
		plr:SetAttribute("MatchDeaths", 0)
		plr:SetAttribute("MatchObj", 0)
		setReady(plr, false)
	end
	deployed, team, stats, spawning, spawnTime = {}, {}, {}, {}, {}
	Spawns.Reset()
	Maps.Unload()
	restoreConfig()
end

local function runVoting()
	phase = "Voting"
	modeDef, mapDef, endRequest = nil, nil, nil
	votes = { Map = {}, Mode = {} }
	for _, p in Players:GetPlayers() do setReady(p, false) end

	local pool = {}
	for _, m in Modes.Maps do table.insert(pool, m.Id) end
	candidates = {}
	while #candidates < math.min(MC.MapChoices, #pool) do
		table.insert(candidates, table.remove(pool, math.random(1, #pool)))
	end
	clearAttributes({ "Vote", "Score", "Round", "Alive", "Leader", "Maps", "Mode", "Map", "Intro", "Obj", "Flag", "Hill" })
	set("Maps", table.concat(candidates, ","))
	recount()

	local endAt = now() + MC.VoteTime
	set("Phase", "Voting")
	set("PhaseEnd", endAt)
	while true do
		task.wait(0.5)
		local players = Players:GetPlayers()
		local readyCount = 0
		for _, p in players do
			if ready[p] then readyCount += 1 end
		end
		if #players == 0 then
			endAt = now() + MC.VoteTime
			set("PhaseEnd", endAt)
		elseif readyCount == #players and endAt - now() > MC.StartEarly then
			endAt = now() + MC.StartEarly
			set("PhaseEnd", endAt)
		end
		if now() >= endAt then
			if readyCount > 0 then break end
			endAt = now() + 10 -- nobody wants in yet: keep the vote open
			set("PhaseEnd", endAt)
		end
	end

	local modeId, mapId = winner("Mode", enabledModeIds()), winner("Map", candidates)
	modeDef, mapDef = Modes.Get(modeId), Modes.GetMap(mapId)
end

local function aliveCounts()
	local a, b = 0, 0
	for plr in deployed do
		if alive(plr) then
			if team[plr] == "Alpha" then a += 1 elseif team[plr] == "Bravo" then b += 1 end
		end
	end
	return a, b
end

local function buildResults(winnerKey, reason)
	local list = {}
	for plr, st in stats do
		if plr.Parent then table.insert(list, { Name = plr.DisplayName, Team = team[plr], K = st.K, D = st.D, UserId = plr.UserId }) end
	end
	table.sort(list, function(x, y) return x.K > y.K end)
	local players = {}
	for i = 1, math.min(8, #list) do players[i] = list[i] end
	local label
	if typeof(winnerKey) == "Instance" then label = winnerKey.DisplayName else label = winnerKey or "Draw" end
	return {
		Mode = modeDef.Name, ModeId = modeDef.Id, Map = mapDef.Name, Teams = modeDef.Teams == true,
		Reason = reason, Winner = label, WinnerTeam = typeof(winnerKey) == "string" and winnerKey or nil,
		WinnerUserId = typeof(winnerKey) == "Instance" and winnerKey.UserId or nil,
		Score = { Alpha = modeDef.Rounds and roundWins.Alpha or teamScore.Alpha, Bravo = modeDef.Rounds and roundWins.Bravo or teamScore.Bravo },
		Players = players,
	}
end

-- one elimination round. Returns the winning team name or nil (draw)
local function playRound(round)
	ctx.MatchFrozen = false
	roundActive = false
	set("Round", round)
	message(("ROUND %d"):format(round))
	local pending = 0
	for plr in deployed do
		if plr.Parent then
			pending += 1
			task.spawn(function()
				M.Spawn(plr)
				pending -= 1
			end)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 10 do task.wait(0.1) end
	local participants = { Alpha = 0, Bravo = 0 }
	for plr in deployed do
		if alive(plr) then participants[team[plr]] += 1 end
	end
	roundActive = true
	local endAt = now() + modeDef.RoundTime
	set("PhaseEnd", endAt)
	while true do
		task.wait(0.25)
		local a, b = aliveCounts()
		set("AliveAlpha", a)
		set("AliveBravo", b)
		if participants.Alpha > 0 and participants.Bravo > 0 then
			if a == 0 and b == 0 then return nil end
			if a == 0 then return "Bravo" end
			if b == 0 then return "Alpha" end
		end
		if now() >= endAt then
			if a > b then return "Alpha" elseif b > a then return "Bravo" end
			return nil
		end
		if count(deployed) == 0 then return nil end
	end
end

local function startObjective()
	Objectives.Start(modeDef, {
		Folder = folder, Objectives = Maps.Objectives(),
		Deployed = function() return deployed end,
		Team = function(plr) return team[plr] end,
		Alive = alive,
		AddScore = addScore,
		Message = function(text, tone) message(text, nil, tone) end,
		TeamMessage = teamMessage,
		PlayerScore = function(plr, n) -- objective actions for the scoreboard's OBJ column
			local s = stats[plr]
			if s then
				s.O = (s.O or 0) + n
				plr:SetAttribute("MatchObj", s.O)
			end
		end,
	})
end

-- match history + win / loss for everybody still in the match. Leavers get no entry; an empty match is not recorded.
-- Win = on the winning team (team modes) or first place (free-for-all); no winner = Draw; everybody else = Loss.
local function recordHistory(winnerKey, reason)
	if reason == "Empty" then return end
	for plr, st in stats do
		if plr.Parent then
			local result
			if winnerKey == nil then result = "Draw"
			elseif typeof(winnerKey) == "Instance" then result = winnerKey == plr and "Win" or "Loss"
			else result = team[plr] == winnerKey and "Win" or "Loss" end
			ctx.Data.RecordMatch(plr, { Result = result, Mode = modeDef.Name, ModeId = modeDef.Id, Map = mapDef.Name, K = st.K, D = st.D, O = st.O })
		end
	end
end

local function runMatch()
	phase = "Match"
	teamScore, roundWins, endRequest = { Alpha = 0, Bravo = 0 }, { Alpha = 0, Bravo = 0 }, nil
	warned = { Alpha = false, Bravo = false }
	applyMode(modeDef)
	Maps.Load(mapDef.Id)
	local mapInfo = Maps.Info()
	set("MapCenter", mapInfo.Center) -- the full-map view (Radar) draws the arena from these
	set("MapSize", mapInfo.Size)
	local limit = modeDef.TimeLimit or modeDef.RoundTime
	introStart = now()
	introEnd = introStart + MC.IntroTime
	introActive = true
	ctx.MatchFrozen = true -- nobody can be hurt during the intro
	set("Phase", "Match")
	set("Mode", modeDef.Id)
	set("Map", mapDef.Id)
	set("ScoreAlpha", 0)
	set("ScoreBravo", 0)
	set("ScoreLimit", modeDef.Rounds and modeDef.RoundsToWin or modeDef.ScoreLimit)
	set("LeaderName", "")
	set("LeaderScore", 0)
	set("Round", 0)
	set("AliveAlpha", 0)
	set("AliveBravo", 0)
	set("IntroEnd", introEnd)
	set("PhaseEnd", introEnd + limit)

	for plr in ready do
		if plr.Parent then deploy(plr) end
	end

	-- intro: title card + flyover + 3-2-1 on the client, everybody held at their spawn point
	while now() < introEnd and #Players:GetPlayers() > 0 do task.wait(0.1) end
	introActive = false
	for _, root in anchored do
		if root.Parent then root.Anchored = false end
	end
	anchored = {}
	ctx.MatchFrozen = false
	Remotes.MatchEvent:FireAllClients("Go")
	if not modeDef.Rounds then set("PhaseEnd", now() + limit) end
	if modeDef.Objective then startObjective() end

	local winnerKey, reason
	if modeDef.Rounds then
		local round = 0
		while not winnerKey do
			round += 1
			local w = playRound(round)
			ctx.MatchFrozen = true
			roundActive = false
			if w then
				roundWins[w] += 1
				set("ScoreAlpha", roundWins.Alpha)
				set("ScoreBravo", roundWins.Bravo)
				message(("%s WINS THE ROUND"):format(w:upper()))
				if roundWins[w] >= modeDef.RoundsToWin then winnerKey = w end
			else
				message("ROUND DRAW")
			end
			if count(deployed) == 0 then break end -- everybody left: back to the vote
			if not winnerKey then task.wait(MC.RoundIntermission) end
		end
		reason = winnerKey and "Rounds" or "Empty"
	else
		local endAt = folder:GetAttribute("PhaseEnd")
		local startedAt = now()
		while not endRequest and now() < endAt do
			task.wait(0.25)
			if count(deployed) == 0 and now() - startedAt > 15 then break end -- nobody is playing: back to the vote
			if modeDef.Teams then
				local a, b = aliveCounts()
				set("AliveAlpha", a)
				set("AliveBravo", b)
			end
		end
		Objectives.Stop()
		reason = endRequest and "ScoreLimit" or (count(deployed) == 0 and "Empty" or "TimeLimit")
		if endRequest then
			winnerKey = endRequest.Winner
		elseif modeDef.Teams then
			if teamScore.Alpha > teamScore.Bravo then winnerKey = "Alpha" elseif teamScore.Bravo > teamScore.Alpha then winnerKey = "Bravo" end
		else
			local best, bestK = nil, 0
			for plr, st in stats do
				if plr.Parent and st.K > bestK then best, bestK = plr, st.K end
			end
			winnerKey = best
		end
	end
	recordHistory(winnerKey, reason)
	return buildResults(winnerKey, reason)
end

local function runResults(results)
	phase = "Results"
	ctx.MatchFrozen = true
	for plr in deployed do -- everybody stands still while the end sequence plays
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
			anchored[plr] = root
		end
	end
	set("Phase", "Results")
	set("PhaseEnd", now() + MC.ResultsTime)
	Remotes.MatchEvent:FireAllClients("Results", results)
	task.wait(MC.ResultsTime)
	cleanupMatch()
end

local function loop()
	while true do
		runVoting()
		local results = runMatch()
		runResults(results)
	end
end

-- ---------------------------------------------------------------- init
function M.Init(c)
	ctx, Remotes = c, c.Remotes
	Players.CharacterAutoLoads = false -- the match decides when and where players spawn
	for _, plr in Players:GetPlayers() do
		if plr.Character then plr.Character:Destroy() end
	end
	folder = Instance.new("Folder")
	folder.Name = "MatchState"
	folder.Parent = FPS
	ensureTeams()
	ctx.Score.OnMatchKill = M.OnKill
	Objectives.Init(c)

	Remotes.Vote.OnServerEvent:Connect(function(plr, kind, id)
		if phase ~= "Voting" or (kind ~= "Map" and kind ~= "Mode") or type(id) ~= "string" then return end
		local valid
		if kind == "Map" then valid = table.find(candidates, id) ~= nil
		else
			local def = Modes.Get(id)
			valid = def ~= nil and def.Enabled == true
		end
		if not valid then return end
		votes[kind][plr] = id
		recount()
	end)

	Remotes.Deploy.OnServerEvent:Connect(function(plr, want)
		if phase == "Voting" then
			if want == nil then setReady(plr, not ready[plr]) else setReady(plr, want == true) end
		elseif phase == "Match" then
			setReady(plr, true)
			deploy(plr)
		end
	end)

	Players.PlayerAdded:Connect(function(plr)
		plr.Neutral = true
		setReady(plr, false)
		plr:SetAttribute("Deployed", false)
	end)
	for _, plr in Players:GetPlayers() do
		plr.Neutral = true
		setReady(plr, false)
		plr:SetAttribute("Deployed", false)
	end
	Players.PlayerRemoving:Connect(function(plr)
		ready[plr], deployed[plr], team[plr], stats[plr], spawning[plr], spawnTime[plr] = nil, nil, nil, nil, nil, nil
		anchored[plr], deathInfo[plr] = nil, nil
		votes.Map[plr], votes.Mode[plr] = nil, nil
		if phase == "Voting" then recount() end
	end)

	task.spawn(loop)
end

return M
