-- Configuracoes do sistema.
local ui = mosaic.ui
local theme = mosaic.theme

local w, h = term.getSize()
local f = ui.form()

local function save()
    settings.save()
    mosaic.notify("Configuracoes salvas")
end


local y = 1
local function row(text)
    f:add(ui.label { x = 2, y = y, text = text })
    y = y + 1
end

-- Nome do computador
row("Nome deste computador:")
local nameBox = f:add(ui.textbox {
    x = 2, y = y, w = math.min(30, w - 4), text = os.getComputerLabel() or "",
    onEnter = function(self)
        os.setComputerLabel(self.text ~= "" and self.text or nil)
        mosaic.notify("Nome alterado")
    end,
})
y = y + 2

-- Tema
row("Tema:")
local themeBox = f:add(ui.dropdown {
    x = 2, y = y, w = 14, items = theme.names,
    selected = (theme.name == "dark") and 2 or 1,
    onChange = function(_, item)
        settings.set("mosaic.theme", item)
        theme.load(item)
        save()
        mosaic.notify("Reinicie o OS para aplicar em tudo")
        mosaic.redraw()
    end,
})
y = y + 2

-- Relogio
row("Relogio da taskbar:")
local clockBox = f:add(ui.dropdown {
    x = 2, y = y, w = 14, items = { "real", "game" },
    selected = settings.get("mosaic.clock") == "game" and 2 or 1,
    onChange = function(_, item) settings.set("mosaic.clock", item) save() mosaic.redraw() end,
})
y = y + 2

-- Relay
row("Relay (controle remoto):")
local relayBox = f:add(ui.textbox {
    x = 2, y = y, w = math.min(40, w - 4), text = settings.get("mosaic.relay.url") or "",
    placeholder = "ws://IP:8765/ws/computer",
})
y = y + 1
local tokenBox = f:add(ui.textbox {
    x = 2, y = y, w = math.min(40, w - 4), text = settings.get("mosaic.relay.token") or "",
    placeholder = "token", mask = "*",
})
y = y + 2

f:add(ui.button { x = 2, y = y, text = "Salvar relay", onClick = function()
    settings.set("mosaic.relay.url", relayBox.text ~= "" and relayBox.text or nil)
    settings.set("mosaic.relay.token", tokenBox.text ~= "" and tokenBox.text or nil)
    save()
    if ui.confirm("Reiniciar o computador para conectar agora?", "Relay") then mosaic.reboot() end
end })
f:add(ui.button { x = 16, y = y, text = "Testar", alt = true, onClick = function()
    local url = relayBox.text
    if url == "" then ui.msgbox("Preencha a URL do relay primeiro.", "Relay") return end
    if not http then ui.msgbox("A API http esta desativada neste servidor.", "Relay") return end
    local httpUrl = url:gsub("^ws", "http"):gsub("/ws/computer$", "/api/ping")
    local body, err = mosaic.lib("httpx").get(httpUrl)
    if body then ui.msgbox("Relay respondeu: " .. tostring(body):sub(1, 60), "Relay")
    else ui.msgbox("Sem resposta: " .. tostring(err), "Relay") end
end })
y = y + 2

f:add(ui.checkbox {
    x = 2, y = y, text = "Rede entre computadores",
    checked = settings.get("mosaic.net.enabled") ~= false,
    onChange = function(_, v) settings.set("mosaic.net.enabled", v) save() end,
})
y = y + 1
f:add(ui.checkbox {
    x = 2, y = y, text = "Papel de parede",
    checked = settings.get("mosaic.wallpaper") ~= nil,
    onChange = function(_, v)
        settings.set("mosaic.wallpaper", v and "/home/wallpaper.nfp" or nil)
        save()
        mosaic.emit("apps_changed")
    end,
})
y = y + 2

f:add(ui.button { x = 2, y = y, text = "Ver todas as opcoes", alt = true, onClick = function()
    local names = settings.getNames()
    local items = {}
    for _, n in ipairs(names) do
        if n:match("^mosaic%.") then
            items[#items + 1] = { text = n .. " = " .. textutils.serialise(settings.get(n)):gsub("\n", " ") }
        end
    end
    local idx = ui.menu(items, 2, 3, w - 4, { maxH = h - 6 })
    if idx then
        local key = names[idx]
        local novo = ui.prompt(key .. ":", tostring(settings.get(key) or ""), "Editar opcao")
        if novo then
            if novo == "true" then settings.set(key, true)
            elseif novo == "false" then settings.set(key, false)
            elseif tonumber(novo) then settings.set(key, tonumber(novo))
            elseif novo == "" then settings.unset(key)
            else settings.set(key, novo) end
            save()
        end
    end
    f.dirty = true
end })

f.onEvent = function(_, ev)
    if ev == "term_resize" then w, h = term.getSize() f.dirty = true return true end
end

f:run()
