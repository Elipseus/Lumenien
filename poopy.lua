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
