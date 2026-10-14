-- Cosmetics: everything a player can wear or show off, as pure data + logic shared by the server (validation, purchases) and the client (menu, effects).
--
--   OPERATORS     colored placeholder rigs (recolors the character; "Your Avatar" leaves the Roblox avatar alone)
--   PLAYER CARDS  the banner behind your name (gradient + pattern)
--   EMBLEMS       the badge on the card
--   TITLES        the line of text under your name
--   EMOTES        procedural third-person emotes, 6 wheel slots (see Emotes.luau)
--   TRACERS       bullet tracer styles (see TracerFX.luau)
--
-- Unlocks work like the Armory: every item has a player level. Reach it and it is yours, or buy it early with credits.
-- The price drops the closer you are to the level (same formula and rates as Armory.Econ), and rarer items cost more.
-- Add an item = one line in the tables below. Replace a placeholder operator with a real model later by reading the
-- "Operator" character attribute (set by CosmeticsService) and swapping the character / accessories.
local Config = require(script.Parent.Config)
local Armory = require(script.Parent.Armory)
local Progression = require(script.Parent.Progression)
local Emotes = require(script.Parent.Emotes)

local Cosmetics = {}

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

Cosmetics.Categories = { "Operator", "Card", "Emblem", "Title", "Emote", "Tracer" }
Cosmetics.Labels = { Operator = "OPERATORS", Card = "PLAYER CARDS", Emblem = "EMBLEMS", Title = "TITLES", Emote = "EMOTES", Tracer = "TRACERS" }
Cosmetics.Singular = { Operator = "OPERATOR", Card = "PLAYER CARD", Emblem = "EMBLEM", Title = "TITLE", Emote = "EMOTE", Tracer = "TRACER" }
Cosmetics.EmoteSlots = 6
Cosmetics.Rarities = {
	Common = { Color = C(170, 176, 184), Price = 1 },
	Rare = { Color = C(90, 160, 255), Price = 1.5 },
	Epic = { Color = C(190, 110, 255), Price = 2.2 },
	Legendary = { Color = C(255, 178, 64), Price = 3.5 },
}

Cosmetics.Items = {}
Cosmetics.ById = {}
for _, cat in Cosmetics.Categories do
	Cosmetics.Items[cat] = {}
	Cosmetics.ById[cat] = {}
end

local function add(cat, def)
	def.Category = cat
	def.Level = math.clamp(def.Level or 1, 1, Config.Progression.MaxLevel)
	def.Rarity = def.Rarity or "Common"
	def.Order = #Cosmetics.Items[cat] + 1
	table.insert(Cosmetics.Items[cat], def)
	Cosmetics.ById[cat][def.Id] = def
end

-- ================================================================ operators (placeholder rigs)
-- Skin / Head (nil = skin) / Torso / Sleeve / Pants / Boots / Vest / Accent (visor band). Avatar = true leaves your own avatar untouched.
local SKIN = C(226, 176, 140)
add("Operator", { Id = "Default", Name = "Your Avatar", Role = "NO CHANGE", Avatar = true, Level = 1, Skin = SKIN, Torso = C(120, 128, 136), Sleeve = C(120, 128, 136),
	Pants = C(96, 102, 110), Boots = C(50, 54, 60), Vest = C(70, 76, 82), Accent = C(255, 178, 64), Desc = "Keep the Roblox avatar you joined with." })
add("Operator", { Id = "Vanguard", Name = "Vanguard", Role = "ASSAULT", Level = 1, Skin = SKIN, Torso = C(74, 84, 60), Sleeve = C(62, 72, 50), Pants = C(58, 62, 50),
	Boots = C(30, 28, 26), Vest = C(44, 50, 42), Accent = C(255, 178, 64), Desc = "Placeholder rig. Olive drab fatigues with an amber visor band." })
add("Operator", { Id = "Sandstorm", Name = "Sandstorm", Role = "RECON", Level = 4, Skin = C(198, 150, 112), Torso = C(168, 146, 104), Sleeve = C(150, 130, 92), Pants = C(140, 122, 88),
	Boots = C(70, 56, 40), Vest = C(110, 96, 70), Accent = C(240, 230, 190), Desc = "Placeholder rig. Desert tan kit." })
add("Operator", { Id = "Nightshade", Name = "Nightshade", Role = "STEALTH", Rarity = "Rare", Level = 8, Skin = SKIN, Head = C(24, 22, 30), Torso = C(30, 28, 38), Sleeve = C(26, 24, 34),
	Pants = C(22, 20, 28), Boots = C(14, 14, 18), Vest = C(40, 34, 56), Accent = C(170, 90, 255), Desc = "Placeholder rig. Blacked-out with a violet visor band." })
