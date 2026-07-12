--[[
    Minimal UI Library  (Mercury-style)
    - Dark, minimalistic theme, smooth animations (Quint InOut), drag & drop
    - Safe tweens (protected against nil / destroyed instances)
    - Minimize into header (top stays fixed) / full hide / close-confirm

    - Made by polosa__
]]

local TweenService     = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local CoreGui          = game:GetService("CoreGui")
local Players          = game:GetService("Players")

local Library = {}
Library.__index = Library

--// THEME
local Theme = {
    Background   = Color3.fromRGB(18, 18, 20),
    Sidebar      = Color3.fromRGB(24, 24, 27),
    Element      = Color3.fromRGB(30, 30, 34),
    ElementHover = Color3.fromRGB(38, 38, 43),
    Stroke       = Color3.fromRGB(45, 45, 50),
    Accent       = Color3.fromRGB(120, 130, 255),
    Text         = Color3.fromRGB(235, 235, 240),
    SubText      = Color3.fromRGB(140, 140, 150),
    Danger       = Color3.fromRGB(200, 60, 60),
    Discord      = Color3.fromRGB(88, 101, 242),
}

--// Default icons (rbxassetid). Переопределяются через config.Icons
local DefaultIcons = {
    Minimize = "rbxassetid://10734896206",
    Close    = "rbxassetid://10747384394",
    Restore  = "rbxassetid://10734886735",
}

--// Smooth animation preset
local SMOOTH_STYLE = Enum.EasingStyle.Quint
local SMOOTH_DIR   = Enum.EasingDirection.InOut
local SMOOTH_TIME  = 0.4

--// Utils
local function alive(obj)
    return typeof(obj) == "Instance" and (obj.Parent ~= nil or obj:IsDescendantOf(game))
end

local function tween(obj, time, props, style, dir)
    if not alive(obj) then return end
    local ok, t = pcall(function()
        return TweenService:Create(
            obj,
            TweenInfo.new(time, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out),
            props
        )
    end)
    if ok and t then t:Play() return t end
end

local function resolveIcon(icon)
    if not icon then return "" end
    if type(icon) == "number" then
        return "rbxassetid://" .. icon
    end
    icon = tostring(icon)
    if icon:match("^rbxassetid://") or icon:match("^rbxthumb://") or icon:match("^http") then
        return icon
    end
    local loader = rawget(getfenv(), "getcustomasset") or rawget(getfenv(), "getsynasset")
    if loader then
        local ok, res = pcall(loader, icon)
        if ok and res then return res end
    end
    return icon
end

-- Copy text to clipboard (executor-safe)
local function copyText(str)
    local fn = rawget(getfenv(), "setclipboard")
        or rawget(getfenv(), "toclipboard")
        or rawget(getfenv(), "set_clipboard")
        or (syn and syn.write_clipboard)
    if fn then
        local ok = pcall(fn, tostring(str))
        return ok
    end
    return false
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Stroke
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function padding(parent, all)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, all)
    p.PaddingBottom = UDim.new(0, all)
    p.PaddingLeft   = UDim.new(0, all)
    p.PaddingRight  = UDim.new(0, all)
    p.Parent = parent
    return p
end

--// Window dragging
local function makeDraggable(frame, handle)
    local dragging, dragInput, startPos, startFramePos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = input.Position
            startFramePos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            if not alive(frame) then dragging = false return end
            local delta = input.Position - startPos
            frame.Position = UDim2.new(
                startFramePos.X.Scale, startFramePos.X.Offset + delta.X,
                startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y
            )
        end
    end)
end

