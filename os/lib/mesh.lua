-- Malha 3D: lista de triangulos com transformacoes encadeaveis, e geradores que dispensam
-- arquivo de modelo.
--
--   local mesh = mosaic.lib("mesh")
--   local m = mesh.cube():scale(2):translate(0, 1, 0)
--   local m2 = mesh.voxels(resultado.layers, { w = 15, h = 1, d = 15 })
--
-- Cada triangulo e' um vetor de nove numeros mais a cor, e nao uma tabela de campos com
-- nome. E' feio de ler e e' de proposito: em Lua sem JIT, indice numerico e' medivelmente
-- mais rapido que chave de texto, e o rasterizador toca em todos eles a cada quadro.
--
--   tri = { x1, y1, z1, x2, y2, z2, x3, y3, z3, c = cor }
local mesh = {}

local Model = {}
Model.__index = Model

-- `closed` diz que a malha e' uma casca fechada, e portanto que descartar face de costas
-- nao muda o desenho. Plano e grade sao abertos: com descarte eles somem vistos por baixo,
-- que e' correto para um terreno e errado para uma parede.
function mesh.new(tris, closed)
    return setmetatable({ tris = tris or {}, closed = closed or false }, Model)
end

function mesh.isModel(m) return getmetatable(m) == Model end

function Model:add(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
    self.tris[#self.tris + 1] = { x1, y1, z1, x2, y2, z2, x3, y3, z3, c = c }
    return self
end

-- Quadrilatero vira dois triangulos, mantendo a ordem dos cantos.
function Model:quad(a, b, c, d, cor)
    self:add(a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], cor)
    self:add(a[1], a[2], a[3], c[1], c[2], c[3], d[1], d[2], d[3], cor)
    return self
end

function Model:count() return #self.tris end

function Model:clone()
    local out = {}
    for i, t in ipairs(self.tris) do
        out[i] = { t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], c = t.c }
    end
    return mesh.new(out, self.closed)
end

function Model:translate(dx, dy, dz)
    dx, dy, dz = dx or 0, dy or 0, dz or 0
    for _, t in ipairs(self.tris) do
        t[1], t[2], t[3] = t[1] + dx, t[2] + dy, t[3] + dz
        t[4], t[5], t[6] = t[4] + dx, t[5] + dy, t[6] + dz
        t[7], t[8], t[9] = t[7] + dx, t[8] + dy, t[9] + dz
    end
    return self
end

function Model:scale(sx, sy, sz)
    sy = sy or sx
    sz = sz or sx
    for _, t in ipairs(self.tris) do
        t[1], t[2], t[3] = t[1] * sx, t[2] * sy, t[3] * sz
        t[4], t[5], t[6] = t[4] * sx, t[5] * sy, t[6] * sz
        t[7], t[8], t[9] = t[7] * sx, t[8] * sy, t[9] * sz
    end
    return self
end

function Model:rotate(rx, ry, rz)
    rx, ry, rz = rx or 0, ry or 0, rz or 0
    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    local cz, sz = math.cos(rz), math.sin(rz)
    for _, t in ipairs(self.tris) do
        for i = 0, 6, 3 do
            local x, y, z = t[i + 1], t[i + 2], t[i + 3]
            -- Y (giro na horizontal), depois X (inclinacao), depois Z (rolagem).
            x, z = x * cy + z * sy, -x * sy + z * cy
            y, z = y * cx - z * sx, y * sx + z * cx
            x, y = x * cz - y * sz, x * sz + y * cz
            t[i + 1], t[i + 2], t[i + 3] = x, y, z
        end
    end
    return self
end

function Model:bounds()
    if #self.tris == 0 then return 0, 0, 0, 0, 0, 0 end
    local inf = math.huge
    local x0, y0, z0, x1, y1, z1 = inf, inf, inf, -inf, -inf, -inf
    for _, t in ipairs(self.tris) do
        for i = 0, 6, 3 do
            local x, y, z = t[i + 1], t[i + 2], t[i + 3]
            if x < x0 then x0 = x end
            if y < y0 then y0 = y end
            if z < z0 then z0 = z end
            if x > x1 then x1 = x end
            if y > y1 then y1 = y end
            if z > z1 then z1 = z end
        end
    end
    return x0, y0, z0, x1, y1, z1
end

function Model:center()
    local x0, y0, z0, x1, y1, z1 = self:bounds()
    return self:translate(-(x0 + x1) / 2, -(y0 + y1) / 2, -(z0 + z1) / 2)
end

-- Coloca a base no zero, para o modelo ficar "em pe" no chao.
function Model:alignBottom()
    local _, y0 = self:bounds()
    return self:translate(0, -y0, 0)
