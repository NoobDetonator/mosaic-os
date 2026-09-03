-- Camera e rasterizador 3D, desenhando num canvas de sub-pixel do lib/pixel.
--
--   local three = mosaic.lib("three")
--   local frame = three.frame(canvas)
--   frame:setCamera(0, 2, -6, 0.2, 0, 0)
--   frame:draw({ { model = m } })
--
-- Escrito olhando a arquitetura do Pine3D (quadro, camera, objeto, modelo, buffer), mas nao
-- e' ele: o Pine3D e' dependencia externa instalada por pastebin, e o CLAUDE.md deste projeto
-- proibe dependencia externa. As diferencas que importam:
--
--   * saida em sub-pixel (2x3 por celula), entao 102x57 pontos numa tela de 51x19;
--   * z-buffer por ponto em vez de ordenar poligono, o que acerta malha que se atravessa;
--   * as cores passam pela paleta do Mosaic, que remapeia 7 das 16;
--   * entra no manifest com sha1, como todo arquivo nosso.
--
-- O que foi copiado de proposito porque esta certo: os senos e cossenos da camera calculados
-- uma vez por quadro, e as estruturas quentes indexadas por numero.
local three = {}

three.NEAR = 0.05        -- nada mais perto que isso e' desenhado

local Frame = {}
Frame.__index = Frame

function three.frame(canvas)
    local f = setmetatable({
        canvas = canvas,
        cam = { x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0 },
        fov = 70,
        cull = false,        -- ver o comentario em Frame:draw
        zbuf = {},
    }, Frame)
    f:setFoV(70)
    return f
end

function Frame:setCanvas(canvas)
    self.canvas = canvas
    return self
end

function Frame:setCamera(x, y, z, rx, ry, rz)
    local c = self.cam
    c.x, c.y, c.z = x or c.x, y or c.y, z or c.z
    c.rx, c.ry, c.rz = rx or c.rx, ry or c.ry, rz or c.rz
    return self
end

function Frame:setFoV(graus)
    self.fov = math.max(10, math.min(170, graus or 70))
    return self
end

-- Coloca a camera olhando para um ponto, a uma distancia, com os dois angulos. E' o jeito
-- que uma pre-visualizacao gira: o alvo fica parado e a camera anda em volta.
function Frame:orbit(alvo, dist, giro, altura)
    local cx = math.cos(altura) * dist
    self.cam.x = alvo[1] - math.sin(giro) * cx
    self.cam.y = alvo[2] + math.sin(altura) * dist
    self.cam.z = alvo[3] - math.cos(giro) * cx
    self.cam.ry = giro
    self.cam.rx = -altura
    self.alvo = alvo
    return self
end

-- Mundo para tela. Devolve px, py, profundidade — ou nil quando esta atras da camera.
function Frame:project(x, y, z, pre)
    local c = self.cam
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local sinY, cosY = pre.sinY, pre.cosY
    local sinX, cosX = pre.sinX, pre.cosX

    local ax = dx * cosY - dz * sinY
    local az = dx * sinY + dz * cosY
    local ay = dy * cosX - az * sinX
    local bz = dy * sinX + az * cosX
    if bz <= three.NEAR then return nil end

    return pre.cx + ax / bz * pre.escala, pre.cy - ay / bz * pre.escala, bz
end

function Frame:angles()
    local c = self.cam
    local canvas = self.canvas
    return {
        sinY = math.sin(c.ry), cosY = math.cos(c.ry),
        sinX = math.sin(c.rx), cosX = math.cos(c.rx),
        cx = canvas.w / 2, cy = canvas.h / 2,
        -- Sub-pixel do CC e' quadrado (3x3 texels), entao nao ha correcao de proporcao.
        escala = (canvas.w / 2) / math.tan(math.rad(self.fov) / 2),
    }
end

function Frame:map3dTo2d(x, y, z)
    local px, py, d = self:project(x, y, z, self:angles())
    if not px then return nil end
    return px, py, d
end

function Frame:clear(cor)
    self.canvas:clear(cor or colors.black)
    local zb = self.zbuf
    for i = 1, self.canvas.w * self.canvas.h do zb[i] = 0 end
    return self
end

