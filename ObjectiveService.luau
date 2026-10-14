-- ObjectiveService: the objective game modes. MatchService starts one when the match countdown ends and stops it when the match ends.
--   Domination    three flags (A, B, C). Standing in a flag moves its capture bar towards your team; both teams inside = contested (frozen).
--                 Neutral -> owned takes CaptureTime seconds for one player (more players are faster, up to 3). An owned flag scores 1 point every
--                 ScoreInterval seconds. Enemy progress first neutralises a flag, then captures it.
--   Kill Confirmed every death drops a dog tag. An enemy picking it up = "Confirmed" (+1 team point), a teammate picking it up = "Denied" (no point).
--                 Tags disappear after TagLife seconds. Kills themselves do not score.
--   Hardpoint     one hill is active at a time (Maps.Objectives().Hills, in order). The team that is alone inside it scores 1 point per second,
--                 both teams = contested. The hill moves after HillTime seconds (the next one is shown HillPreview seconds early).
-- Everything the client needs is published as attributes on the MatchState folder (prefixes Obj / Flag / Hill) and, for Kill Confirmed, as a
-- Folder "Tags" under it (one child per tag with attributes Pos / Team / Name). The client draws all visuals from that (ObjectiveClient).
-- env (from MatchService): { Folder, Objectives, Deployed(), Team(plr), Alive(plr), AddScore(team, n), Message(text, tone), TeamMessage(team, forTeam, forOthers, toneTeam, toneOthers) }
local Players = game:GetService("Players")

local O = {}
local ctx
local run -- { Token, Env, Def, OnDeath, Cleanup } while a mode is running

local STEP = 0.2
local ZONE_UP, ZONE_DOWN = 14, 4       -- how far above / below the zone's ground point still counts as inside
local PICKUP_RANGE = 4.5               -- dog tag pickup distance
local OPPOSITE = { Alpha = "Bravo", Bravo = "Alpha" }

local function now() return workspace:GetServerTimeNow() end

local function set(env, key, value)
	if env.Folder:GetAttribute(key) ~= value then env.Folder:SetAttribute(key, value) end
end

-- players that count for objectives: deployed, alive, not downed, on a team. { { Plr, Pos, Team } ... }
local function gather(env)
	local list = {}
	for plr in env.Deployed() do
		if plr.Parent and env.Alive(plr) then
			local s = ctx.State[plr]
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			local tm = env.Team(plr)
			if root and tm and not (s and s.Down) then
				table.insert(list, { Plr = plr, Pos = root.Position, Team = tm })
			end
		end
	end
	return list
end

local function inZone(pos, zone)
	local d = pos - zone.Pos
	return d.X * d.X + d.Z * d.Z <= zone.Radius * zone.Radius and d.Y > -ZONE_DOWN and d.Y < ZONE_UP
end

-- who is inside a zone: { Alpha = { plr ... }, Bravo = { plr ... } }
local function occupants(present, zone)
	local out = { Alpha = {}, Bravo = {} }
	for _, p in present do
		if inZone(p.Pos, zone) then table.insert(out[p.Team], p.Plr) end
	end
	return out
end

-- XP tag + one point in the scoreboard's OBJ column
local function award(env, plr, tag)
	ctx.Score.Award(plr, tag)
	if env.PlayerScore then env.PlayerScore(plr, 1) end
end

local function round2(x) return math.floor(x * 50 + 0.5) / 50 end

