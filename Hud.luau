-- In-game HUD: compass strip, crosshair + hitmarker, health / armor plates / perks (bottom left), ammo + weapon + equipment (bottom right),
-- progress bar, toasts, directional damage indicators, scope overlay and full-screen status overlays.
local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.Config)
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local Armory = require(script.Parent.Armory)

local Hud = {}
Hud.__index = Hud

local LEFT, RIGHT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local C = Vector2.new(0.5, 0.5)
local PLATE_W, PLATE_GAP = 92, 6

local function tween(obj, t, props)
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

function Hud.new(player)
	local self = setmetatable({}, Hud)
	local screen = Instance.new("ScreenGui")
	screen.Name, screen.ResetOnSpawn, screen.IgnoreGuiInset, screen.Enabled, screen.DisplayOrder = "FPSHud", false, true, false, 5
	screen.Parent = player:WaitForChild("PlayerGui")
	-- everything lives in a root frame so the whole HUD can be scaled (Interface.HudScale + automatic phone scaling)
	local gui = Instance.new("Frame")
	gui.Name, gui.BackgroundTransparency, gui.BorderSizePixel = "Root", 1, 0
	local ui = Instance.new("UIScale")
	ui.Parent = gui
	gui.Parent = screen
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		local s = Settings.AutoScale(vp, 900, 0.5, 1.1) * Settings.Get("Interface.HudScale") / 100
		ui.Scale = s
		gui.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
	Settings.OnChanged(function(key)
		if key == "Interface.HudScale" or key == "All" then fit() end
		if key:sub(1, 10) == "Interface." or key == "All" then self:ApplySettings() end
	end)
	InputMap.OnBindingsChanged(function() self:RefreshKeys() end)
	InputMap.OnDeviceChanged(function() self:RefreshKeys() end)
	task.defer(function()
		self:ApplySettings()
		self:RefreshKeys()
	end)
	self.Screen, self.Gui = screen, gui

	-- ---------------------------------------------------------------- crosshair + hitmarker
	self.Cross = {}
	local function line(name, w, h, anchor)
		local f = Theme.Frame(gui, UDim2.fromOffset(w, h), UDim2.fromScale(0.5, 0.5), anchor, Theme.Text)
		Theme.Stroke(f, Color3.new(0, 0, 0), 1, 0.5)
		self.Cross[name] = f
	end
	line("Top", 2, 9, Vector2.new(0.5, 1))
	line("Bottom", 2, 9, Vector2.new(0.5, 0))
	line("Left", 9, 2, Vector2.new(1, 0.5))
	line("Right", 9, 2, Vector2.new(0, 0.5))
	line("Dot", 3, 3, C)

	local hit = Instance.new("Frame")
	hit.Size, hit.AnchorPoint, hit.Position, hit.BackgroundTransparency, hit.Visible = UDim2.fromOffset(44, 44), C, UDim2.fromScale(0.5, 0.5), 1, false
	hit.Parent = gui
	self.HitScale = Instance.new("UIScale")
	self.HitScale.Parent = hit
	for _, d in { { -1, -1, 45 }, { 1, -1, -45 }, { -1, 1, -45 }, { 1, 1, 45 } } do
		local t = Theme.Frame(hit, UDim2.fromOffset(10, 2), UDim2.new(0.5, d[1] * 11, 0.5, d[2] * 11), C, Theme.Text)
		t.Rotation = d[3]
	end
	self.Hit, self.HitToken = hit, 0

	-- ---------------------------------------------------------------- compass
	local comp = Theme.Frame(gui, UDim2.fromOffset(420, 28), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0), Theme.Panel, 0.55)
	comp.ClipsDescendants = true
	Theme.Round(comp, 4)
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = comp
	self.CompassItems = {}
	local names = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
	for deg = 0, 345, 15 do
		local nm = names[deg]
		if nm then
			local l = Theme.Label(comp, nm, nm:len() == 1 and 17 or 12, nm == "N" and Theme.Accent or Theme.Text, CENTER, Theme.Display, UDim2.new(0, 0, 0.5, -1), UDim2.fromOffset(30, 20), C)
			table.insert(self.CompassItems, { Obj = l, Deg = deg, Text = true })
		else
			local t = Theme.Frame(comp, UDim2.fromOffset(1, 6), UDim2.new(0, 0, 1, -3), Vector2.new(0.5, 1), Theme.Dim)
			table.insert(self.CompassItems, { Obj = t, Deg = deg })
		end
	end
	local mark = Theme.Label(gui, "▼", 11, Theme.Accent, CENTER, Theme.Body, UDim2.new(0.5, 0, 0, 40), UDim2.fromOffset(20, 12), Vector2.new(0.5, 0))
	self.HeadingLbl = Theme.Label(gui, "000", 13, Theme.Text, CENTER, Theme.Display, UDim2.new(0.5, 0, 0, 52), UDim2.fromOffset(60, 16), Vector2.new(0.5, 0))
	mark.TextStrokeTransparency = 0.4
	self.CompassMark = mark
	self.Compass = comp

	-- ---------------------------------------------------------------- bottom-left: perks, plates, health
	local left = Theme.Frame(gui, UDim2.fromOffset(300, 150), UDim2.new(0, 40, 1, -34), Vector2.new(0, 1), Color3.new(), 1)
	self.PerkChips = {}
	for i = 1, 3 do
		local chip = Theme.Frame(left, UDim2.fromOffset(94, 16), UDim2.fromOffset((i - 1) * 100, 0), nil, Color3.new(), 0.45)
		Theme.Round(chip, 3)
		chip.Visible = false
		local t = Theme.Label(chip, "", 10, Theme.Dim, CENTER, Theme.Display)
		self.PerkChips[i] = { Frame = chip, Label = t }
	end

	self.PlateBars, self.PlateBase = {}, {}
	for i = 1, Config.Armor.MaxEquipped do
		local back = Theme.Frame(left, UDim2.fromOffset(PLATE_W, 12), UDim2.fromOffset((i - 1) * (PLATE_W + PLATE_GAP), 26), nil, Color3.new(), 0.45)
		Theme.Round(back, 3)
		Theme.Stroke(back, Theme.Plate, 1, 0.65)
		local fill = Theme.Frame(back, UDim2.fromScale(0, 1), UDim2.new(), nil, Theme.Plate)
		Theme.Round(fill, 3)
		self.PlateBars[i] = fill
	end
	self.PlateLbl = Theme.Label(left, "", 12, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(0, 42), UDim2.fromOffset(300, 16))
	self.HpLbl = Theme.Label(left, "150", 46, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(0, 58), UDim2.fromOffset(120, 50))
	Theme.Label(left, "HP", 14, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(86, 82), UDim2.fromOffset(40, 20))
	local hpBack = Theme.Frame(left, UDim2.fromOffset(PLATE_W * 3 + PLATE_GAP * 2, 8), UDim2.fromOffset(0, 112), nil, Color3.new(), 0.45)
	Theme.Round(hpBack, 3)
	Theme.Stroke(hpBack, Theme.Dim, 1, 0.7)
	self.HpBar = Theme.Frame(hpBack, UDim2.fromScale(1, 1), UDim2.new(), nil, Theme.Text)
	Theme.Round(self.HpBar, 3)

	-- ---------------------------------------------------------------- bottom-right: equipment, weapon, ammo
	local right = Theme.Frame(gui, UDim2.fromOffset(340, 168), UDim2.new(1, -40, 1, -34), Vector2.new(1, 1), Color3.new(), 1)
	self.DetLbl = Theme.Label(right, "", 12, Theme.Accent, RIGHT, Theme.Display, UDim2.fromOffset(0, 0), UDim2.fromOffset(340, 16))
	self.Slots = {}
	for i, key in { "Tactical", "Lethal" } do
		local slot = Theme.Glass(right, UDim2.fromOffset(92, 54), UDim2.new(1, -(i - 1) * 100, 0, 18), Vector2.new(1, 0))
		local chip = Theme.Chip(slot, InputMap.Label(key), UDim2.fromOffset(22, 16), UDim2.fromOffset(6, 6))
		local keyText = chip:FindFirstChildOfClass("TextLabel")
		keyText.TextScaled = true
		self.KeyChips = self.KeyChips or {}
		self.KeyChips[key] = keyText
		local name = Theme.Label(slot, "", 15, Theme.Text, CENTER, Theme.Display, UDim2.new(0, 4, 0, 18), UDim2.new(1, -8, 0, 22))
		name.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize, lim.MinTextSize = 15, 8
		lim.Parent = name
		local pips = {}
		for p = 1, 4 do
			local pip = Theme.Frame(slot, UDim2.fromOffset(10, 4), UDim2.new(1, -6 - (p - 1) * 13, 1, -8), Vector2.new(1, 1), Theme.Accent)
			Theme.Round(pip, 1)
			pips[p] = pip
		end
		self.Slots[key] = { Frame = slot, Name = name, Pips = pips, KeyText = keyText }
	end
	self.ModeChip = Theme.Frame(right, UDim2.fromOffset(60, 18), UDim2.fromOffset(0, 82), nil, Color3.new(), 0.35)
	Theme.Round(self.ModeChip, 3)
	Theme.Stroke(self.ModeChip, Theme.Dim, 1, 0.6)
	self.ModeLbl = Theme.Label(self.ModeChip, "", 11, Theme.Dim, CENTER, Theme.Display)
	self.NameLbl = Theme.Label(right, "", 22, Theme.Text, RIGHT, Theme.Display, UDim2.fromOffset(70, 78), UDim2.fromOffset(270, 26))
	self.AmmoLbl = Theme.Label(right, "", 20, Theme.Text, RIGHT, Theme.Display, UDim2.fromOffset(0, 100), UDim2.fromOffset(340, 56))
	local magBack = Theme.Frame(right, UDim2.fromOffset(340, 4), UDim2.fromOffset(0, 160), nil, Color3.new(), 0.45)
	Theme.Round(magBack, 2)
	self.MagBar = Theme.Frame(magBack, UDim2.fromScale(1, 1), UDim2.new(), nil, Theme.Text)
	Theme.Round(self.MagBar, 2)

	-- ---------------------------------------------------------------- hints / progress / toast / debug
	self.HintLbl = Theme.Label(gui, "", 18, Theme.Warn, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.6), UDim2.fromOffset(300, 24), C)
	local pback = Theme.Frame(gui, UDim2.fromOffset(260, 8), UDim2.fromScale(0.5, 0.66), C, Color3.new(), 0.45)
	Theme.Round(pback, 4)
	Theme.Stroke(pback, Theme.Dim, 1, 0.7)
	pback.Visible = false
	self.ProgBack = pback
	self.ProgBar = Theme.Frame(pback, UDim2.fromScale(0, 1), UDim2.new(), nil, Theme.Text)
	Theme.Round(self.ProgBar, 4)
	self.ProgLbl = Theme.Label(gui, "", 15, Theme.Text, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.66), UDim2.fromOffset(300, 20), Vector2.new(0.5, 1.8))
	self.ToastLbl = Theme.Label(gui, "", 20, Theme.Text, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.74), UDim2.fromOffset(400, 28), C)
	self.ToastLbl.TextTransparency, self.ToastToken = 1, 0
	self.DebugLbl = Theme.Label(gui, "", 13, Theme.Dim, LEFT, Theme.Body, UDim2.fromOffset(16, 70), UDim2.fromOffset(300, 20))

	-- ---------------------------------------------------------------- XP bar (bottom center), score feed, medal banner
	local xp = Theme.Frame(gui, UDim2.fromOffset(340, 36), UDim2.new(0.5, 0, 1, -20), Vector2.new(0.5, 1), Color3.new(), 1)
	self.LevelLbl = Theme.Label(xp, "LV 1", 16, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 20))
	self.XPLbl = Theme.Label(xp, "", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.fromOffset(120, 2), UDim2.fromOffset(220, 18))
	local xpBack = Theme.Frame(xp, UDim2.fromOffset(340, 5), UDim2.fromOffset(0, 24), nil, Color3.new(), 0.45)
	Theme.Round(xpBack, 2)
	self.XPFill = Theme.Frame(xpBack, UDim2.fromScale(0, 1), nil, nil, Theme.Accent)
	Theme.Round(self.XPFill, 2)

	-- ---------------------------------------------------------------- kill streak chips (above the XP bar)
	local streaks = Theme.Frame(gui, UDim2.fromOffset(3 * 104 + 2 * 6, 46), UDim2.new(0.5, 0, 1, -64), Vector2.new(0.5, 1), Color3.new(), 1)
	streaks.Visible = false
	self.StreakFrame, self.StreakChips = streaks, {}
	self.KeyChips = self.KeyChips or {}
	for i = 1, 3 do
		local f = Theme.Glass(streaks, UDim2.fromOffset(104, 46), UDim2.fromOffset((i - 1) * 110, 0))
		local stroke = f:FindFirstChildOfClass("UIStroke")
		local chip = Theme.Chip(f, InputMap.Label("Streak" .. i), UDim2.fromOffset(22, 16), UDim2.fromOffset(5, 5))
		local keyText = chip:FindFirstChildOfClass("TextLabel")
		keyText.TextScaled = true
		self.KeyChips["Streak" .. i] = keyText
		local name = Theme.Label(f, "", 13, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(28, 3), UDim2.new(1, -32, 0, 20))
		name.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize, lim.MinTextSize = 13, 8
		lim.Parent = name
		local state = Theme.Label(f, "", 11, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(4, 24), UDim2.new(1, -8, 0, 12))
		local back = Theme.Frame(f, UDim2.new(1, -12, 0, 3), UDim2.new(0, 6, 1, -7), nil, Color3.new(), 0.45)
		local fill = Theme.Frame(back, UDim2.fromScale(0, 1), nil, nil, Theme.Accent)
		self.StreakChips[i] = { Frame = f, Stroke = stroke, Name = name, State = state, Fill = fill, Back = back }
	end

	self.Feed = Theme.Frame(gui, UDim2.fromOffset(260, 130), UDim2.new(0.5, 70, 0.5, -10), nil, Color3.new(), 1)
	local list = Instance.new("UIListLayout")
	list.SortOrder, list.Padding = Enum.SortOrder.LayoutOrder, UDim.new(0, 2)
	list.Parent = self.Feed
	self.FeedOrder = 0

	self.BannerLbl = Theme.Label(gui, "", 44, Theme.Accent, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.22), UDim2.fromOffset(600, 52), C)
	self.BannerSub = Theme.Label(gui, "", 18, Theme.Text, CENTER, Theme.Display, UDim2.new(0.5, 0, 0.22, 34), UDim2.fromOffset(400, 22), C)
	self.BannerLbl.TextTransparency, self.BannerSub.TextTransparency, self.BannerToken = 1, 1, 0
	self.BannerScale = Instance.new("UIScale")
	self.BannerScale.Parent = self.BannerLbl

	-- ---------------------------------------------------------------- downed screen + interaction prompt
	local down = Theme.Frame(gui, UDim2.fromScale(1, 1), nil, nil, Color3.fromRGB(110, 0, 0), 0.82)
	down.Visible, down.ZIndex = false, 8
	self.DownFrame = down
	Theme.Label(down, "YOU ARE DOWN", 46, Theme.Danger, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.36), UDim2.fromOffset(600, 56), C)
	Theme.Label(down, "Stay alive until a teammate revives you. Shoot with your sidearm.", 16, Theme.Text, CENTER, Theme.Body, UDim2.new(0.5, 0, 0.36, 40), UDim2.fromOffset(600, 22), C)
	local dback = Theme.Frame(down, UDim2.fromOffset(320, 8), UDim2.fromScale(0.5, 0.46), C, Color3.new(), 0.4)
	Theme.Round(dback, 4)
	self.DownFill = Theme.Frame(dback, UDim2.fromScale(1, 1), nil, nil, Theme.Danger)
	Theme.Round(self.DownFill, 4)
	self.PromptLbl = Theme.Label(gui, "", 18, Theme.Text, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.7), UDim2.fromOffset(500, 24), C)

	-- ---------------------------------------------------------------- overlays + scope
	local function overlay(color)
		local f = Theme.Frame(gui, UDim2.fromScale(1, 1), UDim2.new(), nil, color, 1)
		f.ZIndex = 20
		return f
	end
	self.Overlays = {
		Flash = overlay(Color3.new(1, 1, 1)), Stun = overlay(Color3.fromRGB(30, 30, 40)),
		Gas = overlay(Color3.fromRGB(120, 170, 60)), Damage = overlay(Color3.fromRGB(190, 0, 0)),
	}
	local scope = Instance.new("Frame")
	scope.Size, scope.BackgroundTransparency, scope.Visible, scope.ZIndex = UDim2.fromScale(1, 1), 1, false, 10
	scope.Parent = gui
	self.Scope, self.ScopeBuilt = scope, Vector2.zero
	self.PrevArmor = 0
	return self
