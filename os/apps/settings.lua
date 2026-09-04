-- Configuracoes do sistema.
--
-- Os campos ficam em caixas de grupo: antes era uma pilha de rotulos e campos soltos, sem
-- nada dizendo o que pertencia a que. O form rola sozinho, entao os grupos podem passar da
-- altura da janela sem problema.
local ui = mosaic.ui
local theme = mosaic.theme

local f = ui.form()

local function save()
    settings.save()
    mosaic.notify("Configuracoes salvas")
end

-- Abre um grupo em `y` com `rows` linhas de conteudo e devolve a primeira linha de dentro.
-- A moldura ocupa uma linha em cima e uma embaixo, e recua duas colunas de cada lado.
local INSET = 3
local function group(y, rows, title)
    f:add(ui.group { x = 1, y = y, w = -1, h = rows + 2, text = title })
    return y + 1
end

local y = 1

-- ---------------------------------------------------------------- identificacao
local inner = group(y, 2, "Este computador")
f:add(ui.label { x = INSET, y = inner, text = "Nome:" })
f:add(ui.textbox {
    x = INSET + 6, y = inner, w = -(INSET + 7), text = os.getComputerLabel() or "",
    placeholder = "sem nome",
    onEnter = function(self)
        os.setComputerLabel(self.text ~= "" and self.text or nil)
        mosaic.notify("Nome alterado")
    end,
})
f:add(ui.label { x = INSET, y = inner + 1, text = "Enter grava o nome", fg = theme.mutedFg })
y = y + 4

-- ---------------------------------------------------------------- aparencia
inner = group(y, 2, "Aparencia")
local themeIndex = 1
for i, n in ipairs(theme.names) do if n == theme.name then themeIndex = i end end
f:add(ui.label { x = INSET, y = inner, text = "Tema:" })
f:add(ui.dropdown {
    x = INSET + 8, y = inner, w = 14, items = theme.names, selected = themeIndex,
    onChange = function(_, item)
        settings.set("mosaic.theme", item)
        theme.load(item)
        save()
        mosaic.notify("Reinicie o OS para aplicar em tudo")
        mosaic.redraw()
    end,
})
f:add(ui.label { x = INSET, y = inner + 1, text = "Relogio:" })
f:add(ui.dropdown {
    x = INSET + 8, y = inner + 1, w = 14, items = { "real", "game" },
    selected = settings.get("mosaic.clock") == "game" and 2 or 1,
    onChange = function(_, item) settings.set("mosaic.clock", item) save() mosaic.redraw() end,
})
y = y + 4

-- ---------------------------------------------------------------- som
-- O aviso de "sem alto-falante" e' medido na hora de abrir, e nao um palpite: sem ele a
-- pessoa mexe no volume e acha que quebrou alguma coisa.
local audio = mosaic.lib("audio")
inner = group(y, 2, "Som")
f:add(ui.checkbox {
    x = INSET, y = inner, text = "Sons do sistema",
    checked = settings.get("mosaic.som.enabled") ~= false,
    onChange = function(self)
        settings.set("mosaic.som.enabled", self.checked)
        save()
        if self.checked then audio.sfx("abrir") end
    end,
})
f:add(ui.label { x = INSET, y = inner + 1, text = "Volume:" })
f:add(ui.dropdown {
    x = INSET + 8, y = inner + 1, w = 10, items = { "0", "1", "2", "3" },
    selected = math.floor(tonumber(settings.get("mosaic.som.volume")) or 1) + 1,
    onChange = function(_, item)
        settings.set("mosaic.som.volume", tonumber(item))
        save()
        audio.sfx("abrir")
    end,
})
f:add(ui.label {
    x = INSET + 19, y = inner + 1, w = -(INSET + 20),
    -- Curto de proposito: sobram ~20 colunas depois do seletor de volume na janela padrao,
    -- e "sem alto-falante ao lado" saia cortado no meio da palavra.
    text = audio.has() and "" or "sem alto-falante", fg = theme.mutedFg,
})
y = y + 4

-- ---------------------------------------------------------------- relay
inner = group(y, 4, "Relay (controle remoto)")
local relayBox = f:add(ui.textbox {
    x = INSET, y = inner, w = -(INSET + 1), text = settings.get("mosaic.relay.url") or "",
    placeholder = "ws://IP:8765/ws/computer",
})
local tokenBox = f:add(ui.textbox {
    x = INSET, y = inner + 1, w = -(INSET + 1), text = settings.get("mosaic.relay.token") or "",
    placeholder = "token", mask = "*",
})
f:add(ui.button { x = INSET, y = inner + 3, text = "&Salvar relay", onClick = function()
    settings.set("mosaic.relay.url", relayBox.text ~= "" and relayBox.text or nil)
    settings.set("mosaic.relay.token", tokenBox.text ~= "" and tokenBox.text or nil)
    save()
    if ui.confirm("Reiniciar o computador para conectar agora?", "Relay") then mosaic.reboot() end
end })
f:add(ui.button { x = INSET + 15, y = inner + 3, text = "&Testar", alt = true, onClick = function()
    local url = relayBox.text
    if url == "" then ui.msgbox("Preencha a URL do relay primeiro.", "Relay") return end
    if not http then ui.msgbox("A API http esta desativada neste servidor.", "Relay") return end
    -- O ping e publico e nao pede token: serve so para saber se o relay esta de pe.
    local httpUrl = url:gsub("^ws", "http"):gsub("/ws/computer$", "/api/ping")
    local body, err = mosaic.lib("httpx").get(httpUrl)
    if body then ui.msgbox("Relay respondeu: " .. tostring(body):sub(1, 60), "Relay")
    else ui.msgbox("Sem resposta: " .. tostring(err), "Relay") end
end })
y = y + 6

-- ---------------------------------------------------------------- sistema
inner = group(y, 2, "Sistema")
f:add(ui.checkbox {
    x = INSET, y = inner, text = "&Rede entre computadores",
    checked = settings.get("mosaic.net.enabled") ~= false,
    onChange = function(_, v) settings.set("mosaic.net.enabled", v) save() end,
})
f:add(ui.checkbox {
    x = INSET, y = inner + 1, text = "&Papel de parede",
    checked = settings.get("mosaic.wallpaper") ~= nil,
    onChange = function(_, v)
        settings.set("mosaic.wallpaper", v and "/home/wallpaper.nfp" or nil)
        save()
        mosaic.emit("apps_changed")
    end,
})
y = y + 4

f:add(ui.button { x = 1, y = y, text = "Ver &todas as opcoes", alt = true, onClick = function()
    local W, H = term.getSize()
    local names = settings.getNames()
    local items = {}
    for _, n in ipairs(names) do
        if n:match("^mosaic%.") then
            items[#items + 1] = { text = n .. " = " .. textutils.serialise(settings.get(n)):gsub("\n", " ") }
        end
    end
    local idx = ui.menu(items, 2, 3, W - 4, { maxH = H - 6 })
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

f:run()
