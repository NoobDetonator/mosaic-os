-- Demo 3D: um cubo girando.
--
-- Nao aparece no menu Iniciar nem na pasta Programas de proposito. Para rodar, abra o
-- Arquivos, va em /os/demos e mande Executar.
--
-- E' o "ola mundo" do motor: prova que anima, mede quanto custa o quadro, e serve de molde
-- para qualquer outro demo.
local ui = mosaic.ui
local theme = mosaic.theme
local pixel = mosaic.lib("pixel")
local mesh = mosaic.lib("mesh")
local three = mosaic.lib("three")

local INTERVALO = 0.05        -- um tique do Minecraft; e' o teto de taxa que o CC permite

local f = ui.form()
local canvas, frame, cw, ch
local giro, altura = 0.6, 0.4
local rodando, comCull = true, true
local ms, quadros, marco, fps = 0, 0, os.epoch("utc"), 0

local cubo = mesh.cube():center()

local rodape = f:add(ui.label { x = 1, bottom = 0, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

-- Canvas e quadro guardados entre desenhos, e refeitos so' quando a janela muda de tamanho.
-- Recriar os dois todo quadro custa 0,47 ms medidos, e faz o z-buffer crescer do zero cada vez.
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
    frame:orbit({ 0, 0, 0 }, 2.5, giro, altura)
    frame:clear(colors.black)
    frame:draw({ { model = cubo } }, { cull = comCull })
    canvas:render(t, 1, 1)
    ms = os.epoch("utc") - inicio
end

local function atualizaRodape()
    rodape.text = string.format(" %d tri | %d ms | %.0f fps | cull %s | setas, espaco, C, Q",
        cubo:count(), ms, fps, comCull and "on" or "off")
end

local timer = os.startTimer(INTERVALO)

f.onEvent = function(_, ev, a)
    if ev == "timer" and a == timer then
        timer = os.startTimer(INTERVALO)
        -- Demo em segundo plano continua recebendo o timer e continuaria desenhando, gastando
        -- o computador inteiro por nada. Anima so' quando esta na frente.
        if mosaic.focused() ~= mosaic.current() then return true end
        if rodando then giro = giro + 0.08 end
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
        if a == keys.space then rodando = not rodando atualizaRodape() f.dirty = true return true
        elseif a == keys.q then f:stop() return true
        elseif a == keys.c then comCull = not comCull atualizaRodape() f.dirty = true return true
        elseif a == keys.left then giro = giro - 0.15 f.dirty = true return true
        elseif a == keys.right then giro = giro + 0.15 f.dirty = true return true
        elseif a == keys.up then
            altura = math.min(1.4, altura + 0.15) f.dirty = true return true
        elseif a == keys.down then
            altura = math.max(-1.4, altura - 0.15) f.dirty = true return true
        end
    end
end

atualizaRodape()
f:run()
