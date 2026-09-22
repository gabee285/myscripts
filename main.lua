--[[
    Gabriel's Mystery v6 — USER VERSION
    WARNING: Violates Roblox ToS. Educational use only.

    - 7 tabs: Combat, Auto, Movement, Fling, Teleport, ESP, Server
    - Config save/load (auto + manual)
    - Fling player list with refresh
    - Fixed fling: teleports IN FRONT + pushes backward
    - Gun detection: universal GunDrop Part match across ALL maps
    - HasItem: Tool-only check, ignores GunBelt/GunTipAttachment/etc.
    - Registers itself so the ADMIN version can kick this client
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Camera = Workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer

-- ==================== SELF-REGISTRATION ====================
local REGISTRY_NAME = "GM_ScriptRegistry"
local registry = ReplicatedStorage:FindFirstChild(REGISTRY_NAME)
if not registry then
    local ok, folder = pcall(function()
        local f = Instance.new("Folder")
        f.Name = REGISTRY_NAME
        f.Parent = ReplicatedStorage
        return f
    end)
    registry = ok and folder or nil
end

local myEntry
if registry and registry.Parent then
    for _, c in ipairs(registry:GetChildren()) do
        if c:IsA("ObjectValue") and c.Value == LocalPlayer then c:Destroy() end
    end
    myEntry = Instance.new("ObjectValue")
    myEntry.Name = "User_" .. LocalPlayer.UserId
    myEntry.Value = LocalPlayer
    myEntry.Parent = registry
end

_G.GM_KICK_REGISTRY = _G.GM_KICK_REGISTRY or {}

task.spawn(function()
    while true do
        task.wait(0.4)
        local shouldKick = false
        if registry and registry.Parent then
            local flag = registry:FindFirstChild("KICK_" .. tostring(LocalPlayer.UserId))
            if flag then shouldKick = true end
            if myEntry and not myEntry.Parent then shouldKick = true end
        end
        if _G.GM_KICK_REGISTRY[LocalPlayer.UserId] then shouldKick = true end
        if shouldKick then
            pcall(function() LocalPlayer:Kick("Removed by script admin.") end)
            break
        end
    end
end)

LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent and myEntry and myEntry.Parent then myEntry:Destroy() end
end)

-- ==================== CONFIG FILE ====================
local CONFIG_FOLDER = "GabrielsMystery"
local CONFIG_FILE = CONFIG_FOLDER .. "/config_user.json"

local function CanSave()
    return type(writefile) == "function"
       and type(readfile) == "function"
       and type(isfile) == "function"
end

local function EnsureConfigFolder()
    if type(makefolder) == "function" then
        pcall(function() makefolder(CONFIG_FOLDER) end)
    end
end

-- ==================== TRANSPARENCY ====================
local TRANSPARENCY = {
    MainWindow = 0.15,
    Rows = 0.25,
    TabPills = 0.25,
    TabPillsActive = 0.15,
}

-- ==================== ITEM CHECK (TOOL-ONLY) ====================
local function HasItem(player, itemName)
    if not player then return false end
    local char = player.Character
    local bp = player.Backpack
    local lower = itemName:lower()

    local function checkContainer(container)
        if not container then return false end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") then
                local n = obj.Name:lower()
                if n == lower then return true end
                if lower == "gun" then
                    if n == "knife" or n == "toys" then
                        -- skip
                    elseif n:find("gun", 1, true)
                        or n == "revolver"
                        or n == "pistol"
                        or n == "deagle"
                        or n == "firearm"
                        or n == "hallowgun" then
                        return true
                    end
                end
            end
        end
        return false
    end

    return checkContainer(char) or checkContainer(bp)
end

-- ==================== ROLE DETECTION ====================
local SheriffUserId = nil
local SheriffDead = false
local LastSheriffCheck = 0
local ROLE_POLL_INTERVAL = 0.5

local function GetPlayerRole(player)
    if not player or player == LocalPlayer then return "Local" end
    if not player.Character then return "Unknown" end
    if HasItem(player, "Knife") then return "Murderer" end
    if HasItem(player, "Gun") then
        if SheriffUserId and player.UserId ~= SheriffUserId and SheriffDead then
            return "Hero"
        end
        return "Sheriff"
    end
    return "Innocent"
end

local function WatchForDeath(player, onDeath)
    if not player then return end
    local function hookChar(char)
        if not char then return end
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end
        if hum.Health <= 0 then onDeath(char, hum) end
        hum.Died:Connect(function() onDeath(char, hum) end)
    end
    if player.Character then task.spawn(hookChar, player.Character) end
    player.CharacterAdded:Connect(hookChar)
end

local function OnSheriffDied(char, hum)
    SheriffDead = true
    Notify("💀 Sheriff died!", Color3.fromRGB(255, 100, 100), 5)
    if Config and Config.AutoSheriffPickup and TriggerSheriffPickup then
        task.spawn(function()
            task.wait(0.4)
            TriggerSheriffPickup(true)
        end)
    end
end

local function RefreshSheriffTracking()
    SheriffUserId = nil
    SheriffDead = false
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if HasItem(p, "Gun") then
            SheriffUserId = p.UserId
            WatchForDeath(p, OnSheriffDied)
            return
        end
    end
end

local LastKnifeHolder = nil
local function GetKnifeHolder()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and HasItem(p, "Knife") then return p end
    end
    return nil
end

-- ==================== CONFIG ====================
local Config = {
    AimbotEnabled = false,
    AutoShootTeamCheck = true,
    AutoShootRange = 500,
    AutoShootWallCheck = false,
    HitboxEnabled = true,
    HitboxSize = 8,
    AutoKnife = false,
    AutoKnifeRange = 8,
    AutoEscape = false,
    AutoEscapeTriggerDist = 30,
    AutoEscapeReturnDist = 150,
    KillNotifier = true,
    AntiAFK = true,
    AutoSheriffPickup = false,
    Noclip = false,
    MobileButtonsEnabled = false,
    FlingForce = 6500,
    ESPEnabled = true,
    ESPShowName = true,
    ESPShowRole = true,
    ESPShowDistance = true,
    ESPFillTransparency = 0.65,
    AimbotKey = Enum.KeyCode.Q,
    GrabGunKey = Enum.KeyCode.LeftControl,
    AimbotKeyName = "Q",
    GrabGunKeyName = "Ctrl",
}

local KeyOptions = {
    { name = "Q", key = Enum.KeyCode.Q }, { name = "E", key = Enum.KeyCode.E },
    { name = "F", key = Enum.KeyCode.F }, { name = "G", key = Enum.KeyCode.G },
    { name = "H", key = Enum.KeyCode.H }, { name = "J", key = Enum.KeyCode.J },
    { name = "Z", key = Enum.KeyCode.Z }, { name = "X", key = Enum.KeyCode.X },
    { name = "C", key = Enum.KeyCode.C }, { name = "V", key = Enum.KeyCode.V },
    { name = "B", key = Enum.KeyCode.B }, { name = "N", key = Enum.KeyCode.N },
    { name = "M", key = Enum.KeyCode.M }, { name = "R", key = Enum.KeyCode.R },
    { name = "T", key = Enum.KeyCode.T }, { name = "Y", key = Enum.KeyCode.Y },
    { name = "U", key = Enum.KeyCode.U }, { name = "I", key = Enum.KeyCode.I },
    { name = "O", key = Enum.KeyCode.O }, { name = "P", key = Enum.KeyCode.P },
    { name = "L", key = Enum.KeyCode.L }, { name = "K", key = Enum.KeyCode.K },
    { name = "Ctrl", key = Enum.KeyCode.LeftControl },
    { name = "Shift", key = Enum.KeyCode.LeftShift },
    { name = "Alt", key = Enum.KeyCode.LeftAlt },
    { name = "Tab", key = Enum.KeyCode.Tab },
    { name = "Caps", key = Enum.KeyCode.CapsLock },
    { name = "Space", key = Enum.KeyCode.Space },
    { name = "1", key = Enum.KeyCode.One }, { name = "2", key = Enum.KeyCode.Two },
    { name = "3", key = Enum.KeyCode.Three }, { name = "4", key = Enum.KeyCode.Four },
    { name = "5", key = Enum.KeyCode.Five },
}

local RoleColors = {
    Innocent = Color3.fromRGB(0, 255, 0),
    Murderer = Color3.fromRGB(255, 0, 0),
    Sheriff  = Color3.fromRGB(0, 120, 255),
    Hero     = Color3.fromRGB(255, 220, 0),
    Local    = Color3.fromRGB(255, 255, 255),
    Unknown  = Color3.fromRGB(180, 180, 180),
}

-- ==================== SAVE/LOAD ====================
local KEY_TO_NAME = {}
for _, opt in ipairs(KeyOptions) do KEY_TO_NAME[opt.key] = opt.name end
local NAME_TO_KEY = {}
for _, opt in ipairs(KeyOptions) do NAME_TO_KEY[opt.name] = opt.key end

local function SerializeConfig()
    local out = {}
    for k, v in pairs(Config) do
        if type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
            out[k] = v
        elseif typeof and typeof(v) == "EnumItem" then
            out[k] = v.Name
        end
    end
    return HttpService:JSONEncode(out)
end

local function ApplyConfig(data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do
        if k == "AimbotKey" or k == "GrabGunKey" then
            if NAME_TO_KEY[v] then Config[k] = NAME_TO_KEY[v] end
        elseif Config[k] ~= nil then
            Config[k] = v
        end
    end
end

local lastSaveTime = 0
local function SaveConfig(showNotify)
    if not CanSave() then
        if showNotify then
            Notify("❌ writefile not supported", Color3.fromRGB(255, 100, 100), 4)
        end
        return false
    end
    EnsureConfigFolder()
    local ok = pcall(function() writefile(CONFIG_FILE, SerializeConfig()) end)
    if ok then
        lastSaveTime = tick()
        if showNotify then
            Notify("💾 Config saved", Color3.fromRGB(90, 220, 160), 2)
        end
    elseif showNotify then
        Notify("❌ Save failed", Color3.fromRGB(255, 100, 100), 4)
    end
    return ok
end

local function LoadConfig(showNotify)
    if not CanSave() then
        if showNotify then
            Notify("❌ readfile not supported", Color3.fromRGB(255, 100, 100), 4)
        end
        return false
    end
    if not isfile(CONFIG_FILE) then
        if showNotify then
            Notify("⚠️ No config found", Color3.fromRGB(255, 180, 90), 3)
        end
        return false
    end
    local ok, contents = pcall(function() return readfile(CONFIG_FILE) end)
    if not ok or not contents then return false end
    local decoded
    local decodeOk = pcall(function() decoded = HttpService:JSONDecode(contents) end)
    if not decodeOk then return false end
    ApplyConfig(decoded)
    if Config.AimbotKey then
        Config.AimbotKeyName = KEY_TO_NAME[Config.AimbotKey] or "Q"
    end
    if Config.GrabGunKey then
        Config.GrabGunKeyName = KEY_TO_NAME[Config.GrabGunKey] or "Ctrl"
    end
    ApplyNoclip()
    ApplyAntiAFK()
    if showNotify then
        Notify("📂 Config loaded", Color3.fromRGB(90, 220, 160), 3)
    end
    return true
end

local function DebouncedAutoSave()
    if tick() - lastSaveTime > 1 then
        task.spawn(function()
            task.wait(0.4)
            SaveConfig(false)
        end)
    end
end

task.spawn(function()
    task.wait(1.5)
    LoadConfig(false)
end)

-- ==================== NOTIFICATIONS ====================
local notifyGui = Instance.new("ScreenGui")
notifyGui.Name = "GM_Notify"
notifyGui.ResetOnSpawn = false
notifyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
notifyGui.IgnoreGuiInset = true
notifyGui.DisplayOrder = 999
notifyGui.Parent = CoreGui

local notifyContainer = Instance.new("Frame")
notifyContainer.Size = UDim2.new(0, 340, 0, 500)
notifyContainer.Position = UDim2.new(0, 20, 0.5, -250)
notifyContainer.BackgroundTransparency = 1
notifyContainer.Parent = notifyGui

local notifyLayout = Instance.new("UIListLayout")
notifyLayout.Padding = UDim.new(0, 10)
notifyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifyLayout.Parent = notifyContainer

local notifyCount = 0

function Notify(text, color, duration)
    color = color or Color3.fromRGB(180, 140, 255)
    duration = duration or 4
    notifyCount = notifyCount + 1

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
    card.BackgroundTransparency = 0.08
    card.BorderSizePixel = 0
    card.LayoutOrder = notifyCount
    card.Parent = notifyContainer
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(60, 55, 80)
    cardStroke.Thickness = 1
    cardStroke.Transparency = 0.5
    cardStroke.Parent = card

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 4, 1, -16)
    accent.Position = UDim2.new(0, 8, 0, 8)
    accent.BackgroundColor3 = color
    accent.BorderSizePixel = 0
    accent.Parent = card
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -32, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Position = UDim2.new(0, 22, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(245, 243, 252)
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = card

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.PaddingLeft = UDim.new(0, 22)
    pad.PaddingRight = UDim.new(0, 14)
    pad.Parent = card

    card.Position = UDim2.new(-0.3, 0, 0, 0)
    TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    task.spawn(function()
        task.wait(duration)
        local fadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quart)
        TweenService:Create(card, fadeInfo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(cardStroke, fadeInfo, {Transparency = 1}):Play()
        TweenService:Create(accent, fadeInfo, {Transparency = 1}):Play()
        TweenService:Create(label, fadeInfo, {TextTransparency = 1}):Play()
        task.wait(0.4)
        card:Destroy()
    end)
end

-- ==================== ESP ====================
local ESPObjects = {}

local function CreateESP(player)
    if player == LocalPlayer or ESPObjects[player] then return end
    local esp = {}
    esp.Highlight = Instance.new("Highlight")
    esp.Highlight.FillTransparency = Config.ESPFillTransparency
    esp.Highlight.OutlineTransparency = 0
    esp.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    esp.Highlight.Parent = CoreGui

    esp.NameTag = Instance.new("BillboardGui")
    esp.NameTag.Size = UDim2.new(0, 220, 0, 45)
    esp.NameTag.StudsOffset = Vector3.new(0, 3, 0)
    esp.NameTag.AlwaysOnTop = true
    esp.NameTag.Parent = CoreGui

    esp.InfoLabel = Instance.new("TextLabel")
    esp.InfoLabel.Size = UDim2.new(1, 0, 1, 0)
    esp.InfoLabel.BackgroundTransparency = 1
    esp.InfoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    esp.InfoLabel.TextStrokeTransparency = 0
    esp.InfoLabel.TextSize = 13
    esp.InfoLabel.Font = Enum.Font.GothamBold
    esp.InfoLabel.TextWrapped = true
    esp.InfoLabel.Parent = esp.NameTag
    ESPObjects[player] = esp
end

local function RemoveESP(player)
    local esp = ESPObjects[player]
    if esp then
        if esp.Highlight then esp.Highlight:Destroy() end
        if esp.NameTag then esp.NameTag:Destroy() end
        ESPObjects[player] = nil
    end
end

local function UpdateESP()
    for player, esp in pairs(ESPObjects) do
        if not player.Parent or not player.Character then
            esp.Highlight.Adornee = nil
            esp.NameTag.Adornee = nil
            continue
        end
        local char = player.Character
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp or not Config.ESPEnabled then
            esp.Highlight.Adornee = nil
            esp.NameTag.Adornee = nil
            continue
        end
        local role = GetPlayerRole(player)
        local color = RoleColors[role] or RoleColors.Unknown
        esp.Highlight.Adornee = char
        esp.Highlight.FillColor = color
        esp.Highlight.OutlineColor = color
        esp.Highlight.FillTransparency = Config.ESPFillTransparency
        esp.NameTag.Adornee = hrp
        local dist = math.floor((Camera.CFrame.Position - hrp.Position).Magnitude)
        local parts = {}
        if Config.ESPShowName then table.insert(parts, player.Name) end
        if Config.ESPShowRole then table.insert(parts, "[" .. role .. "]") end
        if Config.ESPShowDistance then table.insert(parts, dist .. "m") end
        esp.InfoLabel.Text = table.concat(parts, " ")
        esp.InfoLabel.TextColor3 = color
    end
end

-- ==================== MURDERER HITBOX ====================
local MurdererHitboxes = {}

local function CreateHitboxFor(player)
    if MurdererHitboxes[player] or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hitbox = Instance.new("Part")
    hitbox.Name = "FakeHitbox"
    hitbox.Size = Vector3.new(4, 6, 4) * (Config.HitboxSize / 4)
    hitbox.CanCollide = false
    hitbox.CanTouch = true
    hitbox.CanQuery = true
    hitbox.Transparency = 1
    hitbox.Anchored = false
    hitbox.Massless = true
    hitbox.Material = Enum.Material.SmoothPlastic
    hitbox.Parent = Workspace
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hrp
    weld.Part1 = hitbox
    weld.Parent = hitbox
    hitbox.CFrame = hrp.CFrame
    MurdererHitboxes[player] = { part = hitbox, weld = weld, char = player.Character }
end

local function RemoveHitboxFor(player)
    local data = MurdererHitboxes[player]
    if not data then return end
    if data.part then pcall(function() data.part:Destroy() end) end
    MurdererHitboxes[player] = nil
end

local function UpdateHitboxes()
    if not Config.HitboxEnabled then
        for player in pairs(MurdererHitboxes) do RemoveHitboxFor(player) end
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if GetPlayerRole(p) == "Murderer" and p.Character then
            if not MurdererHitboxes[p] or MurdererHitboxes[p].char ~= p.Character then
                RemoveHitboxFor(p)
                CreateHitboxFor(p)
            end
        else
            if MurdererHitboxes[p] then RemoveHitboxFor(p) end
        end
    end
end

-- ==================== AIMBOT ====================
local function GetAimPart(char)
    if not char then return nil end
    local torso = char:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then return torso end
    local upper = char:FindFirstChild("UpperTorso")
    if upper and upper:IsA("BasePart") then return upper end
    local lower = char:FindFirstChild("LowerTorso")
    if lower and lower:IsA("BasePart") then return lower end
    return char:FindFirstChild("HumanoidRootPart")
end

local function IsValidTarget(player)
    if player == LocalPlayer or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if GetPlayerRole(player) ~= "Murderer" then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if (Camera.CFrame.Position - hrp.Position).Magnitude > Config.AutoShootRange then
        return false
    end
    if Config.AutoShootWallCheck then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
        local hit = Workspace:Raycast(Camera.CFrame.Position, hrp.Position - Camera.CFrame.Position, params)
        if hit and not hit.Instance:IsDescendantOf(player.Character) then
            return false
        end
    end
    return true
end

local function GetMurderer()
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if IsValidTarget(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local d = (Camera.CFrame.Position - hrp.Position).Magnitude
            if d < closestDist then
                closestDist = d
                closest = p
            end
        end
    end
    return closest
end

local function RunAimbot()
    if not Config.AimbotEnabled then return end
    local target = GetMurderer()
    if not target then return end
    local aimPart = GetAimPart(target.Character)
    if not aimPart then return end
    local predicted = aimPart.Position + (aimPart.AssemblyLinearVelocity * 0.08)
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, predicted)
end

-- ==================== AUTO-KNIFE ====================
local lastStab = 0

local function GetNearestPlayerByRole(role, maxDist)
    local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHrp then return nil end
    local closest, closestDist = nil, maxDist or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if GetPlayerRole(p) ~= role then continue end
        if not p.Character then continue end
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local d = (myHrp.Position - hrp.Position).Magnitude
        if d < closestDist then
            closestDist = d
            closest = p
        end
    end
    return closest, closestDist
end

local function RunAutoKnife()
    if not Config.AutoKnife then return end
    if not HasItem(LocalPlayer, "Knife") then return end
    local target = GetNearestPlayerByRole("Innocent", Config.AutoKnifeRange)
                or GetNearestPlayerByRole("Sheriff", Config.AutoKnifeRange)
                or GetNearestPlayerByRole("Hero", Config.AutoKnifeRange)
    if not target or not target.Character then return end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local theirHrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not myHrp or not theirHrp then return end
    myHrp.CFrame = CFrame.new(myHrp.Position, Vector3.new(theirHrp.Position.X, myHrp.Position.Y, theirHrp.Position.Z))
    if tick() - lastStab < 0.4 then return end
    lastStab = tick()
    pcall(function()
        local tool = myChar:FindFirstChildOfClass("Tool")
        if tool and tool.Activate then tool:Activate() end
    end)
end

-- ==================== AUTO-ESCAPE ====================
local escapeState = { active = false, savedCFrame = nil, safeSince = nil }

local function FindLobbySpawnForEscape()
    local lobbyFolder = Workspace:FindFirstChild("Lobby")
    if lobbyFolder then
        for _, obj in ipairs(lobbyFolder:GetDescendants()) do
            if obj:IsA("SpawnLocation") then return obj end
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            local node = obj
            for _ = 1, 6 do
                if not node then break end
                if node.Name:lower():find("lobby", 1, true) then return obj end
                node = node.Parent
            end
        end
    end
end

local function RunAutoEscape()
    if not Config.AutoEscape then
        if escapeState.active and escapeState.savedCFrame then
            local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myHrp then pcall(function() myHrp.CFrame = escapeState.savedCFrame end) end
            escapeState = { active = false, savedCFrame = nil, safeSince = nil }
        end
        return
    end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end
    local murderer = GetNearestPlayerByRole("Murderer", math.huge)
    local murdererHrp = murderer and murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart")
    if not murdererHrp then
        if escapeState.active and escapeState.savedCFrame then
            pcall(function() myHrp.CFrame = escapeState.savedCFrame end)
            escapeState = { active = false, savedCFrame = nil, safeSince = nil }
        end
        return
    end
    if escapeState.active then
        local savedPos = escapeState.savedCFrame and escapeState.savedCFrame.Position
        local dSaved = savedPos and (murdererHrp.Position - savedPos).Magnitude or math.huge
        local dMe = (murdererHrp.Position - myHrp.Position).Magnitude
        if dSaved >= Config.AutoEscapeReturnDist and dMe >= Config.AutoEscapeReturnDist then
            if not escapeState.safeSince then escapeState.safeSince = tick() end
            if tick() - escapeState.safeSince >= 2.0 then
                pcall(function() myHrp.CFrame = escapeState.savedCFrame end)
                escapeState = { active = false, savedCFrame = nil, safeSince = nil }
                Notify("Returned to original position", Color3.fromRGB(90, 220, 160))
                return
            end
        else
            escapeState.safeSince = nil
        end
        local lobbyPart = FindLobbySpawnForEscape()
        if lobbyPart and lobbyPart:IsA("BasePart") then
            pcall(function() myHrp.CFrame = CFrame.new(lobbyPart.Position + Vector3.new(0, 3, 0)) end)
        end
        return
    end
    local dist = (myHrp.Position - murdererHrp.Position).Magnitude
    if dist <= Config.AutoEscapeTriggerDist then
        escapeState.active = true
        escapeState.savedCFrame = myHrp.CFrame
        escapeState.safeSince = nil
        local lobbyPart = FindLobbySpawnForEscape()
        if lobbyPart and lobbyPart:IsA("BasePart") then
            pcall(function() myHrp.CFrame = CFrame.new(lobbyPart.Position + Vector3.new(0, 3, 0)) end)
            Notify("Murderer nearby — hid in lobby", Color3.fromRGB(255, 100, 100))
        else
            escapeState = { active = false, savedCFrame = nil, safeSince = nil }
        end
    end
end

-- ==================== GUN DETECTION v6 (UNIVERSAL + TOOL-ONLY) ====================
local pickupInProgress = false
local lastPickupTime = 0

local function IsDroppedGunPart(obj)
    if not obj or not obj:IsA("BasePart") then return false end
    if obj.Name ~= "GunDrop" then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and obj:IsDescendantOf(p.Character) then
            return false
        end
    end
    return true
end

local function IsHeldGunTool(obj)
    if not obj or not obj:IsA("Tool") then return false end
    local n = obj.Name:lower()
    if n == "knife" or n == "toys" then return false end
    if n:find("display") then return false end
    if n:find("belt") then return false end
    if n:find("attachment") then return false end
    if n:find("fake") then return false end
    if n:find("ref") then return false end
    return n:find("gun", 1, true) ~= nil
        or n == "hallowgun"
        or n == "revolver"
        or n == "pistol"
        or n == "deagle"
        or n == "firearm"
end

local function FindGroundGun()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if IsDroppedGunPart(obj) then
            return obj, obj, nil
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if IsHeldGunTool(obj) then
            local holder = nil
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character and obj:IsDescendantOf(p.Character) then
                    holder = p
                    break
                end
            end
            local isLiveHeld = false
            if holder then
                local hum = holder.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then isLiveHeld = true end
            end
            if not isLiveHeld then
                local handle = obj:FindFirstChild("Handle")
                    or obj:FindFirstChildWhichIsA("BasePart")
                if handle then
                    return obj, handle, nil
                end
            end
        end
    end

    return nil, nil, nil
end

local function FindGunHolder()
    for _, p in ipairs(Players:GetPlayers()) do        if p == LocalPlayer then continue end
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if char then
            for _, obj in ipairs(char:GetChildren()) do
                if IsHeldGunTool(obj) then return p, "equipped" end
            end
        end
        local bp = p:FindFirstChild("Backpack")
        if bp then
            for _, obj in ipairs(bp:GetChildren()) do
                if IsHeldGunTool(obj) then return p, "backpack" end
            end
        end
    end
    return nil, nil
end

local function AttemptGrab(gun, handle, myHrp)
    if not gun or not handle or not gun.Parent or not handle.Parent then
        return false
    end
    if not myHrp then return false end

    local hum = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")

    if gun:IsA("Tool") and hum then
        pcall(function() hum:EquipTool(gun) end)
    end

    pcall(function() handle:SetNetworkOwner(LocalPlayer) end)
    pcall(function() firetouchinterest(myHrp, handle, 0) end)
    pcall(function() firetouchinterest(myHrp, handle, 1) end)
    pcall(function() firetouchinterest(handle, myHrp, 0) end)
    pcall(function() firetouchinterest(handle, myHrp, 1) end)

    task.wait(0.08)

    if not HasItem(LocalPlayer, "Gun") then
        task.wait(0.15)
    end

    if not HasItem(LocalPlayer, "Gun") and gun:IsA("Tool") then
        pcall(function()
            local bp = LocalPlayer:FindFirstChild("Backpack")
            if bp and gun and gun.Parent then gun.Parent = bp end
        end)
    end

    return HasItem(LocalPlayer, "Gun")
end

local function TriggerSheriffPickup(isAuto)
    if pickupInProgress then
        if not isAuto then
            Notify("Pickup already in progress", Color3.fromRGB(255, 180, 90))
        end
        return
    end
    if HasItem(LocalPlayer, "Gun") then
        if not isAuto then
            Notify("You already have the Gun", Color3.fromRGB(255, 180, 90))
        end
        return
    end
    if tick() - lastPickupTime < 0.5 then return end
    lastPickupTime = tick()

    local holder, location = FindGunHolder()
    if holder then
        local label = holder.DisplayName or holder.Name
        if label ~= holder.Name then
            label = label .. " (" .. holder.Name .. ")"
        end
        Notify("❌ " .. label .. " has the Gun (" .. location .. ")",
            Color3.fromRGB(255, 100, 100), 5)
        return
    end

    local gun, handle = FindGroundGun()
    if not gun or not handle then
        Notify("❌ No dropped Gun on the ground",
            Color3.fromRGB(255, 100, 100), 5)
        return
    end

    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHrp then
        if not isAuto then
            Notify("You have no character", Color3.fromRGB(255, 100, 100))
        end
        return
    end

    pickupInProgress = true
    local gunPos = handle.Position
    Notify("🎯 Snapping to Gun on the ground...",
        Color3.fromRGB(255, 180, 90), 3)

    task.spawn(function()
        local savedCFrame = myHrp.CFrame
        pcall(function() myHrp.CFrame = CFrame.new(gunPos) end)
        RunService.Heartbeat:Wait()
        local success = AttemptGrab(gun, handle, myHrp)
        pcall(function()
            local myH2 = LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myH2 then myH2.CFrame = savedCFrame end
        end)
        if success then
            Notify("✅ Got the Gun!", Color3.fromRGB(90, 220, 160))
        else
            Notify("❌ Failed to grab Gun",
                Color3.fromRGB(255, 100, 100), 5)
        end
        pickupInProgress = false
    end)
end

-- ==================== KILL NOTIFIER ====================
local deathWatched = {}
local deathNotifiedThisRound = {}

local function WatchPlayerDeaths(player)
    if player == LocalPlayer or deathWatched[player] then return end
    deathWatched[player] = true
    local function onCharacter(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end
        deathNotifiedThisRound[player] = false
        hum.Died:Connect(function()
            if deathNotifiedThisRound[player] then return end
            deathNotifiedThisRound[player] = true
            local role = GetPlayerRole(player)
            if Config.KillNotifier then
                local dn = player.DisplayName or player.Name
                local label = dn ~= player.Name and (dn .. " (" .. player.Name .. ")") or player.Name
                Notify("💀 " .. label .. " (" .. role .. ") died",
                    RoleColors[role] or Color3.fromRGB(255, 255, 255), 5)
            end
        end)
    end
    player.CharacterAdded:Connect(onCharacter)
    if player.Character then task.spawn(onCharacter, player.Character) end
end

-- ==================== ANTI-AFK ====================
local antiAfkConn
function ApplyAntiAFK()
    if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
    if not Config.AntiAFK then return end
    antiAfkConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end)
end

-- ==================== FLING ====================
local ActiveFlings = {}
local FlingThreads = {}

local function RestoreMovement()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        pcall(function()
            hrp.Anchored = false
            hrp.Velocity = Vector3.new(0, 0, 0)
            hrp.RotVelocity = Vector3.new(0, 0, 0)
        end)
    end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
end

local function StopFling(player)
    local state = ActiveFlings[player]
    if state then state.running = false ActiveFlings[player] = nil end
    if FlingThreads[player] then
        pcall(function() task.cancel(FlingThreads[player]) end)
        FlingThreads[player] = nil
    end
    RestoreMovement()
end

local function FlingPlayer(player)
    if player == LocalPlayer then return false, "Cannot fling yourself" end
    if not player.Character then return false, "Player has no character" end
    local targetHrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not targetHrp then return false, "No HumanoidRootPart" end
    if ActiveFlings[player] then
        StopFling(player)
        return true, "Stopped flinging " .. player.Name
    end
    StopFling(player)
    local state = {running = true}
    ActiveFlings[player] = state
    pcall(function() targetHrp:SetNetworkOwner(LocalPlayer) end)
    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
        end
    end)

    local forceMul = (Config.FlingForce or 6500) / 6500

    local thread = task.spawn(function()
        local iteration = 0
        local spinAngle = 0
        local frontDistances = {2.0, 2.5, 3.0, 1.5, 2.8}
        local frontIndex = 0

        while state.running and iteration < 500 do
            iteration = iteration + 1
            local myC = LocalPlayer.Character
            local myH = myC and myC:FindFirstChild("HumanoidRootPart")
            local targetChar = player.Character
            local targetH = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
            local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            if not myH or not targetH or not targetHum or targetHum.Health <= 0 then break end

            if iteration % 5 == 0 then
                pcall(function() targetH:SetNetworkOwner(LocalPlayer) end)
            end

            local targetVel = targetH.AssemblyLinearVelocity
            local facingDir
            if targetVel.Magnitude > 2 then
                facingDir = Vector3.new(targetVel.X, 0, targetVel.Z).Unit
            else
                local lv = targetH.CFrame.LookVector
                facingDir = Vector3.new(lv.X, 0, lv.Z).Unit
            end

            frontIndex = (frontIndex % #frontDistances) + 1
            local frontDist = frontDistances[frontIndex]
            local frontPos = targetH.Position + (facingDir * frontDist)

            spinAngle = spinAngle + math.random(5000, 12000)
            local spin = CFrame.Angles(
                math.rad(spinAngle * 3),
                math.rad(spinAngle),
                math.rad(spinAngle * 2)
            )

            pcall(function()
                myH.Anchored = true
                myH.CFrame = CFrame.new(frontPos) * spin
                myH.Anchored = false
                local pushDir = -facingDir
                myH.Velocity = Vector3.new(
                    pushDir.X * math.random(4000, 9000) * forceMul,
                    math.random(2500, 7000) * forceMul,
                    pushDir.Z * math.random(4000, 9000) * forceMul
                )
                myH.RotVelocity = Vector3.new(
                    math.random(-5000, 5000),
                    math.random(-8000, 8000),
                    math.random(-5000, 5000)
                )
            end)
            RunService.Heartbeat:Wait()
        end
        RestoreMovement()
        ActiveFlings[player] = nil
        FlingThreads[player] = nil
    end)
    FlingThreads[player] = thread
    return true, "Flinging " .. player.Name
end

local function FindPlayerByRole(role)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and GetPlayerRole(p) == role then return p end
    end
end

-- ==================== TELEPORT ====================
local function FindLobbySpawn()
    local lobbyFolder = Workspace:FindFirstChild("Lobby")
    if lobbyFolder then
        for _, obj in ipairs(lobbyFolder:GetDescendants()) do
            if obj:IsA("SpawnLocation") then return obj end
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            local node = obj
            for _ = 1, 6 do
                if not node then break end
                if node.Name:lower():find("lobby", 1, true) then return obj end
                node = node.Parent
            end
        end
    end
end

local NON_MAP_NAMES = {
    lobby=true, spawns=true, spawn=true, effects=true, lights=true,
    camera=true, terrain=true, baseplate=true, debris=true, players=true,
    sound=true, sounds=true, music=true, gui=true, hud=true, scripts=true,
}
local MAP_KEYWORDS = {"house","mansion","bank","milbase","military","lab","laboratory","office","police",
    "prison","school","cabin","boat","cruise","farm","factory","hotel","hospital","mineshaft","mine",
    "pier","plane","ruins","snowy","snow","submarine","train","villa","warehouse","woods","sewer",
    "carnival","circus","mall","airport","alley","arcade","camp","castle","cave","church","city",
    "cliff","desert","docks","fair","forest","fort","garden","ghost","hideout","island","junkyard",
    "kingdom","library","lighthouse","manor","metro","motel","mountain","museum","nightclub",
    "observatory","park","penthouse","pyramid","ranch","resort","restaurant","river","rooftop",
    "sanctuary","ship","shop","skyscraper","slums","space","stadium","station","studio","subway",
    "temple","theater","themepark","tower","town","treehouse","tunnel","vault","village","volcano",
    "waterfall","zoo"}

local function IsNonMapName(n) return NON_MAP_NAMES[n:lower()] == true end
local function MatchesMapKeyword(n)
    local l = n:lower()
    for _, kw in ipairs(MAP_KEYWORDS) do
        if l:find(kw, 1, true) then return true end
    end
    return false
end

local function ScoreMapCandidate(child)
    if not (child:IsA("Model") or child:IsA("Folder")) then return -1 end
    if IsNonMapName(child.Name) then return -1 end
    if child:FindFirstChildOfClass("Humanoid") then return -1 end
    local score = 0
    if MatchesMapKeyword(child.Name) then score = score + 100 end
    local low = child.Name:lower()
    if low == "map" or low == "currentmap" then score = score + 150 end
    local parts, spawns, sampled = 0, 0, 0
    for _, d in ipairs(child:GetDescendants()) do
        sampled = sampled + 1
        if d:IsA("BasePart") then parts = parts + 1 end
        if d:IsA("SpawnLocation") then spawns = spawns + 1 end
        if sampled >= 200 then break end
    end
    if parts >= 3 then score = score + 20 end
    if parts >= 20 then score = score + 30 end
    if parts >= 100 then score = score + 40 end
    if spawns > 0 then score = score + 15 end
    if parts < 3 then score = score - 50 end
    return score
end

local function FindRealMapModel()
    local candidates = {}
    for _, child in ipairs(Workspace:GetChildren()) do
        local low = child.Name:lower()
        if low == "map" or low == "currentmap" or low == "playarea" or low == "round" then
            for _, sub in ipairs(child:GetChildren()) do
                if (sub:IsA("Model") or sub:IsA("Folder")) and not IsNonMapName(sub.Name) then
                    return sub, "contained"
                end
            end
            local s = ScoreMapCandidate(child)
            if s > 0 then return child, "named" end
        end
    end
    for _, child in ipairs(Workspace:GetChildren()) do
        local s = ScoreMapCandidate(child)
        if s > 0 then table.insert(candidates, {model = child, score = s}) end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    return candidates[1].model, "score"
end

local function FindSpawnInMap(mapModel)
    if not mapModel then return nil end
    for _, obj in ipairs(mapModel:GetDescendants()) do
        if obj:IsA("SpawnLocation") then return obj end
    end
    for _, obj in ipairs(mapModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if n:find("spawn", 1, true) or n == "start" or n == "teleport" then
                return obj
            end
        end
    end
    local bestPart, bestY = nil, -math.huge
    for _, obj in ipairs(mapModel:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Position.Y > bestY then
            bestY = obj.Position.Y
            bestPart = obj
        end
    end
    return bestPart
end

local function TeleportTo(part)
    if not part then return false, "No part" end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No character" end
    hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 5, 0))
    return true, "Teleported"
end

local function TeleportToLobby()
    local spawn = FindLobbySpawn()
    if not spawn then return false, "No lobby spawn" end
    return TeleportTo(spawn)
end

local function TeleportToMap()
    local mapModel = FindRealMapModel()
    if not mapModel then return false, "No map detected" end
    local spawn = FindSpawnInMap(mapModel)
    if not spawn then return false, "No spawn in map" end
    return TeleportTo(spawn)
end

local function RejoinServer()
    local placeId = game.PlaceId
    local jobId = game.JobId
    if not jobId or jobId == "" then return false, "No JobId" end
    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
    end)
    if ok then return true, "Rejoining" end
    return false, "Failed"
end

-- ==================== NOCLIP ====================
local noclipConn
function ApplyNoclip()
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not Config.Noclip then return end
    noclipConn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

-- ==================== SCREEN GUI ====================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GabrielsMystery"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = CoreGui

local MinPill = Instance.new("TextButton")
MinPill.Size = UDim2.new(0, 180, 0, 44)
MinPill.Position = UDim2.new(0.5, -90, 0, -60)
MinPill.BackgroundColor3 = Color3.fromRGB(28, 24, 36)
MinPill.BackgroundTransparency = TRANSPARENCY.MainWindow
MinPill.Text = "🔍  Gabriel's Mystery"
MinPill.TextColor3 = Color3.fromRGB(245, 240, 255)
MinPill.TextSize = 14
MinPill.Font = Enum.Font.GothamBold
MinPill.AutoButtonColor = false
MinPill.Active = true
MinPill.Draggable = true
MinPill.Visible = false
MinPill.Parent = ScreenGui
Instance.new("UICorner", MinPill).CornerRadius = UDim.new(1, 0)

local isMinimized = false

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 460, 0, 500)
Main.Position = UDim2.new(0.5, -230, 0.5, -250)
Main.BackgroundColor3 = Color3.fromRGB(28, 24, 36)
Main.BackgroundTransparency = TRANSPARENCY.MainWindow
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 24)

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(80, 68, 105)
MainStroke.Thickness = 1
MainStroke.Transparency = 0.4
MainStroke.Parent = Main

