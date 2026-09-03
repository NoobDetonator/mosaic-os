-- Motor de expressoes da calculadora: tokenizador, analisador descendente recursivo e
-- avaliador. Substitui o `load("return " .. texto)` que a calculadora usava.
--
--   local expr = mosaic.lib("expr")
--   local ctx = { vars = {}, deg = false }
--   local v, err, col = expr.eval("2(3+4)!", ctx)
--
-- Por que nao continuar no `load`: ele nao faz multiplicacao implicita (`2pi`), nao tem
-- fatorial, nao tem modo graus, nao aceita `x = 5` como conta, e o erro que ele devolve fala
-- de sintaxe de Lua, nao da conta que a pessoa escreveu. Aqui o erro vem com a coluna.
--
-- Regras de precedencia, da mais fraca para a mais forte:
--   =            atribuicao, so no topo
--   + -
--   * / %        e a multiplicacao implicita, no mesmo nivel (entao 1/2x e' (1/2)*x)
--   - unario
--   ^            associa a direita, e -2^2 e' -(2^2)
--   !            posfixo
local expr = {}

-- ---------------------------------------------------------------- constantes e funcoes

expr.constants = { pi = math.pi, e = math.exp(1) }

local function toRad(ctx, a) return ctx.deg and a * math.pi / 180 or a end
local function fromRad(ctx, a) return ctx.deg and a * 180 / math.pi or a end

local function checkInt(a, quem)
    if a ~= math.floor(a) then error(quem .. " so aceita numero inteiro", 0) end
    return a
end

-- n = quantidade de argumentos; -1 e' variadico. `f` recebe o contexto na frente porque as
-- funcoes de angulo precisam saber se estamos em graus.
expr.functions = {
    sqrt  = { n = 1, help = "raiz quadrada", f = function(_, a)
        if a < 0 then error("raiz de numero negativo", 0) end
        return math.sqrt(a)
    end },
    abs   = { n = 1, help = "valor absoluto", f = function(_, a) return math.abs(a) end },
    floor = { n = 1, help = "arredonda para baixo", f = function(_, a) return math.floor(a) end },
    ceil  = { n = 1, help = "arredonda para cima", f = function(_, a) return math.ceil(a) end },
    round = { n = -1, help = "arredonda (casas opcional)", f = function(_, a, casas)
        local m = 10 ^ (casas or 0)
        return math.floor(a * m + 0.5) / m
    end },
    min   = { n = -1, help = "menor valor", f = function(_, ...) return math.min(...) end },
    max   = { n = -1, help = "maior valor", f = function(_, ...) return math.max(...) end },
    sin   = { n = 1, help = "seno", f = function(c, a) return math.sin(toRad(c, a)) end },
    cos   = { n = 1, help = "cosseno", f = function(c, a) return math.cos(toRad(c, a)) end },
    tan   = { n = 1, help = "tangente", f = function(c, a) return math.tan(toRad(c, a)) end },
    asin  = { n = 1, help = "arco seno", f = function(c, a)
        if a < -1 or a > 1 then error("asin so aceita de -1 a 1", 0) end
        return fromRad(c, math.asin(a))
    end },
    acos  = { n = 1, help = "arco cosseno", f = function(c, a)
        if a < -1 or a > 1 then error("acos so aceita de -1 a 1", 0) end
        return fromRad(c, math.acos(a))
    end },
    atan  = { n = -1, help = "arco tangente (y, x opcional)", f = function(c, a, b)
        -- math.atan2 saiu no Lua 5.4; la o proprio math.atan aceita os dois argumentos.
        if b then return fromRad(c, (math.atan2 or math.atan)(a, b)) end
        return fromRad(c, math.atan(a))
    end },
    ln    = { n = 1, help = "logaritmo natural", f = function(_, a)
        if a <= 0 then error("logaritmo de numero nao positivo", 0) end
        return math.log(a)
    end },
    log   = { n = -1, help = "logaritmo (base 10, ou log(x, base))", f = function(_, a, base)
        if a <= 0 then error("logaritmo de numero nao positivo", 0) end
        return math.log(a) / math.log(base or 10)
    end },
    exp   = { n = 1, help = "e elevado a x", f = function(_, a) return math.exp(a) end },
    hypot = { n = 2, help = "hipotenusa", f = function(_, a, b) return math.sqrt(a * a + b * b) end },
    gcd   = { n = 2, help = "maximo divisor comum", f = function(_, a, b)
        a, b = math.abs(checkInt(a, "gcd")), math.abs(checkInt(b, "gcd"))
        while b > 0 do a, b = b, a % b end
        return a
    end },
    lcm   = { n = 2, help = "minimo multiplo comum", f = function(_, a, b)
        a, b = math.abs(checkInt(a, "lcm")), math.abs(checkInt(b, "lcm"))
        if a == 0 or b == 0 then return 0 end
        local x, y = a, b
        while y > 0 do x, y = y, x % y end
        return a / x * b
    end },
}

-- ---------------------------------------------------------------- tokenizador

local SYMBOLS = { ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true,
    ["^"] = true, ["!"] = true, ["("] = true, [")"] = true, [","] = true, ["="] = true }

-- Devolve a lista de tokens, ou nil, mensagem, coluna.
local function tokenize(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") or (c == "." and s:sub(i + 1, i + 1):match("%d")) then
            local j = i
            while s:sub(j, j):match("[%d.]") do j = j + 1 end
            -- Notacao cientifica so quando vem digito depois do e: "2e3" e' 2000, mas
            -- "2e" e' 2 vezes a constante de Euler.
            local ec = s:sub(j, j)
            if ec == "e" or ec == "E" then
                local k = j + 1
                if s:sub(k, k) == "+" or s:sub(k, k) == "-" then k = k + 1 end
                if s:sub(k, k):match("%d") then
                    while s:sub(k, k):match("%d") do k = k + 1 end
                    j = k
                end
            end
            local texto = s:sub(i, j - 1)
            local v = tonumber(texto)
            if not v then return nil, "numero invalido: " .. texto, i end
            out[#out + 1] = { kind = "num", value = v, col = i }
            i = j
        elseif c:match("[%a_]") then
            local j = i
            while s:sub(j, j):match("[%w_]") do j = j + 1 end
            out[#out + 1] = { kind = "name", value = s:sub(i, j - 1), col = i }
            i = j
        elseif SYMBOLS[c] then
            out[#out + 1] = { kind = c, col = i }
            i = i + 1
        else
            return nil, "nao entendi o caractere '" .. c .. "'", i
        end
    end
    out[#out + 1] = { kind = "eof", col = n + 1 }
    return out
end

-- ---------------------------------------------------------------- analisador

local Parser = {}
Parser.__index = Parser

local function fail(p, msg, col)
    error({ expr = true, msg = msg, col = col or p:peek().col }, 0)
end

function Parser:peek(off) return self.toks[self.i + (off or 0)] end
function Parser:next() local t = self.toks[self.i] self.i = self.i + 1 return t end
function Parser:accept(kind)
    if self:peek().kind == kind then return self:next() end
    return nil
end
function Parser:expect(kind, oque)
    local t = self:accept(kind)
    if not t then fail(self, "esperava " .. (oque or kind)) end
    return t
end

local function factorial(a, col, p)
    if a < 0 or a ~= math.floor(a) then fail(p, "fatorial so vale para inteiro nao negativo", col) end
    if a > 170 then fail(p, "fatorial grande demais", col) end
    local r = 1
    for k = 2, a do r = r * k end
    return r
end

function Parser:primary()
    local t = self:peek()
    if t.kind == "num" then
        self:next()
        return t.value
    elseif t.kind == "(" then
        self:next()
        local v = self:addsub()
        self:expect(")", "um ) para fechar")
        return v
    elseif t.kind == "name" then
        self:next()
        local fn = expr.functions[t.value]
        if fn and self:peek().kind == "(" then
            self:next()
            local args = {}
            if self:peek().kind ~= ")" then
                repeat args[#args + 1] = self:addsub() until not self:accept(",")
            end
            self:expect(")", "um ) para fechar " .. t.value)
            if fn.n >= 0 and #args ~= fn.n then
                fail(self, t.value .. " espera " .. fn.n .. " argumento(s), veio " .. #args, t.col)
            end
            if fn.n < 0 and #args == 0 then
                fail(self, t.value .. " precisa de ao menos um argumento", t.col)
            end
            local ok, v = pcall(fn.f, self.ctx, table.unpack(args))
            if not ok then fail(self, tostring(v), t.col) end
            return v
        end
        if fn then fail(self, t.value .. " e uma funcao, use " .. t.value .. "(...)", t.col) end
        if expr.constants[t.value] then return expr.constants[t.value] end
        local v = self.ctx.vars and self.ctx.vars[t.value]
        if v == nil then fail(self, "nao conheco '" .. t.value .. "'", t.col) end
        return v
    elseif t.kind == "eof" then
        fail(self, "a conta terminou antes da hora")
    end
    fail(self, "nao esperava '" .. t.kind .. "' aqui")
end

function Parser:postfix()
    local col = self:peek().col
    local v = self:primary()
    while self:accept("!") do v = factorial(v, col, self) end
    return v
end

function Parser:power()
    local base = self:postfix()
    if self:accept("^") then
        local e = self:unary()          -- associa a direita, e aceita 2^-1
        return base ^ e
    end
    return base
end

function Parser:unary()
    if self:accept("-") then return -self:unary() end
    if self:accept("+") then return self:unary() end
    return self:power()
end

-- Um token que pode comecar um valor novo grudado no anterior: 2pi, 2(3), (1)(2).
local function startsValue(t)
    return t.kind == "num" or t.kind == "name" or t.kind == "("
end

function Parser:muldiv()
    local v = self:unary()
    while true do
        local t = self:peek()
        if t.kind == "*" then self:next() v = v * self:unary()
        elseif t.kind == "/" then
            self:next()
            local d = self:unary()
            if d == 0 then fail(self, "divisao por zero", t.col) end
            v = v / d
        elseif t.kind == "%" then
            self:next()
            local d = self:unary()
            if d == 0 then fail(self, "resto de divisao por zero", t.col) end
            v = v % d
        elseif startsValue(t) then
            v = v * self:unary()        -- multiplicacao implicita
        else
            return v
        end
    end
end

function Parser:addsub()
    local v = self:muldiv()
    while true do
        if self:accept("+") then v = v + self:muldiv()
        elseif self:accept("-") then v = v - self:muldiv()
        else return v end
    end
end

-- ---------------------------------------------------------------- porta de entrada

-- Roda o analisador sobre uma lista de tokens ja pronta. Separado do eval porque o grafico
-- avalia a mesma expressao uma vez por coluna da tela: reanalisar o texto a cada ponto
-- custaria o dobro do desenho inteiro.
local function run(toks, ctx, inicio)
    local p = setmetatable({ toks = toks, i = inicio or 1, ctx = ctx }, Parser)
    local ok, v = pcall(function()
        local r = p:addsub()
        if p:peek().kind ~= "eof" then fail(p, "sobrou '" .. p:peek().kind .. "' no fim") end
        return r
    end)
    if not ok then
        if type(v) == "table" and v.expr then return nil, v.msg, v.col end
        return nil, tostring(v), 1
    end
    if type(v) ~= "number" then return nil, "isso nao deu um numero", 1 end
    if v ~= v then return nil, "resultado indefinido", 1 end
    return v
end

-- Prepara a expressao uma vez e devolve uma funcao que so' avalia. Serve para o grafico.
-- Nao aceita atribuicao: quem desenha uma curva nao muda variavel do sistema.
function expr.compile(texto)
    local toks, err, col = tokenize(tostring(texto or ""))
    if not toks then return nil, err, col end
    if toks[1].kind == "eof" then return nil, "conta vazia", 1 end
    return function(ctx)
        ctx = ctx or {}
        ctx.vars = ctx.vars or {}
        return run(toks, ctx)
    end
end

-- Devolve valor, ou nil, mensagem, coluna. O quarto retorno e' o nome da variavel quando a
-- conta era uma atribuicao.
function expr.eval(texto, ctx)
    ctx = ctx or {}
    ctx.vars = ctx.vars or {}
    texto = tostring(texto or "")
    if texto:match("^%s*$") then return nil, "conta vazia", 1 end

    local toks, err, col = tokenize(texto)
    if not toks then return nil, err, col end

    -- Atribuicao: so' vale quando a conta inteira e' `nome = ...`.
    local nome, inicio = nil, 1
    if toks[1].kind == "name" and toks[2] and toks[2].kind == "=" then
        nome = toks[1].value
        if expr.functions[nome] or expr.constants[nome] then
            return nil, "'" .. nome .. "' ja e do sistema, escolha outro nome", toks[1].col
        end
        inicio = 3
    end

    local v, msg, c = run(toks, ctx, inicio)
    if v == nil then return nil, msg, c end
    if nome then ctx.vars[nome] = v end
    return v, nil, nil, nome
end

-- Notacao cientifica na mao. O `%g` do C mudaria para exponencial sozinho, mas o fengari
-- (o emulador em JS) devolve o numero inteiro por extenso no lugar: sao tres implementacoes
-- de Lua diferentes rodando este codigo, entao a decisao e nossa e nao do string.format.
local function sci(v)
    local expo = math.floor(math.log(math.abs(v)) / math.log(10))
    local mant = v / (10 ^ expo)
    if math.abs(mant) >= 10 then mant, expo = mant / 10, expo + 1 end
    if math.abs(mant) < 1 then mant, expo = mant * 10, expo - 1 end
    local m = string.format("%.6f", mant)
    m = (m:gsub("0+$", ""))
    m = (m:gsub("%.$", ""))
    return m .. "e" .. expo
end

-- Numero para texto, do jeito que se le numa calculadora.
function expr.format(v)
    if type(v) ~= "number" then return tostring(v) end
    if v ~= v then return "indefinido" end
    if v == math.huge then return "infinito" end
    if v == -math.huge then return "-infinito" end
    local a = math.abs(v)
    -- %d quebra com fracionario no Lua 5.3 do CraftOS-PC; %.0f nunca quebra.
    if v == math.floor(v) and a < 1e15 then return string.format("%.0f", v) end
    if a ~= 0 and (a >= 1e15 or a < 1e-5) then return sci(v) end
    local s = string.format("%.10f", v)
    s = (s:gsub("0+$", ""))
    s = (s:gsub("%.$", ""))
    return s
end

-- Nomes das funcoes em ordem, para o menu do app.
function expr.functionNames()
    local out = {}
    for nome in pairs(expr.functions) do out[#out + 1] = nome end
    table.sort(out)
    return out
end

function expr.demo()
    local ctx = { vars = {}, deg = false }
    local function v(s)
        local r, err, col = expr.eval(s, ctx)
        assert(r ~= nil, s .. " deveria dar numero, deu erro: " .. tostring(err) .. " col " .. tostring(col))
        return r
    end
    local function perto(s, esperado)
        local r = v(s)
        assert(math.abs(r - esperado) < 1e-9, s .. " deu " .. tostring(r) .. ", esperava " .. tostring(esperado))
    end
    local function recusa(s)
        local r, err = expr.eval(s, ctx)
        assert(r == nil and err, s .. " deveria ser recusado")
    end

    -- basico e precedencia
    perto("2+2", 4)
    perto("2+3*4", 14)
    perto("(2+3)*4", 20)
    perto("10/4", 2.5)
    perto("10%3", 1)
    perto("2^3^2", 512)            -- associa a direita
    perto("-2^2", -4)              -- o menos vem depois da potencia
    perto("2^-1", 0.5)
    perto("-(3)", -3)
    perto("--3", 3)

    -- multiplicacao implicita
    perto("2(3+4)", 14)
    perto("(1+1)(2+2)", 8)
    perto("3pi", 3 * math.pi)
    perto("1/2pi", 0.5 * math.pi)  -- mesmo nivel do *, entao esquerda para direita

    -- fatorial
    perto("5!", 120)
    perto("0!", 1)
    perto("3!+1", 7)
    recusa("(-1)!")
    recusa("1.5!")

    -- funcoes
    perto("sqrt(16)", 4)
    perto("max(1,7,3)", 7)
    perto("min(1,7,3)", 1)
    perto("round(2.567, 2)", 2.57)
    perto("round(2.5)", 3)
    perto("gcd(12, 18)", 6)
    perto("lcm(4, 6)", 12)
    perto("log(1000)", 3)
    perto("log(8, 2)", 3)
    perto("ln(exp(1))", 1)
    perto("hypot(3,4)", 5)
    perto("abs(-3)+floor(1.9)+ceil(1.1)", 3 + 1 + 2)

    -- graus contra radianos
    perto("sin(0)", 0)
    ctx.deg = true
    perto("sin(90)", 1)
    perto("cos(180)", -1)
    perto("asin(1)", 90)
    ctx.deg = false
    perto("sin(pi/2)", 1)

    -- notacao cientifica, e o `e` sozinho continuando constante
    perto("2e3", 2000)
    perto("1.5e-2", 0.015)
    perto("2e", 2 * math.exp(1))

    -- variaveis
    local r, err, _, nome = expr.eval("x = 12", ctx)
    assert(r == 12 and nome == "x", "atribuicao deveria devolver o valor e o nome")
    assert(err == nil, "atribuicao nao deveria dar erro")
    perto("x*3", 36)
    ctx.vars.ans = 36
    perto("ans+4", 40)
    recusa("pi = 3")               -- nao deixa remendar o sistema
    recusa("sqrt = 2")

    -- erros que precisam ser recusados, com coluna
    recusa("")
    recusa("2+")
    recusa("(2")
    recusa("2)")
    recusa("1/0")
    recusa("5%0")
    recusa("naoexiste")
    recusa("sqrt(-1)")
    recusa("ln(0)")
    recusa("sqrt")                 -- funcao sem parenteses
    recusa("sqrt(1,2)")            -- numero errado de argumentos
    recusa("2 $ 3")
    local _, msg, col = expr.eval("2 + naoexiste", ctx)
    assert(col == 5, "a coluna do erro deveria ser 5, veio " .. tostring(col))
    assert(msg:find("naoexiste"), "a mensagem deveria citar o nome desconhecido")

    -- compile avalia varias vezes sem reanalisar o texto
    local fn = assert(expr.compile("x^2 + 1"))
    local c2 = { vars = {}, deg = false }
    c2.vars.x = 3
    assert(fn(c2) == 10, "compile deveria dar 10 para x = 3")
    c2.vars.x = 0
    assert(fn(c2) == 1, "compile deveria dar 1 para x = 0")
    assert(select(1, fn({ vars = {} })) == nil, "sem a variavel, compile tem de recusar")
    assert(expr.compile("2 +") ~= nil, "erro de sintaxe so aparece na hora de avaliar")
    assert(select(1, expr.compile("2 +")({ vars = {} })) == nil, "conta quebrada deveria falhar")
    assert(expr.compile("") == nil, "texto vazio nao compila")

    -- formatacao
    assert(expr.format(4) == "4", "inteiro nao devia ganhar casa decimal")
    assert(expr.format(2.5) == "2.5", "fracionario errado: " .. expr.format(2.5))
    assert(expr.format(1 / 0) == "infinito", "infinito errado")
    assert(expr.format(1e20) == "1e20", "grande saiu como [" .. expr.format(1e20) .. "]")
    assert(expr.format(0.0000001) == "1e-7", "pequeno saiu como [" .. expr.format(0.0000001) .. "]")
    assert(expr.format(1/3):sub(1, 6) == "0.3333", "fracao saiu como [" .. expr.format(1/3) .. "]")
    assert(expr.format(0) == "0", "zero errado")
    assert(expr.format(-2.5) == "-2.5", "negativo errado")

    return true
end

return expr
