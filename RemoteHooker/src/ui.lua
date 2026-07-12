-- src/ui.lua
local settings = require("src/settings")
local utils = require("src/utils")
local UI = {}
UI.isRecording = true
UI.packetCount = 0
UI.capturedPackets = {}
UI.selectedPacket = nil
-- =============================================
-- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ GUI
-- =============================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ScreenGui, Main, TopBar, ContentContainer, BottomBar
local ScrollingFrame, Information, ArgsScroll, ArgsLabel
local RemotesAmount, GuiName
local Functions, GridInterface
local PlayButton, StopButton, MinButton, CloseButton
local DiscordButton
local Execute, ExcludeName, ExcludeIndex, ResetExclusions, CopyCode, CopyFullPath, ClearButtonFunc, CopyHex
local ResizeHandle
local isMinimized = false
local onClose = nil
local nextSequence = 0
local renderGeneration = 0
local MAX_PACKETS = 500
-- =============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ UI (ПЕРЕМЕЩЕНЫ ВВЕРХ!)
-- =============================================
local function updateCounter()
    if RemotesAmount then
        RemotesAmount.Text = "Remotes Hooked: " .. tostring(UI.packetCount)
    end
end

local function updateRecordingStatus(recording)
    if GuiName then
        if recording then
            GuiName.TextColor3 = Color3.fromRGB(0, 230, 118)
        else
            GuiName.TextColor3 = Color3.fromRGB(255, 76, 76)
        end
    end
end

-- =============================================
-- ФУНКЦИЯ ОБНОВЛЕНИЯ CANVAS ДЛЯ СПИСКА РЕМОУТОВ
-- =============================================
local function updatePacketListCanvas()
    if not ScrollingFrame then return end
    local total = 0
    for _, child in ipairs(ScrollingFrame:GetChildren()) do
        if child:IsA("TextButton") then
            total = total + 1
        end
    end
    local height = math.max(total * 30 + 10, ScrollingFrame.AbsoluteSize.Y)
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, height)
end
-- =============================================
-- ФУНКЦИЯ ОБНОВЛЕНИЯ CANVAS ДЛЯ АРГУМЕНТОВ
-- =============================================
local function updateArgsCanvas()
    if not ArgsLabel or not ArgsScroll then return end
    local textService = game:GetService("TextService")
    local text = ArgsLabel.Text
    local fontSize = ArgsLabel.TextSize
    local font = ArgsLabel.Font
    local textBounds = textService:GetTextSize(text, fontSize, font, Vector2.new(20000, 100000))
    local textWidth = math.max(textBounds.X + 20, ArgsScroll.AbsoluteSize.X)
    local textHeight = math.max(textBounds.Y + 20, ArgsScroll.AbsoluteSize.Y)

    ArgsLabel.Size = UDim2.new(1, 0, 0, textBounds.Y + 10)
    ArgsScroll.CanvasSize = UDim2.new(0, textWidth, 0, textHeight + 20)
end
-- =============================================
-- ФУНКЦИЯ ОБНОВЛЕНИЯ РАЗМЕРОВ ПРИ РЕСАЙЗЕ
-- =============================================
local function updateSizes()
    if not Main or not ContentContainer or not ScrollingFrame or not Information or not ArgsScroll or not Functions then
        return
    end
    local mainWidth = Main.Size.X.Offset
    local mainHeight = Main.Size.Y.Offset
    local topBarHeight = 50
    local bottomBarHeight = 30
    local contentHeight = mainHeight - topBarHeight - bottomBarHeight
    ContentContainer.Size = UDim2.new(1, 0, 0, contentHeight)
    ContentContainer.Position = UDim2.new(0, 0, 0, topBarHeight)

    ScrollingFrame.Size = UDim2.new(0, 135, 1, 0)

    Information.Size = UDim2.new(1, -135, 1, 0)

    ArgsScroll.Size = UDim2.new(1, -10, 1, -75)

    Functions.Size = UDim2.new(1, -10, 0, 65)
    Functions.Position = UDim2.new(0, 5, 1, -70)

    updatePacketListCanvas()
    updateArgsCanvas()
