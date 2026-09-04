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
function httpx.requestAsync(url, body, headers)
    if not http then return nil, "API http desativada no servidor" end
    http.request(url, body, headers)
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

function httpx.allowed(url)
    if not http then return false, "API http desativada no servidor" end
    return http.checkURL(url)
end

return httpx
