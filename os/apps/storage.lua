-- Armazem em rede: consulta, retirada, deposito e configuracao dos baus.
-- O servico storage (no boot) controla as transferencias; esta janela so envia comandos.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")

local f = ui.form()
local view = "items"
local sortMode = "name"
local queries = { items = "", chests = "" }
local selectedKeys = { items = nil, chests = nil }
local snapshot
local serviceError
local list, search, summary, detail, footer
local showView, refresh, rebuild, withdraw, chooseRole

local function command(action, extra)
    local payload = extra or {}
    payload.action = action
    os.queueEvent("mosaic:storage_cmd", payload)
end

local function lower(s)
    return tostring(s or ""):lower()
end

local function contains(haystack, needle)
    return needle == "" or lower(haystack):find(needle, 1, true) ~= nil
end

local function selected()
    local it = list and list:getSelected()
    if it and not it.header then return it end
    return nil
end

local function locationCount(locations)
    if type(locations) ~= "table" then return 0 end
    local n = 0
    local seen = {}
    for key, place in pairs(locations) do
        local name = type(place) == "table" and (place.inventory or place.name or place.chest) or nil
        if not name and type(key) == "string" then name = key end
        if name and not seen[name] then seen[name] = true n = n + 1 end
    end
    return n
end

local roles = {
    input = "Entrada", output = "Saida", storage = "Armazenar", ignore = "Ignorar",
}
local roleShort = {
    input = "ENT", output = "SAI", storage = "EST", ignore = "IGN",
}

local title = f:add(ui.label {
    x = 1, y = 1, w = "fill", text = "", bg = theme.accent, fg = theme.accentFg,
})

local tabItems = f:add(ui.button {
    x = 1, y = 2, w = 9, text = "&Itens", onClick = function() showView("items") end,
})
local tabChests = f:add(ui.button {
    x = 11, y = 2, w = 9, text = "&Baus", onClick = function() showView("chests") end,
})
local hint = f:add(ui.label {
    x = 22, y = 2, w = -21, text = "", fg = theme.mutedFg,
})
f:add(ui.label { x = 1, y = 3, w = 7, text = " Buscar", fg = theme.mutedFg })
search = f:add(ui.textbox {
    x = 8, y = 3, w = -7, placeholder = "Nome ou ID do item",
    onChange = function(_, value)
        queries[view] = value
        rebuild()
    end,
    onEnter = function()
        local it = selected()
        if not it then return end
        if view == "items" then withdraw(it) else chooseRole(it) end
    end,
})
summary = f:add(ui.label { x = 1, y = 4, w = "fill", text = "", fg = theme.mutedFg })

footer = f:add(ui.label {
    x = 1, bottom = 0, w = "fill", text = "", bg = theme.taskbarBg, fg = theme.taskbarFg,
})

local actionBar = ui.row(f, { bottom = 1, items = {
    { text = "&Sacar", w = 10, onClick = function()
        if view == "items" then withdraw(selected()) else chooseRole(selected()) end
    end },
    { text = "&Depositar", w = 14, onClick = function()
        if view == "items" then command("deposit")
        elseif snapshot then
            local config = snapshot.config or {}
            command("set_auto", { enabled = not config.autoDeposit })
        end
    end },
    { text = "&Atualizar", w = 12, onClick = function() command("rescan") end },
} })
local action1, action2, action3 = actionBar.buttons[1], actionBar.buttons[2], actionBar.buttons[3]

