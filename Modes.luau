-- Game modes + maps (shared by the server match logic and the deploy / vote UI).
-- Add a mode = one entry in Modes.List. Add a map = one entry in Modes.Maps (and optionally a hand-built model, see MapService).
local Modes = {}

-- Fields:  Teams (two teams, else free for all), Rounds (elimination rounds instead of a score race), ScoreLimit (kills), TimeLimit (s),
-- Respawn (seconds, false = no respawns), Down (downed / revive system on), Health / StartArmor / StartPlates (override the Config defaults),
-- FriendlyFire, Enabled = false shows the mode as locked in the vote list.
-- Brief = the objective line shown on the match intro card.
-- Objective = "Domination" | "KillConfirmed" | "Hardpoint": team score comes from the objective (ObjectiveService), not from kills.
--   Domination:    CaptureTime (s for one player to flip a flag), ScoreInterval (s per point per owned flag)
--   KillConfirmed: TagLife (s a dog tag stays on the map), MaxTags
--   Hardpoint:     HillTime (s a hill is active), HillGap (s between hills), HillPreview (s the next hill is shown early), HoldXPEvery (s)
Modes.List = {
	{ Id = "TDM", Name = "Team Deathmatch", Desc = "Two teams. First to 50 kills wins.",
		Teams = true, ScoreLimit = 50, TimeLimit = 600, Respawn = 4, Down = false, Enabled = true,
		Brief = "Eliminate the enemy team. First to 50 kills." },
	{ Id = "FFA", Name = "Free For All", Desc = "Everyone for themselves. First to 25 kills wins.",
		Teams = false, ScoreLimit = 25, TimeLimit = 600, Respawn = 3, Down = false, Enabled = true,
		Brief = "Everyone is an enemy. First to 25 kills." },
	{ Id = "HCTDM", Name = "Hardcore TDM", Desc = "30 health, no armor, friendly fire on. First to 50.",
		Teams = true, ScoreLimit = 50, TimeLimit = 600, Respawn = 4, Down = false, Health = 30, StartArmor = 0, StartPlates = 0,
		FriendlyFire = true, Enabled = true, Brief = "30 health, no armor, friendly fire is ON. First to 50 kills." },
	{ Id = "DAO", Name = "Down and Out", Desc = "Elimination rounds. No respawns: revive your squad. First to 3 rounds.",
		Teams = true, Rounds = true, RoundsToWin = 3, RoundTime = 150, Respawn = false, Down = true, Enabled = true,
		Brief = "No respawns. Revive your squad, finish theirs. First to 3 rounds." },
	{ Id = "DOM", Name = "Domination", Desc = "Capture and hold flags A, B and C. First to 200 points.",
		Teams = true, ScoreLimit = 200, TimeLimit = 600, Respawn = 4, Down = false, Enabled = true,
		Objective = "Domination", CaptureTime = 8, ScoreInterval = 5,
		Brief = "Capture and hold flags A, B and C. Owned flags score over time." },
	{ Id = "KC", Name = "Kill Confirmed", Desc = "Collect dog tags. Confirm enemy tags, deny your own. First to 65.",
		Teams = true, ScoreLimit = 65, TimeLimit = 600, Respawn = 3, Down = false, Enabled = true,
		Objective = "KillConfirmed", TagLife = 25, MaxTags = 36,
		Brief = "Kills only score when you collect the dog tag. Deny tags from your fallen teammates." },
	{ Id = "HP", Name = "Hardpoint", Desc = "Hold the moving hill. 1 point per second. First to 250.",
		Teams = true, ScoreLimit = 250, TimeLimit = 600, Respawn = 4, Down = false, Enabled = true,
		Objective = "Hardpoint", HillTime = 60, HillGap = 4, HillPreview = 10, HoldXPEvery = 5,
		Brief = "Stand in the hill to score. It moves every minute, so keep rotating." },
	{ Id = "EXTRACT", Name = "Extraction", Desc = "Loot, survive and extract.", Enabled = false },
	{ Id = "DMZ", Name = "DMZ", Desc = "Contracts and high-stakes survival.", Enabled = false },
}

