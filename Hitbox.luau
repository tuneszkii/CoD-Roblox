-- Pose-aware hitboxes for R6 player characters.
--
-- The default R6 parts the server sees never leave the standing pose (crouch / slide / downed are drawn locally by ThirdPerson.luau),
-- so raycasts against them would always hit a standing body. This module rebuilds the body as boxes from the same pose maths the
-- third-person rig uses (Config.ThirdPerson.StanceDrop / StanceFwd, aim pitch, strafe roll) and the stance replicated through the
-- character attributes, then tests rays against those boxes instead.
--
-- Hit results look like a RaycastResult and `Instance` is the matching real part (Head, Torso, Left Arm ...), so damage code that
-- looks at part names or ancestors keeps working. Anything that is not an R6 player (dummies, R15) falls back to its real parts.
--
-- Used on the server for authority and on the client for tracers / debug drawing (identical maths, same attributes).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local ClimbPose = require(script.Parent.ClimbPose)
local HB = Config.Hitbox
local TPc = Config.ThirdPerson
local DROP, FWD = TPc.StanceDrop, TPc.StanceFwd
local LYING = { Downed = true, Prone = true, Dive = true } -- same body pose (ThirdPerson.luau)
local COL = Config.Movement.Collider -- the physical box per stance: how far the root really sits below its standing height
local STAND_ROOT_Y = Config.Movement.Capsule.StandRootY

local CF, Angles = CFrame.new, CFrame.Angles
local AXES = { "X", "Y", "Z" }

local Hitbox = {}
Hitbox.Reach = HB.BoundRadius -- how far a posed body can be from its real (standing) parts

local states = {} -- [character] = pose state (dropped in step() once the character is gone)

-- ---------------------------------------------------------------- pose state
local function validChar(char)
	if not HB.Enabled or not char or not char.Parent or not Players:GetPlayerFromCharacter(char) then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.RigType ~= Enum.HumanoidRigType.R6 or hum.Health <= 0 then return nil end
	return hum, root
end

-- The stance is client-supplied, so keep it honest: the server owns Down, and slide / crouch have to roughly agree with the speed.
local function stanceOf(char, speed)
	if char:GetAttribute("Down") == true then return "Downed" end
	local stance = char:GetAttribute("Stance")
	if type(stance) ~= "string" then return speed > 1 and "Walk" or "Idle" end
	if stance == "Downed" then return speed > 1 and "Walk" or "Idle" end
	if stance == "Slide" and speed < HB.MinSlideSpeed then return "Crouch" end
	if stance == "Crouch" and speed > HB.MaxCrouchSpeed then return "Walk" end
	if stance == "Prone" and speed > HB.MaxProneSpeed then return "Walk" end
	if stance == "Dive" and speed > HB.MaxDiveSpeed then return "Air" end
	if ClimbPose.Stances[stance] then -- Mantle / Vault: only for as long as the (server-validated) climb data says it lasts
		local start, dur = char:GetAttribute("ClimbStart"), char:GetAttribute("ClimbDur")
		if type(start) ~= "number" or type(dur) ~= "number" or workspace:GetServerTimeNow() - start > dur + HB.ClimbGrace then return "Air" end
	end
	return stance
end

local function readInput(char, root)
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local pitch = char:GetAttribute("AimPitch")
	if type(pitch) ~= "number" then pitch = 0 end
	return stanceOf(char, speed), math.clamp(pitch, -1.5, 1.5), root.CFrame:VectorToObjectSpace(vel)
end

