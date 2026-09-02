-- Gerenciador do reator do Powah: painel, configuracao e registro, tudo em abas
-- na mesma janela. O painel tambem vai para um monitor, adaptado ao tamanho dele.
local ui = mosaic.ui
local theme = mosaic.theme
local powah = mosaic.lib("powah")
local chart = mosaic.lib("chart")
local hal = mosaic.lib("hal")
local strutil = mosaic.lib("strutil")

local INTERVAL = 2   -- segundos entre amostras

settings.define("mosaic.reactor.chest", { description = "Inventario com uraninita", type = "string" })
settings.define("mosaic.reactor.fuelMin", { description = "Alerta de combustivel abaixo de", type = "number", default = 8 })
settings.define("mosaic.reactor.waterMin", { description = "Alerta de agua abaixo de (mB)", type = "number", default = 500 })
settings.define("mosaic.reactor.autofeed", { description = "Repor combustivel sozinho", type = "boolean", default = false })
settings.define("mosaic.reactor.alerts", { description = "Avisar no chat", type = "boolean", default = true })

local hw = powah.discover()
local reading = powah.read(hw)
local firing = {}                       -- alertas ativos, para nao repetir no chat
local hFuel = chart.history(60)
local hWater = chart.history(60)
local hRate = chart.history(60)
-- tanks() nao traz capacidade e o detector nao tem maximo: acompanha o maior valor
-- ja visto para ter uma escala honesta em vez de barra cheia sem significado.
local tankMax, rateMax = 0, 0
local log = {}
local w, h = term.getSize()

