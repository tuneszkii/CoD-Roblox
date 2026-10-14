-- CosmeticsService: the server side of the Cosmetics menu.
--   GetCosmetics()                -> snapshot (XP, credits, owned items, equipped items)
--   CosmeticsBuy(cat, id)         -> buy an unlock early. The price comes from Cosmetics.Progress, never from the client.
--   CosmeticsEquip(cat, id, slot) -> equip an unlocked item (slot = emote wheel slot 1..6)
--   Emote(id)  (event)            -> play an equipped emote ("" = stop)
-- What you wear is published as player attributes so every client can draw it:
--   CosOperator (also on the character as "Operator"), CosCard, CosEmblem, CosTitle, CosTracer.
-- Operators recolor the character (BodyColors + a visor band). They apply on spawn; the third-person rig and the first-person arms read the
-- "Operator" character attribute. To use real models later, swap the character there instead of recoloring it.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Cosmetics = require(RS:WaitForChild("FPS"):WaitForChild("Cosmetics"))
local Emotes = require(RS.FPS:WaitForChild("Emotes"))
local Armory = require(RS.FPS:WaitForChild("Armory"))

local C = {}
local ctx
local lastCall = {}
local checked = {}

local function throttled(plr, key, gap)
	local t = os.clock()
	local last = lastCall[plr] or {}
	lastCall[plr] = last
	if t - (last[key] or 0) < gap then return true end
	last[key] = t
	return false
end

-- profile data with a validated Cosmetics blob (validated once per player, then kept valid by the handlers below)
local function dataFor(plr, wait)
	local d = wait and ctx.Data.Wait(plr, 15) or ctx.Data.Get(plr)
	if not d then return nil end
	if not checked[plr] then
		checked[plr] = true
		d.Cosmetics = Cosmetics.Sanitize(d.XP, d.Cosmetics)
		ctx.Data.MarkDirty(plr)
	end
	return d
end

local function snapshot(d)
	return { XP = d.XP, Credits = math.floor(d.Credits), Owned = d.Cosmetics.Owned, Equipped = d.Cosmetics.Equipped, UnlockAll = Armory.UnlockAll }
end

local function publish(plr, d)
	local E = d.Cosmetics.Equipped
	plr:SetAttribute("CosOperator", E.Operator)
	plr:SetAttribute("CosCard", E.Card)
	plr:SetAttribute("CosEmblem", E.Emblem)
	plr:SetAttribute("CosTitle", E.Title)
	plr:SetAttribute("CosTracer", E.Tracer)
end

