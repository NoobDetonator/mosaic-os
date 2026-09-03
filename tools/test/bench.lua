-- Medicao de desempenho do Mosaic. Roda com `node tools/bench.js [--size 80x30]`.
--
-- Serve para otimizar com numero e nao com palpite. Os tempos aqui sao do CraftOS-PC ou do
-- emulador, que sao mais rapidos que o computador do jogo: o que vale e a PROPORCAO entre as
-- linhas, e o custo por quadro comparado ao tique do Minecraft (50 ms).
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path

settings.define("mosaic.clock", { type = "string", default = "real" })
local theme = require("kernel.theme")
local wm = require("kernel.wm")
local proc = require("kernel.proc")
local pixel = require("lib.pixel")
local iconlib = require("lib.icons")
local vector = require("lib.vector")
local mesh = require("lib.mesh")
local three = require("lib.three")
local mcmath = require("lib.mcmath")
proc.api.ui = require("kernel.ui")
proc.parentShell = shell
wm.init(term.current())
proc.init()

local results = {}

-- os.clock tem resolucao de tique (0,05 s); epoch("utc") da milissegundo de verdade.
local function bench(name, times, fn)
    fn()                       -- uma vez fora da conta, para pagar o custo de carregar
    local t0 = os.epoch("utc")
    for _ = 1, times do fn() end
    local total = os.epoch("utc") - t0
    results[#results + 1] = { name = name, times = times, total = total, each = total / times }
end

local lastMarker = 0
proc.spawn { title = "sentinel", hidden = true, fn = function()
    while true do local _, id = os.pullEvent("test_marker") lastMarker = id end
end }
local marker = 0
local function pump()
    marker = marker + 1
    os.queueEvent("test_marker", marker)
    for _ = 1, 400 do
        if lastMarker >= marker then return end
        proc.step()
    end
end

-- ---------------------------------------------------------------- cenario
local bootStart = os.epoch("utc")
local desk = proc.launch("/os/apps/desktop.lua", {}, {
    title = "Area de trabalho", chrome = false, bottom = true, noclose = true,
    x = 1, y = 1, w = wm.W, h = wm.H - 1, bg = theme.desktopBg, fg = theme.desktopFg,
})
pump()
results[#results + 1] = { name = "abrir a area de trabalho", times = 1,
    total = os.epoch("utc") - bootStart, each = os.epoch("utc") - bootStart }

local appStart = os.epoch("utc")
local files = proc.launch("/os/apps/files.lua", {}, { title = "Arquivos" })
pump()
results[#results + 1] = { name = "abrir o app Arquivos", times = 1,
    total = os.epoch("utc") - appStart, each = os.epoch("utc") - appStart }

local procs = proc.list()

-- ---------------------------------------------------------------- medidas
bench("quadro do compositor (2 janelas)", 200, function()
    wm.render(procs, proc.focus)
end)

-- Sem nada mudar, o diff deveria mandar so a linha do relogio.
bench("quadro sem mudanca (so o diff)", 200, function()
    wm.render(procs, proc.focus)
end)

bench("icone ja no cache", 500, function()
    iconlib.draw(wm.canvas, "files", 2, 2, theme.desktopBg)
end)

bench("icone montado do zero", 20, function()
    iconlib.clearCache()
    iconlib.draw(wm.canvas, "files", 2, 2, theme.desktopBg)
end)

bench("canvas de tela cheia (fromImage)", 10, function()
    local img = {}
    for y = 1, wm.H * 3 do
        local row = {}
        for x = 1, wm.W * 2 do row[x] = colors.blue end
        img[y] = row
    end
    pixel.fromImage(img, wm.W, wm.H, colors.black)
end)

local logo = vector.load("/os/share/vectors/logo.lua")
if logo then
    bench("vetor rasterizado (6x4 celulas)", 20, function()
        vector.clearCache()
        vector.rasterize(logo, 6, 4, colors.black)
    end)
end

bench("um passo do kernel (evento vazio)", 200, function()
    os.queueEvent("bench_ping")
    proc.step()
end)

-- ---------------------------------------------------------------- 3D
-- A pergunta que decide o formato da pre-visualizacao: quanto custa um quadro. Um circulo
-- de 15 e' o caso comum; uma esfera oca de 15 e' o caso ruim.
do
    local canvas = pixel.new(wm.W, wm.H - 4, colors.black)
    local frame = three.frame(canvas)
    frame:orbit({ 0, 0, 0 }, 2.2, 0.7, 0.5)

    local cubo = mesh.cube():center()
    bench("3D: um cubo (12 triangulos)", 50, function()
        frame:clear(colors.black)
        frame:draw({ { model = cubo } })
    end)

    local circ = mcmath.build("circulo", { w = 15 })
    local mCirc = mesh.voxels(circ.layers, circ.w, circ.h, circ.d)
    mCirc:center():normalizeScale()
    results[#results + 1] = { name = "  (circulo 15: " .. mCirc:count() .. " triangulos)",
        times = 1, total = 0, each = 0 }
    bench("3D: circulo 15 macico", 20, function()
        frame:clear(colors.black)
        frame:draw({ { model = mCirc } })
    end)

    local esf = mcmath.build("esfera", { w = 15, hollow = true })
    local mEsf, cortadas = mesh.voxels(esf.layers, esf.w, esf.h, esf.d, { maxFaces = 100000 })
    mEsf:center():normalizeScale()
    results[#results + 1] = { name = "  (esfera oca 15: " .. mEsf:count() .. " tri, " ..
        esf.total .. " blocos, cortou " .. cortadas .. ")", times = 1, total = 0, each = 0 }
    bench("3D: esfera oca 15 inteira", 5, function()
        frame:clear(colors.black)
        frame:draw({ { model = mEsf } })
    end)

    bench("3D: montar a malha da esfera", 5, function()
        mesh.voxels(esf.layers, esf.w, esf.h, esf.d, { maxFaces = 100000 })
    end)
end

-- ---------------------------------------------------------------- relatorio
term.redirect(term.native())
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print(string.format("Mosaic bench - tela %dx%d (%d x %d sub-pixels)", wm.W, wm.H, wm.W * 2, wm.H * 3))
print("")
for _, r in ipairs(results) do
    print(string.format("%-30s %6.2f ms", r.name:sub(1, 30), r.each))
end
print("")
print("Referencia: um tique do Minecraft e 50 ms.")
os.shutdown(0)