--============================================================
--  CREATE WINDOW
--============================================================
function Library:Create(config)
    config = config or {}
    local window = setmetatable({}, Library)
    window.Tabs = {}
    window.Visible = true
    window.Minimized = false

    local icons = {}
    for k, v in pairs(DefaultIcons) do icons[k] = v end
    if config.Icons then
        for k, v in pairs(config.Icons) do icons[k] = v end
    end

    -- Remove any previous instance
    pcall(function()
        local old = CoreGui:FindFirstChild("MinimalUI")
        if old then old:Destroy() end
    end)
    local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild("MinimalUI") then
        pg.MinimalUI:Destroy()
    end

    -- Root GUI
    local gui = Instance.new("ScreenGui")
    gui.Name = "MinimalUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end
    window.Gui = gui

    -- Main window
    local size = config.Size or UDim2.fromOffset(600, 400)
    window.WindowSize = size

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.fromOffset(0, 0)
    main.Position = UDim2.new(0.5, 0, 0.5, -size.Y.Offset/2)
    main.AnchorPoint = Vector2.new(0.5, 0)   -- верх фиксирован
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui
    corner(main, 12)
    stroke(main, Theme.Stroke, 1)

    tween(main, 0.35, {Size = size}, SMOOTH_STYLE, SMOOTH_DIR)

    -- Topbar
    local topbar = Instance.new("Frame")
    topbar.Name = "Topbar"
    topbar.Size = UDim2.new(1, 0, 0, 42)
    topbar.BackgroundColor3 = Theme.Sidebar
    topbar.BorderSizePixel = 0
    topbar.Parent = main
    corner(topbar, 12)

    local topFix = Instance.new("Frame")
    topFix.Size = UDim2.new(1, 0, 0, 12)
    topFix.Position = UDim2.new(0, 0, 1, -12)
    topFix.BackgroundColor3 = Theme.Sidebar
    topFix.BorderSizePixel = 0
    topFix.Parent = topbar

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -120, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamMedium
    title.Text = config.Name or "Minimal UI"
    title.TextColor3 = Theme.Text
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = topbar

    makeDraggable(main, topbar)

    local function makeIconButton(iconId, xOffset, hoverColor)
        local b = Instance.new("ImageButton")
        b.Size = UDim2.fromOffset(28, 28)
        b.Position = UDim2.new(1, xOffset, 0.5, 0)
        b.AnchorPoint = Vector2.new(0, 0.5)
        b.BackgroundColor3 = Theme.Element
        b.AutoButtonColor = false
        b.Image = resolveIcon(iconId)
        b.ImageColor3 = Theme.SubText
        b.ScaleType = Enum.ScaleType.Fit
        b.Parent = topbar
        corner(b, 6)
        local ic = Instance.new("UIPadding")
        ic.PaddingTop = UDim.new(0,7); ic.PaddingBottom = UDim.new(0,7)
        ic.PaddingLeft = UDim.new(0,7); ic.PaddingRight = UDim.new(0,7)
        ic.Parent = b
        b.MouseEnter:Connect(function()
            tween(b, .15, {BackgroundColor3 = hoverColor, ImageColor3 = Theme.Text})
        end)
        b.MouseLeave:Connect(function()
            tween(b, .15, {BackgroundColor3 = Theme.Element, ImageColor3 = Theme.SubText})
        end)
        return b
    end

    -- Close button -> confirm dialog
    local closeBtn = makeIconButton(icons.Close, -36, Theme.Danger)
    closeBtn.MouseButton1Click:Connect(function()
        window:Confirm{
            Title = "Close menu?",
            Text = "Are you sure you want to close the UI?",
            ConfirmText = "Close",
            CancelText = "Cancel",
            OnConfirm = function()
                local t = tween(main, SMOOTH_TIME, {Size = UDim2.fromOffset(0,0)}, SMOOTH_STYLE, SMOOTH_DIR)
                if t then t.Completed:Wait() end
                if alive(gui) then gui:Destroy() end
            end
        }
    end)

    -- Minimize button -> collapse into header
    local minBtn = makeIconButton(icons.Minimize, -70, Theme.ElementHover)
    window.MinimizeButton = minBtn
    window.MinimizeIcon = icons.Minimize
    window.RestoreIcon  = icons.Restore
    minBtn.MouseButton1Click:Connect(function()
        window:ToggleMinimize()
    end)

    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 150, 1, -42)
    sidebar.Position = UDim2.new(0, 0, 0, 42)
    sidebar.BackgroundColor3 = Theme.Sidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main

    local tabList = Instance.new("ScrollingFrame")
    tabList.Size = UDim2.new(1, 0, 1, 0)
    tabList.BackgroundTransparency = 1
    tabList.BorderSizePixel = 0
    tabList.ScrollBarThickness = 0
    tabList.CanvasSize = UDim2.new(0,0,0,0)
    tabList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tabList.Parent = sidebar
    padding(tabList, 10)
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.Padding = UDim.new(0, 6)
    tabLayout.Parent = tabList

    -- Content container
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, -150, 1, -42)
    container.Position = UDim2.new(0, 150, 0, 42)
    container.BackgroundTransparency = 1
    container.Parent = main

    window.Container = container
    window.TabList = tabList
    window.Main = main
    window.Body = { sidebar, container }

    -- Toggle key: press to hide / show whole UI
    window.ToggleKey = config.ToggleKey or Enum.KeyCode.RightControl
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not alive(main) then return end
        if input.KeyCode == window.ToggleKey then
            window:Toggle()
        end
    end)

    return window
