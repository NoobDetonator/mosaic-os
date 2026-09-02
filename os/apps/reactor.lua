-- Gerenciador do reator do Powah: painel, historico, alertas no chat e as acoes.
-- Desenha o mesmo painel na janela e num monitor, adaptando ao tamanho de cada um.
local ui = mosaic.ui
local theme = mosaic.theme
local powah = mosaic.lib("powah")
local chart = mosaic.lib("chart")
local hal = mosaic.lib("hal")
local strutil = mosaic.lib("strutil")

local INTERVAL = 2   -- segundos entre amostras

settings.define("mosaic.reactor.chest", { description = "Inventario da rede com uraninita", type = "string" })
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

local function say(line)
    log[#log + 1] = os.date("%H:%M:%S") .. " " .. line
    while #log > 50 do table.remove(log, 1) end
end

-- Histerese: liga no limite e so desliga com folga. Sem isso um valor tremendo
-- na borda inunda o chat com liga/desliga.
local function alert(key, active, message)
    if active and not firing[key] then
        firing[key] = true
        say("! " .. message)
        mosaic.notify(message)
        if settings.get("mosaic.reactor.alerts") and hw.chatBox then
            hal.chat(message, "Reator")
        end
    elseif not active and firing[key] then
        firing[key] = nil
        say("ok " .. key .. " normalizou")
        if settings.get("mosaic.reactor.alerts") and hw.chatBox then
            hal.chat(key .. " normalizou", "Reator")
        end
    end
end

local function low(key, value, limit)
    if firing[key] then return value < limit * 1.25 end   -- so sai com 25% de folga
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

    -- Reposicao automatica, se houver um inventario configurado na rede com fio.
    local chest = settings.get("mosaic.reactor.chest")
    if settings.get("mosaic.reactor.autofeed") and chest and reading.fuel.count < fuelMin then
        local slot = powah.fuelSlot(hw, reading)
        local moved = powah.feed(hw, chest, slot)
        if moved > 0 then say("+ reposto " .. moved .. " uraninita de " .. chest) end
    end
end

-- ---------------------------------------------------------------- painel
local function bar(t, x, y, w, frac, color)
    frac = math.max(0, math.min(1, frac or 0))
    local n = math.floor(frac * w + 0.5)
    t.setCursorPos(x, y)
    t.setBackgroundColor(color)
    t.write(string.rep(" ", n))
    t.setBackgroundColor(theme.mutedFg)
    t.write(string.rep(" ", w - n))
    t.setBackgroundColor(theme.appBg)
end

local function row(t, y, w, label, value, frac, color)
    t.setCursorPos(1, y)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.write(" " .. strutil.pad(label, 12))
    local barW = math.max(4, w - 14 - #value - 2)
    bar(t, 14, y, barW, frac, color)
    t.setCursorPos(14 + barW + 1, y)
    t.setTextColor(theme.appFg)
    t.write(value)
end

-- Desenha o painel inteiro em qualquer terminal (janela do OS ou monitor).
local function drawPanel(t)
    local w, h = t.getSize()
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
    t.write(strutil.pad(" Reator Powah - " .. estado, w))

    if reading.error then
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(colors.red)
        t.setCursorPos(2, 3)
        t.write(strutil.ellipsis(reading.error, w - 2))
        return
    end

    local y = 3
    row(t, y, w, "Combustivel", tostring(reading.fuel.count), reading.fuel.count / 64, colors.lime)
    y = y + 1
    if reading.coolant.count > 0 then
        row(t, y, w, "Gelo seco", tostring(reading.coolant.count), reading.coolant.count / 64, colors.lightBlue)
        y = y + 1
    end
    if reading.tank then
        local frac = tankMax > 0 and (reading.tank.amount / tankMax) or 0
        row(t, y, w, "Agua", reading.tank.amount .. " mB", frac, colors.blue)
        y = y + 1
    end
    if reading.energy and reading.energy.capacity > 0 then
        row(t, y, w, "Energia", string.format("%d%%", reading.energy.percent),
            reading.energy.percent / 100, colors.red)
        y = y + 1
    end
    if reading.energy and reading.energy.rate then
        row(t, y, w, "Saida", strutil.short(reading.energy.rate) .. " FE/t",
            rateMax > 0 and (reading.energy.rate / rateMax) or 0, colors.yellow)
        y = y + 1
    end

    -- Faltando: diz o que falta em vez de mostrar zero, que seria mentira.
    local faltando = {}
    if not hw.blockReader then faltando[#faltando + 1] = "Block Reader (temperatura)" end
    if not hw.energyDetector and not (reading.energy and reading.energy.rate) then
        faltando[#faltando + 1] = "Energy Detector (FE/t)"
    end
    if #faltando > 0 and y < h then
        t.setCursorPos(2, y)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(strutil.ellipsis("falta: " .. table.concat(faltando, ", "), w - 2))
        y = y + 1
    end

    -- Grafico com o espaco que sobrar, do que houver de historico.
    y = y + 1
    local sobra = h - y
    if sobra >= 3 then
        local serie, cor2, nome = hFuel, colors.lime, "combustivel"
        if hRate.n > 1 then serie, cor2, nome = hRate, colors.yellow, "FE/t"
        elseif hWater.n > 1 then serie, cor2, nome = hWater, colors.blue, "agua" end
        t.setCursorPos(2, y - 1)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(nome .. " (ultimas " .. serie.n .. " amostras)")
        if serie.n > 1 then
            chart.line(t, { x = 1, y = y, w = w, h = sobra, data = serie.data,
                            min = 0, fg = cor2, bg = colors.black, fill = true })
        end
    end
end

local function drawMonitor()
    if not hw.monitor then return end
    local ok = pcall(function()
        hw.monitor.setTextScale(0.5)
        drawPanel(hw.monitor)
    end)
    if not ok then hw.monitor = nil end   -- monitor foi quebrado no jogo
end

-- ---------------------------------------------------------------- janela
local f = ui.form()
f.onDraw = function(_, t) drawPanel(t) end

local w, h = term.getSize()
f:add(ui.button { x = 2, y = h, text = "Parar", alt = true, onClick = function()
    local chest = settings.get("mosaic.reactor.chest")
    if not chest then
        ui.msgbox("Configure antes um inventario da rede em Config, para onde tirar o combustivel.", "Parada")
        return
    end
    if not ui.confirm("Retirar todo o combustivel do reator?", "Parada de emergencia") then return end
    local n, err = powah.pullFuel(hw, chest, reading)
    say(n > 0 and ("- retirado " .. n .. " uraninita") or ("falhou parar: " .. tostring(err)))
    if n > 0 and hw.chatBox then hal.chat("PARADA: combustivel retirado do reator", "Reator") end
    sample()
    f.dirty = true
end })
f:add(ui.button { x = 10, y = h, text = "Registro", alt = true, onClick = function()
    local items = {}
    for i = #log, 1, -1 do items[#items + 1] = { text = " " .. log[i] } end
    if #items == 0 then items[1] = { text = " (nada ainda)" } end
    ui.menu(items, 1, 2, w - 2, { maxH = h - 3 })
    f.dirty = true
end })
f:add(ui.button { x = 21, y = h, text = "Hardware", alt = true, onClick = function()
    local l = {}
    for _, p in ipairs(hal.list()) do
        l[#l + 1] = " " .. p.name .. "  " .. p.type
    end
    ui.msgbox(#l > 0 and table.concat(l, "\n") or "Nenhum periferico conectado.", "Hardware")
    hw = powah.discover()
    f.dirty = true
end })

sample()
local timer = os.startTimer(INTERVAL)
f.onEvent = function(_, ev, id)
    if ev == "timer" and id == timer then
        timer = os.startTimer(INTERVAL)
        sample()
        drawMonitor()
        f.dirty = true
        return true
    end
end

f:run()