end

function Hud:SetEnabled(on) self.Screen.Enabled = on end
function Hud:SetDebug(t) self.DebugLbl.Text = t or "" end

-- ---------------------------------------------------------------- compass
function Hud:SetCompass(look)
	local heading = math.deg(math.atan2(look.X, -look.Z)) % 360
	self.HeadingLbl.Text = ("%03d"):format(math.floor(heading + 0.5) % 360)
	for _, it in self.CompassItems do
		local rel = ((it.Deg - heading + 540) % 360) - 180
		local fade = math.clamp((math.abs(rel) - 55) / 40, 0, 1)
		it.Obj.Position = UDim2.new(0, 210 + rel * 2.2, it.Text and 0.5 or 1, it.Text and -1 or -3)
		it.Obj.Visible = math.abs(rel) < 95
		if it.Text then it.Obj.TextTransparency = fade else it.Obj.BackgroundTransparency = fade end
	end
end

-- ---------------------------------------------------------------- weapon / ammo
function Hud:SetAmmo(ammo, reserve, name, melee, mode, magSize)
	self.NameLbl.Text = Theme.Spaced(name or "")
	self.ModeLbl.Text = mode or ""
	self.ModeChip.Visible = (mode or "") ~= ""
	if melee then
		self.AmmoLbl.Text, self.HintLbl.Text = "", ""
		self.MagBar.Parent.Visible = false
		return
	end
	self.MagBar.Parent.Visible = true
	local frac = magSize and magSize > 0 and ammo / magSize or 1
	local low = frac <= 0.25
	local col = ammo == 0 and Theme.Danger or (low and Theme.Warn or Theme.Text)
	self.AmmoLbl.Text = ('<font size="62" color="rgb(%d,%d,%d)">%d</font><font size="24" color="rgb(150,158,166)"> / %d</font>')
		:format(math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5), ammo, reserve)
	self.MagBar.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	self.MagBar.BackgroundColor3 = col
	if ammo == 0 then
		self.HintLbl.Text = reserve > 0 and ("RELOAD  [R]") or "NO AMMO"
		self.HintLbl.TextColor3 = reserve > 0 and Theme.Warn or Theme.Danger
	elseif low and reserve > 0 then
		self.HintLbl.Text, self.HintLbl.TextColor3 = "LOW AMMO", Theme.Warn
	else
		self.HintLbl.Text = ""
	end
