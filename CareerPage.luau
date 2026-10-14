-- Career: stats, achievements, and weapon mastery, styled with the shared Theme.
local GuiService = game:GetService("GuiService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Achievements = require(script.Parent.Achievements)
local Mastery = require(script.Parent.Mastery)

local CareerPage = {}
local remotes
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local C0 = Color3.new()
local TABS = { { Name = "STATS", Remote = "GetStats" }, { Name = "ACHIEVEMENTS", Remote = "GetAchievements" }, { Name = "MASTERY", Remote = "GetMastery" } }
function CareerPage.Start(r) remotes = r end

local function commas(n)
 local s = tostring(math.floor(tonumber(n) or 0)); local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse(); return (out:gsub("^,", ""))
end
local function pct(n) return ("%.1f%%"):format((tonumber(n) or 0) * 100) end
local function ago(t)
 local d = math.max(0, os.time() - (tonumber(t) or os.time()))
 if d < 3600 then return ("%dm ago"):format(math.max(1, d // 60)) end
 if d < 86400 then return ("%dh ago"):format(d // 3600) end
 return ("%dd ago"):format(d // 86400)
end
local function fetch(name)
 if not remotes or not remotes[name] then return nil end
 local ok, result = pcall(function() return remotes[name]:InvokeServer() end)
 return ok and type(result) == "table" and result or nil
end
local function build(holder)
 local root = Theme.Glass(holder, UDim2.fromScale(1, 1)); root.BackgroundTransparency = 0.25
 Theme.Label(root, "CAREER", 38, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(32, 18), UDim2.fromOffset(300, 50))
 local content = Instance.new("ScrollingFrame")
 content.Name = "CareerContent"; content.BackgroundTransparency = 1; content.BorderSizePixel = 0
 content.Position = UDim2.fromOffset(32, 126); content.Size = UDim2.new(1, -64, 1, -142)
 content.ScrollBarThickness = 5; content.ScrollBarImageColor3 = Theme.Accent; content.AutomaticCanvasSize = Enum.AutomaticSize.Y; content.CanvasSize = UDim2.new()
 content.Parent = root
 local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 6); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = content
 local order, current, token = 0, 1, 0
 local buttons = {}
 local function clear()
  order = 0
  for _, child in content:GetChildren() do if not child:IsA("UIListLayout") then child:Destroy() end end
 end
 local function addLabel(text, color, height, size)
  order += 1
  local label = Theme.Label(content, text, size or 15, color or Theme.Dim, LEFT, Theme.Body, nil, UDim2.new(1, -8, 0, height or 32))
  label.LayoutOrder = order; label.TextWrapped = true; return label
 end
 local function panel(height)
  order += 1; local p = Theme.Glass(content, UDim2.new(1, -8, 0, height)); p.LayoutOrder = order; return p
 end
 local function heading(text, right)
  order += 1; local h = Theme.Frame(content, UDim2.new(1, -8, 0, 26), nil, nil, C0, 1); h.LayoutOrder = order
  Theme.Label(h, text, 14, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(2, 3), UDim2.new(0.65, 0, 1, 0))
  if right then Theme.Label(h, right, 12, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -2, 0, 3), UDim2.new(0.35, 0, 1, 0), Vector2.new(1, 0)) end
 end
 local function progressBar(parent, x, y, width, fraction, color)
  local back = Theme.Frame(parent, UDim2.fromOffset(width, 6), UDim2.fromOffset(x, y), nil, C0, 0.45); Theme.Round(back, 3)
  local fill = Theme.Frame(back, UDim2.new(math.clamp(fraction or 0, 0, 1), 0, 1, 0), nil, nil, color or Theme.Accent, 0); Theme.Round(fill, 3)
 end
 local function renderStats(s)
  if not s then addLabel("Could not load your stats. Select this tab again to retry."); return end
  local best = s.BestGun
  local cards = {
   {"K / D", ("%.2f"):format(s.KD or 0), commas(s.Kills).." kills / "..commas(s.Deaths).." deaths"},
   {"WIN / LOSS", ("%.2f"):format(s.WinLoss or 0), ("%d W  %d L  %d D"):format(s.Wins or 0,s.Losses or 0,s.Draws or 0)},
   {"WIN RATE", pct(s.WinRate), ("%d matches played"):format(s.MatchesPlayed or 0)},
   {"ACCURACY", pct(s.Accuracy), commas(s.Hits).." hits / "..commas(s.Shots).." shots"},
   {"HEADSHOT KILLS", commas(s.Headshots), pct(s.HeadshotRate).." of kills"},
   {"HEAD HITS", commas(s.HeadHits), "shots that hit a head"},
   {"BEST STREAK", tostring(s.BestStreak or 0), commas(s.Assists).." assists"},
   {"BEST GUN", best and Theme.Spaced(best.Name) or "-", best and (commas(best.Kills).." kills | "..pct(best.Accuracy).." accuracy") or "Get a kill with a gun"},
  }
  order += 1; local grid = Theme.Frame(content, UDim2.new(1, -8, 0, 0), nil, nil, C0, 1); grid.AutomaticSize = Enum.AutomaticSize.Y; grid.LayoutOrder = order
  local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.new(0.25, -6, 0, 74); gl.CellPadding = UDim2.fromOffset(6, 6); gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid
  for i, c in cards do
   local f = Theme.Glass(grid, UDim2.fromScale(1, 1)); f.LayoutOrder = i
   Theme.Label(f,c[1],11,Theme.Dim,LEFT,Theme.Display,UDim2.fromOffset(10,5),UDim2.new(1,-20,0,16))
   Theme.Label(f,c[2],25,Theme.Accent,LEFT,Theme.Display,UDim2.fromOffset(10,21),UDim2.new(1,-20,0,29))
   Theme.Label(f,c[3],10,Theme.Dim,LEFT,Theme.Body,UDim2.fromOffset(10,51),UDim2.new(1,-20,0,17))
  end
  heading("WEAPON STATS", "sorted by kills")
  local weapons = s.Weapons or {}
  if #weapons == 0 then addLabel("No weapon stats yet. Play a match.") else
   for i,w in weapons do if i > 15 then break end
    local r = panel(34)
    Theme.Label(r,Theme.Spaced(w.Name),16,Theme.Text,LEFT,Theme.Display,UDim2.fromOffset(12,0),UDim2.new(0.28,0,1,0))
    Theme.Label(r,commas(w.Kills).." kills",14,Theme.Accent,LEFT,Theme.Display,UDim2.new(0.31,0,0,0),UDim2.new(0.17,0,1,0))
    Theme.Label(r,commas(w.HeadKills).." HS",14,Theme.Accent,LEFT,Theme.Display,UDim2.new(0.49,0,0,0),UDim2.new(0.16,0,1,0))
    Theme.Label(r,(w.Shots or 0)>0 and pct(w.Accuracy) or "-",14,Theme.Accent,LEFT,Theme.Display,UDim2.new(0.66,0,0,0),UDim2.new(0.15,0,1,0))
    Theme.Label(r,commas(w.Shots).." shots",13,Theme.Dim,RIGHT,Theme.Display,UDim2.new(1,-12,0,0),UDim2.new(0.18,0,1,0),Vector2.new(1,0))
   end
  end
  heading("RECENT MATCHES", "last 25")
  if #(s.History or {}) == 0 then addLabel("No finished matches yet.") else
   for _,m in s.History do
    local r = panel(38); local color = m.Result == "Win" and Theme.Good or (m.Result == "Loss" and Theme.Danger or Theme.Dim)
    Theme.Label(r,(m.Result or "?"):upper(),14,color,LEFT,Theme.Display,UDim2.fromOffset(12,0),UDim2.new(0.13,0,1,0))
    Theme.Label(r,tostring(m.Mode or "?").." - "..tostring(m.Map or "?"),13,Theme.Text,LEFT,Theme.Display,UDim2.new(0.14,0,0,0),UDim2.new(0.34,0,1,0))
    Theme.Label(r,("%d / %d / %d"):format(m.K or 0,m.D or 0,m.O or 0),13,Theme.Accent,LEFT,Theme.Display,UDim2.new(0.51,0,0,0),UDim2.new(0.17,0,1,0))
    Theme.Label(r,(m.Shots or 0)>0 and pct((m.Hits or 0)/m.Shots) or "-",13,Theme.Dim,LEFT,Theme.Display,UDim2.new(0.7,0,0,0),UDim2.new(0.12,0,1,0))
    Theme.Label(r,m.T and ago(m.T) or "",12,Theme.Dim,RIGHT,Theme.Body,UDim2.new(1,-12,0,0),UDim2.new(0.16,0,1,0),Vector2.new(1,0))
   end
  end
 end
 local function renderAchievements(d)
  if not d then addLabel("Could not load achievements. Select this tab again to retry."); return end
  local progress, done = d.Progress or {}, d.Done or {}; local complete = 0
  for _,def in Achievements.List do if done[def.Id] then complete += 1 end end
  local top = panel(58); Theme.Label(top,("%d / %d COMPLETE"):format(complete,#Achievements.List),22,Theme.Text,LEFT,Theme.Display,UDim2.fromOffset(12,4),UDim2.new(0.5,0,0,28))
  progressBar(top,12,40,300,complete/math.max(#Achievements.List,1),Theme.Good)
  for _,cat in Achievements.Categories do
   heading(cat)
   for _,def in Achievements.List do if def.Cat == cat then
    local isDone = done[def.Id] ~= nil; local value = math.min(progress[def.Key] or 0,def.Goal); local r = panel(66)
    Theme.Label(r,def.Name:upper(),16,isDone and Theme.Good or Theme.Text,LEFT,Theme.Display,UDim2.fromOffset(12,4),UDim2.new(0.52,0,0,22))
    Theme.Label(r,def.Desc,11,Theme.Dim,LEFT,Theme.Body,UDim2.fromOffset(12,27),UDim2.new(0.54,0,0,16))
    progressBar(r,12,49,210,value/math.max(def.Goal,1),isDone and Theme.Good or Theme.Accent)
    Theme.Label(r,isDone and "COMPLETE" or (commas(value).." / "..commas(def.Goal)),12,isDone and Theme.Good or Theme.Dim,LEFT,Theme.Display,UDim2.fromOffset(230,43),UDim2.fromOffset(120,18))
    local reward = Achievements.RewardText(def.Reward)
    if reward ~= "" then Theme.Label(r,reward,11,isDone and Theme.Dim or Theme.Accent,RIGHT,Theme.Display,UDim2.new(1,-12,0,0),UDim2.new(0.34,0,1,0),Vector2.new(1,0)) end
   end end
  end
 end
 local function renderMastery(rows)
  heading("MASTERY TIERS", "per weapon")
  order += 1; local grid = Theme.Frame(content,UDim2.new(1,-8,0,0),nil,nil,C0,1); grid.AutomaticSize=Enum.AutomaticSize.Y; grid.LayoutOrder=order
  local gl=Instance.new("UIGridLayout"); gl.CellSize=UDim2.new(0.2,-5,0,74); gl.CellPadding=UDim2.fromOffset(6,6); gl.Parent=grid
  for i,t in Mastery.Tiers do
   local f=Theme.Glass(grid,UDim2.fromScale(1,1)); f.LayoutOrder=i; Theme.Stroke(f,t.Color,1.5,0.3)
   Theme.Label(f,t.Name,15,t.Color,LEFT,Theme.Display,UDim2.fromOffset(8,4),UDim2.new(1,-16,0,20))
   Theme.Label(f,"WEAPON LVL "..t.Level,10,Theme.Dim,LEFT,Theme.Display,UDim2.fromOffset(8,25),UDim2.new(1,-16,0,14))
   Theme.Label(f,commas(t.Kills).." kills / "..commas(t.HeadKills).." HS",10,Theme.Dim,LEFT,Theme.Body,UDim2.fromOffset(8,40),UDim2.new(1,-16,0,13))
   Theme.Label(f,"+"..commas(t.Credits).." CR  +"..commas(t.XP).." XP",10,Theme.Accent,LEFT,Theme.Display,UDim2.fromOffset(8,54),UDim2.new(1,-16,0,14))
  end
  heading("YOUR WEAPONS", "best first")
  if not rows then addLabel("Could not load mastery. Select this tab again to retry."); return end
  if #rows == 0 then addLabel("Get kills with a weapon to start mastering it."); return end
  for _,w in rows do
   local tier = w.Tier and w.Tier > 0 and Mastery.Tiers[w.Tier] or nil; local r=panel(70)
   Theme.Label(r,Theme.Spaced(w.Weapon),18,Theme.Text,LEFT,Theme.Display,UDim2.fromOffset(12,4),UDim2.new(0.28,0,0,24))
   Theme.Label(r,tier and tier.Name or "UNRANKED",12,tier and tier.Color or Theme.Dim,LEFT,Theme.Display,UDim2.fromOffset(12,29),UDim2.new(0.28,0,0,17))
   Theme.Label(r,"WEAPON LEVEL "..(w.Level or 0),10,Theme.Dim,LEFT,Theme.Body,UDim2.fromOffset(12,48),UDim2.new(0.28,0,0,14))
   local nx=w.Next
   if not nx then Theme.Label(r,"MAXED",20,Theme.Good,RIGHT,Theme.Display,UDim2.new(1,-12,0,0),UDim2.new(0.5,0,1,0),Vector2.new(1,0)) else
    Theme.Label(r,"NEXT: "..nx.Name,12,nx.Color,LEFT,Theme.Display,UDim2.new(0.32,0,0,4),UDim2.new(0.32,0,0,18))
    local needs={{"LEVEL",w.Level or 0,nx.Level},{"KILLS",w.Kills or 0,nx.Kills},{"HEADSHOTS",w.HeadKills or 0,nx.HeadKills}}
    for i,n in needs do local x=0.32+(i-1)*0.22; local frac=math.min(n[2]/math.max(n[3],1),1)
     local h=Theme.Frame(r,UDim2.new(0.2,0,0,36),UDim2.new(x,0,0,28),nil,C0,1)
     Theme.Label(h,n[1].."  "..commas(math.min(n[2],n[3])).." / "..commas(n[3]),10,frac>=1 and Theme.Good or Theme.Dim,LEFT,Theme.Display,nil,UDim2.new(1,0,0,15))
     progressBar(h,0,21,120,frac,frac>=1 and Theme.Good or nx.Color)
    end
   end
  end
 end
 local function paintTabs()
  for i,b in buttons do local on=i==current; b.BackgroundTransparency=on and 0.2 or 0.6; b.TextColor3=on and Theme.Accent or Theme.Dim
   local stroke=b:FindFirstChildOfClass("UIStroke"); if stroke then stroke.Color=on and Theme.Accent or Theme.Dim; stroke.Transparency=on and 0.1 or 0.8 end
  end
 end
 local function load(i)
  current=i; token+=1; local mine=token; paintTabs(); clear(); addLabel("LOADING...",Theme.Dim,30,15)
  task.spawn(function() local data=fetch(TABS[i].Remote); if mine~=token then return end; clear()
   if i==1 then renderStats(data) elseif i==2 then renderAchievements(data) else renderMastery(data) end
  end)
 end
 for i,t in TABS do
  local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.BorderSizePixel=0; b.Text=t.Name; b.Font=Theme.Display; b.TextSize=18; b.BackgroundColor3=Theme.Panel
  b.Size=UDim2.fromOffset(170,40); b.Position=UDim2.fromOffset(32+(i-1)*176,76); Theme.Round(b,4); Theme.Stroke(b,Theme.Dim,1,0.8); b.Parent=root; Widgets.Selectable(b)
  b.Activated:Connect(function() load(i) end); buttons[i]=b
 end
 paintTabs()
 return { Show=function() load(current) end, Hide=function() token+=1 end, Back=function() return false end, Focus=function() GuiService.SelectedObject=buttons[current] end }
end
function CareerPage.Register(MainMenu) MainMenu.RegisterPage("CAREER", build) end
return CareerPage
