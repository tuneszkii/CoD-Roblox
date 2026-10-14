-- ObjectiveClient: everything you see for Domination, Hardpoint and Kill Confirmed. Reads the attributes ObjectiveService publishes on MatchState
-- (ObjKind, Flag_*, Hill*, and the Tags folder) and builds local-only visuals: ground rings, flag poles / light columns, floating markers with
-- distance, dog tags, plus a small HUD under the score strip and a capture bar when you stand in a zone.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local MatchClient = require(script.Parent.MatchClient)
local UISound = require(script.Parent.UISound)

local ObjectiveClient = {}
ObjectiveClient.__index = ObjectiveClient

local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local player = Players.LocalPlayer
local State = script.Parent:WaitForChild("MatchState")
local NEUTRAL = Color3.fromRGB(225, 228, 232)
local ENEMY_TAG, FRIEND_TAG = Theme.Danger, Theme.Plate
local STUDS_TO_METERS = 0.28

local function myTeam() return player.Team and player.Team.Name end
local function teamColor(t) return Theme.TeamColor[t] or NEUTRAL end
local function clock(t)
	t = math.max(0, math.ceil(t))
	return ("%d:%02d"):format(t // 60, t % 60)
end

local function part(parent, size, cf, color, transparency, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency, p.Size, p.CFrame = Enum.Material.Neon, color, transparency, size, cf
	if shape then p.Shape = shape end
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder part lies along X; this stands it up

-- floating marker: circle with a letter / icon, a text line and an optional bar
local function marker(adornee, offset, size)
	local bb = Instance.new("BillboardGui")
	bb.Adornee, bb.AlwaysOnTop, bb.Size, bb.StudsOffset, bb.MaxDistance = adornee, true, UDim2.fromOffset(size, size + 40), offset, 2000
	bb.ResetOnSpawn = false
	bb.Parent = adornee
	local circle = Theme.Frame(bb, UDim2.fromOffset(size, size), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), Color3.new(), 0.35)
	Theme.Round(circle, size)
	local stroke = Theme.Stroke(circle, NEUTRAL, 3, 0)
	local letter = Theme.Label(circle, "", math.floor(size * 0.55), Theme.Text, CENTER, Theme.Display)
	local bar = Theme.Frame(bb, UDim2.fromOffset(size, 5), UDim2.new(0.5, 0, 0, size + 6), Vector2.new(0.5, 0), Color3.new(), 0.4)
	local fill = Theme.Frame(bar, UDim2.fromScale(0, 1), nil, nil, NEUTRAL, 0)
	local text = Theme.Label(bb, "", 14, Theme.Text, CENTER, Theme.Display, UDim2.new(0.5, 0, 0, size + 14), UDim2.fromOffset(size + 60, 18), Vector2.new(0.5, 0))
	return { Gui = bb, Circle = circle, Stroke = stroke, Letter = letter, Bar = bar, Fill = fill, Text = text }
end

function ObjectiveClient.new()
	local self = setmetatable({}, ObjectiveClient)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "ObjectiveHud", false, true, 6
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")
	self.Gui, self.Root = gui, root
	self.Kind = nil
	self.World = nil

	-- row under the score strip
	self.Row = Theme.Frame(root, UDim2.fromOffset(320, 50), UDim2.new(0.5, 0, 0, 138), Vector2.new(0.5, 0), Color3.new(), 1)
	self.Row.Visible = false
	self.Chips = {}
	self.HillPanel = Theme.Glass(self.Row, UDim2.fromScale(1, 1))
	self.HillPanel.Visible = false
	self.HillState = Theme.Label(self.HillPanel, "", 20, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 26))
	self.HillTime = Theme.Label(self.HillPanel, "", 14, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 29), UDim2.new(1, 0, 0, 18))

	-- capture bar while you stand in a zone
	self.Cap = Theme.Frame(root, UDim2.fromOffset(300, 40), UDim2.fromScale(0.5, 0.7), Vector2.new(0.5, 0), Color3.new(), 1)
	self.Cap.Visible = false
	self.CapLbl = Theme.Label(self.Cap, "", 20, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 24))
	local capBack = Theme.Frame(self.Cap, UDim2.fromOffset(260, 8), UDim2.new(0.5, 0, 0, 28), Vector2.new(0.5, 0), Color3.new(), 0.45)
	Theme.Round(capBack, 4)
	self.CapFill = Theme.Frame(capBack, UDim2.fromScale(0, 1), nil, nil, NEUTRAL, 0)
	Theme.Round(self.CapFill, 4)

	MatchClient.OnChanged(function() self:_sync() end)
	MatchClient.OnEvent(function(kind, a, b, c)
		if kind == "TagFX" then self:_tagBurst(a, b, c)
		elseif kind == "Message" and b ~= nil then
			if b == "Good" then UISound.Play("Capture") elseif b == "Bad" then UISound.Play("Lost") elseif b == "Warn" then UISound.Play("Warn") end
		end
	end)
	State.ChildAdded:Connect(function(child) if child.Name == "Tags" then self:_watchTags(child) end end)
	RunService.Heartbeat:Connect(function() self:_tick() end)
	self:_sync()
	return self
