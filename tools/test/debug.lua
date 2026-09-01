package.path = "/os/?.lua;/os/?/init.lua;" .. package.path
local ok, err = pcall(function()
    settings.define("mosaic.clock", { type = "string", default = "real" })
    local theme = require("kernel.theme")
    local wm = require("kernel.wm")
    local proc = require("kernel.proc")
    proc.api.ui = require("kernel.ui")
    proc.parentShell = shell
    wm.init(term.current())
    proc.init()
    local target = "/os/apps/launcher.lua"
    local p = proc.launch(target, {}, { title = "DBG", x = 1, y = 1, w = wm.W, h = wm.H - 2, holdOnError = true })
    os.queueEvent("timer", -1)
    for _ = 1, 3 do proc.step() end
    host.print("=== dead=" .. tostring(p.dead) .. " ===")
    host.print(wm.screenshotText())
end)
if not ok then host.print("PCALL ERRO: " .. tostring(err)) end
os.shutdown(0)