-- ---------------------------------------------------------------- Domination
local function startDomination(def, env)
	local flags, ids = {}, {}
	for _, f in env.Objectives.Flags do
		table.insert(flags, { Id = f.Id, Pos = f.Pos, Radius = f.Radius, Prog = 0, Owner = nil, Warned = -100 })
		table.insert(ids, f.Id)
	end
	if #flags == 0 then warn("[ObjectiveService] this map has no flags") return nil end
	set(env, "ObjKind", "Domination")
	set(env, "Flags", table.concat(ids, ","))
	for _, f in flags do
		local k = "Flag_" .. f.Id .. "_"
		set(env, k .. "Pos", f.Pos)
		set(env, k .. "R", f.Radius)
		set(env, k .. "Owner", "")
		set(env, k .. "Prog", 0)
		set(env, k .. "Cont", false)
	end

	local captureTime, interval = def.CaptureTime or 8, def.ScoreInterval or 5
	local tick = 0

	local function step(dt)
		local present = gather(env)
		for _, f in flags do
			local occ = occupants(present, f)
			local na, nb = #occ.Alpha, #occ.Bravo
			local contested = na > 0 and nb > 0
			if contested then
				-- frozen until one side leaves
			elseif na > 0 or nb > 0 then
				local pusher = na > 0 and "Alpha" or "Bravo"
				local crowd = math.min(math.max(na, nb), 3)
				local rate = (1 / captureTime) * (1 + 0.5 * (crowd - 1))
				f.Prog = math.clamp(f.Prog + (pusher == "Alpha" and 1 or -1) * rate * dt, -1, 1)
			else -- nobody here: the flag drifts back to its owner (or to neutral)
				local target = f.Owner == "Alpha" and 1 or (f.Owner == "Bravo" and -1 or 0)
				local drift = dt / (captureTime * 2)
				if f.Prog < target then f.Prog = math.min(target, f.Prog + drift)
				elseif f.Prog > target then f.Prog = math.max(target, f.Prog - drift) end
			end

			local newOwner = f.Owner
			if f.Prog >= 1 then newOwner = "Alpha"
			elseif f.Prog <= -1 then newOwner = "Bravo"
			elseif f.Owner == "Alpha" and f.Prog <= 0 then newOwner = nil -- neutralised on the way to the other side
			elseif f.Owner == "Bravo" and f.Prog >= 0 then newOwner = nil end

			if newOwner ~= f.Owner then
				local old = f.Owner
				f.Owner = newOwner
				if newOwner then
					for _, plr in occ[newOwner] do award(env, plr, "Capture") end
					env.TeamMessage(newOwner, ("FLAG %s CAPTURED"):format(f.Id), ("ENEMY CAPTURED FLAG %s"):format(f.Id))
				else
					local pusher = OPPOSITE[old]
					for _, plr in occ[pusher] do award(env, plr, "Neutralize") end
					env.TeamMessage(pusher, ("FLAG %s NEUTRALIZED"):format(f.Id), ("FLAG %s LOST"):format(f.Id))
				end
			elseif f.Owner and not contested then -- an enemy is taking one of our flags
				local enemy = #occ[OPPOSITE[f.Owner]] > 0
				if enemy and os.clock() - f.Warned > 10 then
					f.Warned = os.clock()
					env.TeamMessage(f.Owner, ("FLAG %s UNDER ATTACK"):format(f.Id), nil, "Warn")
				end
			end

			local k = "Flag_" .. f.Id .. "_"
			set(env, k .. "Owner", f.Owner or "")
			set(env, k .. "Prog", round2(f.Prog))
			set(env, k .. "Cont", contested)
		end

		tick += dt
		if tick >= interval then
			tick -= interval
			local owned = { Alpha = 0, Bravo = 0 }
			for _, f in flags do
				if f.Owner then owned[f.Owner] += 1 end
			end
			if owned.Alpha > 0 then env.AddScore("Alpha", owned.Alpha) end
			if owned.Bravo > 0 then env.AddScore("Bravo", owned.Bravo) end
		end
	end
	return step, nil, nil
end

