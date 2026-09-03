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
-- Convencoes: mao esquerda. Com a camera sem giro, +x vai para a direita, +y para cima e
-- **+z para dentro da tela**. `setCamera(0, 0, -5)` olha para a origem.
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
    return self
end

-- Senos, cossenos e escala do quadro. Calcular isso custa quatro trigonometricas e uma
-- tabela, entao quem desenha em laco pede uma vez com `frame:begin()` e reaproveita.
function Frame:begin()
    local c = self.cam
    local canvas = self.canvas
    return {
        sinY = math.sin(c.ry), cosY = math.cos(c.ry),
        sinX = math.sin(c.rx), cosX = math.cos(c.rx),
        sinZ = math.sin(c.rz), cosZ = math.cos(c.rz), temZ = c.rz ~= 0,
        camX = c.x, camY = c.y, camZ = c.z,
        -- O buffer comeca em 1, entao o meio de w pontos e (w + 1) / 2, nao w / 2. Com w / 2
        -- a imagem inteira ficava meio sub-pixel acima e a esquerda.
        cx = (canvas.w + 1) / 2, cy = (canvas.h + 1) / 2,
        -- Sub-pixel do CC e' quadrado (3x3 texels), entao nao ha correcao de proporcao.
        escala = (canvas.w / 2) / math.tan(math.rad(self.fov) / 2),
    }
end
Frame.angles = Frame.begin      -- nome antigo

-- Mundo para o espaco da camera, SEM a divisao de perspectiva. O corte no plano proximo
-- precisa acontecer aqui, antes de dividir por z.
function Frame:view(x, y, z, pre)
    local dx, dy, dz = x - pre.camX, y - pre.camY, z - pre.camZ
    local ax = dx * pre.cosY - dz * pre.sinY
    local az = dx * pre.sinY + dz * pre.cosY
    local ay = dy * pre.cosX - az * pre.sinX
    local bz = dy * pre.sinX + az * pre.cosX
    if pre.temZ then
        ax, ay = ax * pre.cosZ - ay * pre.sinZ, ax * pre.sinZ + ay * pre.cosZ
    end
    return ax, ay, bz
end

-- Mundo para tela. Devolve px, py, profundidade — ou nil quando esta atras da camera.
-- `pre` e' opcional: passe o de `frame:begin()` para nao pagar quatro trigonometricas por ponto.
function Frame:project(x, y, z, pre)
    pre = pre or self:begin()
    local ax, ay, bz = self:view(x, y, z, pre)
    if bz <= three.NEAR then return nil end
    return pre.cx + ax / bz * pre.escala, pre.cy - ay / bz * pre.escala, bz
end
Frame.map3dTo2d = Frame.project

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

-- ---------------------------------------------------------------- corte no plano proximo
--
-- Sem isso, vertice atras da camera fazia `project` devolver nil e o TRIANGULO INTEIRO era
-- jogado fora. Um triangulo com um vertice atras deveria virar dois; virava nada. Enquanto a
-- camera so' orbitava a distancia fixa isso nunca apareceu, mas qualquer camera que ande faz
-- a geometria perto sumir aos pedacos.
--
-- Sutherland-Hodgman contra um plano so' (z = NEAR), no espaco da camera. Saida: 0, 3 ou 4
-- vertices num vetor plano.
local sx, sy, sz = {}, {}, {}        -- rascunho reaproveitado: nada aqui faz yield

local function clipNear(out, ax, ay, az, bx, by, bz, cx, cy, cz)
    local near = three.NEAR
    sx[1], sy[1], sz[1] = ax, ay, az
    sx[2], sy[2], sz[2] = bx, by, bz
    sx[3], sy[3], sz[3] = cx, cy, cz
    local n, j = 0, 3
    for i = 1, 3 do
        local zp, zc = sz[j], sz[i]
        local dentroP, dentroC = zp >= near, zc >= near
        if dentroP ~= dentroC then
            local t = (near - zp) / (zc - zp)
            out[n + 1] = sx[j] + (sx[i] - sx[j]) * t
            out[n + 2] = sy[j] + (sy[i] - sy[j]) * t
            out[n + 3] = near
            n = n + 3
        end
        if dentroC then
            out[n + 1] = sx[i]
            out[n + 2] = sy[i]
            out[n + 3] = sz[i]
            n = n + 3
        end
        j = i
    end
    return n / 3
end
three.clipNear = clipNear            -- exposto para o self-check

