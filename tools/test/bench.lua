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
--
-- Mediana de varias rodadas, e nao media de uma: com poucas iteracoes, uma pausa do coletor
-- de lixo caindo dentro do laco dominava o numero e a medida virava sorte. O min e o max
-- entram no relatorio para a dispersao ficar visivel em vez de escondida.
local function bench(name, times, fn, rodadas)
    rodadas = rodadas or 5
    fn()                       -- uma vez fora da conta, para pagar o custo de carregar
    local amostras = {}
    for r = 1, rodadas do
        if collectgarbage then pcall(collectgarbage) end
        local t0 = os.epoch("utc")
        for _ = 1, times do fn() end
        amostras[r] = (os.epoch("utc") - t0) / times
    end
    table.sort(amostras)
    results[#results + 1] = { name = name, times = times,
        each = amostras[math.ceil(#amostras / 2)], min = amostras[1], max = amostras[#amostras] }
end

-- Linha solta no relatorio, para anotar um numero que nao e tempo.
local function nota(texto)
    results[#results + 1] = { name = texto, nota = true }
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
-- Cada custo medido separado. Antes as tres linhas de 3D incluiam o frame:clear, que sozinho
-- e' milhares de escritas de tabela: para o cubo de 12 triangulos o clear custava mais que o
-- desenho, e ninguem sabia disso olhando o relatorio.
do
    local canvas = pixel.new(wm.W, wm.H - 4, colors.black)
    local frame = three.frame(canvas)
    frame:orbit({ 0, 0, 0 }, 2.2, 0.7, 0.5)
    frame:clear(colors.black)      -- paga o crescimento do z-buffer antes de medir

    nota(string.format("  (canvas %dx%d celulas = %d pontos)", canvas.cols, canvas.rows,
        canvas.w * canvas.h))

    bench("3D: clear (canvas + zbuf)", 100, function() frame:clear(colors.black) end)
    bench("3D: canvas:render (a saida)", 100, function() canvas:render(wm.canvas, 1, 1) end)

    local cubo = mesh.cube():center()
    bench("3D: cubo 12 tri, clear+draw", 200, function()
        frame:clear(colors.black)
        frame:draw({ { model = cubo } })
    end)

    -- Varredura com a MESMA cobertura de tela: separa o custo por triangulo do custo por pixel.
    local function grade(n)
        return mesh.grid(n, n, function() return 0 end):center():normalizeScale()
    end
    for _, n in ipairs({ 7, 22, 71 }) do
        local g = grade(n)
        nota("  (grade " .. n .. "x" .. n .. ": " .. g:count() .. " triangulos)")
        bench("3D: grade " .. n .. "x" .. n .. ", clear+draw", 20, function()
            frame:clear(colors.black)
            frame:draw({ { model = g } })
        end)
    end

    local circ = mcmath.build("circulo", { w = 15 })
    local mCirc = mesh.voxels(circ.layers, circ.w, circ.h, circ.d)
    mCirc:center():normalizeScale()
    nota("  (circulo 15: " .. mCirc:count() .. " triangulos)")
    bench("3D: circulo 15 macico", 20, function()
        frame:clear(colors.black)
        frame:draw({ { model = mCirc } })
    end)

    local esf = mcmath.build("esfera", { w = 15, hollow = true })
    local mEsf, cortadas = mesh.voxels(esf.layers, esf.w, esf.h, esf.d, { maxFaces = 100000 })
    mEsf:center():normalizeScale()
    nota("  (esfera oca 15: " .. mEsf:count() .. " tri, " .. esf.total ..
        " blocos, cortou " .. cortadas .. ")")
    bench("3D: esfera oca 15", 10, function()
        frame:clear(colors.black)
        frame:draw({ { model = mEsf } })
    end)

    -- A malha de voxel se declara fechada, entao a linha de cima ja mede COM descarte de
    -- face de costas. Esta aqui desliga, para a comparacao continuar existindo.
    bench("3D: esfera oca 15, sem cull", 10, function()
        frame:clear(colors.black)
        frame:draw({ { model = mEsf } }, { cull = false })
    end)

    bench("3D: montar a malha da esfera", 5, function()
        mesh.voxels(esf.layers, esf.w, esf.h, esf.d, { maxFaces = 100000 })
    end)

    -- Quadro inteiro, dos dois jeitos: criando canvas e quadro toda vez, e reaproveitando.
    -- A diferenca e' exatamente o que o app ganha ao guardar os dois.
    bench("3D: quadro criando canvas e frame", 20, function()
        local c = pixel.new(wm.W, wm.H - 4, colors.black)
        local f = three.frame(c)
        f:orbit({ 0, 0, 0 }, 2.2, 0.7, 0.5)
        f:clear(colors.black)
        f:draw({ { model = mCirc } })
        c:render(wm.canvas, 1, 1)
    end)
    bench("3D: quadro reaproveitando os dois", 20, function()
        frame:orbit({ 0, 0, 0 }, 2.2, 0.7, 0.5)
        frame:clear(colors.black)
        frame:draw({ { model = mCirc } })
        canvas:render(wm.canvas, 1, 1)
    end)
end

-- ---------------------------------------------------------------- audio
-- A pergunta que decide o desenho do player: cabe decodificar um bloco inteiro de uma vez,
-- ou o daemon precisa picar em pedacos menores? Um bloco de 16 KiB e' ~2,7 s de som, entao
-- so' passa a doer perto de 2700 ms - mas o limite de 7 s do CC e' por RESUME, e a propria
-- documentacao avisa que a primeira fornada pode estourar. Acima de ~50 ms eu pico.
do
    local audio = require("lib.audio")
    local dec = audio.decoder()
    if dec then
        -- O DFPWM gasta 1 bit por amostra e aceita qualquer entrada, entao bytes ao acaso
        -- medem o mesmo que uma musica de verdade e nao precisam de arquivo.
        local partes = {}
        for i = 1, audio.CHUNK do partes[i] = string.char(math.random(0, 255)) end
        local chunk = table.concat(partes)
        nota(string.format("  (bloco de %d bytes = %d amostras = %.1f s de som)",
            #chunk, #chunk * 8, (#chunk * 8) / audio.RATE))
        bench("audio: decodificar um bloco DFPWM", 5, function() dec(chunk) end)
    else
        nota("  (sem cc.audio.dfpwm nesta ROM: decodificacao nao medida)")
    end
end

-- ---------------------------------------------------------------- relatorio
-- Vai para arquivo, nao so' para a tela: o relatorio ja passou das 19 linhas do terminal e as
-- medidas de 3D rolavam para fora sem ninguem notar que faltavam.
local linhas = {
    string.format("Mosaic bench - tela %dx%d (%d x %d sub-pixels)", wm.W, wm.H, wm.W * 2, wm.H * 3),
    "",
}
for _, r in ipairs(results) do
    if r.nota then
        linhas[#linhas + 1] = r.name
    else
        local espalhou = (r.max and r.min and r.max > r.min) and
            string.format("  (%.2f a %.2f)", r.min, r.max) or ""
        linhas[#linhas + 1] = string.format("%-34s %7.2f ms%s", r.name:sub(1, 34), r.each, espalhou)
    end
end
linhas[#linhas + 1] = ""
linhas[#linhas + 1] = "Referencia: um tique do Minecraft e 50 ms."

local texto = table.concat(linhas, "\n")
local h = fs.open("/out/bench.txt", "w")
if h then h.write(texto) h.close() end

term.redirect(term.native())
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("bench pronto: " .. #results .. " linhas em /out/bench.txt")
os.shutdown(0)
