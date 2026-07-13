local network = require("src/network")
local ui = require("src/ui")

if setthreadidentity then
    pcall(setthreadidentity, 2)
end

ui.init({ onClose = network.shutdown })
local ok, err = network.init(ui.addPacket)
if ok then
    print("[RemoteHooker] Loaded successfully")
else
    ui.showError("Capture unavailable: " .. tostring(err))
    warn("[RemoteHooker] Loaded without capture:", err)
end

return { network = network, ui = ui }
