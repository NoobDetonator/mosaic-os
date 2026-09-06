-- Painel do cluster: quem esta na frota, em que estado, e o que da' para mandar fazer.
--
-- A lista vem do netd (`mosaic.clusterNodes`), que e' quem recebe a batida de ponto. Este app
-- so' desenha e manda pedido - nao guarda estado de frota nenhum, porque "quem esta no ar"
-- depende do relogio e um valor guardado envelhece calado.
--
-- Papel e grupo se configuram em Configuracoes; aqui so' se le'.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")
local netx = mosaic.lib("netx")
local cluster = mosaic.lib("cluster")

local W = select(1, term.getSize())
local ESTREITO = W < 64

local f = ui.form()
local lista, status, barra
local senha                        -- perguntada uma vez, reaproveitada enquanto a janela vive
local nos = {}
local aviso                        -- achado da ultima varredura, mostrado ate' a proxima

local cabecalho = f:add(ui.label { x = 2, y = 1, w = -2, text = "" })
local recado = f:add(ui.label { x = 2, y = 2, w = -2, text = "", fg = theme.mutedFg })

-- ---------------------------------------------------------------- formato

-- "ha 42s" / "ha 5m" / "ha 2h". Segundo cru passa de mil rapido e vira ruido.
local function faz(ms, agora)
    local s = math.max(0, math.floor(((agora or os.epoch("utc")) - (ms or 0)) / 1000))
    if s < 90 then return "ha " .. s .. "s" end
    if s < 5400 then return "ha " .. math.floor(s / 60) .. "m" end
    return "ha " .. math.floor(s / 3600) .. "h"
end

local CURTO = { computador = "pc", turtle = "turtle", pocket = "pocket" }

-- Combustivel da turtle: -1 quer dizer sem limite (o servidor desligou o consumo).
local function combustivel(n)
    if n.kind ~= "turtle" or n.fuel == nil then return nil end
    if n.fuel < 0 then return "inf" end
    return tostring(n.fuel)
end

local function linhaDe(n, agora)
    -- A marca diz o essencial antes de qualquer texto: quem sou eu, quem esta no ar, quem sumiu.
    local marca = (n.id == os.getComputerID()) and "*" or (n.online and ">" or "!")
    local estado = n.online and "no ar" or faz(n.visto, agora)
    local comb = combustivel(n)
    if ESTREITO then
        -- Sem versao e sem combustivel: em 51 colunas eles empurram o nome para fora, e o
        -- nome e' o que a pessoa procura na lista.
        return string.format("%s #%-3d %-15s %-6s %s",
            marca, n.id, strutil.ellipsis(n.name or "?", 15),
            CURTO[n.kind] or "?", estado)
    end
    return string.format("%s #%-3d %-18s %-7s %-6s %-9s%s",
        marca, n.id, strutil.ellipsis(n.name or "?", 18),
        CURTO[n.kind] or "?", tostring(n.version or "?"), estado,
        comb and ("comb " .. comb) or "")
end

-- ---------------------------------------------------------------- a lista

