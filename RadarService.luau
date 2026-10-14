-- RadarService: the server decides what the minimap may show about the OTHER team. Clients never compute it.
--   * UAV state lives here only (it used to be a replicated "UAVUntil" attribute that the client trusted).
--     While a player's team has a live UAV, every SWEEP seconds each teammate is sent a snapshot of the enemies (position + facing).
--     Players with the Ghost perk are left out of the snapshot. There is no through-wall highlight any more: the UAV is minimap-only.
--   * Gunfire pings: an unsuppressed shot tells the shooter's enemies where the SHOOTER STANDS (server position, not the client-supplied
--     muzzle origin), at most every PING_GAP seconds per shooter.
--   * Enemy positions are only ever sent to a client inside one of these two messages, so a client cannot invent or force a reveal.
-- Remote "RadarSync" (server -> client):
--   ("UAV", untilServerTime)          your team's UAV runs until this time (0 = none / over)
--   ("Sweep", { {Id, Pos, Yaw}, ... }) one UAV sweep of the enemies
--   ("Ping", userId, Pos, Yaw)        an enemy fired an unsuppressed weapon
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FPS = RS:WaitForChild("FPS")

local Rd = {}
local ctx

local SWEEP = 3        -- seconds between UAV sweeps
local TICK = 0.25      -- how often the server checks UAV state
local PING_GAP = 0.2   -- minimum seconds between two pings from the same shooter

local UAV = {}         -- [owner] = server time their UAV runs until
local Told = {}        -- [player] = the UAV end time that player's client was last told (nil = told "none")
local NextSweep = {}   -- [player] = server time of that player's next sweep
local LastPing = {}    -- [shooter] = os.clock() of their last ping

local function sameTeam(a, b) return a == b or (a.Team ~= nil and a.Team == b.Team) end

local function rootOf(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if h and h.Health > 0 and r then return r end
	return nil
end

local function yawOf(root)
	local l = root.CFrame.LookVector
	return math.atan2(-l.X, -l.Z)
end

local function ghost(plr)
	local s = ctx.State[plr]
	return s ~= nil and s.Perks ~= nil and s.Perks.Ghost == true
end

-- the minimap is only live for a deployed, living player during the match
local function eligible(plr)
	local state = FPS:FindFirstChild("MatchState")
	return state ~= nil and state:GetAttribute("Phase") == "Match" and plr:GetAttribute("Deployed") == true and rootOf(plr) ~= nil
end

-- latest end time among my team's live UAVs (0 = none)
local function uavUntil(plr, now)
	local best = 0
	for owner, t in UAV do
		if t > now and owner.Parent and sameTeam(plr, owner) then best = math.max(best, t) end
	end
	return best
end

local function sweepFor(plr)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= plr and not sameTeam(plr, other) and not ghost(other) then
			local root = rootOf(other)
			if root and other:GetAttribute("Deployed") == true then
				table.insert(list, { Id = other.UserId, Pos = root.Position, Yaw = yawOf(root) })
			end
		end
	end
	return list
end

-- ---------------------------------------------------------------- UAV state (called by StreakService)
function Rd.StartUAV(owner, duration)
	UAV[owner] = workspace:GetServerTimeNow() + duration
	for _, p in Players:GetPlayers() do
		if sameTeam(p, owner) then NextSweep[p] = nil end -- the team gets its first sweep right away
	end
end

function Rd.ClearUAV(owner)
	UAV[owner] = nil
end

-- ---------------------------------------------------------------- gunfire pings (called by FPSServer after an unsuppressed shot)
function Rd.Ping(shooter)
	local state = FPS:FindFirstChild("MatchState")
	if not state or state:GetAttribute("Phase") ~= "Match" then return end
	local clock = os.clock()
	if clock - (LastPing[shooter] or -100) < PING_GAP then return end
	local root = rootOf(shooter)
	if not root then return end
	LastPing[shooter] = clock
	local pos, yaw = root.Position, yawOf(root)
	for _, p in Players:GetPlayers() do
		if p ~= shooter and not sameTeam(p, shooter) and eligible(p) then
			ctx.Remotes.RadarSync:FireClient(p, "Ping", shooter.UserId, pos, yaw)
		end
	end
end

-- ---------------------------------------------------------------- loop
local function tick()
	local now = workspace:GetServerTimeNow()
	for owner, t in UAV do
		if t <= now or not owner.Parent then UAV[owner] = nil end
	end
	for _, p in Players:GetPlayers() do
		local untilT = uavUntil(p, now)
		if untilT > 0 and eligible(p) then
			if Told[p] ~= untilT then
				Told[p] = untilT
				ctx.Remotes.RadarSync:FireClient(p, "UAV", untilT)
			end
			if now >= (NextSweep[p] or 0) then
				NextSweep[p] = now + SWEEP
				ctx.Remotes.RadarSync:FireClient(p, "Sweep", sweepFor(p))
			end
		elseif Told[p] then
			Told[p], NextSweep[p] = nil, nil
			ctx.Remotes.RadarSync:FireClient(p, "UAV", 0)
		end
	end
end

function Rd.Init(c)
	ctx = c
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= TICK then
			acc = 0
			tick()
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		UAV[plr], Told[plr], NextSweep[plr], LastPing[plr] = nil, nil, nil, nil
	end)
end

return Rd
