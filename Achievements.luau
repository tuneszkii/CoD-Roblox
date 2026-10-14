-- In-game achievements: pure data (the server tracks progress in AchievementService, the client reads this list for its screens / toasts).
-- Every achievement watches one KEY:
--   "Tag:<Tag>"          how many times you earned that score tag (Config.Scoring.Tags: Kill, Headshot, Assist, DoubleKill, Longshot, Capture, ...)
--   "Wins", "Matches"    matches won / finished      "Flawless" = matches won without dying     "MatchKills" = most kills in one match (Max)
--   "BestStreak" (Max)   best kill streak            "Level" (Max) = player level
--   "Mastery:<Tier>"     weapons that reached that mastery tier (Mastery.Tiers)     "Achievements" = achievements completed
-- Mode "Add" counts up, "Max" keeps the best value. Goal = the number needed.
-- Reward = { XP, Credits, Title, Emblem }. Title / Emblem must be reward-only items in Cosmetics (granted once, then yours to equip).
-- Add one = one line in the list below.
local A = {}

A.Categories = { "COMBAT", "MATCH", "PROGRESS", "MASTERY" }
A.List = {}
A.ById = {}
A.ByKey = {} -- [key] = { def, ... }

local function add(cat, id, name, desc, key, goal, reward, mode)
	local def = { Id = id, Cat = cat, Name = name, Desc = desc, Key = key, Goal = goal, Reward = reward or {}, Mode = mode or "Add" }
	def.Order = #A.List + 1
	table.insert(A.List, def)
	A.ById[id] = def
	A.ByKey[key] = A.ByKey[key] or {}
	table.insert(A.ByKey[key], def)
end

-- ---------------------------------------------------------------- combat
add("COMBAT", "Kills1", "Welcome to the Fight", "Get your first kill.", "Tag:Kill", 1, { XP = 100 })
add("COMBAT", "Kills100", "Gun for Hire", "Get 100 kills.", "Tag:Kill", 100, { XP = 600, Credits = 200 })
add("COMBAT", "Kills500", "Seasoned", "Get 500 kills.", "Tag:Kill", 500, { XP = 2000, Credits = 600, Emblem = "Veteran" })
add("COMBAT", "Kills2500", "Exterminator", "Get 2,500 kills.", "Tag:Kill", 2500, { XP = 8000, Credits = 2500, Title = "Exterminator" })
add("COMBAT", "Head10", "Aim High", "Get 10 headshot kills.", "Tag:Headshot", 10, { XP = 200 })
add("COMBAT", "Head100", "Head Case", "Get 100 headshot kills.", "Tag:Headshot", 100, { XP = 1500, Credits = 500, Title = "Sharpshooter" })
add("COMBAT", "Head500", "Dome Specialist", "Get 500 headshot kills.", "Tag:Headshot", 500, { XP = 6000, Credits = 2000 })
add("COMBAT", "Assist25", "Team Player", "Get 25 assists.", "Tag:Assist", 25, { XP = 400, Credits = 150 })
add("COMBAT", "Assist150", "Support Main", "Get 150 assists.", "Tag:Assist", 150, { XP = 2000, Credits = 600 })
add("COMBAT", "Double10", "Two for One", "Get 10 Double Kills.", "Tag:DoubleKill", 10, { XP = 500, Credits = 200 })
add("COMBAT", "Triple5", "Hat Trick", "Get 5 Triple Kills.", "Tag:TripleKill", 5, { XP = 900, Credits = 300 })
add("COMBAT", "Quad1", "Four Play", "Get a Quad Kill.", "Tag:QuadKill", 1, { XP = 800, Credits = 250 })
add("COMBAT", "Penta1", "Ace", "Get a Penta Kill.", "Tag:PentaKill", 1, { XP = 2500, Credits = 1000, Title = "Ace" })
add("COMBAT", "Long10", "Long Arm", "Get 10 Longshot kills.", "Tag:Longshot", 10, { XP = 600, Credits = 200 })
add("COMBAT", "Point25", "Up Close", "Get 25 Point Blank kills.", "Tag:PointBlank", 25, { XP = 600, Credits = 200 })
add("COMBAT", "Back10", "Silent Takedown", "Get 10 Backstab kills.", "Tag:Backstab", 10, { XP = 600, Credits = 200 })
add("COMBAT", "Revenge10", "Payback", "Get 10 Revenge kills.", "Tag:Revenge", 10, { XP = 500, Credits = 150 })
add("COMBAT", "Collat5", "Two Birds", "Get 5 Collateral kills.", "Tag:Collateral", 5, { XP = 800, Credits = 250 })
add("COMBAT", "Wall10", "Through the Wall", "Get 10 Wallbang kills.", "Tag:Wallbang", 10, { XP = 600, Credits = 200 })
add("COMBAT", "Armor50", "Plate Breaker", "Break the armor of 50 enemies.", "Tag:ArmorBreak", 50, { XP = 700, Credits = 250 })
add("COMBAT", "Down25", "Down You Go", "Knock down 25 enemies.", "Tag:KnockDown", 25, { XP = 500, Credits = 150 })
add("COMBAT", "Revive10", "Medic!", "Revive 10 teammates.", "Tag:Revive", 10, { XP = 700, Credits = 250 })
add("COMBAT", "Finish10", "Finish Him", "Finish off 10 downed enemies.", "Tag:Finisher", 10, { XP = 600, Credits = 200 })
add("COMBAT", "Streak5", "Hot Streak", "Reach a 5 kill streak.", "BestStreak", 5, { XP = 400, Credits = 150 }, "Max")
add("COMBAT", "Streak10", "Unstoppable", "Reach a 10 kill streak.", "BestStreak", 10, { XP = 1500, Credits = 500, Title = "Unstoppable" }, "Max")

