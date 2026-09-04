-- HTTP pratico. `local httpx = mosaic.lib("httpx")`
-- Tudo aqui usa argumentos posicionais. O que e' 1.105 (novo demais para o nosso alvo) e' o
-- campo `timeout` e a forma tabela do websocket; a forma tabela do get/post/request e' bem
-- mais velha (1.80pr1.6) e seria permitida. Posicional em tudo, para nao ter que lembrar.
local httpx = {}

local function readBody(res)
    local body = res.readAll()
    local code = res.getResponseCode()
    local headers = res.getResponseHeaders()
    res.close()
    return body, code, headers
end

function httpx.get(url, headers)
    if not http then return nil, "API http desativada no servidor" end
    local res, err = http.get(url, headers)
    if not res then return nil, err or "falha na requisicao" end
    return readBody(res)
end

function httpx.post(url, body, headers)
    if not http then return nil, "API http desativada no servidor" end
    local res, err = http.post(url, body, headers)
    if not res then return nil, err or "falha na requisicao" end
    return readBody(res)
end

function httpx.getJSON(url, headers)
    local body, code = httpx.get(url, headers)
    if not body then return nil, code end
    local ok, value = pcall(textutils.unserialiseJSON, body)
    if not ok or value == nil then return nil, "resposta nao e JSON valido" end
    return value, code
end

function httpx.postJSON(url, tbl, headers)
    headers = headers or {}
    headers["Content-Type"] = headers["Content-Type"] or "application/json"
    local ok, body = pcall(textutils.serialiseJSON, tbl)
    if not ok then return nil, "nao consegui converter para JSON: " .. tostring(body) end
    local res, code = httpx.post(url, body, headers)
    if not res then return nil, code end
    local ok2, value = pcall(textutils.unserialiseJSON, res)
    if not ok2 or value == nil then return res, code end
    return value, code
end

-- Baixa para um arquivo. onProgress(bytes) e opcional.
function httpx.download(url, path, headers)
    if not http then return false, "API http desativada no servidor" end
    local res, err = http.get(url, headers, true)
    if not res then return false, err or "falha na requisicao" end
    local data = res.readAll()
    res.close()
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "wb")
    if not h then return false, "nao consegui escrever " .. path end
    h.write(data)
    h.close()
    return true, #data
end

-- Versao assincrona: dispara e devolve um "handle" que voce consulta nos eventos
-- http_success / http_failure. Util dentro de apps que nao podem travar.
-- `binary` importa: no CC:T do nosso alvo o modo texto passa o corpo por UTF-8, e byte de
-- audio nao sobrevive a isso. Quem baixa DFPWM tem que pedir binario.
function httpx.requestAsync(url, body, headers, binary)
    if not http then return nil, "API http desativada no servidor" end
    http.request(url, body, headers, binary and true or false)
    return url
end

-- Espera uma resposta de `url` disparada por requestAsync, com timeout.
function httpx.await(url, timeout)
    local timer = os.startTimer(timeout or 15)
    while true do
        local ev, a, b = os.pullEvent()
        if ev == "http_success" and a == url then
            os.cancelTimer(timer)
            return readBody(b)
        elseif ev == "http_failure" and a == url then
            os.cancelTimer(timer)
            return nil, b or "falha"
        elseif ev == "timer" and a == timer then
            return nil, "tempo esgotado"
        end
    end
end

-- Baixa em modo binario e devolve a string, sem passar por arquivo.
--
-- Existe separado do `get` porque nas versoes antigas do CC o modo texto passa o corpo por
-- UTF-8, e byte de audio nao sobrevive a isso. E existe separado do `download` porque um
-- computador do jogo tem 1 MB de disco: musica nao cabe, tem que ser tocada de passagem.
function httpx.getBinary(url, headers)
    if not http then return nil, "API http desativada no servidor" end
    local res, err = http.get(url, headers, true)
    if not res then return nil, err or "falha na requisicao" end
    local data = res.readAll()
    local code = res.getResponseCode()
    res.close()
    return data, code
end

-- ---------------------------------------------------------------- relay

-- O endereco HTTP do relay, deduzido do websocket que ja esta configurado.
--
-- Guardar duas configuracoes (uma ws, uma http) daria duas chances de errar; e o app
-- Configuracoes ja fazia essa conversao na mao, so' que escondida dentro do botao Testar.
--
-- Devolve nil quando o relay nao esta configurado - quem chama decide se degrada ou avisa.
function httpx.gateway()
    if not settings then return nil end
    local ws = settings.get("mosaic.relay.url")
    if not ws or ws == "" then return nil end
    local base = ws:gsub("^ws", "http"):gsub("/ws/computer$", "")
    return {
        url = base,
        token = settings.get("mosaic.relay.token"),
        headers = { ["Authorization"] = "Bearer " .. tostring(settings.get("mosaic.relay.token") or "") },
    }
end

-- Monta a URL de uma rota do relay com os parametros ja escapados.
function httpx.gatewayUrl(rota, params)
    local g = httpx.gateway()
    if not g then return nil, "relay nao configurado" end
    local partes = {}
    for k, v in pairs(params or {}) do
        partes[#partes + 1] = k .. "=" .. textutils.urlEncode(tostring(v))
    end
    local q = #partes > 0 and ("?" .. table.concat(partes, "&")) or ""
    return g.url .. rota .. q, g.headers
end

-- Pede uma rota do relay e devolve a tabela ja decodificada.
function httpx.gatewayJSON(rota, params)
    local url, headers = httpx.gatewayUrl(rota, params)
    if not url then return nil, headers end
    local doc, code = httpx.getJSON(url, headers)
    if not doc then return nil, code end
    -- O relay responde 502 com { erro = "..." } quando o site do outro lado falhou: isso e'
    -- resposta valida, nao erro de rede, e a mensagem e' para a pessoa ler.
    if type(doc) == "table" and doc.erro then return nil, doc.erro end
    return doc
end

function httpx.allowed(url)
    if not http then return false, "API http desativada no servidor" end
    return http.checkURL(url)
end

function httpx.demo()
    -- Sem rede, tudo tem que devolver erro em vez de estourar.
    if not http then
        assert(httpx.get("http://x") == nil, "get sem http deveria devolver nil")
        assert(httpx.getBinary("http://x") == nil, "getBinary sem http deveria devolver nil")
    end

    -- A conversao de ws:// para http:// e o motivo de existir do gateway(): uma configuracao
    -- so', em vez de duas que podem discordar.
    local antes = settings and settings.get("mosaic.relay.url")
    if settings then
        settings.set("mosaic.relay.url", "ws://1.2.3.4:8765/ws/computer")
        settings.set("mosaic.relay.token", "abc")
        local g = httpx.gateway()
        assert(g and g.url == "http://1.2.3.4:8765", "gateway montou a URL errada: " .. tostring(g and g.url))
        assert(g.headers["Authorization"] == "Bearer abc", "gateway nao levou o token")

        local url = httpx.gatewayUrl("/api/busca", { q = "a b" })
        assert(url == "http://1.2.3.4:8765/api/busca?q=a+b" or url == "http://1.2.3.4:8765/api/busca?q=a%20b",
            "parametro nao foi escapado: " .. tostring(url))

        settings.set("mosaic.relay.url", "")
        assert(httpx.gateway() == nil, "sem relay configurado, gateway tem que dar nil")
        if antes then settings.set("mosaic.relay.url", antes) end
    end
    return true
end

return httpx
