-- MainMenu: full-screen front end. Top tabs (Deploy / Armory / Cosmetics / Career / Battle Pass / Store / Settings), content below, hint bar at the bottom.
-- Settings is complete; the other tabs are placeholders with a registry (MainMenu.RegisterPage) so each can be replaced with a real page.
-- Works with mouse, touch and gamepad (LB / RB = next / previous tab, B = back).
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local Widgets = require(script.Parent.Widgets)
local SettingsMenu = require(script.Parent.SettingsMenu)

local MainMenu = {}
MainMenu.__index = MainMenu

local GAME_NAME = "CODFPS" -- placeholder wordmark
local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local C0 = Color3.new()

-- ---------------------------------------------------------------- page registry
-- A page builder is function(holder: Frame, menu) -> { Show = fn?, Hide = fn?, Back = fn? (return true if handled), Focus = fn? }
local registry = {}
local order = { "DEPLOY", "ARMORY", "COSMETICS", "CAREER", "BATTLE PASS", "STORE", "SETTINGS" }
local widths = { DEPLOY = 112, ARMORY = 112, COSMETICS = 140, CAREER = 112, ["BATTLE PASS"] = 156, STORE = 100, SETTINGS = 126 }

function MainMenu.RegisterPage(title, builder)
	registry[title] = builder
	if not table.find(order, title) then table.insert(order, title) end
end

local function placeholder(title, lines, buttonText, onButton)
	return function(holder, menu)
		local p = Theme.Glass(holder, UDim2.fromScale(1, 1))
		p.BackgroundTransparency = 0.25
		Theme.Label(p, title, 38, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(32, 24), UDim2.fromOffset(500, 50))
		Theme.Label(p, "COMING NEXT", 13, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(34, 74), UDim2.fromOffset(300, 18))
		local body = Theme.Label(p, table.concat(lines, "\n\n"), 17, Theme.Dim, LEFT, Theme.Body, UDim2.fromOffset(34, 108), UDim2.new(1, -68, 0, 220))
		body.TextWrapped, body.TextYAlignment = true, Enum.TextYAlignment.Top
		local page = {}
		if buttonText then
			local b = Widgets.FlatButton(p, buttonText, UDim2.fromOffset(220, 48), UDim2.new(1, -32, 1, -28), Vector2.new(1, 1), true)
			b.TextSize = 20
			b.Activated:Connect(function() onButton(menu) end)
			page.Focus = function() GuiService.SelectedObject = b end
		end
		return page
	end
end

registry["DEPLOY"] = placeholder("DEPLOY", {
	"Map and mode voting lives here: Team Deathmatch, Free For All, Hardcore Team Deathmatch, Down and Out, Extraction and DMZ.",
	"For now this button drops you straight into the match.",
}, "DEPLOY", function(menu) menu:Deploy() end)

-- ARMORY is built by ArmoryPage (ArmoryPage.Register(MainMenu) before MainMenu.new); this placeholder is only a fallback
registry["ARMORY"] = placeholder("ARMORY", { "Classes, gunsmith, perks, equipment and kill streaks." })

registry["COSMETICS"] = placeholder("COSMETICS", { "Banners, operators, tracers, player cards and more." })
registry["BATTLE PASS"] = placeholder("BATTLE PASS", { "Seasonal tiers, free and premium rewards, and challenges." })
registry["STORE"] = placeholder("STORE", { "Currency purchases and bundles." })

registry["SETTINGS"] = function(holder, menu)
	local sm = SettingsMenu.new(holder, { EditTouch = function() menu:EditTouchLayout() end })
	return {
		Show = function() sm:Show() end,
		Hide = function() sm:Hide() end,
		Back = function() return sm:Back() end,
		Focus = function() sm:FocusNav() end,
	}
end