end

-- ---------------------------------------------------------------- lifecycle
function ObjectiveClient:_teardown()
	if self.World then self.World:Destroy() end
	self.World, self.Flags, self.Hill, self.Tags = nil, nil, nil, nil
	for _, c in self.Chips do c.Frame:Destroy() end
	self.Chips = {}
	self.Row.Visible, self.HillPanel.Visible, self.Cap.Visible = false, false, false
	self.TagConn = nil
end

function ObjectiveClient:_sync()
	local kind = MatchClient.Phase() == "Match" and State:GetAttribute("ObjKind") or nil
	if kind == self.Kind then return end
	self:_teardown()
	self.Kind = kind
	if not kind then return end
	local world = Instance.new("Folder")
	world.Name = "FPSObjectives"
	world.Parent = workspace
	self.World = world
	if kind == "Domination" then self:_buildFlags()
	elseif kind == "Hardpoint" then self:_buildHill()
	elseif kind == "KillConfirmed" then
		self.Tags = {}
		local f = State:FindFirstChild("Tags")
		if f then self:_watchTags(f) end
	end
end

-- ---------------------------------------------------------------- Domination
function ObjectiveClient:_buildFlags()
	self.Flags = {}
	self.Row.Visible = true
	local csv = State:GetAttribute("Flags") or ""
	local order = 0
	for id in csv:gmatch("[^,]+") do
		order += 1
		local pos, r = State:GetAttribute("Flag_" .. id .. "_Pos"), State:GetAttribute("Flag_" .. id .. "_R") or 9
		if typeof(pos) == "Vector3" then
			local disc = part(self.World, Vector3.new(0.3, r * 2, r * 2), CFrame.new(pos + Vector3.new(0, 0.2, 0)) * VERTICAL, NEUTRAL, 0.55, Enum.PartType.Cylinder)
			local pole = part(self.World, Vector3.new(0.5, 14, 0.5), CFrame.new(pos + Vector3.new(0, 7, 0)), Color3.fromRGB(170, 174, 180), 0, Enum.PartType.Block)
			pole.Material = Enum.Material.Metal
			local cloth = part(self.World, Vector3.new(0.15, 3.4, 5.5), CFrame.new(pos + Vector3.new(0.4, 3, 2.75)), NEUTRAL, 0.1, Enum.PartType.Block)
			local m = marker(pole, Vector3.new(0, 9, 0), 46)
			m.Letter.Text = id
			-- HUD chip
			local chip = Theme.Glass(self.Row, UDim2.fromOffset(46, 46), UDim2.new(0.5, (order - 2) * 56, 0.5, 0), Vector2.new(0.5, 0.5))
			local lbl = Theme.Label(chip, id, 26, Theme.Text, CENTER, Theme.Display)
			local bar = Theme.Frame(chip, UDim2.new(1, -8, 0, 4), UDim2.new(0, 4, 1, -7), nil, Color3.new(), 0.4)
			local fill = Theme.Frame(bar, UDim2.fromScale(0, 1), nil, nil, NEUTRAL, 0)
			table.insert(self.Chips, { Frame = chip, Stroke = chip:FindFirstChildOfClass("UIStroke"), Fill = fill, Label = lbl })
			self.Flags[id] = { Id = id, Pos = pos, R = r, Disc = disc, Cloth = cloth, Marker = m, Chip = self.Chips[#self.Chips], Last = nil }
		end
	end
end

function ObjectiveClient:_tickFlags(t)
	local mine = myTeam()
	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local inside
	for id, f in self.Flags do
		local k = "Flag_" .. id .. "_"
		local owner = State:GetAttribute(k .. "Owner") or ""
		local prog = State:GetAttribute(k .. "Prog") or 0
		local cont = State:GetAttribute(k .. "Cont") == true
		local lead = prog > 0 and "Alpha" or (prog < 0 and "Bravo" or nil)
		local col = owner ~= "" and teamColor(owner) or NEUTRAL:Lerp(teamColor(lead), math.abs(prog) * 0.8)
		if cont then col = Theme.Warn:Lerp(col, 0.5 + 0.5 * math.sin(t * 8)) end

		f.Disc.Color, f.Marker.Stroke.Color, f.Marker.Fill.BackgroundColor3 = col, col, teamColor(lead)
		f.Cloth.Color = col
		f.Chip.Stroke.Color, f.Chip.Fill.BackgroundColor3 = col, teamColor(lead)
		f.Chip.Label.TextColor3 = owner ~= "" and col or Theme.Text
		local share = owner ~= "" and 1 or math.abs(prog)
		f.Marker.Fill.Size = UDim2.fromScale(share, 1)
		f.Chip.Fill.Size = UDim2.fromScale(share, 1)
		-- the flag rises with capture progress and waves
		local height = 2.2 + 9.5 * math.max(share, owner ~= "" and 1 or 0)
		f.Cloth.CFrame = CFrame.new(f.Pos + Vector3.new(0.4, height, 2.75)) * CFrame.Angles(math.sin(t * 3 + f.R) * 0.06, 0, 0)
		f.Disc.Transparency = 0.55 + 0.12 * math.sin(t * 2)

		local label
		if cont then label = "CONTESTED"
		elseif owner == mine and owner ~= "" then label = "DEFEND"
		else label = "CAPTURE" end
		f.Marker.Text.Text = ("%s  %dM"):format(label, math.floor(((cam and cam.CFrame.Position or f.Pos) - f.Pos).Magnitude * STUDS_TO_METERS))

		if root then
			local d = root.Position - f.Pos
			if d.X * d.X + d.Z * d.Z <= f.R * f.R and d.Y > -4 and d.Y < 14 then
				inside = { Id = id, Share = share, Color = col, Cont = cont, Owner = owner, Lead = lead }
			end
		end
	end
	if inside then
		self.Cap.Visible = true
		local verb = inside.Cont and "CONTESTED" or (inside.Owner == mine and inside.Owner ~= "" and "HOLDING" or (inside.Owner ~= "" and "NEUTRALIZING" or "CAPTURING"))
		self.CapLbl.Text = ("%s  %s"):format(verb, inside.Id)
		self.CapFill.Size = UDim2.fromScale(inside.Share, 1)
		self.CapFill.BackgroundColor3 = inside.Color
	else
		self.Cap.Visible = false
	end
end

-- ---------------------------------------------------------------- Hardpoint
function ObjectiveClient:_buildHill()
	self.Row.Visible, self.HillPanel.Visible = true, true
	local W = self.World
	local h = { R = 15 }
	h.Disc = part(W, Vector3.new(0.3, 30, 30), CFrame.new(0, -500, 0) * VERTICAL, NEUTRAL, 0.5, Enum.PartType.Cylinder)
	h.Shell = part(W, Vector3.new(34, 30, 30), CFrame.new(0, -500, 0) * VERTICAL, NEUTRAL, 0.9, Enum.PartType.Cylinder)
	h.Anchor = part(W, Vector3.new(1, 1, 1), CFrame.new(0, -500, 0), NEUTRAL, 1, Enum.PartType.Block)
	h.Marker = marker(h.Anchor, Vector3.new(0, 14, 0), 46)
	h.Marker.Letter.Text = "H"
	h.NextDisc = part(W, Vector3.new(0.3, 30, 30), CFrame.new(0, -500, 0) * VERTICAL, Theme.Dim, 0.75, Enum.PartType.Cylinder)
	h.NextAnchor = part(W, Vector3.new(1, 1, 1), CFrame.new(0, -500, 0), NEUTRAL, 1, Enum.PartType.Block)
	h.NextMarker = marker(h.NextAnchor, Vector3.new(0, 8, 0), 34)
	h.NextMarker.Letter.Text = ">"
	h.NextMarker.Stroke.Color = Theme.Dim
	self.Hill = h
end

local function place(discs, pos, r)
	for _, d in discs do
		d.Part.Size = d.Shell and Vector3.new(34, r * 2, r * 2) or Vector3.new(0.3, r * 2, r * 2)
		d.Part.CFrame = CFrame.new(pos + Vector3.new(0, d.Shell and 17 or 0.2, 0)) * VERTICAL
	end
end

function ObjectiveClient:_tickHill(t)
	local h = self.Hill
	local on = State:GetAttribute("HillOn") == true
	local pos, r = State:GetAttribute("HillPos"), State:GetAttribute("HillR") or 15
	local owner = State:GetAttribute("HillOwner") or ""
	local mine = myTeam()
	local now = workspace:GetServerTimeNow()
	local cam = workspace.CurrentCamera

	if on and typeof(pos) == "Vector3" then
		if h.Pos ~= pos then
			h.Pos = pos
			place({ { Part = h.Disc }, { Part = h.Shell, Shell = true } }, pos, r)
			h.Anchor.CFrame = CFrame.new(pos)
		end
		local col = Theme.Accent
		if owner == "Alpha" or owner == "Bravo" then col = teamColor(owner)
		elseif owner == "Contested" then col = Theme.Warn:Lerp(Theme.Danger, 0.5 + 0.5 * math.sin(t * 8)) end
		h.Disc.Color, h.Shell.Color, h.Marker.Stroke.Color = col, col, col
		h.Disc.Transparency = 0.45 + 0.1 * math.sin(t * 2)
		h.Marker.Gui.Enabled = true
		h.Marker.Text.Text = ("HARDPOINT  %dM"):format(math.floor(((cam and cam.CFrame.Position or pos) - pos).Magnitude * STUDS_TO_METERS))

		local label = "UNCONTROLLED"
		if owner == "Contested" then label = "CONTESTED"
		elseif owner ~= "" then label = owner == mine and "YOUR TEAM HOLDS" or "ENEMY HOLDS" end
		self.HillState.Text, self.HillState.TextColor3 = label, col
		local left = (State:GetAttribute("HillEnd") or now) - now
		self.HillTime.Text = (State:GetAttribute("HillNextPos") ~= nil and left < 11) and ("MOVES IN %d"):format(math.ceil(left)) or ("HILL %s"):format(clock(left))

		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local d = root and (root.Position - pos)
		if d and d.X * d.X + d.Z * d.Z <= r * r and d.Y > -4 and d.Y < 14 then
			self.Cap.Visible = true
			self.CapLbl.Text = owner == "Contested" and "CONTESTED" or (owner == mine and "HOLDING THE HARDPOINT" or "IN THE HARDPOINT")
			self.CapFill.Size = UDim2.fromScale(owner == "Contested" and 0.5 or 1, 1)
			self.CapFill.BackgroundColor3 = col
		else
			self.Cap.Visible = false
		end
	else
		h.Pos = nil
		h.Disc.CFrame, h.Shell.CFrame = CFrame.new(0, -500, 0), CFrame.new(0, -500, 0)
		h.Marker.Gui.Enabled = false
		self.Cap.Visible = false
		local gapEnd = State:GetAttribute("HillNextAt")
		self.HillState.Text, self.HillState.TextColor3 = "HARDPOINT MOVING", Theme.Warn
		self.HillTime.Text = gapEnd and ("NEXT IN %d"):format(math.max(0, math.ceil(gapEnd - now))) or ""
	end

	local npos, nr = State:GetAttribute("HillNextPos"), State:GetAttribute("HillNextR") or 15
	if typeof(npos) == "Vector3" then
		if h.NextPos ~= npos then
			h.NextPos = npos
			place({ { Part = h.NextDisc } }, npos, nr)
			h.NextAnchor.CFrame = CFrame.new(npos)
		end
		h.NextMarker.Gui.Enabled = true
		h.NextMarker.Text.Text = "NEXT HILL"
		h.NextDisc.Transparency = 0.7 + 0.1 * math.sin(t * 4)
	else
		h.NextPos = nil
		h.NextDisc.CFrame = CFrame.new(0, -500, 0)
		h.NextMarker.Gui.Enabled = false
	end
end

-- ---------------------------------------------------------------- Kill Confirmed
function ObjectiveClient:_watchTags(folder)
	if self.Kind ~= "KillConfirmed" then return end
	self.Tags = self.Tags or {}
	local function add(node)
		local pos = node:GetAttribute("Pos")
		if typeof(pos) ~= "Vector3" or self.Tags[node] or not self.World then return end
		local friendly = node:GetAttribute("Team") == myTeam()
		local col = friendly and FRIEND_TAG or ENEMY_TAG
		local p = part(self.World, Vector3.new(0.9, 1.3, 0.15), CFrame.new(pos), col, 0)
		local m = marker(p, Vector3.new(0, 2.6, 0), 26)
		m.Letter.Text = friendly and "x" or "+"
		m.Stroke.Color = col
		m.Bar.Visible = false
		m.Text.Text = friendly and "DENY" or "CONFIRM"
		m.Text.TextColor3 = col
		self.Tags[node] = { Part = p, Pos = pos, Born = os.clock() }
	end
	for _, n in folder:GetChildren() do add(n) end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(n)
		local t = self.Tags and self.Tags[n]
		if t then
			t.Part:Destroy()
			self.Tags[n] = nil
		end
	end)
end

function ObjectiveClient:_tickTags(t)
	for _, tag in self.Tags or {} do
		local bob = math.sin(t * 3 + tag.Born) * 0.25
		tag.Part.CFrame = CFrame.new(tag.Pos + Vector3.new(0, 0.6 + bob, 0)) * CFrame.Angles(0, t * 3 + tag.Born, 0)
	end
end

-- pickup / expiry burst. outcome: Confirm | Deny | Expire
function ObjectiveClient:_tagBurst(pos, outcome, victimTeam)
	if typeof(pos) ~= "Vector3" then return end
	local friendly = victimTeam == myTeam()
	local col = outcome == "Expire" and Theme.Dim or (friendly and FRIEND_TAG or ENEMY_TAG)
	if outcome == "Confirm" then UISound.Play("Confirm") elseif outcome == "Deny" then UISound.Play("Deny") end
	local ring = part(workspace, Vector3.new(0.2, 1, 1), CFrame.new(pos) * VERTICAL, col, 0.2, Enum.PartType.Cylinder)
	local size = outcome == "Expire" and 4 or 10
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, size, size), Transparency = 1 }):Play()
	task.delay(0.5, function() ring:Destroy() end)
end

-- ---------------------------------------------------------------- per frame
function ObjectiveClient:_tick()
	if not self.Kind then return end
	local t = os.clock()
	if self.Flags then self:_tickFlags(t)
	elseif self.Hill then self:_tickHill(t)
	elseif self.Tags then self:_tickTags(t) end
end

return ObjectiveClient
