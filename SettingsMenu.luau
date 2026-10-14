-- SettingsMenu: category list on the left, schema-driven options on the right, plus the keybind editor.
-- Lives inside whatever Frame the main menu gives it. ctx.EditTouch() opens the mobile layout editor.
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local Widgets = require(script.Parent.Widgets)

local SettingsMenu = {}
SettingsMenu.__index = SettingsMenu

local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local C0 = Color3.new()

local PAGE = {}
for _, p in Settings.Pages do PAGE[p.Id] = p end

function SettingsMenu.new(parent, ctx)
	local self = setmetatable({}, SettingsMenu)
	self.Ctx, self.Current, self.Refreshers = ctx or {}, "Graphics", {}
	self.BindDevice = InputMap.Device == "PAD" and "PAD" or "KBM"

	local root = Theme.Frame(parent, UDim2.fromScale(1, 1), nil, nil, C0, 1)
	self.Root = root

	-- left: categories
	local nav = Instance.new("ScrollingFrame")
	nav.BackgroundTransparency, nav.BorderSizePixel = 1, 0
	nav.Size, nav.Position = UDim2.new(0, 210, 1, 0), UDim2.new()
	nav.ScrollBarThickness, nav.CanvasSize, nav.AutomaticCanvasSize = 0, UDim2.new(), Enum.AutomaticSize.Y
	nav.Parent = root
	local navList = Instance.new("UIListLayout")
	navList.Padding, navList.SortOrder = UDim.new(0, 6), Enum.SortOrder.LayoutOrder
	navList.Parent = nav
	self.NavButtons = {}
	for i, page in Settings.Pages do
		local b = Instance.new("TextButton")
		b.AutoButtonColor, b.Text, b.LayoutOrder = false, "", i
		b.Size, b.BackgroundColor3, b.BackgroundTransparency, b.BorderSizePixel = UDim2.new(1, -6, 0, 46), Theme.Panel, 0.45, 0
		Theme.Round(b, 5)
		local bar = Theme.Frame(b, UDim2.new(0, 4, 1, -12), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5), Theme.Accent, 1)
		Theme.Round(bar, 2)
		local label = Theme.Label(b, page.Title, 16, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(18, 0), UDim2.new(1, -24, 1, 0))
		b.Parent = nav
		Widgets.Selectable(b)
		b.Activated:Connect(function()
			self:Select(page.Id)
			if InputMap.Device == "PAD" then self:FocusContent() end
		end)
		self.NavButtons[page.Id] = { Button = b, Bar = bar, Label = label }
	end

	-- right: options
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
	scroll.Size, scroll.Position = UDim2.new(1, -226, 1, 0), UDim2.fromOffset(226, 0)
	scroll.ScrollBarThickness, scroll.ScrollBarImageColor3 = 5, Theme.Accent
	scroll.CanvasSize, scroll.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = root
	local list = Instance.new("UIListLayout")
	list.Padding, list.SortOrder = UDim.new(0, 6), Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent = scroll
	self.Scroll = scroll

	self.Toast = Theme.Label(root, "", 14, Theme.Accent, CENTER, Theme.Display, UDim2.new(0.5, 113, 1, -6), UDim2.fromOffset(420, 22), Vector2.new(0.5, 1))
	self.Toast.TextTransparency = 1

	-- keep the keybind labels in sync when binds change from elsewhere (controller preset, reset, glyph style)
	Settings.OnChanged(function(key)
		if (key == "Binds" or key == "All" or key == "Interface.Glyphs") and self.BindLabels then self:_refreshBinds() end
	end)

	self:Select(self.Current)
	return self
end

function SettingsMenu:_toast(text)
	self.ToastToken = (self.ToastToken or 0) + 1
	local token = self.ToastToken
	self.Toast.Text, self.Toast.TextTransparency = text, 0
	task.delay(2.2, function()
		if self.ToastToken == token then self.Toast.TextTransparency = 1 end
	end)
end

-- ---------------------------------------------------------------- pages
function SettingsMenu:Select(id)
	if not PAGE[id] then return end
	InputMap.CancelCapture() -- drop any half-finished rebind
	self.Current = id
	for pid, n in self.NavButtons do
		local on = pid == id
		n.Bar.BackgroundTransparency = on and 0 or 1
		n.Label.TextColor3 = on and Theme.Text or Theme.Dim
		n.Button.BackgroundTransparency = on and 0.15 or 0.45
	end
	self:_build(id)
end

function SettingsMenu:_clear()
	for _, c in self.Scroll:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.Refreshers, self.BindLabels = {}, nil
end

function SettingsMenu:_build(id)
	self:_clear()
	local page, order = PAGE[id], 0
	for _, e in page.Entries do
		order += 1
		if e.Type == "Binds" then
			order = self:_buildBinds(order)
		elseif e.Type == "Action" then
			Widgets.ActionRow(self.Scroll, e.Label, e.Desc, e.Button, order, function()
				if e.Id == "TouchEditor" and self.Ctx.EditTouch then self.Ctx.EditTouch() end
			end)
		else
			local w = Widgets.FromEntry(self.Scroll, e, order)
			if w then table.insert(self.Refreshers, w.Refresh) end
		end
	end
	if id ~= "Keybinds" then
		order += 1
		Widgets.ActionRow(self.Scroll, "Reset this page", "Restore the default values for these options.", "RESET", order, function()
			Settings.ResetPage(id)
			self:_build(id)
			self:_toast("DEFAULTS RESTORED")
		end)
	end
	self.Scroll.CanvasPosition = Vector2.zero