end

--============================================================
--  SHOW / HIDE (полностью прячет UI)
--============================================================
function Library:Toggle()
    if not alive(self.Main) then return end
    self.Visible = not self.Visible
    if self.Visible then
        self.Main.Visible = true
        local target = self.Minimized
            and UDim2.new(self.WindowSize.X.Scale, self.WindowSize.X.Offset, 0, 42)
            or self.WindowSize
        tween(self.Main, SMOOTH_TIME, {Size = target}, SMOOTH_STYLE, SMOOTH_DIR)
    else
        local t = tween(self.Main, SMOOTH_TIME, {Size = UDim2.fromOffset(0, 0)}, SMOOTH_STYLE, SMOOTH_DIR)
        if t then
            t.Completed:Connect(function()
                if (not self.Visible) and alive(self.Main) then
                    self.Main.Visible = false
                end
            end)
        else
            self.Main.Visible = false
        end
    end
end

function Library:Show() if not self.Visible then self:Toggle() end end
function Library:Hide() if self.Visible then self:Toggle() end end

--============================================================
--  MINIMIZE / RESTORE (сворачивает в шапку, верх фиксирован)
--============================================================
function Library:ToggleMinimize()
    if not alive(self.Main) then return end
    self.Minimized = not self.Minimized
    if self.Minimized then
        for _, obj in ipairs(self.Body) do
            if alive(obj) then obj.Visible = false end
        end
        tween(self.Main, SMOOTH_TIME, {
            Size = UDim2.new(self.WindowSize.X.Scale, self.WindowSize.X.Offset, 0, 42)
        }, SMOOTH_STYLE, SMOOTH_DIR)
        if alive(self.MinimizeButton) then
            self.MinimizeButton.Image = resolveIcon(self.RestoreIcon)
        end
    else
        for _, obj in ipairs(self.Body) do
            if alive(obj) then obj.Visible = true end
        end
        tween(self.Main, SMOOTH_TIME, {Size = self.WindowSize}, SMOOTH_STYLE, SMOOTH_DIR)
        if alive(self.MinimizeButton) then
            self.MinimizeButton.Image = resolveIcon(self.MinimizeIcon)
        end
    end
end