add("Operator", { Id = "Viper", Name = "Viper", Role = "SUPPORT", Rarity = "Rare", Level = 12, Skin = SKIN, Head = C(30, 52, 34), Torso = C(40, 70, 44), Sleeve = C(34, 60, 38),
	Pants = C(30, 50, 34), Boots = C(18, 24, 18), Vest = C(24, 36, 26), Accent = C(150, 255, 80), Desc = "Placeholder rig. Dark green with a toxic lime band." })
add("Operator", { Id = "Ember", Name = "Ember", Role = "BREACHER", Rarity = "Rare", Level = 16, Skin = SKIN, Torso = C(52, 50, 54), Sleeve = C(44, 42, 46), Pants = C(36, 36, 40),
	Boots = C(20, 18, 18), Vest = C(70, 36, 20), Accent = C(255, 120, 40), Desc = "Placeholder rig. Charcoal with orange trim." })
add("Operator", { Id = "Cobalt", Name = "Cobalt", Role = "ENFORCER", Rarity = "Epic", Level = 22, Skin = SKIN, Torso = C(28, 44, 90), Sleeve = C(24, 38, 78), Pants = C(22, 30, 58),
	Boots = C(14, 16, 26), Vest = C(30, 36, 60), Accent = C(80, 190, 255), Desc = "Placeholder rig. Navy blue with an electric blue band." })
add("Operator", { Id = "Frostbite", Name = "Frostbite", Role = "SNIPER", Rarity = "Epic", Level = 28, Skin = SKIN, Head = C(225, 235, 245), Torso = C(220, 230, 240), Sleeve = C(200, 214, 228),
	Pants = C(190, 204, 220), Boots = C(120, 134, 150), Vest = C(150, 176, 205), Accent = C(120, 210, 255), Desc = "Placeholder rig. Winter whites with an ice band." })
add("Operator", { Id = "Crimson", Name = "Crimson", Role = "ASSASSIN", Rarity = "Epic", Level = 34, Skin = SKIN, Head = C(60, 14, 18), Torso = C(110, 24, 30), Sleeve = C(92, 20, 26),
	Pants = C(60, 16, 20), Boots = C(24, 10, 12), Vest = C(40, 12, 14), Accent = C(255, 70, 70), Desc = "Placeholder rig. Maroon with a red band." })
add("Operator", { Id = "Goldleaf", Name = "Goldleaf", Role = "VETERAN", Rarity = "Legendary", Level = 45, Skin = SKIN, Head = C(30, 28, 24), Torso = C(34, 32, 28), Sleeve = C(30, 28, 24),
	Pants = C(26, 24, 22), Boots = C(120, 96, 40), Vest = C(150, 120, 50), Accent = C(255, 205, 80), Desc = "Placeholder rig. Black and gold." })

-- ================================================================ player cards
-- A / B = gradient colors, Pattern = None | Stripes | Chevron | Dots | Grid, PatternColor, Accent = title color.
add("Card", { Id = "Slate", Name = "Slate", Level = 1, A = C(44, 52, 62), B = C(24, 28, 34), Pattern = "None", PatternColor = C(255, 255, 255), Accent = C(255, 178, 64) })
add("Card", { Id = "Hazard", Name = "Hazard", Level = 3, A = C(54, 50, 30), B = C(26, 24, 16), Pattern = "Chevron", PatternColor = C(255, 205, 40), Accent = C(255, 205, 40) })
add("Card", { Id = "Ember Stripe", Name = "Ember Stripe", Level = 6, A = C(74, 34, 22), B = C(30, 20, 20), Pattern = "Stripes", PatternColor = C(255, 140, 60), Accent = C(255, 150, 70) })
add("Card", { Id = "Arctic", Name = "Arctic", Level = 9, A = C(70, 96, 120), B = C(28, 40, 54), Pattern = "Stripes", PatternColor = C(220, 240, 255), Accent = C(190, 235, 255) })
add("Card", { Id = "Jungle", Name = "Jungle", Level = 12, A = C(44, 78, 46), B = C(18, 34, 22), Pattern = "Dots", PatternColor = C(170, 255, 150), Accent = C(170, 255, 130) })
add("Card", { Id = "Neon Grid", Name = "Neon Grid", Rarity = "Rare", Level = 15, A = C(30, 20, 62), B = C(12, 10, 28), Pattern = "Grid", PatternColor = C(120, 200, 255), Accent = C(120, 220, 255) })
add("Card", { Id = "Midnight", Name = "Midnight", Rarity = "Rare", Level = 20, A = C(24, 30, 66), B = C(8, 10, 24), Pattern = "Dots", PatternColor = C(140, 160, 255), Accent = C(150, 170, 255) })
add("Card", { Id = "Royal", Name = "Royal", Rarity = "Epic", Level = 25, A = C(86, 40, 130), B = C(30, 16, 54), Pattern = "Chevron", PatternColor = C(230, 190, 255), Accent = C(235, 200, 255) })
add("Card", { Id = "Blood Moon", Name = "Blood Moon", Rarity = "Epic", Level = 32, A = C(120, 24, 30), B = C(34, 8, 12), Pattern = "Stripes", PatternColor = C(255, 90, 90), Accent = C(255, 120, 120) })
add("Card", { Id = "Gold Rush", Name = "Gold Rush", Rarity = "Legendary", Level = 40, A = C(150, 112, 30), B = C(54, 38, 10), Pattern = "Chevron", PatternColor = C(255, 230, 140), Accent = C(255, 235, 150) })

