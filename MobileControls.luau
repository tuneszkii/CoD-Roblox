-- MobileControls: on-screen controls for touch devices.
--   * move stick (fixed or floating, push fully to sprint), look drag on the rest of the screen, hold buttons for every action,
--     sprint lock toggle, optional second fire button, drag-while-firing aiming
--   * layout editor (MobileControls:Edit): drag, resize, fade, hide, mirror and reset every button; saved through Settings
-- Buttons press InputMap actions, so rebinding / weapon code never needs to know about touch.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local Widgets = require(script.Parent.Widgets)

local MobileControls = {}
MobileControls.__index = MobileControls

local C0 = Color3.new()
local CENTER, LEFT = Enum.TextXAlignment.Center, Enum.TextXAlignment.Left

local function isTouch(input)
	return input.UserInputType == Enum.UserInputType.Touch
end
local function pos2(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

function MobileControls.new()
	local self = setmetatable({}, MobileControls)
	self.Elements = {}      -- [id] = { Def, Frame, Label, Stroke, ... }
	self.Touches = {}       -- [InputObject] = { Kind, Id, ... }
	self.Editing, self.SprintLocked = false, false

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled = "MobileControls", false, true, 4, false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = gui

	-- look zone: everything that isn't a button (sits behind them)
	local look = Instance.new("Frame")
	look.Name, look.BackgroundTransparency, look.Size, look.Active, look.ZIndex = "LookZone", 1, UDim2.fromScale(1, 1), true, 1
	look.Parent = gui
	look.InputBegan:Connect(function(input)
		if isTouch(input) and not self.Editing then self.Touches[input] = { Kind = "look" } end
	end)
	self.LookZone = look

	UIS.InputChanged:Connect(function(input) self:_onChanged(input) end)
	UIS.InputEnded:Connect(function(input) self:_onEnded(input) end)

	local function refresh() self:_refreshVisible() end
	InputMap.OnDeviceChanged(refresh)
	InputMap.OnEnabledChanged(refresh)
	Settings.OnChanged(function(key)
		if key == "Layout" or key == "All" or key:sub(1, 6) == "Touch." then self:_build() end
	end)
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:_build() end) end

	self:_build()
	self:_refreshVisible()
	return self
end

-- ---------------------------------------------------------------- visibility
function MobileControls:_refreshVisible()
	local show = self.Editing or (InputMap.Device == "Touch" and InputMap.Enabled)
	if self.Gui.Enabled and not show then self:_releaseAll() end
	self.Gui.Enabled = show
end

function MobileControls:_releaseAll()
	for input, t in self.Touches do
		self:_endTouch(input, t)
	end
	self.Touches = {}
	InputMap.TouchMove = Vector2.zero
	InputMap.Release("Sprint", "t:stick")
end

-- ---------------------------------------------------------------- building
local function unitSize()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return vp.Y * 0.1 * Settings.Get("Touch.Scale") / 100
end

function MobileControls:_style(el, pressed)
	local L = Settings.GetLayout(el.Id)
	local vis = (Settings.Get("Touch.Opacity") / 100) * L.O
	local lit = pressed or (el.Id == "SprintLock" and self.SprintLocked)
	el.Frame.BackgroundColor3 = lit and Theme.Accent or C0
	el.Frame.BackgroundTransparency = 1 - (lit and 0.75 or 0.55) * vis
	el.Stroke.Color = lit and Theme.Accent or Theme.Text
	el.Stroke.Transparency = 1 - 0.85 * vis
	if el.Label then
		el.Label.TextColor3 = lit and Color3.fromRGB(20, 20, 20) or Theme.Text
		el.Label.TextTransparency = 1 - math.clamp(vis * 1.1, 0.15, 1)
	end
	if self.Editing and not L.V then -- hidden buttons stay editable but ghosted
		el.Frame.BackgroundTransparency, el.Stroke.Transparency = 0.8, 0.5
	end
end

function MobileControls:_build()
	for _, el in self.Elements do el.Frame:Destroy() end
	for _, el in self.Elements do
		if el.Hit then el.Hit:Destroy() end
	end
	self.Elements = {}
	local unit = unitSize()
	for _, def in Settings.TouchButtons do
		local L = Settings.GetLayout(def.Id)
		if L.V or self.Editing then
			if def.Kind == "Stick" then self:_buildStick(def, L, unit) else self:_buildButton(def, L, unit) end
		end
	end
	if self.Editing then self:_select(self.Selected) end
end

