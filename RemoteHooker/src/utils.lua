-- src/utils.lua
local utils = {}

local function escapeString(str)
    local result = {}
    for i = 1, #str do
        local c = str:byte(i)
        if c == 0 then table.insert(result, "\\000")
        elseif c == 10 then table.insert(result, "\\n")
        elseif c == 13 then table.insert(result, "\\r")
        elseif c == 9 then table.insert(result, "\\t")
        elseif c == 92 then table.insert(result, "\\\\")
        elseif c == 34 then table.insert(result, "\\\"")
        elseif c < 32 or c > 126 then table.insert(result, string.format("\\%03d", c))
        else table.insert(result, string.char(c))
        end
    end
    return table.concat(result)
end

-- Корректно строит путь, пропуская "game" в начале и добавляя цвета
local function convertPathToGetService(path, forClipboard)
    if not path or path == "" then return "game" end
    local parts = {}
    for part in string.gmatch(path, "[^.]+") do table.insert(parts, part) end
    if #parts == 0 then return "game" end

    local startIndex = 1
    if parts[1] == "game" then startIndex = 2 end

    if startIndex > #parts then
        return forClipboard and "game" or '<font color="#8BE9FD">game</font>'
    end

    if forClipboard then
        local result = 'game:GetService("' .. parts[startIndex] .. '")'
        for i = startIndex + 1, #parts do result = result .. ':WaitForChild("' .. parts[i] .. '")' end
        return result
    else
        local result = '<font color="#8BE9FD">game</font>:<font color="#50FA7B">GetService</font>(<font color="#F1FA8C">"' .. parts[startIndex] .. '"</font>)'
        for i = startIndex + 1, #parts do result = result .. ':<font color="#50FA7B">WaitForChild</font>(<font color="#F1FA8C">"' .. parts[i] .. '"</font>)' end
        return result
    end
end

function utils.serializeValue(val, indent, forClipboard, state)
    indent = indent or "    "
    state = state or { visited = {}, depth = 0 }
    local t = typeof(val)
    forClipboard = forClipboard or false

    local function color(text, colorHex)
        return forClipboard and text or ('<font color="' .. colorHex .. '">' .. text .. '</font>')
    end

    if t == "string" then
        return color('"' .. escapeString(val) .. '"', "#F1FA8C")
    elseif t == "number" then
        return color(tostring(val), "#FFB86C")
    elseif t == "boolean" then
        return color(tostring(val), "#BD93F9")
    elseif t == "Instance" then
        local ok, res = pcall(function() return val:GetFullName() end)
        return color(ok and res or "[Instance]", "#8BE9FD")
    elseif t == "Vector3" then
        if forClipboard then
            return string.format("Vector3.new(%s, %s, %s)", val.X, val.Y, val.Z)
        else
            return '<font color="#50FA7B">Vector3.new</font>(<font color="#FFB86C">' .. val.X .. '</font>, <font color="#FFB86C">' .. val.Y .. '</font>, <font color="#FFB86C">' .. val.Z .. '</font>)'
        end
    elseif t == "CFrame" then
        local components = { val:GetComponents() }
        local values = {}
        for i = 1, #components do values[i] = tostring(components[i]) end
        local expression = "CFrame.new(" .. table.concat(values, ", ") .. ")"
        return color(expression, "#50FA7B")
    elseif t == "buffer" then
        local ok, str = pcall(function() return buffer.tostring(val, 0, buffer.len(val)) end)
        if forClipboard then
            return ok and string.format('buffer.fromstring("%s")', escapeString(str)) or "<buffer>"
        else
            return ok and string.format('<font color="#50FA7B">buffer.fromstring</font>(<font color="#F1FA8C">"%s"</font>)', escapeString(str)) or '<font color="#6272A4">&lt;buffer&gt;</font>'
        end
    elseif t == "table" then
        if state.visited[val] then return color("<cyclic table>", "#FF5555") end
        if state.depth >= 8 then return color("<max depth>", "#6272A4") end
        if next(val) == nil then return "{}" end

        state.visited[val] = true
        local childState = { visited = state.visited, depth = state.depth + 1 }
        local parts = {}
        local innerIndent = indent .. "    "
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if count > 200 then
                table.insert(parts, innerIndent .. color("-- truncated", "#6272A4"))
                break
            end
            local keyStr = typeof(k) == "number" and color("[" .. tostring(k) .. "]", "#FFB86C") or utils.serializeValue(k, innerIndent, forClipboard, childState)
            local valueStr = utils.serializeValue(v, innerIndent, forClipboard, childState)
            table.insert(parts, innerIndent .. keyStr .. " = " .. valueStr)
        end
        state.visited[val] = nil
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    else
        return color("<" .. t .. "> (" .. tostring(val) .. ")", "#6272A4")
    end
end

function utils.formatArgsTable(packet, forClipboard)
    forClipboard = forClipboard or false
    local fullPath = convertPathToGetService(packet.path, forClipboard)

    local function color(text, colorHex)
        return forClipboard and text or ('<font color="' .. colorHex .. '">' .. text .. '</font>')
    end

    local lines = {}
    table.insert(lines, color("local", "#FF79C6") .. " " .. color("args", "#8BE9FD") .. " = {")

    local argCount = packet.argCount or packet.args.n or #packet.args
    for i = 1, argCount do
        local arg = packet.args[i]
        local formatted = utils.serializeValue(arg, "    ", forClipboard)
        local indexStr = color("[" .. i .. "]", "#FFB86C")
        table.insert(lines, "    " .. indexStr .. " = " .. formatted .. ",")
    end

    table.insert(lines, "}")
    table.insert(lines, "")

    local methodStr = color(packet.method, "#50FA7B")
    local unpackStr = color("table.unpack", "#50FA7B") .. "(" .. color("args", "#8BE9FD") .. ", " .. color("1", "#FFB86C") .. ", " .. color(tostring(argCount), "#FFB86C") .. ")"

    table.insert(lines, fullPath .. ":" .. methodStr .. "(" .. unpackStr .. ")")

    return table.concat(lines, "\n")
end

function utils.getHexFromPacket(packet)
    local hexParts = {}
    local argCount = packet.argCount or packet.args.n or #packet.args
    for i = 1, argCount do
        local arg = packet.args[i]
        if typeof(arg) == "buffer" then
            local hex = ""
            for j = 0, buffer.len(arg) - 1 do hex = hex .. string.format("%02X", buffer.readu8(arg, j)) end
            table.insert(hexParts, string.format("[%d] = %s", i, hex))
        end
    end
    return #hexParts == 0 and "No buffers found in arguments" or table.concat(hexParts, "\n")
end

-- Для копирования (без тегов)
function utils.generateCodeStr(packet)
    return utils.formatArgsTable(packet, true)
end

-- Для UI (с тегами)
function utils.generateHighlightedCode(packet)
    return utils.formatArgsTable(packet, false)
end

function utils.findInstanceByPath(path)
    local parts = string.split(path, ".")
    local obj = game
    for _, part in ipairs(parts) do
        local child = obj:FindFirstChild(part)
        if not child then return nil end
        obj = child
    end
    return obj
end

return utils