end

-- Deixa a maior dimensao valendo 1, para a camera nao precisar saber o tamanho do modelo.
function Model:normalizeScale()
    local x0, y0, z0, x1, y1, z1 = self:bounds()
    local maior = math.max(x1 - x0, y1 - y0, z1 - z0)
    if maior <= 0 then return self end
    return self:scale(1 / maior)
end

-- Uma cor so', ou um mapa de-para.
function Model:mapColor(c)
    for _, t in ipairs(self.tris) do
        if type(c) == "table" then t.c = c[t.c] or t.c else t.c = c end
    end
    return self
end

-- ---------------------------------------------------------------- geradores

-- Tons por face: no alto, no lado e embaixo. Com 16 cores nao da' para sombrear de verdade,
-- entao a profundidade vem de tres tons fixos, e isso ja le como volume.
mesh.TOP, mesh.SIDE, mesh.BOTTOM = colors.white, colors.lightGray, colors.gray

-- Cubo de aresta 1 com um canto na origem.
function mesh.cube(opts)
    opts = opts or {}
    local topo = opts.top or mesh.TOP
    local lado = opts.side or mesh.SIDE
    local base = opts.bottom or mesh.BOTTOM
    local m = mesh.new()
    local p = function(x, y, z) return { x, y, z } end
    m:quad(p(0, 1, 0), p(1, 1, 0), p(1, 1, 1), p(0, 1, 1), topo)
    m:quad(p(0, 0, 1), p(1, 0, 1), p(1, 0, 0), p(0, 0, 0), base)
    m:quad(p(0, 0, 0), p(1, 0, 0), p(1, 1, 0), p(0, 1, 0), lado)
    m:quad(p(1, 0, 1), p(0, 0, 1), p(0, 1, 1), p(1, 1, 1), lado)
    m:quad(p(0, 0, 1), p(0, 0, 0), p(0, 1, 0), p(0, 1, 1), lado)
    m:quad(p(1, 0, 0), p(1, 0, 1), p(1, 1, 1), p(1, 1, 0), lado)
    m.closed = true
    return m
end

function mesh.plane(opts)
    opts = opts or {}
    local s = opts.size or 1
    local c = opts.color or mesh.TOP
    local y = opts.y or 0
    return mesh.new():quad({ 0, y, 0 }, { s, y, 0 }, { s, y, s }, { 0, y, s }, c)
end

-- Grade de altura: fn(i, j) devolve a altura. Serve para superficie de funcao.
function mesh.grid(nx, nz, fn, opts)
    opts = opts or {}
    local m = mesh.new()
    local cor = opts.color or mesh.TOP
    for j = 0, nz - 1 do
        for i = 0, nx - 1 do
            local a = { i, fn(i, j) or 0, j }
            local b = { i + 1, fn(i + 1, j) or 0, j }
            local c = { i + 1, fn(i + 1, j + 1) or 0, j + 1 }
            local d = { i, fn(i, j + 1) or 0, j + 1 }
            m:quad(a, b, c, d, cor)
        end
    end
    return m
end