end

-- slots: { Label, Count, Max } or nil
function Hud:SetEquip(lethal, tactical, detonatorReady)
	for _, key in { "Lethal", "Tactical" } do
		local info = key == "Lethal" and lethal or tactical
		local s = self.Slots[key]
		s.Frame.Visible = info ~= nil
		if info then
			s.Name.Text = info.Label:upper()
			local empty = info.Count <= 0
			s.Name.TextColor3 = empty and Theme.Dim or Theme.Text
			s.Frame.BackgroundTransparency = empty and 0.6 or Theme.PanelAlpha
			for p, pip in s.Pips do
				pip.Visible = p <= (info.Max or 4)
				pip.BackgroundColor3 = p <= info.Count and Theme.Accent or Theme.Dim
				pip.BackgroundTransparency = p <= info.Count and 0 or 0.7
			end
		end
	end
	local dk = InputMap.Label("Detonate")
	self.DetLbl.Text = detonatorReady and ((dk ~= "" and ("[%s]  "):format(dk) or "") .. "DETONATE") or ""
end

-- ---------------------------------------------------------------- health / armor / perks
function Hud:SetHealth(hp, max)
	local frac = math.clamp(hp / max, 0, 1)
	self.HpLbl.Text = ("%d"):format(math.ceil(hp))
	self.HpBar.Size = UDim2.fromScale(frac, 1)
	local col = Theme.Text
	if frac < 0.3 then
		col = Theme.Text:Lerp(Theme.Danger, 0.55 + 0.45 * math.sin(os.clock() * 8))
	end
	self.HpBar.BackgroundColor3, self.HpLbl.TextColor3 = col, col
