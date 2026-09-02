-- Gerenciador do reator do Powah: painel, configuracao e registro, tudo em abas
-- na mesma janela. O painel tambem vai para um monitor, adaptado ao tamanho dele.
local ui = mosaic.ui
local theme = mosaic.theme
local powah = mosaic.lib("powah")
local chart = mosaic.lib("chart")
local hal = mosaic.lib("hal")
local strutil = mosaic.lib("strutil")

-- Cada chamada de periferico pela rede custa 1 tick; com a capacidade e o NBT em
-- cache sobram ~4 por ciclo (0.2 s). Da para amostrar de segundo em segundo.
local INTERVAL = 1

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
local hEnergy = chart.history(60)
local hNet = chart.history(60)
local netFeTick, netMax = nil, 0    -- balanco do buffer em FE/t, com sinal
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

-- A temperatura do Powah mora no nucleo do multiblock, que fica cercado de pecas
-- e nenhum Block Reader alcanca. O sinal util no lugar dela e o ritmo de consumo:
-- quanto tempo falta ate acabar, que e o que o operador precisa saber.
local function acabaEm(valor, hist)
    local porMin = hist:fallPerMin(INTERVAL)
    if not porMin or porMin <= 0 then return nil end
    return valor / porMin
end

local function prazo(valor, hist)
    local m = acabaEm(valor, hist)
    if not m then return "" end
    if m < 90 then return string.format(" ~%dmin", math.floor(m + 0.5)) end
    return string.format(" ~%.1fh", m / 60)
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
    -- Balanco do buffer: mais util que o throughput do detector, porque tem SINAL --
    -- diz se esta carregando ou drenando. E funciona sem o detector estar na linha.
    -- (medido no servidor: buffer caindo 132 FE/s = 6.6 FE/t, com o detector em 0.)
    if reading.energy and reading.energy.capacity > 0 then
        hEnergy:push(reading.energy.stored)
        local porSeg = hEnergy:slopePerSec(INTERVAL)
        netFeTick = porSeg and (porSeg / 20) or nil   -- 20 ticks por segundo
        if netFeTick then
            netMax = math.max(netMax, math.abs(netFeTick))
            hNet:push(netFeTick)
        end
    end

    local fuelMin = settings.get("mosaic.reactor.fuelMin") or 8
    alert("combustivel", low("combustivel", reading.fuel.count, fuelMin),
        "Combustivel baixo: " .. reading.fuel.count .. " uraninita")

    if reading.tank then
        local waterMin = settings.get("mosaic.reactor.waterMin") or 500
        alert("agua", low("agua", reading.tank.amount, waterMin),
            "Agua baixa: " .. reading.tank.amount .. " mB")
    end

    -- Multiblock desmontado: o unico sinal util que sobrou no NBT da peca.
    if reading.built ~= nil then
        alert("montagem", reading.built == false, "Reator DESMONTADO")
    end

    -- Projecao no lugar da temperatura: avisa antes de acabar, nao depois.
    local mFuel = acabaEm(reading.fuel.count, hFuel)
    alert("prazo do combustivel", mFuel ~= nil and low("prazo do combustivel", mFuel, 10),
        string.format("Combustivel acaba em ~%d min no ritmo atual", math.floor((mFuel or 0) + 0.5)))
    if reading.tank then
        local mWater = acabaEm(reading.tank.amount, hWater)
        alert("prazo da agua", mWater ~= nil and low("prazo da agua", mWater, 10),
            string.format("Agua acaba em ~%d min no ritmo atual", math.floor((mWater or 0) + 0.5)))
    end

    -- Buffer drenando: quanto falta para zerar. Mais acionavel que "energia baixa",
    -- porque 90% caindo rapido e pior que 20% estavel.
    if reading.energy and netFeTick and netFeTick < 0 then
        local minutos = reading.energy.stored / (-netFeTick * 20 * 60)
        alert("energia drenando", low("energia drenando", minutos, 15),
            string.format("Buffer zera em ~%d min no ritmo atual", math.floor(minutos + 0.5)))
    else
        alert("energia drenando", false, "")
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