Main.Size = UDim2.new(0, 0, 0, 0)
Main.BackgroundTransparency = 1
TweenService:Create(Main, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
    Size = UDim2.new(0, 460, 0, 500),
    BackgroundTransparency = TRANSPARENCY.MainWindow
}):Play()

local function MinimizeUI()
    if isMinimized then return end
    isMinimized = true
    local shrink = TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1
    })
    shrink:Play()
    shrink.Completed:Connect(function() Main.Visible = false end)
    MinPill.Position = UDim2.new(0.5, -90, 0, -60)
    MinPill.BackgroundTransparency = 1
    MinPill.TextTransparency = 1
    MinPill.Visible = true
    task.wait(0.05)
    TweenService:Create(MinPill, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -90, 0, 16),
        BackgroundTransparency = TRANSPARENCY.MainWindow,
        TextTransparency = 0
    }):Play()
end

local function RestoreUI()
    if not isMinimized then return end
    isMinimized = false
    local pillOut = TweenService:Create(MinPill, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, -90, 0, -60),
        BackgroundTransparency = 1, TextTransparency = 1
    })
    pillOut:Play()
    pillOut.Completed:Connect(function() MinPill.Visible = false end)
    Main.Visible = true
    Main.Size = UDim2.new(0, 0, 0, 0)
    Main.BackgroundTransparency = 1
    TweenService:Create(Main, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 460, 0, 500),
        BackgroundTransparency = TRANSPARENCY.MainWindow
    }):Play()
