-- A turtle como nó do cluster: capacidades, movimento com motivo, e posição que sobrevive.
--
--   local tx = mosaic.lib("turtlex")
--   if tx.existe() then
--       local ok, porque = tx.anda("frente")
--       local p = tx.posicao()          -- { x, y, z, olhando }
--   end
--
-- O DESENHO INTEIRO sai do chunk descarregado. Quando ninguem esta por perto o pedaco de
-- mundo sai de memoria e a turtle **nao pausa**: ela perde o estado de execucao e volta para
-- o shell vazio. Entao nada que importa pode viver so' na memoria - a posicao vai para disco
-- a cada passo, e nao no fim da tarefa.
--
-- Proibido nesta versao (mais novo que o alvo 1.101):
--   * `turtle.getEquippedLeft/Right` (1.116) - por isso a ferramenta e' descoberta por sonda;
--   * prazo no `rednet.lookup` (1.118).
local turtlex = {}

turtlex.ARQUIVO = "/os/var/turtle/pos.json"

-- Norte, leste, sul, oeste. A ordem e' a do jogo: virar a direita anda +1 nesta lista, e e'
-- por isso que a conta e' `% 4` e nao um monte de if.
turtlex.OLHARES = { "norte", "leste", "sul", "oeste" }
local PASSO = {
    norte = { x = 0, z = -1 },
    leste = { x = 1, z = 0 },
    sul   = { x = 0, z = 1 },
    oeste = { x = -1, z = 0 },
}

function turtlex.existe() return turtle ~= nil end

-- ---------------------------------------------------------------- combustivel

-- `getFuelLevel` devolve a STRING "unlimited" quando o servidor desligou o consumo. Nao e'
-- numero, e comparar isso com um limite derruba o servico - foi o primeiro tropeco aqui.
-- -1 quer dizer "sem limite".
function turtlex.combustivel()
    if not turtle then return nil end
    local ok, v = pcall(turtle.getFuelLevel)
    if not ok then return nil end
    if v == "unlimited" then return -1 end
    return tonumber(v)
end

function turtlex.combustivelIlimitado() return turtlex.combustivel() == -1 end

-- Da' para andar quantos blocos? -1 = sem limite.
function turtlex.alcance()
    local c = turtlex.combustivel()
    if c == nil then return 0 end
    return c
end

-- Tenta abastecer com o que estiver nos slots. Devolve quanto subiu.
function turtlex.abastece(alvo)
    if not turtle then return 0 end
    if turtlex.combustivelIlimitado() then return 0 end
    local antes = turtlex.combustivel() or 0
    local guardado = turtle.getSelectedSlot()
    for slot = 1, 16 do
        if (turtlex.combustivel() or 0) >= (alvo or math.huge) then break end
        turtle.select(slot)
        -- `refuel` levanta erro em item que nao e' combustivel em algumas versoes; pcall
        -- porque abastecer nao pode derrubar quem chamou.
        pcall(turtle.refuel)
    end
    turtle.select(guardado)
    return (turtlex.combustivel() or 0) - antes
end

-- ---------------------------------------------------------------- capacidades

-- Modem equipado: da' para descobrir de verdade, porque modem E' periferico e aparece no
-- `peripheral.getType` do lado onde esta.
local function modemNoLado(lado)
    local ok, tipo = pcall(peripheral.getType, lado)
    return ok and tipo == "modem"
end

