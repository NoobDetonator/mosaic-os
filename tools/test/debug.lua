-- Bancada de testes: abre um app no emulador e despeja a tela em /dbg.txt.
-- Rode por `node tools/debug.js <app> [x,y ...]` (nunca direto pelo emu.js: a saida
-- se perde quando o processo chama process.exit num pipe).
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path
local args = { ... }
local target = (args[1] and #args[1] > 0) and args[1] or "/os/apps/settings.lua"

local out = fs.open("/dbg.txt", "w")
local function say(s) out.write(tostring(s) .. "\n") end

-- Argumento "fake": instala um reator do Powah de mentira, para conferir o painel
-- com dados variando sem precisar do jogo.
local fake = false
for i = 2, #args do
    if args[i] == "fake" then
        fake = true
        dofile("/test/fake-reactor.lua").instalar()
    end
end

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
    -- Com o reator falso, deixa varias amostras acumularem para o grafico ter serie.
    if fake then for _ = 1, 400 do proc.step() end end
    say("=== " .. target .. " (dead=" .. tostring(p.dead) .. ") ===")
    say(wm.screenshotText())

    -- Cliques na tela, na ordem: "12,18" vira um clique em x=12 y=18.
    for i = 2, #args do
        local x, y = args[i]:match("^(%d+),(%d+)$")
        if x then
            os.queueEvent("mouse_click", 1, tonumber(x), tonumber(y))
            os.queueEvent("mouse_up", 1, tonumber(x), tonumber(y))
            for _ = 1, 4 do proc.step() end
            say("=== apos clicar em " .. args[i] .. " ===")
            say(wm.screenshotText())
        end
    end

    for _ = 1, 20 do os.queueEvent("mouse_scroll", 1, 10, 10) proc.step() end
    say("=== apos rolar ate o fim ===")
    say(wm.screenshotText())
end)
if not ok then say("PCALL ERRO: " .. tostring(err)) end
out.close()
os.shutdown(0)