-- Size = arena width (x) and length (z) in studs. Cover = number of random cover blocks. Seed makes the layout the same every time.
Modes.Maps = {
	{ Id = "Warehouse", Name = "Warehouse", Desc = "Tight lanes and crates.", Size = { 140, 200 }, Cover = 30, Seed = 11,
		Floor = Color3.fromRGB(96, 98, 102), Wall = Color3.fromRGB(70, 72, 78), CoverColor = Color3.fromRGB(176, 120, 60) },
	{ Id = "Crossroads", Name = "Crossroads", Desc = "Open centre, flanking routes.", Size = { 180, 180 }, Cover = 36, Seed = 23,
		Floor = Color3.fromRGB(120, 112, 98), Wall = Color3.fromRGB(88, 84, 76), CoverColor = Color3.fromRGB(94, 110, 84) },
	{ Id = "Compound", Name = "Compound", Desc = "Compact and close quarters.", Size = { 110, 150 }, Cover = 24, Seed = 37,
		Floor = Color3.fromRGB(84, 92, 96), Wall = Color3.fromRGB(56, 64, 70), CoverColor = Color3.fromRGB(150, 150, 156) },
	{ Id = "Docks", Name = "Docks", Desc = "Long sightlines along the pier.", Size = { 100, 260 }, Cover = 34, Seed = 51,
		Floor = Color3.fromRGB(104, 94, 86), Wall = Color3.fromRGB(60, 74, 90), CoverColor = Color3.fromRGB(70, 110, 140) },
}

Modes.Config = {
	VoteTime = 30,           -- seconds of voting before a match starts
	StartEarly = 5,          -- once everybody is ready the vote ends after this many seconds
	ResultsTime = 15,        -- includes EndPresentTime
	IntroTime = 9,           -- match start: title card + map flyover, then the countdown (all players frozen, nobody can be hurt)
	CountdownTime = 3,       -- the last seconds of IntroTime are the 3-2-1
	LateIntroTime = 3.5,     -- short card for players who deploy into a running match
	EndPresentTime = 3.6,    -- victory / defeat title + camera orbit before the scoreboard slides in
	RoundIntermission = 5,
	SpawnProtection = 2.5,   -- seconds of invulnerability after spawning (firing or meleeing ends it early, see Spawn.BreakProtectionOnFire)
	-- SpawnService tuning: every spawn point is scored, unsafe ones are skipped (distances in studs, times in seconds)
	Spawn = {
		Height = 3.5,              -- the character is placed this high above the ground under the spawn point
		MinEnemyDistance = 28,     -- an enemy this close makes a spawn unsafe
		CamperDistance = 60,       -- same, around a player who has been spawn killing
		LosRange = 140,            -- enemies further away are not checked for line of sight
		LosHardDistance = 90,      -- an enemy this close with a clear view of the spawn makes it unsafe
		LosPenalty = 90,           -- score lost per enemy that can see the spawn (less the further away he is; x1.6 if he is looking at it)
		FacingDot = 0.35,          -- an enemy "looks at" the spawn when his facing dotted with the direction to it is above this
		IdealEnemyDistance = 110,  -- nearest enemy at least this far = full distance score
		DistWeight = 100,          -- score for the distance to the nearest enemy
		AllyBonus = 18, AllyIdeal = 35, -- team modes: a bonus for spawning about AllyIdeal studs from a teammate
		HeatRadius = 38, DeathHeat = 30, DeathLife = 10,                   -- recent deaths make nearby spawns less attractive
		SpawnKillWindow = 6, SpawnKillHeat = 90, SpawnKillLife = 25,       -- dying this soon after spawning marks that spawn as a trap
		FireRadius = 45, FirePenalty = 28, FireLife = 3,                   -- recent enemy gunfire (unsuppressed) nearby
		ReuseRadius = 14, ReuseTime = 8, ReusePenalty = 80,                -- a spawn somebody just used is avoided; the same pad twice in 2 s is never used
		OccupiedRadius = 3.5,      -- somebody standing this close = blocked
		CamperKills = 3, CamperWindow = 25, CamperLife = 20,               -- this many spawn kills by one player = he is camping the spawns
		FlipAfter = 2, TrapWindow = 20,                                    -- this many spawn kills against a team = it may spawn on the other side of the map
		MaxWait = 2,               -- no safe spawn at all: wait up to this long for one before spawning anyway
		UnsafeProtectionMult = 2,  -- spawning anyway gives this much longer spawn protection
		BreakProtectionOnFire = true,
		Noise = 6,                 -- a little randomness so the best spawn is not always the same one
	},
	MapChoices = 3,          -- how many maps are offered per vote
	TeamNames = { "Alpha", "Bravo" },
}

local byId, mapById = {}, {}
for _, m in Modes.List do byId[m.Id] = m end
for _, m in Modes.Maps do mapById[m.Id] = m end

function Modes.Get(id) return byId[id] end
function Modes.GetMap(id) return mapById[id] end

return Modes
