-- StreakClient: the player side of kill streaks.
--  * keeps the HUD chips in sync (StreakSync) and announces READY / calls (StreakFX)
--  * Streak1-3 / StreakNext actions ask the server to use a streak (the server checks everything; targeted ones send the camera ray)
--  * UAV has no client code: its sweeps reach the minimap from the server (RadarService -> Radar), and there is no through-wall highlight
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Theme)
local InputMap = require(script.Parent.InputMap)
local Armory = require(script.Parent.Armory)

local StreakClient = {}
StreakClient.__index = StreakClient

local player = Players.LocalPlayer
local TARGETED = { Airstrike = true, Mortar = true, ChemStrike = true }
local ANNOUNCE = { UAV = "UAV", Airstrike = "AIRSTRIKE", Mortar = "MORTAR BARRAGE", ChemStrike = "CHEMICAL STRIKE" }

local function sameTeam(a, b) return a == b or (a.Team ~= nil and a.Team == b.Team) end

function StreakClient.new(hud)
	local self = setmetatable({}, StreakClient)
	self.Hud, self.Sync = hud, { Kills = 0, Slots = {} }
	local Remotes = RS:WaitForChild("FPS"):WaitForChild("Remotes")
	self.Remotes = Remotes

	Remotes:WaitForChild("StreakSync").OnClientEvent:Connect(function(sync)
		self.Sync = sync
		hud:SetStreaks(sync)
	end)
	Remotes:WaitForChild("StreakFX").OnClientEvent:Connect(function(kind, id, a)
		local def = Armory.Streaks[id]
		if not def then return end
		if kind == "Ready" then
			local key = InputMap.Label("Streak" .. tostring(a))
			hud:Toast(("%s READY%s"):format(def.Name:upper(), key ~= "" and ("  [" .. key .. "]") or ""), Theme.Accent)
		elseif kind == "NoTarget" then
			hud:Toast("AIM AT THE GROUND OR A WALL", Theme.Warn)
		elseif kind == "Call" then
			local caller = a
			if caller == player then
				hud:Toast(def.Name:upper() .. " CALLED IN", Theme.Accent)
			elseif typeof(caller) == "Instance" and ANNOUNCE[id] then
				if sameTeam(player, caller) then hud:Toast("FRIENDLY " .. ANNOUNCE[id], Theme.Good)
				else hud:Toast("ENEMY " .. ANNOUNCE[id], Theme.Danger) end
			end
		end
	end)

	for i = 1, 3 do InputMap.OnBegan("Streak" .. i, function() self:Use(i) end) end
	InputMap.OnBegan("StreakNext", function()
		for i, slot in self.Sync.Slots do
			if slot.State == "Ready" then
				self:Use(i)
				return
			end
		end
	end)

	return self
end

-- state = result of GetState().Streaks (so the chips are right as soon as you spawn)
function StreakClient:Reset(sync)
	self.Sync = sync or { Kills = 0, Slots = {} }
	self.Hud:SetStreaks(self.Sync)
end

function StreakClient:Use(slot)
	local info = self.Sync.Slots[slot]
	if not info or info.State ~= "Ready" then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local cam = workspace.CurrentCamera
	if TARGETED[info.Id] then
		self.Remotes.StreakUse:FireServer(slot, cam.CFrame.Position, cam.CFrame.LookVector)
	else
		self.Remotes.StreakUse:FireServer(slot)
	end
end

return StreakClient
