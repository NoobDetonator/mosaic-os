-- Scheduler de processos (coroutines cooperativas) + roteamento de eventos + API global `mosaic`.
local wm = require("kernel.wm")
local theme = require("kernel.theme")

local proc = {}
local procs, byId = {}, {}      -- procs = z-order (1 = fundo)
local nextId = 1
local dirty = true
local mouseOwner, drag
local clockTimer
local held = {}                 -- teclas seguradas (para Alt+Tab)
local exiting = false
proc.current = nil
proc.focus = nil

local SHELL = "/rom/programs/shell.lua"
local RUNNER = "/os/kernel/runner.lua"

local function pack(...) return { n = select("#", ...), ... } end

-- Som do sistema. Carregado tarde e sempre dentro de pcall: computador sem alto-falante e'
-- o caso normal, e nenhum barulho vale derrubar o compositor. O `false` marca "ja tentei e
-- nao tem", para nao repetir o require a cada janela.
local audio
local function sfx(name)
    if audio == nil then
        local ok, mod = pcall(require, "lib.audio")
        audio = ok and mod or false
    end
    if audio then pcall(audio.sfx, name) end
end

local function safeLog(name, msg)
    local h
    pcall(function()
        local path = "/os/var/log/" .. name .. ".log"
        if not fs.exists("/os/var/log") then fs.makeDir("/os/var/log") end
        if fs.exists(path) and fs.getSize(path) > 16384 then
            if fs.exists(path .. ".old") then fs.delete(path .. ".old") end
            fs.move(path, path .. ".old")
        end
        h = fs.open(path, "a")
        if h then h.writeLine(os.date() .. " " .. tostring(msg)) end
    end)
    if h then pcall(h.close) end
end
local function log(msg) safeLog("kernel", msg) end
proc.log = log

-- ---------------------------------------------------------------- foco / z-order
function proc.raise(p)
    if p.bottom then return end
    for i, q in ipairs(procs) do
        if q == p then table.remove(procs, i) break end
    end
    table.insert(procs, p)
    dirty = true
end

function proc.setFocus(p)
    if proc.focus == p then return end
    local old = proc.focus
    proc.focus = p
    if p then p.minimized = false end
    if old and old.popup and not old.dead then proc.kill(old) end
    dirty = true
end

local function refocus()
    for i = #procs, 1, -1 do
        local p = procs[i]
        if p.win and not p.minimized and not p.hidden then proc.setFocus(p) return end
    end
    proc.setFocus(nil)
end

-- ---------------------------------------------------------------- ciclo de vida
function proc.exit(p)
    if p.dead then return end
    p.dead = true
    if p.monitor then proc.toScreen(p) end
    for i, q in ipairs(procs) do
        if q == p then table.remove(procs, i) break end
    end
    byId[p.id] = nil
    if p.onExit then pcall(p.onExit, p) end
    if not p.hidden and not p.popup and not p.silent then sfx("fechar") end
    os.queueEvent("proc_exit", p.id)
    if proc.focus == p then proc.focus = nil refocus() end
    dirty = true
end

proc.kill = proc.exit

function proc.terminate(p)
    if p.noclose then return end
    if p.terminatedAt and os.clock() - p.terminatedAt < 3 then
        proc.kill(p)          -- segundo clique em 3 s: mata na marra
        return
    end
    p.terminatedAt = os.clock()
    proc.resume(p, "terminate")
end

function proc.crash(p, err)
    local tb = tostring(err)
    if debug and debug.traceback then tb = debug.traceback(p.co, tostring(err)) or tb end
    log("CRASH [" .. p.id .. " " .. tostring(p.title) .. "] " .. tb)
    safeLog("crash", tostring(p.title) .. "\n" .. tb)
    -- Um som so'. Sem o `silent`, sairiam tres: fechar do processo que caiu, erro, e abrir
    -- da janela de erro.
    p.silent = true
    sfx("erro")
    proc.exit(p)
    if p.hidden then
        wm.toast("Servico " .. tostring(p.title) .. " caiu: " .. tostring(err):sub(1, 40), 6)
        return
    end
    proc.spawn {
        title = "Erro: " .. tostring(p.title),
        silent = true,
        w = math.min(wm.W - 2, 46), h = 8,
        fn = function()
            mosaic.ui.msgbox(tostring(err), "O programa fechou com erro")
        end,
    }