--============================================================
--  CONFIRM DIALOG
--============================================================
function Library:Confirm(opts)
    opts = opts or {}
    if not alive(self.Gui) then return end

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 1
    overlay.ZIndex = 100
    overlay.Parent = self.Gui
    tween(overlay, .2, {BackgroundTransparency = 0.5})

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(300, 150)
    box.Position = UDim2.new(0.5, 0, 0.5, 0)
    box.AnchorPoint = Vector2.new(0.5, 0.5)
    box.BackgroundColor3 = Theme.Background
    box.BackgroundTransparency = 1
    box.ZIndex = 101
    box.Parent = overlay
    corner(box, 12)
    stroke(box, Theme.Stroke, 1)
    tween(box, .25, {BackgroundTransparency = 0}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -32, 0, 24)
    title.Position = UDim2.new(0, 16, 0, 18)
    title.BackgroundTransparency = 1
    title.Text = opts.Title or "Are you sure?"
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = box

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -32, 0, 40)
    desc.Position = UDim2.new(0, 16, 0, 48)
    desc.BackgroundTransparency = 1
    desc.Text = opts.Text or ""
    desc.TextColor3 = Theme.SubText
    desc.Font = Enum.Font.Gotham
    desc.TextSize = 13
    desc.TextWrapped = true
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.TextYAlignment = Enum.TextYAlignment.Top
    desc.ZIndex = 102
    desc.Parent = box

    local function close()
        local t = tween(overlay, .2, {BackgroundTransparency = 1})
        tween(box, .2, {BackgroundTransparency = 1})
        if t then
            t.Completed:Connect(function() if alive(overlay) then overlay:Destroy() end end)
        elseif alive(overlay) then
            overlay:Destroy()
        end
    end

    local function makeBtn(text, xScale, danger, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -22, 0, 34)
        b.Position = UDim2.new(xScale, xScale == 0 and 16 or 6, 1, -50)
        b.BackgroundColor3 = danger and Theme.Danger or Theme.Element
        b.Text = text
        b.TextColor3 = Theme.Text
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 14
        b.AutoButtonColor = false
        b.ZIndex = 102
        b.Parent = box
        corner(b, 8)
        b.MouseButton1Click:Connect(function()
            close()
            if cb then cb() end
        end)
        return b
    end

    makeBtn(opts.CancelText or "Cancel", 0, false, opts.OnCancel)
    makeBtn(opts.ConfirmText or "Confirm", 0.5, true, opts.OnConfirm)
end

--============================================================
--  NOTIFICATIONS
--============================================================
function Library:Notification(cfg)
    cfg = cfg or {}
    local gui = self.Gui
    if not alive(gui) then return end

    local holder = gui:FindFirstChild("NotifHolder")
    if not holder then
        holder = Instance.new("Frame")
        holder.Name = "NotifHolder"
        holder.Size = UDim2.new(0, 300, 1, -20)
        holder.Position = UDim2.new(1, -310, 0, 10)
        holder.BackgroundTransparency = 1
        holder.ZIndex = 90
        holder.Parent = gui
        local l = Instance.new("UIListLayout")
        l.VerticalAlignment = Enum.VerticalAlignment.Bottom
        l.HorizontalAlignment = Enum.HorizontalAlignment.Right
        l.Padding = UDim.new(0, 8)
        l.Parent = holder
    end

    local notif = Instance.new("Frame")
    notif.Size = UDim2.new(0, 300, 0, 0)
    notif.BackgroundColor3 = Theme.Element
    notif.BorderSizePixel = 0
    notif.ClipsDescendants = true
    notif.ZIndex = 91
    notif.Parent = holder
    corner(notif, 8)
    stroke(notif, Theme.Stroke, 1)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 20)
    title.Position = UDim2.new(0, 12, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = cfg.Title or "Notification"
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 92
    title.Parent = notif

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -20, 0, 30)
    text.Position = UDim2.new(0, 12, 0, 30)
    text.BackgroundTransparency = 1
    text.Text = cfg.Text or ""
    text.TextColor3 = Theme.SubText
    text.Font = Enum.Font.Gotham
    text.TextSize = 12
    text.TextWrapped = true
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextYAlignment = Enum.TextYAlignment.Top
    text.ZIndex = 92
    text.Parent = notif

    tween(notif, .3, {Size = UDim2.new(0, 300, 0, 70)})
    task.delay(cfg.Duration or 3, function()
        local t = tween(notif, .3, {Size = UDim2.new(0, 300, 0, 0)})
        if t then t.Completed:Wait() end
        if alive(notif) then notif:Destroy() end
    end)