-- ================================================================ emblems
-- Shape = Circle | Diamond | Square | Ring | Crosshair, Mark = 1-2 letters drawn on top.
add("Emblem", { Id = "Rookie", Name = "Rookie", Level = 1, Shape = "Square", Mark = "I", Color = C(190, 196, 204) })
add("Emblem", { Id = "Alpha", Name = "Alpha", Level = 2, Shape = "Diamond", Mark = "A", Color = C(255, 178, 64) })
add("Emblem", { Id = "Crosshair", Name = "Crosshair", Level = 5, Shape = "Crosshair", Mark = "", Color = C(235, 240, 245) })
add("Emblem", { Id = "Bravo", Name = "Bravo", Level = 8, Shape = "Circle", Mark = "B", Color = C(120, 190, 235) })
add("Emblem", { Id = "Hazard", Name = "Hazard", Level = 11, Shape = "Square", Mark = "!", Color = C(255, 205, 40) })
add("Emblem", { Id = "Frostbyte", Name = "Frostbyte", Rarity = "Rare", Level = 16, Shape = "Ring", Mark = "F", Color = C(150, 220, 255) })
add("Emblem", { Id = "Reaper", Name = "Reaper", Rarity = "Rare", Level = 21, Shape = "Diamond", Mark = "R", Color = C(235, 70, 70) })
add("Emblem", { Id = "Phoenix", Name = "Phoenix", Rarity = "Epic", Level = 27, Shape = "Circle", Mark = "P", Color = C(255, 130, 50) })
add("Emblem", { Id = "Royal", Name = "Royal", Rarity = "Epic", Level = 33, Shape = "Ring", Mark = "K", Color = C(200, 130, 255) })
add("Emblem", { Id = "Golden Eye", Name = "Golden Eye", Rarity = "Legendary", Level = 42, Shape = "Crosshair", Mark = "", Color = C(255, 205, 80) })

-- ================================================================ titles
local titles = {
	{ "Rookie", 1 }, { "Trigger Happy", 5 }, { "Plate Collector", 9 }, { "Headhunter", 14 }, { "Marksman", 19 },
	{ "Last Man Standing", 24, "Rare" }, { "Ghost", 30, "Rare" }, { "Warzone Veteran", 38, "Epic" }, { "No Scope Needed", 46, "Epic" }, { "Living Legend", 60, "Legendary" },
}
for _, t in titles do add("Title", { Id = t[1], Name = t[1], Level = t[2], Rarity = t[3] }) end

-- ================================================================ reward-only items (Reward = where they come from)
-- Not unlocked by level and not for sale: AchievementService puts them in your Owned list (see Achievements.luau / Mastery.luau).
local function reward(cat, def, why)
	def.Reward, def.Level = why, 1
	add(cat, def)