-- ---------------------------------------------------------------- match
add("MATCH", "Matches1", "Deployed", "Finish a match.", "Matches", 1, { XP = 150 })
add("MATCH", "Matches10", "Regular", "Finish 10 matches.", "Matches", 10, { XP = 800, Credits = 250 })
add("MATCH", "Matches50", "Lifer", "Finish 50 matches.", "Matches", 50, { XP = 3000, Credits = 1000 })
add("MATCH", "Wins1", "Victory", "Win a match.", "Wins", 1, { XP = 300, Credits = 100 })
add("MATCH", "Wins10", "Winner", "Win 10 matches.", "Wins", 10, { XP = 1500, Credits = 500 })
add("MATCH", "Wins25", "Closer", "Win 25 matches.", "Wins", 25, { XP = 3000, Credits = 1000, Title = "Closer" })
add("MATCH", "Wins50", "Champion", "Win 50 matches.", "Wins", 50, { XP = 6000, Credits = 2000, Emblem = "Champion" })
add("MATCH", "MatchKills15", "On Fire", "Get 15 kills in one match.", "MatchKills", 15, { XP = 500, Credits = 150 }, "Max")
add("MATCH", "MatchKills25", "Dominant", "Get 25 kills in one match.", "MatchKills", 25, { XP = 1500, Credits = 500 }, "Max")
add("MATCH", "Flawless1", "Untouchable", "Win a match without dying.", "Flawless", 1, { XP = 1000, Credits = 400 })
add("MATCH", "Flawless5", "Ghost in the Machine", "Win 5 matches without dying.", "Flawless", 5, { XP = 4000, Credits = 1500 })
add("MATCH", "Capture10", "Flag Bearer", "Capture 10 flags.", "Tag:Capture", 10, { XP = 700, Credits = 250 })
add("MATCH", "Hill25", "Hold the Line", "Earn 25 Hill Hold awards.", "Tag:HillHold", 25, { XP = 700, Credits = 250 })
add("MATCH", "Confirm25", "Tag Collector", "Confirm 25 kills.", "Tag:Confirmed", 25, { XP = 700, Credits = 250 })
add("MATCH", "Deny10", "Denied!", "Deny 10 kills.", "Tag:Denied", 10, { XP = 600, Credits = 200 })

-- ---------------------------------------------------------------- progress
add("PROGRESS", "Level10", "Getting Started", "Reach level 10.", "Level", 10, { XP = 300, Credits = 200 }, "Max")
add("PROGRESS", "Level25", "Making a Name", "Reach level 25.", "Level", 25, { Credits = 600 }, "Max")
add("PROGRESS", "Level50", "Halfway There", "Reach level 50.", "Level", 50, { Credits = 1500 }, "Max")
add("PROGRESS", "Level100", "Max Level", "Reach level 100.", "Level", 100, { Credits = 5000 }, "Max")
add("PROGRESS", "Done10", "Collector", "Complete 10 achievements.", "Achievements", 10, { XP = 1500, Credits = 500 })
add("PROGRESS", "Done25", "Completionist", "Complete 25 achievements.", "Achievements", 25, { XP = 5000, Credits = 2000 })

-- ---------------------------------------------------------------- mastery
add("MASTERY", "MBronze1", "Practice Makes Perfect", "Reach Bronze mastery on a weapon.", "Mastery:Bronze", 1, { XP = 300 })
add("MASTERY", "MBronze5", "Well Rounded", "Reach Bronze mastery on 5 weapons.", "Mastery:Bronze", 5, { XP = 1500, Credits = 500 })
add("MASTERY", "MSilver1", "Honed", "Reach Silver mastery on a weapon.", "Mastery:Silver", 1, { XP = 600, Credits = 200 })
add("MASTERY", "MGold1", "Golden Gun", "Reach Gold mastery on a weapon.", "Mastery:Gold", 1, { XP = 1500, Credits = 500 })
add("MASTERY", "MGold3", "Triple Gold", "Reach Gold mastery on 3 weapons.", "Mastery:Gold", 3, { XP = 4000, Credits = 1500 })
add("MASTERY", "MDiamond1", "Diamond in the Rough", "Reach Diamond mastery on a weapon.", "Mastery:Diamond", 1, { XP = 6000, Credits = 3000 })

-- "Mm Xxx" style text for a reward table
function A.RewardText(r)
	local parts = {}
	if r.XP then table.insert(parts, ("+%d XP"):format(r.XP)) end
	if r.Credits then table.insert(parts, ("+%d CR"):format(r.Credits)) end
	if r.Title then table.insert(parts, "TITLE: " .. r.Title) end
	if r.Emblem then table.insert(parts, "EMBLEM: " .. r.Emblem) end
	return table.concat(parts, "   ")
end

return A