end

-- Resume com filtro de evento, captura de term.redirect e isolamento de erro.
function proc.resume(p, ...)
    if p.dead then return end
    local ev = (...)
    if p.filter ~= nil and p.filter ~= ev and ev ~= "terminate" then return end
    local prevCur = proc.current
    proc.current = p
    local prevTerm = term.redirect(p.term)
    local ok, res = coroutine.resume(p.co, ...)
    p.term = term.redirect(prevTerm)
    proc.current = prevCur
    dirty = true
    if not ok then
        proc.crash(p, res)
    elseif coroutine.status(p.co) == "dead" then
        proc.exit(p)
    else
        p.filter = res
    end
end

-- ---------------------------------------------------------------- multishell compat
function proc.makeMultishell(p)
    local ms = {}
    function ms.launch(env, path, ...)
        local q = proc.spawn { env = env, runPath = path, args = pack(...), title = (fs.getName(path):gsub("%.lua$", "")) }
        return q.id
    end
    function ms.getCurrent() return proc.current and proc.current.id or p.id end
    function ms.getFocus() return proc.focus and proc.focus.id or nil end
    function ms.setFocus(id)
        local q = byId[id]
        if not q or q.hidden then return false end
        proc.raise(q) proc.setFocus(q)
        return true
    end
    function ms.getTitle(id) local q = byId[id] return q and q.title or nil end
    function ms.setTitle(id, title)
        local q = byId[id]
        if q and not q.titleLocked then q.title = tostring(title) dirty = true end
    end
    function ms.getCount()
        local n = 0
        for _, q in ipairs(procs) do if not q.hidden then n = n + 1 end end
        return n
    end
    return ms
end