end

MinPill.MouseButton1Click:Connect(RestoreUI)

-- Mobile buttons
local MobileButtonsGui = Instance.new("ScreenGui")
MobileButtonsGui.Name = "GM_MobileButtons"
MobileButtonsGui.ResetOnSpawn = false
MobileButtonsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
MobileButtonsGui.IgnoreGuiInset = true
MobileButtonsGui.Parent = CoreGui

local mobileAimOn = false
local MobileAimBtn, MobileGrabBtn

local function SetMobileButtonsVisible(state)
    MobileButtonsGui.Enabled = state
    Config.MobileButtonsEnabled = state
end

MobileAimBtn = Instance.new("TextButton")
MobileAimBtn.Size = UDim2.new(0, 90, 0, 90)
MobileAimBtn.Position = UDim2.new(0, 20, 0.5, 40)
MobileAimBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
MobileAimBtn.BackgroundTransparency = 0.15
MobileAimBtn.Text = "AIM\nOFF"
MobileAimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileAimBtn.TextSize = 16
MobileAimBtn.Font = Enum.Font.GothamBold
MobileAimBtn.Active = true
MobileAimBtn.Draggable = true
MobileAimBtn.Parent = MobileButtonsGui
Instance.new("UICorner", MobileAimBtn).CornerRadius = UDim.new(1, 0)

