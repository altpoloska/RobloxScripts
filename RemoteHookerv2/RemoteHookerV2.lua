-- Bundled by luabundle {"version":"1.7.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
local network = require("src/network")
local ui = require("src/ui")

if setthreadidentity then
    pcall(setthreadidentity, 2)
end

ui.init({
    onClose = network.shutdown,
    onRecordingChanged = network.setRecording,
})
local ok, err = network.init(ui.addPacket)
if ok then
    print("[RemoteHooker] Loaded successfully")
else
    ui.showError("Capture unavailable: " .. tostring(err))
    warn("[RemoteHooker] Loaded without capture:", err)
end

return { network = network, ui = ui }

end)
__bundle_register("src/ui", function(require, _LOADED, __bundle_register, __bundle_modules)
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
    resizeHandle.Size = UDim2.fromOffset(28, 28)
    resizeHandle.BackgroundTransparency = 1
    resizeHandle.Image = ASSETS.resize
    resizeHandle.ImageColor3 = COLORS.text
    resizeHandle.ImageTransparency = 0.1
    resizeHandle.ZIndex = 20
    resizeHandle.Parent = window

    -- A high-contrast corner marker makes the resize affordance obvious even
    -- when the built-in Studio texture is faint in the current experience.
    local resizeCorner = Instance.new("TextLabel")
    resizeCorner.Name = "CornerIndicator"
    resizeCorner.Size = UDim2.fromScale(1, 1)
    resizeCorner.BackgroundTransparency = 1
    resizeCorner.BorderSizePixel = 0
    resizeCorner.Font = Enum.Font.GothamBold
    resizeCorner.Text = "◢"
    resizeCorner.TextColor3 = COLORS.text
    resizeCorner.TextSize = 19
    resizeCorner.TextTransparency = 0.05
    resizeCorner.ZIndex = 21
    resizeCorner.Parent = resizeHandle

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

end)
__bundle_register("src/utils", function(require, _LOADED, __bundle_register, __bundle_modules)
local utils = {}

local function luaString(value)
    local out = {'"'}
    for i = 1, #value do
        local byte = string.byte(value, i)
        if byte == 34 then out[#out + 1] = '\\"'
        elseif byte == 92 then out[#out + 1] = '\\\\'
        elseif byte == 10 then out[#out + 1] = '\\n'
        elseif byte == 13 then out[#out + 1] = '\\r'
        elseif byte == 9 then out[#out + 1] = '\\t'
        elseif byte < 32 or byte > 126 then out[#out + 1] = string.format('\\%03d', byte)
        else out[#out + 1] = string.char(byte) end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function richEscape(value)
    return tostring(value):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'):gsub("'", '&apos;')
end

local colors = { keyword='#FF79C6', name='#8BE9FD', string='#F1FA8C', number='#FFB86C', bool='#BD93F9', fn='#50FA7B', note='#7D8590', error='#FF6B6B' }
local function paint(text, role, plain)
    if plain then return text end
    return '<font color="' .. colors[role] .. '">' .. richEscape(text) .. '</font>'
end

local function safeNameExpression(parent, name)
    return parent .. ':WaitForChild(' .. luaString(name) .. ')'
end

function utils.instanceExpression(instance, plain)
    if typeof(instance) ~= 'Instance' then return 'nil --[[ invalid Instance ]]' end
    local chain, current = {}, instance
    while current and current ~= game do
        table.insert(chain, 1, current)
        current = current.Parent
    end
    if current ~= game or #chain == 0 then return 'nil --[[ detached Instance ]]' end

    local first = chain[1]
    local expression
    local ok, service = pcall(function() return game:GetService(first.ClassName) end)
    if ok and service == first then
        expression = 'game:GetService(' .. luaString(first.ClassName) .. ')'
    else
        expression = safeNameExpression('game', first.Name)
    end
    for i = 2, #chain do expression = safeNameExpression(expression, chain[i].Name) end
    return expression
end

function utils.snapshot(value, state, decoder)
    state = state or { seen = {}, depth = 0, count = 0 }
    local kind = typeof(value)
    if kind == 'buffer' then
        if decoder then
            local ok, decoded = pcall(decoder, value)
            if ok then return utils.snapshot(decoded, state, nil) end
        end
        local ok, copy = pcall(function()
            local target = buffer.create(buffer.len(value))
            buffer.copy(target, 0, value, 0, buffer.len(value))
            return target
        end)
        return ok and copy or value
    end
    if kind ~= 'table' then return value end
    if state.seen[value] then return '<cyclic reference>' end
    if state.depth >= 10 or state.count >= 2000 then return '<snapshot limit>' end
    local result = {}
    state.seen[value] = result
    local child = { seen = state.seen, depth = state.depth + 1, count = state.count }
    for key, item in pairs(value) do
        child.count = child.count + 1
        if child.count > 2000 then result['<truncated>'] = true
        break end
        result[utils.snapshot(key, child, decoder)] = utils.snapshot(item, child, decoder)
    end
    state.seen[value] = nil
    return result
end

function utils.snapshotArgs(packed, decoder)
    local result = { n = packed.n }
    for i = 1, packed.n do result[i] = utils.snapshot(packed[i], nil, decoder) end
    return result
end

local constructors = {
    Vector2 = function(v) return ('Vector2.new(%s, %s)'):format(v.X, v.Y) end,
    Vector3 = function(v) return ('Vector3.new(%s, %s, %s)'):format(v.X, v.Y, v.Z) end,
    Color3 = function(v) return ('Color3.new(%s, %s, %s)'):format(v.R, v.G, v.B) end,
    UDim = function(v) return ('UDim.new(%s, %s)'):format(v.Scale, v.Offset) end,
    UDim2 = function(v) return ('UDim2.new(%s, %s, %s, %s)'):format(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset) end,
    Rect = function(v) return ('Rect.new(%s, %s, %s, %s)'):format(v.Min.X, v.Min.Y, v.Max.X, v.Max.Y) end,
    Ray = function(v)
        return (
            'Ray.new(Vector3.new(%s, %s, %s), Vector3.new(%s, %s, %s))'
        ):format(
            v.Origin.X,
            v.Origin.Y,
            v.Origin.Z,
            v.Direction.X,
            v.Direction.Y,
            v.Direction.Z
        )
    end,
    BrickColor = function(v) return 'BrickColor.new(' .. luaString(v.Name) .. ')' end,
    NumberRange = function(v) return ('NumberRange.new(%s, %s)'):format(v.Min, v.Max) end,
}

local function serializeSequence(value, colorSequence)
    local points = {}
    for _, point in ipairs(value.Keypoints) do
        if colorSequence then
            points[#points+1] = ('ColorSequenceKeypoint.new(%s, Color3.new(%s, %s, %s))'):format(point.Time, point.Value.R, point.Value.G, point.Value.B)
        else
            points[#points+1] = ('NumberSequenceKeypoint.new(%s, %s, %s)'):format(point.Time, point.Value, point.Envelope)
        end
    end
    return (colorSequence and 'ColorSequence.new({' or 'NumberSequence.new({') .. table.concat(points, ', ') .. '})'
end

function utils.serializeValue(value, plain, state)
    state = state or { seen = {}, depth = 0, count = 0 }
    local kind = typeof(value)
    if kind == 'nil' then return paint('nil', 'keyword', plain)
    elseif kind == 'string' then return paint(luaString(value), 'string', plain)
    elseif kind == 'number' then
        local text = value ~= value and '0/0' or value == math.huge and 'math.huge' or value == -math.huge and '-math.huge' or tostring(value)
        return paint(text, 'number', plain)
    elseif kind == 'boolean' then return paint(tostring(value), 'bool', plain)
    elseif kind == 'Instance' then return paint(utils.instanceExpression(value, true), 'name', plain)
    elseif kind == 'CFrame' then
        local c = { value:GetComponents() }
        for i=1,#c do c[i]=tostring(c[i]) end
        return paint('CFrame.new(' .. table.concat(c, ', ') .. ')', 'fn', plain)
    elseif constructors[kind] then return paint(constructors[kind](value), 'fn', plain)
    elseif kind == 'EnumItem' then return paint(tostring(value), 'name', plain)
    elseif kind == 'NumberSequence' then return paint(serializeSequence(value, false), 'fn', plain)
    elseif kind == 'ColorSequence' then return paint(serializeSequence(value, true), 'fn', plain)
    elseif kind == 'buffer' then
        local ok, bytes = pcall(buffer.tostring, value)
        return paint(ok and ('buffer.fromstring(' .. luaString(bytes) .. ')') or 'nil --[[ unreadable buffer ]]', ok and 'fn' or 'error', plain)
    elseif kind == 'table' then
        if state.seen[value] then return paint('nil --[[ cyclic table ]]', 'error', plain) end
        if state.depth >= 10 or state.count >= 2000 then return paint('nil --[[ limit ]]', 'error', plain) end
        state.seen[value] = true
        local child = { seen = state.seen, depth = state.depth + 1, count = state.count }
        local rows = {}
        for key, item in pairs(value) do
            child.count = child.count + 1
            if child.count > 2000 then rows[#rows+1] = '    -- truncated'
            break end
            local keyText
            if type(key) == 'string' and key:match('^[%a_][%w_]*$') then keyText = key
            else keyText = '[' .. utils.serializeValue(key, plain, child) .. ']' end
            rows[#rows+1] = '    ' .. keyText .. ' = ' .. utils.serializeValue(item, plain, child) .. ','
        end
        state.seen[value] = nil
        return '{\n' .. table.concat(rows, '\n') .. '\n}'
    end
    return paint('nil --[[ unsupported ' .. kind .. ': ' .. tostring(value) .. ' ]]', 'error', plain)
end

function utils.formatPacket(packet, plain)
    local lines = {}
    if packet.callingScript then
        lines[#lines + 1] = '-- Calling script: ' .. packet.callingScript
    end
    if packet.blocked then
        lines[#lines + 1] = '-- BLOCKED'
    end

    local args = packet.args or packet.rawArgs
    local remote = packet.remoteExpression or 'nil --[[ remote missing ]]'
    local renderedRemote = plain and remote or paint(remote, 'name', false)
    local renderedMethod = paint(packet.method, 'fn', plain)

    if packet.argCount == 0 then
        lines[#lines + 1] = renderedRemote .. ':' .. renderedMethod .. '()'
    else
        lines[#lines + 1] =
            paint('local', 'keyword', plain)
            .. ' '
            .. paint('args', 'name', plain)
            .. ' = {'

        local containsNil = false
        for i = 1, packet.argCount do
            if args[i] == nil then
                containsNil = true
            end

            lines[#lines + 1] =
                '    ['
                .. i
                .. '] = '
                .. utils.serializeValue(args[i], plain)
                .. ','
        end

        lines[#lines + 1] = '}'
        lines[#lines + 1] = ''

        local unpackExpression = 'unpack(args)'
        if containsNil then
            unpackExpression = 'unpack(args, 1, ' .. packet.argCount .. ')'
        end

        lines[#lines + 1] =
            renderedRemote
            .. ':'
            .. renderedMethod
            .. '('
            .. unpackExpression
            .. ')'
    end

    if packet.returns then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '-- Returned:'
        for i = 1, packet.returnCount do
            lines[#lines + 1] =
                '-- ['
                .. i
                .. '] = '
                .. utils.serializeValue(packet.returns[i], plain)
        end
    end
    return table.concat(lines, '\n')
end

function utils.generateCodeStr(packet) return utils.formatPacket(packet, true) end
function utils.generateHighlightedCode(packet) return utils.formatPacket(packet, false) end

function utils.getHexFromPacket(packet)
    local rows, args = {}, packet.rawArgs or packet.args
    for i=1,packet.argCount do
        if typeof(args[i]) == 'buffer' then
            local bytes = {}
            for j=0,buffer.len(args[i])-1 do bytes[#bytes+1] = string.format('%02X', buffer.readu8(args[i], j)) end
            rows[#rows+1] = ('[%d] = %s'):format(i, table.concat(bytes))
        end
    end
    return #rows > 0 and table.concat(rows, '\n') or 'No buffers found in arguments'
end

function utils.findInstanceByPath(path)
    local current = game
    for part in string.gmatch(path or '', '[^.]+') do
        if part ~= 'game' then current = current:FindFirstChild(part)
        if not current then return nil end end
    end
    return current
end

return utils

end)
__bundle_register("src/settings", function(require, _LOADED, __bundle_register, __bundle_modules)
local settings = {
    ignoredPathPatterns = {},
    excludedNames = {},
    excludedPaths = {},
    blockedPaths = {},
    maxPackets = 500,
    maxPendingPackets = 250,
    captureCallingScript = true,
    -- Stack collection is expensive; enable only while diagnosing a call.
    captureTraceback = false,
}

local excludedPathCount = 0
local blockedPathCount = 0

local function safePath(remote)
    local ok, path = pcall(function() return remote:GetFullName() end)
    return ok and path or tostring(remote)
end

function settings.getRemoteState(remote)
    local name = remote.Name
    if settings.excludedNames[name] then
        return true, false, nil
    end

    -- Avoid GetFullName entirely while no path-based rule is configured.
    if excludedPathCount == 0
        and blockedPathCount == 0
        and #settings.ignoredPathPatterns == 0
    then
        return false, false, nil
    end

    local path = safePath(remote)
    local ignored = settings.excludedPaths[path] == true

    if not ignored then
        for _, pattern in ipairs(settings.ignoredPathPatterns) do
            local ok, matched = pcall(string.match, path, pattern)
            if ok and matched then
                ignored = true
                break
            end
        end
    end

    return ignored, settings.blockedPaths[path] == true, path
end

function settings.shouldIgnore(remote)
    local ignored = settings.getRemoteState(remote)
    return ignored
end

function settings.isBlocked(remote)
    local _, blocked = settings.getRemoteState(remote)
    return blocked
end

function settings.excludeName(name)
    settings.excludedNames[name] = true
end

function settings.excludePath(path)
    if not settings.excludedPaths[path] then
        excludedPathCount = excludedPathCount + 1
        settings.excludedPaths[path] = true
    end
end

function settings.setBlocked(path, value)
    local wasBlocked = settings.blockedPaths[path] == true
    local shouldBlock = value == true
    if wasBlocked ~= shouldBlock then
        blockedPathCount = blockedPathCount + (shouldBlock and 1 or -1)
        settings.blockedPaths[path] = shouldBlock and true or nil
    end
end

function settings.isPathBlocked(path) return settings.blockedPaths[path] == true end
function settings.resetExclusions()
    table.clear(settings.excludedNames)
    table.clear(settings.excludedPaths)
    excludedPathCount = 0
end
function settings.resetBlocks()
    table.clear(settings.blockedPaths)
    blockedPathCount = 0
end

return settings

end)
__bundle_register("src/network", function(require, _LOADED, __bundle_register, __bundle_modules)
local settings = require("src/settings")
local utils = require("src/utils")

local network = {}
local oldNamecall
local isActive = false
local initialized = false
local recordingEnabled = true
local onPacket = nil
local decoder = nil
local callDepth = 0

-- Unblocked calls are processed in batches outside __namecall. Using indices
-- avoids table.remove(1), which would shift the entire queue on every packet.
local pendingPackets = {}
local queueHead = 1
local queueTail = 0
local drainScheduled = false

function network.setDecoder(callback)
    assert(callback == nil or type(callback) == "function", "decoder must be a function or nil")
    decoder = callback
end

function network.setRecording(value)
    recordingEnabled = value ~= false
end

local function captureCallMetadata()
    local callingScript
    if settings.captureCallingScript and type(getcallingscript) == "function" then
        local ok, scriptValue = pcall(getcallingscript)
        if ok and scriptValue ~= nil then
            if typeof(scriptValue) == "Instance" then
                local pathOk, fullName = pcall(function()
                    return scriptValue:GetFullName()
                end)
                callingScript = pathOk and fullName or tostring(scriptValue)
            else
                callingScript = tostring(scriptValue)
            end
        end
    end

    local traceback
    if settings.captureTraceback and debug and type(debug.traceback) == "function" then
        local ok, trace = pcall(function()
            return debug.traceback(nil, 3)
        end)
        if ok and trace ~= nil then
            traceback = tostring(trace)
        end
    end

    return callingScript, traceback
end

local function makePacket(remote, method, rawArgs, blocked, callingScript, traceback)
    local okPath, path = pcall(function() return remote:GetFullName() end)
    local okName, name = pcall(function() return remote.Name end)
    local okExp, exp = pcall(function() return utils.instanceExpression(remote, true) end)
    local argsOk, snapshot = pcall(utils.snapshotArgs, rawArgs, decoder)

    return {
        method = method,
        name = okName and name or "Unknown",
        path = okPath and path or tostring(remote),
        remoteExpression = okExp and exp or "game",
        instance = remote,
        rawArgs = rawArgs,
        args = argsOk and snapshot or {},
        argCount = rawArgs.n,
        returns = nil,
        returnCount = 0,
        timestamp = os.clock(),
        callingScript = callingScript,
        traceback = traceback,
        blocked = blocked == true,
    }
end

local function dispatchPacket(remote, method, rawArgs, blocked, callingScript, traceback)
    if not isActive or type(onPacket) ~= "function" then
        return
    end

    callDepth = callDepth + 1
    local ok, err = pcall(function()
        onPacket(makePacket(remote, method, rawArgs, blocked, callingScript, traceback))
    end)
    callDepth = callDepth - 1

    if not ok then
        warn("[Network] Failed to capture packet:", err)
    end
end

local function drainPacketQueue()
    while queueHead <= queueTail do
        local item = pendingPackets[queueHead]
        pendingPackets[queueHead] = nil
        queueHead = queueHead + 1

        if item then
            dispatchPacket(
                item.remote,
                item.method,
                item.args,
                false,
                item.callingScript,
                item.traceback
            )
        end
    end

    queueHead = 1
    queueTail = 0
    drainScheduled = false
end

local function enqueuePacket(remote, method, rawArgs, callingScript, traceback)
    local maxPending = settings.maxPendingPackets or settings.maxPackets or 500
    if queueTail - queueHead + 1 >= maxPending then
        return
    end

    queueTail = queueTail + 1
    pendingPackets[queueTail] = {
        remote = remote,
        method = method,
        args = rawArgs,
        callingScript = callingScript,
        traceback = traceback,
    }

    if not drainScheduled then
        drainScheduled = true
        task.defer(drainPacketQueue)
    end
end

function network.init(packetCallback)
    if initialized then return false, "network hook is already initialized" end
    if type(packetCallback) ~= "function" then return false, "packet callback is required" end
    if not hookmetamethod or not getnamecallmethod or not setnamecallmethod then
        return false, "required hook functions are unavailable"
    end

    onPacket = packetCallback
    isActive = true

    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", function(self, ...)
            if not isActive or callDepth > 0 then
                return oldNamecall(self, ...)
            end

            local method = getnamecallmethod()

            if checkcaller and checkcaller() then
                return oldNamecall(self, ...)
            end

            -- Do not allocate table.pack for unrelated namecalls. This is the
            -- hottest path and should forward with the original varargs.
            local isRemoteCall = false
            if typeof(self) == "Instance" then
                local className = self.ClassName
                isRemoteCall = (method == "FireServer" and className == "RemoteEvent")
                    or (method == "InvokeServer" and className == "RemoteFunction")
            end

            if isRemoteCall then
                -- Resolve the path once for exclusions and blocking.
                local ignored, blocked = settings.getRemoteState(self)
                if not ignored then
                    if blocked then
                        if recordingEnabled then
                            local packedArgs = table.pack(...)
                            local callingScript, traceback = captureCallMetadata()
                            dispatchPacket(
                                self,
                                method,
                                packedArgs,
                                true,
                                callingScript,
                                traceback
                            )
                        end

                        setnamecallmethod(method)
                        return nil
                    elseif recordingEnabled then
                        -- Only captured calls pay for argument copying and metadata.
                        local packedArgs = table.pack(...)
                        local callingScript, traceback = captureCallMetadata()
                        enqueuePacket(self, method, packedArgs, callingScript, traceback)
                    end
                end
            end

            setnamecallmethod(method)
            return oldNamecall(self, ...)
        end)
    end)

    if not ok then
        isActive = false
        onPacket = nil
        return false, result
    end

    oldNamecall = result
    initialized = true
    print("[Network] Batched async hook installed successfully.")
    return true
end

function network.shutdown()
    isActive = false
    recordingEnabled = false
    onPacket = nil
    table.clear(pendingPackets)
    queueHead = 1
    queueTail = 0
    drainScheduled = false
    print("[Network] Capture disabled.")
end

function network.isActive()
    return isActive
end

return network

end)
return __bundle_require("__root")