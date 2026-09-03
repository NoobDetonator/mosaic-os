-- Demo 3D: terreno com camera livre.
--
-- Abra pelo Arquivos em /os/demos e mande Executar.
--
-- Este demo existe para provar o corte no plano proximo. Antes dele, todo triangulo com um
-- vertice atras da camera era jogado fora inteiro: bastava chegar perto do chao para o chao
-- sumir aos pedacos. Ande para dentro do morro e veja que ele continua la.
local ui = mosaic.ui
local theme = mosaic.theme
local pixel = mosaic.lib("pixel")
local mesh = mosaic.lib("mesh")
local three = mosaic.lib("three")

local INTERVALO = 0.05
local N = 24                  -- celulas de cada lado
local PASSO = 0.9
local GIRO = 0.12

-- Ruido de valor: hash por seno, interpolado com suavizacao. Nao e' Perlin, mas para um morro
-- de demo ele basta e cabe em quinze linhas.
local function hash(x, z)
    local s = math.sin(x * 12.9898 + z * 78.233) * 43758.5453
    return s - math.floor(s)
end

local function ruido(x, z)
    local xi, zi = math.floor(x), math.floor(z)
    local xf, zf = x - xi, z - zi
    local u = xf * xf * (3 - 2 * xf)
    local v = zf * zf * (3 - 2 * zf)
    local a, b = hash(xi, zi), hash(xi + 1, zi)
    local c, d = hash(xi, zi + 1), hash(xi + 1, zi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
end

local function altura(x, z)
    return ruido(x * 0.14, z * 0.14) * 7 + ruido(x * 0.45, z * 0.45) * 1.6
end

-- Cor por altura. A rampa verde do CC so' tem dois tons, entao a parte alta passa para o
-- cinza e o branco, que e' a unica rampa de quatro degraus que a paleta oferece.
local function corDe(y)
    if y < 2.2 then return colors.green
    elseif y < 4.0 then return colors.lime
    elseif y < 6.0 then return colors.lightGray
    else return colors.white end
end

local function montaTerreno()
    -- A altura de cada vertice e calculada UMA vez: o mesh.grid chamaria a funcao quatro
    -- vezes por celula, uma por quadrado vizinho.
    local h = {}
    for j = 0, N do
        h[j] = {}
        for i = 0, N do h[j][i] = altura(i, j) end
    end
    local m = mesh.new()
    for j = 0, N - 1 do
        for i = 0, N - 1 do
            local y1, y2 = h[j][i], h[j][i + 1]
            local y3, y4 = h[j + 1][i + 1], h[j + 1][i]
            local media = (y1 + y2 + y3 + y4) / 4
            m:quad({ i, y1, j }, { i + 1, y2, j }, { i + 1, y3, j + 1 }, { i, y4, j + 1 },
                corDe(media))
        end
    end
    return m
end

local terreno = montaTerreno()

local f = ui.form()
local canvas, frame, cw, ch
local camx, camy, camz = N / 2, 12, -8
local giro, incl = 0, -0.35
local ms, quadros, marco, fps = 0, 0, os.epoch("utc"), 0

local rodape = f:add(ui.label { x = 1, bottom = 0, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

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
    frame:setCamera(camx, camy, camz, incl, giro, 0)
    frame:clear(colors.black)
    frame:draw({ { model = terreno } }, { cull = true })
    canvas:render(t, 1, 1)
    ms = os.epoch("utc") - inicio
end

local function atualizaRodape()
    rodape.text = string.format(" %d,%d,%d | %d tri | %d ms | %.0f fps | WASD, setas, X sai",
        camx, camy, camz, terreno:count(), ms, fps)
end

-- Frente da camera pela convencao do motor: (sin do giro, 0, cos do giro).
local function anda(frente, lado)
    local s, c = math.sin(giro), math.cos(giro)
    camx = camx + (frente * s + lado * c) * PASSO
    camz = camz + (frente * c - lado * s) * PASSO
end

local timer = os.startTimer(INTERVALO)

f.onEvent = function(_, ev, a)
    if ev == "timer" and a == timer then
        timer = os.startTimer(INTERVALO)
        if mosaic.focused() ~= mosaic.current() then return true end
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
        if a == keys.w then anda(1, 0)
        elseif a == keys.s then anda(-1, 0)
        elseif a == keys.a then anda(0, -1)
        elseif a == keys.d then anda(0, 1)
        elseif a == keys.space then camy = camy + PASSO
        elseif a == keys.leftShift then camy = camy - PASSO
        elseif a == keys.left then giro = giro - GIRO
        elseif a == keys.right then giro = giro + GIRO
        elseif a == keys.up then incl = math.min(1.4, incl + GIRO)
        elseif a == keys.down then incl = math.max(-1.4, incl - GIRO)
        elseif a == keys.x then f:stop() return true
        else return false end
        atualizaRodape()
        f.dirty = true
        return true
    end
end

atualizaRodape()
f:run()
