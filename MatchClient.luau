-- MatchClient: read-only view of the match state (replicated as attributes by MatchService) plus the vote / deploy requests.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local FPS = script.Parent
local Remotes = FPS:WaitForChild("Remotes")
local State = FPS:WaitForChild("MatchState")
local player = Players.LocalPlayer

local MatchClient = {}
local myVotes = {}
local changed, events = {}, {}

local function fire()
	for _, fn in table.clone(changed) do task.spawn(fn) end
end

function MatchClient.Phase() return State:GetAttribute("Phase") or "Voting" end
function MatchClient.Get(key) return State:GetAttribute(key) end

function MatchClient.TimeLeft()
	local e = State:GetAttribute("PhaseEnd")
	return e and math.max(0, e - workspace:GetServerTimeNow()) or 0
end

function MatchClient.Candidates()
	local csv, out = State:GetAttribute("Maps") or "", {}
	for id in csv:gmatch("[^,]+") do table.insert(out, id) end
	return out
end

function MatchClient.VoteCount(kind, id) return State:GetAttribute("Vote" .. kind .. "_" .. id) or 0 end
function MatchClient.MyVote(kind) return myVotes[kind] end
function MatchClient.IsReady() return player:GetAttribute("Ready") == true end
function MatchClient.IsDeployed() return player:GetAttribute("Deployed") == true end

function MatchClient.Vote(kind, id)
	if MatchClient.Phase() ~= "Voting" then return end
	myVotes[kind] = id
	Remotes.Vote:FireServer(kind, id)
	fire()
end

-- Voting: toggles "ready". Match: spawns you if you are not in yet.
function MatchClient.Deploy(want)
	Remotes.Deploy:FireServer(want)
end

function MatchClient.OnChanged(fn)
	table.insert(changed, fn)
	return { Disconnect = function()
		local i = table.find(changed, fn)
		if i then table.remove(changed, i) end
	end }
end

-- server -> client messages: ("Message", text) ("Respawn", seconds) ("Results", data)
function MatchClient.OnEvent(fn)
	table.insert(events, fn)
end

State.AttributeChanged:Connect(function(name)
	if name == "Phase" and MatchClient.Phase() == "Voting" then myVotes = {} end -- new vote, new options
	fire()
end)
player:GetAttributeChangedSignal("Ready"):Connect(fire)
player:GetAttributeChangedSignal("Deployed"):Connect(fire)
Remotes:WaitForChild("MatchEvent").OnClientEvent:Connect(function(...)
	for _, fn in table.clone(events) do task.spawn(fn, ...) end
end)

return MatchClient