MobileAimBtn.MouseButton1Click:Connect(function()
    mobileAimOn = not mobileAimOn
    Config.AimbotEnabled = mobileAimOn
    MobileAimBtn.BackgroundColor3 = mobileAimOn and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(180, 60, 60)
    MobileAimBtn.Text = mobileAimOn and "AIM\nON" or "AIM\nOFF"
end)

MobileGrabBtn = Instance.new("TextButton")
MobileGrabBtn.Size = UDim2.new(0, 90, 0, 90)
MobileGrabBtn.Position = UDim2.new(0, 20, 0.5, -130)
MobileGrabBtn.BackgroundColor3 = Color3.fromRGB(180, 140, 40)
MobileGrabBtn.BackgroundTransparency = 0.15
MobileGrabBtn.Text = "GRAB\nGUN"
MobileGrabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileGrabBtn.TextSize = 16
MobileGrabBtn.Font = Enum.Font.GothamBold
MobileGrabBtn.Active = true
MobileGrabBtn.Draggable = true
MobileGrabBtn.Parent = MobileButtonsGui
Instance.new("UICorner", MobileGrabBtn).CornerRadius = UDim.new(1, 0)

MobileGrabBtn.MouseButton1Click:Connect(function() TriggerSheriffPickup() end)
SetMobileButtonsVisible(false)

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 80)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 300, 0, 40)
Title.Position = UDim2.new(0, 28, 0, 22)
Title.BackgroundTransparency = 1
Title.Text = "Gabriel's Mystery"
Title.TextColor3 = Color3.fromRGB(245, 240, 255)
Title.TextSize = 26
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local TitleShadow = Title:Clone()
TitleShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
TitleShadow.TextTransparency = 0.6
TitleShadow.Position = UDim2.new(0, 29, 0, 23)
TitleShadow.ZIndex = Title.ZIndex - 1
TitleShadow.Parent = Header