-- ---------------------------------------------------------------- spawn
-- spec: { title, fn | runPath, args, env, x, y, w, h, hidden, minimized, maximized, chrome, bottom,
--         noclose, popup, term, daemon, holdOnError, titleLocked, onExit, bg, fg }
function proc.spawn(spec)
    local p = {
        id = nextId, title = spec.title or "app", args = spec.args or {},
        hidden = spec.hidden, chrome = spec.chrome ~= false, bottom = spec.bottom,
        minimized = spec.minimized, noclose = spec.noclose, popup = spec.popup,
        daemon = spec.daemon, holdOnError = spec.holdOnError, silent = spec.silent,
        titleLocked = spec.titleLocked or spec.title ~= nil,
        onExit = spec.onExit, filter = nil,
    }
    nextId = nextId + 1
    p.env = spec.env or setmetatable({}, { __index = _G })
    p.env.multishell = proc.makeMultishell(p)
    if not p.hidden then
        wm.defaultGeometry(p, spec)
        p.win = window.create(wm.canvas, p.x, wm.clientTop(p), p.w, p.h, false)
        p.win.setBackgroundColor(spec.bg or theme.clientBg)
        p.win.setTextColor(spec.fg or theme.clientFg)
        p.win.clear()
        p.win.setCursorPos(1, 1)
    end
    p.term = spec.term or p.win or wm.nullTerm
    local args = p.args
    p.co = coroutine.create(function()
        if spec.fn then return spec.fn(table.unpack(args, 1, args.n or #args)) end
        return os.run(p.env, spec.runPath, table.unpack(args, 1, args.n or #args))
    end)
    if p.bottom then table.insert(procs, 1, p) else table.insert(procs, p) end
    byId[p.id] = p
    if not p.hidden and not p.popup and not p.bottom and not spec.silent then sfx("abrir") end
    if not p.hidden and not p.minimized then proc.setFocus(p) end
    proc.resume(p)
    return p
end

-- Roda um programa (arquivo) dentro do shell da ROM, numa janela nova.
function proc.launch(path, args, spec)
    spec = spec or {}
    args = args or {}
    spec.runPath = SHELL
    spec.args = pack(RUNNER, path, table.unpack(args, 1, args.n or #args))
    spec.title = spec.title or (fs.getName(path):gsub("%.lua$", ""))
    if spec.holdOnError == nil then spec.holdOnError = true end
    return proc.spawn(spec)
end

-- Shell interativo numa janela.
function proc.launchShell(spec)
    spec = spec or {}
    spec.runPath = SHELL
    spec.args = pack()
    -- O shell da ROM so roda /rom/startup.lua quando nao tem shell pai: passamos o do boot.
    spec.env = spec.env or setmetatable({ shell = proc.parentShell }, { __index = _G })
    spec.title = spec.title or "Terminal"
    return proc.spawn(spec)
end

-- Roda uma linha de comando ("edit /home/x.lua") no shell da ROM e sai quando terminar.
function proc.runCommand(cmd, spec)
    spec = spec or {}
    local words = {}
    for word in tostring(cmd):gmatch("%S+") do words[#words + 1] = word end
    spec.runPath = SHELL
    spec.args = pack(table.unpack(words))
    spec.env = spec.env or setmetatable({ shell = proc.parentShell }, { __index = _G })
    spec.title = spec.title or words[1] or "cmd"
    return proc.spawn(spec)
end

-- Servico em segundo plano (sem janela).
function proc.daemon(name, path, args)
    return proc.launch(path, args, { title = name, hidden = true, daemon = true, holdOnError = false })
end

function proc.list() return procs end
function proc.get(id) return byId[id] end
function proc.markDirty() dirty = true end

-- ---------------------------------------------------------------- roteamento
local function broadcast(ev)
    local snap = {}
    for i = #procs, 1, -1 do snap[#snap + 1] = procs[i] end
    for _, p in ipairs(snap) do
        if not p.dead then proc.resume(p, table.unpack(ev, 1, ev.n)) end
    end
end

local function cycleFocus()
    local vis = {}
    for _, p in ipairs(procs) do
        if p.win and not p.hidden and not p.bottom and not p.popup then vis[#vis + 1] = p end
    end
    if #vis == 0 then return end
    -- vis esta em z-order; se o topo ja esta focado, vai para o mais ao fundo
    local target = vis[#vis]
    if target == proc.focus then target = vis[1] end
    proc.raise(target) proc.setFocus(target)
end

-- Cursor por teclado. Enquanto ligado, o kernel ENGOLE setas/Enter/Esc: se os apps tambem
-- vissem essas teclas, a lista rolaria junto com o cursor. O clique sai como um mouse_click
-- de verdade na fila de eventos, entao cai no mesmo caminho do mouse e nenhum app muda.
local function pointerKey(name, code, isHeld)
    local p = wm.pointer
    local step = isHeld and 3 or 1        -- tecla segurada anda mais rapido
    if name == "key" then
        if code == keys.left then p.x = math.max(1, p.x - step)
        elseif code == keys.right then p.x = math.min(wm.W, p.x + step)
        elseif code == keys.up then p.y = math.max(1, p.y - step)
        elseif code == keys.down then p.y = math.min(wm.H, p.y + step)
        elseif code == keys.enter or code == keys.numPadEnter or code == keys.space then
            -- isHeld tem que barrar: senao a repeticao do teclado dispara um clique por tique.
            if not isHeld then
                local button = (held[keys.leftShift] or held[keys.rightShift]) and 2 or 1
                os.queueEvent("mouse_click", button, p.x, p.y)
            end
        elseif code == keys.escape then
            p.on = false
        else
            return false
        end
        return true
    elseif name == "key_up" and (code == keys.enter or code == keys.numPadEnter or code == keys.space) then
        -- Sem o mouse_up o mouseOwner fica preso e todo evento seguinte vai para o alvo errado.
        local button = (held[keys.leftShift] or held[keys.rightShift]) and 2 or 1
        os.queueEvent("mouse_up", button, p.x, p.y)
        return true
    end
    return false
end

-- ---------------------------------------------------------------- telas de parede
--
-- Um app "na parede" e' um app cujo TERMINAL e' o monitor, em vez da janela dele na area de
-- trabalho. Nao passa pelo compositor: o monitor nao tem z-order, nem barra de tarefas, nem
-- janela por cima. E nao precisa mesmo - o `monitor_touch` do CC so' da clique de botao
-- direito, sem arrastar e sem soltar, entao gerenciar janelas numa parede seria capengo.
--
-- Isso funciona porque duas pecas ja existiam: `p.term` pode ser qualquer terminal (o daemon
-- do relay ja usa isso para um shell sem janela), e o `Form:draw` refaz o layout sozinho
-- quando o terminal muda de tamanho. Mandar um app para a parede e' trocar o terminal dele.

-- Rotulo curto do monitor, para caber no botao da barra de tarefas: "monitor_3" vira "3",
-- e um monitor grudado no lado vira "top".
local function monLabel(name)
    return name:match("_(%d+)$") or name:sub(1, 3)
end

function proc.monitors() return require("lib.hal").monitors() end

-- Devolve o processo que esta usando este monitor, se houver.
function proc.onMonitor(name)
    for _, p in ipairs(procs) do
        if p.monitor and p.monitor.name == name then return p end
    end
end

-- Manda o app para o monitor. Devolve true, ou false + motivo.
function proc.toMonitor(p, name)
    if not p or p.dead or p.bottom or p.hidden then return false, "esse programa nao vai" end
    local alvo
    for _, m in ipairs(proc.monitors()) do if m.name == name then alvo = m end end
    if not alvo then return false, "monitor nao encontrado" end

    local ocupado = proc.onMonitor(name)
    if ocupado and ocupado ~= p then proc.toScreen(ocupado) end
    if p.monitor then proc.toScreen(p) end

    -- Tudo em pcall: no jogo alguem quebra o bloco com o computador ligado.
    local ok = pcall(function()
        -- O monitor tem paleta PROPRIA: sem isto o app sai com as cores erradas na parede.
        -- O apps/mirror.lua ja tinha descoberto isso; o reactor.lua nunca aplicou.
        local palette = require("kernel.palette")
        if palette.enabled() then palette.apply(alvo.p) end
        alvo.scale = require("lib.hal").fitMonitor(alvo.p, 26, 8, 56)
        -- A escala muda o tamanho em caracteres, entao o que hal.monitors() mediu ja e'
        -- velho. Sem reler aqui, o menu mostraria o tamanho de antes de encaixar.
        alvo.w, alvo.h = alvo.p.getSize()
        alvo.p.setBackgroundColor(theme.appBg)
        alvo.p.setTextColor(theme.appFg)
        alvo.p.clear()
        alvo.p.setCursorPos(1, 1)
    end)
    if not ok then return false, "o monitor nao respondeu" end

    alvo.label = monLabel(name)
    p.monitor = alvo
    p.term = alvo.p
    -- term_resize para o app refazer o layout no tamanho da parede. Sem isto ele so' se
    -- ajustaria no proximo desenho, e um app parado esperando evento nunca desenharia.
    proc.resume(p, "term_resize")
    dirty = true
    return true
end

-- Traz o app de volta para a area de trabalho.
function proc.toScreen(p)
    if not p or not p.monitor then return false end
    local mon = p.monitor
    p.monitor = nil
    p.term = p.win or wm.nullTerm
    pcall(function()
        local palette = require("kernel.palette")
        -- restore usa nativePaletteColour, que e' da 1.81 e nao existe no emulador: quando
        -- ele nao da conta, devolve slot a slot pelas cores de fabrica.
        if not palette.restore(mon.p) then
            palette.restoreSlots(mon.p, palette.ccDefaults)
        end
        mon.p.setBackgroundColor(colors.black)
        mon.p.setTextColor(colors.white)
        mon.p.clear()
        mon.p.setCursorPos(1, 1)
    end)
    if not p.dead then proc.resume(p, "term_resize") end
    dirty = true
    return true
end

-- Menu da janela: clique direito no botao da barra de tarefas.
--
-- A barra de titulo nao serve de gatilho porque o botao direito nela ja redimensiona, e o
-- Windows tambem poe o menu da janela no botao da barra.
--
-- O menu e' modal (ui.dialog roda o proprio laco de eventos), entao tem que viver dentro de
-- um processo. E ele nao chama proc.toMonitor direto: manda um evento e o laco principal
-- resolve. Chamar o scheduler de dentro de uma corrotina que o scheduler esta rodando e'
-- reentrancia, e nao vale o susto por tres linhas economizadas.
function proc.windowMenu(p, x)
    if not p or p.dead then return end
    local itens, acoes = {}, {}
    for _, m in ipairs(proc.monitors()) do
        if not (p.monitor and p.monitor.name == m.name) then
            itens[#itens + 1] = { text = "Para " .. monLabel(m.name) .. " (" .. m.w .. "x" .. m.h .. ")" }
            acoes[#acoes + 1] = { "monitor", m.name }
        end
    end
    if p.monitor then
        itens[#itens + 1] = { text = "Trazer de volta" }
        acoes[#acoes + 1] = { "tela" }
    end
    if #itens == 0 then
        itens[1] = { text = "Nenhum monitor", disabled = true }
        acoes[1] = { "nada" }
    end

    local w = 12
    for _, it in ipairs(itens) do w = math.max(w, #it.text + 2) end
    w = math.min(w, wm.W)
    local h = math.min(#itens, wm.H - 2)
    local id = p.id
    proc.spawn {
        title = "Janela", chrome = false, popup = true, holdOnError = false,
        x = math.max(1, math.min(x or 1, wm.W - w + 1)), y = math.max(1, wm.H - h),
        w = w, h = h, bg = theme.appBg, fg = theme.appFg,
        fn = function()
            local idx = mosaic.ui.menu(itens, 1, 1, w)
            local a = idx and acoes[idx]
            if a and a[1] ~= "nada" then os.queueEvent("mosaic:window_menu", id, a[1], a[2]) end
        end,
    }
end

function proc.togglePointer()
    local p = wm.pointer
    p.on = not p.on
    if p.on then
        p.x, p.y = math.floor(wm.W / 2), math.floor(wm.H / 2)
        wm.toast("Cursor por teclado: setas movem, Enter clica, Esc sai", 5)
    end
    dirty = true
end

local function handleMouse(name, btn, x, y)
    if drag then
        if name == "mouse_drag" then
            wm.dragTo(drag, x, y)
        elseif name == "mouse_up" then
            if drag.resize then proc.resume(drag.p, "term_resize") end
            drag = nil
        end
        return
    end
    if mouseOwner and name ~= "mouse_click" and name ~= "mouse_scroll" then
        if not mouseOwner.dead then
            proc.resume(mouseOwner, name, btn, x - mouseOwner.x + 1, y - wm.clientTop(mouseOwner) + 1)
        end
        if name == "mouse_up" then mouseOwner = nil end
        return
    end
    local h = wm.hitTest(procs, x, y)
    -- Clique numa janela sobe e foca; cliques na taskbar sao tratados abaixo (alternam minimizar).
    if h.p and name == "mouse_click" and h.kind ~= "taskbar" then proc.raise(h.p) proc.setFocus(h.p) end
    if h.kind == "client" then
        if name == "mouse_click" then mouseOwner = h.p end
        proc.resume(h.p, name, btn, h.lx, h.ly)
    elseif name == "mouse_click" then
        if h.kind == "title" then
            if btn == 1 then
                drag = { p = h.p, ox = x - h.p.x, oy = y - h.p.y }
            elseif btn == 2 then
                drag = { p = h.p, resize = true, x0 = x, y0 = y, w0 = h.p.w, h0 = h.p.h }
            end
        elseif h.kind == "close" then
            proc.terminate(h.p)
        elseif h.kind == "min" then
            h.p.minimized = true
            refocus()
        elseif h.kind == "max" then
            wm.toggleMax(h.p)
            proc.resume(h.p, "term_resize")
        elseif h.kind == "start" then
            proc.toggleStartMenu()
        elseif h.kind == "taskbar" and h.p then
            if btn == 2 then
                proc.windowMenu(h.p, h.p and x or 1)
            elseif h.p == proc.focus and not h.p.minimized then
                h.p.minimized = true refocus()
            else
                proc.raise(h.p) proc.setFocus(h.p)
            end
        elseif h.kind == "desktop" then
            for _, p in ipairs(procs) do if p.bottom then proc.setFocus(p) break end end
        end
    end
end

function proc.toggleStartMenu()
    if proc.startMenu and not proc.startMenu.dead then
        proc.kill(proc.startMenu)
        proc.startMenu = nil
        return
    end
    local h = math.max(4, wm.H - 2)
    local w = math.min(wm.W, 24)
    proc.startMenu = proc.launch("/os/apps/launcher.lua", {}, {
        title = "Iniciar", chrome = false, popup = true, x = 1, y = wm.H - h, w = w, h = h,
        holdOnError = false, bg = theme.appBg, fg = theme.appFg,
    })
end

-- Um passo do kernel: renderiza se preciso, espera um evento e roteia.
function proc.step()
    if dirty or wm.hasToasts() then wm.render(procs, proc.focus) dirty = false end
    local ev = pack(os.pullEventRaw())
    local name = ev[1]
    if name == "timer" and ev[2] == clockTimer then
        clockTimer = os.startTimer(1)
        dirty = true
    elseif name == "term_resize" then
        if wm.resize() then
            for _, p in ipairs(procs) do
                if p.win then
                    if p.bottom then p.w, p.h = wm.W, wm.H - 1 end
                    if p.maximized then p.w, p.h = wm.W, wm.H - 1 - (p.chrome and 1 or 0) end
                    wm.apply(p)
                end
            end
        end
        broadcast(ev)
    elseif name == "key" or name == "key_up" then
        -- Evento de tecla sem codigo existe (o CraftOS-PC manda um ao ganhar foco) e nao pode
        -- derrubar o kernel inteiro.
        if ev[2] ~= nil then held[ev[2]] = (name == "key") or nil end
        local alt = held[keys.leftAlt] or held[keys.rightAlt]
        local ctrl = held[keys.leftCtrl] or held[keys.rightCtrl]
        -- Atalhos do sistema. Ctrl+T, Ctrl+R e Ctrl+S ficam de fora de proposito: o proprio CC
        -- os intercepta quando segurados, e reinicia ou desliga o computador.
        if name == "key" and alt and ev[2] == keys.m then
            proc.togglePointer()
        elseif wm.pointer.on and pointerKey(name, ev[2], ev[3]) then
            dirty = true
        elseif name == "key" and alt and ev[2] == keys.tab then
            cycleFocus()
        elseif name == "key" and ctrl and ev[2] == keys.escape then
            proc.toggleStartMenu()
        elseif name == "key" and alt and ev[2] == keys.f4 then
            if proc.focus then proc.terminate(proc.focus) end
        elseif proc.focus then
            proc.resume(proc.focus, table.unpack(ev, 1, ev.n))
        end
    elseif name == "char" or name == "paste" or name == "terminate" or name == "file_transfer" then
        if proc.focus then proc.resume(proc.focus, table.unpack(ev, 1, ev.n)) end
    elseif name == "mouse_click" or name == "mouse_up" or name == "mouse_drag" or name == "mouse_scroll" then
        handleMouse(name, ev[2], ev[3], ev[4])
        dirty = true
    elseif name == "mosaic:window_menu" then
        local alvo = byId[ev[2]]
        if alvo then
            if ev[3] == "monitor" then
                local ok, err = proc.toMonitor(alvo, ev[4])
                if not ok then wm.toast(err or "nao deu", 4) end
            elseif ev[3] == "tela" then
                proc.toScreen(alvo)
            end
        end
    elseif name == "monitor_touch" then
        -- Toque na parede vira clique no app daquele monitor. Coordenada sai igual: o app
        -- ocupa a tela inteira, entao nao ha janela para descontar.
        --
        -- O foco do TECLADO nao muda de proposito. Quem toca a parede pode estar digitando
        -- noutra janela no computador, e roubar o foco mandaria as letras para o lugar
        -- errado. Alem disso o monitor so' manda clique: nao existe arrastar nem soltar.
        local alvo = proc.onMonitor(ev[2])
        if alvo then proc.resume(alvo, "mouse_click", 1, ev[3], ev[4]) end
    elseif name == "monitor_resize" then
        local alvo = proc.onMonitor(ev[2])
        if alvo and alvo.monitor then
            local ok, w, h = pcall(function() return alvo.monitor.p.getSize() end)
            if ok then alvo.monitor.w, alvo.monitor.h = w, h end
            proc.resume(alvo, "term_resize")
        end
    elseif name == "peripheral_detach" then
        -- Alguem quebrou o bloco com o computador ligado. O app volta para a area de
        -- trabalho em vez de escrever num monitor que nao existe mais.
        local alvo = proc.onMonitor(ev[2])
        if alvo then
            alvo.monitor = nil          -- some antes do toScreen: o monitor nao responde mais
            alvo.term = alvo.win or wm.nullTerm
            if not alvo.dead then proc.resume(alvo, "term_resize") end
            wm.toast("O monitor sumiu: " .. tostring(alvo.title) .. " voltou para a tela", 5)
            dirty = true
        end
        broadcast(ev)
    else
        broadcast(ev)
    end
    return not exiting and #procs > 0
end

function proc.run()
    while proc.step() do end
end

function proc.init()
    clockTimer = os.startTimer(1)
end

-- ---------------------------------------------------------------- API global `mosaic`
local api = {}
proc.api = api
api.version = require("version")
api.theme = theme
api.wm = wm
api.proc = proc

function api.launch(path, ...) return proc.launch(path, pack(...)).id end
function api.launchWith(spec, path, ...) return proc.launch(path, pack(...), spec).id end
function api.shell() return proc.launchShell().id end
function api.spawn(spec) return proc.spawn(spec).id end
function api.current() return proc.current and proc.current.id end
function api.focused() return proc.focus and proc.focus.id end
function api.list()
    local out = {}
    for i = #procs, 1, -1 do
        local p = procs[i]
        out[#out + 1] = {
            id = p.id, title = p.title, hidden = p.hidden or false, minimized = p.minimized or false,
            focused = p == proc.focus, daemon = p.daemon or false, filter = p.filter,
            x = p.x, y = p.y, w = p.w, h = p.h,
        }
    end
    return out
end
function api.kill(id) local p = byId[id] if p then proc.kill(p) return true end return false end
function api.terminate(id) local p = byId[id] if p then proc.terminate(p) return true end return false end
function api.focus(id)
    local p = byId[id]
    if p and not p.hidden then proc.raise(p) proc.setFocus(p) return true end
    return false
end
function api.minimize(id)
    local p = byId[id or (proc.current and proc.current.id)]
    if p then p.minimized = true if proc.focus == p then refocus() end return true end
    return false
end
function api.setTitle(id, t)
    local p = byId[id or (proc.current and proc.current.id)]
    if p then p.title = tostring(t) p.titleLocked = true dirty = true end
end
function api.holdOnError() return proc.current and proc.current.holdOnError or false end
function api.notify(text, secs) wm.toast(text, secs) dirty = true end
function api.screenshot() return wm.screenshot() end
function api.screenshotText() return wm.screenshotText() end
-- Tamanho da TELA, nao da janela. term.getSize() dentro de um app devolve a janela dele,
-- entao quem precisa se situar na tela inteira (a taskbar esta na ultima linha, por exemplo)
-- nao tinha como saber.
function api.screenSize() return wm.W, wm.H end
function api.redraw() dirty = true end
function api.daemon(name, path, ...) return proc.daemon(name, path, pack(...)).id end
function api.exitToShell() exiting = true end
function api.shutdown() os.shutdown() end
function api.reboot() os.reboot() end
function api.startMenu() proc.toggleStartMenu() end
function api.log(msg) log(msg) end
function api.require(name) return require(name) end   -- modulos kernel/lib com cache unico
function api.lib(name) return require("lib." .. name) end
function api.emit(name, ...) os.queueEvent("mosaic:" .. name, ...) end
function api.isTiny() return wm.tiny end
function api.altHeld() return (held[keys.leftAlt] or held[keys.rightAlt]) and true or false end
-- O CC manda `key` com o codigo da tecla, sem dizer quais modificadores estao segurados:
-- quem quer Ctrl+C precisa perguntar. (Ctrl+T, Ctrl+R e Ctrl+S sao do proprio CC.)
function api.ctrlHeld() return (held[keys.leftCtrl] or held[keys.rightCtrl]) and true or false end
function api.pointer() return wm.pointer end
function api.togglePointer() proc.togglePointer() end

_G.mosaic = api
return proc