-- ---------------------------------------------------------------- Hardpoint
local function startHardpoint(def, env)
	local hills = env.Objectives.Hills
	if #hills == 0 then warn("[ObjectiveService] this map has no hills") return nil end
	local hillTime, gap, preview, holdEvery = def.HillTime or 60, def.HillGap or 4, def.HillPreview or 10, def.HoldXPEvery or 5
	local idx, on = 0, false
	local activeUntil, gapUntil = 0, 0
	local previewed = false
	local lastOwner, lastMsg = "", -100
	local scoreT, holdT = 0, 0

	set(env, "ObjKind", "Hardpoint")
	set(env, "HillOn", false)

	local function activate(i)
		idx, on = i, true
		local h = hills[i]
		activeUntil = now() + hillTime
		previewed, lastOwner, scoreT, holdT = false, "", 0, 0
		set(env, "HillPos", h.Pos)
		set(env, "HillR", h.Radius)
		set(env, "HillIdx", i)
		set(env, "HillOwner", "")
		set(env, "HillEnd", activeUntil)
		set(env, "HillNextPos", nil)
		set(env, "HillNextR", nil)
		set(env, "HillNextAt", nil)
		set(env, "HillOn", true)
		env.Message("HARDPOINT ACTIVE", "Warn")
	end
	activate(1)

	local function step(dt)
		local t = now()
		if not on then
			if t >= gapUntil then activate(idx % #hills + 1) end
			return
		end

		local present = gather(env)
		local occ = occupants(present, { Pos = hills[idx].Pos, Radius = hills[idx].Radius })
		local na, nb = #occ.Alpha, #occ.Bravo
		local owner = ""
		if na > 0 and nb > 0 then owner = "Contested"
		elseif na > 0 then owner = "Alpha"
		elseif nb > 0 then owner = "Bravo" end
		set(env, "HillOwner", owner)

		if owner ~= lastOwner then
			lastOwner = owner
			if os.clock() - lastMsg > 3 then
				if owner == "Alpha" or owner == "Bravo" then
					lastMsg = os.clock()
					env.TeamMessage(owner, "HARDPOINT SECURED", "ENEMY HOLD THE HARDPOINT")
				elseif owner == "Contested" then
					lastMsg = os.clock()
					env.Message("HARDPOINT CONTESTED", "Warn")
				end
			end
		end

		scoreT += dt
		while scoreT >= 1 do
			scoreT -= 1
			if owner == "Alpha" or owner == "Bravo" then
				env.AddScore(owner, 1)
				holdT += 1
				if holdT >= holdEvery then
					holdT = 0
					for _, plr in occ[owner] do award(env, plr, "HillHold") end
				end
			end
		end

		if not previewed and t >= activeUntil - preview then
			previewed = true
			local nx = hills[idx % #hills + 1]
			set(env, "HillNextPos", nx.Pos)
			set(env, "HillNextR", nx.Radius)
			set(env, "HillNextAt", activeUntil + gap)
		end
		if t >= activeUntil then
			on = false
			gapUntil = activeUntil + gap
			set(env, "HillOn", false)
			set(env, "HillOwner", "")
			set(env, "HillNextAt", gapUntil)
			env.Message("HARDPOINT MOVING", "Warn")
		end
	end
	return step, nil, nil
end

-- ---------------------------------------------------------------- Kill Confirmed
local function floorBelow(pos)
	local ignore = {}
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos, Vector3.new(0, -14, 0), params)
	return hit and hit.Position + Vector3.new(0, 1.3, 0) or pos
end

local function startKillConfirmed(def, env)
	local tagLife, maxTags = def.TagLife or 25, def.MaxTags or 36
	local folder = Instance.new("Folder")
	folder.Name = "Tags"
	folder.Parent = env.Folder
	local tags = {} -- { Node, Pos, Team, Born } oldest first
	set(env, "ObjKind", "KillConfirmed")

	local function remove(tag, outcome)
		local i = table.find(tags, tag)
		if i then table.remove(tags, i) end
		tag.Node:Destroy()
		ctx.Remotes.MatchEvent:FireAllClients("TagFX", tag.Pos, outcome, tag.Team)
	end

	local function onDeath(victim, victimTeam, pos)
		if not victimTeam or typeof(pos) ~= "Vector3" then return end
		local node = Instance.new("Folder")
		node.Name = "Tag"
		local at = floorBelow(pos)
		node:SetAttribute("Pos", at)
		node:SetAttribute("Team", victimTeam)
		node:SetAttribute("Name", victim.DisplayName)
		node.Parent = folder
		table.insert(tags, { Node = node, Pos = at, Team = victimTeam, Born = now() })
		while #tags > maxTags do remove(tags[1], "Expire") end
	end

	local function step(_dt)
		local t = now()
		for _, tag in table.clone(tags) do
			if t - tag.Born >= tagLife then remove(tag, "Expire") end
		end
		if #tags == 0 then return end
		for _, p in gather(env) do
			for _, tag in table.clone(tags) do
				if table.find(tags, tag) and (p.Pos - tag.Pos).Magnitude <= PICKUP_RANGE then
					if p.Team == tag.Team then
						award(env, p.Plr, "Denied")
						remove(tag, "Deny")
					else
						award(env, p.Plr, "Confirmed")
						env.AddScore(p.Team, 1)
						remove(tag, "Confirm")
					end
				end
			end
		end
	end
	local function cleanup() folder:Destroy() end
	return step, onDeath, cleanup
end

local KINDS = { Domination = startDomination, Hardpoint = startHardpoint, KillConfirmed = startKillConfirmed }

-- ---------------------------------------------------------------- public
function O.Init(c) ctx = c end

function O.Start(def, env)
	O.Stop()
	local starter = KINDS[def.Objective]
	if not starter then return false end
	local token = {}
	local mine = { Token = token, Env = env, Def = def }
	run = mine
	local step, onDeath, cleanup = starter(def, env)
	if not step then
		run = nil
		return false
	end
	mine.OnDeath, mine.Cleanup = onDeath, cleanup
	task.spawn(function()
		local last = os.clock()
		while run == mine do
			task.wait(def.Objective == "KillConfirmed" and 0.1 or STEP)
			if run ~= mine then break end
			local t = os.clock()
			local dt = t - last
			last = t
			local ok, err = pcall(step, dt)
			if not ok then warn("[ObjectiveService] " .. tostring(err)) end
		end
	end)
	return true
end

function O.Stop()
	local r = run
	run = nil
	if not r then return end
	if r.Cleanup then r.Cleanup() end
	for k in r.Env.Folder:GetAttributes() do
		if k:sub(1, 3) == "Obj" or k:sub(1, 4) == "Flag" or k:sub(1, 4) == "Hill" then r.Env.Folder:SetAttribute(k, nil) end
	end
end

-- MatchService calls this for every death while a match is running
function O.OnDeath(victim, victimTeam, pos)
	if run and run.OnDeath then run.OnDeath(victim, victimTeam, pos) end
end

return O
