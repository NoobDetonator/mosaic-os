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

local function log(msg)
    local h = fs.open("/os/var/log/kernel.log", "a")
    if h then h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg)) h.close() end
end
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
    local h = fs.open("/os/var/log/crash.log", "a")
    if h then h.writeLine(os.date() .. " " .. tostring(p.title) .. "\n" .. tb .. "\n") h.close() end
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
            if h.p == proc.focus and not h.p.minimized then
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