function MobileControls:_buildButton(def, L, unit)
	local px = unit * L.S
	local f = Instance.new("Frame")
	f.Name = def.Id
	f.Size, f.Position, f.AnchorPoint = UDim2.fromOffset(px, px), UDim2.fromScale(L.X, L.Y), Vector2.new(0.5, 0.5)
	f.BorderSizePixel, f.Active, f.ZIndex = 0, true, 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = f
	local label = Theme.Label(f, def.Label, math.clamp(math.floor(px * 0.24), 9, 22), Theme.Text, CENTER, Theme.Display)
	label.ZIndex = 6
	f.Parent = self.Gui
	local el = { Id = def.Id, Def = def, Frame = f, Label = label, Stroke = stroke }
	self.Elements[def.Id] = el
	self:_style(el, false)
	f.InputBegan:Connect(function(input)
		if not isTouch(input) and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if self.Editing then
			self:_editPress(el, input)
		elseif isTouch(input) then
			self:_buttonDown(el, input)
		end
	end)
end

function MobileControls:_buildStick(def, L, unit)
	local px = unit * L.S
	local base = Instance.new("Frame")
	base.Name = "Stick"
	base.Size, base.Position, base.AnchorPoint = UDim2.fromOffset(px, px), UDim2.fromScale(L.X, L.Y), Vector2.new(0.5, 0.5)
	base.BorderSizePixel, base.ZIndex = 0, 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = base
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = base
	local knob = Instance.new("Frame")
	knob.Size, knob.Position, knob.AnchorPoint = UDim2.fromOffset(px * 0.42, px * 0.42), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	knob.BackgroundColor3, knob.BackgroundTransparency, knob.BorderSizePixel, knob.ZIndex = Theme.Text, 0.35, 0, 6
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0.5, 0)
	kc.Parent = knob
	knob.Parent = base
	base.Parent = self.Gui

	local el = { Id = def.Id, Def = def, Frame = base, Stroke = stroke, Knob = knob, Size = px }
	self.Elements[def.Id] = el
	self:_style(el, false)

	-- touch area: the base itself (fixed) or the whole lower-left quarter (floating)
	local floating = Settings.Get("Touch.StickMode") == "Floating" and not self.Editing
	local hit = Instance.new("Frame")
	hit.BackgroundTransparency, hit.Active, hit.ZIndex, hit.BorderSizePixel = 1, true, 3, 0
	if floating then
		hit.Size, hit.Position, hit.AnchorPoint = UDim2.fromScale(0.45, 0.75), UDim2.fromScale(0, 1), Vector2.new(0, 1)
	else
		hit.Size, hit.Position, hit.AnchorPoint = UDim2.fromOffset(px * 1.5, px * 1.5), UDim2.fromScale(L.X, L.Y), Vector2.new(0.5, 0.5)
	end
	hit.Parent = self.Gui
	el.Hit = hit
	hit.InputBegan:Connect(function(input)
		if self.Editing then
			if isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1 then self:_editPress(el, input) end
		elseif isTouch(input) then
			self:_stickDown(el, input)
		end
	end)
	base.InputBegan:Connect(function(input)
		if self.Editing and (isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1) then self:_editPress(el, input) end
	end)
end

-- ---------------------------------------------------------------- play: buttons
function MobileControls:_buttonDown(el, input)
	local def = el.Def
	if def.Kind == "Toggle" then
		self.SprintLocked = not self.SprintLocked
		if self.SprintLocked then InputMap.Press(def.Action, "t:lock") else InputMap.Release(def.Action, "t:lock") end
		self:_style(el, false)
		return
	end
	local drag = (def.Id == "Fire" or def.Id == "FireLeft") and Settings.Get("Touch.DragFire")
	self.Touches[input] = { Kind = "button", Id = def.Id, Action = def.Action, Drag = drag }
	InputMap.Press(def.Action, "t:" .. def.Id)
	self:_style(el, true)
end

function MobileControls:_endTouch(input, t)
	if t.Kind == "button" then
		InputMap.Release(t.Action, "t:" .. t.Id)
		local el = self.Elements[t.Id]
		if el then self:_style(el, false) end
	elseif t.Kind == "stick" then
		InputMap.TouchMove = Vector2.zero
		InputMap.Release("Sprint", "t:stick")
		local el = self.Elements.Stick
		if el then
			el.Knob.Position = UDim2.fromScale(0.5, 0.5)
			if t.Floating then
				local L = Settings.GetLayout("Stick")
				el.Frame.Position = UDim2.fromScale(L.X, L.Y)
			end
		end
	end
end

-- ---------------------------------------------------------------- play: stick
function MobileControls:_stickDown(el, input)
	for _, t in self.Touches do
		if t.Kind == "stick" then return end -- one finger per stick
	end
	local floating = Settings.Get("Touch.StickMode") == "Floating"
	local inset = GuiService:GetGuiInset()
	local origin
	if floating then
		origin = pos2(input)
		el.Frame.Position = UDim2.fromOffset(origin.X + inset.X, origin.Y + inset.Y)
	else
		origin = el.Frame.AbsolutePosition + el.Frame.AbsoluteSize / 2 - inset
	end
	self.Touches[input] = { Kind = "stick", Origin = origin, Radius = el.Size / 2, Floating = floating }
	self:_updateStick(input, self.Touches[input])