local function MakeIconButton(icon, xOffset, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 28, 0, 28)
    btn.Position = UDim2.new(1, xOffset, 0, 26)
    btn.BackgroundTransparency = 1
    btn.Text = icon
    btn.TextColor3 = color
    btn.TextSize = 20
    btn.Font = Enum.Font.GothamBold
    btn.Parent = Header
    btn.MouseButton1Click:Connect(callback)
    return btn
end

MakeIconButton("−", -64, Color3.fromRGB(255, 210, 60), function() MinimizeUI() end)
MakeIconButton("✕", -32, Color3.fromRGB(255, 80, 80), function()
    local fade = TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {
        Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1
    })
    fade:Play()
    fade.Completed:Connect(function() ScreenGui:Destroy() end)
end)

-- Platform chooser
local PlatformFrame = Instance.new("Frame")
PlatformFrame.Size = UDim2.new(1, -56, 0, 130)
PlatformFrame.Position = UDim2.new(0, 28, 0, 78)
PlatformFrame.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
PlatformFrame.BackgroundTransparency = 0.1
PlatformFrame.BorderSizePixel = 0
PlatformFrame.Parent = Main
Instance.new("UICorner", PlatformFrame).CornerRadius = UDim.new(0, 14)

local platTitle = Instance.new("TextLabel")
platTitle.Size = UDim2.new(1, -40, 0, 24)
platTitle.Position = UDim2.new(0, 20, 0, 10)
platTitle.BackgroundTransparency = 1
platTitle.Text = "Choose your platform"
platTitle.TextColor3 = Color3.fromRGB(245, 240, 255)
platTitle.TextSize = 15
platTitle.Font = Enum.Font.GothamBold
platTitle.TextXAlignment = Enum.TextXAlignment.Left
platTitle.Parent = PlatformFrame