end
reward("Title", { Id = "Sharpshooter", Name = "Sharpshooter", Rarity = "Rare" }, "ACHIEVEMENT: HEAD CASE")
reward("Title", { Id = "Exterminator", Name = "Exterminator", Rarity = "Epic" }, "ACHIEVEMENT: EXTERMINATOR")
reward("Title", { Id = "Ace", Name = "Ace", Rarity = "Epic" }, "ACHIEVEMENT: ACE")
reward("Title", { Id = "Unstoppable", Name = "Unstoppable", Rarity = "Rare" }, "ACHIEVEMENT: UNSTOPPABLE")
reward("Title", { Id = "Closer", Name = "Closer", Rarity = "Rare" }, "ACHIEVEMENT: CLOSER")
reward("Title", { Id = "Apprentice", Name = "Apprentice", Rarity = "Common" }, "MASTERY: BRONZE ON ANY WEAPON")
reward("Title", { Id = "Adept", Name = "Adept", Rarity = "Rare" }, "MASTERY: SILVER ON ANY WEAPON")
reward("Title", { Id = "Gold Standard", Name = "Gold Standard", Rarity = "Epic" }, "MASTERY: GOLD ON ANY WEAPON")
reward("Title", { Id = "Platinum Hands", Name = "Platinum Hands", Rarity = "Epic" }, "MASTERY: PLATINUM ON ANY WEAPON")
reward("Title", { Id = "Diamond Cutter", Name = "Diamond Cutter", Rarity = "Legendary" }, "MASTERY: DIAMOND ON ANY WEAPON")
reward("Emblem", { Id = "Veteran", Name = "Veteran", Rarity = "Rare", Shape = "Square", Mark = "V", Color = C(150, 170, 120) }, "ACHIEVEMENT: SEASONED")
reward("Emblem", { Id = "Champion", Name = "Champion", Rarity = "Epic", Shape = "Ring", Mark = "C", Color = C(255, 205, 80) }, "ACHIEVEMENT: CHAMPION")
reward("Emblem", { Id = "MasteryBronze", Name = "Bronze Master", Rarity = "Common", Shape = "Diamond", Mark = "B", Color = C(205, 127, 50) }, "MASTERY: BRONZE ON ANY WEAPON")
reward("Emblem", { Id = "MasterySilver", Name = "Silver Master", Rarity = "Rare", Shape = "Diamond", Mark = "S", Color = C(192, 198, 206) }, "MASTERY: SILVER ON ANY WEAPON")
reward("Emblem", { Id = "MasteryGold", Name = "Gold Master", Rarity = "Epic", Shape = "Diamond", Mark = "G", Color = C(255, 205, 80) }, "MASTERY: GOLD ON ANY WEAPON")
reward("Emblem", { Id = "MasteryPlatinum", Name = "Platinum Master", Rarity = "Epic", Shape = "Circle", Mark = "P", Color = C(150, 220, 235) }, "MASTERY: PLATINUM ON ANY WEAPON")
reward("Emblem", { Id = "MasteryDiamond", Name = "Diamond Master", Rarity = "Legendary", Shape = "Circle", Mark = "D", Color = C(130, 190, 255) }, "MASTERY: DIAMOND ON ANY WEAPON")

-- ================================================================ emotes (poses live in Emotes.luau)
local emoteMeta = {
	Wave = { 1 }, Salute = { 1 }, Point = { 1 }, Shrug = { 1 },
	Flex = { 10, "Rare" }, Facepalm = { 14, "Rare" }, Cheer = { 20, "Epic" }, Dance = { 26, "Epic" },
}
for _, id in Emotes.List do
	local m = emoteMeta[id] or { 1 }
	add("Emote", { Id = id, Name = Emotes.Defs[id].Name, Level = m[1], Rarity = m[2], Duration = Emotes.Defs[id].Duration })
end

-- ================================================================ tracers
-- Color, Width / Length (studs), Speed (studs/s). Trail = glowing ribbon, Sparks = particles, Rainbow = random hue per bullet.
add("Tracer", { Id = "Classic", Name = "Classic", Level = 1, Color = C(255, 215, 140), Width = 0.06, Length = 5, Speed = 650 })
add("Tracer", { Id = "Laser", Name = "Laser", Level = 3, Color = C(255, 60, 60), Width = 0.05, Length = 10, Speed = 900 })
add("Tracer", { Id = "Toxic", Name = "Toxic", Level = 7, Color = C(130, 255, 90), Width = 0.07, Length = 5, Speed = 650 })
add("Tracer", { Id = "Plasma", Name = "Plasma", Rarity = "Rare", Level = 12, Color = C(80, 200, 255), Width = 0.1, Length = 7, Speed = 700, Trail = true })
add("Tracer", { Id = "Violet", Name = "Violet", Rarity = "Rare", Level = 17, Color = C(190, 100, 255), Width = 0.08, Length = 6, Speed = 700, Sparks = true })
add("Tracer", { Id = "Ember", Name = "Ember", Rarity = "Epic", Level = 22, Color = C(255, 120, 40), Width = 0.09, Length = 6, Speed = 650, Sparks = true, Trail = true })
add("Tracer", { Id = "Frost", Name = "Frost", Rarity = "Epic", Level = 28, Color = C(210, 240, 255), Width = 0.08, Length = 8, Speed = 750, Trail = true, Sparks = true })
add("Tracer", { Id = "Prismatic", Name = "Prismatic", Rarity = "Epic", Level = 35, Color = C(255, 255, 255), Width = 0.09, Length = 7, Speed = 750, Rainbow = true, Trail = true })
add("Tracer", { Id = "Gold", Name = "Gold", Rarity = "Legendary", Level = 42, Color = C(255, 200, 60), Width = 0.1, Length = 9, Speed = 800, Trail = true, Sparks = true })

