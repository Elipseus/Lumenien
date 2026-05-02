local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/GhostDuckyy/UI-Libraries/main/Neverlose/source.lua"))()

local Window = Library:Window({ text = "lumens gui" })

local StarterGui       = game:GetService("StarterGui")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local LP               = Players.LocalPlayer
local camera           = workspace.CurrentCamera

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = 4})
    end)
end

-- ================================================
-- STATE VARS
-- ================================================
local infiniteSprint   = false; local sprintConn     = nil
local jumpBoost        = false; local jpLoop         = nil; local jpCA = nil
local aimlockEnabled   = false; local lockedTarget   = nil
local inputConn        = nil;   local renderConn     = nil
local aimlockBind      = Enum.KeyCode.Q
local noclipEnabled    = false; local noclipConn     = nil
local oldLighting      = {}
local autogen          = false; local genconn        = nil; local firingconn = nil
local lastfiretime     = 0;     local genmode        = "Blatant"; local customdelay = 3
local autoEscape       = false; local autoEscapeConn = nil
local dotEnabled       = false; local dotConn        = nil
local instantInteract  = false; local promptConns    = {}
local safeTeleport     = false; local safePart       = nil
local viewKiller       = false
local killerAddedConn  = nil;   local killerRemovedConn = nil
local antiDeath        = { enabled=false, threshold=30, conn=nil, lastPos=nil, teleported=false, debounce=false, plate=nil }
local esp              = { survivors={}, killers={}, generators={} }
local batteryHighlights= {}; local fuseHighlights   = {}
local trapHighlights   = {}; local minionHighlights  = {}
local batteryConn      = nil; local fuseConn         = nil
local descendantConn   = nil; local minionConn       = nil
local playerLabels     = {}
local espMethod        = "Highlight"
local isMobile         = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local tpSpeed          = 25
local allESPActive     = false
local guiVisible       = true
local autoLoad         = false
local playerConfigs    = {}
local configPath       = "lumens_configs.json"

local pp = Instance.new("Part")
pp.Name = "pp"; pp.Size = Vector3.new(50,2,50)
pp.Position = Vector3.new(0,1000,0); pp.Anchored = true
pp.CanCollide = true; pp.Transparency = 0.3
pp.Parent = workspace

-- ================================================
-- GUI TOGGLE
-- ================================================
local TweenService = game:GetService("TweenService")
local guiFrame = game:GetService("CoreGui"):WaitForChild("Neverlose")
local bodyFrame = guiFrame:WaitForChild("Body")
local guiVisible = true
local toggling = false

-- add a UIScale to bodyFrame so we can tween scale instead of size
local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = bodyFrame

local function hideGUI()
    if toggling then return end
    toggling = true
    guiVisible = false
    TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Scale = 0
    }):Play()
    task.delay(0.22, function()
        bodyFrame.Visible = false
        uiScale.Scale = 1
        toggling = false
    end)
end

local function showGUI()
    if toggling then return end
    toggling = true
    guiVisible = true
    uiScale.Scale = 0
    bodyFrame.Visible = true
    TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1
    }):Play()
    task.delay(0.3, function()
        toggling = false
    end)
end

local function toggleGUI()
    if guiVisible then hideGUI() else showGUI() end
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightAlt then toggleGUI() end
end)

local dragging = false
local dragInput, dragStart, startPos

bodyFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = bodyFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

bodyFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        local targetPos = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        TweenService:Create(bodyFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = targetPos
        }):Play()
    end
end)

-- ================================================
-- CONFIG PERSISTENCE
-- ================================================
local function saveConfigsToFile()
    pcall(function()
        local data = {}
        for name, snap in pairs(playerConfigs) do
            data[name] = snap
        end
        data["__autoload__"] = autoLoad
        writefile(configPath, HttpService:JSONEncode(data))
    end)
end

local function loadConfigsFromFile()
    pcall(function()
        if not isfile(configPath) then return end
        local raw = readfile(configPath)
        if not raw or raw == "" then return end
        local data = HttpService:JSONDecode(raw)
        if data["__autoload__"] ~= nil then
            autoLoad = data["__autoload__"]
            data["__autoload__"] = nil
        end
        for name, snap in pairs(data) do
            playerConfigs[name] = snap
        end
    end)
end

loadConfigsFromFile()

-- ================================================
-- HELPERS
-- ================================================
local function getMyTeamFolder()
    local char = LP.Character
    if not char then return nil end
    local pf = workspace:FindFirstChild("PLAYERS")
    if not pf then return nil end
    if char.Parent == pf:FindFirstChild("ALIVE") then return "ALIVE" end
    if char.Parent == pf:FindFirstChild("KILLER") then return "KILLER" end
    return nil
end

local function lerpMove(root, targetCF)
    if not root then return end
    local startCF = root.CFrame
    local dist = (startCF.Position - targetCF.Position).Magnitude
    if dist < 1 then root.CFrame = targetCF return end
    local t = 0
    while t < dist / tpSpeed do
        t += RunService.Heartbeat:Wait()
        root.CFrame = startCF:Lerp(targetCF, math.clamp(t / (dist/tpSpeed), 0, 1))
    end
    root.CFrame = targetCF
end

local function lerpTo(targetCF)
    local char = LP.Character or LP.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    lerpMove(root, targetCF)
end

local function returnToLastPos()
    if antiDeath.plate then antiDeath.plate:Destroy() antiDeath.plate = nil end
    if antiDeath.lastPos then task.spawn(function() lerpTo(antiDeath.lastPos) end) end
    antiDeath.lastPos = nil
    antiDeath.teleported = false
end

-- ================================================
-- ESP HELPERS
-- ================================================
local function newHighlight(obj, color)
    if not obj then return end
    local h = Instance.new("Highlight")
    h.FillColor = color; h.FillTransparency = 0.5
    h.OutlineColor = color; h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Adornee = obj; h.Parent = obj
    return h
end

local function createDrawingBox()
    local box = Drawing.new("Square")
    box.Thickness = 2; box.Filled = false; box.Transparency = 1
    return box
end

local function updateDrawingBox(box, obj)
    if not box or not obj then return end
    local root = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
    if not root then return end
    local vector, onScreen = camera:WorldToViewportPoint(root.Position)
    if onScreen then
        local size = (camera:WorldToViewportPoint(root.Position + Vector3.new(0,3,0)) - vector).Y * 2.5
        box.Size = Vector2.new(size*1.2, size)
        box.Position = Vector2.new(vector.X - box.Size.X/2, vector.Y - box.Size.Y/2)
        box.Visible = true
    else box.Visible = false end
end

