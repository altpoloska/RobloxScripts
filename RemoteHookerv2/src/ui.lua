local settings = require("src/settings")
local utils = require("src/utils")

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {
    isRecording = true,
    packetCount = 0,
    capturedPackets = {},
    selectedPacket = nil,
}

local ASSETS = {
    close = "rbxassetid://10747384394",
    minimize = "rbxassetid://10734896206",
    restore = "rbxassetid://10734886735",
    pause = "rbxassetid://7734021897",
    play = "rbxassetid://7743871480",
    resize = "rbxasset://textures/ui/Studio/ResizeHandle.png",
}


local COLORS = {
    canvas = Color3.fromRGB(17, 18, 21),
    surface = Color3.fromRGB(24, 25, 29),
    elevated = Color3.fromRGB(31, 32, 37),
    hover = Color3.fromRGB(39, 41, 47),
    border = Color3.fromRGB(53, 55, 63),
    text = Color3.fromRGB(242, 243, 245),
    muted = Color3.fromRGB(149, 152, 163),
    blue = Color3.fromRGB(94, 159, 232),
    green = Color3.fromRGB(90, 205, 143),
    orange = Color3.fromRGB(231, 155, 84),
    red = Color3.fromRGB(229, 100, 94),
    overlay = Color3.fromRGB(8, 9, 11),
}

local MIN_WIDTH = 520
local MIN_HEIGHT = 320
local DEFAULT_SIZE = Vector2.new(760, 560)
local MINIMIZED_HEIGHT = 48

local player = Players.LocalPlayer
local screenGui
local window
local topBar
local titleLabel
local titleGlow
local statusLabel
local sidebar
local searchBox
local packetList
local content
local codeScroll
local codeLabel
local codeHighlight
local editorCaret
local actionScroll
local actionGrid
local resizeHandle
local pauseButton
local minimizeButton
local closeButton
local closeOverlay
local authorBadge
local editButton

local onClose
local onRecordingChanged
local connections = {}
local sequence = 0
local generation = 0
local filterMode = "All"
local grouped = true
local minimized = false
local previousSize = DEFAULT_SIZE
local previousPosition
local editorUnlocked = false
local editorDirty = false
local suppressEditorChange = false
local nextActionOrder = 0

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function disconnectAll()
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)
end

local function addCorner(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 7)
    corner.Parent = object
    return corner
end

local function addStroke(object, color)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or COLORS.border
    stroke.Thickness = 1
    stroke.Parent = object
    return stroke
end