end

function Hud:SetArmor(armor, carried)
	local pa = Config.Armor.PlateArmor
	for i, bar in self.PlateBars do
		bar.Size = UDim2.fromScale(math.clamp((armor - (i - 1) * pa) / pa, 0, 1), 1)
		if armor < self.PrevArmor and self.PrevArmor > (i - 1) * pa and armor <= (i - 1) * pa + pa * 0.99 then
			-- plate took damage: flash it
			bar.BackgroundColor3 = Theme.Danger
			tween(bar, 0.45, { BackgroundColor3 = Theme.Plate })
		end
	end
	self.PrevArmor = armor
	local pk = InputMap.Label("Plate")
	self.PlateLbl.Text = ("PLATES  <font color=\"rgb(240,242,244)\">%d</font>   %s"):format(carried, pk ~= "" and ("[" .. pk .. "]") or "")
end

function Hud:SetPerks(list)
	for i, chip in self.PerkChips do
		local n = list and list[i]
		chip.Frame.Visible = n ~= nil
		if n then chip.Label.Text = Theme.Spaced(n) end
	end
end

-- ---------------------------------------------------------------- feedback
-- sync = { Kills = n, Slots = { { Id, Kills, State = "Locked" | "Ready" | "Used" | "Empty" } x3 } } from StreakService
function Hud:SetStreaks(sync)
	local any = false
	for i, c in self.StreakChips do
		local slot = sync and sync.Slots and sync.Slots[i]
		local def = slot and slot.Id ~= "" and Armory.Streaks[slot.Id]
		c.Frame.Visible = def ~= nil
		if def then
			any = true
			c.Name.Text = def.Name:upper()
			local ready, used = slot.State == "Ready", slot.State == "Used"
			c.Stroke.Color, c.Stroke.Transparency = ready and Theme.Accent or Theme.Dim, ready and 0.05 or 0.75
			c.Stroke.Thickness = ready and 2 or 1
			c.Name.TextColor3 = (ready and Theme.Accent) or (used and Theme.Dim) or Theme.Text
			if ready then
				c.State.Text, c.State.TextColor3 = "READY", Theme.Accent
			elseif used then
				c.State.Text, c.State.TextColor3 = "USED", Theme.Dim
			else
				c.State.Text, c.State.TextColor3 = ("%d / %d KILLS"):format(math.min(sync.Kills, def.Kills), def.Kills), Theme.Dim
			end
			c.Fill.Size = UDim2.fromScale(ready and 1 or (used and 0 or math.clamp(sync.Kills / def.Kills, 0, 1)), 1)
			c.Fill.BackgroundColor3 = ready and Theme.Accent or Theme.Dim
		end
	end
	self.StreakFrame.Visible = any
