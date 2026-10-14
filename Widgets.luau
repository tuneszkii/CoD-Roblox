-- Widgets: reusable menu controls (slider, toggle, choice, button, header) that work with mouse, touch and gamepad.
-- They read / write Settings directly (entry.Key) and return { Row, Refresh } so a page can re-sync after a reset.
-- Gamepad: sliders / choices are Selectable; D-pad left / right adjusts them (hold to repeat); A activates buttons and toggles.
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)

local Widgets = {}

local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local C0 = Color3.new()

-- ---------------------------------------------------------------- shared selection highlight (gamepad focus ring)
local selImage = Instance.new("Frame")
selImage.BackgroundTransparency = 1
selImage.Size = UDim2.fromScale(1, 1)
do
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness = Theme.Accent, 2
	s.Parent = selImage
	local r = Instance.new("UICorner")
	r.CornerRadius = UDim.new(0, 6)
	r.Parent = selImage
end
Widgets.SelectionImage = selImage

function Widgets.Selectable(obj, adjustFn)
	obj.Selectable = true
	obj.SelectionImageObject = selImage
	if adjustFn then
		obj.NextSelectionLeft, obj.NextSelectionRight = obj, obj -- D-pad left / right adjusts instead of moving focus
		Widgets._adjust[obj] = adjustFn
	end