-- ---------------------------------------------------------------- construction
-- opts: OnToggle(open), OnDeploy(), EditTouch(onClose)
function MainMenu.new(opts)
	local self = setmetatable({}, MainMenu)
	self.Opts, self.IsOpen, self.Hidden, self.Current = opts or {}, false, false, "DEPLOY"
	self.Pages, self.Holders, self.TabButtons = {}, {}, {}

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled = "MainMenu", false, true, 50, false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = gui

	local back = Theme.Frame(gui, UDim2.fromScale(1, 1), nil, nil, Color3.fromRGB(8, 10, 12), 0.12)
	back.Active = true -- swallow clicks so nothing behind the menu is hit
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.35) })
	grad.Parent = back

	-- touch phones are short and wide: design for a shorter screen so text stays readable
	local root, fit = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 760 end, "Interface.Scale")
	self.Root, self.Fit = root, fit
	InputMap.OnDeviceChanged(function() if self.Fit then self.Fit() end end)

	-- top bar
	local top = Theme.Frame(root, UDim2.new(1, 0, 0, 64), nil, nil, C0, 0.35)
	Theme.Frame(top, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), nil, Theme.Accent, 0.55)
	Theme.Label(top, GAME_NAME, 30, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(28, 0), UDim2.fromOffset(190, 64))
	local tabs = Theme.Frame(top, UDim2.new(1, -520, 1, 0), UDim2.fromOffset(220, 0), nil, C0, 1)
	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection, tabList.Padding, tabList.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 4), Enum.SortOrder.LayoutOrder
	tabList.VerticalAlignment = Enum.VerticalAlignment.Center
	tabList.Parent = tabs
	for i, title in order do
		local b = Instance.new("TextButton")
		b.AutoButtonColor, b.Text, b.LayoutOrder, b.BorderSizePixel = false, "", i, 0
		b.Size, b.BackgroundTransparency = UDim2.fromOffset(widths[title] or 120, 44), 1
		local label = Theme.Label(b, title, 17, Theme.Dim, CENTER, Theme.Display)
		local line = Theme.Frame(b, UDim2.new(1, -16, 0, 3), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1), Theme.Accent, 1)
		b.Parent = tabs
		Widgets.Selectable(b)
		b.Activated:Connect(function() self:Select(title) end)
		self.TabButtons[title] = { Button = b, Label = label, Line = line }
	end
	self.LevelLbl = Theme.Label(top, "", 17, Theme.Text, RIGHT, Theme.Display, UDim2.new(1, -28, 0, 10), UDim2.fromOffset(260, 22), Vector2.new(1, 0))
	self.CreditLbl = Theme.Label(top, "", 13, Theme.Accent, RIGHT, Theme.Display, UDim2.new(1, -28, 0, 34), UDim2.fromOffset(260, 18), Vector2.new(1, 0))
	self:SetCurrency(0)

	-- content + bottom bar
	self.Content = Theme.Frame(root, UDim2.new(1, -56, 1, -64 - 22 - 44), UDim2.fromOffset(28, 78), nil, C0, 1)
	local bottom = Theme.Frame(root, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), C0, 0.45)
	self.Hint = Theme.Label(bottom, "", 14, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(28, 0), UDim2.new(1, -56, 1, 0))
	local function hint()
		local d = InputMap.Device
		if d == "PAD" then self.Hint.Text = "A  SELECT      B  BACK      LB / RB  SWITCH TAB"
		elseif d == "Touch" then self.Hint.Text = ""
		else self.Hint.Text = ("%s  CLOSE MENU"):format(InputMap.Label("Menu", "KBM")) end
	end
	hint()
	InputMap.OnDeviceChanged(hint)
	InputMap.OnBindingsChanged(hint)

	-- menu key toggles; gamepad LB / RB / B
	InputMap.OnBegan("Menu", function() self:Toggle() end)
	UIS.InputBegan:Connect(function(input)
		if not self.IsOpen or self.Hidden or InputMap.IsCapturing() then return end
		local kc = input.KeyCode
		if input.UserInputType.Name:sub(1, 7) ~= "Gamepad" then return end
		if kc == Enum.KeyCode.ButtonR1 then self:Step(1)
		elseif kc == Enum.KeyCode.ButtonL1 then self:Step(-1)
		elseif kc == Enum.KeyCode.ButtonB then self:Back() end
	end)

	self:Select(self.Current, true)
	return self