local PCBtn = Instance.new("TextButton")
PCBtn.Size = UDim2.new(0.5, -25, 0, 50)
PCBtn.Position = UDim2.new(0, 15, 0, 45)
PCBtn.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
PCBtn.Text = "🖥  PC"
PCBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PCBtn.TextSize = 16
PCBtn.Font = Enum.Font.GothamBold
PCBtn.Parent = PlatformFrame
Instance.new("UICorner", PCBtn).CornerRadius = UDim.new(0, 10)

local MobileBtn = Instance.new("TextButton")
MobileBtn.Size = UDim2.new(0.5, -25, 0, 50)
MobileBtn.Position = UDim2.new(0.5, 10, 0, 45)
MobileBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 60)
MobileBtn.Text = "📱  Mobile"
MobileBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileBtn.TextSize = 16
MobileBtn.Font = Enum.Font.GothamBold
MobileBtn.Parent = PlatformFrame
Instance.new("UICorner", MobileBtn).CornerRadius = UDim.new(0, 10)

local RestOfUI = Instance.new("Frame")
RestOfUI.Size = UDim2.new(1, 0, 1, -130)
RestOfUI.Position = UDim2.new(0, 0, 0, 130)
RestOfUI.BackgroundTransparency = 1
RestOfUI.Visible = false
RestOfUI.Parent = Main

local function ShowRestOfUI()
    PlatformFrame.Visible = false
    RestOfUI.Visible = true
end

PCBtn.MouseButton1Click:Connect(function()
    SetMobileButtonsVisible(false)
    ShowRestOfUI()
    Notify("✅ PC mode selected", Color3.fromRGB(90, 220, 160), 3)
end)

MobileBtn.MouseButton1Click:Connect(function()
    SetMobileButtonsVisible(true)
    ShowRestOfUI()
    Notify("📱 Mobile mode — floating buttons on", Color3.fromRGB(255, 180, 90), 4)
end)

-- Tab bar
local TabBarHolder = Instance.new("Frame")
TabBarHolder.Size = UDim2.new(1, -56, 0, 40)
TabBarHolder.Position = UDim2.new(0, 28, 0, 8)
TabBarHolder.BackgroundTransparency = 1
TabBarHolder.ClipsDescendants = true
TabBarHolder.Parent = RestOfUI

local TabBar = Instance.new("ScrollingFrame")
TabBar.Size = UDim2.new(1, 0, 1, 0)
TabBar.BackgroundTransparency = 1
TabBar.BorderSizePixel = 0
TabBar.ScrollBarThickness = 0
TabBar.ScrollingDirection = Enum.ScrollingDirection.X
TabBar.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
TabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
TabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
TabBar.Parent = TabBarHolder

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.Padding = UDim.new(0, 8)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabBar

local tabButtons = {}

local function MakeTabButton(id, icon, label, width, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, width, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
    btn.BackgroundTransparency = TRANSPARENCY.TabPills
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = order
    btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 68, 105)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = btn
    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(0, 24, 1, 0)
    iconLbl.Position = UDim2.new(0, 14, 0, 0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = icon
    iconLbl.TextColor3 = Color3.fromRGB(220, 215, 235)
    iconLbl.TextSize = 15
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.TextXAlignment = Enum.TextXAlignment.Left
    iconLbl.Parent = btn
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -40, 1, 0)
    nameLbl.Position = UDim2.new(0, 38, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = label
    nameLbl.TextColor3 = Color3.fromRGB(220, 215, 235)
    nameLbl.TextSize = 13
    nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent = btn
    tabButtons[id] = btn
    return btn
end

local ContentHolder = Instance.new("Frame")
ContentHolder.Size = UDim2.new(1, -56, 1, -110)
ContentHolder.Position = UDim2.new(0, 28, 0, 56)
ContentHolder.BackgroundTransparency = 1
ContentHolder.ClipsDescendants = true
ContentHolder.Parent = RestOfUI

local ContentSlide = Instance.new("Frame")
ContentSlide.Size = UDim2.new(1, 0, 1, 0)
ContentSlide.BackgroundTransparency = 1
ContentSlide.Parent = ContentHolder

-- UI helpers
local function SectionHeader(parent, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 22)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(170, 160, 195)
    lbl.TextSize = 13
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
end

local function AddInfo(parent, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 30)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(150, 140, 175)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
end

local function ActionRow(parent, text, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
    row.BackgroundTransparency = TRANSPARENCY.Rows
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -32, 1, 0)
    label.Position = UDim2.new(0, 20, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(245, 240, 255)
    label.TextSize = 15
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    row.MouseButton1Click:Connect(callback)
    return row
end

local function ToggleRow(parent, text, default, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
    row.BackgroundTransparency = TRANSPARENCY.Rows
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -100, 1, 0)
    label.Position = UDim2.new(0, 20, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(245, 240, 255)
    label.TextSize = 15
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row
    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 44, 0, 24)
    track.Position = UDim2.new(1, -58, 0.5, -12)
    track.BackgroundColor3 = default and Color3.fromRGB(120, 90, 200) or Color3.fromRGB(45, 40, 58)
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = default and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = default and Color3.fromRGB(245, 240, 255) or Color3.fromRGB(160, 155, 180)
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local state = default
    local function applyState(animate)
        local tc = state and Color3.fromRGB(120, 90, 200) or Color3.fromRGB(45, 40, 58)
        local kc = state and Color3.fromRGB(245, 240, 255) or Color3.fromRGB(160, 155, 180)
        local kp = state and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        if animate then
            TweenService:Create(track, TweenInfo.new(0.18), {BackgroundColor3 = tc}):Play()
            TweenService:Create(knob, TweenInfo.new(0.18), {BackgroundColor3 = kc, Position = kp}):Play()
        else
            track.BackgroundColor3 = tc
            knob.BackgroundColor3 = kc
            knob.Position = kp
        end
    end
    applyState(false)
    row.MouseButton1Click:Connect(function()
        state = not state
        applyState(true)
        callback(state)
    end)
    return row
end

local function SliderRow(parent, name, min, max, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 52)
    frame.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
    frame.BackgroundTransparency = TRANSPARENCY.Rows
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -32, 0, 22)
    label.Position = UDim2.new(0, 20, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. default
    label.TextColor3 = Color3.fromRGB(245, 240, 255)
    label.TextSize = 13
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -32, 0, 8)
    bar.Position = UDim2.new(0, 20, 0, 32)
    bar.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
    bar.Parent = frame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(150, 110, 220)
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
    local dragging = false
    local function update(input)
        local pos = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (max - min) * pos)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        label.Text = name .. ": " .. value
        callback(value)
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end)
    bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    return frame
end

local function KeybindRow(parent, name, currentKeyName, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 48)
    frame.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
    frame.BackgroundTransparency = TRANSPARENCY.Rows
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, -20, 1, 0)
    label.Position = UDim2.new(0, 20, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(245, 240, 255)
    label.TextSize = 15
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 90, 0, 30)
    btn.Position = UDim2.new(1, -104, 0.5, -15)
    btn.BackgroundColor3 = Color3.fromRGB(120, 90, 200)
    btn.Text = currentKeyName
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local open = false
    local list
    btn.MouseButton1Click:Connect(function()
        if open and list then list:Destroy() list = nil open = false return end
        open = true
        list = Instance.new("Frame")
        list.Size = UDim2.new(1, -40, 0, 200)
        list.Position = UDim2.new(0, 20, 0, 50)
        list.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
        list.BorderSizePixel = 0
        list.ZIndex = 10
        list.Parent = frame
        Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)
        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 4
        scroll.CanvasSize = UDim2.new(0, 0, 0, #KeyOptions * 26)
        scroll.ZIndex = 11
        scroll.Parent = list
        local ll = Instance.new("UIListLayout")
        ll.Padding = UDim.new(0, 2)
        ll.Parent = scroll
        for _, opt in ipairs(KeyOptions) do
            local ob = Instance.new("TextButton")
            ob.Size = UDim2.new(1, -4, 0, 24)
            ob.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
            ob.Text = "  " .. opt.name
            ob.TextColor3 = Color3.fromRGB(230, 220, 245)
            ob.TextSize = 13
            ob.Font = Enum.Font.Gotham
            ob.TextXAlignment = Enum.TextXAlignment.Left
            ob.ZIndex = 12
            ob.Parent = scroll
            Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 6)
            ob.MouseButton1Click:Connect(function()
                btn.Text = opt.name
                callback(opt.key, opt.name)
                if list then list:Destroy() list = nil end
                open = false
            end)
        end
    end)
    return frame
end

local function CreateScrollingTab()
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 100, 160)
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Visible = false
    scroll.Parent = ContentSlide
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 8)
    list.Parent = scroll
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = scroll
    return scroll
end

