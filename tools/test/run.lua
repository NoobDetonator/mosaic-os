-- Self-check do kernel. Roda no emulador (tools/test.js) ou no CraftOS-PC (--script).
-- Injeta eventos sinteticos e verifica a tela composta. Sai com os.shutdown(0) se tudo passou.
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path

local failures, passed = {}, 0
local firstFailScreen
-- Fotografa a tela na PRIMEIRA falha, sozinho. Antes o snap() tinha que ser posto na mao
-- antes do check, ou seja, era preciso adivinhar qual checagem ia quebrar. E' declarado
-- aqui em cima e preenchido la' embaixo, porque `screen()` depende do wm, que ainda nao
-- existe neste ponto do arquivo.
local autoSnap
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failures[#failures + 1] = msg
        if autoSnap then autoSnap() end
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
autoSnap = snap

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

-- 8b. Clique direito no menu Iniciar abre o contexto SEM fechar o Iniciar.
-- O kernel mata o popup quando o processo perde o foco; o menu de contexto e' uma
-- janela filha do mesmo processo, e a duvida era justamente se isso bastava.
os.queueEvent("mouse_click", 1, 3, wm.H)
pump()
check(proc.startMenu and not proc.startMenu.dead, "menu iniciar nao reabriu")
os.queueEvent("mouse_click", 2, 5, 3)   -- botao 2 no primeiro item da lista
pump()
if screen():find("Criar atalho", 1, true) == nil then snap() end
check(screen():find("Criar atalho", 1, true) ~= nil, "menu de contexto do Iniciar nao apareceu")
check(not proc.startMenu.dead, "o Iniciar morreu ao abrir o proprio menu de contexto")
os.queueEvent("key", keys.escape, false)
pump()
check(screen():find("Criar atalho", 1, true) == nil, "menu de contexto nao fechou com Esc")
os.queueEvent("key", keys.escape, false)
pump()

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
local apps = { "files", "settings", "periph", "notes", "calc", "clock", "help", "pkg", "netcenter", "taskman", "reactor", "folder", "music" }
for _, name in ipairs(apps) do
    local path = "/os/apps/" .. name .. ".lua"
    local ap = proc.launch(path, {}, { title = name, x = 2, y = 2, w = wm.W - 4, h = wm.H - 5 })
    pump()
    if ap.dead then snap() end
    check(not ap.dead, "app " .. name .. " fechou sozinho ao abrir")
    -- holdOnError deixa o processo vivo mostrando o erro, entao "nao morreu" nao basta:
    -- foi assim que um erro de layout na calculadora passou batido.
    local tela = screen()
    local estourou = tela:find("attempt to") or tela:find("Pressione qualquer tecla")
    if estourou then snap() end
    check(not estourou, "app " .. name .. " abriu com erro na tela")
    proc.kill(ap)
    pump()
end

-- Demos 3D. Nao estao no registry de proposito (nao aparecem no Iniciar nem em Programas),
-- entao nao entram no laco de cima: abrem pelo caminho.
for _, nome in ipairs({ "cubo", "terreno", "modelo" }) do
    local dp = proc.launch("/os/demos/" .. nome .. ".lua", {}, { title = nome, x = 2, y = 2,
        w = wm.W - 4, h = wm.H - 5 })
    pump()
    local tela = screen()
    local ruim = tela:find("attempt to") or tela:find("Pressione qualquer tecla")
    if dp.dead or ruim then snap() end
    check(not dp.dead, "demo " .. nome .. " fechou sozinho ao abrir")
    check(not ruim, "demo " .. nome .. " abriu com erro na tela")
    proc.kill(dp)
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
check(require("lib.vector").demo() == true, "self-check do lib.vector falhou")
check(require("kernel.draw").HALF:byte() == 149, "caractere de meia celula errado")
local hal = require("lib.hal")
check(type(hal.list()) == "table", "hal.list nao devolveu tabela")
check(hal.find("chatBox") == nil, "hal.find achou periferico inexistente")
local logger = require("lib.log").open("teste")
logger:info("linha de teste")
check(#logger:tail(10) >= 1, "log nao gravou")
local okHttpx, errHttpx = pcall(require("lib.httpx").demo)
check(okHttpx, "httpx.demo falhou: " .. tostring(errHttpx))
local okPixel, errPixel = pcall(require("lib.pixel").demo)
check(okPixel, "pixel.demo falhou: " .. tostring(errPixel))
local okPowah, errPowah = pcall(require("lib.powah").demo)
check(okPowah, "powah.demo falhou: " .. tostring(errPowah))
-- As libs de arquivo: atalho, area de transferencia, propriedades e as operacoes.
-- Cada uma traz o proprio self-check; aqui so' se cobra que ele passe.
for _, nome in ipairs({ "shortcut", "clip", "props", "fileops", "expr", "mcmath", "plot", "create", "mesh", "three", "shade", "audio" }) do
    local okLib, errLib = pcall(require("lib." .. nome).demo)
    check(okLib, nome .. ".demo falhou: " .. tostring(errLib))
end
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
-- titulo na linha 3, cliente 4..7; sombra na coluna 13 (linhas 4..8) e na linha 8 (col 4..13).
-- A sombra e meia celula: a cor dela esta na FRENTE de um caractere de teletexto, e o fundo
-- guarda o que ja estava desenhado atras.
local function fgAt(y, x1, x2)
    local _, fg = wm.canvas.getLine(y)
    return fg:sub(x1, x2 or x1)
end
local function charAt(y, x)
    local text = wm.canvas.getLine(y)
    return text:sub(x, x)
end
check(fgAt(4, 13) == sh, "sem sombra a direita da janela: " .. fgAt(4, 13))
check(charAt(4, 13):byte() >= 128, "a sombra da direita nao usou meia celula")
check(fgAt(8, 4, 13) == string.rep(sh, 10), "sem sombra embaixo da janela: " .. fgAt(8, 4, 13))
check(charAt(8, 4):byte() >= 128, "a sombra de baixo nao usou terco de celula")
check(fgAt(3, 13) ~= sh, "sombra subiu ate a linha do titulo")
check(fgAt(4, 14) ~= sh, "sombra passou de uma coluna")
proc.kill(sombra)
pump()
-- Janela colada na base nao pode pintar sombra na taskbar
local rente = proc.launch("/sombra.lua", {}, { title = "Rente", x = 3, y = wm.H - 3, w = 10, h = 2 })
pump()
check(fgAt(wm.H, 4, 13) ~= string.rep(sh, 10), "sombra invadiu a taskbar")
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

-- 15. Cursor por teclado
os.queueEvent("key", keys.leftAlt, false)
os.queueEvent("key", keys.m, false)
os.queueEvent("key_up", keys.leftAlt)
pump()
check(wm.pointer.on == true, "Alt+M nao ligou o cursor por teclado")
local px, py = wm.pointer.x, wm.pointer.y
os.queueEvent("key", keys.right, false)
pump()
check(wm.pointer.x == px + 1, "seta direita nao moveu o cursor")
os.queueEvent("key", keys.down, false)
pump()
check(wm.pointer.y == py + 1, "seta baixo nao moveu o cursor")
-- tecla segurada anda mais rapido
os.queueEvent("key", keys.right, true)
pump()
check(wm.pointer.x == px + 4, "tecla segurada deveria andar 3 de uma vez")

-- Enter vira clique de verdade: mira o botao Iniciar e o menu tem de abrir.
if proc.startMenu and not proc.startMenu.dead then proc.kill(proc.startMenu) proc.startMenu = nil end
wm.pointer.x, wm.pointer.y = 3, wm.H
os.queueEvent("key", keys.enter, false)
os.queueEvent("key_up", keys.enter)
-- Dois pumps: o clique sintetico entra na fila DEPOIS do marcador deste pump, entao so e
-- processado na rodada seguinte.
pump()
pump()
if not (proc.startMenu and not proc.startMenu.dead) then snap() end
check(proc.startMenu and not proc.startMenu.dead, "Enter do cursor nao clicou no botao Iniciar")

-- Enquanto ligado, o cursor engole as setas: o app focado nao pode ve-las.
check(wm.pointer.on == true, "o cursor deveria continuar ligado")
os.queueEvent("key", keys.escape, false)
pump()
check(wm.pointer.on == false, "Esc nao desligou o cursor por teclado")

-- 16. Ancoragem e fila de botoes
local uiL = require("kernel.ui")
local anchored = proc.spawn { title = "Anc", x = 2, y = 2, w = 30, h = 10, fn = function()
    local ui = mosaic.ui
    local form = ui.form()
    local bar = ui.row(form, { bottom = 0, items = {
        { text = "Um" }, { text = "Dois" }, { text = "Tres" }, { text = "Quatro" },
        { text = "Cinco" }, { text = "Seis" },
    } })
    local rodape = form:add(ui.label { x = 1, above = bar, w = "fill", text = "rodape" })
    local lista = form:add(ui.list { x = 1, y = 1, w = "fill", fillTo = rodape, items = { "a" } })
    _G.__anc = { bar = bar, rodape = rodape, lista = lista, form = form }
    form:run()
end }
pump()
local a = _G.__anc
check(a ~= nil, "o app ancorado nao rodou")
if a then
    -- 6 botoes nao cabem em 30 colunas: a fila tem de quebrar em mais de uma linha
    check(a.bar.lines > 1, "a fila devia ter quebrado em 30 colunas (linhas=" .. a.bar.lines .. ")")
    check(a.rodape.y == a.bar.y - 1, "o rodape nao ficou logo acima da fila")
    check(a.lista.h == a.rodape.y - 1, "a lista nao preencheu ate o rodape")
    check(a.lista.w == 30, "a lista nao pegou a largura inteira: " .. a.lista.w)
    -- Nenhum botao pode passar da borda: era assim que o botao sumia antes.
    for _, b in ipairs(a.bar.buttons) do
        check(b.x + b.w - 1 <= 30, "botao " .. b.text .. " passou da borda")
    end
    -- Janela mais larga: a fila volta para uma linha so e a lista cresce.
    local altura = a.lista.h
    a.form:layout(60, 10)
    check(a.bar.lines == 1, "em 60 colunas a fila devia caber numa linha")
    check(a.lista.h > altura, "a lista devia crescer quando a fila desocupa uma linha")
end
proc.kill(anchored)
pump()

-- 17. Dialogo em janela apertada nao pode estourar
local respondeu
local tiny = proc.spawn { title = "T", x = 2, y = 2, w = 12, h = 3, fn = function()
    respondeu = mosaic.ui.confirm("Texto bem comprido que nao cabe de jeito nenhum aqui.", "Confirmar")
end }
pump()
local tela = screen()
if tela:find("Sim", 1, true) == nil then snap() end
check(tela:find("Nao", 1, true) ~= nil, "o botao Nao sumiu na janela apertada")
check(tela:find("Sim", 1, true) ~= nil, "o botao Sim sumiu na janela apertada")
-- Os botoes tem de ficar na ULTIMA linha do dialogo, com o texto acima.
local linhaBotoes, linhaTexto
do
    local NL = string.char(10)
    local y = 1
    for linha in (tela .. NL):gmatch("(.-)" .. NL) do
        if linha:find("Sim", 1, true) then linhaBotoes = y end
        if linha:find("Texto", 1, true) then linhaTexto = y end
        y = y + 1
    end
end
check(linhaTexto and linhaBotoes and linhaTexto < linhaBotoes,
    "o texto devia ficar acima dos botoes (texto=" .. tostring(linhaTexto) .. " botoes=" .. tostring(linhaBotoes) .. ")")
os.queueEvent("key", keys.escape, false)
pump()
check(respondeu == false, "Esc devia responder nao")
check(tiny.dead == true, "o dialogo apertado nao fechou")

-- 16. Arquivos: barra lateral de Lugares e Discos, e o F9 que esconde
local fl = proc.launch("/os/apps/files.lua", {}, { title = "Arquivos", x = 1, y = 1, w = wm.W, h = wm.H - 2 })
pump()
check(not fl.dead, "files morreu ao abrir")
if screen():find("Lugares", 1, true) == nil then snap() end
check(screen():find("Lugares", 1, true) ~= nil, "barra lateral sem a secao Lugares")
check(screen():find("Discos", 1, true) ~= nil, "barra lateral sem a secao Discos")
os.queueEvent("key", keys.f9, false)
pump()
check(screen():find("Lugares", 1, true) == nil, "F9 nao escondeu a barra lateral")
os.queueEvent("key", keys.f9, false)
pump()
check(screen():find("Lugares", 1, true) ~= nil, "F9 nao trouxe a barra lateral de volta")
proc.kill(fl)
pump()

-- 17. Lista: a seta nao pode travar em separador nem em cabecalho de secao.
-- Antes disto select() so recusava o indice, entao apertar para baixo em cima de um
-- separador nao fazia nada — e o menu Iniciar ja tinha um separador.
local lw = window.create(wm.canvas, 1, 1, 20, 6, false)
local lf = ui.form { term = lw }
local ll = lf:add(ui.list { x = 1, y = 1, w = 20, h = 6, items = {
    { header = true, text = "Secao" },
    { text = "um" },
    { separator = true },
    { text = "dois" },
} })
ll:select(1)
check(ll.selected == 2, "selecionar cabecalho devia cair no item seguinte: " .. tostring(ll.selected))
ll:select(3)
check(ll.selected == 4, "descer no separador devia pular para o proximo: " .. tostring(ll.selected))
ll:select(1)
check(ll.selected == 2, "subir ate o topo devia parar no item, nao no cabecalho: " .. tostring(ll.selected))

-- 18. ctrlHeld: o evento `key` do CC nao diz quais modificadores estao segurados, entao
-- quem quer Ctrl+C precisa perguntar ao kernel. Se ficar preso em true, o app passa a
-- tratar tecla solta como atalho.
os.queueEvent("key", keys.leftCtrl, false)
pump()
check(proc.api.ctrlHeld() == true, "ctrlHeld nao viu o Ctrl segurado")
os.queueEvent("key_up", keys.leftCtrl)
pump()
check(proc.api.ctrlHeld() == false, "ctrlHeld ficou preso depois do key_up")

-- 19. Foco nao pode ficar preso num widget escondido: o teclado sumiria dentro dele.
local hw2 = window.create(wm.canvas, 1, 1, 30, 6, false)
local hf = ui.form { term = hw2 }
local escondivel = hf:add(ui.list { x = 1, y = 1, w = 10, h = 4, items = { { text = "a" } } })
local outro = hf:add(ui.textbox { x = 12, y = 1, w = 10 })
hf:setFocus(escondivel)
check(hf.focused == escondivel, "nao consegui focar o primeiro widget")
escondivel.visible = false
hf:layout(30, 6)
check(hf.focused == outro, "foco ficou no widget escondido: o teclado sumiria ali dentro")

-- 20. Som: com um alto-falante ao lado, abrir e fechar janela tem que tocar.
-- Sem periferico falso isto nao teria como ser testado fora do jogo: o `peripheral` do
-- emulador devolve nil para tudo, e o CraftOS-PC headless nao cria monitor nem alto-falante.
local fake = dofile("/test/fake-periph.lua")
local spk = fake.speaker("speaker_0")
fake.instalar()

local audio = require("lib.audio")
local achados = audio.speakers()
check(#achados == 1 and achados[1].name == "speaker_0",
    "audio.speakers nao achou o alto-falante pelo nome")
check(audio.has(), "audio.has disse que nao tem alto-falante")

check(audio.sfx("abrir") == true, "sfx nao tocou com alto-falante presente")
check(#spk.notas == 1 and spk.notas[1][1] == "bell", "a nota que saiu nao e a de abrir")

-- O volume das configuracoes multiplica, e 0 tem que calar de verdade.
settings.set("mosaic.som.volume", 0)
check(audio.sfx("abrir") == false, "volume 0 deveria calar")
check(#spk.notas == 1, "tocou mesmo com volume 0")
settings.set("mosaic.som.volume", 1)

-- Integracao: o kernel toca sozinho ao abrir e ao fechar uma janela.
local antes = #spk.notas
local som = proc.launch("/os/apps/notes.lua", {}, { title = "Som", x = 2, y = 2, w = 20, h = 6 })
pump()
check(#spk.notas > antes, "abrir janela nao tocou nada")
local depoisDeAbrir = #spk.notas
proc.kill(som) pump()
check(#spk.notas > depoisDeAbrir, "fechar janela nao tocou nada")

-- Janela de servico (hidden) e menu nao podem tocar: seriam estalos sem motivo.
local mudo = #spk.notas
local oculto = proc.spawn { title = "oculto", hidden = true, fn = function() coroutine.yield() end }
pump()
check(#spk.notas == mudo, "processo escondido tocou som")
proc.kill(oculto) pump()
check(#spk.notas == mudo, "fechar processo escondido tocou som")

-- Um crash toca abrir + erro, e mais nada. Sem o `silent` sairiam quatro sons no mesmo
-- instante: abrir, fechar do que caiu, erro, e abrir da janela de erro.
local mudo2 = #spk.notas
local cai = proc.spawn { title = "Cai", fn = function() error("de proposito") end }
pump()
check(cai.dead == true, "o processo de teste nao morreu")
check(#spk.notas - mudo2 == 2,
    "crash tocou " .. (#spk.notas - mudo2) .. " sons em vez de 2 (abrir + erro)")
check(spk.notas[#spk.notas][1] == "bass", "o ultimo som de um crash tem que ser o de erro")

-- 21. Multi-tela: mandar um app para a parede.
-- Dois monitores de tamanhos diferentes, porque com um so' varios erros nao aparecem.
local mon0 = fake.monitor("monitor_0", 30, 10)
local mon1 = fake.monitor("monitor_1", 60, 20)

local hal = require("lib.hal")
local mons = hal.monitors()
check(#mons == 2, "hal.monitors nao achou os dois monitores: " .. #mons)
check(mons[1].name == "monitor_0" and mons[1].w == 30, "monitor veio sem nome ou sem tamanho")

-- A politica de escala (usada pelo reactor e pelo toMonitor): a escala 0,5 vence quando abre
-- uma tela larga, porque e' o que libera layout de duas colunas.
local escala = hal.fitMonitor(mon1, 26, 8, 56)
check(escala == 0.5, "fitMonitor devia preferir 0,5 num monitor que fica largo: " .. tostring(escala))
-- Num monitor que nao fica largo nem na menor escala, vale a MAIOR que ainda couber.
local peq = fake.monitor("monitor_x", 26, 8)
fake.instalar()
local escalaPeq = hal.fitMonitor(peq, 26, 8, 500)
check(escalaPeq >= 1, "fitMonitor encolheu demais um monitor pequeno: " .. tostring(escalaPeq))

-- App de teste que escreve o proprio tamanho: assim da para provar que ele se re-ajustou.
local ultimoClique = ""
local parede = proc.spawn { title = "Parede", x = 2, y = 2, w = 20, h = 5, fn = function()
    while true do
        local w, h = term.getSize()
        term.clear()
        term.setCursorPos(1, 1) term.write("PAREDE " .. w .. "x" .. h)
        if ultimoClique ~= "" then term.setCursorPos(1, 2) term.write(ultimoClique) end
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then ultimoClique = "CLIQUE " .. ev[3] .. "," .. ev[4] end
    end
end }
pump()
check(screen():find("PAREDE", 1, true) ~= nil, "o app de teste nao desenhou na area de trabalho")

-- Vai para a parede.
local okMon, errMon = proc.toMonitor(parede, "monitor_0")
check(okMon, "toMonitor falhou: " .. tostring(errMon))
pump()
check(parede.monitor and parede.monitor.name == "monitor_0", "o app nao registrou o monitor")
check(parede.term == mon0, "o terminal do app nao virou o monitor")

-- Desenhou LA, no tamanho de la'. O tamanho vem depois do fitMonitor, que mexe na escala.
local esperado = "PAREDE " .. parede.monitor.w .. "x" .. parede.monitor.h
check(mon0.tela():find(esperado, 1, true) ~= nil,
    "o monitor nao mostra '" .. esperado .. "'; mostra: " .. mon0.tela():sub(1, 40))
check(parede.monitor.w > 20, "o app nao ganhou area: " .. parede.monitor.w)

-- E sumiu da area de trabalho, em vez de ficar la congelado no ultimo quadro.
wm.render(proc.list(), proc.focus)
check(screen():find("PAREDE", 1, true) == nil, "o app continua desenhado na area de trabalho")
-- Mas continua na barra de tarefas, com o numero do monitor na frente. O nome pode sair
-- cortado (o botao encolhe conforme o numero de janelas), entao a cobranca e' o prefixo.
check(line(wm.H):find("0:Par", 1, true) ~= nil,
    "a barra de tarefas nao marcou em qual monitor o app esta: " .. line(wm.H))

-- Toque na parede vira clique, sem roubar o foco do teclado.
local focoAntes = proc.focus
mon0.tocar(5, 3)
pump()
check(mon0.tela():find("CLIQUE 5,3", 1, true) ~= nil,
    "o toque no monitor nao chegou no app como clique")
check(proc.focus == focoAntes, "o toque na parede roubou o foco do teclado")

-- Um monitor so' segura um app: o segundo expulsa o primeiro.
local outro = proc.spawn { title = "Outro", x = 2, y = 2, w = 20, h = 5, fn = function()
    while true do term.clear() term.setCursorPos(1, 1) term.write("OUTRO") os.pullEvent() end
end }
pump()
check(proc.toMonitor(outro, "monitor_0"), "o segundo app nao foi para o monitor")
pump()
check(parede.monitor == nil, "o primeiro app nao saiu do monitor ocupado")
check(proc.onMonitor("monitor_0") == outro, "o monitor ficou com o app errado")

-- Trocar de monitor leva o app junto e libera o anterior.
check(proc.toMonitor(outro, "monitor_1"), "nao consegui mover para o outro monitor")
pump()
check(proc.onMonitor("monitor_0") == nil, "o monitor antigo continuou ocupado")
check(outro.monitor.name == "monitor_1", "o app nao registrou o monitor novo")

-- Monitor quebrado no jogo: o app volta para a tela em vez de escrever no vazio.
os.queueEvent("peripheral_detach", "monitor_1")
pump()
check(outro.monitor == nil, "o app continuou preso a um monitor que sumiu")
check(outro.term == outro.win, "o terminal do app nao voltou para a janela")

-- E o caminho normal de volta.
check(proc.toMonitor(parede, "monitor_0"), "nao consegui mandar de volta para a parede")
pump()
check(proc.toScreen(parede), "toScreen falhou")
pump()
check(parede.monitor == nil and parede.term == parede.win, "o app nao voltou para a janela")
-- Sobe antes de conferir: a janela de erro do teste 20 continua aberta e cobre esta area.
proc.raise(parede)
wm.render(proc.list(), proc.focus)
check(screen():find("PAREDE", 1, true) ~= nil, "o app nao voltou a desenhar na area de trabalho")

-- O caminho que a pessoa usa: clique direito no botao da barra de tarefas.
local slot
for _, s in ipairs(wm.slots) do if s.p == parede then slot = s end end
check(slot ~= nil, "o app na parede sumiu da barra de tarefas")
if slot then
    os.queueEvent("mouse_click", 2, slot.x1 + 1, wm.H)
    pump()
    local tela = screen()
    check(tela:find("Para 0", 1, true) ~= nil and tela:find("Para 1", 1, true) ~= nil,
        "o menu da janela nao listou os dois monitores")
    -- Escolher a primeira linha manda para monitor_0, pelo evento que o menu dispara.
    -- Dois pumps: o menu so' enfileira o evento ao fechar, e ele entra na fila DEPOIS do
    -- marcador do primeiro pump. Com um so', o teste conferiria antes da acao acontecer.
    os.queueEvent("key", keys.enter, false)
    pump()
    pump()
    check(parede.monitor and parede.monitor.name == "monitor_0",
        "escolher no menu nao mandou o app para a parede")
end

proc.kill(parede) proc.kill(outro) pump()

-- 22. Musica: fila, preparo no relay e audio chegando no alto-falante.
-- Com http falso: o emulador nao tem rede e o CraftOS tem rede de VERDADE, e nenhum dos dois
-- serve para cobrar resposta conhecida.
local fh = fake.http()
settings.set("mosaic.relay.url", "ws://1.2.3.4:8765/ws/computer")
settings.set("mosaic.relay.token", "tk")

local md = proc.daemon("musicd", "/os/net/musicd.lua")
pump()
check(not md.dead, "o servico de musica morreu ao iniciar")
check(type(mosaic.musicStatus) == "function", "o servico nao publicou musicStatus")
check(mosaic.musicStatus().relay == true, "o servico nao viu o relay configurado")

-- O relay responde "espere" enquanto converte: a musica nao pode entrar na fila ainda, e o
-- app tem que ter o que mostrar. Foi medido: preparar leva de 20 a 60 s.
fh.responde("/api/musica", '{"id":"abc0000000000001","estado":"baixando","titulo":"Sweden","espere":true}')
os.queueEvent("mosaic:music_cmd", "add", "sweden")
pump() pump()
local sMus = mosaic.musicStatus()
check(#sMus.fila == 0, "musica entrou na fila antes de ficar pronta")
check(sMus.preparando == "baixando", "o estado de preparo nao chegou: " .. tostring(sMus.preparando))
check(sMus.termo == "Sweden", "o titulo em preparo nao chegou: " .. tostring(sMus.termo))

-- Ficou pronta: entra na fila. Dois blocos, para dar para ver o fim chegar.
fh.responde("/api/musica",
    '{"id":"abc0000000000001","titulo":"Sweden","autor":"C418","duracao":5,"blocos":2}')
-- Sem mandar "add" de novo: o servico continua perguntando sozinho enquanto o relay prepara,
-- e e' isso que se quer cobrar aqui. Mandar de novo punha a mesma musica duas vezes na fila,
-- que e' o comportamento certo para quem pede duas vezes - so' nao e' o que este teste quer.
--
-- proc.step() cru em vez de pump(): a batida do servico e' um os.startTimer, e o relogio do
-- emulador so' anda quando um timer dispara.
for _ = 1, 80 do proc.step() end
sMus = mosaic.musicStatus()
check(#sMus.fila == 1, "a musica pronta nao entrou na fila: " .. #sMus.fila)
check(sMus.fila[1] and sMus.fila[1].titulo == "Sweden", "titulo errado na fila")
check(sMus.fila[1] and sMus.fila[1].blocos == 2, "contagem de blocos errada")

-- O audio so' corre se houver decodificador. O emulador nao tem a ROM com cc.audio.dfpwm;
-- o CraftOS tem, e e' la' que esta parte roda de verdade. Sem gancho falso: um teste que
-- sempre passa nao e' teste.
local audioLib = require("lib.audio")
if audioLib.decoder() then
    local antes = spk.amostras
    fh.responde("/api/audio/", string.rep("\170", 16 * 1024))
    os.queueEvent("mosaic:music_cmd", "play")
    for _ = 1, 60 do proc.step() end
    os.queueEvent("speaker_audio_empty", "speaker_0")
    for _ = 1, 60 do proc.step() end
    check(spk.amostras > antes,
        "nenhuma amostra chegou ao alto-falante (" .. spk.amostras .. " vs " .. antes .. ")")
    local pediuAudio = false
    for _, u in ipairs(fh.pedidos) do if u:find("/api/audio/abc0000000000001/1", 1, true) then pediuAudio = true end end
    check(pediuAudio, "o servico nao pediu o primeiro pedaco de audio")
end

-- Tirar da fila e limpar.
os.queueEvent("mosaic:music_cmd", "remove", 1)
pump() pump()
check(#mosaic.musicStatus().fila == 0, "remover da fila nao funcionou")

-- Sem relay configurado o servico tem que dizer isso, e nao ficar mudo.
settings.set("mosaic.relay.url", "")
os.queueEvent("mosaic:music_cmd", "add", "qualquer")
pump() pump()
check(mosaic.musicStatus().erro ~= nil, "sem relay, o servico deveria reclamar")

proc.kill(md) pump()

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
