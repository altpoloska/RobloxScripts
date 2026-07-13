local HttpService = game:GetService("HttpService")

local Config = require("Config")

local Storage = {}

function Storage.Serialize(macro)
	return HttpService:JSONEncode(macro)
end

function Storage.Deserialize(str)
	return HttpService:JSONDecode(str)
end

-- Ключи-числа идут в произвольном порядке в JSON -- сортируем по номеру.
function Storage.ToOrderedList(macro)
	local list = {}
	for key, value in pairs(macro) do
		local n = tonumber(key)
		if n and type(value) == "table" then
			table.insert(list, { index = n, action = value })
		end
	end
	table.sort(list, function(a, b) return a.index < b.index end)
	return list
end

local function hasFiles()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
end

function Storage.Save(name, macro)
	if not hasFiles() then return false, "File API unavailable" end
	if typeof(makefolder) == "function" and typeof(isfolder) == "function"
		and not isfolder(Config.FolderName) then
		makefolder(Config.FolderName)
	end
	writefile(Config.FolderName .. "/" .. name .. ".json", Storage.Serialize(macro))
	return true
end

function Storage.Load(name)
	if not hasFiles() then return nil, "File API unavailable" end
	local path = Config.FolderName .. "/" .. name .. ".json"
	if typeof(isfile) == "function" and not isfile(path) then
		return nil, "File not found"
	end
	return Storage.Deserialize(readfile(path))
end

function Storage.List()
	if typeof(listfiles) ~= "function" then return {} end
	local ok, files = pcall(listfiles, Config.FolderName)
	if not ok then return {} end
	local out = {}
	for _, path in ipairs(files) do
		local name = path:match("([^/\\]+)%.json$")
		if name then table.insert(out, name) end
	end
	return out
end

return Storage
