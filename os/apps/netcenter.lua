-- Central de rede: estado do relay, computadores Mosaic na rede local, chat e ping.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")
local netx = mosaic.lib("netx")

local PROTOCOL = netx.PROTOCOL
local w, h = term.getSize()
local f = ui.form()
local peers = {}

local relayLine = f:add(ui.label { x = 2, y = 1, w = -2, text = "" })
local relayInfo = f:add(ui.label { x = 2, y = 2, w = -2, text = "", fg = theme.mutedFg })
f:add(ui.label { x = 2, y = 4, text = "Computadores na rede local:" })
local list, status, scan, refreshRelay

function refreshRelay()
    local url = settings.get("mosaic.relay.url")
    if not url or url == "" then
        relayLine.text = "Relay: nao configurado"
        relayLine.fg = theme.mutedFg
        relayInfo.text = "Configure em Configuracoes."
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

function scan()
    status.text = " Procurando computadores..."
    f:draw()
    local st = mosaic.netStatus and mosaic.netStatus() or nil
    if not st or not st.side then
        status.text = " Sem modem. Coloque um no PC."
        list:setItems({})
        f.dirty = true
        return
    end
    -- Uma transmissao e um prazo so' para a rede inteira. Antes era `rednet.lookup` e
    -- depois uma pergunta por vizinho, esperando um segundo em cada: com dez computadores
    -- a tela ficava dez segundos congelada.
    peers = netx.peers()
    list:setItems(peers)
    status.text = string.format(" %d computador(es) | modem em %s | eu: #%d %s",
        #peers, st.side, os.getComputerID(), st.name)
    f.dirty = true
end

local function ask(peer, msg)
    return netx.ask(peer.id, msg)
end

-- Ordem: a fila mede a propria altura, o rodape se ancora acima dela, a lista preenche o resto.
local bar = ui.row(f, { bottom = 0, items = {
    { text = "&Procurar", onClick = function() scan() end },
    { text = "&Acoes", alt = true, onClick = function()
        local p = list:getSelected()
        if p then list.onActivate(list, p) end
    end },
    { text = "&Config", alt = true, onClick = function()
        mosaic.launchWith({ title = "Configuracoes" }, "/os/apps/settings.lua")
    end },
} })
status = f:add(ui.label { x = 1, above = bar, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
list = f:add(ui.list {
    x = 1, y = 5, w = "fill", fillTo = status,
    render = function(p)
        return string.format(" #%-4d %-16s %s", p.id, strutil.ellipsis(p.name or "?", 16), p.os or "")
    end,
})

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
            local res, err = ask(peer, netx.assina({ type = "exec", code = code }, pass))
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

f.onEvent = function(_, ev)
    if ev == "mosaic:relay_state" then refreshRelay() return true end
    -- Sem term_resize: as ancoras do form cuidam do reposicionamento.
end

refreshRelay()
scan()
f:run()
