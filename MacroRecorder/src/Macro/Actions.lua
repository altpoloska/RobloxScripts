-- Конструкторы действий макроса в целевом формате.
-- Каждый билдер возвращает таблицу без поля Time -- Time добавляет Recorder.

local Actions = {}

-- CFrame -> "x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22"
function Actions.encodeCFrame(cf)
	local c = { cf:GetComponents() }
	for i, v in ipairs(c) do
		c[i] = tostring(v)
	end
	return table.concat(c, ", ")
end

-- Строка Pos -> CFrame
function Actions.decodeCFrame(pos)
	local nums = {}
	for token in string.gmatch(pos, "[^,%s]+") do
		table.insert(nums, tonumber(token))
	end
	return CFrame.new(table.unpack(nums))
end

function Actions.PlaceUnit(unitName, cframe)
	return { Type = "PlaceUnit", Unit = unitName, Pos = Actions.encodeCFrame(cframe) }
end

function Actions.UpgradeUnit(unitLabel) -- unitLabel = "Bulmo - 1"
	return { Type = "UpgradeUnit", Pos = unitLabel }
end

function Actions.ChangePriority(unitLabel, prio)
	return { Type = "ChangePriority", Prio = prio, Pos = unitLabel }
end

function Actions.UseAbility(unitLabel, abilityIndex)
	return { Type = "UseAbility", Abi = abilityIndex, Pos = unitLabel }
end

function Actions.ConfirmTowerLink(unitLabel)
	return { Type = "ConfirmTowerLink", Pos = unitLabel }
end

function Actions.VoteSkip()
	return { Type = "VoteSkip" }
end

return Actions
