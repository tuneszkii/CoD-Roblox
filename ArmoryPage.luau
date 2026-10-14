-- ArmoryPage: the ARMORY tab of the main menu. Register with ArmoryPage.Register(MainMenu) before MainMenu.new.
--
-- Three columns (nav | list | detail) that change with the mode:
--   CLASS   nav = your 10 classes, list = the class's slots (primary, secondary, equipment, perks, streaks), detail = what is in the focused slot
--   PICK    list = everything you can put in that slot (locked items show their level), detail = stats / unlock progress / EQUIP or BUY FORWARD
--   GUNSMITH nav = attachment slots of the weapon, list = attachments for that slot, detail = stat change if you equip it
-- Buy forward: locked items show a progress bar and the credit price to unlock them now. The price drops the closer you are (see Armory.Progress).
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Config)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Armory = require(script.Parent.Armory)
local AC = require(script.Parent.ArmoryClient)
local MatchClient = require(script.Parent.MatchClient)

local ArmoryPage = {}

local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local C0 = Color3.new()

local SLOT_KEYS = { "Primary", "Secondary", "Lethal", "Tactical", "Perk1", "Perk2", "Perk3", "Streak1", "Streak2", "Streak3" }
local SLOT_TITLES = { Primary = "PRIMARY WEAPON", Secondary = "SECONDARY WEAPON", Lethal = "LETHAL", Tactical = "TACTICAL",
	Perk1 = "PERK 1", Perk2 = "PERK 2", Perk3 = "PERK 3", Streak1 = "KILL STREAK 1", Streak2 = "KILL STREAK 2", Streak3 = "KILL STREAK 3" }

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in t do c[k] = deepCopy(v) end
	return c
end

local function clear(frame)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
	end
end

-- ---------------------------------------------------------------- small widgets
local function column(parent, xScale, xOff, wScale, wOff, title)
	local p = Theme.Glass(parent, UDim2.new(wScale, wOff, 1, -54), UDim2.new(xScale, xOff, 0, 54))
	p.BackgroundTransparency = 0.25
	Theme.Label(p, title, 13, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 20))
	Theme.Frame(p, UDim2.new(1, -28, 0, 1), UDim2.fromOffset(14, 28), nil, Theme.Accent, 0.7)
	local sf = Instance.new("ScrollingFrame")
	sf.BackgroundTransparency, sf.BorderSizePixel = 1, 0
	sf.Position, sf.Size = UDim2.fromOffset(8, 36), UDim2.new(1, -12, 1, -44)
	sf.ScrollBarThickness, sf.ScrollBarImageColor3 = 5, Theme.Accent
	sf.CanvasSize, sf.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	sf.Parent = p
	local list = Instance.new("UIListLayout")
	list.Padding, list.SortOrder = UDim.new(0, 5), Enum.SortOrder.LayoutOrder
	list.Parent = sf
	return p, sf
end

-- o = { Small, Name, Tag, TagColor, Dim, Frac, Selected, Active, Height, OnClick }
local function row(parent, order, o)
	local b = Instance.new("TextButton")
	b.AutoButtonColor, b.Text, b.LayoutOrder, b.BorderSizePixel = false, "", order, 0
	b.Size, b.BackgroundColor3 = UDim2.new(1, -8, 0, o.Height or 52), Theme.Panel
	b.BackgroundTransparency = o.Selected and 0.15 or 0.4
	Theme.Round(b, 5)
	Theme.Stroke(b, (o.Selected or o.Active) and Theme.Accent or Theme.Dim, o.Selected and 2 or 1, (o.Selected or o.Active) and 0.1 or 0.75)
	if o.Small then
		Theme.Label(b, o.Small, 10, o.Active and Theme.Accent or Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(14, 5), UDim2.new(1, -90, 0, 12))
		Theme.Label(b, o.Name, 18, o.Dim and Theme.Dim or Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(14, 18), UDim2.new(1, -90, 0, 24))
	else
		Theme.Label(b, o.Name, 18, o.Dim and Theme.Dim or Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(14, 0), UDim2.new(1, -90, 1, 0))
	end
	if o.Tag then Theme.Label(b, o.Tag, 14, o.TagColor or Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -12, 0, 0), UDim2.fromOffset(80, o.Height or 52), Vector2.new(1, 0)) end
	if o.Frac then
		local back = Theme.Frame(b, UDim2.new(1, -28, 0, 3), UDim2.new(0, 14, 1, -6), nil, C0, 0.45)
		Theme.Frame(back, UDim2.fromScale(math.clamp(o.Frac, 0, 1), 1), nil, nil, Theme.Accent)
	end
	b.Parent = parent
	Widgets.Selectable(b)
	b.Activated:Connect(o.OnClick)
	return b