end

function Hud:SetProgress(text, alpha, color)
	if alpha == nil then
		self.ProgBack.Visible, self.ProgLbl.Text = false, ""
		return
	end
	self.ProgBack.Visible = true
	self.ProgLbl.Text = text or ""
	self.ProgBar.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	self.ProgBar.BackgroundColor3 = color or Theme.Text
end

function Hud:Toast(text, color)
	self.ToastToken += 1
	local tok = self.ToastToken
	self.ToastLbl.Text, self.ToastLbl.TextColor3, self.ToastLbl.TextTransparency = text, color or Theme.Text, 0
	task.delay(1.4, function()
		if self.ToastToken == tok then tween(self.ToastLbl, 0.4, { TextTransparency = 1 }) end
	end)
end

local CROSS_COLORS = { White = Theme.Text, Amber = Theme.Accent, Green = Theme.Good, Cyan = Theme.Plate, Red = Theme.Danger, Pink = Color3.fromRGB(255, 120, 200) }

-- crosshair + compass options from the settings menu
function Hud:ApplySettings()
	local get = Settings.Get
	local c = self.Cross
	local col = CROSS_COLORS[get("Interface.CrossColor")] or Theme.Text
	local len, th = get("Interface.CrossLength"), get("Interface.CrossThickness")
	c.Top.Size, c.Bottom.Size = UDim2.fromOffset(th, len), UDim2.fromOffset(th, len)
	c.Left.Size, c.Right.Size = UDim2.fromOffset(len, th), UDim2.fromOffset(len, th)
	for _, f in c do f.BackgroundColor3 = col end
	c.Dot.Visible = get("Interface.CrossDot")
	self.CrossOpacity, self.CrossShown = get("Interface.CrossOpacity") / 100, get("Interface.Crosshair")
	local compass = get("Interface.Compass")
	self.Compass.Visible, self.CompassMark.Visible, self.HeadingLbl.Visible = compass, compass, compass