local function createPlayerLabels(char, showHealth)
    if not char or playerLabels[char] or char == LP.Character then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    billboard.Size = UDim2.new(0, 120, 0, 45)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = math.huge
    billboard.Parent = char

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1,0,1,0)
    frame.BackgroundTransparency = 1
    frame.Parent = billboard

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = frame

    local healthLabel, staminaLabel

    if showHealth then
        healthLabel = Instance.new("TextLabel")
        healthLabel.Size = UDim2.new(1, 0, 0, 18)
        healthLabel.BackgroundTransparency = 1
        healthLabel.TextStrokeTransparency = 0
        healthLabel.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        healthLabel.Font = Enum.Font.GothamBold
        healthLabel.TextSize = 13
        healthLabel.TextScaled = false
        healthLabel.Text = "100 / 100"
        healthLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
        healthLabel.LayoutOrder = 1
        healthLabel.Parent = frame
    end

    staminaLabel = Instance.new("TextLabel")
    staminaLabel.Size = UDim2.new(1, 0, 0, 18)
    staminaLabel.BackgroundTransparency = 1
    staminaLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
    staminaLabel.TextStrokeTransparency = 0
    staminaLabel.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    staminaLabel.Font = Enum.Font.GothamBold
    staminaLabel.TextSize = 13
    staminaLabel.TextScaled = false
    staminaLabel.Text = "100 / 100"
    staminaLabel.LayoutOrder = 2
    staminaLabel.Parent = frame

    playerLabels[char] = { gui=billboard, healthText=healthLabel, staminaText=staminaLabel, humanoid=hum }

    if showHealth and healthLabel then
        hum.HealthChanged:Connect(function()
            if not playerLabels[char] then return end
            local hp = math.floor(hum.Health)
            healthLabel.Text = hp .. " / " .. math.floor(hum.MaxHealth)
            healthLabel.TextColor3 = hp >= 75 and Color3.fromRGB(0,255,100) or hp >= 41 and Color3.fromRGB(255,220,0) or Color3.fromRGB(255,50,50)
        end)
        local hp = math.floor(hum.Health)
        healthLabel.Text = hp .. " / " .. math.floor(hum.MaxHealth)
        healthLabel.TextColor3 = hp >= 75 and Color3.fromRGB(0,255,100) or hp >= 41 and Color3.fromRGB(255,220,0) or Color3.fromRGB(255,50,50)
    end

    char:GetAttributeChangedSignal("Stamina"):Connect(function()
        if not playerLabels[char] then return end
        staminaLabel.Text = math.floor(char:GetAttribute("Stamina") or 0) .. " / " .. math.floor(char:GetAttribute("MaxStamina") or 100)
    end)
    staminaLabel.Text = math.floor(char:GetAttribute("Stamina") or 0) .. " / " .. math.floor(char:GetAttribute("MaxStamina") or 100)
end

local function espAdd(tbl, obj, color)
    if not obj or tbl[obj] or obj == LP.Character then return end
    if espMethod == "Dual" then
        tbl[obj] = { highlight=newHighlight(obj,color), drawing=createDrawingBox() }
        tbl[obj].drawing.Color = color
    elseif espMethod == "Highlight" then
        tbl[obj] = newHighlight(obj, color)
    else
        local box = createDrawingBox(); box.Color = color; tbl[obj] = box
    end
    if tbl == esp.survivors then createPlayerLabels(obj, true)
    elseif tbl == esp.killers then createPlayerLabels(obj, false) end
end

local function espRemove(tbl, obj)
    if not tbl[obj] then return end
    if typeof(tbl[obj]) == "table" then
        if tbl[obj].highlight then tbl[obj].highlight:Destroy() end
        if tbl[obj].drawing then tbl[obj].drawing:Remove() end
    elseif typeof(tbl[obj]) == "Instance" then tbl[obj]:Destroy()
    else tbl[obj]:Remove() end
    tbl[obj] = nil
    if playerLabels[obj] then
        if playerLabels[obj].gui then playerLabels[obj].gui:Destroy() end
        playerLabels[obj] = nil
    end
end

local function espClear(tbl)
    for obj in pairs(tbl) do espRemove(tbl, obj) end
end

RunService.RenderStepped:Connect(function()
    if espMethod ~= "Drawing" and espMethod ~= "Dual" then return end
    for _, tbl in pairs({esp.survivors, esp.killers, esp.generators}) do
        for obj, data in pairs(tbl) do
            if typeof(data) == "table" and data.drawing then updateDrawingBox(data.drawing, obj)
            elseif typeof(data) ~= "Instance" then updateDrawingBox(data, obj) end
        end
    end
end)

-- ================================================
-- ESP ENABLE/DISABLE
-- ================================================
local survivorESPOn=false; local killerESPOn=false; local generatorESPOn=false
local batteryESPOn=false;  local fuseESPOn=false;   local trapESPOn=false
local minionESPOn=false

local function enableSurvivorESP()
    local pf = workspace:FindFirstChild("PLAYERS")
    local alive = pf and pf:FindFirstChild("ALIVE")
    if not alive then return end
    for _, v in ipairs(alive:GetChildren()) do if v:IsA("Model") then espAdd(esp.survivors,v,Color3.fromRGB(80,180,255)) end end
    esp.survivorAdd = alive.ChildAdded:Connect(function(v) if v:IsA("Model") then espAdd(esp.survivors,v,Color3.fromRGB(80,180,255)) end end)
    esp.survivorRemove = alive.ChildRemoved:Connect(function(v) espRemove(esp.survivors,v) end)
end
local function disableSurvivorESP()
    if esp.survivorAdd then esp.survivorAdd:Disconnect() esp.survivorAdd = nil end
    if esp.survivorRemove then esp.survivorRemove:Disconnect() esp.survivorRemove = nil end
    espClear(esp.survivors)
end

local function enableKillerESP()
    local pf = workspace:FindFirstChild("PLAYERS")
    local killers = pf and pf:FindFirstChild("KILLER")
    if not killers then return end
    for _, v in ipairs(killers:GetChildren()) do if v:IsA("Model") then espAdd(esp.killers,v,Color3.fromRGB(255,80,80)) end end
    esp.killerAdd = killers.ChildAdded:Connect(function(v) if v:IsA("Model") then espAdd(esp.killers,v,Color3.fromRGB(255,80,80)) end end)
    esp.killerRemove = killers.ChildRemoved:Connect(function(v) espRemove(esp.killers,v) end)
end
local function disableKillerESP()
    if esp.killerAdd then esp.killerAdd:Disconnect() esp.killerAdd = nil end
    if esp.killerRemove then esp.killerRemove:Disconnect() esp.killerRemove = nil end
    espClear(esp.killers)
end