end

-- ---------------------------------------------------------------- the page
function ArmoryPage.build(holder, menu)
	local Remotes = RS:WaitForChild("FPS"):WaitForChild("Remotes")
	local page = { Mode = "Class", ClassIdx = 1, Focus = "Primary", GunSlotKey = nil, GunSlot = nil, PickItem = nil, AttItem = nil, Msg = "" }

	-- header: breadcrumb + class buttons
	local head = Theme.Frame(holder, UDim2.new(1, 0, 0, 46), nil, nil, C0, 1)
	local crumb = Theme.Label(head, "ARMORY", 26, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(4, 0), UDim2.new(1, -420, 1, 0))
	local msgLbl = Theme.Label(head, "", 14, Theme.Warn, RIGHT, Theme.Display, UDim2.new(1, -400, 0, 0), UDim2.fromOffset(240, 46), Vector2.new(1, 0))
	local selectBtn = Widgets.FlatButton(head, "SELECT CLASS", UDim2.fromOffset(150, 38), UDim2.new(1, -164, 0.5, 0), Vector2.new(1, 0.5), true)
	local respawnBtn = Widgets.FlatButton(head, "EQUIP + RESPAWN", UDim2.fromOffset(150, 38), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))

	local navPanel, nav = column(holder, 0, 0, 0.23, -6, "CLASSES")
	local listPanel, list = column(holder, 0.23, 0, 0.37, -6, "LOADOUT")
	local detPanel, det = column(holder, 0.60, 0, 0.40, 0, "DETAILS")
	navPanel.Position, listPanel.Position = UDim2.new(0, 0, 0, 54), UDim2.new(0.23, 0, 0, 54)
	local titleNav, titleList, titleDet = navPanel:FindFirstChildOfClass("TextLabel"), listPanel:FindFirstChildOfClass("TextLabel"), detPanel:FindFirstChildOfClass("TextLabel")

	local function data() return AC.Data end
	local function cls() return AC.Data and AC.Data.Classes[page.ClassIdx] end

	local function say(text)
		msgLbl.Text = text or ""
		local token = (page.MsgToken or 0) + 1
		page.MsgToken = token
		task.delay(3, function() if page.MsgToken == token then msgLbl.Text = "" end end)
	end

	-- -------------------------------------------------------------- reading a class
	local function slotItem(c, key)
		if key == "Primary" then return "Weapon", c.Primary.Id
		elseif key == "Secondary" then return "Weapon", c.Secondary.Id
		elseif key == "Lethal" then return "Equip", c.Lethal
		elseif key == "Tactical" then return "Equip", c.Tactical
		elseif key:sub(1, 4) == "Perk" then return "Perk", c.Perks[tonumber(key:sub(5))]
		else return "Streak", c.Streaks[tonumber(key:sub(7))] end
	end

	local function itemName(kind, id)
		if not id or id == "" then return "NONE" end
		if kind == "Equip" then return Config.Equipment[id].Label:upper()
		elseif kind == "Perk" then return Theme.Spaced(id)
		elseif kind == "Streak" then return Armory.Streaks[id].Name:upper() end
		return id
	end

	local function commit(newClass)
		local d = data()
		if not d then return end
		local clean = Armory.SanitizeClass(d, newClass, d.Classes[page.ClassIdx])
		d.Classes[page.ClassIdx] = clean
		local idx = page.ClassIdx
		page.render()
		task.spawn(function() AC.SaveClass(idx, clean) end)
	end

	local function withSlot(key, id)
		local c = deepCopy(cls())
		if key == "Primary" then
			if c.Primary.Id ~= id then c.Primary = { Id = id, Att = {} } end
		elseif key == "Secondary" then
			if c.Secondary.Id ~= id then c.Secondary = { Id = id, Att = {} } end
		elseif key == "Lethal" or key == "Tactical" then c[key] = id
		elseif key:sub(1, 4) == "Perk" then c.Perks[tonumber(key:sub(5))] = id
		else c.Streaks[tonumber(key:sub(7))] = id end
		return c
	end

	-- -------------------------------------------------------------- detail panel
	-- d = { Tag, Name, Desc, Stats = { {label, value, base?} }, Progress = Armory.Progress result + Text, Buttons = { {Text, Primary, Fn} }, Notes = {strings} }
	local function showDetail(d)
		clear(det)
		local order = 0
		local function nextOrder() order += 1 return order end
		local function textBlock(text, size, color, font, height)
			local l = Theme.Label(det, text, size, color, LEFT, font or Theme.Body, nil, UDim2.new(1, -8, 0, height or 20))
			l.LayoutOrder = nextOrder()
			l.TextWrapped, l.TextYAlignment = true, Enum.TextYAlignment.Top
			return l
		end
		if not d then return end
		textBlock(d.Tag or "", 12, Theme.Accent, Theme.Display, 16)
		textBlock(d.Name or "", 30, Theme.Text, Theme.Display, 38)
		if d.Desc then
			local l = textBlock(d.Desc, 14, Theme.Dim, Theme.Body, 44)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.Size = UDim2.new(1, -8, 0, 20)
		end
		for _, st in d.Stats or {} do
			local f = Theme.Frame(det, UDim2.new(1, -8, 0, 32), nil, nil, C0, 1)
			f.LayoutOrder = nextOrder()
			Theme.Label(f, st[1]:upper(), 11, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 14))
			local back = Theme.Frame(f, UDim2.new(1, 0, 0, 8), UDim2.fromOffset(0, 18), nil, C0, 0.45)
			Theme.Round(back, 4)
			local now, base = st[2], st[3] or st[2]
			local lo, hi = math.min(now, base), math.max(now, base)
			Theme.Round(Theme.Frame(back, UDim2.fromScale(math.max(lo, 0.02), 1), nil, nil, Theme.Accent), 4)
			if hi > lo then
				local seg = Theme.Frame(back, UDim2.fromScale(hi - lo, 1), UDim2.fromScale(lo, 0), nil, now > base and Theme.Good or Theme.Danger)
				Theme.Round(seg, 3)
			end
		end
		local p = d.Progress
		if p and p.Exists and not p.Unlocked then
			local box = Theme.Glass(det, UDim2.new(1, -8, 0, 92))
			box.LayoutOrder = nextOrder()
			Theme.Label(box, "LOCKED", 12, Theme.Danger, LEFT, Theme.Display, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14))
			Theme.Label(box, d.Progress.Text, 15, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(12, 22), UDim2.new(1, -24, 0, 20))
			local back = Theme.Frame(box, UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 50), nil, C0, 0.45)
			Theme.Round(back, 4)
			Theme.Round(Theme.Frame(back, UDim2.fromScale(math.max(p.Frac, 0.01), 1), nil, nil, Theme.Accent), 4)
			Theme.Label(box, ("%d%%  |  buy forward price drops as you get closer"):format(math.floor(p.Frac * 100)), 11, Theme.Dim, LEFT, Theme.Body,
				UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 16))
		end
		for _, n in d.Notes or {} do textBlock(n, 13, Theme.Dim, Theme.Body, 18) end
		for _, bdef in d.Buttons or {} do
			local b = Widgets.FlatButton(det, bdef.Text, UDim2.new(1, -8, 0, 44), nil, nil, bdef.Primary)
			b.LayoutOrder, b.TextSize = nextOrder(), 18
			b.Activated:Connect(bdef.Fn)
		end
	end

	-- unlock info + buy-forward button for any item. Returns progress table (with .Text) and optional button def
	local function unlockInfo(kind, id, weapon)
		local d = data()
		local p = Armory.Progress(d, kind, id, weapon)
		if not p.Exists or p.Unlocked then return p, nil end
		if p.Track == "Player" then
			p.Text = ("REACH LEVEL %d  |  %s XP TO GO"):format(p.Level, commas(p.Remaining))
		else
			p.Text = ("%s LEVEL %d  |  %s XP TO GO"):format(weapon, p.Level, commas(p.Remaining))
		end
		local afford = d.Credits >= p.Price
		return p, { Text = ("BUY FORWARD  -  %s CR"):format(commas(p.Price)), Primary = afford, Fn = function()
			task.spawn(function()
				local ok, msg = AC.Buy(kind, id, weapon)
				say(ok and "UNLOCKED" or msg)
				page.render()
			end)
		end }
	end

	-- -------------------------------------------------------------- GUNSMITH
	local function gunWeapon() -- the weapon being customized
		local c = cls()
		return c and c[page.GunSlotKey].Id, c and c[page.GunSlotKey].Att
	end

	local function renderGunsmith()
		local weapon, atts = gunWeapon()
		local d = data()
		crumb.Text = ("ARMORY  >  %s  >  GUNSMITH"):format(weapon:upper())
		titleNav.Text, titleList.Text, titleDet.Text = weapon:upper() .. "  |  ATTACHMENT SLOTS", "ATTACHMENTS", "STATS"
		local wlvl, wxp, nextXP = Armory.WeaponLevelFromXP(d.WeaponXP[weapon] or 0)

		clear(nav)
		local info = Theme.Frame(nav, UDim2.new(1, -8, 0, 48), nil, nil, C0, 1)
		info.LayoutOrder = 0
		Theme.Label(info, ("WEAPON LEVEL %d%s   |   %d / %d ATTACHMENTS"):format(wlvl, wlvl >= Armory.MaxWeaponLevel and " (MAX)" or "", #atts, Armory.MaxAttachments),
			12, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(4, 0), UDim2.new(1, -8, 0, 22))
		local back = Theme.Frame(info, UDim2.new(1, -8, 0, 5), UDim2.fromOffset(4, 30), nil, C0, 0.45)
		local floor = Armory.WeaponLevelXP[wlvl]
		Theme.Frame(back, UDim2.fromScale(nextXP and math.clamp((wxp - floor) / (nextXP - floor), 0, 1) or 1, 1), nil, nil, Theme.Accent)

		local equippedBySlot = {}
		for _, id in atts do equippedBySlot[Armory.Attachments[id].Slot] = id end
		local firstSlot
		local n = 0
		for _, slot in Armory.Slots do
			if #Armory.AttachmentsFor(weapon, slot) > 0 then
				n += 1
				firstSlot = firstSlot or slot
				local eq = equippedBySlot[slot]
				row(nav, n, { Small = Armory.SlotLabels[slot], Name = eq and Armory.Attachments[eq].Name:upper() or "NONE", Dim = eq == nil,
					Selected = page.GunSlot == slot, Active = eq ~= nil, OnClick = function()
						page.GunSlot, page.AttItem = slot, nil
						page.render()
					end })
			end
		end
		if n == 0 then
			local l = Theme.Label(nav, "No attachments for this weapon.", 14, Theme.Dim, LEFT, Theme.Body, nil, UDim2.new(1, -8, 0, 24))
			l.LayoutOrder = 1
		end
		if page.GunSlot == nil or #Armory.AttachmentsFor(weapon, page.GunSlot) == 0 then page.GunSlot = firstSlot end

		clear(list)
		local slot = page.GunSlot
		if not slot then
			showDetail(nil)
			return
		end
		local current = equippedBySlot[slot]
		local function with(slotId) -- attachments list with this slot set to slotId (nil = removed)
			local out = {}
			for _, id in atts do
				if Armory.Attachments[id].Slot ~= slot then table.insert(out, id) end
			end
			if slotId then table.insert(out, slotId) end
			return out
		end
		local function setAtts(newList)
			local c = deepCopy(cls())
			c[page.GunSlotKey].Att = newList
			commit(c)
		end

		local ids = Armory.AttachmentsFor(weapon, slot)
		row(list, 0, { Name = "NONE", Selected = page.AttItem == "NONE", Active = current == nil, OnClick = function()
			page.AttItem = "NONE"
			page.render()
		end, Height = 44 })
		for i, id in ids do
			local a = Armory.Attachments[id]
			local p = Armory.Progress(d, "Att", id, weapon)
			row(list, i, { Small = ("WEAPON LEVEL %d"):format(a.Lvl), Name = a.Name:upper(), Dim = not p.Unlocked, Active = current == id,
				Tag = current == id and "EQUIPPED" or (p.Unlocked and "" or "LOCKED"), TagColor = current == id and Theme.Accent or Theme.Danger,
				Frac = (not p.Unlocked) and p.Frac or nil, Selected = page.AttItem == id,
				OnClick = function()
					page.AttItem = id
					page.render()
				end })
		end

		-- detail for the highlighted attachment (defaults to the equipped one)
		local focusId = page.AttItem
		if focusId == nil then focusId = current or "NONE" end
		local baseStats = Armory.Stats(Armory.Build(weapon, atts))
		if focusId == "NONE" then
			showDetail({ Tag = Armory.SlotLabels[slot], Name = "NO ATTACHMENT", Desc = "Leave this slot empty.", Stats = baseStats,
				Buttons = current and { { Text = "REMOVE", Primary = true, Fn = function() setAtts(with(nil)) end } } or {} })
			return
		end
		local a = Armory.Attachments[focusId]
		local newStats = Armory.Stats(Armory.Build(weapon, with(focusId)))
		local stats = {}
		for i, st in newStats do stats[i] = { st[1], st[2], baseStats[i][2] } end
		local p, buy = unlockInfo("Att", focusId, weapon)
		local buttons = {}
		if buy then table.insert(buttons, buy)
		elseif current == focusId then table.insert(buttons, { Text = "REMOVE", Primary = false, Fn = function() setAtts(with(nil)) end })
		else
			table.insert(buttons, { Text = "EQUIP", Primary = true, Fn = function()
				local list2 = with(focusId)
				if #list2 > Armory.MaxAttachments then say(("MAX %d ATTACHMENTS"):format(Armory.MaxAttachments)) return end
				setAtts(list2)
			end })
		end
		local notes = {}
		if a.Mods.Suppressed then table.insert(notes, "Shots are only seen and heard by nearby players.") end
		if a.Mods.Scope then table.insert(notes, "Aiming uses a full scope overlay.") end
		if a.Mods.ArmorPierce then table.insert(notes, ("%d%% of every hit ignores armor plates."):format(math.floor(a.Mods.ArmorPierce * 100 + 0.5))) end
		if a.Mods.Burn then table.insert(notes, ("Burns targets for %d s (%d damage per second, does not stack)."):format(a.Mods.Burn.Time, a.Mods.Burn.Dps)) end
		if a.Mods.PelletAdd then table.insert(notes, ("+%d pellets per shot."):format(a.Mods.PelletAdd)) end
		if a.Mods.ReloadEmpty then table.insert(notes, "Only speeds up reloads on an empty gun.") end
		showDetail({ Tag = Armory.SlotLabels[slot] .. "  |  " .. a.Name:upper(), Name = a.Name:upper(), Desc = a.Desc, Stats = stats, Progress = p, Buttons = buttons, Notes = notes })
	end

	-- -------------------------------------------------------------- PICK
	local function pickList(key)
		local c = cls()
		local items = {}
		local overkill = c.Perks[1] == "Overkill"
		if key == "Primary" or key == "Secondary" then
			for _, id in Armory.Ids("Weapon") do
				local w = Config.Weapons[id]
				local ok
				if key == "Primary" then ok = w.Class ~= "Melee" and (Config.IsPrimary(id) or overkill)
				else ok = (not Config.IsPrimary(id) or overkill) and id ~= c.Primary.Id end
				if ok then table.insert(items, { Kind = "Weapon", Id = id }) end
			end
		elseif key == "Lethal" or key == "Tactical" then
			for _, id in Armory.Ids("Equip", key) do table.insert(items, { Kind = "Equip", Id = id }) end
		elseif key:sub(1, 4) == "Perk" then
			table.insert(items, { Kind = "Perk", Id = "" })
			for _, id in Armory.Ids("Perk", tonumber(key:sub(5))) do table.insert(items, { Kind = "Perk", Id = id }) end
		else
			table.insert(items, { Kind = "Streak", Id = "" })
			for _, id in Armory.Ids("Streak") do table.insert(items, { Kind = "Streak", Id = id }) end
		end
		return items
	end

	-- detail table for one item (weapons, equipment, perks, streaks)
	local function itemDetail(kind, id, key)
		local d = data()
		if not id or id == "" then
			return { Tag = SLOT_TITLES[key] or "", Name = "NONE", Desc = "Leave this slot empty.",
				Buttons = key and { { Text = "EQUIP NONE", Primary = true, Fn = function() commit(withSlot(key, "")) page.Mode = "Class" page.render() end } } or {} }
		end
		local out = { Name = itemName(kind, id) }
		local p, buy = unlockInfo(kind, id)
		out.Progress = p
		local buttons = {}
		if kind == "Weapon" then
			local w = Config.Weapons[id]
			local cfgNow = Armory.Build(id, nil)
			out.Tag = Armory.ClassLabels[w.Class]:upper()
			local bits = { w.Class == "Melee" and "Light and heavy attacks. Hits from behind are lethal." or
				("%s  |  %d rounds  |  %s reload"):format(#Config.FireModesOf(w) > 1 and "Select fire (auto / semi)" or w.FireMode == "Auto" and "Full auto" or "Semi / single", w.MagSize, w.ReloadStyle:lower()) }
			out.Desc = bits[1]
			out.Stats = Armory.Stats(cfgNow)
			if p.Unlocked then
				local lvl = Armory.WeaponLevelFromXP(d.WeaponXP[id] or 0)
				out.Notes = { w.Class == "Melee" and "No attachments." or ("Weapon level %d / %d. Kills with it unlock attachments."):format(lvl, Armory.MaxWeaponLevel) }
			end
		elseif kind == "Equip" then
			local def = Config.Equipment[id]
			out.Tag = def.Kind:upper() .. " EQUIPMENT"
			out.Desc = Armory.EquipDesc[id]
			out.Stats = { { "Carried", math.clamp(def.Count / 4, 0, 1) } }
			if def.Radius then table.insert(out.Stats, { "Radius", math.clamp(def.Radius / 50, 0, 1) }) end
			if def.Duration then table.insert(out.Stats, { "Duration", math.clamp(def.Duration / 20, 0, 1) }) end
			if def.Damage then table.insert(out.Stats, { "Damage", math.clamp(def.Damage[1] / 200, 0, 1) }) end
		elseif kind == "Perk" then
			local def = Config.Perks[id]
			out.Tag, out.Desc = "PERK  |  SLOT " .. def.Slot, def.Desc
		else
			local def = Armory.Streaks[id]
			out.Tag = ("KILL STREAK  |  %s"):format(def.Kind:upper())
			out.Desc = def.Desc
			out.Notes = { ("Earned at %d kills in a row. Lost if you die."):format(def.Kills) }
		end
		if buy then
			table.insert(buttons, buy)
		elseif key then
			table.insert(buttons, { Text = "EQUIP", Primary = true, Fn = function()
				commit(withSlot(key, id))
				page.Mode = "Class"
				page.render()
			end })
		end
		if kind == "Weapon" and p.Unlocked and Config.Weapons[id].Class ~= "Melee" and Config.Weapons[id].Class ~= "Launcher" and (key == "Primary" or key == "Secondary") then
			table.insert(buttons, { Text = "CUSTOMIZE  (GUNSMITH)", Primary = false, Fn = function()
				commit(withSlot(key, id)) -- equip it first, then open the gunsmith for it
				page.Mode, page.GunSlotKey, page.GunSlot, page.AttItem = "Gun", key, nil, nil
				page.render()
			end })
		end
		out.Buttons = buttons
		return out
	end

	local function renderPick()
		local key, c, d = page.Focus, cls(), data()
		crumb.Text = ("ARMORY  >  %s  >  %s"):format(c.Name, SLOT_TITLES[key])
		titleList.Text, titleDet.Text = "SELECT " .. SLOT_TITLES[key], "DETAILS"
		clear(list)
		local equippedKind, equippedId = slotItem(c, key)
		local items = pickList(key)
		local focus = page.PickItem
		for i, it in items do
			local p = Armory.Progress(d, it.Kind, it.Id ~= "" and it.Id or nil)
			local locked = it.Id ~= "" and p.Exists and not p.Unlocked
			local lvl = it.Id ~= "" and Armory.Requirement(it.Kind, it.Id)
			row(list, i, { Small = it.Kind == "Weapon" and Armory.ClassLabels[Config.Weapons[it.Id].Class]:upper() or nil, Name = itemName(it.Kind, it.Id),
				Dim = locked, Tag = it.Id == equippedId and "EQUIPPED" or (locked and ("LV %d"):format(lvl.Level) or ""),
				TagColor = it.Id == equippedId and Theme.Accent or Theme.Danger, Frac = locked and p.Frac or nil,
				Selected = focus == it.Id, Active = it.Id == equippedId, OnClick = function()
					page.PickItem = it.Id
					page.render()
				end })
		end
		local show = focus
		if show == nil then show = equippedId end
		showDetail(itemDetail(equippedKind, show, key))
	end

	-- -------------------------------------------------------------- CLASS
	local function renderClass()
		local d, c = data(), cls()
		crumb.Text = "ARMORY  >  " .. c.Name
		titleNav.Text, titleList.Text, titleDet.Text = "CLASSES", "LOADOUT", "DETAILS"

		clear(nav)
		for i = 1, Armory.MaxClasses do
			local unlocked = Armory.ClassUnlocked(d, i)
			local cl = d.Classes[i]
			row(nav, i, { Small = i == d.Selected and "ACTIVE CLASS" or ("CLASS %d"):format(i), Name = unlocked and cl.Name or "LOCKED", Dim = not unlocked,
				Tag = unlocked and "" or ("LV %d"):format(Armory.ClassLevels[i]), Selected = i == page.ClassIdx, Active = i == d.Selected, Height = 46,
				OnClick = function()
					page.ClassIdx = i
					page.render()
				end })
		end

		clear(list)
		if not Armory.ClassUnlocked(d, page.ClassIdx) then
			local p, buy = unlockInfo("Class", page.ClassIdx)
			showDetail({ Tag = "CUSTOM CLASS", Name = ("CLASS %d"):format(page.ClassIdx), Desc = "Another custom class slot.", Progress = p, Buttons = { buy } })
			return
		end

		-- rename box
		local box = Theme.Glass(list, UDim2.new(1, -8, 0, 40))
		box.LayoutOrder = 0
		Theme.Label(box, "NAME", 10, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(14, 0), UDim2.fromOffset(40, 40))
		local tb = Instance.new("TextBox")
		tb.BackgroundTransparency, tb.Text, tb.PlaceholderText, tb.ClearTextOnFocus = 1, c.Name, "CLASS NAME", false
		tb.Font, tb.TextSize, tb.TextColor3, tb.TextXAlignment = Theme.Display, 18, Theme.Text, LEFT
		tb.Position, tb.Size, tb.MaxVisibleGraphemes = UDim2.fromOffset(58, 0), UDim2.new(1, -70, 1, 0), Armory.ClassNameLen
		tb.Parent = box
		tb.FocusLost:Connect(function()
			if tb.Text ~= c.Name then
				local nc = deepCopy(cls())
				nc.Name = tb.Text
				commit(nc)
			end
		end)

		for i, key in SLOT_KEYS do
			local kind, id = slotItem(c, key)
			local extra = ""
			if key == "Primary" or key == "Secondary" then
				local n = #c[key].Att
				extra = n > 0 and ("%d ATT"):format(n) or ""
			end
			row(list, i, { Small = SLOT_TITLES[key], Name = itemName(kind, id), Dim = id == "", Tag = extra, TagColor = Theme.Accent, Selected = page.Focus == key,
				OnClick = function()
					page.Focus = key
					page.PickItem = nil
					page.render()
				end })
		end

		local kind, id = slotItem(c, page.Focus)
		local det2 = itemDetail(kind, id, nil)
		local buttons = { { Text = "CHANGE", Primary = true, Fn = function()
			page.Mode, page.PickItem = "Pick", nil
			page.render()
		end } }
		if kind == "Weapon" and Config.Weapons[id].Class ~= "Melee" and Config.Weapons[id].Class ~= "Launcher" then
			table.insert(buttons, { Text = "CUSTOMIZE  (GUNSMITH)", Primary = false, Fn = function()
				page.Mode, page.GunSlotKey, page.GunSlot, page.AttItem = "Gun", page.Focus, nil, nil
				page.render()
			end })
			-- show the attachments currently on the gun
			local atts = c[page.Focus].Att
			if #atts > 0 then
				local names = {}
				for _, a in atts do table.insert(names, Armory.Attachments[a].Name) end
				det2.Notes = { "Attachments: " .. table.concat(names, ", ") }
				det2.Stats = Armory.Stats(Armory.Build(id, atts))
			end
		end
		det2.Buttons = buttons
		det2.Progress = nil
		showDetail(det2)
	end

	-- -------------------------------------------------------------- render + header buttons
	local function renderHeader()
		local d = data()
		local unlocked = d and Armory.ClassUnlocked(d, page.ClassIdx)
		selectBtn.Visible = unlocked == true
		local active = d and d.Selected == page.ClassIdx
		selectBtn.Text = active and "ACTIVE CLASS" or "SELECT CLASS"
		respawnBtn.Visible = unlocked == true and MatchClient.IsDeployed()
	end

	page.render = function()
		if not holder.Parent then return end
		local d = data()
		if not d then
			crumb.Text = "ARMORY  (LOADING...)"
			return
		end
		local listScroll = list.CanvasPosition
		if page.Mode == "Gun" then renderGunsmith()
		elseif page.Mode == "Pick" then renderPick()
		else renderClass() end
		renderHeader()
		task.defer(function() list.CanvasPosition = listScroll end)
	end

	selectBtn.Activated:Connect(function()
		task.spawn(function()
			if AC.Select(page.ClassIdx) then say("CLASS SELECTED - APPLIES ON NEXT SPAWN") else say("COULD NOT SELECT") end
			page.render()
		end)
	end)
	respawnBtn.Activated:Connect(function()
		task.spawn(function()
			AC.Select(page.ClassIdx)
			Remotes.Respawn:FireServer() -- the server only allows this right after spawning
			say("REQUESTED RESPAWN")
			menu:Close()
		end)
	end)

	AC.OnChanged(function() page.render() end)

	return {
		Show = function()
			task.spawn(function()
				AC.Load()
				local d = data()
				if d and not page.Started then
					page.Started, page.ClassIdx = true, d.Selected
				end
				page.render()
			end)
		end,
		Back = function()
			if page.Mode == "Gun" or page.Mode == "Pick" then
				page.Mode = "Class"
				page.render()
				return true
			end
			return false
		end,
		Focus = function()
			local first = list:FindFirstChildWhichIsA("TextButton", true)
			if first then GuiService.SelectedObject = first end
		end,
	}
end

function ArmoryPage.Register(MainMenu)
	MainMenu.RegisterPage("ARMORY", ArmoryPage.build)
end

return ArmoryPage