end
-- =============================================
-- СОЗДАНИЕ ГУИ
-- =============================================
local function createGUI()
    local guiParent = PlayerGui

    -- Некоторые среды возвращают CoreGui из gethui(), но не дают текущему
    -- потоку обращаться к нему. Проверяем доступ внутри pcall и иначе
    -- безопасно используем PlayerGui.
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then
            local canAccess = pcall(function()
                result:FindFirstChild("RemoteSpoofer_Gui")
            end)
            if canAccess then
                guiParent = result
            end
        end
    end

    local oldGui
    pcall(function()
        oldGui = guiParent:FindFirstChild("RemoteSpoofer_Gui")
    end)
    if oldGui then
        oldGui:Destroy()
    end

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RemoteSpoofer_Gui"
    ScreenGui.DisplayOrder = 999999
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ResetOnSpawn = false

    local parented = pcall(function()
        ScreenGui.Parent = guiParent
    end)
    if not parented then
        ScreenGui.Parent = PlayerGui
    end

    Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 525, 0, 516)
    Main.Position = UDim2.new(0.24, 0, 0.16, 0)
    Main.BorderSizePixel = 0
    Main.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    Main.Parent = ScreenGui

    task.defer(function()
        local parentSize = Main.Parent.AbsoluteSize
        if parentSize.X > 0 and parentSize.Y > 0 then
            local x = Main.Position.X.Scale * parentSize.X + Main.Position.X.Offset
            local y = Main.Position.Y.Scale * parentSize.Y + Main.Position.Y.Offset
            Main.Position = UDim2.new(0, x, 0, y)
        end
    end)

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 8)
    MainCorner.Parent = Main

    ResizeHandle = Instance.new("Frame")
    ResizeHandle.Name = "ResizeHandle"
    ResizeHandle.Size = UDim2.new(0, 16, 0, 16)
    ResizeHandle.Position = UDim2.new(1, -16, 1, -16)
    ResizeHandle.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
    ResizeHandle.BorderSizePixel = 0
    ResizeHandle.ZIndex = 10
    ResizeHandle.Parent = Main

    local handleCorner = Instance.new("UICorner")
    handleCorner.CornerRadius = UDim.new(0, 2)
    handleCorner.Parent = ResizeHandle

    local dots = Instance.new("ImageLabel")
    dots.Size = UDim2.new(1, 0, 1, 0)
    dots.BackgroundTransparency = 1
    dots.Image = "rbxasset://textures/ui/Studio/ResizeHandle.png"
    dots.ImageColor3 = Color3.fromRGB(200, 200, 200)
    dots.Parent = ResizeHandle

    -- TopBar
    TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 50)
    TopBar.BorderSizePixel = 0
    TopBar.BackgroundColor3 = Color3.fromRGB(18, 19, 26)
    TopBar.Parent = Main

    local TopBarCorner = Instance.new("UICorner")
    TopBarCorner.CornerRadius = UDim.new(0, 8)
    TopBarCorner.Parent = TopBar

    GuiName = Instance.new("TextLabel")
    GuiName.Name = "GuiName"
    GuiName.Size = UDim2.new(0, 200, 1, 0)
    GuiName.Position = UDim2.new(0, 10, 0, 0)
    GuiName.BackgroundTransparency = 1
    GuiName.Font = Enum.Font.SourceSansBold
    GuiName.TextSize = 13
    GuiName.Text = "  RemoteSpoofer"
    GuiName.TextColor3 = Color3.fromRGB(200, 205, 215)
    GuiName.TextXAlignment = Enum.TextXAlignment.Left
    GuiName.Parent = TopBar

    RemotesAmount = Instance.new("TextLabel")
    RemotesAmount.Name = "RemotesAmount"
    RemotesAmount.Size = UDim2.new(0, 130, 1, 0)
    RemotesAmount.Position = UDim2.new(0.30, 0, 0, 0)
    RemotesAmount.BackgroundTransparency = 1
    RemotesAmount.Font = Enum.Font.SourceSansBold
    RemotesAmount.TextSize = 13
    RemotesAmount.Text = "Remotes Hooked: 0"
    RemotesAmount.TextColor3 = Color3.fromRGB(140, 145, 160)
    RemotesAmount.TextXAlignment = Enum.TextXAlignment.Center
    RemotesAmount.Parent = TopBar

    -- Кнопки в TopBar
    local ButtonsContainer = Instance.new("Frame")
    ButtonsContainer.Name = "ButtonsContainer"
    ButtonsContainer.Size = UDim2.new(0, 160, 1, 0)
    ButtonsContainer.Position = UDim2.new(1, -170, 0, 0)
    ButtonsContainer.BackgroundTransparency = 1
    ButtonsContainer.Parent = TopBar

    local function applyButtonEffects(btn, defaultBg, hoverBg, defaultText, hoverText, strokeColor)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = btn
        local stroke = Instance.new("UIStroke")
        stroke.Color = strokeColor or Color3.fromRGB(35, 38, 50)
        stroke.Thickness = 1
        stroke.Parent = btn

        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = hoverBg
            btn.TextColor3 = hoverText
            if strokeColor then stroke.Color = hoverText end
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = defaultBg
            btn.TextColor3 = defaultText
            if strokeColor then stroke.Color = strokeColor end
        end)
    end

    local function createTopBtn(text, color, xPos, width)
        width = width or 36
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, width, 0, 26)
        btn.Position = UDim2.new(0, xPos, 0.5, -13)
        btn.BackgroundColor3 = Color3.fromRGB(24, 26, 35)
        btn.Text = text
        btn.Font = Enum.Font.SourceSansBold
        btn.TextSize = 12
        btn.TextColor3 = color
        btn.Parent = ButtonsContainer
        applyButtonEffects(btn, Color3.fromRGB(24, 26, 35), Color3.fromRGB(32, 35, 48), color, color, Color3.fromRGB(40, 43, 55))
        return btn
    end

    PlayButton = createTopBtn("Play", Color3.fromRGB(0, 230, 118), 0)
    StopButton = createTopBtn("Stop", Color3.fromRGB(255, 76, 76), 40)
    MinButton = createTopBtn("▼", Color3.fromRGB(255, 255, 255), 80, 30)
    CloseButton = createTopBtn("X", Color3.fromRGB(255, 255, 255), 115, 30)
    CloseButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    applyButtonEffects(CloseButton, Color3.fromRGB(200, 50, 50), Color3.fromRGB(255, 80, 80), Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
    MinButton.BackgroundColor3 = Color3.fromRGB(50, 50, 150)
    applyButtonEffects(MinButton, Color3.fromRGB(50, 50, 150), Color3.fromRGB(80, 80, 200), Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))

    -- ContentContainer
    ContentContainer = Instance.new("Frame")
    ContentContainer.Name = "ContentContainer"
    ContentContainer.Size = UDim2.new(1, 0, 1, -50 - 30)
    ContentContainer.Position = UDim2.new(0, 0, 0, 50)
    ContentContainer.BackgroundTransparency = 1
    ContentContainer.Parent = Main

    -- ScrollingFrame
    ScrollingFrame = Instance.new("ScrollingFrame")
    ScrollingFrame.Active = true
    ScrollingFrame.BorderSizePixel = 0
    ScrollingFrame.BackgroundColor3 = Color3.fromRGB(14, 15, 22)
    ScrollingFrame.Size = UDim2.new(0, 135, 1, 0)
    ScrollingFrame.Position = UDim2.new(0, 0, 0, 0)
    ScrollingFrame.ScrollBarThickness = 6
    ScrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(45, 48, 65)
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollingFrame.Parent = ContentContainer

    local ListLayout = Instance.new("UIListLayout")
    ListLayout.Padding = UDim.new(0, 4)
    ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    ListLayout.Parent = ScrollingFrame

    ScrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePacketListCanvas)
    ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updatePacketListCanvas)

    -- Information
    Information = Instance.new("Frame")
    Information.Name = "Information"
    Information.Size = UDim2.new(1, -135, 1, 0)
    Information.Position = UDim2.new(0, 135, 0, 0)
    Information.BorderSizePixel = 0
    Information.BackgroundColor3 = Color3.fromRGB(12, 13, 19)
    Information.Parent = ContentContainer

    -- ArgsScroll
    ArgsScroll = Instance.new("ScrollingFrame")
    ArgsScroll.Name = "ArgsScroll"
    ArgsScroll.Size = UDim2.new(1, -10, 1, -75)
    ArgsScroll.Position = UDim2.new(0, 5, 0, 5)
    ArgsScroll.BackgroundTransparency = 1
    ArgsScroll.BorderSizePixel = 0
    ArgsScroll.ScrollBarThickness = 8
    ArgsScroll.ScrollBarImageColor3 = Color3.fromRGB(45, 48, 65)
    ArgsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ArgsScroll.Parent = Information

    ArgsLabel = Instance.new("TextLabel")
    ArgsLabel.Name = "ArgsLabel"
    ArgsLabel.Size = UDim2.new(1, 0, 0, 0)
    ArgsLabel.BackgroundTransparency = 1
    ArgsLabel.Font = Enum.Font.Code
    ArgsLabel.TextSize = 13
    ArgsLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
    ArgsLabel.TextXAlignment = Enum.TextXAlignment.Left
    ArgsLabel.TextYAlignment = Enum.TextYAlignment.Top
    ArgsLabel.TextWrapped = false
    ArgsLabel.RichText = true  -- ✅ ИСПРАВЛЕНИЕ: ВКЛЮЧАЕМ RICHTEXT
    ArgsLabel.Text = "-- Select a remote to view arguments --"
    ArgsLabel.Parent = ArgsScroll

    ArgsLabel:GetPropertyChangedSignal("Text"):Connect(function()
        task.defer(updateArgsCanvas)
    end)
    ArgsScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateArgsCanvas)

    -- Functions
    Functions = Instance.new("Frame")
    Functions.Name = "Functions"
    Functions.Size = UDim2.new(1, -10, 0, 65)
    Functions.Position = UDim2.new(0, 5, 1, -70)
    Functions.BackgroundTransparency = 1
    Functions.Parent = Information

    GridInterface = Instance.new("UIGridLayout")
    GridInterface.CellSize = UDim2.new(0, 120, 0, 20)
    GridInterface.CellPadding = UDim2.new(0, 2, 0, 2)
    GridInterface.SortOrder = Enum.SortOrder.LayoutOrder
    GridInterface.Parent = Functions

    local function createFuncBtn(text, order, isExecute)
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
        btn.Text = text
        btn.Font = Enum.Font.SourceSansBold
        btn.TextSize = 12
        btn.LayoutOrder = order
        btn.TextColor3 = isExecute and Color3.fromRGB(0, 180, 255) or Color3.fromRGB(200, 205, 215)
        btn.Parent = Functions
        applyButtonEffects(
        btn,
        Color3.fromRGB(18, 20, 28),
        Color3.fromRGB(26, 29, 40),
        btn.TextColor3,
        isExecute and Color3.fromRGB(0, 220, 255) or Color3.fromRGB(255, 255, 255)
        )
        return btn
    end

    Execute = createFuncBtn("Execute", 1, true)
    ExcludeName = createFuncBtn("Exclude (n)", 2, false)
    ExcludeIndex = createFuncBtn("Exclude (i)", 3, false)
    ResetExclusions = createFuncBtn("Reset Exclusions", 4, false)
    CopyCode = createFuncBtn("Copy Code", 5, false)
    CopyFullPath = createFuncBtn("Copy Full Path", 6, false)
    ClearButtonFunc = createFuncBtn("Clear", 7, false)
    CopyHex = createFuncBtn("Copy Hex", 8, false)

    -- BottomBar
    BottomBar = Instance.new("Frame")
    BottomBar.Name = "BottomBar"
    BottomBar.Size = UDim2.new(1, 0, 0, 30)
    BottomBar.Position = UDim2.new(0, 0, 1, -30)
    BottomBar.BorderSizePixel = 0
    BottomBar.BackgroundColor3 = Color3.fromRGB(18, 19, 26)
    BottomBar.Parent = Main

    local BottomCorner = Instance.new("UICorner")
    BottomCorner.CornerRadius = UDim.new(0, 8)
    BottomCorner.Parent = BottomBar

    DiscordButton = Instance.new("TextButton")
    DiscordButton.BorderSizePixel = 0
    DiscordButton.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    DiscordButton.Font = Enum.Font.SourceSansItalic
    DiscordButton.TextSize = 12
    DiscordButton.Size = UDim2.new(0, 200, 0, 20)
    DiscordButton.Position = UDim2.new(0.5, -100, 0.5, -10)
    DiscordButton.TextColor3 = Color3.fromRGB(120, 125, 140)
    DiscordButton.Text = "Made by PoloSka (click to copy discord)"
    DiscordButton.Parent = BottomBar

    local CreditCorner = Instance.new("UICorner")
    CreditCorner.CornerRadius = UDim.new(0, 4)
    CreditCorner.Parent = DiscordButton

    task.defer(updateSizes)