detail = f:add(ui.label {
    x = 1, above = actionBar, w = "fill", text = "", bg = theme.inputBg, fg = theme.inputFg,
})
list = f:add(ui.list {
    x = 1, y = 5, w = "fill", fillTo = detail, items = {},
    render = function(it)
        if it.header then return it.text end
        local W = list.w or 40
        if view == "items" then
            local name = tostring(it.display or strutil.itemName(it.name or it.key or "?"))
            if it.nbt and it.nbt ~= "" then name = name .. " *" end
            local count = "x" .. strutil.short(it.count)
            local nameW = math.max(1, W - #count - 4)
            return " " .. strutil.pad(strutil.ellipsis(name, nameW), nameW) .. " " .. count
        end
        local role = roleShort[it.role] or "EST"
        local use = string.format("%s %d/%d", role, tonumber(it.used) or 0, tonumber(it.slots) or 0)
        local nameW = math.max(1, W - #use - 4)
        return " " .. strutil.pad(strutil.ellipsis(it.name or "?", nameW), nameW) .. " " .. use
    end,
})

local function updateDetail()
    local it = selected()
    if not it then
        detail.text = view == "items"
            and " Selecione um item. Enter para sacar."
            or " Selecione um bau. Enter para definir funcao."
    elseif view == "items" then
        local id = tostring(it.name or it.key or "?")
        local n = locationCount(it.locations)
        detail.text = string.format(" %s | %s | %d bau%s", id, strutil.short(it.count), n, n == 1 and "" or "s")
    else
        detail.text = string.format(" %s | %s | %d/%d slots", it.name or "?",
            roles[it.role] or "Armazenar", tonumber(it.used) or 0, tonumber(it.slots) or 0)
    end
    f.dirty = true
end

list.onSelect = function(_, it)
    if it and not it.header then selectedKeys[view] = view == "items" and it.key or it.name end
    updateDetail()
end
list.onActivate = function(_, it)
    if not it or it.header then return end
    if view == "items" then withdraw(it) else chooseRole(it) end
end

local function itemDetail(it)
    if not it then return end
    local loc = {}
    if type(it.locations) == "table" then
        for _, place in pairs(it.locations) do
            if type(place) == "table" then
                loc[#loc + 1] = tostring(place.name or place.inventory or "bau") .. ": " .. tostring(place.count or "?")
            end
        end
    end
    table.sort(loc)
    ui.msgbox(string.format("%s\nID: %s\nQuantidade: %s\n%s", tostring(it.display or it.name or "?"),
        tostring(it.name or "?"), tostring(it.count or 0),
        #loc > 0 and table.concat(loc, "\n") or "Sem localizacao detalhada."), "Detalhes")
end

list.onContext = function(_, it, _, lx, ly)
    if not it or it.header then return end
    if view == "items" then
        local opts = { "Sacar 1", "Sacar pilha", "Sacar quantidade...", "Sacar tudo", "Detalhes" }
        local idx = ui.menu(opts, list.x + lx - 1, list.y + ly - 1, 22)
        f.dirty = true
        if idx == 1 then withdraw(it, 1)
        elseif idx == 2 then withdraw(it, math.min(tonumber(it.maxCount) or 64, tonumber(it.count) or 64))
        elseif idx == 3 then withdraw(it)
        elseif idx == 4 then withdraw(it, tonumber(it.count) or 0)
        elseif idx == 5 then itemDetail(it) end
    else
        chooseRole(it, list.x + lx - 1, list.y + ly - 1)
    end
end

function withdraw(it, quantity)
    if not it or not it.key then return end
    if not snapshot or not snapshot.output then
        ui.msgbox("Defina um bau de Saida na aba Baus.", "Saida necessaria")
        return
    end
    if snapshot.busy then return end
    local available = math.max(0, tonumber(it.count) or 0)
    if available == 0 then return end
    if quantity == nil then
        local answer = ui.prompt("Quantidade para enviar ao bau de Saida:",
            tostring(math.min(64, available)), "Sacar " .. tostring(it.display or it.name or "item"))
        if answer == nil then return end
        quantity = tonumber(strutil.trim(answer))
    end
    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 then
        ui.msgbox("Digite uma quantidade inteira maior que zero.", "Quantidade invalida")
        return
    end
    command("withdraw", { key = it.key, count = math.min(quantity, available) })
end

function chooseRole(it, x, y)
    if not it or not it.name or (snapshot and snapshot.busy) then return end
    local opts = {
        { text = (it.role == "input" and "* " or "  ") .. "Entrada", role = "input" },
        { text = (it.role == "output" and "* " or "  ") .. "Saida", role = "output" },
        { text = (it.role == "storage" and "* " or "  ") .. "Armazenar", role = "storage" },
        { text = (it.role == "ignore" and "* " or "  ") .. "Ignorar", role = "ignore" },
    }
    local idx = ui.menu(opts, x or 2, y or 6, 17)
    f.dirty = true
    if idx and opts[idx].role ~= it.role then
        command("set_role", { name = it.name, role = opts[idx].role })
    end
end

local function sortItems(items)
    table.sort(items, function(a, b)
        local ac, bc = tonumber(a.count) or 0, tonumber(b.count) or 0
        if sortMode == "count" and ac ~= bc then
            return ac > bc
        end
        local an = lower(a.display or a.name or a.key)
        local bn = lower(b.display or b.name or b.key)
        if an ~= bn then return an < bn end
        return lower(a.key) < lower(b.key)
    end)
end

function rebuild()
    if not list then return end
    local query = lower(strutil.trim(queries[view] or ""))
    local rows = {}
    local source = snapshot and (view == "items" and snapshot.items or snapshot.inventories) or {}
    for _, it in ipairs(source or {}) do
        if view == "items" then
            if contains(it.display, query) or contains(it.name, query) or contains(it.key, query) then
                rows[#rows + 1] = it
            end
        elseif contains(it.name, query) or contains(it.type, query) or contains(roles[it.role], query) then
            rows[#rows + 1] = it
        end
    end
    if view == "items" then sortItems(rows)
    else table.sort(rows, function(a, b) return lower(a.name) < lower(b.name) end) end
    local count = #rows
    if count == 0 then
        local message
        if query ~= "" then message = " Nenhum resultado. Limpe a busca."
        elseif not snapshot then message = " Servico de armazem indisponivel."
        elseif view == "items" and #(snapshot.inventories or {}) == 0 then
            message = " Nenhum bau. Ligue modems com fio."
        elseif view == "items" then message = " Nenhum item guardado nos baus."
        else message = " Nenhum inventario foi detectado." end
        rows[1] = { header = true, text = message }
    end
    list:setItems(rows, false)
    if count == 0 then list.selected = nil
    else
        local wanted = selectedKeys[view]
        local at = 1
        if wanted then
            for i, it in ipairs(rows) do
                if (view == "items" and it.key or it.name) == wanted then at = i break end
            end
        end
        list.selected = at
        selectedKeys[view] = view == "items" and rows[at].key or rows[at].name
        list:ensureVisible()
    end
    if view == "items" then
        summary.text = string.format(" %d tipos | %s itens | %d exibidos", #(snapshot and snapshot.items or {}),
            strutil.short(snapshot and snapshot.totalItems or 0), count)
    else
        local used = tonumber(snapshot and snapshot.usedSlots) or 0
        local total = tonumber(snapshot and snapshot.totalSlots) or 0
        summary.text = string.format(" %d baus | %d/%d slots | %d exibidos", #(snapshot and snapshot.inventories or {}),
            used, total, count)
    end
    updateDetail()
end

function showView(nextView)
    if view ~= nextView then queries[view] = search.text or "" end
    view = nextView
    if search.text ~= (queries[view] or "") then search:setText(queries[view] or "") end
    search.placeholder = view == "items" and "Nome ou ID do item" or "Nome ou tipo do bau"
    tabItems.bg = view == "items" and theme.accent or theme.buttonBg
    tabItems.fg = view == "items" and theme.accentFg or theme.buttonFg
    tabChests.bg = view == "chests" and theme.accent or theme.buttonBg
    tabChests.fg = view == "chests" and theme.accentFg or theme.buttonFg
    hint.text = view == "items" and "Enter sacar | F6 ordem" or "Enter definir funcao"
    action1.text = view == "items" and "&Sacar" or "&Tipo"
    action2.text = view == "items" and "&Depositar" or
        ((snapshot and snapshot.config and snapshot.config.autoDeposit) and "Auto: ON" or "Auto: OFF")
    rebuild()
end

function refresh()
    local getter = mosaic.storageStatus
    if type(getter) ~= "function" then
        snapshot, serviceError = nil, "Servico nao iniciado. Reinicie o Mosaic OS."
    else
        local ok, result = pcall(getter)
        if ok and type(result) == "table" then snapshot, serviceError = result, nil
        else snapshot, serviceError = nil, "Falha ao ler o servico de armazem." end
    end
    local W = term.getSize()
    local label = " MOSAIC / ARMAZEM"
    local state = not snapshot and "OFFLINE" or snapshot.state == "ready" and "REDE OK"
        or snapshot.state == "setup" and "CONFIGURAR" or "ATENCAO"
    title.bg = (snapshot and snapshot.state == "error") and theme.errorBg or theme.accent
    title.fg = (snapshot and snapshot.state == "error") and theme.errorFg or theme.accentFg
    title.text = label .. string.rep(" ", math.max(1, W - #label - #state - 1)) .. state
    if serviceError then footer.text = " " .. serviceError
    elseif snapshot.error then footer.text = " " .. tostring(snapshot.error)
    elseif snapshot.busy then footer.text = " Aguarde: transferindo itens..."
    elseif not snapshot.input then footer.text = " Defina um bau de Entrada na aba Baus."
    elseif not snapshot.output then footer.text = " Defina um bau de Saida na aba Baus."
    elseif snapshot.activity and snapshot.activity ~= "" then footer.text = " " .. tostring(snapshot.activity)
    else footer.text = " Pronto. F5 atualiza | Ctrl+F busca | F1 ajuda" end
    action1.disabled = not snapshot or snapshot.busy
    action2.disabled = not snapshot or snapshot.busy or (view == "items" and not snapshot.input)
    action3.disabled = not snapshot or snapshot.busy
    showView(view)
    if action1.disabled and f.focused == action1 then f:setFocus(search) end
    if action2.disabled and f.focused == action2 then f:setFocus(search) end
    if action3.disabled and f.focused == action3 then f:setFocus(search) end
    f.dirty = true
end

local timer = os.startTimer(2)
f.onEvent = function(_, ev, a)
    if ev == "mosaic:storage_state" then refresh() return true
    elseif ev == "timer" and a == timer then
        timer = os.startTimer(2)
        if mosaic.focused() == mosaic.current() then refresh() end
        return true
    elseif ev == "key" and a == keys.f5 then command("rescan") return true
    elseif ev == "key" and a == keys.f6 then
        if view == "items" then sortMode = sortMode == "name" and "count" or "name" rebuild() end
        return true
    elseif ev == "key" and a == keys.f1 then
        ui.msgbox("Itens: busque por nome ou ID, selecione e use Sacar.\n" ..
            "O item vai para o bau de Saida.\n\n" ..
            "Baus: defina um bau de Entrada, um de Saida e deixe os demais em Armazenar. " ..
            "Ponha itens na Entrada e use Depositar, ou ative Auto.\n\n" ..
            "F5 atualiza, F6 ordena, Ctrl+F busca.", "Como usar")
        f.dirty = true
        return true
    elseif ev == "key" and a == keys.f and mosaic.ctrlHeld() then
        f:setFocus(search)
        return true
    end
end

refresh()
f:run()