-- objetos: { { model = , x = , y = , z = , rx = , ry = , rz = , scale = } , ... }
-- As transformacoes do objeto sao aplicadas por vertice na hora, sem copiar o modelo.
--
-- Sobre `cull`: com z-buffer, descartar face de costas so' economiza tempo, nao muda o
-- desenho. Medido: tira 25% do quadro, e nao os 50% que a contagem de faces sugere — a face
-- descartada ja pagou a transformacao dos tres vertices antes do teste de area.
function Frame:draw(objetos, opts)
    opts = opts or {}
    local pre = self:begin()
    local canvas, zb = self.canvas, self.zbuf
    local cull = opts.cull
    if cull == nil then cull = self.cull end
    local near = three.NEAR
    local pcx, pcy, pesc = pre.cx, pre.cy, pre.escala

    local poly = {}                  -- ate 4 vertices depois do corte
    local px, py, pw = {}, {}, {}    -- os mesmos vertices ja projetados
    local enviados, cortados = 0, 0

    for _, obj in ipairs(objetos) do
        local m = obj.model or obj[1]
        if m then
            local ox, oy, oz = obj.x or 0, obj.y or 0, obj.z or 0
            local esc = obj.scale or 1
            local rx, ry, rz = obj.rx or 0, obj.ry or 0, obj.rz or 0
            local temRot = rx ~= 0 or ry ~= 0 or rz ~= 0
            local cxr, sxr, cyr, syr, czr, szr = 1, 0, 1, 0, 1, 0
            if temRot then
                cxr, sxr = math.cos(rx), math.sin(rx)
                cyr, syr = math.cos(ry), math.sin(ry)
                czr, szr = math.cos(rz), math.sin(rz)
            end

            local function ponto(x, y, z)
                x, y, z = x * esc, y * esc, z * esc
                if temRot then
                    x, z = x * cyr + z * syr, -x * syr + z * cyr
                    y, z = y * cxr - z * sxr, y * sxr + z * cxr
                    x, y = x * czr - y * szr, x * szr + y * czr
                end
                return self:view(x + ox, y + oy, z + oz, pre)
            end

            for _, t in ipairs(m.tris) do
                local ax, ay, az = ponto(t[1], t[2], t[3])
                local bx, by, bz = ponto(t[4], t[5], t[6])
                local cx, cy, cz = ponto(t[7], t[8], t[9])
                local cor = t.c or colors.white

                if az >= near and bz >= near and cz >= near then
                    -- Caminho comum, e por isso ele nao encosta em tabela nenhuma: passar os
                    -- vertices por um vetor intermediario custou 21 operacoes de tabela por
                    -- triangulo e DOBROU o tempo da cena de 10 mil triangulos. Medido.
                    local ia, ib, ic = 1 / az, 1 / bz, 1 / cz
                    raster(canvas, zb,
                        pcx + ax * ia * pesc, pcy - ay * ia * pesc, ia,
                        pcx + bx * ib * pesc, pcy - by * ib * pesc, ib,
                        pcx + cx * ic * pesc, pcy - cy * ic * pesc, ic, cor, cull)
                    enviados = enviados + 1
                else
                    -- Caminho raro: alguem esta atras da camera. So' aqui o vetor entra.
                    local nv = clipNear(poly, ax, ay, az, bx, by, bz, cx, cy, cz)
                    if nv >= 3 then
                        for k = 1, nv do
                            local iz = 1 / poly[k * 3]
                            px[k] = pcx + poly[k * 3 - 2] * iz * pesc
                            py[k] = pcy - poly[k * 3 - 1] * iz * pesc
                            pw[k] = iz
                        end
                        raster(canvas, zb, px[1], py[1], pw[1], px[2], py[2], pw[2],
                            px[3], py[3], pw[3], cor, cull)
                        if nv == 4 then
                            raster(canvas, zb, px[1], py[1], pw[1], px[3], py[3], pw[3],
                                px[4], py[4], pw[4], cor, cull)
                        end
                        enviados = enviados + 1
                        cortados = cortados + 1
                    end
                end
            end
        end
    end
    return enviados, cortados
end