local CombatScroll   = CreateScrollingTab()
local AutoScroll     = CreateScrollingTab()
local MovementScroll = CreateScrollingTab()
local FlingScroll    = CreateScrollingTab()
local TeleportScroll = CreateScrollingTab()
local ESPScroll      = CreateScrollingTab()
local ServerScroll   = CreateScrollingTab()

-- ==================== COMBAT TAB ====================
SectionHeader(CombatScroll, "Aimbot (Camera Lock)")
ToggleRow(CombatScroll, "Enable Aimbot", Config.AimbotEnabled, function(v)
    Config.AimbotEnabled = v
    DebouncedAutoSave()
end)
AddInfo(CombatScroll, "Camera locks onto Murderer — you still need to click to shoot.")
ToggleRow(CombatScroll, "Team Check", Config.AutoShootTeamCheck, function(v)
    Config.AutoShootTeamCheck = v
    DebouncedAutoSave()
end)
ToggleRow(CombatScroll, "Wall Check", Config.AutoShootWallCheck, function(v)
    Config.AutoShootWallCheck = v
    DebouncedAutoSave()
end)
SliderRow(CombatScroll, "Max Range", 50, 1000, Config.AutoShootRange, function(v)
    Config.AutoShootRange = v
    DebouncedAutoSave()
end)

SectionHeader(CombatScroll, "Murderer Hitbox")
ToggleRow(CombatScroll, "Enable Hitbox Boost", Config.HitboxEnabled, function(v)
    Config.HitboxEnabled = v
    if not v then
        for p in pairs(MurdererHitboxes) do RemoveHitboxFor(p) end
    end
    DebouncedAutoSave()
end)
SliderRow(CombatScroll, "Hitbox Size", 4, 20, Config.HitboxSize, function(v)
    Config.HitboxSize = v
    DebouncedAutoSave()
end)

SectionHeader(CombatScroll, "Auto-Knife")
ToggleRow(CombatScroll, "Enable Auto-Knife", Config.AutoKnife, function(v)
    Config.AutoKnife = v
    DebouncedAutoSave()
end)
SliderRow(CombatScroll, "Stab Range", 3, 20, Config.AutoKnifeRange, function(v)
    Config.AutoKnifeRange = v
    DebouncedAutoSave()
end)

SectionHeader(CombatScroll, "Keybinds")
KeybindRow(CombatScroll, "Aimbot Key", Config.AimbotKeyName, function(key, name)
    Config.AimbotKey = key
    Config.AimbotKeyName = name
    Notify("Aimbot key: " .. name, Color3.fromRGB(90, 220, 160), 3)
    SaveConfig(false)
end)
KeybindRow(CombatScroll, "Grab Gun Key", Config.GrabGunKeyName, function(key, name)
    Config.GrabGunKey = key
    Config.GrabGunKeyName = name
    Notify("Grab Gun key: " .. name, Color3.fromRGB(90, 220, 160), 3)
    SaveConfig(false)
end)

-- ==================== AUTO TAB ====================
SectionHeader(AutoScroll, "Sheriff Pickup")
AddInfo(AutoScroll, "Only works when the gun is DROPPED on the ground.")
ToggleRow(AutoScroll, "🤖 Auto-Sheriff Pickup", Config.AutoSheriffPickup, function(v)
    Config.AutoSheriffPickup = v
    Notify(v and "Auto-Sheriff ON" or "Auto-Sheriff OFF",
        v and Color3.fromRGB(90, 220, 160) or Color3.fromRGB(255, 180, 90), 4)
    DebouncedAutoSave()
end)
ActionRow(AutoScroll, "🔫 Grab Dropped Gun Now", function() TriggerSheriffPickup() end)

SectionHeader(AutoScroll, "Auto-Escape")
ToggleRow(AutoScroll, "Enable Auto-Escape", Config.AutoEscape, function(v)
    Config.AutoEscape = v
    DebouncedAutoSave()
end)
SliderRow(AutoScroll, "Escape Trigger Distance", 10, 100, Config.AutoEscapeTriggerDist, function(v)
    Config.AutoEscapeTriggerDist = v
    DebouncedAutoSave()
end)
SliderRow(AutoScroll, "Return Distance", 50, 500, Config.AutoEscapeReturnDist, function(v)
    Config.AutoEscapeReturnDist = v
    DebouncedAutoSave()
end)

SectionHeader(AutoScroll, "Notifications")
ToggleRow(AutoScroll, "Kill Notifier", Config.KillNotifier, function(v)
    Config.KillNotifier = v
    DebouncedAutoSave()
end)
ToggleRow(AutoScroll, "Anti-AFK", Config.AntiAFK, function(v)
    Config.AntiAFK = v
    ApplyAntiAFK()
    DebouncedAutoSave()
end)

-- ==================== MOVEMENT TAB ====================
SectionHeader(MovementScroll, "Movement")
ToggleRow(MovementScroll, "Noclip", Config.Noclip, function(v)
    Config.Noclip = v
    ApplyNoclip()
    DebouncedAutoSave()
end)
AddInfo(MovementScroll, "Walk through walls and objects.")

SectionHeader(MovementScroll, "Mobile")
ToggleRow(MovementScroll, "Show Floating Buttons", Config.MobileButtonsEnabled, function(v)
    SetMobileButtonsVisible(v)
    Notify(v and "Mobile buttons ON" or "Mobile buttons OFF",
        Color3.fromRGB(90, 220, 160), 3)
    DebouncedAutoSave()
end)

-- ==================== FLING TAB ====================
SectionHeader(FlingScroll, "Quick Fling")
ActionRow(FlingScroll, "💥 Fling Murderer", function()
    local p = FindPlayerByRole("Murderer")
    if p then
        local ok, msg = FlingPlayer(p)
        Notify(msg or "", Color3.fromRGB(255, 100, 100))
    else
        Notify("No Murderer found", Color3.fromRGB(255, 100, 100))
    end
end)
ActionRow(FlingScroll, "💥 Fling Sheriff", function()
    local p = FindPlayerByRole("Sheriff")
    if p then
        local ok, msg = FlingPlayer(p)
        Notify(msg or "", Color3.fromRGB(90, 160, 255))
    else
        Notify("No Sheriff found", Color3.fromRGB(255, 100, 100))
    end
end)
ActionRow(FlingScroll, "🛑 Stop All Flings", function()
    for _, p in ipairs(Players:GetPlayers()) do
        if ActiveFlings[p] then StopFling(p) end
    end
    RestoreMovement()
    Notify("Stopped all flings", Color3.fromRGB(255, 180, 90))
end)

SectionHeader(FlingScroll, "Fling Force")
SliderRow(FlingScroll, "Force", 1000, 15000, Config.FlingForce, function(v)
    Config.FlingForce = v
    DebouncedAutoSave()
end)
AddInfo(FlingScroll, "Higher = more chaos. Default 6500.")

SectionHeader(FlingScroll, "Fling Player From List")
AddInfo(FlingScroll, "Select any player in the server to fling. Use REFRESH to update.")