local function enableGeneratorESP()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") and v.Name == "Generator" then espAdd(esp.generators,v,Color3.fromRGB(0,255,100)) end
    end
    esp.genAdd = workspace.DescendantAdded:Connect(function(v)
        if v:IsA("Model") and v.Name == "Generator" then espAdd(esp.generators,v,Color3.fromRGB(0,255,100)) end
    end)
    esp.genRemove = workspace.DescendantRemoving:Connect(function(v)
        if esp.generators[v] then espRemove(esp.generators,v) end
    end)
end
local function disableGeneratorESP()
    if esp.genAdd then esp.genAdd:Disconnect() esp.genAdd = nil end
    if esp.genRemove then esp.genRemove:Disconnect() esp.genRemove = nil end
    espClear(esp.generators)
end

local function enableBatteryESP()
    local ignore = workspace:FindFirstChild("IGNORE")
    if ignore then
        for _, v in ipairs(ignore:GetDescendants()) do
            if v:IsA("MeshPart") and v.Name == "Battery" then
                local h = newHighlight(v, Color3.fromRGB(255,0,255))
                if h then batteryHighlights[v] = h end
            end
        end
    end
    batteryConn = workspace.DescendantAdded:Connect(function(v)
        if v:IsA("MeshPart") and v.Name == "Battery" then
            local h = newHighlight(v, Color3.fromRGB(255,0,255))
            if h then batteryHighlights[v] = h end
        end
    end)
end
local function disableBatteryESP()
    if batteryConn then batteryConn:Disconnect() batteryConn = nil end
    for _, h in pairs(batteryHighlights) do pcall(function() h:Destroy() end) end
    batteryHighlights = {}
end

local function enableFuseESP()
    local gm = workspace.MAPS and workspace.MAPS:FindFirstChild("GAME MAP")
    local fb = gm and gm:FindFirstChild("FuseBoxes")
    if fb then
        for _, fuseBox in ipairs(fb:GetChildren()) do
            local battery = fuseBox:FindFirstChild("Battery")
            if battery then
                local h = newHighlight(battery, Color3.fromRGB(0,255,255))
                if h then fuseHighlights[battery] = h end
            end
        end
    end
    fuseConn = workspace.DescendantAdded:Connect(function(v)
        if v:IsA("BasePart") and v.Name == "Battery" and v.Parent and v.Parent.Name == "FuseBox" then
            task.wait(0.1)
            local h = newHighlight(v, Color3.fromRGB(0,255,255))
            if h then fuseHighlights[v] = h end
        end
    end)
end
local function disableFuseESP()
    if fuseConn then fuseConn:Disconnect() fuseConn = nil end
    for _, h in pairs(fuseHighlights) do pcall(function() h:Destroy() end) end
    fuseHighlights = {}
end

local function enableTrapESP()
    local ignore = workspace:FindFirstChild("IGNORE")
    if ignore then
        for _, obj in ipairs(ignore:GetChildren()) do
            if obj:IsA("Model") and obj.Name == "Trap" then
                local h = newHighlight(obj, Color3.fromRGB(255,100,0))
                if h then trapHighlights[obj] = h end
            end
        end
    end
    descendantConn = workspace.DescendantAdded:Connect(function(v)
        if v:IsA("Model") and v.Name == "Trap" then
            task.wait(0.1)
            local h = newHighlight(v, Color3.fromRGB(255,100,0))
            if h then trapHighlights[v] = h end
        end
    end)
end
local function disableTrapESP()
    if descendantConn then descendantConn:Disconnect() descendantConn = nil end
    for _, h in pairs(trapHighlights) do pcall(function() h:Destroy() end) end
    trapHighlights = {}
end

local function enableMinionESP()
    local ignore = workspace:FindFirstChild("IGNORE")
    if ignore then
        for _, obj in ipairs(ignore:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "Minion" then
                local h = newHighlight(obj, Color3.fromRGB(255,165,0))
                if h then minionHighlights[obj] = h end
            end
        end
    end
    minionConn = workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") and obj.Name == "Minion" then
            local h = newHighlight(obj, Color3.fromRGB(255,165,0))
            if h then minionHighlights[obj] = h end
        end
    end)
end
local function disableMinionESP()
    if minionConn then minionConn:Disconnect() minionConn = nil end
    for _, h in pairs(minionHighlights) do pcall(function() h:Destroy() end) end
    minionHighlights = {}
end