function three.demo()
    local pixel = require("lib.pixel")
    local mesh = require("lib.mesh")

    local canvas = pixel.new(20, 8, colors.black)     -- 40 x 24 pontos
    local f = three.frame(canvas)
    local meioX, meioY = (canvas.w + 1) / 2, (canvas.h + 1) / 2

    -- Ponto bem na frente da camera cai no meio da tela.
    f:setCamera(0, 0, -5, 0, 0, 0)
    local px, py = f:map3dTo2d(0, 0, 0)
    assert(px and math.abs(px - meioX) < 0.01, "o ponto de frente deveria cair no meio em x")
    assert(math.abs(py - meioY) < 0.01, "o ponto de frente deveria cair no meio em y")

    -- O que esta atras nao projeta.
    assert(f:map3dTo2d(0, 0, -10) == nil, "ponto atras da camera nao pode projetar")

    -- Mais longe fica mais perto do centro.
    local perto = select(1, f:map3dTo2d(1, 0, 0))
    f:setCamera(0, 0, -50)
    local longe = select(1, f:map3dTo2d(1, 0, 0))
    assert(math.abs(longe - meioX) < math.abs(perto - meioX),
        "perspectiva errada: o objeto distante deveria encolher")

    -- Rolagem: com a camera girada 90 graus no proprio eixo, o que estava a direita sobe.
    f:setCamera(0, 0, -5, 0, 0, 0)
    local dx = select(1, f:map3dTo2d(1, 0, 0)) - meioX
    f:setCamera(0, 0, -5, 0, 0, math.pi / 2)
    local rx2, ry2 = f:map3dTo2d(1, 0, 0)
    assert(math.abs(rx2 - meioX) < 0.01, "com rolagem de 90 graus o ponto deveria sair do eixo x")
    assert(math.abs((meioY - ry2) - dx) < 0.01, "a rolagem nao levou o ponto para cima")
    f:setCamera(0, 0, -5, 0, 0, 0)

    -- ---------------------------------------------------------------- corte
    local out = {}
    -- Tudo na frente: sai igual, tres vertices.
    assert(three.clipNear(out, 0, 0, 1, 1, 0, 1, 0, 1, 1) == 3, "triangulo inteiro na frente")
    -- Tudo atras: nao sai nada.
    assert(three.clipNear(out, 0, 0, -1, 1, 0, -1, 0, 1, -1) == 0, "triangulo inteiro atras")
    -- Um vertice na frente: vira um triangulo.
    local n1 = three.clipNear(out, 0, 0, 1, 1, 0, -1, 0, 1, -1)
    assert(n1 == 3, "um vertice na frente deveria dar um triangulo, deu " .. n1)
    -- Dois na frente: vira quatro vertices, ou seja dois triangulos.
    local n2 = three.clipNear(out, 0, 0, 1, 1, 0, 1, 0, 1, -1)
    assert(n2 == 4, "dois vertices na frente deveriam dar quatro pontos, deu " .. n2)
    -- O vertice cortado fica exatamente no plano.
    for k = 1, n2 do
        assert(out[k * 3] >= three.NEAR - 1e-9, "sobrou vertice atras do plano depois do corte")
    end

    -- Na pratica: um triangulo com um vertice atras da camera. Sem corte ele era jogado
    -- fora inteiro e nao pintava nada. Os dois vertices da frente ficam de lados opostos do
    -- eixo, para o que sobra cair DENTRO da tela - a primeira versao deste teste usava uma
    -- parede inclinada cuja parte visivel projetava toda fora do canvas, e falhava por
    -- geometria ruim, nao por bug no corte.
    local atravessa = mesh.new()
    atravessa:add(-2, -1, 3, 2, -1, 3, 0, 1, -1, colors.white)
    f:setCamera(0, 0, 0, 0, 0, 0)
    f:clear(colors.black)
    local enviados, cortados = f:draw({ { model = atravessa } })
    assert(enviados == 1 and cortados == 1, "o triangulo deveria ter sido cortado e desenhado")
    local pintouCorte = 0
    for y = 1, canvas.h do
        for x = 1, canvas.w do
            if canvas:get(x, y) ~= colors.black then pintouCorte = pintouCorte + 1 end
        end
    end
    assert(pintouCorte > 100, "triangulo cruzando a camera deveria pintar, pintou " .. pintouCorte)

    -- Tudo atras nao pinta nada, e nao conta como cortado.
    f:clear(colors.black)
    local atras = mesh.new()
    atras:add(-2, -1, -3, 2, -1, -3, 0, 1, -3, colors.white)
    local env2, cort2 = f:draw({ { model = atras } })
    assert(env2 == 0 and cort2 == 0, "triangulo todo atras nao deveria ir para o rasterizador")

    -- ---------------------------------------------------------------- resto
    f:setCamera(0, 0, -4, 0, 0, 0)
    f:clear(colors.black)
    local cubo = mesh.cube():center()
    local n = f:draw({ { model = cubo } })
    assert(n == 12, "deveria ter desenhado os 12 triangulos, desenhou " .. n)
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
    local meio = canvas:get(math.floor(meioX), math.floor(meioY))
    assert(meio == colors.red, "o cubo da frente tinha de ganhar do de tras, veio " .. tostring(meio))

    -- E o contrario tambem: desenhar o de tras depois nao pode apagar o da frente.
    f:clear(colors.black)
    f:draw({ { model = longe2, z = 6 }, { model = perto2, z = 0 } })
    meio = canvas:get(math.floor(meioX), math.floor(meioY))
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
            assert(math.abs(ax - meioX) < 0.01 and math.abs(ay - meioY) < 0.01,
                "o alvo da orbita tem de cair no meio da tela, caiu em " .. ax .. "," .. ay)
            assert(math.abs(az - 10) < 1e-6, "a profundidade do alvo tem de ser a distancia")
        end
    end

    -- Alvo fora da origem.
    f:orbit({ 3, 1, -2 }, 8, 1.1, 0.4)
    local bx, by = f:map3dTo2d(3, 1, -2)
    assert(bx and math.abs(bx - meioX) < 0.01 and math.abs(by - meioY) < 0.01,
        "orbita em volta de um alvo deslocado nao centrou")

    -- `begin` reaproveitado da o mesmo resultado que calcular na hora.
    local pre = f:begin()
    local qx, qy = f:project(3, 1, -2, pre)
    assert(math.abs(qx - meioX) < 0.01 and math.abs(qy - meioY) < 0.01,
        "projetar com o `pre` guardado tem de dar o mesmo que sem ele")

    return true
end

return three
