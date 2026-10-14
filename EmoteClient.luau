-- EmoteClient: the emote wheel (default key B, touch EMOTE button) and playing your own emote.
-- Picking an emote asks the server (Remotes.Emote); the server sets the Emote / EmoteStart character attributes and every client
-- (including you) animates them in ThirdPerson.luau. While yours plays the camera swings round in front of you.
-- Moving, jumping, shooting, aiming, taking damage or dying cancels it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local Cosmetics = require(script.Parent.Cosmetics)
local CC = require(script.Parent.CosmeticsClient)
local ThirdPerson = require(script.Parent.ThirdPerson)

local EmoteClient = {}
EmoteClient.__index = EmoteClient

local CENTER = Enum.TextXAlignment.Center
local C0 = Color3.new()
local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
local CANCEL_ACTIONS = { "Jump", "Fire", "Aim", "Crouch", "Prone", "Sprint", "Reload", "Melee", "Lethal", "Tactical", "Plate" }

-- deps = { Remotes, CamRig, Viewmodel, Weapons, Movement, CanUse = fn() -> bool (alive, in a match, menu closed) }
function EmoteClient.new(deps)
	local self = setmetatable({ D = deps, Open = false, Playing = nil, StartedAt = 0 }, EmoteClient)

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled = "EmoteWheel", false, true, 40, false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = gui
	local root, fit = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 760 end, "Interface.Scale")
	InputMap.OnDeviceChanged(fit)
	local dim = Theme.Frame(root, UDim2.fromScale(1, 1), nil, nil, Color3.fromRGB(6, 8, 10), 0.45)
	local close = Instance.new("TextButton") -- click outside the wheel to close it
	close.BackgroundTransparency, close.Text, close.Size = 1, "", UDim2.fromScale(1, 1)
	close.Parent = dim
	close.Activated:Connect(function() self:CloseWheel() end)
	Theme.Label(dim, "EMOTES", 22, Theme.Dim, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(200, 30), Vector2.new(0.5, 0.5))
	self.Slots = {}
	for i = 1, Cosmetics.EmoteSlots do
		local a = math.rad(-90 + (i - 1) * 360 / Cosmetics.EmoteSlots)
		local b = Instance.new("TextButton")
		b.AutoButtonColor, b.Text, b.BorderSizePixel = false, "", 0
		b.Size, b.AnchorPoint = UDim2.fromOffset(170, 56), Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, math.cos(a) * 250, 0.5, math.sin(a) * 170)
		b.BackgroundColor3, b.BackgroundTransparency = Theme.Panel, 0.2
		Theme.Round(b, 6)
		Theme.Stroke(b, Theme.Accent, 1, 0.4)
		Theme.Label(b, tostring(i), 12, Theme.Accent, CENTER, Theme.Display, UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 14))
		local name = Theme.Label(b, "", 20, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 18), UDim2.new(1, 0, 0, 30))
		b.Parent = dim
		Widgets.Selectable(b)
		b.Activated:Connect(function()
			local id = self.Ids and self.Ids[i]
			if id and id ~= "" then self:Play(id) end
		end)
		self.Slots[i] = { Button = b, Name = name }
	end

	InputMap.OnBegan("Emote", function() self:ToggleWheel() end)
	UIS.InputBegan:Connect(function(input)
		if not self.Open then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB then
			self:CloseWheel()
			return
		end
		for i, key in NUMBER_KEYS do
			if kc == key then
				local id = self.Ids and self.Ids[i]
				if id and id ~= "" then self:Play(id) end
			end
		end
	end)
	deps.Remotes.DamageFX.OnClientEvent:Connect(function() if self.Playing then self:Cancel() end end)
	return self
end

function EmoteClient:_canStart()
	local D = self.D
	local m, w = D.Movement, D.Weapons
	return D.CanUse() and not self.Playing and m.Speed < 1.5 and m.Grounded and not m.Downed and not (w.Rl or w.Busy or w.Act or w.Downed)
end

function EmoteClient:ToggleWheel()
	if self.Open then self:CloseWheel() else self:OpenWheel() end
end

function EmoteClient:OpenWheel()
	if self.Open or not self:_canStart() then return end
	if not CC.Data then task.spawn(CC.Load) end
	local E = CC.Data and CC.Data.Equipped
	self.Ids = E and E.Emotes or { "Wave", "Salute", "Point", "Shrug", "", "" }
	for i, s in self.Slots do
		local id = self.Ids[i]
		local def = id and id ~= "" and Cosmetics.Get("Emote", id)
		s.Name.Text = def and def.Name:upper() or "EMPTY"
		s.Name.TextColor3 = def and Theme.Text or Theme.Dim
		s.Button.Active = def ~= nil and def ~= false
	end
	self.Open = true
	self.Gui.Enabled = true
	local D = self.D
	InputMap.SetEnabled(false)
	D.CamRig.Suspended = true
	UIS.MouseBehavior, UIS.MouseIconEnabled = Enum.MouseBehavior.Default, true
	D.Weapons:SetActive(false)
end

function EmoteClient:CloseWheel(keepWeaponsOff)
	if not self.Open then return end
	self.Open = false
	self.Gui.Enabled = false
	local D = self.D
	InputMap.SetEnabled(true)
	D.CamRig.Suspended = false
	UIS.MouseIconEnabled = false
	if not keepWeaponsOff and D.CanUse() then D.Weapons:SetActive(true) end
end

function EmoteClient:Play(id)
	self:CloseWheel(true)
	local D = self.D
	self.Playing, self.StartedAt = id, os.clock()
	D.Remotes.Emote:FireServer(id)
	ThirdPerson.SetLocal(true)
	D.CamRig.OrbitOn = true
	D.Viewmodel:SetVisible(false)
	D.Weapons:SetActive(false)
	self.Conn = RunService.RenderStepped:Connect(function()
		if not self.Playing then return end
		local char = Players.LocalPlayer.Character
		local over = os.clock() - self.StartedAt > 1.0 and (char == nil or (char:GetAttribute("Emote") or "") == "") -- server ended it
		local moved = InputMap.GetMoveVector().Magnitude > 0.2
		if not moved and os.clock() - self.StartedAt > 0.3 then
			for _, a in CANCEL_ACTIONS do
				if InputMap.IsDown(a) then moved = true break end
			end
		end
		if over or moved then self:Cancel() end
	end)
end

-- silent = true when the character is already gone (death, end of match): nothing to tell the server
function EmoteClient:Cancel(silent)
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	if self.Open then self:CloseWheel(true) end
	if not self.Playing then return end
	self.Playing = nil
	local D = self.D
	if not silent then D.Remotes.Emote:FireServer("") end
	ThirdPerson.SetLocal(false)
	D.CamRig.OrbitOn = false
	D.Viewmodel:SetVisible(true)
	if not silent and D.CanUse() then D.Weapons:SetActive(true) end
end

return EmoteClient
