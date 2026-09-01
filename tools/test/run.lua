-- Self-check do kernel. Roda no emulador (tools/test.js) ou no CraftOS-PC (--script).
-- Injeta eventos sinteticos e verifica a tela composta. Sai com os.shutdown(0) se tudo passou.
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path

local failures, passed = {}, 0
local firstFailScreen
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failures[#failures + 1] = msg
    end
end

settings.define("mosaic.clock", { type = "string", default = "real" })
local theme = require("kernel.theme")
local wm = require("kernel.wm")
local proc = require("kernel.proc")
proc.api.ui = require("kernel.ui")
proc.parentShell = shell
wm.init(term.current())
proc.init()

-- Sentinela: processo oculto que marca quando um evento nosso ja foi processado.
-- Sem isso, eventos internos (proc_exit, timer do relogio) desalinham a contagem de passos.
local lastMarker = 0
proc.spawn { title = "sentinel", hidden = true, fn = function()
    while true do
        local _, id = os.pullEvent("test_marker")
        lastMarker = id
    end
end }

local marker = 0
local function pump(limit)
    marker = marker + 1
    local mine = marker
    os.queueEvent("test_marker", mine)
    for _ = 1, limit or 400 do
        if lastMarker >= mine then return true end
        proc.step()
    end
    return lastMarker >= mine
end

local function screen() return wm.screenshotText() end
local function line(y) return (wm.canvas.getLine(y)) end
local function snap() if not firstFailScreen then firstFailScreen = screen() end end

-- 1. Desktop como janela de fundo
local desk = proc.launch("/os/apps/desktop.lua", {}, {
    title = "Area de trabalho", chrome = false, bottom = true, noclose = true,
    x = 1, y = 1, w = wm.W, h = wm.H - 1, bg = theme.desktopBg, fg = theme.desktopFg,
})
pump()
check(not desk.dead, "desktop morreu ao iniciar")
check(line(wm.H):sub(1, 3) == " M ", "taskbar sem botao Iniciar: " .. line(wm.H))
check(screen():find("Terminal", 1, true) ~= nil, "icone Terminal nao desenhado")

-- 2. Programa simples numa janela
local h = fs.open("/hello.lua", "w")
h.write('print("ola mundo")\nos.pullEvent("key")\n')
h.close()
local p = proc.launch("/hello.lua", {}, { title = "Hello", x = 3, y = 3, w = 20, h = 5 })
pump()
check(not p.dead, "hello morreu")
check(line(3):sub(3, 8) == " Hello", "titulo da janela errado: [" .. line(3) .. "]")
check(line(4):sub(3, 11) == "ola mundo", "saida do programa nao apareceu: [" .. line(4) .. "]")
check(proc.focus == p, "janela nova nao ficou focada")
check(line(wm.H):find("Hello", 1, true) ~= nil, "taskbar nao mostra Hello")

-- 3. Arrastar pela barra de titulo
os.queueEvent("mouse_click", 1, 5, 3)
os.queueEvent("mouse_drag", 1, 10, 6)
os.queueEvent("mouse_up", 1, 10, 6)
pump()
check(p.x == 8 and p.y == 6, "arrastar falhou: x=" .. p.x .. " y=" .. p.y)
check(line(6):sub(8, 13) == " Hello", "titulo nao seguiu o arrasto: [" .. line(6) .. "]")

-- 4. Minimizar e restaurar pela taskbar
os.queueEvent("mouse_click", 1, p.x + p.w - 3, p.y)
pump()
check(p.minimized == true, "minimizar falhou")
check(line(6):sub(8, 13) ~= " Hello", "janela minimizada ainda aparece")
local slot
for _, s in ipairs(wm.slots) do if s.p == p then slot = s end end
check(slot ~= nil, "slot da taskbar sumiu")
if slot then
    os.queueEvent("mouse_click", 1, slot.x1, wm.H)
    pump()
end
check(p.minimized == false and proc.focus == p, "restaurar pela taskbar falhou")

-- 5. Teclado vai so para a janela focada; o programa termina no 'key' e a janela some
os.queueEvent("key", keys.a, false)
os.queueEvent("char", "a")
pump()
check(p.dead == true, "hello nao terminou apos tecla")
check(line(wm.H):find("Hello", 1, true) == nil, "taskbar ainda mostra Hello")
check(proc.focus == desk, "foco nao voltou para o desktop")

-- 6. Erro em programa: a janela segura a mensagem (holdOnError)
local e = fs.open("/boom.lua", "w")
e.write('error("kaboom")\n')
e.close()
local b = proc.launch("/boom.lua", {}, { title = "Boom", x = 3, y = 3, w = 30, h = 6 })
pump()
check(not b.dead, "boom fechou sem segurar o erro")
check(screen():find("kaboom", 1, true) ~= nil, "mensagem de erro nao apareceu")
os.queueEvent("mouse_click", 1, b.x + b.w - 1, b.y)   -- fechar (terminate)
pump()
check(b.dead == true, "fechar pelo x nao terminou o programa com erro")

-- 7. Crash de processo nativo (fn) vira janela de erro; o kernel continua
local c = proc.spawn { title = "Nativo", fn = function() error("falha nativa") end }
check(c.dead == true, "processo nativo com erro nao morreu")
pump()
check(screen():find("falha nativa", 1, true) ~= nil, "janela de erro do crash nao apareceu")
os.queueEvent("key", keys.enter, false)   -- botao OK
pump()
if screen():find("falha nativa", 1, true) ~= nil then snap() end
check(screen():find("falha nativa", 1, true) == nil, "janela de erro nao fechou com Enter")

-- 8. Menu Iniciar abre e fecha ao clicar fora
os.queueEvent("mouse_click", 1, 2, wm.H)
pump()
if not (proc.startMenu and not proc.startMenu.dead) then snap() end
check(proc.startMenu and not proc.startMenu.dead, "menu iniciar nao abriu")
check(screen():find("Terminal", 1, true) ~= nil, "menu iniciar sem itens")
os.queueEvent("mouse_click", 1, wm.W - 2, 3)   -- clique no desktop
pump()
check(proc.startMenu.dead == true, "menu iniciar nao fechou ao perder foco")

-- 9. Shell interativo: digita um comando
local sh = proc.launchShell { x = 2, y = 2, w = 40, h = 8 }
pump()
for ch in ("/hello.lua"):gmatch(".") do os.queueEvent("char", ch) end
os.queueEvent("key", keys.enter, false)
pump()
pump()
if screen():find("ola mundo", 1, true) == nil then snap() end
check(screen():find("ola mundo", 1, true) ~= nil, "shell nao executou o programa digitado")
check(not sh.dead, "shell fechou sozinho")

-- 10. Gerenciador de tarefas abre e lista o Terminal
local tm = proc.launch("/os/apps/taskman.lua", {}, { title = "Tarefas", x = 5, y = 4, w = 44, h = 12 })
pump()
check(not tm.dead, "taskman morreu")
if screen():find("Terminal", 1, true) == nil then snap() end
check(screen():find("Terminal", 1, true) ~= nil, "taskman nao listou o Terminal")

-- 11. Dialogo de confirmacao dentro de um app nativo
local answer
local d = proc.spawn { title = "Dlg", x = 2, y = 2, w = 40, h = 10, fn = function()
    answer = mosaic.ui.confirm("Continuar?", "Teste")
end }
pump()
if screen():find("Continuar?", 1, true) == nil then snap() end
check(screen():find("Continuar?", 1, true) ~= nil, "dialogo confirm nao apareceu")
os.queueEvent("key", keys.enter, false)   -- botao padrao = Sim
pump()
check(answer == true, "confirm nao devolveu true (" .. tostring(answer) .. ")")
check(d.dead == true, "processo do dialogo nao terminou")

-- 12. Todos os apps abrem sem quebrar
local apps = { "files", "settings", "periph", "notes", "calc", "clock", "help", "pkg", "netcenter", "taskman" }
for _, name in ipairs(apps) do
    local path = "/os/apps/" .. name .. ".lua"
    local ap = proc.launch(path, {}, { title = name, x = 2, y = 2, w = wm.W - 4, h = wm.H - 5 })
    pump()
    if ap.dead then snap() end
    check(not ap.dead, "app " .. name .. " fechou sozinho ao abrir")
    proc.kill(ap)
    pump()
end

-- 13. Bibliotecas carregam e funcionam
local strutil = require("lib.strutil")
check(strutil.bytes(2048) == "2.0 KB", "strutil.bytes errado: " .. strutil.bytes(2048))
check(strutil.short(1500000) == "1.50M", "strutil.short errado: " .. strutil.short(1500000))
check(strutil.duration(3725) == "1h 2m", "strutil.duration errado: " .. strutil.duration(3725))
check(strutil.itemName("minecraft:iron_ingot") == "Iron Ingot", "strutil.itemName errado")
check(#strutil.wrap("um dois tres quatro cinco", 10) == 4, "strutil.wrap errado: " .. #strutil.wrap("um dois tres quatro cinco", 10))
local fsx = require("lib.fsx")
check(fsx.write("/tmp_test.txt", "abc") == true, "fsx.write falhou")
check(fsx.read("/tmp_test.txt") == "abc", "fsx.read falhou")
check(fsx.writeJSON("/tmp_test.json", { a = 1 }) == true, "fsx.writeJSON falhou")
check(fsx.readJSON("/tmp_test.json").a == 1, "fsx.readJSON falhou")
check(fsx.uniqueName("/tmp_test.txt") == "/tmp_test (2).txt", "fsx.uniqueName errado: " .. fsx.uniqueName("/tmp_test.txt"))
local hal = require("lib.hal")
check(type(hal.list()) == "table", "hal.list nao devolveu tabela")
check(hal.find("chatBox") == nil, "hal.find achou periferico inexistente")
local logger = require("lib.log").open("teste")
logger:info("linha de teste")
check(#logger:tail(10) >= 1, "log nao gravou")
require("lib.httpx")

-- Resultado
term.redirect(term.native())
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print(string.format("Kernel self-check: %d ok, %d falhas", passed, #failures))
for _, f in ipairs(failures) do printError(" - " .. f) end
if firstFailScreen and host then
    host.print("--- tela na primeira falha ---")
    host.print(firstFailScreen)
end
os.shutdown(#failures == 0 and 0 or 1)