end
Widgets._adjust = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------- global input (one set of connections for every widget)
local drag
UIS.InputChanged:Connect(function(input)
	if drag and (input == drag.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
		drag.Apply(input.Position.X)
	end
end)
UIS.InputEnded:Connect(function(input)
	if drag and (input == drag.Input or (drag.Input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
		if drag.Scroller then drag.Scroller.ScrollingEnabled = true end
		drag = nil
	end
end)
UIS.InputBegan:Connect(function(input)
	local kc = input.KeyCode
	if input.UserInputType.Name:sub(1, 7) ~= "Gamepad" or (kc ~= Enum.KeyCode.DPadLeft and kc ~= Enum.KeyCode.DPadRight) then return end
	local sel = GuiService.SelectedObject
	local fn = sel and Widgets._adjust[sel]
	if not fn then return end
	local dir = kc == Enum.KeyCode.DPadRight and 1 or -1
	fn(dir)
	task.spawn(function() -- hold to repeat
		task.wait(0.4)
		while UIS:IsGamepadButtonDown(input.UserInputType, kc) and GuiService.SelectedObject == sel do
			fn(dir)
			task.wait(0.07)
		end
	end)
end)

-- ---------------------------------------------------------------- helpers
function Widgets.Fmt(entry, v)
	local step = entry.Step or 1
	local decimals = step >= 1 and 0 or (step >= 0.1 and 1 or 2)
	return (("%." .. decimals .. "f"):format(v)) .. (entry.Suffix or "")
end

function Widgets.Header(parent, text, order)
	local h = Theme.Frame(parent, UDim2.new(1, -8, 0, 34), nil, nil, C0, 1)
	h.LayoutOrder = order
	Theme.Label(h, text, 14, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(4, 8), UDim2.new(1, -8, 0, 20))
	Theme.Frame(h, UDim2.new(1, -8, 0, 1), UDim2.new(0, 4, 1, -2), nil, Theme.Accent, 0.7)
	return h
end

-- base row: title (+ optional description) on the left, `right` container (310 x 36) on the right
function Widgets.Row(parent, label, desc, order)
	local h = desc and 68 or 54
	local row = Theme.Frame(parent, UDim2.new(1, -8, 0, h), nil, nil, Theme.Panel, 0.45)
	row.LayoutOrder = order
	Theme.Round(row, 5)
	if desc then
		Theme.Label(row, label, 17, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(16, 8), UDim2.new(1, -350, 0, 24))
		local d = Theme.Label(row, desc, 12, Theme.Dim, LEFT, Theme.Body, UDim2.fromOffset(16, 33), UDim2.new(1, -350, 0, 30))
		d.TextWrapped, d.TextYAlignment = true, Enum.TextYAlignment.Top
	else
		Theme.Label(row, label, 17, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(16, 0), UDim2.new(1, -350, 1, 0))
	end
	local right = Theme.Frame(row, UDim2.fromOffset(310, 36), UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5), C0, 1)
	return row, right
end

local function flatButton(parent, text, size, pos, anchor, primary)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Size, b.Position, b.AnchorPoint, b.Text = size, pos or UDim2.new(), anchor or Vector2.zero, text
	b.BackgroundColor3 = primary and Theme.Accent or C0
	b.BackgroundTransparency, b.BorderSizePixel = primary and 0 or 0.4, 0
	b.Font, b.TextSize = Theme.Display, 16
	b.TextColor3 = primary and Color3.fromRGB(20, 20, 20) or Theme.Text
	Theme.Round(b, 5)
	if not primary then Theme.Stroke(b, Theme.Dim, 1, 0.65) end
	b.Parent = parent
	Widgets.Selectable(b)
	return b
end
Widgets.FlatButton = flatButton

-- ---------------------------------------------------------------- slider
function Widgets.Slider(parent, entry, order)
	local row, right = Widgets.Row(parent, entry.Label, entry.Desc, order)
	local value = Theme.Label(right, "", 17, Theme.Accent, RIGHT, Theme.Display, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(72, 36), Vector2.new(1, 0))
	local hit = Theme.Frame(right, UDim2.fromOffset(224, 36), UDim2.new(), nil, C0, 1)
	hit.Active = true
	local track = Theme.Frame(hit, UDim2.new(1, -10, 0, 6), UDim2.new(0, 5, 0.5, 0), Vector2.new(0, 0.5), C0, 0.45)
	Theme.Round(track, 3)
	local fill = Theme.Frame(track, UDim2.fromScale(0, 1), nil, nil, Theme.Accent, 0)
	Theme.Round(fill, 3)
	local knob = Theme.Frame(track, UDim2.fromOffset(18, 18), UDim2.fromScale(0, 0.5), Vector2.new(0.5, 0.5), Theme.Text, 0)
	Theme.Round(knob, 9)

	local function refresh()
		local v = Settings.Get(entry.Key)
		local t = (v - entry.Min) / (entry.Max - entry.Min)
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.fromScale(t, 0.5)
		value.Text = Widgets.Fmt(entry, v)
	end
	local function setFromX(x)
		local t = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		Settings.Set(entry.Key, entry.Min + t * (entry.Max - entry.Min)) -- Settings snaps to the step
		refresh()
	end
	hit.InputBegan:Connect(function(input)
		local ut = input.UserInputType
		if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
			local scroller = hit:FindFirstAncestorOfClass("ScrollingFrame")
			if scroller then scroller.ScrollingEnabled = false end -- don't scroll the list while dragging
			drag = { Input = input, Apply = setFromX, Scroller = scroller }
			setFromX(input.Position.X)
		end
	end)
	Widgets.Selectable(hit, function(dir)
		Settings.Set(entry.Key, Settings.Get(entry.Key) + dir * (entry.Step or 1))
		refresh()
	end)
	refresh()
	return { Row = row, Refresh = refresh }
end

-- ---------------------------------------------------------------- toggle
function Widgets.Toggle(parent, entry, order)
	local row, right = Widgets.Row(parent, entry.Label, entry.Desc, order)
	local pill = Instance.new("TextButton")
	pill.Text, pill.AutoButtonColor = "", false
	pill.Size, pill.Position, pill.AnchorPoint = UDim2.fromOffset(64, 30), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5)
	pill.BorderSizePixel = 0
	Theme.Round(pill, 15)
	Theme.Stroke(pill, Theme.Dim, 1, 0.6)
	pill.Parent = right
	local knob = Theme.Frame(pill, UDim2.fromOffset(22, 22), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5), Theme.Text, 0)
	Theme.Round(knob, 11)
	local label = Theme.Label(right, "", 14, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -74, 0, 0), UDim2.fromOffset(80, 36), Vector2.new(1, 0))

	local function refresh()
		local on = Settings.Get(entry.Key)
		pill.BackgroundColor3 = on and Theme.Accent or C0
		pill.BackgroundTransparency = on and 0 or 0.4
		knob.Position = on and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
		knob.BackgroundColor3 = on and Color3.fromRGB(20, 20, 20) or Theme.Text
		label.Text = on and "ON" or "OFF"
		label.TextColor3 = on and Theme.Accent or Theme.Dim
	end
	pill.Activated:Connect(function()
		Settings.Set(entry.Key, not Settings.Get(entry.Key))
		refresh()
	end)
	Widgets.Selectable(pill)
	refresh()
	return { Row = row, Refresh = refresh }