-- Triangulo com z-buffer. A profundidade interpolada e' 1/z, que e' o que varia linearmente
-- na tela; interpolar z direto entortaria a comparacao nas faces inclinadas.
local function raster(canvas, zb, x1, y1, w1, x2, y2, w2, x3, y3, w3, cor, cull)
    local area = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
    if area == 0 then return 0 end
    if cull and area > 0 then return 0 end

    local W, H = canvas.w, canvas.h
    local minx = math.max(1, math.floor(math.min(x1, x2, x3)))
    local maxx = math.min(W, math.ceil(math.max(x1, x2, x3)))
    local miny = math.max(1, math.floor(math.min(y1, y2, y3)))
    local maxy = math.min(H, math.ceil(math.max(y1, y2, y3)))
    if minx > maxx or miny > maxy then return 0 end

    local inv = 1 / area
    local pintados = 0
    for py = miny, maxy do
        local rowbase = (py - 1) * W
        for px = minx, maxx do
            local b1 = ((x2 - px) * (y3 - py) - (y2 - py) * (x3 - px)) * inv
            local b2 = ((x3 - px) * (y1 - py) - (y3 - py) * (x1 - px)) * inv
            local b3 = 1 - b1 - b2
            if b1 >= 0 and b2 >= 0 and b3 >= 0 then
                local w = b1 * w1 + b2 * w2 + b3 * w3
                local i = rowbase + px
                if w > zb[i] then
                    zb[i] = w
                    canvas:set(px, py, cor)
                    pintados = pintados + 1
                end
            end
        end
    end
    return pintados
end

-- objetos: { { model = , x = , y = , z = , rx = , ry = , rz = , scale = } , ... }
-- As transformacoes do objeto sao aplicadas por vertice na hora, sem copiar o modelo.
--
-- Sobre `cull`: com z-buffer, descartar face de costas so' economiza tempo, nao muda o
-- desenho. Fica desligado por padrao porque depende da ordem dos cantos de cada gerador
-- estar consistente, e o preco de errar (buraco no modelo) e' pior que o ganho.
function Frame:draw(objetos, opts)
    opts = opts or {}
    local pre = self:angles()
    local canvas, zb = self.canvas, self.zbuf
    local desenhados, fora = 0, 0

    for _, obj in ipairs(objetos) do
        local m = obj.model or obj[1]
        if m then
            local ox, oy, oz = obj.x or 0, obj.y or 0, obj.z or 0
            local esc = obj.scale or 1
            local rx, ry, rz = obj.rx or 0, obj.ry or 0, obj.rz or 0
            local temRot = rx ~= 0 or ry ~= 0 or rz ~= 0
            local cxr, sxr = math.cos(rx), math.sin(rx)
            local cyr, syr = math.cos(ry), math.sin(ry)
            local czr, szr = math.cos(rz), math.sin(rz)

            local function ponto(x, y, z)
                x, y, z = x * esc, y * esc, z * esc
                if temRot then
                    x, z = x * cyr + z * syr, -x * syr + z * cyr
                    y, z = y * cxr - z * sxr, y * sxr + z * cxr
                    x, y = x * czr - y * szr, x * szr + y * czr
                end
                return self:project(x + ox, y + oy, z + oz, pre)
            end

            for _, t in ipairs(m.tris) do
                local ax, ay, aw = ponto(t[1], t[2], t[3])
                if ax then
                    local bx, by, bw = ponto(t[4], t[5], t[6])
                    if bx then
                        local cx, cy, cw = ponto(t[7], t[8], t[9])
                        if cx then
                            raster(canvas, zb, ax, ay, 1 / aw, bx, by, 1 / bw, cx, cy, 1 / cw,
                                t.c or colors.white, opts.cull or self.cull)
                            desenhados = desenhados + 1
                        else fora = fora + 1 end
                    else fora = fora + 1 end
                else fora = fora + 1 end
            end
        end
    end
    return desenhados, fora
end

