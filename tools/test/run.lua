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
check(line(wm.H):find("Iniciar", 1, true) ~= nil, "taskbar sem botao Iniciar: " .. line(wm.H))
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
os.queueEvent("mouse_click", 1, 3, wm.H)
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
local apps = { "files", "settings", "periph", "notes", "calc", "clock", "help", "pkg", "netcenter", "taskman", "reactor" }
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
check(require("kernel.draw").demo() == true, "self-check do kernel.draw falhou")
check(require("lib.pixel").demo() == true, "self-check do lib.pixel falhou")
check(require("lib.icons").demo() == true, "self-check do lib.icons falhou")
check(require("kernel.draw").HALF:byte() == 149, "caractere de meia celula errado")
local hal = require("lib.hal")
check(type(hal.list()) == "table", "hal.list nao devolveu tabela")
check(hal.find("chatBox") == nil, "hal.find achou periferico inexistente")
local logger = require("lib.log").open("teste")
logger:info("linha de teste")
check(#logger:tail(10) >= 1, "log nao gravou")
require("lib.httpx")
local okPixel, errPixel = pcall(require("lib.pixel").demo)
check(okPixel, "pixel.demo falhou: " .. tostring(errPixel))
local okPowah, errPowah = pcall(require("lib.powah").demo)
check(okPowah, "powah.demo falhou: " .. tostring(errPowah))
local okChart, errChart = pcall(require("lib.chart").demo)
check(okChart, "chart.demo falhou: " .. tostring(errChart))
-- O app Ajuda le /os/docs; sem isso ele abre vazio mandando "rode o Atualizar OS".
check(fs.isDir("/os/docs"), "sem /os/docs: o app Ajuda fica vazio")
local nmd = 0
for _, n in ipairs(fs.list("/os/docs") or {}) do if n:match("%.md$") then nmd = nmd + 1 end end
check(nmd >= 4, "poucos documentos em /os/docs: " .. nmd)

-- 14. Form rola quando o conteudo passa da altura da janela (era o bug do app Configuracoes)
local ui = proc.api.ui
local vw = window.create(wm.canvas, 1, 1, 20, 5, false)
local sf = ui.form { term = vw }
sf:add(ui.label { x = 1, y = 1, text = "topo" })
local fundo = sf:add(ui.button { x = 1, y = 12, text = "fundo" })
check(sf:contentHeight() == 12, "contentHeight errado: " .. sf:contentHeight())
check(sf:maxScroll(5) == 7, "maxScroll errado: " .. sf:maxScroll(5))
sf:scrollTo(999, 5)
check(sf.scroll == 7, "scrollTo nao limitou no fim: " .. tostring(sf.scroll))
sf.scroll = 0
sf:reveal(fundo)
check(sf.scroll == 7, "reveal nao trouxe o widget para a tela: " .. tostring(sf.scroll))
sf:draw()
check(vw.getLine(5):find("fundo", 1, true) ~= nil, "widget rolado nao desenhou na ultima linha")
local clicado = false
fundo.onClick = function() clicado = true end
sf:handle("mouse_click", 1, 1, 5)          -- clique na linha 5 da tela = linha 12 do conteudo
check(clicado, "clique no widget rolado nao chegou nele")
sf.scroll = 0
sf:handle("mouse_scroll", 1, 1, 3)          -- roda do mouse fora de widget rolavel = rola o form
check(sf.scroll == 1, "roda do mouse nao rolou o form: " .. tostring(sf.scroll))

-- Widget preso (pinned): fica na tela quando o resto rola. Barra de navegacao usa isso.
local fixo = sf:add(ui.button { x = 12, y = 5, text = "fixo", pinned = true })
check(sf:contentHeight() == 12, "widget preso nao devia contar na altura rolavel: " .. sf:contentHeight())
sf.scroll = 7
sf:draw()
check(vw.getLine(5):find("fixo", 1, true) ~= nil, "widget preso sumiu quando o form rolou")
local fixoClicado = false
fixo.onClick = function() fixoClicado = true end
sf:handle("mouse_click", 1, 13, 5)          -- linha 5 da TELA, com o form rolado em 7
check(fixoClicado, "clique no widget preso nao chegou nele")

-- 15. Sombra da janela: coluna a direita e linha embaixo, sem invadir a taskbar
for _, q in ipairs(proc.list()) do
    if not q.bottom and not q.hidden then proc.kill(q) end
end
pump()
local sh = colors.toBlit(theme.shadowBg)
local hs = fs.open("/sombra.lua", "w")
hs.write('os.pullEvent("key")\n')
hs.close()
local sombra = proc.launch("/sombra.lua", {}, { title = "Sombra", x = 3, y = 3, w = 10, h = 4 })
pump()
check(not sombra.dead, "processo da sombra morreu")
-- titulo na linha 3, cliente 4..7; sombra na coluna 13 (linhas 4..8) e na linha 8 (col 4..13)
local function bgAt(y, x1, x2)
    local _, _, bg = wm.canvas.getLine(y)
    return bg:sub(x1, x2 or x1)
end
check(bgAt(4, 13) == sh, "sem sombra a direita da janela: " .. bgAt(4, 13))
check(bgAt(8, 4, 13) == string.rep(sh, 10), "sem sombra embaixo da janela: " .. bgAt(8, 4, 13))
check(bgAt(3, 13) ~= sh, "sombra subiu ate a linha do titulo")
check(bgAt(4, 14) ~= sh, "sombra passou de uma coluna")
proc.kill(sombra)
pump()
-- Janela colada na base nao pode pintar sombra na taskbar
local rente = proc.launch("/sombra.lua", {}, { title = "Rente", x = 3, y = wm.H - 3, w = 10, h = 2 })
pump()
check(bgAt(wm.H, 4, 13) ~= string.rep(sh, 10), "sombra invadiu a taskbar")
proc.kill(rente)
pump()

-- 14. Navegacao por teclado
local ui = require("kernel.ui")
local label, letter, mark = ui.mnemonic("&Salvar")
check(label == "Salvar", "mnemonic devolveu rotulo errado: " .. tostring(label))
check(letter == "s", "mnemonic achou a letra errada: " .. tostring(letter))
check(mark == 1, "mnemonic marcou a posicao errada: " .. tostring(mark))
check(select(2, ui.mnemonic("Sem atalho")) == nil, "texto sem & nao pode ter atalho")
check(ui.mnemonic("A && B") == "A & B", "&& deveria virar um & literal")

-- Enter aciona o botao padrao do formulario; Esc o de cancelar.
local escolha
local kb = proc.spawn { title = "Teclado", x = 2, y = 2, w = 40, h = 8, fn = function()
    escolha = mosaic.ui.confirm("Vai?", "Teste")
end }
pump()
os.queueEvent("key", keys.escape, false)
pump()
check(escolha == false, "Esc deveria acionar o botao de cancelar (" .. tostring(escolha) .. ")")
check(kb.dead == true, "processo do dialogo nao terminou apos Esc")

-- Ctrl+Esc abre o menu Iniciar
os.queueEvent("key", keys.leftCtrl, false)
os.queueEvent("key", keys.escape, false)
pump()
if not (proc.startMenu and not proc.startMenu.dead) then snap() end
check(proc.startMenu and not proc.startMenu.dead, "Ctrl+Esc nao abriu o menu Iniciar")
os.queueEvent("key_up", keys.leftCtrl)
os.queueEvent("mouse_click", 1, wm.W - 2, 3)
pump()

-- Alt+F4 fecha a janela focada
local vitima = proc.launch("/hello.lua", {}, { title = "Vitima", x = 3, y = 3, w = 20, h = 5 })
pump()
check(proc.focus == vitima, "a janela nova deveria estar em foco")
os.queueEvent("key", keys.leftAlt, false)
os.queueEvent("key", keys.f4, false)
os.queueEvent("key_up", keys.leftAlt)
pump()
check(vitima.dead == true, "Alt+F4 nao fechou a janela focada")

-- Setas navegam os icones da area de trabalho, e Enter abre o selecionado.
-- Contar processos e' o unico jeito de ver isso de fora: os icones ficam cobertos pelas
-- janelas que os testes anteriores deixaram abertas.
proc.setFocus(desk)
local antes = #mosaic.list()
os.queueEvent("key", keys.home, false)
pump()
os.queueEvent("key", keys.enter, false)
pump()
check(not desk.dead, "area de trabalho morreu ao receber setas")
check(#mosaic.list() > antes, "Enter na area de trabalho nao abriu o icone selecionado")

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