-- Largura do rotulo acompanha a coluna. "Combustivel" tem 11: com 0.4 uma coluna
-- de 28 ja cabe o nome inteiro, e abaixo disso encolhe em vez de estourar.
local function labelWidth(cw)
    return math.max(5, math.min(11, math.floor(cw * 0.4)))
end

-- Uma barra rotulada dentro de uma coluna que comeca em x e tem cw de largura.
local function row(t, x, y, cw, label, value, frac, color)
    local lw = labelWidth(cw)
    -- O valor nunca pode empurrar a barra para fora da coluna: corta ele primeiro,
    -- senao a linha vaza para a coluna vizinha.
    value = strutil.ellipsis(value, math.max(1, cw - lw - 6))
    t.setCursorPos(x, y)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.write(" " .. strutil.pad(strutil.ellipsis(label, lw), lw))
    local bx = x + lw + 1
    local barW = math.max(3, cw - lw - 2 - #value - 1)
    bar(t, bx, y, barW, frac, color)
    t.setCursorPos(bx + barW + 1, y)
    t.setTextColor(theme.appFg)
    t.write(value)
end

-- Faixa de grafico com titulo. Devolve a primeira linha livre depois dela.
local function drawChart(t, x, cw, y, ch, hist, color, nome, minimo)
    if ch < 3 or hist.n < 2 then return y end
    t.setCursorPos(x, y)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.mutedFg)
    t.write(strutil.pad(strutil.ellipsis(nome .. " (" .. hist.n .. ")", cw), cw))
    chart.line(t, { x = x, y = y + 1, w = cw, h = ch - 1, data = hist.data,
                    min = minimo, fg = color, bg = colors.black, fill = true })
    return y + ch
end