local function segment(a, b, thick, pad)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-3 then return nil end
	local fwd = d / len
	local up = math.abs(fwd.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local mid = (a + b) * 0.5
	return CFrame.lookAt(mid, mid + fwd, up), Vector3.new(thick, thick, len + pad)
end

-- Mirrors ThirdPerson.update: torso / head through the R6 joints, shoulders + hands for the arms, hip -> foot for the legs.
local function compute(st)
	local root, hum = st.Root, st.Hum
	-- The client's collider sinks the real root in low stances (Movement.luau), but the pose maths below is written against the standing
	-- root, so lift it back up by how far it has sunk.
	local rootCF = root.CFrame * CF(0, st.RootDrop, 0)
	local cp = st.CP -- mantle / vault pose (ClimbPose.luau), nil otherwise
	local torsoCF = rootCF * CF(0, -st.Drop - 1, 0) * Angles(0, st.Yaw, 0) * Angles(-(st.Fwd - st.Pitch * 0.35), 0, st.Roll - st.Peek * Config.Camera.Peek.Angle) * CF(0, 1, 0)
	local headCF = torsoCF * CF(0, 1, 0) * Angles(math.clamp(st.Pitch * 0.7, -0.9, 0.9) + st.DownA, 0, 0) * CF(0, 0.5, 0)
	local aimCF = torsoCF * CF(0, 0.4, 0) * Angles(st.Pitch * 0.65 + st.DownA * st.Fwd, 0, 0)

	local boxes = {
		{ Name = "Head", CF = headCF, Size = HB.Size.Head },
		{ Name = "Torso", CF = torsoCF, Size = HB.Size.Torso },
	}

	-- arms: shoulder -> the hand position while holding a gun
	for _, side in { 1, -1 } do
		local shoulder = (torsoCF * CF(side * 0.9, 0.5, 0)).Position
		local hand = (aimCF * CF(side == 1 and HB.HandR or HB.HandL)).Position
		if cp then
			local w = side == 1 and cp.HandW.R or cp.HandW.L
			if w > 0 then hand = hand:Lerp((side == 1 and cp.Hand.R or cp.Hand.L).Position, w) end
		end
		local cf, size = segment(shoulder, hand, HB.ArmThick, 0.4)
		if cf then table.insert(boxes, { Name = side == 1 and "Right Arm" or "Left Arm", CF = cf, Size = size }) end
	end

	-- legs: hip -> sole, per stance (same targets the foot-planting IK aims for, without the walk-cycle swing)
	local look = rootCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local right = rootCF.RightVector
	local groundY = rootCF.Position.Y - (hum.HipHeight + HB.LegLength + root.Size.Y * 0.5)
	local total = TPc.Thigh + TPc.Shin
	for _, side in { 1, -1 } do
		local hip = (torsoCF * CF(side * 0.5, -1, 0)).Position
		local base = rootCF.Position + right * side * 0.5
		local ankle
		if st.Stance == "Air" then
			ankle = hip + Vector3.new(0, -total * 0.78, 0) + flat * (0.5 * side * -1 + 0.2)
		elseif cp then -- mantle / vault: feet on the climb pose, easing back to standing on the floor as the body lands
			ankle = Vector3.new(base.X, groundY + 0.2, base.Z):Lerp((side == 1 and cp.Foot.R or cp.Foot.L) + Vector3.new(0, 0.2, 0), cp.FootW)
		elseif LYING[st.Stance] then
			local p = base - flat * (1.7 + (side == 1 and 0.15 or 0)) + right * side * 0.25
			ankle = Vector3.new(p.X, st.Stance == "Dive" and hip.Y or groundY + 0.25, p.Z) -- a dive flies: the legs trail at hip height
		elseif st.Stance == "Slide" then
			local p = base + flat * (side == 1 and 1.9 or 0.3)
			ankle = Vector3.new(p.X, groundY + 0.2 + (side == 1 and 0.25 or 0), p.Z)
		else
			ankle = Vector3.new(base.X, groundY + 0.2, base.Z)
		end
		local cf, size = segment(hip, ankle - Vector3.new(0, 0.15, 0), HB.LegThick, 0.1)
		if cf then table.insert(boxes, { Name = side == 1 and "Right Leg" or "Left Leg", CF = cf, Size = size }) end
	end

	st.Boxes, st.Center = boxes, torsoCF.Position
end

local function poseOf(char)
	local hum, root = validChar(char)
	if not hum then return nil end
	local st = states[char]
	if not st or st.Root ~= root then
		local stance, pitch = readInput(char, root)
		st = { Char = char, Hum = hum, Root = root, Stance = stance, Pitch = pitch, Roll = 0, Yaw = 0, Peek = 0,
			Drop = DROP[stance] or 0, Fwd = FWD[stance] or 0, DownA = LYING[stance] and 1 or 0,
			RootDrop = 0, FloorT = 0, FloorDist = nil }
		states[char] = st
		compute(st)
	elseif not st.Boxes then
		compute(st)
	end
	return st
end

-- ---------------------------------------------------------------- physical proxies (server)
-- Roblox physics only collides with real parts, which stay standing. Each posed player therefore gets six invisible anchored proxy parts
-- that follow the boxes. They collide ONLY with parts in the "Thrown" collision group (grenades, C4, ...), while the real character parts are
-- moved to a group that ignores "Thrown". To limit replication the proxies only move while a tracked physics object is near the player.
local IS_SERVER = RunService:IsServer()
local PROXY_GROUP, PLAYER_GROUP = "HitboxProxy", "HitboxPlayers"
Hitbox.ThrownGroup = "Thrown"

local tracked = {}                                -- [part] = true, loose physics objects that should collide with posed bodies
local proxies = {}                                -- [character] = { Parts = { [boxName] = part }, Active = bool }
local proxyInfo = setmetatable({}, { __mode = "k" }) -- [proxy part] = { Char, Name }
local proxyFolder

local function newProxy(char, box)
	if not proxyFolder then
		proxyFolder = Instance.new("Folder")
		proxyFolder.Name = "HitboxProxies"
		proxyFolder.Parent = workspace
	end
	local p = Instance.new("Part")
	p.Name = "HB_" .. box.Name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Transparency = true, false, false, true, false, 1
	p.CollisionGroup = PROXY_GROUP
	p.Size, p.CFrame = box.Size, box.CF
	p.Parent = proxyFolder
	proxyInfo[p] = { Char = char, Name = box.Name }
	return p
end

local function proxySet(char, st)
	local set = proxies[char]
	if not set then
		set = { Parts = {}, Active = false }
		for _, box in st.Boxes do set.Parts[box.Name] = newProxy(char, box) end
		proxies[char] = set
	end
	return set
end

local function nearTracked(pos)
	for part in tracked do
		if part.Parent == nil or part.Anchored then
			tracked[part] = nil
		elseif (part.Position - pos).Magnitude <= HB.PhysicalRange then
			return true
		end
	end
	return false
end

local function updateProxies(live)
	for char, set in proxies do
		if not live[char] then -- left, died or stopped being an R6 player
			for _, p in set.Parts do p:Destroy() end
			proxies[char] = nil
		end
	end
	if next(tracked) == nil then
		for _, set in proxies do
			if set.Active then
				set.Active = false
				for _, p in set.Parts do p.CanCollide = false end
			end
		end
		return
	end
	for char, st in live do
		if nearTracked(st.Center) then
			local set = proxySet(char, st)
			set.Active = true
			for _, box in st.Boxes do
				local p = set.Parts[box.Name]
				p.Size, p.CFrame, p.CanCollide = box.Size, box.CF, true
			end
		else
			local set = proxies[char]
			if set and set.Active then
				set.Active = false
				for _, p in set.Parts do p.CanCollide = false end
			end
		end
	end
end

-- A dive is the one lying pose a player can hold at sprint speed, so the server only believes it for a short window per dive, with a
-- gap before the next. Past that it is drawn / hit as an airborne body (the same fallback every untrusted claim gets). A dive that lands
-- turns into an ordinary slow Prone, which needs no window.
local function diveWindow(st, stance, now)
	if stance ~= "Dive" then
		st.DiveDenied = false
		if st.DiveStart then st.DiveEnd, st.DiveStart = now, nil end
		return stance
	end
	if st.DiveDenied then return "Air" end
	if not st.DiveStart then
		if now - (st.DiveEnd or -math.huge) < HB.DiveGap then
			st.DiveDenied = true
			return "Air"
		end
		st.DiveStart = now
	end
	if now - st.DiveStart > HB.DiveMaxTime then
		st.DiveDenied = true
		return "Air"
	end
	return "Dive"
end

-- How far the real root sits below its standing height. While the player is standing on something the floor is the truth (the server
-- looks down every FloorRate seconds), so a client cannot float a low hitbox in mid-air. Diving / airborne bodies use the stance's value.
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local function measureFloor(st, now)
	if now - st.FloorT < HB.FloorRate then return end
	st.FloorT = now
	local list = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(list, plr.Character) end
	end
	floorParams.FilterDescendantsInstances = list
	local r = workspace:Raycast(st.Root.Position, Vector3.new(0, -(STAND_ROOT_Y + 1), 0), floorParams)
	st.FloorDist = r and r.Distance or nil
end

local function rootDropTarget(st, stance)
	local col = COL[stance]
	local byStance = col and col.RootDrop or 0
	if stance == "Dive" or stance == "Air" or ClimbPose.Stances[stance] then return byStance end
	local d = st.FloorDist
	if d and d <= STAND_ROOT_Y + 0.6 then return math.clamp(STAND_ROOT_Y - d, 0, 2.6) end
	return byStance
end

local function step(dt)
	local now = os.clock()
	local k, kp = 1 - math.exp(-14 * dt), 1 - math.exp(-20 * dt)
	for char in states do
		if not char.Parent then states[char] = nil end
	end
	local live = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local st = char and poseOf(char)
		if st then
			live[char] = st
			local stance, pitch, lv = readInput(char, st.Root)
			if IS_SERVER then stance = diveWindow(st, stance, now) end -- authority only: the window is for what bullets hit, not for how the client draws
			st.Stance = stance
			measureFloor(st, now)
			st.RootDrop += (rootDropTarget(st, stance) - st.RootDrop) * k
			local climb = ClimbPose.Read(char, stance)
			local cp = climb and ClimbPose.Solve(climb.Kind, climb.T, st.Root.CFrame * CF(0, st.RootDrop, 0), climb.Ledge, climb.Depth)
			st.CP = cp
			st.Pitch += (pitch - st.Pitch) * kp
			st.Drop += ((cp and cp.Drop or DROP[stance] or 0) - st.Drop) * k
			st.Fwd += ((cp and cp.Fwd or FWD[stance] or 0) - st.Fwd) * k
			st.Yaw += ((cp and cp.Yaw or 0) - st.Yaw) * k
			st.DownA += ((LYING[stance] and 1 or 0) - st.DownA) * k
			st.Roll += (math.clamp(-lv.X * 0.012, -0.22, 0.22) + (cp and cp.Roll or 0) - st.Roll) * k
			local peekT = char:GetAttribute("PeekAmt")
			st.Peek += (math.clamp(type(peekT) == "number" and peekT or 0, -1, 1) - st.Peek) * k -- corner peek lean (server sanity-checks it in StateSync)
			compute(st)
		end
	end
	if IS_SERVER and HB.Physical then updateProxies(live) end
end

-- ---------------------------------------------------------------- ray / box maths
-- Ray origin + vec * t (t in 0..1) against an oriented box, grown by `pad` studs on every side (sphere sweeps).
local function rayBox(origin, vec, cf, size, pad)
	local o, d = cf:PointToObjectSpace(origin), cf:VectorToObjectSpace(vec)
	local h = size * 0.5 + Vector3.one * pad
	local tmin, tmax, axis, sgn = 0, 1, nil, 1
	for i = 1, 3 do
		local a = AXES[i]
		local oa, da, ha = o[a], d[a], h[a]
		if math.abs(da) < 1e-9 then
			if math.abs(oa) > ha then return nil end
		else
			local inv = 1 / da
			local t1, t2, s = (-ha - oa) * inv, (ha - oa) * inv, -1
			if t1 > t2 then t1, t2, s = t2, t1, 1 end
			if t1 > tmin then tmin, axis, sgn = t1, a, s end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	local normal
	if axis then
		normal = cf:VectorToWorldSpace(Vector3.new(axis == "X" and sgn or 0, axis == "Y" and sgn or 0, axis == "Z" and sgn or 0))
	else
		normal = vec.Magnitude > 0 and -vec.Unit or Vector3.yAxis -- started inside the box
	end
	return tmin, normal
end

local function nearSegment(origin, vec, point, radius)
	local len2 = vec:Dot(vec)
	local u = len2 > 0 and math.clamp((point - origin):Dot(vec) / len2, 0, 1) or 0
	return (origin + vec * u - point).Magnitude <= radius
end

local function partFor(char, name)
	return char:FindFirstChild(name) or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
end

-- Casts the world (every posed player excluded) and then the posed bodies, returning whichever is closest.
local function cast(origin, vec, ignore, respectCanCollide, radius)
	local list = ignore and table.clone(ignore) or {}
	local bodies = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local st = char and poseOf(char)
		if st then
			table.insert(list, char) -- the real (standing) parts must not be hit
			if not (ignore and table.find(ignore, char)) then table.insert(bodies, st) end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = respectCanCollide == true
	local res
	if radius then res = workspace:Spherecast(origin, radius, vec, params) else res = workspace:Raycast(origin, vec, params) end

	local len = vec.Magnitude
	local best, bestDist = res, res and res.Distance or math.huge
	for _, st in bodies do
		if nearSegment(origin, vec, st.Center, HB.BoundRadius + (radius or 0)) then
			for _, box in st.Boxes do
				local t, normal = rayBox(origin, vec, box.CF, box.Size, radius or 0)
				if t and t * len < bestDist then
					bestDist = t * len
					best = { Instance = partFor(st.Char, box.Name), Position = origin + vec * t, Normal = normal,
						Distance = bestDist, Material = Enum.Material.Plastic, Posed = true }
				end
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------- public API
-- origin, vec (direction * length), ignore = { instances } (usually the shooter's character). Returns nil or a RaycastResult-like table.
function Hitbox.Raycast(origin, vec, ignore, respectCanCollide)
	return cast(origin, vec, ignore, respectCanCollide, nil)
end

function Hitbox.Spherecast(origin, radius, vec, ignore, respectCanCollide)
	return cast(origin, vec, ignore, respectCanCollide, radius)
end

-- Where the body really is (chest of the posed torso). Falls back to the root part for dummies / R15.
function Hitbox.Center(char)
	local st = poseOf(char)
	if st then return st.Center end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- For line-of-sight rays: the extra instances plus every posed character (their standing parts are not really there).
function Hitbox.Exclusions(extra)
	local list = extra and table.clone(extra) or {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char and poseOf(char) then table.insert(list, char) end
	end
	return list
end

function Hitbox.IsPosed(char) return poseOf(char) ~= nil end

-- ---- physical objects (server) -----------------------------------------------------------------------------------------
-- Put a loose physics part in the "Thrown" collision group and track it: it then collides with the posed bodies, not the standing parts.
function Hitbox.TrackPhysical(part)
	if not (IS_SERVER and HB.Physical) then return end
	part.CollisionGroup = Hitbox.ThrownGroup
	tracked[part] = true
end

-- If `part` is one of the proxies: returns { Char, Name } (which body part of whom it stands for), else nil.
function Hitbox.ProxyInfo(part) return proxyInfo[part] end

-- Current world CFrame of one hitbox ("Head", "Torso", "Left Arm" ...). Stuck grenades / C4 use it to ride along with the pose.
function Hitbox.BoxCFrame(char, name)
	local st = poseOf(char)
	if not st then return nil end
	for _, box in st.Boxes do
		if box.Name == name then return box.CF end
	end
	return nil
end

-- The proxy parts of a character (created on demand), e.g. for NoCollisionConstraints with the thrower.
function Hitbox.ProxyParts(char)
	local st = IS_SERVER and HB.Physical and poseOf(char)
	if not st then return {} end
	local list = {}
	for _, p in proxySet(char, st).Parts do table.insert(list, p) end
	return list
end

local function setupPhysics()
	local PhysicsService = game:GetService("PhysicsService")
	for _, g in { Hitbox.ThrownGroup, PROXY_GROUP, PLAYER_GROUP } do
		pcall(function() PhysicsService:RegisterCollisionGroup(g) end)
	end
	PhysicsService:CollisionGroupSetCollidable(Hitbox.ThrownGroup, PLAYER_GROUP, false) -- no more bumping into the standing body
	PhysicsService:CollisionGroupSetCollidable(Hitbox.ThrownGroup, PROXY_GROUP, true)   -- ... but into the posed one
	PhysicsService:CollisionGroupSetCollidable(PROXY_GROUP, PLAYER_GROUP, false)        -- proxies never shove real characters
	PhysicsService:CollisionGroupSetCollidable(PROXY_GROUP, PROXY_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PROXY_GROUP, "Default", false)

	local function group(char)
		local function apply(d) if d:IsA("BasePart") then d.CollisionGroup = PLAYER_GROUP end end
		for _, d in char:GetDescendants() do apply(d) end
		char.DescendantAdded:Connect(apply)
	end
	local function watch(plr)
		plr.CharacterAdded:Connect(group)
		if plr.Character then group(plr.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, plr in Players:GetPlayers() do watch(plr) end
end

-- ---------------------------------------------------------------- debug drawing (client)
local debugOn, debugParts = false, {}
local COLORS = { Head = Color3.fromRGB(235, 70, 70), Torso = Color3.fromRGB(240, 150, 50), ["Left Arm"] = Color3.fromRGB(235, 215, 70),
	["Right Arm"] = Color3.fromRGB(235, 215, 70), ["Left Leg"] = Color3.fromRGB(70, 150, 240), ["Right Leg"] = Color3.fromRGB(70, 150, 240) }

local function clearDebug()
	for char, set in debugParts do
		for _, p in set do p:Destroy() end
		debugParts[char] = nil
	end
end

local function drawDebug()
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	local seen = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local st = char and char ~= me and states[char]
		if st and st.Boxes and char.Parent then
			seen[char] = true
			local set = debugParts[char]
			if not set then
				set = {}
				debugParts[char] = set
			end
			for _, box in st.Boxes do
				local p = set[box.Name]
				if not p then
					p = Instance.new("Part")
					p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
					p.Material, p.Transparency, p.Color = Enum.Material.SmoothPlastic, 0.6, COLORS[box.Name]
					p.Name = "HB_" .. box.Name
					p.Parent = workspace.CurrentCamera
					set[box.Name] = p
				end
				p.Size, p.CFrame = box.Size, box.CF
			end
		end
	end
	for char, set in debugParts do
		if not seen[char] then
			for _, p in set do p:Destroy() end
			debugParts[char] = nil
		end
	end
end

function Hitbox.SetDebug(on)
	if not RunService:IsClient() then return end
	debugOn = on == true
	if not debugOn then clearDebug() end
end

function Hitbox.ToggleDebug()
	Hitbox.SetDebug(not debugOn)
	return debugOn
end

local started = false
function Hitbox.Start()
	if started then return end
	started = true
	Hitbox.SetDebug(HB.Debug)
	if IS_SERVER and HB.Enabled and HB.Physical then setupPhysics() end
	RunService.Heartbeat:Connect(function(dt)
		step(dt)
		if debugOn then drawDebug() end
	end)
end

return Hitbox