function three.demo()
    local pixel = require("lib.pixel")
    local mesh = require("lib.mesh")

    local canvas = pixel.new(20, 8, colors.black)     -- 40 x 24 pontos
    local f = three.frame(canvas)

    -- Ponto bem na frente da camera cai no meio da tela.
    f:setCamera(0, 0, -5, 0, 0, 0)
    local px, py = f:map3dTo2d(0, 0, 0)
    assert(px and math.abs(px - canvas.w / 2) < 0.01, "o ponto de frente deveria cair no meio em x")
    assert(math.abs(py - canvas.h / 2) < 0.01, "o ponto de frente deveria cair no meio em y")

    -- O que esta atras nao projeta.
    assert(f:map3dTo2d(0, 0, -10) == nil, "ponto atras da camera nao pode projetar")

    -- Mais longe fica mais perto do centro.
    local perto = select(1, f:map3dTo2d(1, 0, 0))
    f:setCamera(0, 0, -50)
    local longe = select(1, f:map3dTo2d(1, 0, 0))
    assert(math.abs(longe - canvas.w / 2) < math.abs(perto - canvas.w / 2),
        "perspectiva errada: o objeto distante deveria encolher")

    -- Um cubo na frente pinta alguma coisa.
    f:setCamera(0, 0, -4, 0, 0, 0)
    f:clear(colors.black)
    local cubo = mesh.cube():center()
    local n = f:draw({ { model = cubo } })
    assert(n == 12, "deveria ter tentado desenhar os 12 triangulos, tentou " .. n)
    local pintou = 0
    for y = 1, canvas.h do
        for x = 1, canvas.w do
            if canvas:get(x, y) ~= colors.black then pintou = pintou + 1 end
        end
    end
    assert(pintou > 20, "o cubo mal pintou a tela: " .. pintou .. " pontos")

    -- z-buffer: o que esta na frente ganha, mesmo desenhado antes.
    f:clear(colors.black)
    local perto2 = mesh.cube():center():mapColor(colors.red)
    local longe2 = mesh.cube():center():scale(3):mapColor(colors.lime)
    f:draw({ { model = perto2, z = 0 }, { model = longe2, z = 6 } })
    local meio = canvas:get(math.floor(canvas.w / 2), math.floor(canvas.h / 2))
    assert(meio == colors.red, "o cubo da frente tinha de ganhar do de tras, veio " .. tostring(meio))

    -- E o contrario tambem: desenhar o de tras depois nao pode apagar o da frente.
    f:clear(colors.black)
    f:draw({ { model = longe2, z = 6 }, { model = perto2, z = 0 } })
    meio = canvas:get(math.floor(canvas.w / 2), math.floor(canvas.h / 2))
    assert(meio == colors.red, "a ordem de desenho nao pode mudar o resultado com z-buffer")

    -- Limpar zera a profundidade, senao o quadro seguinte herdaria o anterior.
    f:clear(colors.black)
    assert(f.zbuf[1] == 0, "o clear tem de zerar o z-buffer")

    -- Orbita: a camera fica na distancia pedida E olhando para o alvo. So' conferir a
    -- distancia nao basta: com o sinal do giro trocado ela fica longe certo e apontada para
    -- o lado errado, que foi exatamente o bug que a tela preta mostrou.
    for _, giro in ipairs({ 0, 0.7, 2.5, -1.2 }) do
        for _, alt in ipairs({ 0, 0.5, -0.8 }) do
            f:orbit({ 0, 0, 0 }, 10, giro, alt)
            local d = math.sqrt(f.cam.x ^ 2 + f.cam.y ^ 2 + f.cam.z ^ 2)
            assert(math.abs(d - 10) < 1e-6, "a orbita deveria manter a distancia, deu " .. d)
            local ax, ay, az = f:map3dTo2d(0, 0, 0)
            assert(ax, "o alvo da orbita tem de estar visivel (giro " .. giro .. ")")
            assert(math.abs(ax - canvas.w / 2) < 0.01 and math.abs(ay - canvas.h / 2) < 0.01,
                "o alvo da orbita tem de cair no meio da tela, caiu em " .. ax .. "," .. ay)
            assert(math.abs(az - 10) < 1e-6, "a profundidade do alvo tem de ser a distancia")
        end
    end

    -- Alvo fora da origem.
    f:orbit({ 3, 1, -2 }, 8, 1.1, 0.4)
    local bx, by = f:map3dTo2d(3, 1, -2)
    assert(bx and math.abs(bx - canvas.w / 2) < 0.01 and math.abs(by - canvas.h / 2) < 0.01,
        "orbita em volta de um alvo deslocado nao centrou")

    return true
end

return three