end
-- =============================================
-- ОБРАБОТЧИКИ КНОПОК �� ЛОГИКА
-- =============================================
local function setupEventHandlers()
    local dragging = false
    local dragStartX, dragStartY, mainPosX, mainPosY
    local UserInputService = game:GetService("UserInputService")
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            local mousePos = UserInputService:GetMouseLocation()
            dragStartX = mousePos.X
            dragStartY = mousePos.Y
            mainPosX = Main.Position.X.Offset
            mainPosY = Main.Position.Y.Offset
        end
    end)

    TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = UserInputService:GetMouseLocation()
            local deltaX = mousePos.X - dragStartX
            local deltaY = mousePos.Y - dragStartY
            Main.Position = UDim2.new(0, mainPosX + deltaX, 0, mainPosY + deltaY)
        end
    end)

    -- Ресайз
    local resizing = false
    local resizeStartX, resizeStartY, startWidth, startHeight

    ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            local mousePos = UserInputService:GetMouseLocation()
            resizeStartX = mousePos.X
            resizeStartY = mousePos.Y
            startWidth = Main.Size.X.Offset
            startHeight = Main.Size.Y.Offset
        end
    end)

    ResizeHandle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = UserInputService:GetMouseLocation()
            local deltaX = mousePos.X - resizeStartX
            local deltaY = mousePos.Y - resizeStartY
            local newWidth = math.max(400, startWidth + deltaX)
            local newHeight = math.max(300, startHeight + deltaY)
            Main.Size = UDim2.new(0, newWidth, 0, newHeight)
            updateSizes()
        end
    end)

    -- Сворачивание
    local function toggleMinimize()
        isMinimized = not isMinimized
        if isMinimized then
            ContentContainer.Visible = false
            BottomBar.Visible = false
            ResizeHandle.Visible = false
            Main.Size = UDim2.new(0, 525, 0, 50)
            MinButton.Text = "▲"
        else
            ContentContainer.Visible = true
            BottomBar.Visible = true
            ResizeHandle.Visible = true
            Main.Size = UDim2.new(0, 525, 0, 516)
            MinButton.Text = "▼"
            updateSizes()
        end
    end

    MinButton.MouseButton1Click:Connect(toggleMinimize)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.H and
        (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) and
        (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
            toggleMinimize()
        end
    end)

    -- Кнопки
    PlayButton.MouseButton1Click:Connect(function()
        UI.isRecording = true
        updateRecordingStatus(true)
        print("[UI] Recording started")
    end)

    StopButton.MouseButton1Click:Connect(function()
        UI.isRecording = false
        updateRecordingStatus(false)
        print("[UI] Recording stopped")
    end)

    ClearButtonFunc.MouseButton1Click:Connect(function()
        UI.packetCount = 0
        UI.capturedPackets = {}
        renderGeneration = renderGeneration + 1
        UI.selectedPacket = nil
        ArgsLabel.Text = "-- Select a remote to view arguments --"
        for _, child in ipairs(ScrollingFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        updatePacketListCanvas()
        updateCounter()
        print("[UI] Cleared")
    end)

    CloseButton.MouseButton1Click:Connect(function()
        UI.isRecording = false
        if onClose then
            local ok, err = pcall(onClose)
            if not ok then warn("[UI] Shutdown callback failed:", err) end
        end
        print("[UI] Shutting down and closing GUI")
        ScreenGui:Destroy()
    end)

    Execute.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        local p = UI.selectedPacket
        pcall(function()
            local obj = p.instance
            if not obj or not obj.Parent then
                obj = utils.findInstanceByPath(p.path)
            end
            if obj and obj.Parent then
                if p.method == "FireServer" then
                    obj:FireServer(table.unpack(p.args, 1, p.argCount or p.args.n or #p.args))
                elseif p.method == "InvokeServer" then
                    obj:InvokeServer(table.unpack(p.args, 1, p.argCount or p.args.n or #p.args))
                end
                print("[UI] Executed", p.method, "on", p.path)
            else
                warn("[UI] Object not found:", p.path)
            end
        end)
    end)

    ExcludeName.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        settings.excludeName(UI.selectedPacket.name)
        print("[UI] Excluded by name:", UI.selectedPacket.name)
    end)

    ExcludeIndex.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        settings.excludePath(UI.selectedPacket.path)
        print("[UI] Excluded by path:", UI.selectedPacket.path)
    end)

    ResetExclusions.MouseButton1Click:Connect(function()
        settings.resetExclusions()
        print("[UI] All exclusions reset")
    end)

    CopyCode.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        local code = utils.generateCodeStr(UI.selectedPacket)
        if setclipboard then
            setclipboard(code)
            print("[UI] Code copied")
        else
            print(code)
        end
    end)

    CopyFullPath.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        if setclipboard then
            setclipboard(UI.selectedPacket.path)
            print("[UI] Path copied")
        end
    end)

    CopyHex.MouseButton1Click:Connect(function()
        if not UI.selectedPacket then return end
        local hexStr = utils.getHexFromPacket(UI.selectedPacket)
        if setclipboard then
            setclipboard(hexStr)
            print("[UI] Hex copied")
        else
            print(hexStr)
        end
    end)

    DiscordButton.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard("polosa__")
            print("[UI] Discord copied")
        end
    end)