end

-- key-cap chips follow the player's bindings and current device (hidden on touch)
function Hud:RefreshKeys()
	for action, label in self.KeyChips or {} do
		label.Text = InputMap.Label(action)
		label.Parent.Visible = label.Text ~= ""
	end
end

function Hud:UpdateCrosshair(gap, transparency)
	local c = self.Cross
	c.Top.Position = UDim2.new(0.5, 0, 0.5, -gap)
	c.Bottom.Position = UDim2.new(0.5, 0, 0.5, gap)
	c.Left.Position = UDim2.new(0.5, -gap, 0.5, 0)
	c.Right.Position = UDim2.new(0.5, gap, 0.5, 0)
	local t = (self.CrossShown == false) and 1 or 1 - (1 - transparency) * (self.CrossOpacity or 1)
	for _, f in c do
		f.BackgroundTransparency = t
		local s = f:FindFirstChildOfClass("UIStroke")
		if s then s.Transparency = 0.5 + 0.5 * t end
	end
end

function Hud:Hitmarker(head, kill)
	if not Settings.Get("Interface.Hitmarkers") then return end
	self.HitToken += 1
	local tok = self.HitToken
	local col = kill and Theme.Danger or (head and Theme.Accent or Theme.Text)
	for _, f in self.Hit:GetChildren() do
		if f:IsA("Frame") then f.BackgroundColor3 = col end
	end
	self.HitScale.Scale = kill and 1.7 or 1.3
	tween(self.HitScale, 0.12, { Scale = 1 })
	self.Hit.Visible = true
	task.delay(kill and 0.28 or 0.13, function() if self.HitToken == tok then self.Hit.Visible = false end end)