end

-- ---------------------------------------------------------------- pages
function MainMenu:Select(title, silent)
	local builder = registry[title]
	if not builder then return end
	local old = self.Pages[self.Current]
	if old and old.Hide and self.Current ~= title then old.Hide() end
	self.Current = title
	for t, b in self.TabButtons do
		local on = t == title
		b.Label.TextColor3 = on and Theme.Text or Theme.Dim
		b.Line.BackgroundTransparency = on and 0 or 1
	end
	for t, holder in self.Holders do holder.Visible = t == title end
	if not self.Holders[title] then
		local holder = Theme.Frame(self.Content, UDim2.fromScale(1, 1), nil, nil, C0, 1)
		self.Holders[title] = holder
		self.Pages[title] = builder(holder, self) or {}
		for t, h in self.Holders do h.Visible = t == title end
	end
	local page = self.Pages[title]
	if page.Show and not silent then page.Show() end
	if not silent and InputMap.Device == "PAD" and self.IsOpen then
		if page.Focus then page.Focus() else GuiService.SelectedObject = self.TabButtons[title].Button end
	end
end

function MainMenu:Step(dir)
	local i = table.find(order, self.Current) or 1
	self:Select(order[(i - 1 + dir) % #order + 1])
end

function MainMenu:Back()
	local page = self.Pages[self.Current]
	if page and page.Back and page.Back() then return end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(self.Holders[self.Current]) and self.TabButtons[self.Current] then
		GuiService.SelectedObject = self.TabButtons[self.Current].Button -- first back press: up to the tab bar
		return
	end
	self:Close()
end

-- ---------------------------------------------------------------- open / close
function MainMenu:Open(title)
	if self.IsOpen then
		if title then self:Select(title) end
		return
	end
	self.IsOpen = true
	self.Gui.Enabled = true
	InputMap.SetEnabled(false)
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	UIS.MouseIconEnabled = true
	self:Select(title or self.Current)
	if self.Opts.OnToggle then self.Opts.OnToggle(true) end
end

function MainMenu:Close()
	if not self.IsOpen then return end
	local page = self.Pages[self.Current]
	if page and page.Hide then page.Hide() end
	Settings.Flush()
	self.IsOpen, self.Hidden = false, false
	self.Gui.Enabled = false
	GuiService.SelectedObject = nil
	InputMap.SetEnabled(true)
	if self.Opts.OnToggle then self.Opts.OnToggle(false) end
end

function MainMenu:Toggle()
	if self.IsOpen then self:Close() else self:Open() end
end

function MainMenu:Deploy()
	self:Close()
	if self.Opts.OnDeploy then self.Opts.OnDeploy() end
end

-- hide the menu without "closing" it (the touch layout editor is shown on top of the game instead)
function MainMenu:SetHidden(hidden)
	self.Hidden = hidden
	self.Gui.Enabled = self.IsOpen and not hidden
end

function MainMenu:EditTouchLayout()
	if not self.Opts.EditTouch then return end
	self:SetHidden(true)
	self.Opts.EditTouch(function()
		self:SetHidden(false)
		self:Select("SETTINGS")
	end)
end

-- ---------------------------------------------------------------- header info
function MainMenu:SetProfile(summary)
	if summary then
		self.LevelLbl.Text = ("LEVEL %d"):format(summary.Level or 1)
		if summary.Credits then self:SetCurrency(summary.Credits) end
	end
end

function MainMenu:SetCurrency(amount)
	local text = tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	self.CreditLbl.Text = "CREDITS  " .. text:gsub("^,", "")
end

return MainMenu