end
-- =============================================
-- ФУНКЦИЯ ДОБАВЛЕНИЯ ПАКЕТА
-- =============================================
function UI.addPacket(packet)
    if not UI.isRecording or not ScreenGui or not ScreenGui.Parent then return end

    nextSequence = nextSequence + 1
    packet.sequence = nextSequence
    packet.argCount = packet.argCount or packet.args.n or #packet.args
    UI.packetCount = UI.packetCount + 1

    -- Новые пакеты храним в начале, старые сдвигаются вниз.
    table.insert(UI.capturedPackets, 1, packet)

    -- Не даём истории и GUI бесконечно расти.
    if #UI.capturedPackets > MAX_PACKETS then
        local oldest = table.remove(UI.capturedPackets)
        oldest.discarded = true
        if oldest.item then oldest.item:Destroy() end
    end

    local packetGeneration = renderGeneration
    task.defer(function()
        if packet.discarded or packetGeneration ~= renderGeneration then return end
        if not ScrollingFrame or not ScrollingFrame.Parent then return end

        local ok, err = pcall(function()
            local item = Instance.new("TextButton")
            packet.item = item
            item.Name = "Packet_" .. packet.sequence
            item.LayoutOrder = -packet.sequence -- чем новее пакет, тем выше он в UIListLayout
            item.Size = UDim2.new(1, -6, 0, 26)
            item.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
            item.Text = "  " .. packet.name
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.Font = Enum.Font.SourceSansBold
            item.TextSize = 13
            item.Parent = ScrollingFrame

            local itemCorner = Instance.new("UICorner")
            itemCorner.CornerRadius = UDim.new(0, 4)
            itemCorner.Parent = item

            local itemStroke = Instance.new("UIStroke")
            itemStroke.Thickness = 1
            if packet.method == "InvokeServer" then
                item.TextColor3 = Color3.fromRGB(0, 180, 255)
                itemStroke.Color = Color3.fromRGB(0, 50, 100)
            else
                item.TextColor3 = Color3.fromRGB(255, 130, 0)
                itemStroke.Color = Color3.fromRGB(100, 50, 0)
            end
            itemStroke.Parent = item

            item.MouseButton1Click:Connect(function()
                UI.selectedPacket = packet
                ArgsLabel.Text = utils.formatArgsTable(packet)
                task.defer(updateArgsCanvas)
            end)

            updateCounter()
            updatePacketListCanvas()
            ScrollingFrame.CanvasPosition = Vector2.new(0, 0)
        end)

        if not ok then
            warn("[UI] Failed to render packet:", err)
        end
    end)
end
-- =============================================
-- ИНИЦИАЛИЗАЦИЯ
-- =============================================
function UI.init(options)
    options = options or {}
    onClose = options.onClose
    createGUI()
    setupEventHandlers()
    updateRecordingStatus(true)
    task.wait(0.1)
    updatePacketListCanvas()
    updateArgsCanvas()
    print("[UI] GUI initialized")
end
return UI