-- As barras, numa coluna. Devolve a primeira linha livre.
local function drawGauges(t, x, cw, y0)
    local y = y0
    -- Coluna estreita nao comporta o "~26min" junto do valor: ou some a barra.
    local comPrazo = cw >= 34
    local function put(label, value, frac, color)
        row(t, x, y, cw, label, value, frac, color)
        y = y + 1
    end
    put("Combustivel", reading.fuel.count .. (comPrazo and prazo(reading.fuel.count, hFuel) or ""),
        reading.fuel.count / 64, colors.lime)
    if reading.coolant.count > 0 then
        put("Gelo seco", tostring(reading.coolant.count), reading.coolant.count / 64, colors.lightBlue)
    end
    if reading.tank then
        put("Agua", reading.tank.amount .. " mB" .. (comPrazo and prazo(reading.tank.amount, hWater) or ""),
            tankMax > 0 and (reading.tank.amount / tankMax) or 0, colors.blue)
    end
    if reading.energy and reading.energy.capacity > 0 then
        -- math.floor: em Lua 5.3 o %d recusa float, e o percentual e fracionario.
        put("Energia", string.format("%d%%", math.floor(reading.energy.percent)),
            reading.energy.percent / 100, colors.red)
    end
    if netFeTick then
        -- Com sinal: verde carregando, laranja drenando. E o numero que responde
        -- "produzo mais do que gasto?", que o throughput sozinho nao responde.
        local mag = math.abs(netFeTick)
        put("Balanco", (netFeTick >= 0 and "+" or "-") ..
            (mag >= 1000 and strutil.short(mag) or string.format("%.1f", mag)) .. " FE/t",
            netMax > 0 and (mag / netMax) or 0,
            netFeTick >= 0 and colors.lime or colors.orange)
    end
    if reading.energy and reading.energy.rate and reading.energy.rate > 0 then
        put("Saida", strutil.short(reading.energy.rate) .. " FE/t",
            rateMax > 0 and (reading.energy.rate / rateMax) or 0, colors.yellow)
    end
    return y
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

    -- Tela baixa (monitor pequeno) nao pode gastar linha em branco depois do titulo.
    local topo = (th < 14) and 2 or 3
    -- Tela larga (o 3x2 da 57x24 na escala 0.5) ganha duas colunas: barras a
    -- esquerda, graficos a direita, que e onde a densidade do sub-pixel aparece.
    -- 56: abaixo disso as duas colunas ficam com 25 e cortam "Combustivel". A janela
    -- do computador (51) fica melhor em coluna unica; o monitor 3x2 (57) em duas.
    local largo = tw >= 56
    local colW = largo and math.floor(tw * 0.5) or tw

    local y = drawGauges(t, 1, colW, topo)

    -- Diz o que falta em vez de mostrar zero, que seria mentira.
    local faltando = {}
    if not hw.blockReader then faltando[#faltando + 1] = "Block Reader" end
    if not (reading.energy and reading.energy.rate and reading.energy.rate > 0) then
        faltando[#faltando + 1] = "Detector na linha"
    end
    if #faltando > 0 and y < th then
        t.setCursorPos(2, y)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.mutedFg)
        t.write(strutil.ellipsis("falta: " .. table.concat(faltando, ", "), colW - 2))
        y = y + 1
    end

    if largo then
        -- Dois graficos empilhados na coluna da direita, dividindo a altura.
        local cx, cw = colW + 2, tw - colW - 1
        local disp = th - topo + 1
        local metade = math.floor(disp / 2)
        local yy = topo
        if hEnergy.n > 1 then
            yy = drawChart(t, cx, cw, yy, metade, hEnergy, colors.red, "Buffer FE", 0)
        else
            yy = drawChart(t, cx, cw, yy, metade, hFuel, colors.lime, "Combustivel", 0)
        end
        if hNet.n > 1 then
            -- Sem min = 0: o balanco fica negativo quando drena, e cortar isso
            -- em zero esconderia justamente a informacao que interessa.
            drawChart(t, cx, cw, yy, disp - metade, hNet, colors.orange, "Balanco FE/t")
        else
            drawChart(t, cx, cw, yy, disp - metade, hWater, colors.blue, "Agua", 0)
        end
    else
        -- Coluna unica: um grafico embaixo, com teto. Solto, ele viraria um bloco
        -- de cor ocupando a tela toda num monitor baixo.
        y = y + ((th < 14) and 0 or 1)
        local sobra = math.min(7, th - y + 1)
        local serie, cor2, nome, mn = hFuel, colors.lime, "Combustivel", 0
        if hNet.n > 1 then serie, cor2, nome, mn = hNet, colors.orange, "Balanco FE/t", nil
        elseif hEnergy.n > 1 then serie, cor2, nome, mn = hEnergy, colors.red, "Buffer FE", 0 end
        drawChart(t, 1, tw, y, sobra, serie, cor2, nome, mn)
    end
end

-- Maior escala de texto que ainda deixa o painel caber: texto grande se le de
-- longe, mas nao pode espremer as barras. Medido no servidor: um monitor 2x2 so
-- serve a 0.5 (36x10); um maior aguenta 1 e fica bem mais legivel de longe.
local monitorScale
local function fitMonitor(m)
    -- Se a escala menor render uma tela larga, ela vence: e a unica que abre o
    -- layout de duas colunas com grafico grande (um 3x2 da 57x24 assim, contra
    -- 29x12 na escala 1). Texto menor, mas muito mais informacao na parede.
    m.setTextScale(0.5)
    if m.getSize() >= 56 then monitorScale = 0.5 return end
    -- Senao, a MAIOR escala que ainda deixa o painel caber: num monitor pequeno
    -- vale mais ler de longe do que espremer barra.
    for _, s in ipairs({ 1.5, 1, 0.5 }) do
        m.setTextScale(s)
        local mw, mh = m.getSize()
        if mw >= 26 and mh >= 8 then monitorScale = s return end
    end
    m.setTextScale(0.5)
    monitorScale = 0.5
end

local function drawMonitor()
    if not hw.monitor then return end
    local ok = pcall(function()
        if not monitorScale then fitMonitor(hw.monitor) end
        drawPanel(hw.monitor, 0)
    end)
    if not ok then hw.monitor, monitorScale = nil, nil end   -- monitor quebrado no jogo
end

-- ---------------------------------------------------------------- janela
local f = ui.form()
local mode = "painel"
local logList

local SIDES = { front = true, back = true, top = true, bottom = true, left = true, right = true }

-- Inventarios que servem de deposito de combustivel.
-- pushItems/pullItems so funcionam DENTRO DA MESMA REDE: medido no servidor, um bau
-- encostado no computador ("right") da "Source does not exist" para um reator que
-- vem por cabo. Entao, se o reator e de rede, so oferece inventarios de rede --
-- senao o app deixaria escolher uma opcao que falha calada.
local function inventories()
    local reactorEmRede = hw.reactorName ~= nil and not SIDES[hw.reactorName]
    local out = { "(nenhum)" }
    for _, n in ipairs(peripheral.getNames()) do
        if n ~= hw.reactorName and (not reactorEmRede or not SIDES[n]) then
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
local nav = {}
local function tab(label, m)
    local b
    b = f:add(ui.button { x = navX, y = h, text = label, pinned = true,
        alt = true, onClick = function() setMode(m) end })
    nav[#nav + 1] = b
    navX = navX + b:width() + 1
    return b
end
tab("Painel", "painel")
tab("Config", "config")
tab("Registro", "registro")

nav[#nav + 1] = f:add(ui.button { x = navX, y = h, text = "Parar", pinned = true, bg = colors.red, fg = colors.white,
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
cy = cy + 1
local chestHint = f:add(ui.label { x = 2, y = cy, w = w - 3, tab = "config",
    fg = colors.orange, text = "" })
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
    -- Medido: so a peca EXTRATORA do multiblock publica energy_storage. Ligar o
    -- cabo em outra peca da inventario e tanque, mas nenhuma leitura de energia.
    if hw.reactor and not hw.reactor.getEnergy then
        lines[#lines + 1] = "[!] Esta face do reator nao da energia."
        lines[#lines + 1] = "    Ligue o cabo na peca extratora."
    end
    if reading.coreHint then
        -- O leitor esta numa peca. O nucleo guarda a temperatura, mas fica cercado
        -- de pecas no meio do multiblock: nao da para encostar nada nele sem
        -- desmontar o reator. Informa e para de pedir -- nao e' bug, e' o mod.
        local c = reading.coreHint
        lines[#lines + 1] = "[i] Le uma peca. O nucleo esta em"
        lines[#lines + 1] = "    " .. c.x .. " " .. c.y .. " " .. c.z .. ", cercado: sem temperatura."
        lines[#lines + 1] = "    Usando projecao de consumo."
    else
        mark("Block Reader", hw.blockReader ~= nil, "estado do multiblock")
    end
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
        chestHint.text = (#chestBox.items <= 1)
            and "nenhum na rede: ponha um modem com fio no bau" or ""
        if mode == "registro" then setMode("registro") end
        f.dirty = true
        return true
    elseif ev == "term_resize" then
        -- A janela pode ser maximizada depois de aberta: sem reposicionar, a barra
        -- de abas fica presa na altura antiga, no meio do formulario.
        w, h = term.getSize()
        for _, b in ipairs(nav) do b.y = h end
        logList.w, logList.h = w, h - 1
        hwLabel.w = w - 3
        chestBox.w = math.min(28, w - 4)
        f.dirty = true
        return true
    end
end

f:run()