local function createLabel(parent, text, size, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.SourceSans
    label.Text = text
    label.TextColor3 = color or COLORS.text
    label.TextSize = size or 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function createTextButton(parent, text)
    local button = Instance.new("TextButton")
    button.AutoButtonColor = false
    button.BackgroundColor3 = COLORS.elevated
    button.BorderSizePixel = 0
    button.Font = Enum.Font.Gotham
    button.Text = text
    button.TextColor3 = COLORS.text
    button.TextSize = 13
    button.Parent = parent
    addCorner(button, 6)
    addStroke(button)

    connect(button.MouseEnter, function()
        button.BackgroundColor3 = COLORS.hover
    end)

    connect(button.MouseLeave, function()
        button.BackgroundColor3 = COLORS.elevated
    end)

    return button
end

local function createIconButton(parent, imageAsset, description)
    local button = Instance.new("ImageButton")
    button.Name = description
    button.AutoButtonColor = false
    button.BackgroundColor3 = COLORS.surface
    button.BorderSizePixel = 0
    button.Image = imageAsset
    button.ImageColor3 = COLORS.muted
    button.ScaleType = Enum.ScaleType.Fit
    button.Parent = parent
    addCorner(button, 6)

    connect(button.MouseEnter, function()
        button.BackgroundColor3 = COLORS.hover
        button.ImageColor3 = COLORS.text
    end)

    connect(button.MouseLeave, function()
        button.BackgroundColor3 = COLORS.surface
        button.ImageColor3 = COLORS.muted
    end)

    return button
end

local function setTitleState(recording)
    if not titleLabel then
        return
    end

    local color = recording and COLORS.green or COLORS.orange
    titleLabel.TextColor3 = color

    if pauseButton then
        pauseButton.Image = recording and ASSETS.pause or ASSETS.play
        pauseButton.ImageColor3 = color
    end
end

local function updateStatus(message, color)
    if not statusLabel then
        return
    end

    statusLabel.Text = message or string.format(
        "Captured %d  ·  Retained %d",
        UI.packetCount,
        #UI.capturedPackets
    )
    statusLabel.TextColor3 = color or COLORS.muted
end

local LUA_KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local function escapeRichText(text)
    return tostring(text)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

local function colorToken(text, color)
    return '<font color="' .. color .. '">' .. escapeRichText(text) .. "</font>"
end

local function highlightLua(source)
    local output = {}
    local index = 1
    local length = #source

    while index <= length do
        local character = source:sub(index, index)
        local nextCharacter = source:sub(index + 1, index + 1)

        if character == "-" and nextCharacter == "-" then
            local finish = source:find("\n", index, true) or (length + 1)
            output[#output + 1] = colorToken(
                source:sub(index, finish - 1),
                "#7D8590"
            )
            if finish <= length then
                output[#output + 1] = "\n"
            end
            index = finish + 1
        elseif character == '"' or character == "'" then
            local quote = character
            local finish = index + 1
            local escaped = false

            while finish <= length do
                local current = source:sub(finish, finish)
                if escaped then
                    escaped = false
                elseif current == "\\" then
                    escaped = true
                elseif current == quote then
                    finish = finish + 1
                    break
                end
                finish = finish + 1
            end

            output[#output + 1] = colorToken(
                source:sub(index, finish - 1),
                "#E5C07B"
            )
            index = finish
        elseif character:match("[%d]") then
            local finish = index
            while finish <= length
                and source:sub(finish, finish):match("[%w%.xXA-Fa-f_]") do
                finish = finish + 1
            end
            output[#output + 1] = colorToken(
                source:sub(index, finish - 1),
                "#D19A66"
            )
            index = finish
        elseif character:match("[%a_]") then
            local finish = index
            while finish <= length
                and source:sub(finish, finish):match("[%w_]") do
                finish = finish + 1
            end

            local word = source:sub(index, finish - 1)
            local lookAhead = finish
            while source:sub(lookAhead, lookAhead):match("%s") do
                lookAhead = lookAhead + 1
            end

            if LUA_KEYWORDS[word] then
                output[#output + 1] = colorToken(word, "#C678DD")
            elseif source:sub(lookAhead, lookAhead) == "(" then
                output[#output + 1] = colorToken(word, "#61AFEF")
            else
                output[#output + 1] = escapeRichText(word)
            end
            index = finish
        else
            output[#output + 1] = escapeRichText(character)
            index = index + 1
        end
    end

    return table.concat(output)
end

local function refreshCaret()
    if not editorCaret or not codeLabel then
        return
    end

    local cursorPosition = codeLabel.CursorPosition
    if not editorUnlocked or cursorPosition < 1 then
        editorCaret.Visible = false
        return
    end

    local prefix = codeLabel.Text:sub(1, cursorPosition - 1)
    local currentLine = prefix:match("([^\n]*)$") or ""
    local lineNumber = 1
    for _ in prefix:gmatch("\n") do
        lineNumber = lineNumber + 1
    end

    local lineBounds = TextService:GetTextSize(
        currentLine,
        codeLabel.TextSize,
        codeLabel.Font,
        Vector2.new(6000, 100)
    )
    local lineHeight = TextService:GetTextSize(
        "Ag",
        codeLabel.TextSize,
        codeLabel.Font,
        Vector2.new(100, 100)
    ).Y

    editorCaret.Position = UDim2.fromOffset(
        codeLabel.Position.X.Offset + lineBounds.X,
        codeLabel.Position.Y.Offset + (lineNumber - 1) * lineHeight
    )
    editorCaret.Size = UDim2.fromOffset(2, lineHeight)
    editorCaret.Visible = true
end

local function refreshEditor(text)
    if not codeLabel or not codeHighlight or not codeScroll then
        return
    end

    codeHighlight.Text = highlightLua(text)

    task.defer(function()
        if not codeLabel or not codeHighlight or not codeScroll then
            return
        end

        local bounds = TextService:GetTextSize(
            text,
            codeLabel.TextSize,
            codeLabel.Font,
            Vector2.new(6000, 100000)
        )
        local editorSize = UDim2.fromOffset(
            math.max(bounds.X + 24, codeScroll.AbsoluteSize.X - 16),
            math.max(bounds.Y + 24, codeScroll.AbsoluteSize.Y - 16)
        )

        codeLabel.Size = editorSize
        codeHighlight.Size = editorSize
        codeScroll.CanvasSize = UDim2.fromOffset(
            editorSize.X.Offset,
            editorSize.Y.Offset
        )
        refreshCaret()
    end)
end

local function updateCode(text)
    if not codeLabel then
        return
    end

    suppressEditorChange = true
    codeLabel.Text = text
    suppressEditorChange = false
    editorDirty = false
    refreshEditor(text)
end

function UI.showError(message)
    updateCode("-- ERROR\n" .. tostring(message))
    updateStatus(tostring(message), COLORS.red)
end

local function matchesFilter(packet)
    local query = searchBox and searchBox.Text:lower() or ""
    if query ~= "" then
        local matchesName = packet.name:lower():find(query, 1, true)
        local matchesPath = packet.path:lower():find(query, 1, true)
        if not matchesName and not matchesPath then
            return false
        end
    end

    if filterMode == "Events" then
        return packet.method == "FireServer"
    elseif filterMode == "Functions" then
        return packet.method == "InvokeServer"
    elseif filterMode == "Blocked" then
        return packet.blocked == true
    end

    return true
end

local function selectPacket(packet)
    if editorUnlocked then
        updateStatus("Lock the editor before selecting a remote", COLORS.orange)
        return
    end

    UI.selectedPacket = packet
    editorUnlocked = false
    editorDirty = false
    if codeLabel then
        codeLabel.TextEditable = false
    end
    if editButton then
        editButton.Text = "Edit remote"
    end
    updateCode(utils.generateCodeStr(packet))

    local suffix = packet.blocked and "  ·  BLOCKED" or ""
    updateStatus(
        packet.method .. "  ·  " .. packet.path .. suffix,
        packet.blocked and COLORS.red or COLORS.muted
    )
end

local function clearPacketButtons()
    for _, child in ipairs(packetList:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function clearPackets()
    generation = generation + 1
    UI.packetCount = 0
    UI.selectedPacket = nil
    table.clear(UI.capturedPackets)

    editorUnlocked = false
    editorDirty = false
    codeLabel.TextEditable = false
    if editorCaret then
        editorCaret.Visible = false
    end
    if editButton then
        editButton.Text = "Edit remote"
    end

    clearPacketButtons()
    packetList.CanvasPosition = Vector2.new(0, 0)
    packetList.CanvasSize = UDim2.new()
    updateCode("-- Select a remote call --")
    updateStatus("Remote list cleared", COLORS.muted)
end

local function renderPacketList()
    if not packetList then
        return
    end

    generation = generation + 1
    local renderGeneration = generation
    clearPacketButtons()

    local entries = {}
    if grouped then
        local groups = {}
        for _, packet in ipairs(UI.capturedPackets) do
            if matchesFilter(packet) then
                local key = packet.method .. "\0" .. packet.path
                if not groups[key] then
                    groups[key] = {
                        packet = packet,
                        count = 0,
                    }
                    entries[#entries + 1] = groups[key]
                end
                groups[key].count = groups[key].count + 1
            end
        end
    else
        for _, packet in ipairs(UI.capturedPackets) do
            if matchesFilter(packet) then
                entries[#entries + 1] = {
                    packet = packet,
                    count = 1,
                }
            end
        end
    end

    for index, entry in ipairs(entries) do
        if renderGeneration ~= generation then
            return
        end

        local packet = entry.packet
        local button = createTextButton(packetList, "")
        button.LayoutOrder = index
        button.Size = UDim2.new(1, -8, 0, 36)
        button.Text = "  " .. packet.name
        button.TextXAlignment = Enum.TextXAlignment.Left

        if entry.count > 1 then
            button.Text = button.Text .. "  ×" .. entry.count
        end

        if packet.blocked then
            button.TextColor3 = COLORS.red
        elseif packet.method == "InvokeServer" then
            button.TextColor3 = COLORS.blue
        else
            button.TextColor3 = COLORS.orange
        end

        connect(button.MouseButton1Click, function()
            selectPacket(packet)
        end)
    end

    packetList.CanvasSize = UDim2.fromOffset(0, #entries * 40 + 6)
end

local function updateResponsiveLayout()
    if not window or minimized then
        return
    end

    local width = window.AbsoluteSize.X
    local height = window.AbsoluteSize.Y
    local sidebarWidth = math.clamp(math.floor(width * 0.28), 170, 230)

    sidebar.Size = UDim2.new(0, sidebarWidth, 1, -92)
    content.Position = UDim2.fromOffset(sidebarWidth + 18, 56)
    content.Size = UDim2.new(1, -(sidebarWidth + 26), 1, -94)

    local availableWidth = math.max(220, content.AbsoluteSize.X - 16)
    local columns = math.max(1, math.floor((availableWidth + 6) / 118))
    local cellWidth = math.floor((availableWidth - (columns - 1) * 6) / columns)
    actionGrid.CellSize = UDim2.fromOffset(cellWidth, 34)
    actionGrid.FillDirectionMaxCells = columns

    local actionHeight = math.clamp(math.floor(height * 0.22), 46, 92)
    actionScroll.Size = UDim2.new(1, -16, 0, actionHeight)
    actionScroll.Position = UDim2.new(0, 8, 1, -(actionHeight + 8))
    codeScroll.Size = UDim2.new(1, -16, 1, -(actionHeight + 24))

    task.defer(function()
        if actionScroll and actionGrid then
            actionScroll.CanvasSize = UDim2.fromOffset(
                0,
                actionGrid.AbsoluteContentSize.Y + 4
            )
        end
    end)
end

local function executeSelected()
    if not UI.selectedPacket then
        UI.showError("Select a packet first")
        return
    end

    if type(loadstring) ~= "function" then
        UI.showError("The executor does not provide loadstring; edited code cannot run")
        return
    end

    local source = codeLabel.Text
    local chunk, compileError = loadstring(source, "RemoteHookerEditor")
    if not chunk then
        UI.showError("Compile error:\n" .. tostring(compileError))
        return
    end

    local ok, result = xpcall(function()
        return table.pack(chunk())
    end, function(err)
        if debug and type(debug.traceback) == "function" then
            return debug.traceback(tostring(err), 2)
        end
        return tostring(err)
    end)

    if not ok then
        UI.showError("Execution failed:\n" .. tostring(result))
        return
    end

    updateStatus(
        result.n > 0 and ("Edited code executed  ·  Returns " .. result.n)
            or "Edited code executed",
        COLORS.green
    )
end

local function copyText(text, successMessage)
    if type(setclipboard) == "function" then
        setclipboard(text)
        updateStatus(successMessage, COLORS.green)
    else
        print(text)
        updateStatus("Clipboard unavailable; printed to console", COLORS.orange)
    end
end

local function setMinimized(value)
    minimized = value
    if minimized then
        previousSize = Vector2.new(window.AbsoluteSize.X, window.AbsoluteSize.Y)
        previousPosition = window.Position

        -- Keep the top edge (and therefore the header) at exactly the same
        -- screen position while a center-anchored window changes height.
        local heightDelta = (previousSize.Y - MINIMIZED_HEIGHT) * 0.5
        window.Position = UDim2.new(
            previousPosition.X.Scale,
            previousPosition.X.Offset,
            previousPosition.Y.Scale,
            previousPosition.Y.Offset - heightDelta
        )
        sidebar.Visible = false
        content.Visible = false
        resizeHandle.Visible = false
        statusLabel.Visible = false
        if authorBadge then
            authorBadge.Visible = false
        end
        minimizeButton.Image = ASSETS.restore
        window.Size = UDim2.fromOffset(
            math.max(MIN_WIDTH, previousSize.X),
            MINIMIZED_HEIGHT
        )
    else
        sidebar.Visible = true
        content.Visible = true
        resizeHandle.Visible = true
        statusLabel.Visible = true
        if authorBadge then
            authorBadge.Visible = true
        end
        minimizeButton.Image = ASSETS.minimize
        window.Size = UDim2.fromOffset(previousSize.X, previousSize.Y)
        if previousPosition then
            window.Position = previousPosition
        end
        task.defer(updateResponsiveLayout)
    end
end

local function hideCloseWarning()
    if closeOverlay then
        closeOverlay.Visible = false
    end
end

local function showCloseWarning()
    if closeOverlay then
        closeOverlay.Visible = true
    end
end

local function createCloseWarning()
    closeOverlay = Instance.new("Frame")
    closeOverlay.Name = "CloseWarning"
    closeOverlay.Size = UDim2.fromScale(1, 1)
    closeOverlay.BackgroundColor3 = COLORS.overlay
    closeOverlay.BackgroundTransparency = 0.2
    closeOverlay.BorderSizePixel = 0
    closeOverlay.Visible = false
    closeOverlay.ZIndex = 100
    closeOverlay.Parent = window
    addCorner(closeOverlay, 9)

    local dialog = Instance.new("Frame")
    dialog.AnchorPoint = Vector2.new(0.5, 0.5)
    dialog.Position = UDim2.fromScale(0.5, 0.5)
    dialog.Size = UDim2.fromOffset(330, 150)
    dialog.BackgroundColor3 = COLORS.surface
    dialog.BorderSizePixel = 0
    dialog.ZIndex = 101
    dialog.Parent = closeOverlay
    addCorner(dialog, 9)
    addStroke(dialog)

    local heading = createLabel(dialog, "Close RemoteHooker?", 17, COLORS.text)
    heading.Font = Enum.Font.SourceSansSemibold
    heading.Position = UDim2.fromOffset(18, 14)
    heading.Size = UDim2.new(1, -36, 0, 24)
    heading.ZIndex = 102

    local message = createLabel(
        dialog,
        "Captured calls will be cleared and the hook will be disabled.",
        13,
        COLORS.muted
    )
    message.Position = UDim2.fromOffset(18, 43)
    message.Size = UDim2.new(1, -36, 0, 40)
    message.TextWrapped = true
    message.TextYAlignment = Enum.TextYAlignment.Top
    message.ZIndex = 102

    local cancel = createTextButton(dialog, "Cancel")
    cancel.Position = UDim2.new(1, -206, 1, -48)
    cancel.Size = UDim2.fromOffset(92, 32)
    cancel.ZIndex = 102

    local confirm = createTextButton(dialog, "Close")
    confirm.Position = UDim2.new(1, -106, 1, -48)
    confirm.Size = UDim2.fromOffset(88, 32)
    confirm.TextColor3 = COLORS.red
    confirm.ZIndex = 102

    connect(cancel.MouseButton1Click, hideCloseWarning)
    connect(confirm.MouseButton1Click, UI.shutdown)
end

local function createActionButton(text, callback, color)
    nextActionOrder = nextActionOrder + 1

    local button = createTextButton(actionScroll, text)
    button.LayoutOrder = nextActionOrder
    button.Size = UDim2.fromOffset(112, 34)
    if color then
        button.TextColor3 = color
    end
    connect(button.MouseButton1Click, callback)
    return button
end

local function createGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    local preferredParent = playerGui

    if type(gethui) == "function" then
        local getHuiOk, hui = pcall(gethui)
        if getHuiOk and hui then
            preferredParent = hui
        end
    end

    -- local oldGui
    -- pcall(function()
    --     oldGui = preferredParent:FindFirstChild("RemoteHookerV2")
    -- end)
    -- if oldGui then
    --     pcall(function()
    --         oldGui:Destroy()
    --     end)
    -- end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = game:GetService("HttpService"):GenerateGUID(false)
    screenGui.DisplayOrder = 999999
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false

    local parented = pcall(function()
        screenGui.Parent = preferredParent
    end)
    if not parented then
        screenGui.Parent = playerGui
    end

    window = Instance.new("Frame")
    window.Name = "Window"
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.Position = UDim2.fromScale(0.5, 0.5)
    window.Size = UDim2.fromOffset(DEFAULT_SIZE.X, DEFAULT_SIZE.Y)
    window.BackgroundColor3 = COLORS.canvas
    window.BorderSizePixel = 0
    window.ClipsDescendants = true
    window.Parent = screenGui
    addCorner(window, 9)
    addStroke(window)

    topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 48)
    topBar.BackgroundColor3 = COLORS.surface
    topBar.BorderSizePixel = 0
    topBar.Parent = window

    titleLabel = createLabel(topBar, "RemoteHooker", 16, COLORS.green)
    titleLabel.Font = Enum.Font.Gotham
    titleLabel.Position = UDim2.fromOffset(14, 0)
    titleLabel.Size = UDim2.fromOffset(140, 48)
    titleGlow = nil

    statusLabel = createLabel(topBar, "Recording", 12, COLORS.muted)
    statusLabel.Position = UDim2.fromOffset(150, 0)
    statusLabel.Size = UDim2.new(1, -300, 1, 0)

    pauseButton = createIconButton(topBar, ASSETS.pause, "Pause")
    pauseButton.Size = UDim2.fromOffset(32, 32)
    pauseButton.Position = UDim2.new(1, -112, 0.5, -16)

    minimizeButton = createIconButton(topBar, ASSETS.minimize, "Minimize")
    minimizeButton.Size = UDim2.fromOffset(32, 32)
    minimizeButton.Position = UDim2.new(1, -76, 0.5, -16)

    closeButton = createIconButton(topBar, ASSETS.close, "Close")
    closeButton.Size = UDim2.fromOffset(32, 32)
    closeButton.Position = UDim2.new(1, -40, 0.5, -16)

    sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Position = UDim2.fromOffset(8, 56)
    sidebar.Size = UDim2.new(0, 220, 1, -92)
    sidebar.BackgroundTransparency = 1
    sidebar.Parent = window

    searchBox = Instance.new("TextBox")
    searchBox.Name = "Search"
    searchBox.Size = UDim2.new(1, 0, 0, 34)
    searchBox.BackgroundColor3 = COLORS.surface
    searchBox.BorderSizePixel = 0
    searchBox.ClearTextOnFocus = false
    searchBox.Font = Enum.Font.SourceSans
    searchBox.PlaceholderColor3 = COLORS.muted
    searchBox.PlaceholderText = "Search"
    searchBox.Text = ""
    searchBox.TextColor3 = COLORS.text
    searchBox.TextSize = 13
    searchBox.Parent = sidebar
    addCorner(searchBox, 6)
    addStroke(searchBox)

    local filterButton = createTextButton(sidebar, "All")
    filterButton.Position = UDim2.fromOffset(0, 40)
    filterButton.Size = UDim2.new(0.5, -3, 0, 32)

    local groupButton = createTextButton(sidebar, "Grouped")
    groupButton.Position = UDim2.new(0.5, 3, 0, 40)
    groupButton.Size = UDim2.new(0.5, -3, 0, 32)

    packetList = Instance.new("ScrollingFrame")
    packetList.Name = "Packets"
    packetList.Position = UDim2.fromOffset(0, 78)
    packetList.Size = UDim2.new(1, 0, 1, -78)
    packetList.BackgroundTransparency = 1
    packetList.BorderSizePixel = 0
    packetList.CanvasSize = UDim2.new()
    packetList.ScrollBarImageColor3 = COLORS.border
    packetList.ScrollBarThickness = 4
    packetList.Parent = sidebar

    local packetLayout = Instance.new("UIListLayout")
    packetLayout.Padding = UDim.new(0, 4)
    packetLayout.SortOrder = Enum.SortOrder.LayoutOrder
    packetLayout.Parent = packetList

    content = Instance.new("Frame")
    content.Name = "Content"
    content.Position = UDim2.fromOffset(238, 56)
    content.Size = UDim2.new(1, -246, 1, -94)
    content.BackgroundColor3 = COLORS.surface
    content.BorderSizePixel = 0
    content.Parent = window
    addCorner(content, 7)
    addStroke(content)

    codeScroll = Instance.new("ScrollingFrame")
    codeScroll.Name = "Code"
    codeScroll.Position = UDim2.fromOffset(8, 8)
    codeScroll.Size = UDim2.new(1, -16, 1, -94)
    codeScroll.BackgroundColor3 = COLORS.canvas
    codeScroll.BorderSizePixel = 0
    codeScroll.CanvasSize = UDim2.new()
    codeScroll.ScrollBarImageColor3 = COLORS.border
    codeScroll.ScrollBarThickness = 5
    codeScroll.Parent = content
    addCorner(codeScroll, 6)

    codeHighlight = Instance.new("TextLabel")
    codeHighlight.Name = "SyntaxHighlight"
    codeHighlight.BackgroundTransparency = 1
    codeHighlight.BorderSizePixel = 0
    codeHighlight.Font = Enum.Font.Code
    codeHighlight.Position = UDim2.fromOffset(8, 8)
    codeHighlight.RichText = true
    codeHighlight.Size = UDim2.new(1, -16, 1, -16)
    codeHighlight.Text = ""
    codeHighlight.TextColor3 = COLORS.text
    codeHighlight.TextSize = 13
    codeHighlight.TextWrapped = false
    codeHighlight.TextXAlignment = Enum.TextXAlignment.Left
    codeHighlight.TextYAlignment = Enum.TextYAlignment.Top
    codeHighlight.ZIndex = 1
    codeHighlight.Parent = codeScroll

    codeLabel = Instance.new("TextBox")
    codeLabel.Name = "ArgumentEditor"
    codeLabel.BackgroundTransparency = 1
    codeLabel.BorderSizePixel = 0
    codeLabel.ClearTextOnFocus = false
    codeLabel.Font = Enum.Font.Code
    codeLabel.MultiLine = true
    codeLabel.Position = UDim2.fromOffset(8, 8)
    codeLabel.RichText = false
    codeLabel.Size = UDim2.new(1, -16, 1, -16)
    codeLabel.Text = "-- Select a remote call --"
    codeLabel.TextColor3 = COLORS.text
    codeLabel.TextEditable = false
    codeLabel.TextSize = 13
    codeLabel.TextTransparency = 1
    codeLabel.TextWrapped = false
    codeLabel.TextXAlignment = Enum.TextXAlignment.Left
    codeLabel.TextYAlignment = Enum.TextYAlignment.Top
    codeLabel.ZIndex = 2
    codeLabel.Parent = codeScroll

    editorCaret = Instance.new("Frame")
    editorCaret.Name = "EditorCaret"
    editorCaret.BackgroundColor3 = COLORS.blue
    editorCaret.BorderSizePixel = 0
    editorCaret.Size = UDim2.fromOffset(2, 14)
    editorCaret.Visible = false
    editorCaret.ZIndex = 3
    editorCaret.Parent = codeScroll

    connect(codeLabel:GetPropertyChangedSignal("Text"), function()
        if editorUnlocked and not suppressEditorChange then
            editorDirty = true
        end
        refreshEditor(codeLabel.Text)
    end)

    connect(codeLabel:GetPropertyChangedSignal("CursorPosition"), refreshCaret)
    connect(codeLabel:GetPropertyChangedSignal("SelectionStart"), refreshCaret)
    connect(codeScroll:GetPropertyChangedSignal("CanvasPosition"), refreshCaret)

    refreshEditor(codeLabel.Text)

    actionScroll = Instance.new("ScrollingFrame")
    actionScroll.Name = "Actions"
    actionScroll.Position = UDim2.new(0, 8, 1, -78)
    actionScroll.Size = UDim2.new(1, -16, 0, 70)
    actionScroll.BackgroundTransparency = 1
    actionScroll.BorderSizePixel = 0
    actionScroll.CanvasSize = UDim2.new()
    actionScroll.ScrollBarImageColor3 = COLORS.border
    actionScroll.ScrollBarThickness = 4
    actionScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    actionScroll.Parent = content

    actionGrid = Instance.new("UIGridLayout")
    actionGrid.CellPadding = UDim2.fromOffset(6, 6)
    actionGrid.CellSize = UDim2.fromOffset(112, 34)
    actionGrid.FillDirection = Enum.FillDirection.Horizontal
    actionGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    actionGrid.SortOrder = Enum.SortOrder.LayoutOrder
    actionGrid.Parent = actionScroll
    nextActionOrder = 0

    createActionButton("Run code", executeSelected, COLORS.green)

    editButton = createActionButton("Edit remote", function()
        if not UI.selectedPacket then
            updateStatus("Select a remote first", COLORS.orange)
            return
        end

        editorUnlocked = not editorUnlocked
        codeLabel.TextEditable = editorUnlocked
        editButton.Text = editorUnlocked and "Lock editor" or "Edit remote"

        if editorUnlocked then
            codeLabel:CaptureFocus()
            refreshCaret()
            updateStatus("Editor unlocked", COLORS.blue)
        else
            codeLabel:ReleaseFocus()
            if editorCaret then
                editorCaret.Visible = false
            end
            updateStatus(
                editorDirty and "Editor locked · unsaved changes kept" or "Editor locked",
                editorDirty and COLORS.orange or COLORS.muted
            )
        end
    end, COLORS.blue)

    createActionButton("Clear", clearPackets, COLORS.red)

    createActionButton("Reset editor", function()
        if UI.selectedPacket then
            updateCode(utils.generateCodeStr(UI.selectedPacket))
            updateStatus("Editor reset", COLORS.muted)
        end
    end)
    createActionButton("Copy code", function()
        if UI.selectedPacket then
            copyText(codeLabel.Text, "Edited code copied")
        end
    end)
    createActionButton("Copy path", function()
        if UI.selectedPacket then
            local value = UI.selectedPacket.remoteExpression or UI.selectedPacket.path
            copyText(value, "Path copied")
        end
    end)
    createActionButton("Copy hex", function()
        if UI.selectedPacket then
            copyText(utils.getHexFromPacket(UI.selectedPacket), "Hex copied")
        end
    end)
    createActionButton("Exclude name", function()
        if UI.selectedPacket then
            settings.excludeName(UI.selectedPacket.name)
            renderPacketList()
            updateStatus("Name excluded", COLORS.orange)
        end
    end)
    createActionButton("Exclude path", function()
        if UI.selectedPacket then
            settings.excludePath(UI.selectedPacket.path)
            renderPacketList()
            updateStatus("Path excluded", COLORS.orange)
        end
    end)
    createActionButton("Reset exclusions", function()
        settings.resetExclusions()
        updateStatus("All exclusions reset", COLORS.green)
    end)
    createActionButton("Block / allow", function()
        if not UI.selectedPacket then
            return
        end

        local path = UI.selectedPacket.path
        local shouldBlock = not settings.isPathBlocked(path)
        settings.setBlocked(path, shouldBlock)
        updateStatus(
            shouldBlock and "Remote blocked" or "Remote allowed",
            shouldBlock and COLORS.red or COLORS.green
        )
    end, COLORS.red)

    createActionButton("Show trace", function()
        if not UI.selectedPacket then
            return
        end

        local trace = UI.selectedPacket.traceback or "Trace unavailable"
        updateCode("-- Traceback\n" .. trace)
    end)

    authorBadge = createTextButton(
        window,
        "made by polosa__ (click to copy)"
    )
    authorBadge.AnchorPoint = Vector2.new(0.5, 1)
    authorBadge.Position = UDim2.new(0.5, 0, 1, -5)
    authorBadge.Size = UDim2.fromOffset(226, 23)
    authorBadge.BackgroundColor3 = COLORS.surface
    authorBadge.Font = Enum.Font.Gotham
    authorBadge.TextColor3 = COLORS.muted
    authorBadge.TextSize = 11
    authorBadge.ZIndex = 10

    connect(authorBadge.MouseButton1Click, function()
        copyText("polosa__", "Author copied")
    end)

    resizeHandle = Instance.new("ImageButton")
    resizeHandle.Name = "ResizeHandle"
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.Position = UDim2.fromScale(1, 1)
    resizeHandle.Size = UDim2.fromOffset(24, 24)
    resizeHandle.BackgroundTransparency = 1
    resizeHandle.Image = ASSETS.resize
    resizeHandle.ImageColor3 = COLORS.text
    resizeHandle.ImageTransparency = 0.15
    resizeHandle.ZIndex = 20
    resizeHandle.Parent = window

    createCloseWarning()

    local dragging = false
    local dragStart
    local startPosition
    local resizing = false
    local resizeStart
    local startSize

    connect(topBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPosition = window.Position
        end
    end)

    connect(resizeHandle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            resizeStart = input.Position
            startSize = window.AbsoluteSize
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        if dragging and not minimized then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        elseif resizing and not minimized then
            local delta = input.Position - resizeStart
            window.Size = UDim2.fromOffset(
                math.max(MIN_WIDTH, startSize.X + delta.X),
                math.max(MIN_HEIGHT, startSize.Y + delta.Y)
            )
            updateResponsiveLayout()
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            resizing = false
        end
    end)

    connect(searchBox:GetPropertyChangedSignal("Text"), renderPacketList)

    local modes = { "All", "Events", "Functions", "Blocked" }
    local modeIndex = 1
    connect(filterButton.MouseButton1Click, function()
        modeIndex = modeIndex % #modes + 1
        filterMode = modes[modeIndex]
        filterButton.Text = filterMode
        renderPacketList()
    end)

    connect(groupButton.MouseButton1Click, function()
        grouped = not grouped
        groupButton.Text = grouped and "Grouped" or "Ungrouped"
        renderPacketList()
    end)

    connect(pauseButton.MouseButton1Click, function()
        UI.isRecording = not UI.isRecording
        if onRecordingChanged then
            pcall(onRecordingChanged, UI.isRecording)
        end
        setTitleState(UI.isRecording)
        updateStatus(
            UI.isRecording and "Recording" or "Paused",
            UI.isRecording and COLORS.green or COLORS.orange
        )
    end)

    connect(minimizeButton.MouseButton1Click, function()
        setMinimized(not minimized)
    end)

    connect(closeButton.MouseButton1Click, showCloseWarning)
    connect(window:GetPropertyChangedSignal("AbsoluteSize"), updateResponsiveLayout)

    setTitleState(true)
    task.defer(updateResponsiveLayout)
end

function UI.addPacket(packet)
    if not UI.isRecording or not screenGui or not screenGui.Parent then
        return
    end

    sequence = sequence + 1
    packet.sequence = sequence
    UI.packetCount = UI.packetCount + 1
    table.insert(UI.capturedPackets, 1, packet)

    if #UI.capturedPackets > settings.maxPackets then
        table.remove(UI.capturedPackets)
    end

    renderPacketList()
    updateStatus()
end

function UI.shutdown()
    UI.isRecording = false

    if onClose then
        pcall(onClose)
    end

    disconnectAll()
    if screenGui then
        screenGui:Destroy()
    end
    screenGui = nil
end

function UI.init(options)
    options = options or {}
    onClose = options.onClose
    onRecordingChanged = options.onRecordingChanged
    createGUI()
    if onRecordingChanged then
        pcall(onRecordingChanged, UI.isRecording)
    end
    updateStatus("Recording", COLORS.green)
end

return UI