local playerListContainer
local function BuildPlayerList()
    if playerListContainer then playerListContainer:Destroy() end
    playerListContainer = Instance.new("Frame")
    playerListContainer.Size = UDim2.new(1, 0, 0, 0)
    playerListContainer.AutomaticSize = Enum.AutomaticSize.Y
    playerListContainer.BackgroundTransparency = 1
    playerListContainer.Parent = FlingScroll
    local ll = Instance.new("UIListLayout")
    ll.Padding = UDim.new(0, 4)
    ll.Parent = playerListContainer

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local role = GetPlayerRole(p)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = Color3.fromRGB(40, 34, 50)
        row.BackgroundTransparency = 0.3
        row.Parent = playerListContainer
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(0.6, 0, 1, 0)
        nameLbl.Position = UDim2.new(0, 12, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = p.Name .. " [" .. role .. "]"
        nameLbl.TextColor3 = RoleColors[role] or Color3.fromRGB(220, 220, 220)
        nameLbl.TextSize = 12
        nameLbl.Font = Enum.Font.Gotham
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.Parent = row

        local flingBtn = Instance.new("TextButton")
        flingBtn.Size = UDim2.new(0, 70, 0, 26)
        flingBtn.Position = UDim2.new(1, -78, 0.5, -13)
        flingBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        flingBtn.Text = "FLING"
        flingBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        flingBtn.TextSize = 11
        flingBtn.Font = Enum.Font.GothamBold
        flingBtn.Parent = row
        Instance.new("UICorner", flingBtn).CornerRadius = UDim.new(0, 6)

        flingBtn.MouseButton1Click:Connect(function()
            local ok, msg = FlingPlayer(p)
            Notify(msg or "Fling failed",
                ok and Color3.fromRGB(255, 180, 90) or Color3.fromRGB(255, 100, 100))
        end)
    end
end

ActionRow(FlingScroll, "🔄 Refresh Player List", function()
    BuildPlayerList()
    Notify("Player list refreshed", Color3.fromRGB(90, 220, 160), 2)
end)
BuildPlayerList()

-- ==================== TELEPORT TAB ====================
SectionHeader(TeleportScroll, "Teleport")
ActionRow(TeleportScroll, "🏠 Teleport to Lobby", function()
    local ok, msg = TeleportToLobby()
    Notify(msg or "Failed", ok and Color3.fromRGB(90, 220, 160) or Color3.fromRGB(255, 100, 100))
end)
ActionRow(TeleportScroll, "🗺 Teleport to Map", function()
    local ok, msg = TeleportToMap()
    Notify(msg or "Failed", ok and Color3.fromRGB(90, 220, 160) or Color3.fromRGB(255, 100, 100))
end)
AddInfo(TeleportScroll, "Teleports your character to the lobby or the map spawn.")

-- ==================== ESP TAB ====================
SectionHeader(ESPScroll, "ESP Settings")
ToggleRow(ESPScroll, "Enable ESP", Config.ESPEnabled, function(v)
    Config.ESPEnabled = v
    DebouncedAutoSave()
end)
ToggleRow(ESPScroll, "Show Name", Config.ESPShowName, function(v)
    Config.ESPShowName = v
    DebouncedAutoSave()
end)
ToggleRow(ESPScroll, "Show Role", Config.ESPShowRole, function(v)
    Config.ESPShowRole = v
    DebouncedAutoSave()
end)
ToggleRow(ESPScroll, "Show Distance", Config.ESPShowDistance, function(v)
    Config.ESPShowDistance = v
    DebouncedAutoSave()
end)
SliderRow(ESPScroll, "Fill Transparency", 0, 100, math.floor(Config.ESPFillTransparency * 100), function(v)
    Config.ESPFillTransparency = v / 100
    DebouncedAutoSave()
end)

-- ==================== SERVER TAB ====================
SectionHeader(ServerScroll, "Server")
ActionRow(ServerScroll, "🔄 Rejoin Same Server", function()
    local ok, msg = RejoinServer()
    Notify(msg or "Failed", ok and Color3.fromRGB(90, 220, 160) or Color3.fromRGB(255, 100, 100))
end)
ActionRow(ServerScroll, "🔄 Reset Role Cache", function()
    RefreshSheriffTracking()
    LastKnifeHolder = nil
    Notify("Role cache reset", Color3.fromRGB(180, 140, 255))
end)

SectionHeader(ServerScroll, "Config Save / Load")
AddInfo(ServerScroll, "Settings auto-save on every change. Manual controls below.")
ActionRow(ServerScroll, "💾 Save Config Now", function() SaveConfig(true) end)
ActionRow(ServerScroll, "📂 Load Config", function() LoadConfig(true) end)
ActionRow(ServerScroll, "🗑 Reset to Defaults", function()
    Config.AimbotEnabled = false
    Config.AutoShootTeamCheck = true
    Config.AutoShootRange = 500
    Config.AutoShootWallCheck = false
    Config.HitboxEnabled = true
    Config.HitboxSize = 8
    Config.AutoKnife = false
    Config.AutoKnifeRange = 8
    Config.AutoEscape = false
    Config.AutoEscapeTriggerDist = 30
    Config.AutoEscapeReturnDist = 150
    Config.KillNotifier = true
    Config.AntiAFK = true
    Config.AutoSheriffPickup = false
    Config.Noclip = false
    Config.ESPEnabled = true
    Config.ESPShowName = true
    Config.ESPShowRole = true
    Config.ESPShowDistance = true
    Config.ESPFillTransparency = 0.65
    Config.AimbotKey = Enum.KeyCode.Q
    Config.AimbotKeyName = "Q"
    Config.GrabGunKey = Enum.KeyCode.LeftControl
    Config.GrabGunKeyName = "Ctrl"
    Config.FlingForce = 6500
    ApplyNoclip()
    ApplyAntiAFK()
    Notify("⚙️ Settings reset — reopen tabs to see changes", Color3.fromRGB(255, 180, 90), 5)
    SaveConfig(false)
end)

-- Tab switching
local allTabs = {
    Combat = CombatScroll, Auto = AutoScroll, Movement = MovementScroll,
    Fling = FlingScroll, Teleport = TeleportScroll, ESP = ESPScroll, Server = ServerScroll,
}
local tabButtonMap = {}
tabButtonMap.Combat   = MakeTabButton("Combat",   "⚔", "Combat",   95, 1)
tabButtonMap.Auto     = MakeTabButton("Auto",     "⚡", "Auto",     75, 2)
tabButtonMap.Movement = MakeTabButton("Movement", "🏃", "Move",     80, 3)
tabButtonMap.Fling    = MakeTabButton("Fling",    "💥", "Fling",    75, 4)
tabButtonMap.Teleport = MakeTabButton("Teleport", "🌀", "TP",       65, 5)
tabButtonMap.ESP      = MakeTabButton("ESP",      "👁", "ESP",      65, 6)
tabButtonMap.Server   = MakeTabButton("Server",   "🖥", "Server",   80, 7)

local currentTab = nil
local switching = false

local function AnimateTabSwitch(newTabName)
    if switching or currentTab == newTabName then return end
    switching = true
    local newTab = allTabs[newTabName]
    if not newTab then switching = false return end
    if currentTab and allTabs[currentTab] then
        local out = TweenService:Create(ContentSlide, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Position = UDim2.new(-0.15, 0, 0, 0)
        })
        out:Play()
        out.Completed:Wait()
    end
    for _, tab in pairs(allTabs) do tab.Visible = false end
    newTab.Visible = true
    ContentSlide.Position = UDim2.new(0.15, 0, 0, 0)
    TweenService:Create(ContentSlide, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()
    currentTab = newTabName
    switching = false
end

local function SetActiveTabButton(activeId)
    for id, btn in pairs(tabButtonMap) do
        local isActive = (id == activeId)
        TweenService:Create(btn, TweenInfo.new(0.2), {
            BackgroundColor3 = isActive and Color3.fromRGB(70, 58, 92) or Color3.fromRGB(40, 34, 50),
            BackgroundTransparency = isActive and TRANSPARENCY.TabPillsActive or TRANSPARENCY.TabPills
        }):Play()
    end
end

for id, btn in pairs(tabButtonMap) do
    btn.MouseButton1Click:Connect(function()
        SetActiveTabButton(id)
        AnimateTabSwitch(id)
    end)
end

for _, tab in pairs(allTabs) do tab.Visible = false end
CombatScroll.Visible = true
currentTab = "Combat"
SetActiveTabButton("Combat")

-- Input
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.K then
        if isMinimized then RestoreUI() else MinimizeUI() end
    elseif input.KeyCode == Config.AimbotKey then
        Config.AimbotEnabled = not Config.AimbotEnabled
        Notify("Aimbot: " .. (Config.AimbotEnabled and "ON" or "OFF"),
            Config.AimbotEnabled and Color3.fromRGB(90, 220, 160) or Color3.fromRGB(180, 140, 255), 3)
    elseif input.KeyCode == Config.GrabGunKey then
        TriggerSheriffPickup()
    end
end)

Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then
        CreateESP(p)
        p.CharacterAdded:Connect(function()
            task.wait(1)
            RefreshSheriffTracking()
        end)
        WatchPlayerDeaths(p)
        task.wait(0.5)
        pcall(BuildPlayerList)
    end
end)

Players.PlayerRemoving:Connect(function(p)
    RemoveESP(p)
    StopFling(p)
    RemoveHitboxFor(p)
    deathWatched[p] = nil
    deathNotifiedThisRound[p] = nil
    if SheriffUserId == p.UserId then RefreshSheriffTracking() end
    task.wait(0.5)
    pcall(BuildPlayerList)
end)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        CreateESP(p)
        WatchPlayerDeaths(p)
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    RefreshSheriffTracking()
    LastKnifeHolder = nil
    ApplyNoclip()
    RestoreMovement()
end)

task.spawn(function()
    while task.wait(ROLE_POLL_INTERVAL) do
        local now = tick()
        if now - LastSheriffCheck < ROLE_POLL_INTERVAL then continue end
        LastSheriffCheck = now
        local sheriff = SheriffUserId and Players:GetPlayerByUserId(SheriffUserId)
        if sheriff and not HasItem(sheriff, "Gun") and not SheriffDead then
            SheriffDead = true
            Notify("💀 Sheriff died!", Color3.fromRGB(255, 100, 100), 5)
            if Config and Config.AutoSheriffPickup and TriggerSheriffPickup then
                task.spawn(function()
                    task.wait(0.5)
                    TriggerSheriffPickup(true)
                end)
            end
        end
        local newGunHolder = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and HasItem(p, "Gun") then
                newGunHolder = p
                break
            end
        end
        if newGunHolder and newGunHolder.UserId ~= SheriffUserId then
            RefreshSheriffTracking()
        end
        local knifeHolder = GetKnifeHolder()
        if knifeHolder ~= LastKnifeHolder then
            LastKnifeHolder = knifeHolder
            RefreshSheriffTracking()
        end
    end
end)

task.spawn(function()
    task.wait(2)
    RefreshSheriffTracking()
end)

task.spawn(ApplyAntiAFK)

RunService.RenderStepped:Connect(function()
    UpdateESP()
    RunAimbot()
    RunAutoKnife()
    RunAutoEscape()
    UpdateHitboxes()
end)

Notify("✅ Gabriel's Mystery v6 loaded!", Color3.fromRGB(90, 220, 160), 4)
print("[Gabriel's Mystery v6] Loaded")
