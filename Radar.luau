-- Radar: minimap + full map.
--   Small map (top left): rotates with your view, shows allies live, your objectives and dog tags, and enemies only when they are "known":
--     * UAV      while you or a teammate has a live UAV (Armory.Streaks.UAV) the SERVER sends a sweep every few seconds with every enemy
--                (position + facing). Dots stay where the sweep saw them and fade until the next sweep. Ghost-perk players are not in it.
--     * Gunfire  an enemy that fires an unsuppressed weapon shows for PING_TIME seconds where the server saw them stand.
--     Enemy info only ever comes from the server (RadarService, remote RadarSync); this file just draws it. There is no through-wall highlight.
--   Full map (Map key, default N): north-up view of the whole arena (bounds come from MatchState.MapCenter / MapSize), same markers.
--   Objectives: flags (letter, coloured by owner), the active hill (ring) and the next hill (dim ring), dog tags (red = confirm, blue = deny).
--   It draws markers only, not the geometry, so it works on any map. Options: Settings > Interface > Minimap / size / range.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local Settings = require(script.Parent.Settings)
local MatchClient = require(script.Parent.MatchClient)

local Radar = {}
Radar.__index = Radar

local player = Players.LocalPlayer
local State = script.Parent:WaitForChild("MatchState")
local CENTER = Enum.TextXAlignment.Center
local SWEEP = 3          -- seconds between UAV sweeps (must match RadarService)
local PING_TIME = 2      -- seconds a gunfire ping stays
local LARGE = 540        -- full map size in design units
local ALLY, ENEMY, SELF = Theme.Plate, Color3.fromRGB(255, 70, 60), Color3.new(1, 1, 1)

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function alive(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
end

local function yawOf(plr)
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local l = root.CFrame.LookVector
	return math.atan2(-l.X, -l.Z)
end

-- ---------------------------------------------------------------- build
function Radar.new()
	local self = setmetatable({}, Radar)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "Radar", false, true, 3 -- under the touch buttons
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")
	self.Gui = gui

	local frame = Theme.Frame(root, UDim2.fromOffset(170, 170), UDim2.fromOffset(24, 24), nil, Theme.Panel, 0.35)
	self.Frame = frame
	self.Corner = Theme.Round(frame, 85)
	Theme.Stroke(frame, Theme.Dim, 2, 0.45)
	frame.ClipsDescendants = true
	self.Layer = Theme.Frame(frame, UDim2.fromScale(1, 1), nil, nil, Color3.new(), 1)

	-- range rings + crosshair lines (small map only)
	self.Guides = Theme.Frame(self.Layer, UDim2.fromScale(1, 1), nil, nil, Color3.new(), 1)
	for _, k in { 0.5, 0.99 } do
		local r = Theme.Frame(self.Guides, UDim2.fromScale(k, k), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
		Theme.Round(r, 999)
		Theme.Stroke(r, Theme.Dim, 1, 0.8)
	end
	Theme.Frame(self.Guides, UDim2.new(0, 1, 1, 0), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), Theme.Dim, 0.85)
	Theme.Frame(self.Guides, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), Theme.Dim, 0.85)

	-- arena outline (full map only)
	self.Bounds = Theme.Frame(self.Layer, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
	Theme.Stroke(self.Bounds, Theme.Dim, 2, 0.35)
	self.Bounds.Visible = false

	-- UAV sweep line
	self.Sweep = Theme.Frame(self.Layer, UDim2.new(0, 2, 0.5, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 1), ENEMY, 0.55)
	self.Sweep.Visible = false

	self.Items = Theme.Frame(self.Layer, UDim2.fromScale(1, 1), nil, nil, Color3.new(), 1)
	self.Pool = {}

	-- you
	self.Me = Theme.Frame(self.Layer, UDim2.fromOffset(12, 12), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
	local meDot = Theme.Frame(self.Me, UDim2.fromOffset(9, 9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), SELF, 0)
	meDot.Rotation = 45
	Theme.Frame(self.Me, UDim2.fromOffset(2, 7), UDim2.new(0.5, 0, 0, -1), Vector2.new(0.5, 1), SELF, 0)

	self.Label = Theme.Label(root, "", 14, ENEMY, CENTER, Theme.Display, UDim2.fromOffset(24, 198), UDim2.fromOffset(170, 18))

	self.Pings, self.Snap, self.SnapAt, self.UavUntil = {}, {}, -100, 0 -- all filled by the server (RadarSync)
	self.Large, self.Hidden = false, false

	InputMap.OnBegan("Map", function()
		if MatchClient.Phase() == "Match" then self.Large = not self.Large end
	end)
	-- everything about enemies comes from the server: UAV state, UAV sweeps and gunfire pings
	RS:WaitForChild("FPS"):WaitForChild("Remotes"):WaitForChild("RadarSync").OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "UAV" then
			self.UavUntil = type(a) == "number" and a or 0
			if self.UavUntil <= 0 then self.Snap, self.SnapAt = {}, -100 end
		elseif kind == "Sweep" and type(a) == "table" then
			local snap = {}
			for _, e in a do
				if type(e) == "table" and type(e.Id) == "number" and typeof(e.Pos) == "Vector3" then snap[e.Id] = { Pos = e.Pos, Yaw = e.Yaw } end
			end
			self.Snap, self.SnapAt = snap, os.clock()
		elseif kind == "Ping" and type(a) == "number" and typeof(b) == "Vector3" then
			self.Pings[a] = { Pos = b, Yaw = c, T = os.clock() }
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.05 then
			acc = 0
			self:_update()
		end
	end)
	return self
end

function Radar:SetHidden(h) self.Hidden = h end

-- ---------------------------------------------------------------- markers
local function newItem(layer)
	local holder = Theme.Frame(layer, UDim2.fromOffset(12, 12), nil, Vector2.new(0.5, 0.5), Color3.new(), 1)
	local ring = Theme.Frame(holder, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.new(), 1)
	Theme.Round(ring, 999)
	local ringStroke = Theme.Stroke(ring, Color3.new(1, 1, 1), 2, 0)
	ring.Visible = false
	local dot = Theme.Frame(holder, UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), ENEMY, 0)
	local corner = Theme.Round(dot, 5)
	local tick = Theme.Frame(holder, UDim2.fromOffset(2, 6), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 1), ENEMY, 0)
	local lbl = Theme.Label(holder, "", 12, Color3.new(0, 0, 0), CENTER, Theme.Display)
	lbl.TextStrokeTransparency = 1
	return { Holder = holder, Ring = ring, RingStroke = ringStroke, Dot = dot, Corner = corner, Tick = tick, Label = lbl }
