-- Demo 3D: visualizador dos modelos de /os/share/models.
--
-- Nao aparece no menu Iniciar nem na pasta Programas de proposito. Para rodar, abra o
-- Arquivos, va em /os/demos e mande Executar.
--
-- E' o demo da onda 4: prova que um .obj feito no Blender, passado pelo tools/obj.js, abre
-- aqui com as cores certas e sem sair espelhado nem de dentro para fora.
local ui = mosaic.ui
local theme = mosaic.theme
local pixel = mosaic.lib("pixel")
local mesh = mosaic.lib("mesh")
local three = mosaic.lib("three")
local shade = mosaic.lib("shade")

local INTERVALO = 0.05        -- um tique do Minecraft; e' o teto de taxa que o CC permite

local f = ui.form()
local canvas, frame, cw, ch
local giro, altura = 0, 0.25    -- de proposito baixo: com a camera alta demais a agua do telhado enche a tela e a casa vira uma caixa
local rodando = true
local ms, quadros, marco, fps = 0, 0, os.epoch("utc"), 0

local nomes = mesh.list()
local atual, modelo, erro = 1, nil, nil

-- A luz acompanha a camera, por cima do ombro. Num visualizador quem gira e' o modelo, e uma
-- luz parada no mundo deixa metade das voltas mostrando so' o lado escuro: a casa inteira
-- caia em cinza e os quatro materiais viravam um so'.
--
-- O angulo sai da MESMA formula da camera no `orbit` (-sin, -cos), mais o ombro. Escrever a
-- direcao pela conta do orbit e nao por um `luz` solto foi o que consertou: com o sinal
-- trocado a luz ficava exatamente atras do modelo e dava tudo cinza de novo.
--
-- ALTURA_LUZ e' 0,5 e nao 0,8 de proposito. O vetor e' normalizado, entao quanto mais luz
-- vem de cima, menos sobra para o lado — com 0,8 as duas paredes visiveis (90 graus uma da
-- outra, 45 para a luz) caiam as duas em 0,55, bem em cima do corte do applyTinted.
local OMBRO, ALTURA_LUZ = 0.45, 0.5

-- Cada modelo vem no tamanho que o autor desenhou. Centrar e normalizar deixa a mesma
-- camera servir para todos, e e' o que o `mesh` ja sabe fazer.
local function carrega()
    modelo, erro = nil, nil
    if #nomes == 0 then erro = "nenhum modelo em /os/share/models" return end
    local m, err = mesh.load("/os/share/models/" .. nomes[atual] .. ".lua")
    if not m then erro = tostring(err) return end
    modelo = m:center():normalizeScale()
    shade.normals(modelo)
end

-- applyTinted, e nao apply: o modelo ja traz a cor de cada face do material do Blender, e a
-- luz so' escurece a partir dela. Com `apply` a casa inteira viraria cinza.
local function ilumina()
    if not modelo then return end
    local a = giro + OMBRO
    shade.applyTinted(modelo, -math.sin(a), ALTURA_LUZ, -math.cos(a), 0.35)
end

carrega()
ilumina()

local rodape = f:add(ui.label { x = 1, bottom = 0, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

-- Canvas e quadro guardados entre desenhos, refeitos so' quando a janela muda de tamanho
-- (recriar os dois todo quadro custa medidos 0,47 ms; ver docs/3d-medidas.md).
local function prepara(t)
    local W, H = t.getSize()
    local cols, rows = W, H - 1
    if cols < 4 or rows < 2 then canvas = nil return false end
    if not canvas or cw ~= cols or ch ~= rows then
        canvas = pixel.new(cols, rows, colors.black)
        frame = three.frame(canvas)
        cw, ch = cols, rows
    end
    return true
end

f.onDraw = function(_, t)
    if not prepara(t) then return end
    local inicio = os.epoch("utc")
    -- 1,7 e nao 2,2: o normalizeScale poe a MAIOR dimensao em 1, entao um modelo achatado
    -- (a Suzanne tem 2,73 de orelha a orelha e 1,97 de altura) sobra minusculo no meio da
    -- tela se a camera ficar longe.
    frame:orbit({ 0, 0, 0 }, 1.7, giro, altura)
    frame:clear(colors.black)
    if modelo then frame:draw({ { model = modelo } }) end
    canvas:render(t, 1, 1)
    ms = os.epoch("utc") - inicio
end

local function atualizaRodape()
    if erro then
        rodape.text = " " .. erro
    else
        rodape.text = string.format(" %s (%d/%d) | %d tri | %d ms | %.0f fps | N, setas, espaco, Q",
            nomes[atual], atual, #nomes, modelo:count(), ms, fps)
    end
end

local timer = os.startTimer(INTERVALO)

f.onEvent = function(_, ev, a)
    if ev == "timer" and a == timer then
        timer = os.startTimer(INTERVALO)
        -- Demo em segundo plano continua recebendo o timer e gastaria o computador
        -- desenhando o que ninguem ve.
        if mosaic.focused() ~= mosaic.current() then return true end
        if rodando then
            giro = giro + 0.06
            ilumina()
        end
        quadros = quadros + 1
        local agora = os.epoch("utc")
        if agora - marco >= 1000 then
            fps = quadros * 1000 / (agora - marco)
            quadros, marco = 0, agora
        end
        atualizaRodape()
        f.dirty = true
        return true
    elseif ev == "key" then
        if a == keys.q then f:stop() return true
        elseif a == keys.space then rodando = not rodando atualizaRodape() f.dirty = true return true
        elseif a == keys.n and #nomes > 1 then
            atual = atual % #nomes + 1
            carrega()
            ilumina()
            atualizaRodape()
            f.dirty = true
            return true
        elseif a == keys.left then giro = giro - 0.15 ilumina() f.dirty = true return true
        elseif a == keys.right then giro = giro + 0.15 ilumina() f.dirty = true return true
        elseif a == keys.up then altura = math.min(1.4, altura + 0.15) f.dirty = true return true
        elseif a == keys.down then altura = math.max(-1.4, altura - 0.15) f.dirty = true return true
        end
    end
end

atualizaRodape()
f:run()