-- ================================================
-- APPLY SNAPSHOT
-- ================================================
local function applySnapshot(snap)
    if snap.infiniteSprint and not infiniteSprint then
        infiniteSprint = true
        sprintConn = RunService.Heartbeat:Connect(function()
            if not infiniteSprint then return end
            local char = LP.Character
            if not char then return end
            local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            char:SetAttribute("WalkSpeed", sprinting and 25 or 12)
        end)
    end
    if snap.jumpBoost and not jumpBoost then
        jumpBoost = true
        local char = LP.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then if hum.UseJumpPower then hum.JumpPower = 1.5 else hum.JumpHeight = 1.5 end end
        end
    end
    if snap.noclipEnabled and not noclipEnabled then
        noclipEnabled = true
        noclipConn = RunService.Stepped:Connect(function()
            if not noclipEnabled then return end
            local char = LP.Character
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end
    if snap.fullbright then
        local lighting = game:GetService("Lighting")
        oldLighting = { Brightness=lighting.Brightness, ClockTime=lighting.ClockTime, FogEnd=lighting.FogEnd, GlobalShadows=lighting.GlobalShadows, Ambient=lighting.Ambient }
        lighting.Brightness=5; lighting.ClockTime=14; lighting.FogEnd=100000
        lighting.GlobalShadows=false; lighting.Ambient=Color3.fromRGB(255,255,255)
    end
    if snap.autogen and not autogen then
        autogen = true
        genconn = RunService.Heartbeat:Connect(function()
            local gengui = LP.PlayerGui:FindFirstChild("Gen")
            if gengui then
                if not firingconn then
                    lastfiretime = tick()
                    firingconn = RunService.Heartbeat:Connect(function()
                        if not autogen then return end
                        local delay = genmode=="Blatant" and 0 or genmode=="Silent" and 7 or customdelay
                        if tick()-lastfiretime >= delay then
                            LP.PlayerGui.Gen.GeneratorMain.Event:FireServer({Wires=true,Switches=true,Lever=true})
                            lastfiretime = tick()
                        end
                    end)
                end
            else
                if firingconn then firingconn:Disconnect() firingconn = nil end
            end
        end)
    end
    if snap.autoParry then getgenv().AutoParryEnabled = true end
    if snap.antiDeath and not antiDeath.enabled then
        antiDeath.enabled = true
        antiDeath.conn = RunService.Heartbeat:Connect(function()
            local char = LP.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            if hum.Health < antiDeath.threshold and hum.Health > 0 and not antiDeath.teleported and not antiDeath.debounce then
                antiDeath.debounce = true; antiDeath.teleported = true
                antiDeath.lastPos = root.CFrame
                local pos = root.Position
                antiDeath.plate = Instance.new("Part")
                antiDeath.plate.Size = Vector3.new(50,1,50); antiDeath.plate.Anchored = true
                antiDeath.plate.Position = pos - Vector3.new(0,100,0)
                antiDeath.plate.Name = "AntiDeathPlate"; antiDeath.plate.Parent = workspace
                task.spawn(function() lerpMove(root, CFrame.new(pos - Vector3.new(0,95,0))) end)
                task.delay(1, function() antiDeath.debounce = false end)
            elseif hum.Health >= antiDeath.threshold and antiDeath.teleported and antiDeath.lastPos and not antiDeath.debounce then
                antiDeath.debounce = true
                returnToLastPos()
                task.delay(1, function() antiDeath.debounce = false end)
            end
        end)
    end
    if snap.survivorESP and not survivorESPOn then enableSurvivorESP() survivorESPOn = true end
    if snap.killerESP and not killerESPOn then enableKillerESP() killerESPOn = true end
    if snap.generatorESP and not generatorESPOn then enableGeneratorESP() generatorESPOn = true end
    if snap.batteryESP and not batteryESPOn then enableBatteryESP() batteryESPOn = true end
    if snap.fuseESP and not fuseESPOn then enableFuseESP() fuseESPOn = true end
    if snap.trapESP and not trapESPOn then enableTrapESP() trapESPOn = true end
    if snap.minionESP and not minionESPOn then enableMinionESP() minionESPOn = true end
end

-- ================================================
-- PANIC
-- ================================================
local function doPanic()
    pcall(function()
        local char = LP.Character
        infiniteSprint = false
        if sprintConn then sprintConn:Disconnect() sprintConn = nil end
        if char then
            char:SetAttribute("WalkSpeed", 12)
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = 12 end
        end
        jumpBoost = false
        if jpLoop then jpLoop:Disconnect() jpLoop = nil end
        if jpCA then jpCA:Disconnect() jpCA = nil end
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                if hum.UseJumpPower then hum.JumpPower = 0 else hum.JumpHeight = 0 end
            end
        end
        aimlockEnabled = false; lockedTarget = nil
        if inputConn then inputConn:Disconnect() inputConn = nil end
        if renderConn then renderConn:Disconnect() renderConn = nil end
        noclipEnabled = false
        if noclipConn then noclipConn:Disconnect() noclipConn = nil end
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
        local lighting = game:GetService("Lighting")
        if next(oldLighting) then
            lighting.Brightness=oldLighting.Brightness; lighting.ClockTime=oldLighting.ClockTime
            lighting.FogEnd=oldLighting.FogEnd; lighting.GlobalShadows=oldLighting.GlobalShadows
            lighting.Ambient=oldLighting.Ambient; oldLighting = {}
        end
        autogen = false
        if genconn then genconn:Disconnect() genconn = nil end
        if firingconn then firingconn:Disconnect() firingconn = nil end
        autoEscape = false
        if autoEscapeConn then autoEscapeConn:Disconnect() autoEscapeConn = nil end
        dotEnabled = false
        if dotConn then dotConn:Disconnect() dotConn = nil end
        instantInteract = false
        for _, conn in ipairs(promptConns) do pcall(function() conn:Disconnect() end) end
        promptConns = {}
        safeTeleport = false
        if safePart then safePart:Destroy() safePart = nil end
        viewKiller = false
        if killerAddedConn then killerAddedConn:Disconnect() killerAddedConn = nil end
        if killerRemovedConn then killerRemovedConn:Disconnect() killerRemovedConn = nil end
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
        getgenv().AutoParryEnabled = false
        antiDeath.enabled = false
        if antiDeath.conn then antiDeath.conn:Disconnect() antiDeath.conn = nil end
        if antiDeath.plate then antiDeath.plate:Destroy() antiDeath.plate = nil end
        antiDeath.teleported = false; antiDeath.lastPos = nil; antiDeath.debounce = false
        disableSurvivorESP(); disableKillerESP(); disableGeneratorESP()
        disableBatteryESP(); disableFuseESP(); disableTrapESP(); disableMinionESP()
        survivorESPOn=false; killerESPOn=false; generatorESPOn=false
        batteryESPOn=false; fuseESPOn=false; trapESPOn=false; minionESPOn=false
        allESPActive = false
        if pp and pp.Parent then pp:Destroy() end
    end)
pcall(function()
    TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Scale = 0
    }):Play()
    task.delay(0.25, function()
        guiFrame:Destroy()
    end)
end)
end

-- ================================================
-- TABS
-- ================================================
local MainSection_   = Window:TabSection({ text = "Main" })
local SurvSection_   = Window:TabSection({ text = "Survivor" })
local VisualSection_ = Window:TabSection({ text = "Visual" })
local UtilSection_   = Window:TabSection({ text = "Utility" })

local MainTab   = MainSection_:Tab({ text = "Main",     icon = "rbxassetid://7999345313" })
local SurvTab   = SurvSection_:Tab({ text = "Survivor", icon = "rbxassetid://7999345313" })
local VisualTab = VisualSection_:Tab({ text = "ESP",    icon = "rbxassetid://7999345313" })
local TPTab     = UtilSection_:Tab({ text = "Teleport", icon = "rbxassetid://7999345313" })
local ConfigTab = UtilSection_:Tab({ text = "Config",   icon = "rbxassetid://7999345313" })

-- ================================================
-- MAIN TAB
-- ================================================
local MovSection  = MainTab:Section({ text = "Movement" })
local CombSection = MainTab:Section({ text = "Combat" })

MovSection:Toggle({
    text = "Infinite Sprint", state = false,
    callback = function(s)
        infiniteSprint = s
        if s then
            sprintConn = RunService.Heartbeat:Connect(function()
                if not infiniteSprint then return end
                local char = LP.Character
                if not char then return end
                local pf = workspace:FindFirstChild("PLAYERS")
                if pf and pf:FindFirstChild("LOBBY") and char.Parent == pf.LOBBY then
                    char:SetAttribute("WalkSpeed", 12) return
                end
                if isMobile then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    char:SetAttribute("WalkSpeed", hum and hum.MoveDirection.Magnitude > 0 and 24 or 12)
                else
                    local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
                    char:SetAttribute("WalkSpeed", sprinting and 25 or 12)
                end
            end)
        else
            if sprintConn then sprintConn:Disconnect() sprintConn = nil end
            local char = LP.Character
            if char then
                char:SetAttribute("WalkSpeed", 12)
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = 12 end
            end
        end
    end
})