-- ---------------------------------------------------------------- operators
local function applyOperator(char, op)
	if not char.Parent or op.Avatar then return end
	for _, d in char:GetChildren() do
		if d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("Accessory") or d:IsA("BodyColors") then d:Destroy() end
	end
	local bc = Instance.new("BodyColors")
	bc.HeadColor3, bc.TorsoColor3 = op.Head or op.Skin, op.Torso
	bc.LeftArmColor3, bc.RightArmColor3 = op.Sleeve, op.Sleeve
	bc.LeftLegColor3, bc.RightLegColor3 = op.Pants, op.Pants
	bc.Parent = char

	local old = char:FindFirstChild("OperatorBand")
	if old then old:Destroy() end
	local head = char:FindFirstChild("Head")
	if head and op.Accent then
		local band = Instance.new("Part")
		band.Name, band.Material, band.Color, band.Size = "OperatorBand", Enum.Material.Neon, op.Accent, Vector3.new(1.32, 0.2, 1.32)
		band.CanCollide, band.CanQuery, band.CanTouch, band.Massless, band.CastShadow = false, false, false, true, false
		band.CFrame = head.CFrame * CFrame.new(0, 0.36, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = head, band, band
		band.Parent = char
	end
end

-- called by FPSServer when a character spawns (after the profile is loaded)
function C.OnSpawn(plr, char)
	local d = dataFor(plr, false)
	local id = d and d.Cosmetics.Equipped.Operator or "Default"
	local op = Cosmetics.Operator(id)
	if not op or not Cosmetics.IsUnlocked(d and d.XP or 0, d and d.Cosmetics.Owned, "Operator", id) then id, op = "Default", Cosmetics.Operator("Default") end
	char:SetAttribute("Operator", id)
	char:SetAttribute("Emote", "")
	applyOperator(char, op)
	if not op.Avatar then -- the avatar's clothes / accessories can finish loading after the character spawns
		local conn
		conn = plr.CharacterAppearanceLoaded:Connect(function(c)
			if c == char then
				conn:Disconnect()
				applyOperator(char, op)
			end
		end)
		task.delay(10, function() if conn then conn:Disconnect() end end)
	end
end

-- ---------------------------------------------------------------- emotes
local function clearEmote(char)
	if char and char:GetAttribute("Emote") ~= "" then char:SetAttribute("Emote", "") end
end

-- called from the StateSync handler: moving, jumping, crouching or any action ends the emote
function C.OnState(plr, stance, act)
	local char = plr.Character
	local e = char and char:GetAttribute("Emote")
	if e and e ~= "" and (stance ~= "Idle" or act ~= "") then clearEmote(char) end
end

local function onEmote(plr, id)
	if type(id) ~= "string" or throttled(plr, "Emote", 0.4) then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if id == "" then
		clearEmote(char)
		return
	end
	local d = dataFor(plr, false)
	local s = ctx.State[plr]
	if not d or not s or not s.Ready or s.Down or s.Reloading or s.Cook or s.Plating then return end
	if not table.find(d.Cosmetics.Equipped.Emotes, id) or not Emotes.Defs[id] then return end
	local stance = char:GetAttribute("Stance")
	if (stance ~= nil and stance ~= "Idle") or (char:GetAttribute("Action") or "") ~= "" then return end
	local start = workspace:GetServerTimeNow()
	char:SetAttribute("EmoteStart", start)
	char:SetAttribute("Emote", id)
	task.delay(Emotes.Defs[id].Duration + 0.3, function() -- clear when it is over (unless a newer emote started)
		if char.Parent and char:GetAttribute("EmoteStart") == start then clearEmote(char) end
	end)
end

-- ---------------------------------------------------------------- remotes
local function buy(plr, cat, id)
	if throttled(plr, "Buy", 0.25) then return false, "SLOW DOWN" end
	if type(cat) ~= "string" or type(id) ~= "string" or not Cosmetics.Get(cat, id) then return false, "INVALID" end
	local d = dataFor(plr, true)
	if not d then return false, "NO DATA" end
	local p = Cosmetics.Progress(d.XP, d.Cosmetics.Owned, cat, id)
	if p.Unlocked then return false, "ALREADY UNLOCKED" end
	if math.floor(d.Credits) < p.Price then return false, "NOT ENOUGH CREDITS" end
	if not ctx.Data.SpendCredits(plr, p.Price) then return false, "NOT ENOUGH CREDITS" end
	d.Cosmetics.Owned[Cosmetics.Key(cat, id)] = true
	ctx.Data.MarkDirty(plr)
	return true, snapshot(d)
end

local function equip(plr, cat, id, slot)
	if throttled(plr, "Equip", 0.15) then return false end
	if type(cat) ~= "string" or not Cosmetics.ById[cat] or type(id) ~= "string" then return false end
	local d = dataFor(plr, true)
	if not d then return false end
	local E = d.Cosmetics.Equipped
	if cat == "Emote" then
		if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Cosmetics.EmoteSlots then return false end
		if id ~= "" then
			if not Cosmetics.IsUnlocked(d.XP, d.Cosmetics.Owned, cat, id) then return false end
			for i, e in E.Emotes do
				if e == id then E.Emotes[i] = "" end -- an emote sits in one slot only
			end
		end
		E.Emotes[slot] = id
	else
		if not Cosmetics.IsUnlocked(d.XP, d.Cosmetics.Owned, cat, id) then return false end
		E[cat] = id
	end
	ctx.Data.MarkDirty(plr)
	publish(plr, d)
	return E
end

function C.Init(c)
	ctx = c
	local R = ctx.Remotes
	R.GetCosmetics.OnServerInvoke = function(plr)
		local d = dataFor(plr, true)
		return d and snapshot(d) or false
	end
	R.CosmeticsBuy.OnServerInvoke = buy
	R.CosmeticsEquip.OnServerInvoke = equip
	R.Emote.OnServerEvent:Connect(onEmote)

	-- publish what everybody wears as soon as each profile has loaded (cards / tracers are visible to other players)
	local function onPlayer(plr)
		task.spawn(function()
			local d = dataFor(plr, true)
			if d and plr.Parent then publish(plr, d) end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in Players:GetPlayers() do onPlayer(plr) end
	Players.PlayerRemoving:Connect(function(plr)
		lastCall[plr] = nil
		checked[plr] = nil
	end)
end

return C
