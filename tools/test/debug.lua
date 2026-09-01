-- Bancada de testes: abre um app no emulador e despeja a tela em /dbg.txt.
-- Rode por `node tools/debug.js [caminho-do-app]` (nunca direto pelo emu.js: a saida
-- se perde quando o processo chama process.exit num pipe).
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path
local target = ...
target = (target and #target > 0) and target or "/os/apps/settings.lua"

local out = fs.open("/dbg.txt", "w")
local function say(s) out.write(tostring(s) .. "\n") end

local ok, err = pcall(function()
    settings.define("mosaic.clock", { type = "string", default = "real" })
    local theme = require("kernel.theme")
    local wm = require("kernel.wm")
    local proc = require("kernel.proc")
    proc.api.ui = require("kernel.ui")
    proc.parentShell = shell
    wm.init(term.current())
    proc.init()
    local p = proc.launch(target, {}, {
        title = "DBG", x = 1, y = 1, w = wm.W, h = wm.H - 2, holdOnError = true })
    os.queueEvent("timer", -1)
    for _ = 1, 3 do proc.step() end
    say("=== " .. target .. " (dead=" .. tostring(p.dead) .. ") ===")
    say(wm.screenshotText())
    -- Rola ate o fim, para ver o que fica embaixo da dobra.
    for _ = 1, 20 do os.queueEvent("mouse_scroll", 1, 10, 10) proc.step() end
    say("=== apos rolar ate o fim ===")
    say(wm.screenshotText())
end)
if not ok then say("PCALL ERRO: " .. tostring(err)) end
out.close()
os.shutdown(0)
