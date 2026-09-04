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
settings.define("mosaic.reactor.autofeed", { description = "Repor sozinho o que faltar", type = "boolean", default = false })
settings.define("mosaic.reactor.target", { description = "Completar cada item ate", type = "number", default = 64 })
settings.define("mosaic.reactor.alerts", { description = "Avisar no chat", type = "boolean", default = true })

local hw = powah.discover()
local reading = powah.read(hw)
local firing = {}                       -- alertas ativos, para nao repetir no chat
-- Uma serie por ITEM, criada quando o item aparece pela primeira vez. Antes so'
-- existiam duas series cravadas (combustivel e agua) e os outros tres slots do reator
-- nao tinham historico nenhum.
local hItem = {}
local function serieDe(id)
    hItem[id] = hItem[id] or chart.history(60)
    return hItem[id]
end
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

-- O que esta dentro do reator agora, na ordem dos slots. Recalculado a cada amostra.
local itens = {}

-- Completa tudo o que falta, do bau para o reator, e conta o que entrou. Uma linha por
-- item no registro e uma frase so' no chat: reposicao automatica que fala demais vira
-- ruido e o operador para de ler.
local function reabastece(chest, automatico)
    local alvo = settings.get("mosaic.reactor.target") or 64
    local feito, err = powah.topUp(hw, chest, reading, nil, alvo)
    if err then
        say("falhou repor: " .. tostring(err))
        return 0, err
    end
    local total, partes = 0, {}
    for _, ff in ipairs(feito) do
        total = total + ff.moved
        partes[#partes + 1] = ff.label .. " +" .. ff.moved .. " (" .. ff.para .. ")"
        say("+ " .. ff.label .. " +" .. ff.moved .. " -> " .. ff.para .. ", de " .. chest)
    end
    if total > 0 and chatOn() then
        hal.chat((automatico and "Reposto: " or "Abastecido: ") .. table.concat(partes, ", "), "Reator")
    end
    return total
end

local function sample()
    reading = powah.read(hw)
    if reading.error then
        alert("reator", true, "Sem leitura do reator: " .. reading.error)
        return
    end
    alert("reator", false, "")

    -- Historico de todos os itens, nao so' do combustivel.
    itens = powah.consumables(reading)
    for _, it in ipairs(itens) do serieDe(it.name):push(it.count) end
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

    -- Um alerta por item do reator. Antes so' a uraninita tinha aviso; o gelo seco
    -- podia zerar sem ninguem saber, e ele e' consumido de verdade (medido no servidor).
    for _, it in ipairs(itens) do
        alert("item:" .. it.name, low("item:" .. it.name, it.count, fuelMin),
            it.label .. " baixo: " .. it.count)
    end

    -- Item que sumiu do reator: o alerta dele nao pode ficar preso ligado para sempre.
    for chave in pairs(firing) do
        local id = chave:match("^item:(.+)$")
        if id then
            local achou = false
            for _, it in ipairs(itens) do if it.name == id then achou = true end end
            if not achou then alert(chave, false, "") end
        end
    end

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
    local mFuel = acabaEm(reading.fuel.count, serieDe(powah.FUEL))
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
    if settings.get("mosaic.reactor.autofeed") and chest then
        -- Repoe QUALQUER item que esteja abaixo do minimo, nao so' o combustivel: quem
        -- diz do que o reator precisa e' o proprio reator, pelo que tem dentro.
        local precisa = false
        for _, it in ipairs(itens) do if it.count < fuelMin then precisa = true end end
        if precisa then reabastece(chest, true) end
    end
end

-- ---------------------------------------------------------------- painel

-- Uma barra: a parte cheia na cor do recurso, o resto num cinza neutro.
--
-- Cinza e nao azul: azul era a cor do tanque de agua, entao o "vazio" de toda barra
-- tinha a mesma cor que o cheio de uma delas, e de longe nao dava para saber qual era
-- qual.
local function bar(t, x, y, bw, frac, color)
    frac = math.max(0, math.min(1, frac or 0))
    local n = math.floor(frac * bw + 0.5)
    -- Valor pequeno mas diferente de zero merece pelo menos um ponto: "quase nada" e
    -- "nada" sao coisas diferentes num reator.
    if n == 0 and frac > 0 then n = 1 end
    t.setCursorPos(x, y)
    t.setBackgroundColor(color)
    t.write(string.rep(" ", n))
    t.setBackgroundColor(colors.gray)
    t.write(string.rep(" ", bw - n))
    t.setBackgroundColor(theme.appBg)
end

-- As linhas do painel, montadas antes de desenhar.
--
-- Montar primeiro e desenhar depois nao e' capricho: e' o que permite alinhar os
-- numeros numa coluna so'. Antes cada linha calculava a propria largura, entao 46, 15,
-- 759 mB e -6.6 FE/t comecavam cada um numa coluna diferente e a leitura de relance
-- ficava impossivel.
local function medidas()
    local m = {}
    local function put(label, value, frac, color, dica)
        m[#m + 1] = { label = label, value = value, frac = frac, color = color, dica = dica }
    end
    for _, it in ipairs(itens) do
        put(it.label, tostring(it.count), it.count / it.limit, it.color, prazo(it.count, serieDe(it.name)))
    end
    if #itens == 0 then put("Reator vazio", "0", 0, colors.red) end
    if reading.tank then
        put("Agua", reading.tank.amount .. " mB",
            tankMax > 0 and (reading.tank.amount / tankMax) or 0, colors.blue,
            prazo(reading.tank.amount, hWater))
    end
    if reading.energy and reading.energy.capacity > 0 then
        -- Roxo e nao vermelho: o vermelho agora e' a cor do bloco de redstone, e duas
        -- barras da mesma cor com significados diferentes confundem de longe.
        put("Energia", string.format("%d%%", math.floor(reading.energy.percent)),
            reading.energy.percent / 100, colors.purple)
    end
    if netFeTick then
        -- Com sinal: verde carregando, laranja drenando. E o numero que responde
        -- "produzo mais do que gasto?", que a vazao sozinha nao responde.
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
    return m
end

-- Desenha as barras numa coluna que comeca em x e tem cw de largura, com rotulo e
-- numero cada um na sua coluna fixa. Devolve a primeira linha livre.
local function drawGauges(t, x, cw, y0)
    local m = medidas()
    if #m == 0 then return y0 end

    -- As tres colunas saem do conteudo, nao de numero cravado: rotulo pelo maior nome,
    -- numero pelo maior valor, e a barra fica com o que sobrar.
    local lw, vw = 5, 3
    for _, r in ipairs(m) do
        if #r.label > lw then lw = #r.label end
        if #r.value > vw then vw = #r.value end
    end
    lw = math.min(lw, math.max(5, math.floor(cw * 0.35)))
    vw = math.min(vw, math.max(3, math.floor(cw * 0.30)))

    -- O prazo ("~7min") so' entra se sobrar barra de verdade depois dele: numa coluna
    -- estreita ele comeria o desenho, e a barra e' o que se le de longe.
    local dw = 0
    for _, r in ipairs(m) do if r.dica and #r.dica > dw then dw = #r.dica end end
    if cw - lw - vw - dw - 4 < 8 then dw = 0 end

    local barW = cw - lw - vw - dw - 4
    local y = y0
    for _, r in ipairs(m) do
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.appFg)
        t.setCursorPos(x, y)
        t.write(" " .. strutil.pad(strutil.ellipsis(r.label, lw), lw) .. " ")
        if barW >= 3 then bar(t, x + lw + 2, y, barW, r.frac, r.color) end
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.appFg)
        t.setCursorPos(x + lw + 2 + math.max(0, barW) + 1, y)
        -- Numero encostado a DIREITA: e' o que faz a coluna de valores ficar reta.
        t.write(string.rep(" ", math.max(0, vw - #r.value)) .. r.value)
        if dw > 0 then
            t.setTextColor(theme.mutedFg)
            t.write(strutil.pad(r.dica or "", dw))
        end
        y = y + 1
    end
    return y
end

-- Faixa de grafico com titulo, escala e legenda. Devolve a primeira linha livre.
--
-- O grafico de antes era so' a mancha: sem eixo, sem numero, sem nome de unidade. Dava
-- para ver que subia ou descia e mais nada. Agora o titulo carrega o valor de agora e o
-- topo da escala, que e' o minimo para o desenho querer dizer alguma coisa.
local function drawChart(t, x, cw, y, ch, hist, color, nome)
    if ch < 3 or hist.n < 2 then return y end
    local atual = hist.data[hist.n]
    local lo, hi = atual, atual
    for i = 1, hist.n do
        local v = hist.data[i]
        if v < lo then lo = v end
        if v > hi then hi = v end
    end

    local function curto(v)
        local a = math.abs(v)
        if a >= 1000 then return strutil.short(v) end
        if a >= 10 or v == math.floor(v) then return string.format("%d", math.floor(v + 0.5)) end
        return string.format("%.1f", v)
    end

    -- Titulo no MESMO fundo do grafico: com o fundo do painel atras dele, a faixa preta
    -- comecava um caractere abaixo e o titulo parecia pertencer as barras, nao ao desenho.
    t.setCursorPos(x, y)
    t.setBackgroundColor(colors.black)
    t.setTextColor(color)
    local titulo = " " .. nome .. ": " .. curto(atual)
    local escala = curto(lo) .. ".." .. curto(hi) .. " "
    t.write(strutil.pad(strutil.ellipsis(titulo, cw), math.max(0, cw - #escala)))
    t.setTextColor(colors.lightGray)
    t.write(strutil.ellipsis(escala, cw))
    t.setBackgroundColor(theme.appBg)

    -- Linha, e nao area preenchida.
    --
    -- Com preenchimento e escala presa no zero, uma serie que vive perto do maximo
    -- (o buffer a 97%, a uraninita em 46 de 47) virava um retangulo solido de cor: o
    -- desenho ficava bonito e nao dizia nada. A linha mostra a FORMA, que e' o que um
    -- grafico tem para dar, e a faixa vai escrita no titulo para o desenho nao mentir
    -- sobre a escala.
    chart.line(t, { x = x, y = y + 1, w = cw, h = ch - 1, data = hist.data,
                    fg = color, bg = colors.black })
    return y + ch
end

-- ---------------------------------------------------------------- painel 3D
--
-- O mesmo painel em barras de tres dimensoes: uma coluna por recurso, altura pela
-- porcentagem, cor igual a da barra chata, e legenda ao lado com o numero.
--
-- E' enfeite assumido, e por isso mora numa aba propria: quem esta operando o reator
-- le numero, nao perspectiva. Mas e' enfeite honesto — a altura e' a mesma fracao que a
-- barra mostra, entao nao ha nada aqui que o painel normal nao diga.
local pixel = mosaic.lib("pixel")
local mesh = mosaic.lib("mesh")
local three = mosaic.lib("three")
local shade = mosaic.lib("shade")

local giro3d, alt3d = 0.7, 0.8
local c3d, f3d, cw3d, ch3d

-- Monta a cena do zero a cada quadro: sao ~100 triangulos, e guardar malha entre quadros
-- exigiria saber quando um recurso entrou ou saiu do reator. Medido no CraftOS-PC, a
-- Suzanne inteira (968 triangulos) leva 3 ms; isto aqui nao chega perto de doer.
local function cena3d()
    local m = medidas()
    if #m == 0 then return nil, m end
    local n = #m
    local corpo = mesh.new()
    local ALTURA = 2.4

    -- As barras ficam num CIRCULO, e nao numa fileira.
    --
    -- Em fileira a cena tem angulo ruim: a meia volta do giro voce olha a fila de perfil,
    -- as colunas se escondem umas atras das outras e sobra um borrao — foi o que o
    -- primeiro print mostrou. No circulo toda volta mostra todas as barras, e ainda da'
    -- a nocao de profundidade que uma fileira vista de frente nao da'.
    local raio = math.max(1.0, n * 0.30)
    for i = 1, n do
        local ang = (i - 1) * 2 * math.pi / n
        local x, z = math.sin(ang) * raio, math.cos(ang) * raio

        -- Uma base por barra: e' o chao que diz onde a coluna comeca quando ela e' baixa.
        local piso = mesh.cube { top = colors.lightGray, side = colors.gray, bottom = colors.gray }
        piso:scale(0.86, 0.08, 0.86):translate(x - 0.43, -0.08, z - 0.43)
        for _, t in ipairs(piso.tris) do corpo.tris[#corpo.tris + 1] = t end

        -- Cor por ORIENTACAO da face (topo claro, lados um degrau abaixo), e nao por
        -- Lambert. E' a mesma licao que o mesh.voxels ja tinha aprendido: caixa alinhada
        -- aos eixos so' tem seis normais, e luz direcional joga metade delas no degrau
        -- escuro — no primeiro print as colunas apareceram quase todas cinzas, com um
        -- fiapo da cor de verdade. Assim cada barra fica com a propria cor de longe.
        local base = m[i].color
        local lado = shade.darker[base] or colors.gray
        local alt = math.max(0.08, (m[i].frac or 0) * ALTURA)
        local barra = mesh.cube { top = base, side = lado, bottom = lado }
        barra:scale(0.68, alt, 0.68):translate(x - 0.34, 0, z - 0.34)
        for _, t in ipairs(barra.tris) do corpo.tris[#corpo.tris + 1] = t end
    end
    -- Sem shade.apply nenhum: a cor ja veio da orientacao da face, e passar uma luz por
    -- cima disso desfaria justamente o que resolveu o problema.
    corpo.closed = true
    return corpo, m
end

local function draw3d(t, reserva)
    local tw, th = t.getSize()
    th = th - (reserva or 0)
    t.setBackgroundColor(theme.appBg)
    t.setTextColor(theme.appFg)
    t.clear()

    local corpo, m = cena3d()
    if not corpo then
        t.setCursorPos(2, 2)
        t.write("Sem leitura do reator.")
        return
    end

    -- A legenda fica embaixo (tela estreita) ou a direita (tela larga), e o desenho
    -- pega o resto. Duas colunas de legenda quando ha altura de sobra.
    local legW = 0
    for _, r in ipairs(m) do
        local n = #r.label + #r.value + 4
        if n > legW then legW = n end
    end
    local aoLado = tw - legW >= 24
    local gw = aoLado and (tw - legW) or tw
    local gh = aoLado and th or math.max(3, th - #m)

    if not c3d or cw3d ~= gw or ch3d ~= gh then
        c3d = pixel.new(gw, gh, colors.black)
        f3d = three.frame(c3d)
        -- 45 graus e nao os 70 de fabrica: com o campo aberto e a camera perto, a
        -- perspectiva entorta tanto as colunas que o circulo deixa de parecer um
        -- circulo. Campo mais fechado e camera mais longe achatam o desenho e ele
        -- volta a se ler nos 62 x 51 pontos que a janela tem.
        f3d:setFoV(45)
        cw3d, ch3d = gw, gh
    end

    -- Enquadramento pela esfera que envolve a cena, contra a MENOR metade do canvas:
    -- e' o que faz caber tanto numa janela larga e baixa quanto num monitor alto.
    local x0, y0, z0, x1, y1, z1 = corpo:bounds()
    local cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    local raio = math.sqrt((x1 - cx) ^ 2 + (y1 - cy) ^ 2 + (z1 - cz) ^ 2)
    -- A esfera que envolve a cena ja e' folgada num circulo de barras (ela cobre os
    -- cantos, que projetam para os lados e nao para cima), entao a margem aqui e' 1,0.
    local dist = raio * f3d:begin().escala / (math.min(c3d.w, c3d.h) / 2)

    f3d:orbit({ cx, cy, cz }, dist, giro3d, alt3d)
    f3d:clear(colors.black)
    f3d:draw({ { model = corpo } })
    c3d:render(t, 1, 1)

    -- Legenda: quadradinho na cor, nome e valor. Sem ela o desenho e' so' cor bonita.
    local lx, ly = aoLado and (gw + 1) or 1, aoLado and 1 or (gh + 1)
    for _, r in ipairs(m) do
        if ly > th then break end
        t.setCursorPos(lx, ly)
        t.setBackgroundColor(r.color)
        t.write("  ")
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(theme.appFg)
        local espaco = math.max(0, tw - lx - 1 - #r.value - #r.label - 2)
        t.write(" " .. r.label .. string.rep(" ", espaco) .. r.value .. " ")
        ly = ly + 1
    end
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

    -- Os graficos preenchem TODA a altura que sobrou, seja ela qual for.
    --
    -- Antes o de coluna unica tinha teto de 7 linhas, e num monitor alto o resto da
    -- parede ficava cinza — foi o buraco que apareceu na foto do servidor. Agora a
    -- sobra e' repartida entre quantos graficos couberem, e o ultimo encosta embaixo.
    local candidatos = {}
    local function serie(hist, cor, nome)
        if hist and hist.n > 1 then candidatos[#candidatos + 1] = { hist, cor, nome } end
    end
    -- Ordem de importancia: o que responde "vai durar?" antes do que enfeita.
    serie(hNet, colors.orange, "Balanco FE/t")
    serie(hEnergy, colors.purple, "Buffer FE")
    for _, it in ipairs(itens) do serie(serieDe(it.name), it.color, it.label) end
    serie(hWater, colors.blue, "Agua mB")
    serie(hRate, colors.yellow, "Saida FE/t")

    local gx, gw = 1, tw
    local gy, gh = y + ((th < 14) and 0 or 1), 0
    if largo then
        -- Em coluna dupla os graficos ficam a direita e usam a altura inteira, do topo
        -- das barras ate' embaixo, e nao so' o que sobra debaixo delas.
        gx, gw, gy = colW + 2, tw - colW - 1, topo
    end
    gh = th - gy + 1
    if gh >= 3 and #candidatos > 0 then
        -- Cada grafico quer ao menos 4 linhas (titulo + 3 de desenho). Quantos cabem
        -- e' o que decide, e a divisao inteira distribui a sobra nos primeiros.
        local quantos = math.max(1, math.min(#candidatos, math.floor(gh / 4)))
        local base = math.floor(gh / quantos)
        local resto = gh - base * quantos
        for i = 1, quantos do
            local alt = base + (i <= resto and 1 or 0)
            local c = candidatos[i]
            drawChart(t, gx, gw, gy, alt, c[1], c[2], c[3])
            gy = gy + alt
        end
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

local animar   -- definida junto do temporizador, la' embaixo

local function setMode(m)
    mode = m
    if animar then animar(m == "3d") end
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
    if mode == "painel" then drawPanel(t, 1)
    elseif mode == "3d" then draw3d(t, 1) end
end

-- ---- barra de abas, presa no rodape (nao rola com o conteudo)
-- A barra de abas cabe em janela estreita em vez de ser cortada.
--
-- Aberto pelo caminho o app nasce com 36 colunas, e pela area de trabalho com 51: com os
-- nomes longos a barra passava da borda e o ultimo botao sumia sem nenhum aviso. Entao
-- ela mede antes — nome longo se couber, curto se nao — e o Parar so' entra se ainda
-- sobrar espaco. Ele tambem esta na aba Controle, entao perde-lo aqui perde o atalho,
-- nao a acao.
local ABAS = {
    { longo = "Painel",   curto = "Painel", modo = "painel" },
    { longo = "Controle", curto = "Acoes",  modo = "controle" },
    { longo = "Config",   curto = "Config", modo = "config" },
    { longo = "3D",       curto = "3D",     modo = "3d" },
    { longo = "Registro", curto = "Log",    modo = "registro" },
}
local PARAR = 7   -- #"Parar" + 2

local navX = 1
local nav = {}
local abaBotoes = {}

local function larguraDas(campo, comParar, gap)
    local total = comParar and (PARAR + gap) or 0
    for _, a in ipairs(ABAS) do total = total + #a[campo] + 2 + gap end
    return total - gap
end

-- Tenta na ordem do mais legivel para o mais apertado. O espaco de um caractere entre os
-- botoes e' o primeiro a cair: cada botao ja tem a propria folga interna, entao colados
-- eles continuam se lendo — e "Controle" colado e' melhor que "Acoes" separado. Foi por
-- UMA coluna que a barra inteira caia para os nomes curtos em 51 colunas.
local function montaBarra()
    for _, tentativa in ipairs({
        { "longo", true, 1 }, { "longo", true, 0 },
        { "curto", true, 1 }, { "curto", true, 0 },
        { "curto", false, 1 }, { "curto", false, 0 },
    }) do
        if larguraDas(tentativa[1], tentativa[2], tentativa[3]) <= w then
            return tentativa[1], tentativa[2], tentativa[3]
        end
    end
    return "curto", false, 0
end

local campoAba, comParar, gapAba = montaBarra()

local function tab(label, m)
    local b
    b = f:add(ui.button { x = navX, y = h, text = label, pinned = true,
        alt = true, onClick = function() setMode(m) end })
    nav[#nav + 1] = b
    navX = navX + b:width() + gapAba
    return b
end
for _, a in ipairs(ABAS) do
    abaBotoes[#abaBotoes + 1] = tab(a[campoAba], a.modo)
end

-- Os tres botoes de acao. "Parar" existia sozinho desde o comeco, o que era estranho:
-- parar e' tirar a uraninita do reator, entao ligar e' po-la de volta, e esse botao
-- nunca tinha sido escrito. Agora o par esta completo, e no meio deles o abastecimento
-- manual, que e' a mesma coisa que o automatico faz — so' que na hora que voce mandar.
--
-- Todos pedem o bau da aba Config, porque sem inventario de destino nao ha para onde
-- tirar o combustivel nem de onde trazer.
local function precisaDeBau(titulo)
    local chest = settings.get("mosaic.reactor.chest")
    if chest then return chest end
    ui.msgbox("Escolha antes, na aba Config, o bau com os itens do reator.", titulo)
    setMode("config")
    return nil
end

-- So' o Parar fica na barra de abas, e por um motivo: e' o botao de emergencia, e
-- emergencia nao pode estar atras de uma aba. Iniciar e Abastecer vivem na aba
-- Controle, com uma linha explicando o que cada um faz — em 51 colunas os seis botoes
-- juntos nao cabiam, e cortados ficariam piores que escondidos.
local function iniciar()
    local chest = precisaDeBau("Iniciar")
    if not chest then return end
    local alvo = settings.get("mosaic.reactor.target") or 64
    -- Reator parado esta sem uraninita nenhuma, entao nao ha item dentro para o
    -- topUp completar: o combustivel entra pelo `feed`, que sabe achar o slot vazio.
    local n = powah.feed(hw, chest, powah.fuelSlot(hw, reading), alvo)
    if n > 0 then
        say("> iniciado: " .. n .. " uraninita de " .. chest)
        if chatOn() then hal.chat("INICIADO: " .. n .. " uraninita no reator", "Reator") end
    else
        ui.msgbox("Nao achei uraninita em " .. chest .. ".", "Iniciar")
    end
    sample()
    f.dirty = true
end

local function abastecer()
    local chest = precisaDeBau("Abastecer")
    if not chest then return end
    local total = reabastece(chest, false)
    if total == 0 then mosaic.notify("Ja esta tudo no alvo") end
    sample()
    f.dirty = true
end

local function parar()
    local chest = precisaDeBau("Parada")
    if not chest then return end
    if not ui.confirm("Retirar todo o combustivel do reator?", "Parada de emergencia") then return end
    local n, err = powah.pullFuel(hw, chest, reading)
    say(n > 0 and ("- parado: " .. n .. " uraninita para " .. chest)
        or ("falhou parar: " .. tostring(err)))
    if n > 0 and chatOn() then hal.chat("PARADA: combustivel retirado do reator", "Reator") end
    sample()
    f.dirty = true
end

local pararBtn = f:add(ui.button { x = navX, y = h, text = "Parar", pinned = true,
    bg = colors.red, fg = colors.white, onClick = parar })
pararBtn.visible = comParar
nav[#nav + 1] = pararBtn

-- ---- aba Controle
--
-- Uma tela so' para as tres alavancas que existem, cada uma com uma linha dizendo o que
-- faz. O reator do Powah nao tem liga/desliga: o que liga e desliga e' haver ou nao
-- uraninita dentro dele. Como isso nao e' obvio para quem chega, esta escrito na tela.
local cty = 2
local function acao(label, cor, dica, fn)
    f:add(ui.button { x = 2, y = cty, text = label, bg = cor, fg = colors.white,
        tab = "controle", onClick = fn })
    f:add(ui.label { x = 13, y = cty, w = w - 14, text = dica, tab = "controle",
        fg = theme.mutedFg })
    cty = cty + 2
end

f:add(ui.label { x = 1, y = 1, w = w, text = " Controle do reator", tab = "controle",
    bg = theme.accent, fg = theme.accentFg })
cty = 3
acao("Iniciar", colors.green, "poe uraninita e liga", function() iniciar() end)
acao("Abastecer", colors.blue, "completa tudo que falta", function() abastecer() end)
acao("Parar", colors.red, "tira a uraninita e desliga", function() parar() end)

local estadoLabel = f:add(ui.text { x = 2, y = cty, w = w - 3, h = 9, text = "", tab = "controle" })

-- O texto de estado explica em palavras o que as barras dizem em cor, para quem abriu o
-- app pela primeira vez entender o que esta olhando.
local function estadoTexto()
    if reading.error then return "Sem leitura do reator.\n" .. reading.error end
    local l = {}
    local combustivel = 0
    for _, it in ipairs(itens) do
        if it.name == powah.FUEL then combustivel = it.count end
    end
    l[#l + 1] = combustivel > 0
        and ("LIGADO - " .. combustivel .. " uraninita dentro")
        or "PARADO - sem uraninita dentro"
    local chest = settings.get("mosaic.reactor.chest")
    l[#l + 1] = chest and ("Bau: " .. chest) or "Bau: nenhum escolhido (aba Config)"
    l[#l + 1] = settings.get("mosaic.reactor.autofeed")
        and ("Reposicao automatica LIGADA, ate " .. (settings.get("mosaic.reactor.target") or 64))
        or "Reposicao automatica desligada"
    l[#l + 1] = ""
    l[#l + 1] = "Dentro do reator:"
    if #itens == 0 then
        l[#l + 1] = "  (vazio)"
    else
        for _, it in ipairs(itens) do
            l[#l + 1] = "  " .. it.label .. ": " .. it.count .. "/" .. it.limit
        end
    end
    return table.concat(l, "\n")
end

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

section("Abastecimento")
field("Bau com os itens do reator:")
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
field("Completar cada item ate:")
local targetBox = f:add(ui.textbox { x = 2, y = cy, w = 10,
    text = tostring(settings.get("mosaic.reactor.target") or 64), tab = "config" })
f:add(ui.label { x = 13, y = cy, w = w - 14, tab = "config", fg = theme.mutedFg,
    text = "vale para todo item do reator" })
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
    local alvo = tonumber(targetBox.text)
    if not fuelMin or not waterMin or not alvo then
        ui.msgbox("Os limites precisam ser numeros.", "Config")
        return
    end
    if alvo < 1 or alvo > 64 then
        ui.msgbox("O alvo tem de ficar entre 1 e 64: um slot nao guarda mais que isso.", "Config")
        return
    end
    local chest = chestBox:current()
    settings.set("mosaic.reactor.chest", chest ~= "(nenhum)" and chest or nil)
    settings.set("mosaic.reactor.fuelMin", fuelMin)
    settings.set("mosaic.reactor.waterMin", waterMin)
    settings.set("mosaic.reactor.autofeed", autofeedBox.checked == true)
    settings.set("mosaic.reactor.target", alvo)
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
    -- Temperatura saiu da interface de proposito. Ela so' existe no NBT do nucleo do
    -- multiblock, o nucleo fica cercado de pecas e nenhum Block Reader alcanca ele sem
    -- desmontar o reator. Explicar isso em toda tela era ruido sobre uma coisa que nunca
    -- vai existir; o sinal util no lugar dela e' o prazo ("acaba em ~7min"), que ja esta
    -- nas barras.
    mark("Block Reader", hw.blockReader ~= nil, "estado do multiblock")
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

-- A cena 3D gira sozinha, e num tique de 1 s isso seria um solavanco por segundo. Ela
-- tem o proprio temporizador, de 0,1 s, e ele so' existe enquanto a aba 3D esta na
-- frente: girar uma cena que ninguem esta vendo gasta o computador a toa.
local ANIM = 0.1
local giroTimer = nil
animar = function(ligar)
    if ligar and not giroTimer then giroTimer = os.startTimer(ANIM)
    elseif not ligar then giroTimer = nil end
end

f.onEvent = function(_, ev, id)
    if ev == "timer" and giroTimer and id == giroTimer then
        if mode == "3d" and mosaic.focused() == mosaic.current() then
            giro3d = giro3d + 0.05
            giroTimer = os.startTimer(ANIM)
            f.dirty = true
        else
            giroTimer = nil
        end
        return true
    elseif ev == "timer" and id == timer then
        timer = os.startTimer(INTERVAL)
        sample()
        drawMonitor()
        hwLabel.text = hardwareText()
        estadoLabel.text = estadoTexto()
        chestHint.text = (#chestBox.items <= 1)
            and "nenhum na rede: ponha um modem com fio no bau" or ""
        if mode == "registro" then setMode("registro") end
        f.dirty = true
        return true
    elseif ev == "key" and mode == "3d" then
        if id == keys.left then giro3d = giro3d - 0.2 f.dirty = true return true
        elseif id == keys.right then giro3d = giro3d + 0.2 f.dirty = true return true
        elseif id == keys.up then alt3d = math.min(1.3, alt3d + 0.12) f.dirty = true return true
        elseif id == keys.down then alt3d = math.max(-0.2, alt3d - 0.12) f.dirty = true return true
        elseif id == keys.space then animar(giroTimer == nil) return true
        end
    elseif ev == "term_resize" then
        -- A janela pode ser maximizada depois de aberta: sem reposicionar, a barra
        -- de abas fica presa na altura antiga, no meio do formulario.
        w, h = term.getSize()
        -- Janela maximizada depois de aberta cabe mais texto: refaz os rotulos em vez de
        -- manter os curtos escolhidos quando ela era estreita.
        local campo, quer, gap = montaBarra()
        local x = 1
        for i, a in ipairs(ABAS) do
            abaBotoes[i].text = a[campo]
            abaBotoes[i].x = x
            x = x + abaBotoes[i]:width() + gap
        end
        pararBtn.x, pararBtn.visible = x, quer
        for _, b in ipairs(nav) do b.y = h end
        logList.w, logList.h = w, h - 1
        hwLabel.w = w - 3
        estadoLabel.w = w - 3
        chestBox.w = math.min(28, w - 4)
        f.dirty = true
        return true
    end
end

f:run()
