-- Central de rede: estado do relay, computadores Mosaic na rede local, chat e ping.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")

local PROTOCOL = "mosaic"
local w, h = term.getSize()
local f = ui.form()
local peers = {}

f:add(ui.label { x = 1, y = 1, w = w, text = " Rede", bg = theme.accent, fg = theme.accentFg })
local relayLine = f:add(ui.label { x = 2, y = 3, w = w - 2, text = "" })
local relayInfo = f:add(ui.label { x = 2, y = 4, w = w - 2, text = "", fg = theme.mutedFg })
f:add(ui.label { x = 2, y = 6, text = "Computadores na rede local:" })
local list = f:add(ui.list {
    x = 1, y = 7, w = w, h = h - 9,
    render = function(p)
        return string.format(" #%-4d %-16s %s", p.id, strutil.ellipsis(p.name or "?", 16), p.os or "")
    end,
})
local status = f:add(ui.label { x = 1, y = h, w = w, text = "", bg = theme.taskbarBg, fg = theme.taskbarFg })

local function refreshRelay()
    local url = settings.get("mosaic.relay.url")
    if not url or url == "" then
        relayLine.text = "Relay: nao configurado"
        relayLine.fg = theme.mutedFg
        relayInfo.text = "Configure em Configuracoes para controlar este PC de fora do jogo."
    else
        local st = mosaic.relayStatus and mosaic.relayStatus() or nil
        if st and st.connected then
            relayLine.text = "Relay: conectado"
            relayLine.fg = colors.lime
            relayInfo.text = string.format("%s | enviados %d, recebidos %d", strutil.ellipsis(url, w - 26), st.sent, st.received)
        else
            relayLine.text = "Relay: desconectado"
            relayLine.fg = colors.red
            relayInfo.text = st and tostring(st.error or "tentando reconectar...") or strutil.ellipsis(url, w - 4)
        end
    end
    f.dirty = true
end

local function scan()
    status.text = " Procurando computadores..."
    f:draw()
    local st = mosaic.netStatus and mosaic.netStatus() or nil
    if not st or not st.side then
        status.text = " Sem modem conectado. Coloque um modem no computador."
        list:setItems({})
        f.dirty = true
        return
    end
    local found = { rednet.lookup(PROTOCOL) }
    peers = {}
    for _, id in ipairs(found) do
        if type(id) == "number" and id ~= os.getComputerID() then
            rednet.send(id, { type = "ping", id = os.epoch("utc") }, PROTOCOL)
            local _, reply = rednet.receive(PROTOCOL, 1)
            local info = (type(reply) == "table" and reply.ok and reply.result) or {}
            peers[#peers + 1] = { id = id, name = info.name, os = info.os, label = info.label }
        end
    end
    list:setItems(peers)
    status.text = string.format(" %d computador(es) | modem em %s | eu: #%d %s",
        #peers, st.side, os.getComputerID(), st.name)
    f.dirty = true
end

local function ask(peer, msg)
    msg.id = os.epoch("utc")
    rednet.send(peer.id, msg, PROTOCOL)
    local from, reply
    local deadline = os.clock() + 3
    repeat
        from, reply = rednet.receive(PROTOCOL, 1)
    until (from == peer.id and type(reply) == "table" and reply.id == msg.id) or os.clock() > deadline
    if type(reply) ~= "table" then return nil, "sem resposta" end
    if not reply.ok then return nil, reply.error end
    return reply.result
end

list.onActivate = function(_, peer)
    if not peer then return end
    local actions = {
        { text = "Detalhes", run = function()
            local info, err = ask(peer, { type = "info" })
            if not info then ui.msgbox(tostring(err), "Erro") return end
            ui.msgbox(string.format("#%d %s\nEspaco livre: %s\nPerifericos: %d\nProcessos: %d\nDia %s",
                peer.id, tostring(info.name), strutil.bytes(info.free), #(info.peripherals or {}),
                info.procs or 0, tostring(info.day)), "Computador #" .. peer.id)
        end },
        { text = "Mandar recado", run = function()
            local text = ui.prompt("Mensagem:", "", "Recado")
            if text and #text > 0 then
                local ok, err = ask(peer, { type = "notify", text = text, secs = 8 })
                if not ok then ui.msgbox(tostring(err), "Erro") else mosaic.notify("Recado enviado") end
            end
        end },
        { text = "Executar Lua", run = function()
            local code = ui.prompt("Codigo Lua:", "return os.getComputerLabel()", "Remoto")
            if not code then return end
            local pass = ui.prompt("Senha do computador remoto:", "", "Senha", { mask = "*" })
            if not pass then return end
            local res, err = ask(peer, { type = "exec", code = code, password = pass })
            if not res then ui.msgbox(tostring(err), "Erro") return end
            ui.msgbox((res.output ~= "" and res.output .. "\n" or "") ..
                table.concat(res.returns or {}, "\n"), "Resultado")
        end },
        { text = "Terminal remoto", run = function()
            mosaic.launchWith({ title = "Remoto #" .. peer.id }, "/os/apps/remote.lua", tostring(peer.id))
        end },
    }
    local idx = ui.menu(actions, 4, 8, 20)
    f.dirty = true
    if idx then actions[idx].run() f.dirty = true end
end

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h - 1, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("Procurar", scan)
addBtn("Acoes", function() local p = list:getSelected() if p then list.onActivate(list, p) end end, true)
addBtn("Config", function() mosaic.launchWith({ title = "Configuracoes" }, "/os/apps/settings.lua") end, true)

f.onEvent = function(_, ev)
    if ev == "mosaic:relay_state" then refreshRelay() return true end
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 9
        status.y, status.w = h, w
        f.dirty = true
        return true
    end
end

refreshRelay()
scan()
f:run()