end

function Hud:SetDown(on) self.DownFrame.Visible = on end
function Hud:SetDownBar(frac) self.DownFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) end
function Hud:SetPrompt(text) self.PromptLbl.Text = text or "" end

function Hud:SetXP(level, into, needed)
	self.LevelLbl.Text = "LV " .. level
	if needed > 0 then
		self.XPLbl.Text = ("%s / %s XP"):format(tostring(math.floor(into)), tostring(needed))
		tween(self.XPFill, 0.35, { Size = UDim2.fromScale(math.clamp(into / needed, 0, 1), 1) })
	else
		self.XPLbl.Text = "MAX"
		self.XPFill.Size = UDim2.fromScale(1, 1)
	end
end

-- label: "KILL", xp: number, medal: show the big banner
function Hud:ScorePopup(label, xp, medal)
	self.FeedOrder -= 1
	local e = Theme.Label(self.Feed, ('<font color="rgb(255,178,64)">+%d</font>  %s'):format(xp, label), 17, Theme.Text, LEFT, Theme.Display, nil, UDim2.new(1, 0, 0, 20))
	e.LayoutOrder = self.FeedOrder
	task.delay(2.4, function()
		if e.Parent then
			tween(e, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(0.55, function() e:Destroy() end)
		end
	end)
	local kids = self.Feed:GetChildren()
	local entries = {}
	for _, k in kids do if k:IsA("TextLabel") then table.insert(entries, k) end end
	if #entries > 6 then
		table.sort(entries, function(a, b) return a.LayoutOrder > b.LayoutOrder end)
		entries[1]:Destroy()
	end

	if medal then
		self.BannerToken += 1
		local tok = self.BannerToken
		self.BannerLbl.Text, self.BannerSub.Text = label, ("+%d XP"):format(xp)
		self.BannerLbl.TextTransparency, self.BannerSub.TextTransparency = 0, 0
		self.BannerScale.Scale = 1.4
		tween(self.BannerScale, 0.18, { Scale = 1 })
		task.delay(1.6, function()
			if self.BannerToken == tok then
				tween(self.BannerLbl, 0.5, { TextTransparency = 1 })
				tween(self.BannerSub, 0.5, { TextTransparency = 1 })
			end
		end)
	end
end

-- angle: radians, 0 = damage came from straight ahead, positive = from the right
function Hud:DamageIndicator(angle, amount)
	local holder = Theme.Frame(self.Gui, UDim2.fromOffset(300, 300), UDim2.fromScale(0.5, 0.5), C, Color3.new(), 1)
	holder.Rotation = math.deg(angle)
	local bar = Theme.Frame(holder, UDim2.fromOffset(math.clamp(60 + amount, 60, 140), 6), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0), Theme.Danger)
	Theme.Round(bar, 3)
	tween(bar, 1.1, { BackgroundTransparency = 1 })
	task.delay(1.15, function() holder:Destroy() end)