for _, cat in Cosmetics.Categories do
	table.sort(Cosmetics.Items[cat], function(a, b) -- by level, then in the order they were added
		if a.Level ~= b.Level then return a.Level < b.Level end
		return a.Order < b.Order
	end)
end

-- ================================================================ lookups
function Cosmetics.Get(cat, id)
	local t = Cosmetics.ById[cat]
	return t and type(id) == "string" and t[id] or nil
end

function Cosmetics.List(cat) return Cosmetics.Items[cat] or {} end
function Cosmetics.Operator(id) return Cosmetics.Get("Operator", id) end
function Cosmetics.RarityColor(def) return Cosmetics.Rarities[def.Rarity or "Common"].Color end
function Cosmetics.Key(cat, id) return cat .. ":" .. id end

-- ================================================================ unlocks / prices
-- xp = the player's total XP, owned = the table of bought items ("Operator:Viper" = true).
-- Returns { Exists, Unlocked, Bought, Level, Need, Have, Remaining, Frac, Price (credits, nil when unlocked) }
function Cosmetics.Progress(xp, owned, cat, id)
	local def = Cosmetics.Get(cat, id)
	if not def then return { Exists = false, Unlocked = false } end
	if def.Reward then -- achievement / mastery reward: never unlocked by level, never for sale
		local bought = owned ~= nil and owned[Cosmetics.Key(cat, id)] == true
		return { Exists = true, Unlocked = Armory.UnlockAll or bought, Bought = bought, Reward = def.Reward, Level = def.Level, Need = 0, Have = 0, Remaining = 0, Frac = 0 }
	end
	local E = Armory.Econ
	local need = Progression.XPForLevel(def.Level)
	local have = xp or 0
	local bought = owned ~= nil and owned[Cosmetics.Key(cat, id)] == true
	local remaining = math.max(0, need - have)
	local unlocked = Armory.UnlockAll or bought or remaining <= 0
	local p = { Exists = true, Level = def.Level, Need = need, Have = math.min(have, need), Remaining = remaining,
		Frac = need > 0 and math.clamp(have / need, 0, 1) or 1, Unlocked = unlocked, Bought = bought }
	if not unlocked then
		local mult = Cosmetics.Rarities[def.Rarity].Price
		p.Price = math.clamp(math.ceil(remaining * E.PlayerXPPrice * mult), E.MinPrice, E.MaxPrice)
	end
	return p
end

function Cosmetics.IsUnlocked(xp, owned, cat, id)
	local p = Cosmetics.Progress(xp, owned, cat, id)
	return p.Exists and p.Unlocked
end

-- ================================================================ saved data
function Cosmetics.Default()
	return {
		Owned = {},
		Equipped = { Operator = "Default", Card = "Slate", Emblem = "Rookie", Title = "Rookie", Tracer = "Classic", Emotes = { "Wave", "Salute", "Point", "Shrug", "", "" } },
	}
end

-- Turns whatever was saved / sent into a valid blob: unknown ids dropped, anything not unlocked falls back to the default.
function Cosmetics.Sanitize(xp, blob)
	local clean = Cosmetics.Default()
	if type(blob) ~= "table" then return clean end
	if type(blob.Owned) == "table" then
		for key, v in blob.Owned do
			if v == true and type(key) == "string" then
				local cat, id = key:match("^(%a+):(.+)$")
				if cat and Cosmetics.Get(cat, id) then clean.Owned[key] = true end
			end
		end
	end
	local E = type(blob.Equipped) == "table" and blob.Equipped or {}
	for _, cat in { "Operator", "Card", "Emblem", "Title", "Tracer" } do
		local id = E[cat]
		if Cosmetics.IsUnlocked(xp, clean.Owned, cat, id) then clean.Equipped[cat] = id end
	end
	local slots, seen = {}, {}
	for i = 1, Cosmetics.EmoteSlots do
		local id = type(E.Emotes) == "table" and E.Emotes[i] or clean.Equipped.Emotes[i]
		if type(id) ~= "string" or seen[id] or not Cosmetics.IsUnlocked(xp, clean.Owned, "Emote", id) then id = "" end
		if id ~= "" then seen[id] = true end
		slots[i] = id
	end
	clean.Equipped.Emotes = slots
	return clean
end

return Cosmetics