MovSection:Toggle({
    text = "Allow Jumping", state = false,
    callback = function(s)
        jumpBoost = s
        local function applyJump()
            local char = LP.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            if hum.UseJumpPower then hum.JumpPower = s and 1.5 or 0
            else hum.JumpHeight = s and 1.5 or 0 end
        end
        applyJump()
        if jpLoop then jpLoop:Disconnect() jpLoop = nil end
        if jpCA then jpCA:Disconnect() jpCA = nil end
        if s then
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then jpLoop = hum:GetPropertyChangedSignal("JumpPower"):Connect(applyJump) end
            jpCA = LP.CharacterAdded:Connect(function(c)
                local h = c:WaitForChild("Humanoid")
                applyJump()
                if jpLoop then jpLoop:Disconnect() end
                jpLoop = h:GetPropertyChangedSignal("JumpPower"):Connect(applyJump)
            end)
        end
    end
})

MovSection:Toggle({
    text = "Noclip", state = false,
    callback = function(s)
        noclipEnabled = s
        if s then
            noclipConn = RunService.Stepped:Connect(function()
                if not noclipEnabled then return end
                local char = LP.Character
                if not char then return end
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end)
        else
            if noclipConn then noclipConn:Disconnect() noclipConn = nil end
            local char = LP.Character
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = true end
                end
            end
        end
    end
})

MovSection:Toggle({
    text = "Full Bright", state = false,
    callback = function(s)
        local lighting = game:GetService("Lighting")
        if s then
            oldLighting = {
                Brightness=lighting.Brightness, ClockTime=lighting.ClockTime,
                FogEnd=lighting.FogEnd, GlobalShadows=lighting.GlobalShadows, Ambient=lighting.Ambient
            }
            lighting.Brightness=5; lighting.ClockTime=14; lighting.FogEnd=100000
            lighting.GlobalShadows=false; lighting.Ambient=Color3.fromRGB(255,255,255)
        else
            if next(oldLighting) then
                lighting.Brightness=oldLighting.Brightness; lighting.ClockTime=oldLighting.ClockTime
                lighting.FogEnd=oldLighting.FogEnd; lighting.GlobalShadows=oldLighting.GlobalShadows
                lighting.Ambient=oldLighting.Ambient
            end
        end
    end
})

CombSection:Toggle({
    text = "Aimlock", state = false,
    callback = function(s)
        aimlockEnabled = s
        if s then
            inputConn = UserInputService.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.KeyCode ~= aimlockBind then return end
                if lockedTarget then lockedTarget = nil return end
                local myTeam = getMyTeamFolder()
                if not myTeam then return end
                local myChar = LP.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if not myRoot then return end
                local closest, shortest = nil, math.huge
                local pf = workspace:FindFirstChild("PLAYERS")
                local targetFolder = pf and pf:FindFirstChild(myTeam == "ALIVE" and "KILLER" or "ALIVE")
                if not targetFolder then return end
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p.Character and p.Character.Parent == targetFolder then
                        local r = p.Character:FindFirstChild("HumanoidRootPart")
                        if r then
                            local d = (myRoot.Position - r.Position).Magnitude
                            if d < shortest then shortest = d closest = r end
                        end
                    end
                end
                if closest then lockedTarget = closest end
            end)
            renderConn = RunService.RenderStepped:Connect(function()
                if lockedTarget and lockedTarget.Parent then
                    camera.CFrame = CFrame.new(camera.CFrame.Position, lockedTarget.Position)
                else lockedTarget = nil end
            end)
        else
            lockedTarget = nil
            if inputConn then inputConn:Disconnect() inputConn = nil end
            if renderConn then renderConn:Disconnect() renderConn = nil end
        end
    end
})

CombSection:Keybind({
    text = "Aimlock Bind",
    default = Enum.KeyCode.Q,
    callback = function(key)
        aimlockBind = Enum.KeyCode[key] or Enum.KeyCode.Q
    end
})


-- ================================================
-- SURVIVOR TAB
-- ================================================
local GenSect   = SurvTab:Section({ text = "Generator" })
local SurvSect  = SurvTab:Section({ text = "Survival" })
local ParrySect = SurvTab:Section({ text = "Auto Parry" })
local ADSect    = SurvTab:Section({ text = "Anti Death" })

GenSect:Dropdown({
    text = "Generator Mode",
    list = {"Blatant", "Silent", "Custom"},
    default = "Blatant",
    callback = function(v) genmode = v end
})

GenSect:Textbox({
    text = "Custom Delay (s)",
    value = "3",
    callback = function(v) customdelay = math.max(0, tonumber(v) or 3) end
})

GenSect:Toggle({
    text = "Auto Generator", state = false,
    callback = function(v)
        autogen = v
        if v then
            genconn = RunService.Heartbeat:Connect(function()
                local gengui = LP.PlayerGui:FindFirstChild("Gen")
                if gengui then
                    if not firingconn then
                        lastfiretime = tick()
                        firingconn = RunService.Heartbeat:Connect(function()
                            if not autogen then return end
                            local delay = genmode=="Blatant" and 0 or genmode=="Silent" and 7 or customdelay
                            if tick()-lastfiretime >= delay then
                                LP.PlayerGui.Gen.GeneratorMain.Event:FireServer({Wires=true,Switches=true,Lever=true})
                                lastfiretime = tick()
                            end
                        end)
                    end
                else
                    if firingconn then firingconn:Disconnect() firingconn = nil end
                    lastfiretime = 0
                end
            end)
        else
            if genconn then genconn:Disconnect() genconn = nil end
            if firingconn then firingconn:Disconnect() firingconn = nil end
            lastfiretime = 0
        end
    end
})

SurvSect:Toggle({
    text = "Auto Escape", state = false,
    callback = function(s)
        autoEscape = s
        if s then
            local teleported = false
            autoEscapeConn = RunService.RenderStepped:Connect(function()
                if teleported or not autoEscape then return end
                local char = LP.Character
                if not char then return end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                if not pcall(function() return workspace.GAME.CAN_ESCAPE.Value end) then return end
                if not workspace.GAME.CAN_ESCAPE.Value then return end
                local pf = workspace:FindFirstChild("PLAYERS")
                if not pf or char.Parent ~= pf:FindFirstChild("ALIVE") then return end
                local gm = workspace.MAPS and workspace.MAPS:FindFirstChild("GAME MAP")
                if not gm then return end
                local escapes = gm:FindFirstChild("Escapes")
                if not escapes then return end
                for _, part in pairs(escapes:GetChildren()) do
                    if part:IsA("BasePart") and part:GetAttribute("Enabled") then
                        local hl = part:FindFirstChildOfClass("Highlight")
                        if hl and hl.Enabled then
                            teleported = true
                            root.Anchored = true
                            lerpMove(root, part.CFrame)
                            task.delay(0.5, function() if root then root.Anchored = false end end)
                            task.delay(10, function() teleported = false end)
                            return
                        end
                    end
                end
            end)
        else
            if autoEscapeConn then autoEscapeConn:Disconnect() autoEscapeConn = nil end
        end
    end
})