-- Ferramenta e' outra historia: no CC 1.101 nao existe jeito de PERGUNTAR o que esta
-- equipado (o `getEquippedLeft` e' de 1.116). A sonda aproveita que o `dig` diz o motivo:
-- sem ferramenta ele responde algo com "tool"; com ferramenta e sem bloco na frente, algo
-- com "nothing".
--
-- So' que `dig` QUEBRA o bloco. Entao a sonda so' roda quando o `inspect` garante que nao ha
-- nada na frente - e quando ha, devolve nil em vez de chutar. Melhor "nao sei" que cavar a
-- parede de alguem para responder uma pergunta de tela.
function turtlex.temFerramenta()
    if not turtle then return nil end
    local temBloco = turtle.inspect()
    if temBloco then return nil end                  -- nao da' para saber sem cavar
    local ok, motivo = turtle.dig()
    if ok then return true end                       -- cavou alguma coisa: tem ferramenta
    motivo = tostring(motivo or ""):lower()
    if motivo:find("tool") then return false end
    return true
end

function turtlex.capacidades()
    if not turtle then return nil end
    return {
        modem = modemNoLado("left") or modemNoLado("right"),
        combustivel = turtlex.combustivel(),
        ilimitado = turtlex.combustivelIlimitado(),
    }
end

-- ---------------------------------------------------------------- posicao

local pos           -- cache em memoria; o disco continua sendo a verdade

local function vazia()
    return { x = 0, y = 0, z = 0, olhando = "norte", certa = false, passos = 0 }
end

function turtlex.posicao()
    if pos then return pos end
    local fsx = require("lib.fsx")
    pos = fsx.readJSON(turtlex.ARQUIVO, nil) or vazia()
    if type(pos) ~= "table" or type(pos.x) ~= "number" then pos = vazia() end
    if not PASSO[pos.olhando] then pos.olhando = "norte" end
    return pos
end

-- Grava AGORA, nao no fim da tarefa. Um passo dado e nao gravado e' uma turtle que renasce
-- achando que esta um bloco atras de onde esta - e o erro se acumula.
function turtlex.grava()
    local fsx = require("lib.fsx")
    local dir = fs.getDir(turtlex.ARQUIVO)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    return fsx.writeJSON(turtlex.ARQUIVO, turtlex.posicao())
end

function turtlex.define(x, y, z, olhando)
    local p = turtlex.posicao()
    p.x, p.y, p.z = x, y, z
    if olhando and PASSO[olhando] then p.olhando = olhando end
    p.certa = true
    turtlex.grava()
    return p
end

-- GPS quando houver quatro hosts por perto; conta propria como reserva.
--
-- O GPS diz ONDE, mas nao diz PARA ONDE se olha - isso nao existe na API. Descobrir exigiria
-- andar um bloco e comparar, e andar sem que ninguem pediu e' pior que nao saber.
function turtlex.sincroniza(prazo)
    if not turtle or not gps then return false, "sem gps" end
    local x, y, z = gps.locate(prazo or 2)
    if not x then return false, "gps nao respondeu (precisa de 4 hosts por perto)" end
    local p = turtlex.posicao()
    p.x, p.y, p.z, p.certa = x, y, z, true
    turtlex.grava()
    return true
end

-- ---------------------------------------------------------------- movimento

local function giraNaConta(p, quantos)
    local i = 1
    for k, nome in ipairs(turtlex.OLHARES) do if nome == p.olhando then i = k end end
    p.olhando = turtlex.OLHARES[((i - 1 + quantos) % 4) + 1]
end

-- Vira e ANOTA. Virar sem anotar deixa a posicao gravada certa e a direcao errada, que na
-- pratica e' pior: os passos seguintes vao todos para o lado errado.
function turtlex.vira(lado)
    -- O ARGUMENTO E' CONFERIDO ANTES do hardware, de proposito. Erro de digitacao em codigo
    -- de tarefa e' erro de programacao com ou sem turtle, e responder "nao sou uma turtle"
    -- para um "meio" manda quem le' investigar a coisa errada.
    if lado ~= "direita" and lado ~= "esquerda" then
        return false, "lado invalido: " .. tostring(lado)
    end
    if not turtle then return false, "nao sou uma turtle" end
    local ok
    if lado == "direita" then ok = turtle.turnRight() else ok = turtle.turnLeft() end
    if not ok then return false, "nao consegui virar" end
    giraNaConta(turtlex.posicao(), lado == "direita" and 1 or -1)
    turtlex.grava()
    return true
end

-- Traduz o "false, motivo" do CC para algo que se possa mostrar na tela sem traduzir de novo
-- em cada lugar que chama.
local function porque(motivo)
    local m = tostring(motivo or ""):lower()
    if m:find("fuel") then return "sem combustivel" end
    if m:find("obstruct") then return "tem bloco no caminho" end
    if m:find("block") then return "tem bloco no caminho" end
    -- "Movement failed" e' o que o CC devolve quando ha um mob no lugar. A mensagem crua nao
    -- diz isso, e "falhou" na tela nao ajuda ninguem.
    if m:find("movement failed") then return "tem algo vivo no caminho" end
    if m == "" then return "nao consegui andar" end
    return tostring(motivo)
end

local MOVER = {
    frente = { f = function() return turtle.forward() end, dx = 1, dy = 0 },
    tras   = { f = function() return turtle.back() end, dx = -1, dy = 0 },
    cima   = { f = function() return turtle.up() end, dx = 0, dy = 1 },
    baixo  = { f = function() return turtle.down() end, dx = 0, dy = -1 },
}

function turtlex.anda(direcao)
    -- Mesma regra do `vira`: argumento primeiro, hardware depois.
    local m = MOVER[direcao]
    if not m then return false, "direcao invalida: " .. tostring(direcao) end
    if not turtle then return false, "nao sou uma turtle" end
    local ok, motivo = m.f()
    if not ok then return false, porque(motivo) end
    local p = turtlex.posicao()
    if m.dy ~= 0 then
        p.y = p.y + m.dy
    else
        local d = PASSO[p.olhando]
        p.x, p.z = p.x + d.x * m.dx, p.z + d.z * m.dx
    end
    p.passos = (p.passos or 0) + 1
    turtlex.grava()
    return true
end

-- Descobre onde esta E para onde olha, andando um bloco e comparando.
--
-- E' o unico jeito: o GPS diz ONDE, e direcao nao existe na API do CC. Entao a turtle da' um
-- passo, olha de novo, e a diferenca revela para onde ela estava virada. No fim ela VOLTA -
-- descobrir nao pode mudar de lugar quem chamou.
--
-- Sem GPS nao ha o que fazer: nada no CC devolve coordenada do mundo sem uma constelacao de
-- quatro hosts. Ai o caminho e' a ancora a mao (`turtlex.define`), com a pessoa lendo o F3.
--
-- Tenta para FRENTE e, se houver bloco, para TRAS com o sinal invertido - senao uma turtle
-- encostada numa parede nunca conseguiria se localizar.
function turtlex.descobre(prazo)
    if not turtle then return false, "nao sou uma turtle" end
    if not gps then return false, "sem gps neste computador" end
    local x1, y1, z1 = gps.locate(prazo or 2)
    if not x1 then
        return false, "GPS nao respondeu: precisa de 4 computadores rodando 'gps host' por perto"
    end

    local sinal, ok, motivo = 1, turtle.forward()
    if not ok then sinal, ok, motivo = -1, turtle.back() end
    if not ok then return false, "nao consegui dar um passo: " .. porque(motivo) end

    local x2, _, z2 = gps.locate(prazo or 2)
    -- Volta ANTES de julgar o resultado: se o GPS falhar na segunda leitura, a turtle nao
    -- pode ficar parada um bloco fora do lugar por causa disso.
    if sinal == 1 then turtle.back() else turtle.forward() end
    if not x2 then return false, "o GPS respondeu antes do passo e nao depois" end

    local dx, dz = (x2 - x1) * sinal, (z2 - z1) * sinal
    local olhando
    for nome, d in pairs(PASSO) do
        if d.x == dx and d.z == dz then olhando = nome end
    end
    if not olhando then
        return false, string.format("o passo deu dx=%d dz=%d, que nao e' direcao nenhuma", dx, dz)
    end
    turtlex.define(x1, y1, z1, olhando)
    return true, olhando
end

-- ---------------------------------------------------------------- self-check

function turtlex.demo()
    -- Sem turtle, nada aqui pode levantar erro: a biblioteca vive num OS que roda em
    -- computador comum, e um `nil` mal tratado derrubaria o app de estado.
    if not turtle then
        assert(turtlex.existe() == false, "existe() mentiu num computador comum")
        assert(turtlex.combustivel() == nil, "combustivel devia ser nil sem turtle")
        assert(turtlex.capacidades() == nil, "capacidades devia ser nil sem turtle")
        assert(select(1, turtlex.anda("frente")) == false, "andar sem turtle devia dar false")
        assert(select(1, turtlex.vira("direita")) == false, "virar sem turtle devia dar false")
        assert(turtlex.abastece(100) == 0, "abastecer sem turtle nao move nada")
    end

    if not turtle then
        assert(select(1, turtlex.descobre()) == false, "descobrir sem turtle devia dar false")
    end

    -- A conta que traduz o passo em direcao. E' o coracao do `descobre`, e da' para exercitar
    -- sem turtle e sem GPS: dado um deslocamento, qual direcao produz esse deslocamento.
    local function direcaoDoPasso(dx, dz)
        for nome, d in pairs(PASSO) do if d.x == dx and d.z == dz then return nome end end
    end
    assert(direcaoDoPasso(0, -1) == "norte", "andar -z e' olhar para o norte")
    assert(direcaoDoPasso(1, 0) == "leste", "andar +x e' olhar para o leste")
    assert(direcaoDoPasso(0, 1) == "sul", "andar +z e' olhar para o sul")
    assert(direcaoDoPasso(-1, 0) == "oeste", "andar -x e' olhar para o oeste")
    assert(direcaoDoPasso(1, 1) == nil, "passo na diagonal nao e' direcao")
    assert(direcaoDoPasso(0, 0) == nil, "nao sair do lugar nao revela direcao")
    -- Andar para TRAS inverte o sinal, e e' o caso da turtle encostada na parede: o mesmo
    -- deslocamento fisico tem de dar a direcao OPOSTA.
    assert(direcaoDoPasso(0 * -1, -1 * -1) == "sul", "passo para tras precisa inverter o sinal")

    -- A conta da direcao e' pura, e e' onde um erro passa despercebido: uma volta inteira
    -- para a direita tem de voltar ao mesmo lugar, e a esquerda tem de desfazer a direita.
    local p = { olhando = "norte" }
    giraNaConta(p, 1) assert(p.olhando == "leste", "direita de norte e' leste, deu " .. p.olhando)
    giraNaConta(p, 1) assert(p.olhando == "sul", "duas a direita de norte e' sul")
    giraNaConta(p, 1) assert(p.olhando == "oeste", "tres a direita de norte e' oeste")
    giraNaConta(p, 1) assert(p.olhando == "norte", "quatro a direita volta ao norte")
    giraNaConta(p, -1) assert(p.olhando == "oeste", "esquerda de norte e' oeste")
    giraNaConta(p, -1) assert(p.olhando == "sul", "duas a esquerda de norte e' sul")

    -- Os quatro olhares tem passo, e os passos sao opostos dois a dois. Sem isto um erro de
    -- sinal so' apareceria com a turtle andando na direcao errada dentro do jogo.
    for _, nome in ipairs(turtlex.OLHARES) do
        assert(PASSO[nome], "olhar sem passo: " .. nome)
    end
    assert(PASSO.norte.z == -PASSO.sul.z and PASSO.norte.x == PASSO.sul.x, "norte e sul nao se opoem")
    assert(PASSO.leste.x == -PASSO.oeste.x and PASSO.leste.z == PASSO.oeste.z, "leste e oeste nao se opoem")

    -- O tradutor de motivo: e' o que a pessoa le na tela.
    assert(porque("Out of fuel") == "sem combustivel", "nao traduziu falta de combustivel")
    assert(porque("Movement obstructed") == "tem bloco no caminho", "nao traduziu bloco")
    assert(porque("Movement failed") == "tem algo vivo no caminho", "nao traduziu mob")
    assert(porque(nil) == "nao consegui andar", "motivo vazio precisa de alguma frase")
    assert(porque("coisa estranha") == "coisa estranha", "motivo desconhecido tem de passar inteiro")

    -- Direcao e lado invalidos nao podem passar calados: erro de digitacao em codigo de
    -- tarefa viraria uma turtle parada sem ninguem saber por que.
    assert(select(2, turtlex.anda("diagonal")):find("invalida"), "direcao invalida devia reclamar")
    assert(select(2, turtlex.vira("meio")):find("invalido"), "lado invalido devia reclamar")

    -- Disco: a posicao volta igual, e posicao estragada vira posicao zerada em vez de erro.
    local guardado = turtlex.ARQUIVO
    turtlex.ARQUIVO = "/tmp_turtle_teste.json"
    pos = nil
    local p2 = turtlex.posicao()
    assert(p2.x == 0 and p2.olhando == "norte" and p2.certa == false,
        "sem arquivo, a posicao comeca zerada e ASSUMIDA, nao certa")
    p2.x, p2.y, p2.z, p2.olhando, p2.certa = 10, 64, -3, "oeste", true
    assert(turtlex.grava(), "nao consegui gravar a posicao")
    pos = nil
    local p3 = turtlex.posicao()
    assert(p3.x == 10 and p3.y == 64 and p3.z == -3, "a posicao nao voltou do disco")
    assert(p3.olhando == "oeste" and p3.certa == true, "olhar ou certeza se perderam no disco")

    local h = fs.open(turtlex.ARQUIVO, "w") h.write("{isto nao e json") h.close()
    pos = nil
    assert(turtlex.posicao().x == 0, "json estragado devia virar posicao zerada")
    -- Olhar invalido no disco tambem nao pode derrubar: o passo seguinte indexaria nil.
    local h2 = fs.open(turtlex.ARQUIVO, "w")
    h2.write('{"x":1,"y":2,"z":3,"olhando":"diagonal"}') h2.close()
    pos = nil
    assert(turtlex.posicao().olhando == "norte", "olhar invalido no disco devia cair no norte")
    fs.delete(turtlex.ARQUIVO)
    turtlex.ARQUIVO = guardado
    pos = nil

    return true
end

return turtlex