local function atualiza()
    local papel = cluster.role()
    local eu = os.getComputerID()
    cabecalho.text = string.format("Papel: %s | Grupo: %s | Eu: #%d %s",
        papel, cluster.group(), eu, netx.name())

    if not mosaic.clusterNodes then
        recado.text = "Servico de rede desligado. Ligue em Configuracoes e reinicie."
        lista:setItems({})
        status.text = " Sem netd."
        f.dirty = true
        return
    end

    nos = select(1, mosaic.clusterNodes()) or {}
    local agora = os.epoch("utc")

    -- Cabecalho por grupo. A lista ja vem ordenada por grupo e depois por id (o cluster
    -- ordena de proposito: com `pairs` a linha que voce ia clicar troca de lugar sozinha).
    local itens, grupoAtual, noAr = {}, nil, 0
    for _, n in ipairs(nos) do
        local g = n.group or "sem grupo"
        if g ~= grupoAtual then
            grupoAtual = g
            itens[#itens + 1] = { header = true, text = " " .. g }
        end
        if n.online then noAr = noAr + 1 end
        itens[#itens + 1] = { no = n, text = linhaDe(n, agora),
            fg = (not n.online) and theme.mutedFg or nil }
    end
    lista:setItems(itens, true)

    if aviso then
        recado.text = aviso
        recado.fg = colors.orange
    elseif #nos == 0 then
        recado.fg = theme.mutedFg
        recado.text = papel == "mestre"
            and "Nenhum no bateu ponto ainda. Cada no aparece sozinho em ate 5s."
            or "Este computador e' um no. A frota aparece no mestre."
    else
        recado.fg = theme.mutedFg
        recado.text = ""
    end
    status.text = string.format(" %d no(s), %d no ar | %s", #nos, noAr,
        papel == "mestre" and "este e' o mestre" or ("mestre: "
            .. (cluster.masterId() and ("#" .. cluster.masterId()) or "nao configurado")))
    f.dirty = true
end

-- ---------------------------------------------------------------- acoes

-- Comando que muda algo precisa de senha. Ela e' pedida uma vez e assina os pedidos
-- seguintes; NAO viaja na mensagem (o netx poe uma assinatura HMAC no lugar).
local function pedeSenha()
    if senha then return senha end
    senha = ui.prompt("Senha da rede:", "", "Senha", { mask = "*" })
    return senha
end

local function manda(id, msg)
    local s = pedeSenha()
    if not s then return nil, "cancelado" end
    local r, err = netx.ask(id, netx.assina(msg, s))
    -- Senha errada chega como "assinatura invalida": esquecer a guardada deixa a pessoa
    -- tentar de novo sem fechar a janela.
    if not r and tostring(err):find("assinatura") then senha = nil end
    return r, err
end

local function detalhes(n)
    local linhas = {
        string.format("#%d  %s", n.id, tostring(n.name)),
        "Grupo: " .. tostring(n.group),
        "Tipo: " .. tostring(n.kind) .. "   Versao: " .. tostring(n.version),
        "Estado: " .. (n.online and "no ar" or ("fora do ar " .. faz(n.visto))),
        "Visto: " .. faz(n.visto) .. "   Conhecido desde: " .. faz(n.desde),
        "Livre: " .. strutil.bytes(n.free or 0),
    }
    if n.kind == "turtle" then
        linhas[#linhas + 1] = "Combustivel: " .. (combustivel(n) or "?")
        if n.holding then linhas[#linhas + 1] = "Segurando: " .. tostring(n.holding) end
    end
    local p = n.peripherals
    if p and #p > 0 then linhas[#linhas + 1] = "Perifericos: " .. table.concat(p, ", ") end
    ui.msgbox(table.concat(linhas, "\n"), "No #" .. n.id)
end

-- Reiniciar o grupo inteiro. Um por um, porque uma transmissao nao diz quem obedeceu - e
-- aqui saber quem ficou de fora e' o ponto.
local function reiniciaGrupo(grupo)
    local alvos = {}
    for _, n in ipairs(nos) do
        if (n.group or "sem grupo") == grupo and n.online and n.id ~= os.getComputerID() then
            alvos[#alvos + 1] = n
        end
    end
    if #alvos == 0 then ui.msgbox("Nenhum no do grupo esta no ar.", grupo) return end
    if not ui.confirm("Reiniciar " .. #alvos .. " no(s) de '" .. grupo .. "'?", "Cluster") then return end
    local ok, falhou = 0, {}
    for _, n in ipairs(alvos) do
        status.text = " Reiniciando #" .. n.id .. "..."
        f:draw()
        local r, err = manda(n.id, { type = "reboot" })
        if r then ok = ok + 1 else falhou[#falhou + 1] = "#" .. n.id .. ": " .. tostring(err) end
    end
    ui.msgbox(ok .. " reiniciando." ..
        (#falhou > 0 and ("\nFalharam:\n" .. table.concat(falhou, "\n")) or ""), "Cluster")
    atualiza()
end

-- Espalhar o sistema: o mestre faz o no ficar igual a ele.
--
-- Compara SHA-1 de arquivo por arquivo, e nao versao+tamanho como o plano previa: medido no
-- servidor, hash do sistema inteiro custa 1,8 s (341 KB/s para 605 KB), bem dentro dos 7 s do
-- CC. Tamanho igual com conteudo diferente passaria batido, que era a critica certa.
--
-- O mestre nao baixa nada: ele manda o que TEM. Quem precisa de internet e' so' ele, e so' na
-- hora de atualizar a si mesmo pelo instalador.
local function espalha(alvos)
    local s = pedeSenha()
    if not s then return end
    local busy = ui.busy("Atualizando", "lendo o meu sistema...")
    local okMeu, meu = pcall(cluster.inventario)
    if not okMeu then busy.close() ui.msgbox("Nao consegui ler o meu sistema: " .. tostring(meu), "Erro") return end

    local resumo = {}
    for _, n in ipairs(alvos) do
        busy.set(0, "#" .. n.id .. ": perguntando o que ele tem...")
        -- Prazo generoso: o no gasta ~1,8 s so' calculando os hashes dele.
        local inv, err = netx.ask(n.id, { type = "inventory" }, 20)
        if not inv or type(inv.files) ~= "table" then
            resumo[#resumo + 1] = "#" .. n.id .. ": nao respondeu (" .. tostring(err) .. ")"
        else
            local mandar, sobrando = cluster.diferenca(meu, inv.files)
            if #mandar == 0 then
                resumo[#resumo + 1] = "#" .. n.id .. ": ja esta igual"
                    .. (#sobrando > 0 and (", com " .. #sobrando .. " arquivo(s) a mais") or "")
            else
                local enviados, falha = 0, nil
                for i, caminho in ipairs(mandar) do
                    busy.set(i / #mandar, "#" .. n.id .. " " .. caminho)
                    local h = fs.open(caminho, "r")
                    local dados = h and h.readAll() or nil
                    if h then h.close() end
                    if not dados then falha = caminho .. ": nao consegui ler aqui" break end
                    local r, e = netx.ask(n.id, netx.assina(
                        { type = "sendFile", path = caminho, content = dados, quiet = true }, s), 15)
                    if not r then falha = caminho .. ": " .. tostring(e) break end
                    enviados = enviados + 1
                end
                resumo[#resumo + 1] = string.format("#%d: %d de %d arquivo(s)%s%s",
                    n.id, enviados, #mandar,
                    #sobrando > 0 and (", " .. #sobrando .. " a mais la") or "",
                    falha and ("  PAROU EM " .. falha) or "")
                -- Reiniciar so' se foi tudo: `mosaic.lib` guarda modulo em cache, entao
                -- arquivo novo so' vale depois do boot - mas reiniciar no meio de uma
                -- transferencia quebrada e' trocar um problema por outro pior.
                if not falha then
                    netx.ask(n.id, netx.assina({ type = "reboot" }, s), 5)
                    resumo[#resumo] = resumo[#resumo] .. ", reiniciando"
                end
            end
        end
    end
    busy.close()
    ui.msgbox(table.concat(resumo, "\n"), "Atualizacao da frota")
    atualiza()
end

-- Limpar o que sobra: arquivo que existe no no e nao existe mais no mestre.
--
-- E' acao SEPARADA de atualizar, de proposito. Atualizar so' acrescenta e sobrescreve, e por
-- isso e' seguro repetir; apagar nao volta atras. Misturar as duas faria toda atualizacao
-- carregar um risco que ninguem pediu.
--
-- A lista aparece ANTES da confirmacao: "apagar 12 arquivos" nao e' informacao suficiente
-- para alguem dizer sim.
local function limpa(no)
    local s = pedeSenha()
    if not s then return end
    local busy = ui.busy("Limpando", "lendo o meu sistema...")
    local okMeu, meu = pcall(cluster.inventario)
    if not okMeu then busy.close() ui.msgbox(tostring(meu), "Erro") return end
    busy.set(0, "perguntando ao no...")
    local inv, err = netx.ask(no.id, { type = "inventory" }, 20)
    busy.close()
    if not inv or type(inv.files) ~= "table" then
        ui.msgbox("O no nao respondeu: " .. tostring(err), "Erro") return
    end

    local _, sobrando = cluster.diferenca(meu, inv.files)
    -- O no decide o que aceita apagar, mas mostrar aqui so' o que ele vai aceitar evita
    -- prometer na tela uma limpeza que volta cheia de recusa.
    local alvos = {}
    for _, caminho in ipairs(sobrando) do
        if cluster.podeApagar(caminho) then alvos[#alvos + 1] = caminho end
    end
    local protegidos = #sobrando - #alvos
    if #alvos == 0 then
        ui.msgbox("Nada a limpar no #" .. no.id .. "."
            .. (protegidos > 0 and ("\n\n" .. protegidos .. " arquivo(s) a mais, mas fora do /os: nao se apagam.") or ""),
            "Limpeza")
        return
    end

    local amostra = {}
    for i = 1, math.min(#alvos, 10) do amostra[#amostra + 1] = alvos[i] end
    if #alvos > 10 then amostra[#amostra + 1] = "... e mais " .. (#alvos - 10) end
    if not ui.confirm("Apagar do #" .. no.id .. ":\n\n" .. table.concat(amostra, "\n")
        .. "\n\nIsto nao volta atras.", "Limpeza") then return end

    busy = ui.busy("Limpando #" .. no.id, "")
    local apagados, falhas = 0, {}
    for i, caminho in ipairs(alvos) do
        busy.set(i / #alvos, caminho)
        local r, e = netx.ask(no.id, netx.assina({ type = "deleteFile", path = caminho }, s), 10)
        if r then apagados = apagados + 1 else falhas[#falhas + 1] = caminho .. ": " .. tostring(e) end
    end
    busy.close()
    ui.msgbox(apagados .. " de " .. #alvos .. " apagado(s)."
        .. (protegidos > 0 and ("\n" .. protegidos .. " fora do /os foram poupados.") or "")
        .. (#falhas > 0 and ("\n\nFalharam:\n" .. table.concat(falhas, "\n")) or ""), "Limpeza")
end

local function acoes(n)
    if not n then return end
    local itens = {
        { text = "Detalhes", run = function() detalhes(n) end },
        { text = "Terminal remoto", run = function()
            mosaic.launchWith({ title = "Remoto #" .. n.id }, "/os/apps/remote.lua", tostring(n.id))
        end },
        { text = "Executar Lua", run = function()
            local code = ui.prompt("Codigo Lua:", "return os.getComputerLabel()", "No #" .. n.id)
            if not code then return end
            local r, err = manda(n.id, { type = "exec", code = code })
            if not r then ui.msgbox(tostring(err), "Erro") return end
            ui.msgbox(((r.output or "") ~= "" and r.output .. "\n" or "")
                .. table.concat(r.returns or {}, "\n"), "Resultado")
        end },
        { text = "Atualizar este no", run = function()
            if not ui.confirm("Deixar o #" .. n.id .. " igual a este computador?", "Cluster") then return end
            espalha({ n })
        end },
        { text = "Atualizar o grupo " .. (n.group or "sem grupo"), run = function()
            local alvos = {}
            for _, x in ipairs(nos) do
                if (x.group or "sem grupo") == (n.group or "sem grupo")
                    and x.online and x.id ~= os.getComputerID() then alvos[#alvos + 1] = x end
            end
            if #alvos == 0 then ui.msgbox("Nenhum no do grupo esta no ar.", "Cluster") return end
            if not ui.confirm("Atualizar " .. #alvos .. " no(s)?", "Cluster") then return end
            espalha(alvos)
        end },
        { text = "Limpar o que sobra", run = function() limpa(n) end },
        { text = "Reiniciar", run = function()
            if not ui.confirm("Reiniciar o no #" .. n.id .. "?", "Cluster") then return end
            local r, err = manda(n.id, { type = "reboot" })
            ui.msgbox(r and "Reiniciando." or tostring(err), "No #" .. n.id)
            atualiza()
        end },
        { text = "Reiniciar o grupo " .. (n.group or "sem grupo"), run = function()
            reiniciaGrupo(n.group or "sem grupo")
        end },
        { text = "Esquecer este no", run = function()
            -- So' faz sentido para no que nao volta mais: a lista e' persistida em disco, e
            -- um computador quebrado ficaria de lembrete vermelho para sempre.
            if not ui.confirm("Tirar #" .. n.id .. " da lista?\nEle volta se bater ponto de novo.",
                "Cluster") then return end
            if mosaic.clusterForget then mosaic.clusterForget(n.id) end
            atualiza()
        end },
    }
    local idx = ui.menu(itens, 3, 4, math.min(W - 6, 34), { maxH = 10 })
    if idx and itens[idx] then itens[idx].run() end
end

-- ---------------------------------------------------------------- layout
--
-- A ordem importa: a fila mede a propria altura, o rodape se ancora acima dela, e a lista
-- preenche o que sobrar. O `fillTo` so' enxerga quem ja entrou no form.
-- Varredura: quem responde na rede mas NAO esta na frota, e por que.
--
-- Existe por causa de um caso encontrado no servidor: dois computadores configurados como
-- mestre. Mestre nao bate ponto (so' no empurra), entao cada um enxergava so' a si mesmo e
-- NADA avisava - a tela dizia "1 no" nos dois, como se estivesse tudo certo. Sem esta
-- varredura nao ha como descobrir isso de dentro do jogo.
local function procura()
    status.text = " Procurando na rede..."
    f:draw()
    local naFrota = {}
    for _, n in ipairs(nos) do naFrota[n.id] = true end
    local fora, outrosMestres = {}, 0
    for _, p in ipairs(netx.peers()) do
        if not naFrota[p.id] then
            local r = netx.ask(p.id, { type = "whoami" }, 2)
            local motivo
            if not r then motivo = "responde ping, mas nao conhece cluster (versao antiga?)"
            elseif r.role == "mestre" then
                outrosMestres = outrosMestres + 1
                motivo = "tambem esta como MESTRE - por isso nao bate ponto"
            else motivo = "e' no do grupo '" .. tostring(r.group) .. "' mas nao chegou aqui" end
            fora[#fora + 1] = string.format("#%d %s\n   %s", p.id, tostring(p.name or "?"), motivo)
        end
    end
    if #fora == 0 then
        aviso = nil
        ui.msgbox("Todo computador que respondeu esta na frota.", "Varredura")
    else
        aviso = outrosMestres > 0
            and ("Ha " .. outrosMestres .. " outro(s) MESTRE na rede - veja Procurar.")
            or (#fora .. " computador(es) fora da frota - veja Procurar.")
        ui.msgbox("Fora da frota:\n\n" .. table.concat(fora, "\n"), "Varredura")
    end
    atualiza()
end

barra = ui.row(f, { bottom = 0, items = {
    { text = "&Atualizar", onClick = function() atualiza() end },
    { text = "&Procurar", alt = true, onClick = function() procura() end },
    { text = "A&coes", alt = true, onClick = function()
        local it = lista:getSelected()
        acoes(it and it.no)
    end },
    { text = "&Config", alt = true, onClick = function()
        mosaic.launchWith({ title = "Configuracoes" }, "/os/apps/settings.lua")
    end },
} })
status = f:add(ui.label { x = 1, above = barra, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
lista = f:add(ui.list { x = 1, y = 3, w = "fill", fillTo = status, items = {},
    onActivate = function(_, item) acoes(item and item.no) end })

-- Redesenha sozinho: um no cai sem avisar, e uma tela parada mente. So' quando a janela esta
-- na frente - atras nao ha quem leia, e o netd continua contando ponto de qualquer jeito.
local BATIDA = 2
local t = os.startTimer(BATIDA)
f.onEvent = function(_, ev, a)
    if ev == "timer" and a == t then
        t = os.startTimer(BATIDA)
        if mosaic.focused() == mosaic.current() then atualiza() end
        return true
    end
end

atualiza()
f:run()