local function say(line)
    log[#log + 1] = os.date("%H:%M:%S") .. " " .. line
    while #log > 100 do table.remove(log, 1) end
end

local function chatOn() return settings.get("mosaic.reactor.alerts") and hw.chatBox end

local function alert(key, active, message)
    if active and not firing[key] then
        firing[key] = true
        say("! " .. message)
        mosaic.notify(message)
        if chatOn() then hal.chat(message, "Reator") end
    elseif not active and firing[key] then
        firing[key] = nil
        say("ok " .. key .. " normalizou")
        if chatOn() then hal.chat(key .. " normalizou", "Reator") end
    end
end

-- Histerese: liga no limite e so desliga com 25% de folga. Sem isso um valor
-- tremendo na borda inunda o chat com liga/desliga.
local function low(key, value, limit)
    if firing[key] then return value < limit * 1.25 end
    return value < limit
end

local function sample()
    reading = powah.read(hw)
    if reading.error then
        alert("reator", true, "Sem leitura do reator: " .. reading.error)
        return
    end
    alert("reator", false, "")

    hFuel:push(reading.fuel.count)
    if reading.tank then
        tankMax = math.max(tankMax, reading.tank.amount)
        hWater:push(reading.tank.amount)
    end
    if reading.energy and reading.energy.rate then
        rateMax = math.max(rateMax, reading.energy.rate)
        hRate:push(reading.energy.rate)
    end

    local fuelMin = settings.get("mosaic.reactor.fuelMin") or 8
    alert("combustivel", low("combustivel", reading.fuel.count, fuelMin),
        "Combustivel baixo: " .. reading.fuel.count .. " uraninita")

    if reading.tank then
        local waterMin = settings.get("mosaic.reactor.waterMin") or 500
        alert("agua", low("agua", reading.tank.amount, waterMin),
            "Agua baixa: " .. reading.tank.amount .. " mB")
    end

    local chest = settings.get("mosaic.reactor.chest")
    if settings.get("mosaic.reactor.autofeed") and chest and reading.fuel.count < fuelMin then
        local moved = powah.feed(hw, chest, powah.fuelSlot(hw, reading))
        if moved > 0 then say("+ reposto " .. moved .. " uraninita de " .. chest) end
    end
end

-- ---------------------------------------------------------------- painel
local function bar(t, x, y, bw, frac, color)
    frac = math.max(0, math.min(1, frac or 0))
    local n = math.floor(frac * bw + 0.5)
    t.setCursorPos(x, y)
    t.setBackgroundColor(color)
    t.write(string.rep(" ", n))
    t.setBackgroundColor(theme.mutedFg)
    t.write(string.rep(" ", bw - n))
    t.setBackgroundColor(theme.appBg)
end

local function row(t, y, tw, label, value, frac, color)
    t.setCursorPos(1, y)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.write(" " .. strutil.pad(label, 11))
    local barW = math.max(4, tw - 13 - #value - 2)
    bar(t, 13, y, barW, frac, color)
    t.setCursorPos(13 + barW + 1, y)
    t.setTextColor(theme.appFg)
    t.write(value)
end

-- Desenha o painel em qualquer terminal: a janela do OS ou um monitor.
-- `reserva` sao linhas no rodape que nao podem ser usadas (a barra de abas).
local function drawPanel(t, reserva)
    local tw, th = t.getSize()
    th = th - (reserva or 0)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.clear()

    local estado, cor = "SEM LEITURA", colors.red
    if not reading.error then
        estado = next(firing) and "ATENCAO" or "NORMAL"
        cor = next(firing) and colors.orange or colors.lime
    end
    t.setCursorPos(1, 1)
    t.setBackgroundColor(cor)
    t.setTextColor(colors.black)
    t.write(strutil.pad(" Reator Powah - " .. estado, tw))

    if reading.error then
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(colors.red)
        t.setCursorPos(2, 3)
        t.write(strutil.ellipsis(reading.error, tw - 2))
        return
    end

    local y = 3
    row(t, y, tw, "Combustivel", tostring(reading.fuel.count), reading.fuel.count / 64, colors.lime)
    y = y + 1
    if reading.coolant.count > 0 then
        row(t, y, tw, "Gelo seco", tostring(reading.coolant.count), reading.coolant.count / 64, colors.lightBlue)
        y = y + 1
    end
    if reading.tank then
        row(t, y, tw, "Agua", reading.tank.amount .. " mB",
            tankMax > 0 and (reading.tank.amount / tankMax) or 0, colors.blue)
        y = y + 1
    end
    if reading.energy and reading.energy.capacity > 0 then
        row(t, y, tw, "Energia", string.format("%d%%", reading.energy.percent),
            reading.energy.percent / 100, colors.red)
        y = y + 1
    end
    if reading.energy and reading.energy.rate then
        row(t, y, tw, "Saida", strutil.short(reading.energy.rate) .. " FE/t",
            rateMax > 0 and (reading.energy.rate / rateMax) or 0, colors.yellow)
        y = y + 1
    end

    -- Diz o que falta em vez de mostrar zero, que seria mentira.
    local faltando = {}
    if not hw.blockReader then faltando[#faltando + 1] = "Block Reader (temperatura)" end
    if not hw.energyDetector and not (reading.energy and reading.energy.rate) then
        faltando[#faltando + 1] = "Energy Detector (FE/t)"
    end
    if #faltando > 0 and y < th then
        t.setCursorPos(2, y)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(strutil.ellipsis("falta: " .. table.concat(faltando, ", "), tw - 2))
        y = y + 1
    end

    -- Grafico com o espaco que sobrar, da serie mais interessante que existir.
    y = y + 1
    local sobra = th - y + 1
    if sobra >= 3 then
        local serie, cor2, nome = hFuel, colors.lime, "combustivel"
        if hRate.n > 1 then serie, cor2, nome = hRate, colors.yellow, "FE/t"
        elseif hWater.n > 1 then serie, cor2, nome = hWater, colors.blue, "agua" end
        t.setCursorPos(2, y - 1)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(strutil.ellipsis(nome .. " (" .. serie.n .. " amostras)", tw - 2))
        if serie.n > 1 then
            chart.line(t, { x = 1, y = y, w = tw, h = sobra, data = serie.data,
                            min = 0, fg = cor2, bg = colors.black, fill = true })
        end
    end
end

local function drawMonitor()
    if not hw.monitor then return end
    local ok = pcall(function()
        hw.monitor.setTextScale(0.5)
        drawPanel(hw.monitor, 0)
    end)
    if not ok then hw.monitor = nil end   -- monitor quebrado no jogo
end

-- ---------------------------------------------------------------- janela
local f = ui.form()
local mode = "painel"
local logList

-- Inventarios da rede que servem de deposito de combustivel.
local function inventories()
    local out = { "(nenhum)" }
    for _, n in ipairs(peripheral.getNames()) do
        if n ~= hw.reactorName then
            local p = peripheral.wrap(n)
            if p and p.list and p.pushItems then out[#out + 1] = n end
        end
    end
    return out
end

local function setMode(m)
    mode = m
    for _, wd in ipairs(f.widgets) do
        if wd.tab then wd.visible = (wd.tab == m) end
    end
    if m == "registro" and logList then
        local items = {}
        for i = #log, 1, -1 do items[#items + 1] = { text = " " .. log[i] } end
        if #items == 0 then items[1] = { text = " (nada registrado ainda)" } end
        logList:setItems(items)
    end
    f.scroll = 0
    f.dirty = true
end

f.onDraw = function(_, t)
    if mode == "painel" then drawPanel(t, 1) end
end

-- ---- barra de abas, presa no rodape (nao rola com o conteudo)
local navX = 1
local function tab(label, m)
    local b
    b = f:add(ui.button { x = navX, y = h, text = label, pinned = true,
        alt = true, onClick = function() setMode(m) end })
    navX = navX + b:width() + 1
    return b
end
tab("Painel", "painel")
tab("Config", "config")
tab("Registro", "registro")

f:add(ui.button { x = navX, y = h, text = "Parar", pinned = true, bg = colors.red, fg = colors.white,
    onClick = function()
        local chest = settings.get("mosaic.reactor.chest")
        if not chest then
            ui.msgbox("Escolha antes, na aba Config, o inventario para onde tirar o combustivel.", "Parada")
            setMode("config")
            return
        end
        if not ui.confirm("Retirar todo o combustivel do reator?", "Parada de emergencia") then return end
        local n, err = powah.pullFuel(hw, chest, reading)
        say(n > 0 and ("- retirado " .. n .. " uraninita para " .. chest)
            or ("falhou parar: " .. tostring(err)))
        if n > 0 and chatOn() then hal.chat("PARADA: combustivel retirado do reator", "Reator") end
        sample()
        f.dirty = true
    end })

-- ---- aba Config
local cy = 2
local function section(title)
    f:add(ui.label { x = 1, y = cy, w = w, text = " " .. title, tab = "config",
        bg = theme.accent, fg = theme.accentFg })
    cy = cy + 2
end
local function field(label)
    f:add(ui.label { x = 2, y = cy, text = label, tab = "config" })
    cy = cy + 1
end

section("Reposicao de combustivel")
field("Inventario com uraninita:")
local invs = inventories()
local chestNow = settings.get("mosaic.reactor.chest")
local chestSel = 1
for i, n in ipairs(invs) do if n == chestNow then chestSel = i end end
local chestBox = f:add(ui.dropdown { x = 2, y = cy, w = math.min(28, w - 4), items = invs,
    selected = chestSel, tab = "config" })
cy = cy + 2
local autofeedBox = f:add(ui.checkbox { x = 2, y = cy, text = "Repor sozinho quando faltar",
    checked = settings.get("mosaic.reactor.autofeed") == true, tab = "config" })
cy = cy + 2

section("Alertas")
field("Combustivel abaixo de:")
local fuelBox = f:add(ui.textbox { x = 2, y = cy, w = 10,
    text = tostring(settings.get("mosaic.reactor.fuelMin") or 8), tab = "config" })
cy = cy + 2
field("Agua abaixo de (mB):")
local waterBox = f:add(ui.textbox { x = 2, y = cy, w = 10,
    text = tostring(settings.get("mosaic.reactor.waterMin") or 500), tab = "config" })
cy = cy + 2
local chatCheck = f:add(ui.checkbox { x = 2, y = cy, text = "Avisar no chat do servidor",
    checked = settings.get("mosaic.reactor.alerts") ~= false, tab = "config" })
cy = cy + 2

f:add(ui.button { x = 2, y = cy, text = "Salvar", tab = "config", onClick = function()
    local fuelMin, waterMin = tonumber(fuelBox.text), tonumber(waterBox.text)
    if not fuelMin or not waterMin then
        ui.msgbox("Os limites precisam ser numeros.", "Config")
        return
    end
    local chest = chestBox:current()
    settings.set("mosaic.reactor.chest", chest ~= "(nenhum)" and chest or nil)
    settings.set("mosaic.reactor.fuelMin", fuelMin)
    settings.set("mosaic.reactor.waterMin", waterMin)
    settings.set("mosaic.reactor.autofeed", autofeedBox.checked == true)
    settings.set("mosaic.reactor.alerts", chatCheck.checked == true)
    settings.save()
    say("config salva")
    mosaic.notify("Configuracao salva")
end })
f:add(ui.button { x = 11, y = cy, text = "Testar chat", alt = true, tab = "config", onClick = function()
    if not hw.chatBox then ui.msgbox("Nenhum Chat Box conectado.", "Chat") return end
    hal.chat("Teste do gerenciador do reator", "Reator")
    mosaic.notify("Mensagem enviada")
end })
cy = cy + 2

section("Hardware detectado")
local hwLabel = f:add(ui.text { x = 2, y = cy, w = w - 3, h = 6, text = "", tab = "config" })
cy = cy + 7
f:add(ui.button { x = 2, y = cy, text = "Reprocurar", alt = true, tab = "config", onClick = function()
    hw = powah.discover()
    chestBox.items = inventories()
    sample()
    say("hardware reprocurado")
    setMode("config")
end })

local function hardwareText()
    local lines = {}
    local function mark(nome, ok, para)
        lines[#lines + 1] = (ok and "[x] " or "[ ] ") .. nome .. (ok and "" or "  -> " .. para)
    end
    mark("Reator", hw.reactor ~= nil, "encoste o PC no reator")
    mark("Block Reader", hw.blockReader ~= nil, "temperatura")
    mark("Energy Detector", hw.energyDetector ~= nil, "FE/t e limite de saida")
    mark("Chat Box", hw.chatBox ~= nil, "alertas no chat")
    mark("Monitor", hw.monitor ~= nil, "painel na parede")
    return table.concat(lines, "\n")
end

-- ---- aba Registro
logList = f:add(ui.list { x = 1, y = 1, w = w, h = h - 1, tab = "registro",
    render = function(it) return it.text end })

setMode("painel")
sample()

local timer = os.startTimer(INTERVAL)
f.onEvent = function(_, ev, id)
    if ev == "timer" and id == timer then
        timer = os.startTimer(INTERVAL)
        sample()
        drawMonitor()
        hwLabel.text = hardwareText()
        if mode == "registro" then setMode("registro") end
        f.dirty = true
        return true
    elseif ev == "term_resize" then
        w, h = term.getSize()
        f.dirty = true
    end
end

f:run()
