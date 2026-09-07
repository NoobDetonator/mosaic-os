-- Painel da turtle: onde ela esta, quanto tem de combustivel, e o que da' para mandar fazer.
--
-- A tela de uma turtle e' 39x13. Nao cabe area de trabalho com janelas ali, cabe um painel -
-- e e' por isso que este app existe separado em vez de ser uma aba do Cluster.
local ui = mosaic.ui
local theme = mosaic.theme
local tx = mosaic.lib("turtlex")
local cluster = mosaic.lib("cluster")

local f = ui.form()
local linhaPos, linhaComb, linhaRede, recado, barra

local function diz(texto, cor)
    recado.text = texto or ""
    recado.fg = cor or theme.mutedFg
    f.dirty = true
end

local function atualiza()
    if not tx.existe() then
        linhaPos.text = "Este computador nao e' uma turtle."
        linhaComb.text = "Abra este painel numa turtle."
        linhaRede.text = ""
        f.dirty = true
        return
    end

    local p = tx.posicao()
    -- "assumida" e nao "certa" e' informacao, nao detalhe: uma posicao vinda so' de conta
    -- propria pode ter escorregado se alguem empurrou a turtle ou ela renasceu fora do lugar.
    linhaPos.text = string.format("x=%d y=%d z=%d  olhando %s", p.x, p.y, p.z, p.olhando)
    linhaPos.fg = p.certa and theme.fg or colors.orange

    local c = tx.combustivel()
    local comb = (c == -1) and "sem limite" or tostring(c or "?")
    local cap = tx.capacidades() or {}
    linhaComb.text = string.format("Combustivel: %-10s Modem: %s",
        comb, cap.modem and "sim" or "NAO")

    linhaRede.text = string.format("%s | grupo %s | passos %d",
        p.certa and "posicao conferida" or "posicao assumida",
        cluster.group(), p.passos or 0)
    f.dirty = true
end

linhaPos = f:add(ui.label { x = 2, y = 1, w = -2, text = "" })
linhaComb = f:add(ui.label { x = 2, y = 2, w = -2, text = "" })
linhaRede = f:add(ui.label { x = 2, y = 3, w = -2, text = "", fg = theme.mutedFg })

-- ---------------------------------------------------------------- acoes

local function descobre()
    diz("Descobrindo: vou dar um passo e voltar...", colors.orange)
    f:draw()
    local ok, resultado = tx.descobre()
    if ok then
        diz("Achei: olhando " .. tostring(resultado), colors.lime)
    else
        -- Sem GPS e' o caso comum, e o recado tem de dizer o que fazer em vez de so' falhar.
        diz(tostring(resultado), colors.red)
    end
    atualiza()
end

local function ancora()
    local p = tx.posicao()
    local texto = ui.prompt("x y z olhando (leia no F3):",
        string.format("%d %d %d %s", p.x, p.y, p.z, p.olhando), "Ancorar")
    if not texto then return end
    local x, y, z, olhando = texto:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(%a+)%s*$")
    if not x then
        diz("Escreva assim: 10 64 -3 norte", colors.red)
        return
    end
    local valido = false
    for _, nome in ipairs(tx.OLHARES) do if nome == olhando then valido = true end end
    if not valido then
        diz("Olhar tem de ser: " .. table.concat(tx.OLHARES, ", "), colors.red)
        return
    end
    tx.define(tonumber(x), tonumber(y), tonumber(z), olhando)
    diz("Ancorada.", colors.lime)
    atualiza()
end

local function abastece()
    local antes = tx.combustivel()
    if antes == -1 then diz("O servidor desligou o consumo: nao precisa.", theme.mutedFg) return end
    local subiu = tx.abastece()
    if subiu > 0 then diz("Subiu " .. subiu .. " de combustivel.", colors.lime)
    else diz("Nada nos slots serve de combustivel.", colors.orange) end
    atualiza()
end

barra = ui.row(f, { bottom = 0, items = {
    { text = "&Descobrir", onClick = descobre },
    { text = "&Ancorar", alt = true, onClick = ancora },
    { text = "A&bastecer", alt = true, onClick = abastece },
} })
recado = f:add(ui.label { x = 1, above = barra, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
-- Dica logo acima do recado: sem ela ninguem descobre que da' para dirigir pelo teclado, e
-- num painel de turtle andar e' a coisa mais util que existe.
f:add(ui.label { x = 2, above = recado, w = -2,
    text = "WASD move | espaco/ctrl sobe e desce", fg = theme.mutedFg })

-- ---------------------------------------------------------------- teclado
--
-- Dirigir pelo teclado, nao por botao: sao seis acoes, e seis botoes nao cabem em 39 colunas.
local TECLAS = {
    [keys.w] = { "anda", "frente" },
    [keys.s] = { "anda", "tras" },
    [keys.a] = { "vira", "esquerda" },
    [keys.d] = { "vira", "direita" },
    [keys.space] = { "anda", "cima" },
    [keys.leftCtrl] = { "anda", "baixo" },
}

f.onEvent = function(_, ev, a)
    if ev == "key" then
        local acao = TECLAS[a]
        if not acao then return end
        if not tx.existe() then diz("Nao sou uma turtle.", colors.red) return true end
        local ok, motivo = tx[acao[1]](acao[2])
        if ok then diz("") else diz(tostring(motivo), colors.red) end
        atualiza()
        return true
    end
end

atualiza()
f:run()
