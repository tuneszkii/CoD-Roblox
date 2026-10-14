-- CosmeticsClient: the client's copy of the player's cosmetics (owned items, what is equipped, XP + credits for prices) and the calls to the server.
-- The Cosmetics menu page reads CosmeticsClient.Data and calls Buy / Equip; the server stays the authority (it re-validates everything).
local Armory = require(script.Parent.Armory)

local CC = { Data = nil, Loaded = false }
local listeners = {}
local remotes

local function fire()
	for _, fn in table.clone(listeners) do task.spawn(fn) end
end

function CC.OnChanged(fn)
	table.insert(listeners, fn)
	return { Disconnect = function()
		local i = table.find(listeners, fn)
		if i then table.remove(listeners, i) end
	end }
end

function CC.Start(r)
	remotes = r
	-- XP / credits change while you play (kills, level ups, purchases): keep prices and unlock states current
	remotes.XPSync.OnClientEvent:Connect(function(summary)
		if CC.Data and summary then
			CC.Data.XP, CC.Data.Credits = summary.XP, summary.Credits
			fire()
		end
	end)
end

local function take(data)
	CC.Data, CC.Loaded = data, true
	Armory.UnlockAll = data.UnlockAll == true
	fire()
end

function CC.Load()
	local ok, data = pcall(function() return remotes.GetCosmetics:InvokeServer() end)
	if ok and type(data) == "table" then
		take(data)
		return true
	end
	return false
end

-- returns ok, message
function CC.Buy(cat, id)
	local ok, res, extra = pcall(function() return remotes.CosmeticsBuy:InvokeServer(cat, id) end)
	if not ok then return false, "CONNECTION ERROR" end
	if res == true and type(extra) == "table" then
		take(extra)
		return true
	end
	return false, tostring(extra or "FAILED")
end

-- slot is only used for emotes (1..Cosmetics.EmoteSlots; id "" empties the slot)
function CC.Equip(cat, id, slot)
	local ok, equipped = pcall(function() return remotes.CosmeticsEquip:InvokeServer(cat, id, slot) end)
	if ok and type(equipped) == "table" and CC.Data then
		CC.Data.Equipped = equipped
		fire()
		return true
	end
	return false, "COULD NOT EQUIP"
end

return CC
