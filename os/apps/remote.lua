-- Terminal remoto: manda comandos Lua para outro computador Mosaic pela rede local.
local ui = mosaic.ui
local theme = mosaic.theme

local netx = mosaic.lib("netx")
local PROTOCOL = netx.PROTOCOL
local args = { ... }
local peerId = tonumber(args[1])
local w, h = term.getSize()
local history = {}
local senha

if not peerId then
    local s = ui.prompt("ID do computador remoto:", "", "Terminal remoto")
    peerId = tonumber(s)
    if not peerId then return end
end

mosaic.setTitle(nil, "Remoto #" .. peerId)

local f = ui.form()
local list = f:add(ui.list { x = 1, y = 1, w = w, h = h - 3, items = history, render = function(l) return " " .. l end })
f:add(ui.label { x = 1, y = h - 2, w = w, text = " Codigo Lua (Enter envia):", fg = theme.mutedFg })
local box = f:add(ui.textbox { x = 2, y = h - 1, w = w - 2 })

local function log(line)
    for _, l in ipairs(mosaic.lib("strutil").wrap(line, w - 2)) do history[#history + 1] = l end
    while #history > 300 do table.remove(history, 1) end
    list:setItems(history)
    list.selected = #history
    list:ensureVisible()
    f.dirty = true
end

local function ask(msg)
    return netx.ask(peerId, msg)
end

local function send()
    local code = box.text
    if code == "" then return end
    box:setText("")
    log("> " .. code)
    if not senha then
        senha = ui.prompt("Senha do computador #" .. peerId .. ":", "", "Senha", { mask = "*" })
        if not senha then log("(cancelado)") return end
    end
    local res, err = ask(netx.assina({ type = "exec", code = code }, senha))
    if not res then
        log("erro: " .. tostring(err))
        -- Senha errada agora chega como "assinatura invalida": e' o que o outro lado
        -- consegue dizer sem confirmar qual senha seria a certa.
        if tostring(err):find("senha") or tostring(err):find("assinatura") then senha = nil end
        return
    end
    if res.output and res.output ~= "" then log(res.output) end
    for _, v in ipairs(res.returns or {}) do log("= " .. v) end
end

box.onEnter = send
f:setFocus(box)

local ok, info = pcall(ask, { type = "ping" })
if ok and info then
    log("Conectado a " .. tostring(info.name) .. " (" .. tostring(info.os) .. ")")
else
    log("Nao consegui falar com o computador #" .. peerId .. ".")
    log("Verifique se ele tem um modem e o servico de rede ligado.")
end
log("")

f.onEvent = function(_, ev)
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 4
        box.y, box.w = h - 1, w - 2
        f.dirty = true
        return true
    end
end

f:run()
