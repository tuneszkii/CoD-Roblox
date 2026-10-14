local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local FPS = RS:WaitForChild("FPS")
local Remotes = FPS:WaitForChild("Remotes")

local Movement = require(FPS.Movement)
local CameraRig = require(FPS.CameraRig)
local Viewmodel = require(FPS.Viewmodel)
local WeaponController = require(FPS.WeaponController)
local ThirdPerson = require(FPS.ThirdPerson)
local Theme = require(FPS.Theme)
local ArmoryClient = require(FPS.ArmoryClient)
local ArmoryPage = require(FPS.ArmoryPage)
local StreakClient = require(FPS.StreakClient)
local Hitbox = require(FPS.Hitbox)
local Config = require(FPS.Config)
local Settings = require(FPS.Settings)
local InputMap = require(FPS.InputMap)
local MainMenu = require(FPS.MainMenu)
local MobileControls = require(FPS.MobileControls)
local MatchClient = require(FPS.MatchClient)
local MatchHud = require(FPS.MatchHud)
local DeployPage = require(FPS.DeployPage)
local CosmeticsClient = require(FPS.CosmeticsClient)
local CosmeticsPage = require(FPS.CosmeticsPage)
local CareerPage = require(FPS.CareerPage)
local EmoteClient = require(FPS.EmoteClient)
local Cosmetics = require(FPS.Cosmetics)
local CineCam = require(FPS.CineCam)
local MatchPresentation = require(FPS.MatchPresentation)
local DeathPresentation = require(FPS.DeathPresentation)
local ObjectiveClient = require(FPS.ObjectiveClient)
local Radar = require(FPS.Radar)
local Scoreboard = require(FPS.Scoreboard)

Settings.StartClient(Remotes) -- defaults now, saved options arrive in the background

local movement = Movement.new()
local camRig = CameraRig.new()
local viewmodel = Viewmodel.new()
local weapons = WeaponController.new(movement, camRig, viewmodel)

local active = false

movement.OnLand = function(speed)
	camRig.Shake:Impulse(Vector3.new(-math.clamp(speed * 0.012, 0, 1), 0, 0))
	viewmodel:Land(speed)
end
movement.OnSlide = function()
	camRig.Shake:Impulse(Vector3.new(-0.3, 0, 0.35))
	viewmodel:SlideKick()
end
movement.OnDive = function() -- dive to prone: the view pitches down as the gun is thrown out in front
	camRig.Shake:Impulse(Vector3.new(0.55, 0, -0.25))
	viewmodel:SlideKick()
end
movement.OnMantle = function(kind) -- hands grab the ledge / the hop starts
	camRig.Shake:Impulse(kind == "Vault" and Vector3.new(0.35, 0, 0.15) or Vector3.new(0.5, 0, -0.2))
	viewmodel:SlideKick()
end
movement.OnMantleEnd = function(kind) -- settle onto the ledge / land the vault
	camRig.Shake:Impulse(Vector3.new(kind == "Vault" and -0.35 or -0.5, 0, 0))
	viewmodel:Land(kind == "Vault" and 22 or 26)
end

movement.OnLadder = function() -- grab the ladder
	camRig.Shake:Impulse(Vector3.new(0.25, 0, 0.1))
	viewmodel:SlideKick()
end
movement.OnLadderEnd = function(reason)
	if reason == "Jump" then camRig.Shake:Impulse(Vector3.new(-0.2, 0, 0)) end
end

ThirdPerson.Start()
Hitbox.Start()
UIS.InputBegan:Connect(function(input, processed) -- F8: show the hitboxes bullets are tested against (debug builds only)
	if not processed and Config.Debug and input.KeyCode == Config.Keys.HitboxDebug then Hitbox.ToggleDebug() end
end)

local function onMenuToggle(open)
	camRig.Suspended = open
	UIS.MouseIconEnabled = open
	if open then UIS.MouseBehavior = Enum.MouseBehavior.Default end
	if active then weapons:SetActive(not open) end
end