SurvSect:Toggle({
    text = "Auto Barricade", state = false,
    callback = function(s)
        dotEnabled = s
        if s then
            dotConn = RunService.RenderStepped:Connect(function()
                local dot = LP.PlayerGui:FindFirstChild("Dot")
                if dot and dot:IsA("ScreenGui") then
                    local container = dot:FindFirstChild("Container")
                    if container then
                        local frame = container:FindFirstChild("Frame")
                        if frame and frame:IsA("GuiObject") then
                            if not dot.Enabled then dot:Destroy() return end
                            frame.AnchorPoint = Vector2.new(0.5,0.5)
                            frame.Position = UDim2.new(0.5,0,0.5,0)
                        end
                    end
                end
            end)
        else
            if dotConn then dotConn:Disconnect() dotConn = nil end
        end
    end
})

SurvSect:Toggle({
    text = "Instant Interact", state = false,
    callback = function(v)
        instantInteract = v
        if v then
            local allowedAncestors = {
                "Generator",
                "Battery",
            }

            local function isAllowed(prompt)
                if not prompt:IsA("ProximityPrompt") then return false end
                for _, name in ipairs(allowedAncestors) do
                    if prompt:FindFirstAncestor(name) then return true end
                end
                return false
            end

            for _, obj in ipairs(workspace:GetDescendants()) do
                if isAllowed(obj) then obj.HoldDuration = 0 end
            end

            promptConns[#promptConns+1] = workspace.DescendantAdded:Connect(function(desc)
                if isAllowed(desc) then desc.HoldDuration = 0 end
            end)

        else
            for _, conn in ipairs(promptConns) do pcall(function() conn:Disconnect() end) end
            promptConns = {}
        end
    end
})

SurvSect:Toggle({
    text = "Safety Area", state = false,
    callback = function(s)
        safeTeleport = s
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        if s then
            local pos = root.Position
            safePart = Instance.new("Part")
            safePart.Size = Vector3.new(50,1,50); safePart.Anchored = true
            safePart.Position = pos - Vector3.new(0,100,0)
            safePart.Name = "SafetyPlate"; safePart.Parent = workspace
            task.spawn(function() lerpMove(root, CFrame.new(pos - Vector3.new(0,95,0))) end)
        else
            local pos = root.Position
            if safePart then safePart:Destroy() safePart = nil end
            task.spawn(function() lerpMove(root, CFrame.new(pos + Vector3.new(0,100,0))) end)
        end
    end
})

SurvSect:Toggle({
    text = "View Killer", state = false,
    callback = function(s)
        viewKiller = s
        if s then
            local function setKillerCam(kc)
                local hum = kc:FindFirstChildOfClass("Humanoid")
                if hum then camera.CameraSubject = hum end
            end
            local pf = workspace:FindFirstChild("PLAYERS")
            local kf = pf and pf:FindFirstChild("KILLER")
            if kf then
                local cur = kf:GetChildren()[1]
                if cur then setKillerCam(cur) end
                killerAddedConn = kf.ChildAdded:Connect(setKillerCam)
                killerRemovedConn = kf.ChildRemoved:Connect(function()
                    if viewKiller then
                        local char = LP.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if hum then camera.CameraSubject = hum end
                    end
                end)
            end
        else
            if killerAddedConn then killerAddedConn:Disconnect() killerAddedConn = nil end
            if killerRemovedConn then killerRemovedConn:Disconnect() killerRemovedConn = nil end
            local char = LP.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
    end
})

getgenv().AutoParryEnabled = false

