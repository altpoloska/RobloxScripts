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