end

-- ---------------------------------------------------------------- keybinds
function SettingsMenu:_buildBinds(order)
	local scroll, device = self.Scroll, self.BindDevice
	self.BindLabels = {}

	-- device switch
	order += 1
	local sw = Theme.Frame(scroll, UDim2.new(1, -8, 0, 46), nil, nil, C0, 1)
	sw.LayoutOrder = order
	for i, d in { { "KBM", "KEYBOARD & MOUSE" }, { "PAD", "CONTROLLER" } } do
		local b = Widgets.FlatButton(sw, d[2], UDim2.new(0.5, -4, 1, 0), UDim2.new((i - 1) * 0.5, i == 2 and 4 or 0, 0, 0), nil, device == d[1])
		b.Activated:Connect(function()
			self.BindDevice = d[1]
			self:_build("Keybinds")
		end)
	end

	order += 1
	local hint = Theme.Label(scroll, device == "PAD" and "Select a slot, then press a button. MENU cancels, VIEW clears." or
		"Select a slot, then press a key, mouse button or scroll the wheel. ESC cancels, BACKSPACE clears.", 13, Theme.Dim, LEFT, Theme.Body,
		nil, UDim2.new(1, -8, 0, 22))
	hint.LayoutOrder = order

	for _, group in Settings.ActionGroups do
		local first = true
		for _, def in Settings.Actions do
			if def.Group == group and not (device == "PAD" and def.PadHidden) then
				if first then
					order += 1
					Widgets.Header(scroll, group, order)
					first = false
				end
				order += 1
				self:_bindRow(def, device, order)
			end
		end
	end

	order += 1
	Widgets.ActionRow(scroll, device == "PAD" and "Reset controller binds" or "Reset keyboard & mouse binds", nil, "RESET", order, function()
		Settings.ResetBinds(device)
		if device == "PAD" then Settings.Set("Pad.Preset", "Default") end
		self:_toast("BINDS RESTORED")
	end)
	return order
end

function SettingsMenu:_bindRow(def, device, order)
	local row, right = Widgets.Row(self.Scroll, def.Label, nil, order)
	for slot = 1, 2 do
		local b = Widgets.FlatButton(right, "", UDim2.fromOffset(148, 34), UDim2.new(1, slot == 2 and 0 or -156, 0.5, 0), Vector2.new(1, 0.5))
		b.TextSize = 15
		self.BindLabels[b] = { Action = def.Id, Device = device, Slot = slot }
		b.Activated:Connect(function() self:_rebind(b) end)
	end
	self:_refreshBinds()
end

function SettingsMenu:_refreshBinds()
	if not self.BindLabels then return end
	for b, info in self.BindLabels do
		if b.Parent and not b:GetAttribute("Listening") then
			local code = Settings.GetBind(info.Action, info.Device, info.Slot)
			b.Text = InputMap.CodeLabel(code)
			b.TextColor3 = code == "" and Theme.Dim or Theme.Text
		end
	end
end

function SettingsMenu:_rebind(b)
	local info = self.BindLabels[b]
	for other in self.BindLabels do other:SetAttribute("Listening", nil) end
	b:SetAttribute("Listening", true)
	b.Text, b.TextColor3 = info.Device == "PAD" and "PRESS A BUTTON" or "PRESS A KEY", Theme.Accent
	InputMap.Capture(info.Device, function(code, status)
		b:SetAttribute("Listening", nil)
		if status == "set" or status == "clear" then
			local conflict = Settings.SetBind(info.Action, info.Device, info.Slot, code)
			if conflict then
				local label
				for _, a in Settings.Actions do if a.Id == conflict then label = a.Label end end
				self:_toast(("SWAPPED WITH %s"):format((label or conflict):upper()))
			end
		end
		self:_refreshBinds()
	end)
end

-- ---------------------------------------------------------------- gamepad focus
function SettingsMenu:FocusNav()
	local n = self.NavButtons[self.Current]
	if n then GuiService.SelectedObject = n.Button end
end

function SettingsMenu:FocusContent()
	for _, d in self.Scroll:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and d.Visible then
			GuiService.SelectedObject = d
			return
		end
	end
end

-- B / back: returns true if it did something here (cancelled a rebind, or moved focus back to the category list)
function SettingsMenu:Back()
	if InputMap.IsCapturing() then
		InputMap.CancelCapture()
		self:_refreshBinds()
		return true
	end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(self.Scroll) then
		self:FocusNav()
		return true
	end
	return false
end

function SettingsMenu:Show()
	self:Select(self.Current) -- rebuild so every control shows the live value
end

function SettingsMenu:Hide()
	InputMap.CancelCapture()
	Settings.Flush()
end

return SettingsMenu
