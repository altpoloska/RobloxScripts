local Actions = {}

function Actions.encodeCFrame(cf)
    assert(typeof(cf) == "CFrame", "Expected CFrame")
    local values = { cf:GetComponents() }
    for i, value in ipairs(values) do
        values[i] = string.format("%.9g", value)
    end
    return table.concat(values, ", ")
end

function Actions.decodeCFrame(pos)
    if type(pos) ~= "string" then
        return nil, "Pos must be a string"
    end

    local values = {}
    for token in pos:gmatch("[^,%s]+") do
        local value = tonumber(token)
        if not value then
            return nil, "Pos contains a non-number: " .. token
        end
        values[#values + 1] = value
    end

    if #values ~= 12 then
        return nil, ("CFrame must contain 12 numbers, received %d"):format(#values)
    end

    return CFrame.new(table.unpack(values))
end

function Actions.PlaceUnit(unitName, cframe, label)
    return {
        Type = "PlaceUnit",
        Unit = unitName,
        Label = label,
        Pos = Actions.encodeCFrame(cframe),
    }
end

function Actions.UpgradeUnit(label)
    return { Type = "UpgradeUnit", Pos = label }
end

function Actions.ChangePriority(label, priority)
    return { Type = "ChangePriority", Prio = priority, Pos = label }
end

function Actions.UseAbility(label, abilityIndex)
    return { Type = "UseAbility", Abi = abilityIndex, Pos = label }
end

function Actions.ConfirmTowerLink(label)
    return { Type = "ConfirmTowerLink", Pos = label }
end

function Actions.SellUnit(label)
    return { Type = "SellUnit", Pos = label }
end

function Actions.VoteSkip()
    return { Type = "VoteSkip" }
end

return Actions