end

-- opts: Color, Alpha (0..1 visible), Yaw (radians, shows a facing tick), Square, Letter, Size, RingSize (px diameter)
function Radar:_place(key, x, y, opts)
	local it = self.Pool[key]
	if not it then
		it = newItem(self.Items)
		self.Pool[key] = it
	end
	it.Used = true
	local size = opts.Size or 10
	it.Holder.Position = UDim2.new(0.5, x, 0.5, y)
	it.Holder.Rotation = opts.Yaw and math.deg(opts.Yaw) or 0
	it.Dot.Visible = opts.RingSize == nil
	it.Dot.Size = UDim2.fromOffset(size, size)
	it.Dot.BackgroundColor3, it.Dot.BackgroundTransparency = opts.Color, 1 - (opts.Alpha or 1)
	it.Corner.CornerRadius = UDim.new(0, opts.Square and 2 or size)
	it.Tick.Visible = opts.Yaw ~= nil and opts.RingSize == nil
	it.Tick.BackgroundColor3, it.Tick.BackgroundTransparency = opts.Color, 1 - (opts.Alpha or 1)
	it.Label.Text = opts.Letter or ""
	it.Label.Rotation = opts.Yaw and -math.deg(opts.Yaw) or 0
	it.Ring.Visible = opts.RingSize ~= nil
	if opts.RingSize then
		it.Ring.Size = UDim2.fromOffset(opts.RingSize, opts.RingSize)
		it.RingStroke.Color, it.RingStroke.Transparency = opts.Color, 1 - (opts.Alpha or 1)
	end