ParrySect:Toggle({
    text = "Auto Parry", state = false,
    callback = function(v)
        getgenv().AutoParryEnabled = v

        local attack = {
            "rbxassetid://106673226682917",
            "rbxassetid://112503015929213",
            "rbxassetid://120428956410756",
            "rbxassetid://133752270724243",
        }

        local watchedPlayers = {}
        local watchedAnimators = {}
        local pollConn = nil
        local heartbeatConn = nil
        local lastParryTime = 0
        local PARRY_COOLDOWN = 0.3

        local function fireParry()
            local now = tick()
            if now - lastParryTime < PARRY_COOLDOWN then return end
            lastParryTime = now
            pcall(function()
                local args = {
                    buffer.fromstring("\a"),
                    buffer.fromstring("\254\001\000\254\002\000\006\aAbility\001\002")
                }
                game:GetService("ReplicatedStorage")
                    :WaitForChild("Modules"):WaitForChild("Warp")
                    :WaitForChild("Index"):WaitForChild("Event")
                    :WaitForChild("Reliable"):FireServer(unpack(args))
            end)
        end

        local function isAttackAnim(id)
            for _, aid in ipairs(attack) do if id == aid then return true end end
            return false
        end

        local function getRange(id)
            if id == "rbxassetid://133752270724243" then return getgenv().PullAttackRange or 50 end
            return getgenv().BasicAttackRange or 30
        end

        local function checkDistance(killerChar)
            local myChar = LP.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local kRoot = killerChar and killerChar:FindFirstChild("HumanoidRootPart")
            if not myRoot or not kRoot then return false, nil end
            return true, (myRoot.Position - kRoot.Position).Magnitude
        end

        local function watchAnimator(animator, killerChar)
            if not animator or watchedAnimators[animator] then return end
            watchedAnimators[animator] = true

            -- hook: fires the instant animation starts
            animator.AnimationPlayed:Connect(function(track)
                if not getgenv().AutoParryEnabled then return end
                if not isAttackAnim(track.Animation.AnimationId) then return end

                local ok, dist = checkDistance(killerChar)
                if not ok then return end
                local range = getRange(track.Animation.AnimationId)
                if dist > range then return end

                -- fire immediately
                fireParry()

                -- fire again at a few intervals during the animation window
                -- in case the first one gets dropped
                for _, delay in ipairs({0.05, 0.1, 0.15}) do
                    task.delay(delay, function()
                        if not getgenv().AutoParryEnabled then return end
                        if not track.IsPlaying then return end
                        local ok2, dist2 = checkDistance(killerChar)
                        if not ok2 or dist2 > range then return end
                        fireParry()
                    end)
                end
            end)
        end

        local function watchPlayer(p)
            if watchedPlayers[p] then return end
            watchedPlayers[p] = true

            local function tryWatch(char)
                if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if not hum then return end
                local animator = hum:FindFirstChildOfClass("Animator")
                if animator then
                    watchAnimator(animator, char)
                end
                -- also watch for animator being added later
                hum.ChildAdded:Connect(function(c)
                    if c:IsA("Animator") then watchAnimator(c, char) end
                end)
            end

            if p.Character then tryWatch(p.Character) end
            p.CharacterAdded:Connect(tryWatch)
        end

        -- heartbeat backup — catches anything the animation hook misses
        local function startHeartbeat()
            heartbeatConn = RunService.Heartbeat:Connect(function()
                if not getgenv().AutoParryEnabled then return end
                local myChar = LP.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if not myRoot then return end

                local pf = workspace:FindFirstChild("PLAYERS")
                local kf = pf and pf:FindFirstChild("KILLER")
                if not kf then return end

                for _, char in ipairs(kf:GetChildren()) do
                    local kRoot = char:FindFirstChild("HumanoidRootPart")
                    if not kRoot then continue end
                    local dist = (myRoot.Position - kRoot.Position).Magnitude
                    if dist > (getgenv().BasicAttackRange or 30) then continue end

                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if not hum then continue end
                    local animator = hum:FindFirstChildOfClass("Animator")
                    if not animator then continue end

                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        if not track.IsPlaying then continue end
                        if not isAttackAnim(track.Animation.AnimationId) then continue end
                        local range = getRange(track.Animation.AnimationId)
                        if dist > range then continue end
                        fireParry()
                        break
                    end
                end
            end)
        end

        local function startWatching()
            local pf = workspace:FindFirstChild("PLAYERS")
            local kf = pf and pf:FindFirstChild("KILLER")
            if kf then
                for _, char in ipairs(kf:GetChildren()) do
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Character == char then watchPlayer(p) end
                    end
                end
                kf.ChildAdded:Connect(function(char)
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Character == char then watchPlayer(p) end
                    end
                end)
            else
                pollConn = RunService.Heartbeat:Connect(function()
                    local pf2 = workspace:FindFirstChild("PLAYERS")
                    local kf2 = pf2 and pf2:FindFirstChild("KILLER")
                    if kf2 then
                        pollConn:Disconnect(); pollConn = nil
                        for _, char in ipairs(kf2:GetChildren()) do
                            for _, p in ipairs(Players:GetPlayers()) do
                                if p.Character == char then watchPlayer(p) end
                            end
                        end
                        kf2.ChildAdded:Connect(function(char)
                            for _, p in ipairs(Players:GetPlayers()) do
                                if p.Character == char then watchPlayer(p) end
                            end
                        end)
                    end
                end)
            end
            startHeartbeat()
        end

        if v then
            startWatching()
        else
            watchedPlayers = {}
            watchedAnimators = {}
            if pollConn then pollConn:Disconnect() pollConn = nil end
            if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
        end
    end
})

ParrySect:Slider({
    text = "Main Attack Range", min = 10, max = 35, float = 1,
    callback = function(v) getgenv().BasicAttackRange = v end
})

ParrySect:Slider({
    text = "Ennard Pull Range", min = 10, max = 60, float = 1,
    callback = function(v) getgenv().PullAttackRange = v end
})

ADSect:Toggle({
    text = "Anti Death", state = false,
    callback = function(s)
        antiDeath.enabled = s
        if s then
            antiDeath.conn = RunService.Heartbeat:Connect(function()
                local char = LP.Character
                if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if not hum then return end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                if hum.Health < antiDeath.threshold and hum.Health > 0 and not antiDeath.teleported and not antiDeath.debounce then
                    antiDeath.debounce = true; antiDeath.teleported = true
                    antiDeath.lastPos = root.CFrame
                    local pos = root.Position
                    antiDeath.plate = Instance.new("Part")
                    antiDeath.plate.Size = Vector3.new(50,1,50); antiDeath.plate.Anchored = true
                    antiDeath.plate.Position = pos - Vector3.new(0,100,0)
                    antiDeath.plate.Name = "AntiDeathPlate"; antiDeath.plate.Parent = workspace
                    task.spawn(function() lerpMove(root, CFrame.new(pos - Vector3.new(0,95,0))) end)
                    task.delay(1, function() antiDeath.debounce = false end)
                elseif hum.Health >= antiDeath.threshold and antiDeath.teleported and antiDeath.lastPos and not antiDeath.debounce then
                    antiDeath.debounce = true
                    returnToLastPos()
                    task.delay(1, function() antiDeath.debounce = false end)
                end
            end)
        else
            if antiDeath.conn then antiDeath.conn:Disconnect() antiDeath.conn = nil end
            if antiDeath.teleported then returnToLastPos() end
            antiDeath.debounce = false
        end
    end
})

ADSect:Slider({
    text = "Health Threshold", min = 25, max = 80, float = 0.5,
    callback = function(v) antiDeath.threshold = v end
})

-- ================================================
-- VISUAL TAB
-- ================================================
local ESPSettingsSect = VisualTab:Section({ text = "Settings" })
local ESPTogglesSect  = VisualTab:Section({ text = "Toggles" })

ESPSettingsSect:Dropdown({
    text = "ESP Method",
    list = {"Highlight", "Drawing", "Dual"},
    default = "Highlight",
    callback = function(sel) espMethod = sel end
})

ESPTogglesSect:Button({
    text = "Toggle All ESP",
    callback = function()
        allESPActive = not allESPActive
        if allESPActive then
            enableSurvivorESP(); enableKillerESP(); enableGeneratorESP()
            enableBatteryESP(); enableFuseESP(); enableTrapESP(); enableMinionESP()
            survivorESPOn=true; killerESPOn=true; generatorESPOn=true
            batteryESPOn=true; fuseESPOn=true; trapESPOn=true; minionESPOn=true
        else
            disableSurvivorESP(); disableKillerESP(); disableGeneratorESP()
            disableBatteryESP(); disableFuseESP(); disableTrapESP(); disableMinionESP()
            survivorESPOn=false; killerESPOn=false; generatorESPOn=false
            batteryESPOn=false; fuseESPOn=false; trapESPOn=false; minionESPOn=false
        end
    end
})

ESPTogglesSect:Toggle({
    text = "Survivor ESP", state = false,
    callback = function(s)
        survivorESPOn = s
        if s then enableSurvivorESP() else disableSurvivorESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Killer ESP", state = false,
    callback = function(s)
        killerESPOn = s
        if s then enableKillerESP() else disableKillerESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Generator ESP", state = false,
    callback = function(s)
        generatorESPOn = s
        if s then enableGeneratorESP() else disableGeneratorESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Battery ESP", state = false,
    callback = function(s)
        batteryESPOn = s
        if s then enableBatteryESP() else disableBatteryESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Fuse Box ESP", state = false,
    callback = function(s)
        fuseESPOn = s
        if s then enableFuseESP() else disableFuseESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Bear Trap ESP", state = false,
    callback = function(s)
        trapESPOn = s
        if s then enableTrapESP() else disableTrapESP() end
    end
})

