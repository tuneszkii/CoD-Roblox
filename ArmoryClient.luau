-- ArmoryClient: the client's copy of the player's armory data (credits, XP, weapon XP, purchases, classes) and the calls to the server.
-- The Armory menu page reads ArmoryClient.Data and calls Buy / SaveClass / Select; the server stays the authority (it re-validates everything).
local Armory = require(script.Parent.Armory)

local AC = { Data = nil, Loaded = false }
local listeners = {}
local remotes

local function fire()
	for _, fn in table.clone(listeners) do task.spawn(fn) end
end

function AC.OnChanged(fn)
	table.insert(listeners, fn)
	return { Disconnect = function()
		local i = table.find(listeners, fn)
		if i then table.remove(listeners, i) end
	end }
end

function AC.Start(r)
	remotes = r
	-- XP / level / credits changes (kills, level ups, purchases) keep the header and the page current
	remotes.XPSync.OnClientEvent:Connect(function(summary)
		if AC.Data and summary then
			AC.Data.XP, AC.Data.Credits = summary.XP, summary.Credits
			fire()
		end
	end)
end

-- fetch from the server (the server may still be loading the profile, so this can take a moment)
function AC.Load()
	local ok, data = pcall(function() return remotes.GetArmory:InvokeServer() end)
	if ok and type(data) == "table" then
		AC.Data, AC.Loaded = data, true
		Armory.UnlockAll = data.UnlockAll == true
		fire()
		return true
	end
	return false
end

-- returns ok, message
function AC.Buy(kind, id, weapon)
	local ok, res, extra = pcall(function() return remotes.ArmoryBuy:InvokeServer(kind, id, weapon) end)
	if not ok then return false, "CONNECTION ERROR" end
	if res == true and type(extra) == "table" then
		AC.Data = extra
		fire()
		return true
	end
	return false, tostring(extra or "FAILED")
end

-- store a class; the server answers with the cleaned version
function AC.SaveClass(index, class)
	local ok, clean = pcall(function() return remotes.ArmorySave:InvokeServer(index, class) end)
	if ok and type(clean) == "table" and AC.Data then
		AC.Data.Classes[index] = clean
		fire()
		return clean
	end
	return nil
end

function AC.Select(index)
	local ok, res = pcall(function() return remotes.ArmorySelect:InvokeServer(index) end)
	if ok and res and AC.Data then
		AC.Data.Selected = res
		fire()
		return true
	end
	return false
end

return AC