end

--============================================================
--  TAB
--============================================================
function Library:Tab(config)
    config = config or {}
    local tab = {}
    local win = self   -- ссылка на окно (для уведомлений из элементов)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Theme.Element
    btn.BackgroundTransparency = 1
    btn.Text = "  " .. (config.Name or "Tab")
    btn.TextColor3 = Theme.SubText
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 14
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.Parent = self.TabList
    corner(btn, 7)

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Theme.Stroke
    page.CanvasSize = UDim2.new(0,0,0,0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = self.Container
    padding(page, 14)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.Parent = page

    tab.Button = btn
    tab.Page = page

    local function activate()
        for _, t in pairs(self.Tabs) do
            if t.Page then t.Page.Visible = false end
            if t.Button then
                tween(t.Button, .15, {BackgroundTransparency = 1, TextColor3 = Theme.SubText})
            end
        end
        page.Visible = true
        tween(btn, .15, {BackgroundTransparency = 0, BackgroundColor3 = Theme.Element, TextColor3 = Theme.Text})
    end

    btn.MouseButton1Click:Connect(activate)
    btn.MouseEnter:Connect(function()
        if not page.Visible then tween(btn, .15, {TextColor3 = Theme.Text}) end
    end)
    btn.MouseLeave:Connect(function()
        if not page.Visible then tween(btn, .15, {TextColor3 = Theme.SubText}) end
    end)

    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then activate() end

    local function baseElement(height)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, height or 40)
        f.BackgroundColor3 = Theme.Element
        f.BorderSizePixel = 0
        f.Parent = page
        corner(f, 8)
        stroke(f, Theme.Stroke, 1)
        return f
    end

    --// BUTTON
    function tab:Button(cfg)
        cfg = cfg or {}
        local f = baseElement(40)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.Text = cfg.Name or "Button"
        b.TextColor3 = Theme.Text
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 14
        b.Parent = f
        b.MouseEnter:Connect(function() tween(f, .15, {BackgroundColor3 = Theme.ElementHover}) end)
        b.MouseLeave:Connect(function() tween(f, .15, {BackgroundColor3 = Theme.Element}) end)
        b.MouseButton1Click:Connect(function()
            if cfg.Callback then cfg.Callback() end
        end)
        return f
    end

    --// TOGGLE
    function tab:Toggle(cfg)
        cfg = cfg or {}
        local state = cfg.StartingState or false
        local f = baseElement(40)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -60, 1, 0)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = cfg.Name or "Toggle"
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = f

        local switch = Instance.new("TextButton")
        switch.Size = UDim2.fromOffset(40, 22)
        switch.Position = UDim2.new(1, -54, 0.5, 0)
        switch.AnchorPoint = Vector2.new(0, 0.5)
        switch.BackgroundColor3 = Theme.Stroke
        switch.Text = ""
        switch.AutoButtonColor = false
        switch.Parent = f
        corner(switch, 11)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16)
        knob.Position = UDim2.new(0, 3, 0.5, 0)
        knob.AnchorPoint = Vector2.new(0, 0.5)
        knob.BackgroundColor3 = Theme.Text
        knob.BorderSizePixel = 0
        knob.Parent = switch
        corner(knob, 8)

        local function update()
            if state then
                tween(switch, .2, {BackgroundColor3 = Theme.Accent})
                tween(knob, .2, {Position = UDim2.new(0, 21, 0.5, 0)})
            else
                tween(switch, .2, {BackgroundColor3 = Theme.Stroke})
                tween(knob, .2, {Position = UDim2.new(0, 3, 0.5, 0)})
            end
            if cfg.Callback then cfg.Callback(state) end
        end
        switch.MouseButton1Click:Connect(function()
            state = not state
            update()
        end)
        if state then update() end
        return {
            Set = function(_, v) state = v; update() end,
            Get = function() return state end
        }
    end

    --// SLIDER
    function tab:Slider(cfg)
        cfg = cfg or {}
        local min, max = cfg.Min or 0, cfg.Max or 100
        local value = cfg.Default or min
        local f = baseElement(54)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -60, 0, 20)
        label.Position = UDim2.new(0, 14, 0, 8)
        label.BackgroundTransparency = 1
        label.Text = cfg.Name or "Slider"
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = f

        local valLabel = Instance.new("TextLabel")
        valLabel.Size = UDim2.new(0, 50, 0, 20)
        valLabel.Position = UDim2.new(1, -60, 0, 8)
        valLabel.BackgroundTransparency = 1
        valLabel.Text = tostring(value)
        valLabel.TextColor3 = Theme.SubText
        valLabel.Font = Enum.Font.GothamMedium
        valLabel.TextSize = 13
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.Parent = f

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -28, 0, 6)
        bar.Position = UDim2.new(0, 14, 1, -16)
        bar.BackgroundColor3 = Theme.Stroke
        bar.BorderSizePixel = 0
        bar.Parent = f
        corner(bar, 3)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((value-min)/(max-min), 0, 1, 0)
        fill.BackgroundColor3 = Theme.Accent
        fill.BorderSizePixel = 0
        fill.Parent = bar
        corner(fill, 3)

        local dragging = false
        local function set(x)
            if not alive(bar) then dragging = false return end
            local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            value = math.floor(min + (max - min) * rel + 0.5)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            valLabel.Text = tostring(value)
            if cfg.Callback then cfg.Callback(value) end
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; set(i.Position.X) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then set(i.Position.X) end
        end)
        return {
            Set = function(_, v)
                value = v
                local rel = (v-min)/(max-min)
                if alive(fill) then fill.Size = UDim2.new(rel,0,1,0) end
                if alive(valLabel) then valLabel.Text = tostring(v) end
            end
        }
    end

    --// TEXTBOX
    function tab:Textbox(cfg)
        cfg = cfg or {}
        local f = baseElement(40)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.5, -14, 1, 0)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = cfg.Name or "Textbox"
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = f

        local boxFrame = Instance.new("Frame")
        boxFrame.Size = UDim2.new(0.5, -14, 0, 26)
        boxFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        boxFrame.AnchorPoint = Vector2.new(0, 0.5)
        boxFrame.BackgroundColor3 = Theme.Background
        boxFrame.BorderSizePixel = 0
        boxFrame.Parent = f
        corner(boxFrame, 6)
        stroke(boxFrame, Theme.Stroke, 1)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -12, 1, 0)
        box.Position = UDim2.new(0, 6, 0, 0)
        box.BackgroundTransparency = 1
        box.Text = ""
        box.PlaceholderText = cfg.Placeholder or "Type here..."
        box.PlaceholderColor3 = Theme.SubText
        box.TextColor3 = Theme.Text
        box.Font = Enum.Font.Gotham
        box.TextSize = 13
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClearTextOnFocus = false
        box.Parent = boxFrame
        box.FocusLost:Connect(function()
            if cfg.Callback then cfg.Callback(box.Text) end
        end)
        return f
    end

    --// DROPDOWN
    function tab:Dropdown(cfg)
        cfg = cfg or {}
        local items = cfg.Items or {}
        local open = false
        local f = baseElement(40)
        f.ClipsDescendants = true

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -40, 0, 40)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = cfg.Name or "Dropdown"
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = f

        local selected = Instance.new("TextLabel")
        selected.Size = UDim2.new(0, 140, 0, 40)
        selected.Position = UDim2.new(1, -156, 0, 0)
        selected.BackgroundTransparency = 1
        selected.Text = cfg.StartingText or "Select..."
        selected.TextColor3 = Theme.SubText
        selected.Font = Enum.Font.Gotham
        selected.TextSize = 13
        selected.TextXAlignment = Enum.TextXAlignment.Right
        selected.Parent = f

        local arrow = Instance.new("TextLabel")
        arrow.Size = UDim2.fromOffset(20, 40)
        arrow.Position = UDim2.new(1, -20, 0, 0)
        arrow.BackgroundTransparency = 1
        arrow.Text = "▾"
        arrow.TextColor3 = Theme.SubText
        arrow.Font = Enum.Font.GothamBold
        arrow.TextSize = 12
        arrow.Parent = f

        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(1, -20, 0, 0)
        holder.Position = UDim2.new(0, 10, 0, 44)
        holder.BackgroundTransparency = 1
        holder.Parent = f
        local hl = Instance.new("UIListLayout")
        hl.Padding = UDim.new(0, 4)
        hl.Parent = holder

        local trigger = Instance.new("TextButton")
        trigger.Size = UDim2.new(1, 0, 0, 40)
        trigger.BackgroundTransparency = 1
        trigger.Text = ""
        trigger.Parent = f

        local function buildItems()
            for _, c in pairs(holder:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            for _, item in pairs(items) do
                local name = type(item) == "table" and item[1] or tostring(item)
                local ib = Instance.new("TextButton")
                ib.Size = UDim2.new(1, 0, 0, 28)
                ib.BackgroundColor3 = Theme.Background
                ib.Text = name
                ib.TextColor3 = Theme.SubText
                ib.Font = Enum.Font.Gotham
                ib.TextSize = 13
                ib.AutoButtonColor = false
                ib.Parent = holder
                corner(ib, 6)
                ib.MouseEnter:Connect(function() tween(ib, .1, {TextColor3 = Theme.Text}) end)
                ib.MouseLeave:Connect(function() tween(ib, .1, {TextColor3 = Theme.SubText}) end)
                ib.MouseButton1Click:Connect(function()
                    selected.Text = name
                    open = false
                    tween(f, .2, {Size = UDim2.new(1,0,0,40)})
                    tween(arrow, .2, {Rotation = 0})
                    if cfg.Callback then cfg.Callback(item) end
                end)
            end
        end
        buildItems()

        trigger.MouseButton1Click:Connect(function()
            open = not open
            if open then
                local h = 44 + (#items * 32) + 8
                tween(f, .2, {Size = UDim2.new(1,0,0,h)})
                tween(arrow, .2, {Rotation = 180})
            else
                tween(f, .2, {Size = UDim2.new(1,0,0,40)})
                tween(arrow, .2, {Rotation = 0})
            end
        end)
        return {
            AddItems = function(_, new) for _,v in pairs(new) do table.insert(items, v) end buildItems() end,
            Clear = function() items = {} buildItems() end
        }
    end

    --// KEYBIND
    function tab:Keybind(cfg)
        cfg = cfg or {}
        local key = cfg.Keybind
        local binding = false
        local f = baseElement(40)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -100, 1, 0)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = cfg.Name or "Keybind"
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = f

        local kb = Instance.new("TextButton")
        kb.Size = UDim2.fromOffset(70, 26)
        kb.Position = UDim2.new(1, -84, 0.5, 0)
        kb.AnchorPoint = Vector2.new(0, 0.5)
        kb.BackgroundColor3 = Theme.Background
        kb.Text = key and key.Name or "None"
        kb.TextColor3 = Theme.SubText
        kb.Font = Enum.Font.GothamMedium
        kb.TextSize = 12
        kb.AutoButtonColor = false
        kb.Parent = f
        corner(kb, 6)
        stroke(kb, Theme.Stroke, 1)

        kb.MouseButton1Click:Connect(function()
            binding = true
            kb.Text = "..."
            kb.TextColor3 = Theme.Accent
        end)
        UserInputService.InputBegan:Connect(function(input, gpe)
            if not alive(kb) then return end
            if binding and input.UserInputType == Enum.UserInputType.Keyboard then
                key = input.KeyCode
                kb.Text = key.Name
                kb.TextColor3 = Theme.SubText
                binding = false
            elseif not gpe and key and input.KeyCode == key then
                if cfg.Callback then cfg.Callback() end
            end
        end)
        return f
    end

    --// CREDIT (создатель + Discord)
    function tab:Credit(cfg)
        cfg = cfg or {}
        local hasIcon = cfg.Icon ~= nil
        local hasDiscord = cfg.Discord ~= nil
        local f = baseElement(64)

        if hasIcon then
            local av = Instance.new("ImageLabel")
            av.Size = UDim2.fromOffset(40, 40)
            av.Position = UDim2.new(0, 12, 0.5, 0)
            av.AnchorPoint = Vector2.new(0, 0.5)
            av.BackgroundColor3 = Theme.Background
            av.Image = resolveIcon(cfg.Icon)
            av.ScaleType = Enum.ScaleType.Crop
            av.Parent = f
            corner(av, 20)
            stroke(av, Theme.Stroke, 1)
        end

        local textX = hasIcon and 62 or 14
        local rightPad = hasDiscord and 118 or 20

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -(textX + rightPad), 0, 20)
        nameLbl.Position = UDim2.new(0, textX, 0, 13)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = cfg.Name or "Creator"
        nameLbl.TextColor3 = Theme.Text
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 14
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = f

        local roleLbl = Instance.new("TextLabel")
        roleLbl.Size = UDim2.new(1, -(textX + rightPad), 0, 18)
        roleLbl.Position = UDim2.new(0, textX, 0, 33)
        roleLbl.BackgroundTransparency = 1
        roleLbl.Text = cfg.Description or cfg.Role or ""
        roleLbl.TextColor3 = Theme.SubText
        roleLbl.Font = Enum.Font.Gotham
        roleLbl.TextSize = 12
        roleLbl.TextXAlignment = Enum.TextXAlignment.Left
        roleLbl.TextTruncate = Enum.TextTruncate.AtEnd
        roleLbl.Parent = f

        if hasDiscord then
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromOffset(96, 32)
            btn.Position = UDim2.new(1, -108, 0.5, 0)
            btn.AnchorPoint = Vector2.new(0, 0.5)
            btn.BackgroundColor3 = Theme.Discord
            btn.Text = "Discord"
            btn.TextColor3 = Theme.Text
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 13
            btn.AutoButtonColor = false
            btn.Parent = f
            corner(btn, 7)

            btn.MouseEnter:Connect(function()
                tween(btn, .15, {BackgroundColor3 = Color3.fromRGB(108, 121, 255)})
            end)
            btn.MouseLeave:Connect(function()
                tween(btn, .15, {BackgroundColor3 = Theme.Discord})
            end)
            btn.MouseButton1Click:Connect(function()
                local ok = copyText(cfg.Discord)
                if win and win.Notification then
                    win:Notification{
                        Title = ok and "Copied!" or "Discord",
                        Text  = ok and "Invite link copied to clipboard."
                                    or ("Copy manually: " .. tostring(cfg.Discord)),
                        Duration = 3,
                    }
                end
                if cfg.Callback then cfg.Callback(cfg.Discord) end
            end)
        end

        return f
    end

    --// SECTION HEADER
    function tab:Section(text)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 24)
        l.BackgroundTransparency = 1
        l.Text = text or "Section"
        l.TextColor3 = Theme.SubText
        l.Font = Enum.Font.GothamBold
        l.TextSize = 12
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = page
        return l
    end

    return tab
end

return Library