end

function MobileControls:_updateStick(input, t)
	local el = self.Elements.Stick
	if not el then return end
	local off = pos2(input) - t.Origin
	local len = off.Magnitude
	local m = math.min(len / t.Radius, 1)
	local dir = len > 0 and off.Unit or Vector2.zero
	el.Knob.Position = UDim2.new(0.5, dir.X * m * t.Radius, 0.5, dir.Y * m * t.Radius)
	local dead = 0.12
	local scaled = m <= dead and 0 or (m - dead) / (1 - dead)
	InputMap.TouchMove = Vector2.new(dir.X * scaled, -dir.Y * scaled)
	if Settings.Get("Touch.SprintPush") then
		if m > 0.93 then InputMap.Press("Sprint", "t:stick")
		elseif m < 0.8 then InputMap.Release("Sprint", "t:stick") end
	end
end

-- ---------------------------------------------------------------- global touch events
function MobileControls:_onChanged(input)
	if self.EditDrag and (input == self.EditDrag.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
		self.EditDrag.Apply(input)
		return
	end
	local t = self.Touches[input]
	if not t then return end
	if t.Kind == "look" or (t.Kind == "button" and t.Drag) then
		InputMap.AddTouchLook(Vector2.new(input.Delta.X, input.Delta.Y))
	elseif t.Kind == "stick" then
		self:_updateStick(input, t)
	end
end

function MobileControls:_onEnded(input)
	local d = self.EditDrag
	if d and (input == d.Input or (d.Input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
		self.EditDrag = nil
		if d.Finish then d.Finish() end
		return
	end
	local t = self.Touches[input]
	if t then
		self.Touches[input] = nil
		self:_endTouch(input, t)
	end
end

-- ================================================================ layout editor
function MobileControls:_select(id)
	self.Selected = id
	for eid, el in self.Elements do
		el.Stroke.Thickness = eid == id and 4 or 2
		if eid == id then el.Stroke.Color, el.Stroke.Transparency = Theme.Accent, 0 end
	end
	if self.Panel then self.Panel.Refresh() end
end

function MobileControls:_editPress(el, input)
	self:_select(el.Id)
	local inset = GuiService:GetGuiInset()
	local center = el.Frame.AbsolutePosition + el.Frame.AbsoluteSize / 2
	local grab = pos2(input) + inset
	local offset = center - grab
	local vp = workspace.CurrentCamera.ViewportSize
	local last
	self.EditDrag = {
		Input = input,
		Apply = function(i)
			local p = pos2(i) + inset + offset
			p = Vector2.new(math.clamp(p.X, 0, vp.X), math.clamp(p.Y, 0, vp.Y))
			last = p
			el.Frame.Position = UDim2.fromOffset(p.X, p.Y)
			if el.Hit and not (Settings.Get("Touch.StickMode") == "Floating" and not self.Editing) then
				el.Hit.Position = UDim2.fromOffset(p.X, p.Y)
			end
		end,
		Finish = function()
			if last then Settings.SetLayout(el.Id, { X = last.X / vp.X, Y = last.Y / vp.Y }) end
		end,
	}
end

local function miniSlider(self, parent, title, pos, min, max, get, set, fmt)
	local box = Theme.Frame(parent, UDim2.fromOffset(250, 46), pos, nil, C0, 1)
	Theme.Label(box, title, 13, Theme.Dim, LEFT, Theme.Display, UDim2.new(), UDim2.fromOffset(150, 16))
	local value = Theme.Label(box, "", 13, Theme.Accent, Enum.TextXAlignment.Right, Theme.Display, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(90, 16), Vector2.new(1, 0))
	local hit = Theme.Frame(box, UDim2.fromOffset(250, 28), UDim2.fromOffset(0, 18), nil, C0, 1)
	hit.Active = true
	local track = Theme.Frame(hit, UDim2.new(1, -12, 0, 6), UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5), C0, 0.4)
	Theme.Round(track, 3)
	local fill = Theme.Frame(track, UDim2.fromScale(0, 1), nil, nil, Theme.Accent, 0)
	Theme.Round(fill, 3)
	local knob = Theme.Frame(track, UDim2.fromOffset(18, 18), UDim2.fromScale(0, 0.5), Vector2.new(0.5, 0.5), Theme.Text, 0)
	Theme.Round(knob, 9)
	local function refresh()
		local v = get()
		if not v then return end
		local t = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size, knob.Position = UDim2.fromScale(t, 1), UDim2.fromScale(t, 0.5)
		value.Text = fmt(v)
	end
	hit.InputBegan:Connect(function(input)
		if not (isTouch(input) or input.UserInputType == Enum.UserInputType.MouseButton1) then return end
		local function apply(i)
			local t = math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			set(min + t * (max - min))
			refresh()
		end
		self.EditDrag = { Input = input, Apply = apply }
		apply(input)
	end)
	return refresh
end

function MobileControls:Edit(onClose)
	if self.Editing then return end
	self.Editing, self.OnClose, self.Selected = true, onClose, "Fire"
	self.Snapshot = Settings.SnapshotLayout()
	self:_releaseAll()
	self:_build()
	self:_refreshVisible()

	local egui = Instance.new("ScreenGui")
	egui.Name, egui.ResetOnSpawn, egui.IgnoreGuiInset, egui.DisplayOrder = "MobileEditor", false, true, 60
	egui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.EditorGui = egui
	local root = Widgets.ScaledRoot(egui, 520)

	local panel = Theme.Glass(root, UDim2.fromOffset(560, 154), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	panel.BackgroundTransparency = 0.1
	panel.Active = true -- don't let touches fall through to the buttons behind it
	Theme.Label(panel, "TOUCH LAYOUT", 18, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(16, 8), UDim2.fromOffset(200, 24))
	local nameLbl = Theme.Label(panel, "", 14, Theme.Accent, Enum.TextXAlignment.Right, Theme.Display, UDim2.new(1, -16, 0, 10), UDim2.fromOffset(220, 20), Vector2.new(1, 0))
	Theme.Label(panel, "Drag a button to move it. Tap one to edit it.", 12, Theme.Dim, LEFT, Theme.Body, UDim2.fromOffset(16, 30), UDim2.fromOffset(330, 16))

	local refreshSize = miniSlider(self, panel, "SIZE", UDim2.fromOffset(16, 50), 50, 220,
		function() local L = self.Selected and Settings.GetLayout(self.Selected); return L and L.S * 100 end,
		function(v) if self.Selected then Settings.SetLayout(self.Selected, { S = v / 100 }) end end,
		function(v) return ("%d%%"):format(math.floor(v + 0.5)) end)
	local refreshOpacity = miniSlider(self, panel, "OPACITY", UDim2.fromOffset(294, 50), 10, 100,
		function() local L = self.Selected and Settings.GetLayout(self.Selected); return L and L.O * 100 end,
		function(v) if self.Selected then Settings.SetLayout(self.Selected, { O = v / 100 }) end end,
		function(v) return ("%d%%"):format(math.floor(v + 0.5)) end)

	local visBtn
	local function refresh()
		local def
		for _, d in Settings.TouchButtons do if d.Id == self.Selected then def = d end end
		nameLbl.Text = def and def.Label .. (def.Id == "FireLeft" and " (LEFT)" or "") or ""
		refreshSize()
		refreshOpacity()
		local L = self.Selected and Settings.GetLayout(self.Selected)
		if visBtn then visBtn.Text = L and L.V and "HIDE" or "SHOW" end
	end
	self.Panel = { Refresh = refresh }

	local function button(text, i, primary, fn)
		local b = Widgets.FlatButton(panel, text, UDim2.fromOffset(84, 36), UDim2.fromOffset(14 + (i - 1) * 90, 108), nil, primary)
		b.TextSize = 13
		b.Activated:Connect(fn)
		return b
	end
	visBtn = button("HIDE", 1, false, function()
		if not self.Selected then return end
		Settings.SetLayout(self.Selected, { V = not Settings.GetLayout(self.Selected).V })
	end)
	button("RESET", 2, false, function()
		if self.Selected then Settings.ResetLayout(self.Selected) end
	end)
	button("MIRROR", 3, false, function() Settings.MirrorLayout() end)
	button("RESET ALL", 4, false, function() Settings.ResetLayout() end)
	button("CANCEL", 5, false, function() self:_closeEditor(true) end)
	button("SAVE", 6, true, function() self:_closeEditor(false) end)

	-- keep the panel readouts live when the layout changes (size / visibility buttons)
	self.EditConn = Settings.OnChanged(function(key)
		if key == "Layout" or key == "All" then refresh() end
	end)
	refresh()
end

function MobileControls:_closeEditor(cancel)
	if not self.Editing then return end
	if cancel and self.Snapshot then Settings.RestoreLayout(self.Snapshot) end
	if self.EditConn then self.EditConn.Disconnect() end
	if self.EditorGui then self.EditorGui:Destroy() end
	self.Editing, self.EditorGui, self.Panel, self.EditDrag, self.Snapshot = false, nil, nil, nil, nil
	Settings.Flush()
	self:_build()
	self:_refreshVisible()
	local cb = self.OnClose
	self.OnClose = nil
	if cb then cb() end
end

return MobileControls