-- Malha a partir do resultado do mcmath.build. So' entra face que da' para fora: numa forma
-- macica, as faces internas sao a esmagadora maioria e nenhuma delas aparece.
--
-- opts.maxFaces limita o tamanho; o segundo retorno diz quantas faces ficaram de fora.
function mesh.voxels(layers, w, h, d, opts)
    opts = opts or {}
    local limite = opts.maxFaces or 4000
    local topo = opts.top or mesh.TOP
    local lado = opts.side or mesh.SIDE
    local base = opts.bottom or mesh.BOTTOM
    local m = mesh.new(nil, true)     -- casca de voxel e sempre fechada
    local cortadas = 0

    local function cheio(x, y, z)
        if x < 1 or x > w or y < 1 or y > h or z < 1 or z > d then return false end
        local l = layers[y]
        return l and l[z] and l[z][x] and true or false
    end

    local faces = 0
    for y = 1, h do
        for z = 1, d do
            for x = 1, w do
                if cheio(x, y, z) then
                    local x0, y0, z0 = x - 1, y - 1, z - 1
                    local x1, y1, z1 = x, y, z
                    local lista = {}
                    if not cheio(x, y + 1, z) then
                        lista[#lista + 1] = { { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, topo }
                    end
                    if not cheio(x, y - 1, z) then
                        lista[#lista + 1] = { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { x0, y0, z0 }, base }
                    end
                    if not cheio(x, y, z - 1) then
                        lista[#lista + 1] = { { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 }, lado }
                    end
                    if not cheio(x, y, z + 1) then
                        lista[#lista + 1] = { { x1, y0, z1 }, { x0, y0, z1 }, { x0, y1, z1 }, { x1, y1, z1 }, lado }
                    end
                    if not cheio(x - 1, y, z) then
                        lista[#lista + 1] = { { x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, lado }
                    end
                    if not cheio(x + 1, y, z) then
                        lista[#lista + 1] = { { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, lado }
                    end
                    for _, q in ipairs(lista) do
                        if faces < limite then
                            m:quad(q[1], q[2], q[3], q[4], q[5])
                            faces = faces + 1
                        else
                            cortadas = cortadas + 1
                        end
                    end
                end
            end
        end
    end
    return m, cortadas
end

function mesh.demo()
    local c = mesh.cube()
    assert(c:count() == 12, "um cubo sao 12 triangulos, deu " .. c:count())
    assert(c.closed, "cubo e casca fechada")
    assert(not mesh.plane().closed, "plano e aberto: com descarte sumiria visto por baixo")
    assert(not mesh.grid(2, 2, function() return 0 end).closed, "grade e aberta")
    assert(mesh.cube():clone().closed, "clone tem de manter a marca de fechada")
    local x0, y0, z0, x1, y1, z1 = c:bounds()
    assert(x0 == 0 and y0 == 0 and z0 == 0 and x1 == 1 and y1 == 1 and z1 == 1,
        "o cubo padrao deveria ir de 0 a 1 nos tres eixos")

    local t = mesh.cube():translate(5, 0, 0)
    local tx0, _, _, tx1 = t:bounds()
    assert(tx0 == 5 and tx1 == 6, "translate nao andou com a caixa")

    local s = mesh.cube():scale(2)
    local _, _, _, sx1 = s:bounds()
    assert(sx1 == 2, "scale nao mudou o tamanho")

    local ct = mesh.cube():center()
    local cx0, _, _, cx1 = ct:bounds()
    assert(math.abs(cx0 + 0.5) < 1e-9 and math.abs(cx1 - 0.5) < 1e-9, "center nao centrou")

    local n = mesh.cube():scale(10):normalizeScale()
    local _, _, _, nx1, ny1 = n:bounds()
    assert(math.abs(math.max(nx1, ny1) - 1) < 1e-9, "normalizeScale deveria deixar a maior em 1")

    local ab = mesh.cube():translate(0, 7, 0):alignBottom()
    local _, ay0 = ab:bounds()
    assert(math.abs(ay0) < 1e-9, "alignBottom deveria por a base no zero")

    -- girar meia volta em Y devolve a caixa ao mesmo lugar, espelhada
    local r = mesh.cube():center():rotate(0, math.pi, 0)
    local rx0, _, _, rx1 = r:bounds()
    assert(math.abs(rx0 + 0.5) < 1e-6 and math.abs(rx1 - 0.5) < 1e-6, "rotacao de 180 graus saiu torta")

    -- clone nao compartilha os triangulos
    local orig = mesh.cube()
    local copia = orig:clone():translate(100, 0, 0)
    local ox1 = select(4, orig:bounds())
    assert(ox1 == 1, "mexer na copia mexeu no original")
    assert(select(4, copia:bounds()) == 101, "a copia nao andou")

    -- cor
    local col = mesh.cube():mapColor(colors.red)
    for _, tri in ipairs(col.tris) do assert(tri.c == colors.red, "mapColor nao pintou tudo") end

    -- voxels: um bloco solto tem as seis faces
    local um = { [1] = { [1] = { [1] = true } } }
    local mv = mesh.voxels(um, 1, 1, 1)
    assert(mv:count() == 12, "um bloco sozinho sao 6 faces = 12 triangulos, deu " .. mv:count())

    -- dois blocos colados perdem as duas faces que se tocam
    local dois = { [1] = { [1] = { [1] = true, [2] = true } } }
    local m2 = mesh.voxels(dois, 2, 1, 1)
    assert(m2:count() == 20, "dois blocos colados sao 10 faces = 20 triangulos, deu " .. m2:count())

    -- o teto de faces corta e avisa
    local m3, cortadas = mesh.voxels(um, 1, 1, 1, { maxFaces = 2 })
    assert(m3:count() == 4 and cortadas == 4, "o teto de faces nao cortou direito")

    -- grade
    local g = mesh.grid(3, 3, function() return 0 end)
    assert(g:count() == 18, "grade 3x3 sao 9 quadrados = 18 triangulos, deu " .. g:count())

    return true
end

return mesh