end

function Hud:SetOverlay(name, transparency)
	self.Overlays[name].BackgroundTransparency = math.clamp(transparency, 0, 1)
end

-- ---------------------------------------------------------------- scope
local BANDS = 90
function Hud:_buildScope(vp)
	for _, c in self.Scope:GetChildren() do c:Destroy() end
	local W, H = vp.X, vp.Y
	local R = H * 0.46
	local black = Color3.new(0, 0, 0)
	local function bar(size, pos, anchor)
		return Theme.Frame(self.Scope, size, pos, anchor, black)
	end
	for i = 0, BANDS - 1 do
		local y0, y1 = i / BANDS * H, (i + 1) / BANDS * H
		local dy = (y0 + y1) / 2 - H / 2
		if math.abs(dy) >= R then
			bar(UDim2.fromOffset(W, y1 - y0 + 1), UDim2.fromOffset(0, y0))
		else
			local side = W / 2 - math.sqrt(R * R - dy * dy)
			bar(UDim2.fromOffset(side, y1 - y0 + 1), UDim2.fromOffset(0, y0))
			bar(UDim2.fromOffset(side, y1 - y0 + 1), UDim2.fromOffset(W, y0), Vector2.new(1, 0))
		end
	end
	bar(UDim2.fromOffset(R * 2, 1), UDim2.fromScale(0.5, 0.5), C)
	bar(UDim2.fromOffset(1, R * 2), UDim2.fromScale(0.5, 0.5), C)
	for i = -4, 4 do
		if i ~= 0 then
			bar(UDim2.fromOffset(1, 8), UDim2.new(0.5, 0, 0.5, i * R / 5), C)
			bar(UDim2.fromOffset(8, 1), UDim2.new(0.5, i * R / 5, 0.5, 0), C)
		end
	end
	self.ScopeBuilt = vp
end

function Hud:SetScope(on, viewport)
	if on and viewport ~= self.ScopeBuilt then self:_buildScope(viewport) end
	self.Scope.Visible = on
	self.Compass.Visible = not on
end

return Hud