local mobile = MobileControls.new()
ArmoryClient.Start(Remotes)
DeployPage.Register(MainMenu) -- vote + deploy tab
ArmoryPage.Register(MainMenu) -- classes, gunsmith, perks, equipment, kill streaks
CosmeticsClient.Start(Remotes)
CosmeticsPage.Register(MainMenu) -- operators, cards, emblems, titles, emotes, tracers
CareerPage.Start(Remotes)
CareerPage.Register(MainMenu) -- stats, achievements, and weapon mastery
local menu = MainMenu.new({
	OnToggle = onMenuToggle,
	EditTouch = function(onClose) mobile:Edit(onClose) end,
})
Remotes.XPSync.OnClientEvent:Connect(function(summary) menu:SetProfile(summary) end)
-- the Armory key (L, formerly the loadout menu) opens / closes the ARMORY tab
InputMap.OnBegan("Loadout", function()
	if menu.IsOpen and menu.Current == "ARMORY" then menu:Close() else menu:Open("ARMORY") end
end)
local streaks = StreakClient.new(weapons.Hud)
local menuRef = menu
local emotes = EmoteClient.new({
	Remotes = Remotes, CamRig = camRig, Viewmodel = viewmodel, Weapons = weapons, Movement = movement,
	CanUse = function() return active and not menuRef.IsOpen end,
})
Remotes.ArmoryEvent.OnClientEvent:Connect(function(kind, weapon, level, unlocked)
	if kind ~= "WeaponLevel" then return end
	local text = ("%s  LEVEL %d"):format(weapon, level)
	if #unlocked > 0 then text ..= "  -  UNLOCKED: " .. table.concat(unlocked, ", ") end
	weapons.Hud:Toast(text, Theme.Accent)
end)
-- achievements + weapon mastery rewards: one toast at a time so none is lost
do
	local queue, running = {}, false
	local function drain()
		if running then return end
		running = true
		task.spawn(function()
			while #queue > 0 do
				local t = table.remove(queue, 1)
				weapons.Hud:Toast(t.Text, t.Color)
				task.wait(1.8)
			end
			running = false
		end)
	end
	Remotes.AchievementEvent.OnClientEvent:Connect(function(kind, d)
		if type(d) ~= "table" then return end
		if kind == "Achievement" then
			table.insert(queue, { Text = ("ACHIEVEMENT: %s%s"):format(tostring(d.Name), d.Text and d.Text ~= "" and "   " .. d.Text or ""), Color = Theme.Good })
		elseif kind == "Mastery" then
			table.insert(queue, { Text = ("%s MASTERY: %s%s"):format(tostring(d.TierName), tostring(d.Weapon), d.Text and d.Text ~= "" and "   " .. d.Text or ""), Color = Theme.Accent })
		end
		drain()
	end)
end
MatchHud.new()
ObjectiveClient.new() -- flags, hardpoint, dog tags
local radar = Radar.new()   -- minimap + full map (UAV / gunfire tracking)
Scoreboard.new()        -- hold Tab

-- match start / end + death / respawn presentation (all driven by the server's MatchEvent messages)
CineCam.IsRigActive = function() return camRig.Active end
CineCam.OnChange(function(on, shot)
	if not shot then return end
	if shot.HideViewmodel ~= false and camRig.Active then viewmodel:SetVisible(not on) end
	if shot.HideHud then
		weapons.Hud:SetEnabled(not on and active)
		radar:SetHidden(on)
	end
	if shot.ShowBody then camRig.ShowBody = on end
end)
MatchPresentation.new({
	CloseMenu = function() if menu.IsOpen then menu:Close() end end,
	SetLocked = function(on) weapons:SetLocked(on) end,
	RigActive = function() return active end,
})
local deathPresentation = DeathPresentation.new({
	RigActive = function() return active end,
	ViewCF = function() return active and camRig.CFrame or nil end,
})

-- controller vibration on damage / kills
Remotes.DamageFX.OnClientEvent:Connect(function() InputMap.Rumble(0.6, 0.15) end)
Remotes.ExplosionFX.OnClientEvent:Connect(function() InputMap.Rumble(0.9, 0.3) end)
Remotes.HitConfirm.OnClientEvent:Connect(function(_, kill) if kill then InputMap.Rumble(0.4, 0.12) end end)

local function fetchState()
	for _ = 1, 40 do -- the server builds loadout state when the character spawns
		local ok, state = pcall(function() return Remotes.GetState:InvokeServer() end)
		if ok and state then return state end
		task.wait(0.15)
	end
	return nil
end

-- stop everything that belongs to the current character (death, character removed at the end of a match)
local function cleanup(hum)
	emotes:Cancel(true)
	if not active and not camRig.Active then return end
	active = false
	movement.Active = false
	weapons:SetActive(false)
	viewmodel:SetVisible(false)
	viewmodel:EndTrack()
	camRig:Release(hum)
end

local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	char:WaitForChild("HumanoidRootPart")
	movement:SetCharacter(char)
	camRig:SetCharacter(char)
	viewmodel:SetCharacter(char)
	local state = fetchState()
	if not state or char.Parent == nil then return end
	camRig:Realign() -- the server moves the character to its spawn point right after creating it
	do -- operator colors on the first-person arms (the server sets the Operator attribute on spawn)
		local op = Cosmetics.Operator(char:GetAttribute("Operator") or "")
		if op and not op.Avatar then viewmodel:SetColors(op.Sleeve, op.Boots) else viewmodel:SetColors(nil, nil) end
	end
	weapons:Reset(state)
	streaks:Reset(state.Streaks)
	active = true
	hum.Died:Once(function()
		cleanup(hum)
		deathPresentation:OnLocalDeath()
	end)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup(nil) end -- the match ended and the server removed the character
	end)
	if menu.IsOpen then menu:Close() end -- the match put us in: leave the front end
end

-- back to the vote at the end of every match
MatchClient.OnChanged(function()
	if MatchClient.Phase() == "Voting" and not menu.IsOpen then
		cleanup(nil)
		menu:Open("DEPLOY")
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

-- Movement runs right after the default control script so slide can override Humanoid:Move
RunService:BindToRenderStep("FPS_Move", Enum.RenderPriority.Input.Value + 1, function(dt)
	if not active then return end
	movement:Update(dt, camRig.Yaw, weapons:GetSpeedMult())
end)

RunService:BindToRenderStep("FPS_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not active then return end
	weapons:Update(dt)
	camRig:Update(dt, movement, weapons)
	viewmodel:Update(dt, camRig.CFrame, movement, weapons, camRig.MouseDelta)
end)

menu:Open("DEPLOY") -- front end on join; DEPLOY drops you into the match