ESPTogglesSect:Toggle({
    text = "Minion ESP", state = false,
    callback = function(s)
        minionESPOn = s
        if s then enableMinionESP() else disableMinionESP() end
    end
})

-- ================================================
-- TELEPORT TAB
-- ================================================
local TPSect = TPTab:Section({ text = "Teleport" })

local function getOrderedGenerators()
    local gm = workspace.MAPS and workspace.MAPS:FindFirstChild("GAME MAP")
    local gens = gm and gm:FindFirstChild("Generators")
    if not gens then return {} end
    local models = {}
    for _, v in ipairs(gens:GetChildren()) do if v:IsA("Model") then table.insert(models,v) end end
    table.sort(models, function(a,b) return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0) end)
    return models
end

local generatorIndex = 1
TPSect:Button({
    text = "Generator TP",
    callback = function()
        local models = getOrderedGenerators()
        if #models == 0 then notify("Error","Wait for match to start.") return end
        local part = models[generatorIndex].PrimaryPart or models[generatorIndex]:FindFirstChildWhichIsA("BasePart")
        if part then lerpTo(part.CFrame * CFrame.new(0,0,-5)) end
        generatorIndex = generatorIndex % #models + 1
    end
})

local batteryIndex = 1
TPSect:Button({
    text = "Battery TP",
    callback = function()
        local ignore = workspace:FindFirstChild("IGNORE")
        if not ignore then notify("Error","No batteries found.") return end
        local batteries = {}
        for _, v in ipairs(ignore:GetDescendants()) do
            if v:IsA("MeshPart") and v.Name == "Battery" then table.insert(batteries,v) end
        end
        if #batteries == 0 then notify("Error","No batteries found.") return end
        lerpTo(batteries[batteryIndex].CFrame * CFrame.new(0,3,0))
        batteryIndex = batteryIndex % #batteries + 1
    end
})

local fuseIndex = 1
TPSect:Button({
    text = "Fuse Box TP",
    callback = function()
        local gm = workspace.MAPS and workspace.MAPS:FindFirstChild("GAME MAP")
        local fb = gm and gm:FindFirstChild("FuseBoxes")
        if not fb then notify("Error","No fuse boxes found.") return end
        local batteries = {}
        for _, fuseBox in ipairs(fb:GetChildren()) do
            local b = fuseBox:FindFirstChild("Battery")
            if b then table.insert(batteries,b) end
        end
        if #batteries == 0 then notify("Error","No fuse boxes found.") return end
        lerpTo(batteries[fuseIndex].CFrame * CFrame.new(0,3,0))
        fuseIndex = fuseIndex % #batteries + 1
    end
})

-- ================================================
-- CONFIG TAB
-- ================================================
local ConfigSect       = ConfigTab:Section({ text = "GUI" })
local PlayerConfigSect = ConfigTab:Section({ text = "Player Configs" })

ConfigSect:Toggle({
    text = "Auto Load My Config",
    state = autoLoad,
    callback = function(s)
        autoLoad = s
        saveConfigsToFile()
        if s then
            local mySnap = playerConfigs[LP.Name:lower()]
            if mySnap then applySnapshot(mySnap) end
        end
    end
})

ConfigSect:Button({
    text = "Kill Switch",
    callback = function() doPanic() end
})

local pendingName = ""

PlayerConfigSect:Textbox({
    text = "Player Name",
    value = "",
    callback = function(v) pendingName = v:gsub("%s+", "") end
})

PlayerConfigSect:Button({
    text = "Save Current Settings",
    callback = function()
        local name = pendingName ~= "" and pendingName or LP.Name
        playerConfigs[name:lower()] = {
            infiniteSprint  = infiniteSprint,
            jumpBoost       = jumpBoost,
            noclipEnabled   = noclipEnabled,
            fullbright      = next(oldLighting) ~= nil,
            autogen         = autogen,
            autoEscape      = autoEscape,
            dotEnabled      = dotEnabled,
            instantInteract = instantInteract,
            safeTeleport    = safeTeleport,
            viewKiller      = viewKiller,
            autoParry       = getgenv().AutoParryEnabled,
            antiDeath       = antiDeath.enabled,
            survivorESP     = survivorESPOn,
            killerESP       = killerESPOn,
            generatorESP    = generatorESPOn,
            batteryESP      = batteryESPOn,
            fuseESP         = fuseESPOn,
            trapESP         = trapESPOn,
            minionESP       = minionESPOn,
        }
        saveConfigsToFile()
        notify("Config", "Saved for: " .. name)
    end
})

PlayerConfigSect:Button({
    text = "List Configs",
    callback = function()
        local names = {}
        for name in pairs(playerConfigs) do table.insert(names, name) end
        if #names == 0 then
            notify("Configs", "None saved.")
        else
            local chunk = ""
            for i, name in ipairs(names) do
                chunk = chunk .. name
                if i < #names then chunk = chunk .. ", " end
                if #chunk > 80 then
                    notify("Configs", chunk)
                    chunk = ""
                end
            end
            if chunk ~= "" then notify("Configs", chunk) end
        end
    end
})

PlayerConfigSect:Button({
    text = "Delete Config for Player",
    callback = function()
        local name = pendingName ~= "" and pendingName or LP.Name
        if playerConfigs[name:lower()] then
            playerConfigs[name:lower()] = nil
            saveConfigsToFile()
            notify("Config", "Deleted: " .. name)
        else
            notify("Config", "No config found for: " .. name)
        end
    end
})

PlayerConfigSect:Button({
    text = "Clear All Configs",
    callback = function()
        playerConfigs = {}
        saveConfigsToFile()
        notify("Config", "Cleared.")
    end
})

-- ================================================
-- PLAYER CONFIG AUTO APPLY
-- ================================================
local function checkAndApply(p)
    local snap = playerConfigs[p.Name:lower()]
    if snap then
        notify("Config", "Applying config for: " .. p.Name)
        task.wait(1)
        applySnapshot(snap)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then checkAndApply(p) end
end

Players.PlayerAdded:Connect(function(p)
    checkAndApply(p)
end)

-- auto load your own config on startup
if autoLoad then
    local mySnap = playerConfigs[LP.Name:lower()]
    if mySnap then
        task.wait(1)
        applySnapshot(mySnap)
    end
end