end

-- ---------------------------------------------------------------- choice (< value >)
function Widgets.Choice(parent, entry, order)
	local row, right = Widgets.Row(parent, entry.Label, entry.Desc, order)
	local function cycle(dir)
		local i = table.find(entry.Options, Settings.Get(entry.Key)) or 1
		Settings.Set(entry.Key, entry.Options[(i - 1 + dir) % #entry.Options + 1])
	end
	local mid = flatButton(right, "", UDim2.fromOffset(176, 34), UDim2.new(1, -40, 0.5, 0), Vector2.new(1, 0.5))
	mid.TextColor3 = Theme.Text
	local function arrow(text, x, dir)
		local b = flatButton(right, text, UDim2.fromOffset(34, 34), UDim2.new(1, x, 0.5, 0), Vector2.new(1, 0.5))
		b.TextColor3, b.TextSize = Theme.Accent, 20
		b.Activated:Connect(function() cycle(dir) end)
	end
	arrow("<", -218, -1)
	arrow(">", 0, 1)
	local function refresh() mid.Text = tostring(Settings.Get(entry.Key)):upper() end
	mid.Activated:Connect(function() cycle(1) end)
	Widgets.Selectable(mid, function(dir) cycle(dir) end)
	local conn
	conn = Settings.OnChanged(function(key)
		if not mid.Parent then conn.Disconnect() return end -- page was rebuilt
		if key == entry.Key or key == "All" then refresh() end
	end)
	refresh()
	return { Row = row, Refresh = refresh }
end

-- ---------------------------------------------------------------- action button row
function Widgets.ActionRow(parent, label, desc, buttonText, order, fn)
	local row, right = Widgets.Row(parent, label, desc, order)
	local b = flatButton(right, buttonText, UDim2.fromOffset(200, 36), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5), true)
	b.Activated:Connect(fn)
	return { Row = row, Refresh = function() end }
end

-- build the right widget for a schema entry
function Widgets.FromEntry(parent, entry, order)
	if entry.Type == "Slider" then return Widgets.Slider(parent, entry, order)
	elseif entry.Type == "Toggle" then return Widgets.Toggle(parent, entry, order)
	elseif entry.Type == "Choice" then return Widgets.Choice(parent, entry, order)
	elseif entry.Type == "Header" then
		Widgets.Header(parent, entry.Label, order)
		return { Refresh = function() end }
	end
	return nil
end

-- ---------------------------------------------------------------- scaled root: design in "design units", fit to any screen
-- Returns root (a Frame that always covers the screen, children are laid out in design units) and a function that re-fits it.
-- refHeight = design height for this device (touch devices use a smaller one so text stays readable on phones).
function Widgets.ScaledRoot(gui, refHeight, userScaleKey)
	local root = Instance.new("Frame")
	root.BackgroundTransparency, root.BorderSizePixel = 1, 0
	local ui = Instance.new("UIScale")
	ui.Parent = root
	root.Parent = gui
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local ref = typeof(refHeight) == "function" and refHeight() or refHeight
		local s = math.clamp(vp.Y / ref, 0.45, 2) * (userScaleKey and Settings.Get(userScaleKey) / 100 or 1)
		ui.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
	Settings.OnChanged(function(key)
		if key == userScaleKey or key == "All" then fit() end
	end)
	return root, fit
end

return Widgets