end

-- ---------------------------------------------------------------- per update
function Radar:_update()
	local phase = MatchClient.Phase()
	local char = player.Character
	local me = char and char:FindFirstChild("HumanoidRootPart")
	local show = Settings.Get("Interface.Minimap") and phase == "Match" and not self.Hidden and me ~= nil and alive(player) and MatchClient.IsDeployed()
	if not show then
		self.Frame.Visible, self.Label.Visible = false, false
		self.Large = false
		if not alive(player) then self.Snap, self.Pings = {}, {} end -- stale enemy info never survives a death
		return
	end

	local mapCenter, mapSize = State:GetAttribute("MapCenter"), State:GetAttribute("MapSize")
	local large = self.Large and typeof(mapCenter) == "Vector3" and typeof(mapSize) == "Vector3"
	local px = large and LARGE or Settings.Get("Interface.MinimapSize")
	local frame = self.Frame
	frame.Visible = true
	frame.Size = UDim2.fromOffset(px, px)
	if large then
		frame.AnchorPoint, frame.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		self.Corner.CornerRadius = UDim.new(0, 10)
		frame.BackgroundTransparency = 0.2
	else
		frame.AnchorPoint, frame.Position = Vector2.zero, UDim2.fromOffset(24, 24)
		self.Corner.CornerRadius = UDim.new(0.5, 0)
		frame.BackgroundTransparency = 0.35
	end

	-- world -> map offset in pixels from the centre
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local yawCF = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	local scale, origin
	if large then
		scale = (LARGE - 20) / math.max(mapSize.X, mapSize.Z, 1)
		origin = mapCenter
		self.Bounds.Visible = true
		self.Bounds.Size = UDim2.fromOffset(mapSize.X * scale, mapSize.Z * scale)
	else
		scale = (px / 2 - 4) / Settings.Get("Interface.MinimapRange")
		origin = me.Position
		self.Bounds.Visible = false
	end
	local half = px / 2 - 6
	local function project(pos, clampToEdge)
		local d = flat(pos - origin)
		if not large then d = yawCF:VectorToObjectSpace(d) end
		local x, y = d.X * scale, d.Z * scale
		local len = math.sqrt(x * x + y * y)
		if not large and len > half then
			if not clampToEdge then return nil end
			x, y = x / len * half, y / len * half
		end
		return x, y
	end
	local function facing(yaw) -- screen rotation of a world yaw (0 = up)
		if yaw == nil then return nil end
		return large and -yaw or (-yaw + math.atan2(-look.X, -look.Z)) -- both measured the same way as CameraRig.Yaw
	end

	-- you
	local mx, my = project(me.Position, true)
	self.Me.Position = UDim2.new(0.5, mx or 0, 0.5, my or 0)
	local myYaw = yawOf(player) or 0
	self.Me.Rotation = math.deg(facing(myYaw) or 0)
	self.Guides.Visible = not large

	-- allies (live)
	for _, other in Players:GetPlayers() do
		if other ~= player and player.Team ~= nil and other.Team == player.Team and alive(other) then
			local x, y = project(other.Character.HumanoidRootPart.Position, false)
			if x then self:_place("a" .. other.UserId, x, y, { Color = ALLY, Yaw = facing(yawOf(other)), Size = 9 }) end
		end
	end

	-- enemies: UAV snapshots and gunfire pings
	local clock = os.clock()
	local left = math.max(0, self.UavUntil - workspace:GetServerTimeNow())
	if left > 0 then
		local age = math.min(1, (clock - self.SnapAt) / SWEEP)
		for id, s in self.Snap do
			local x, y = project(s.Pos, false)
			if x then self:_place("e" .. id, x, y, { Color = ENEMY, Yaw = facing(s.Yaw), Alpha = 1 - 0.55 * age, Size = 10 }) end
		end
		self.Sweep.Visible = true
		self.Sweep.Position = UDim2.fromScale(0.5, 0.5)
		self.Sweep.Rotation = age * 360
		self.Sweep.Size = UDim2.new(0, 2, 0.5, 0)
		self.Label.Visible = true
		self.Label.Text = ("UAV  %ds"):format(math.ceil(left))
		self.Label.Position = UDim2.new(0, 24 + (large and 0 or px / 2 - 85), 0, 24 + px + 4)
	else
		self.Sweep.Visible = false
		self.Label.Visible = false
	end
	for id, p in self.Pings do
		local age = clock - p.T
		if age > PING_TIME then
			self.Pings[id] = nil
		elseif not (left > 0 and self.Snap[id]) then -- a live UAV dot already shows this enemy
			local x, y = project(p.Pos, false)
			if x then self:_place("p" .. id, x, y, { Color = ENEMY, Yaw = facing(p.Yaw), Alpha = 1 - age / PING_TIME, Size = 10 }) end
		end
	end

	-- objectives
	local kind = State:GetAttribute("ObjKind")
	if kind == "Domination" then
		for id in (State:GetAttribute("Flags") or ""):gmatch("[^,]+") do
			local pos = State:GetAttribute("Flag_" .. id .. "_Pos")
			if typeof(pos) == "Vector3" then
				local owner = State:GetAttribute("Flag_" .. id .. "_Owner") or ""
				local x, y = project(pos, true)
				self:_place("f" .. id, x, y, { Color = owner ~= "" and Theme.TeamColor[owner] or Color3.fromRGB(225, 228, 232), Square = true, Size = 16, Letter = id })
			end
		end
	elseif kind == "Hardpoint" then
		local r = State:GetAttribute("HillR") or 15
		if State:GetAttribute("HillOn") == true and typeof(State:GetAttribute("HillPos")) == "Vector3" then
			local owner = State:GetAttribute("HillOwner") or ""
			local col = (owner == "Alpha" or owner == "Bravo") and Theme.TeamColor[owner] or (owner == "Contested" and Theme.Warn or Theme.Accent)
			local x, y = project(State:GetAttribute("HillPos"), true)
			self:_place("hill", x, y, { Color = col, RingSize = math.max(14, r * 2 * scale) })
		end
		local np = State:GetAttribute("HillNextPos")
		if typeof(np) == "Vector3" then
			local x, y = project(np, true)
			self:_place("next", x, y, { Color = Theme.Dim, Alpha = 0.7, RingSize = math.max(12, (State:GetAttribute("HillNextR") or 15) * 2 * scale) })
		end
	elseif kind == "KillConfirmed" then
		local tags = State:FindFirstChild("Tags")
		if tags then
			for i, n in tags:GetChildren() do
				local pos = n:GetAttribute("Pos")
				if typeof(pos) == "Vector3" then
					local x, y = project(pos, false)
					if x then
						local friendly = n:GetAttribute("Team") == (player.Team and player.Team.Name)
						self:_place("t" .. i, x, y, { Color = friendly and Theme.Plate or Theme.Danger, Square = true, Size = 7 })
						self.Pool["t" .. i].Holder.Rotation = 45
					end
				end
			end
		end
	end

	-- drop markers nobody refreshed this update
	for key, it in self.Pool do
		if it.Used then
			it.Used = false
		else
			it.Holder:Destroy()
			self.Pool[key] = nil
		end
	end
end

return Radar
