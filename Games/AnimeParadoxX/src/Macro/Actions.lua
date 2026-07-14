local Actions = {}

function Actions.encodePosition(position)
    assert(typeof(position) == "Vector3", "Expected Vector3")
    return string.format("%.9g, %.9g, %.9g", position.X, position.Y, position.Z)
end

function Actions.decodePosition(pos)
    if type(pos) ~= "string" then return nil, "Pos must be a string" end
    local values = {}
    for token in pos:gmatch("[^,%s]+") do
        local value = tonumber(token)
        if not value then return nil, "Pos contains a non-number: " .. token end
        values[#values + 1] = value
    end
    if #values ~= 3 then return nil, ("Vector3 must contain 3 numbers, received %d"):format(#values) end
    return Vector3.new(values[1], values[2], values[3])
end

function Actions.PlaceUnit(unitName, position, rotation, label)
    return {
        Type = "PlaceUnit",
        Unit = unitName,
        Label = label,
        Pos = Actions.encodePosition(position),
        Rotation = tonumber(rotation) or 0,
    }
end

function Actions.UpgradeUnit(label)
    return { Type = "UpgradeUnit", Pos = label }
end

function Actions.SellUnit(label)
    return { Type = "SellUnit", Pos = label }
end

return Actions
