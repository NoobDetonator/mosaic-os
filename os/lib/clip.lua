-- Area de transferencia de arquivos (recortar / copiar / colar).
--
-- O mosaic.require guarda uma copia so' de cada modulo, entao duas janelas do Arquivos
-- enxergam o mesmo recorte: e' isso que faz "recortar aqui, colar ali" funcionar entre janelas.
local fsx = require("lib.fsx")

local clip = {}
clip.mode = nil     -- "copy" | "cut" | nil
clip.paths = {}

-- Caminho na forma do fs.combine: sem barra na frente, sem barra dupla.
local function norm(p) return fs.combine(tostring(p or ""), "") end

function clip.set(mode, paths)
    if type(paths) == "string" then paths = { paths } end
    clip.mode = (#(paths or {}) > 0) and mode or nil
    clip.paths = {}
    for _, p in ipairs(paths or {}) do clip.paths[#clip.paths + 1] = norm(p) end
end

function clip.copy(paths) clip.set("copy", paths) end
function clip.cut(paths) clip.set("cut", paths) end
function clip.clear() clip.mode = nil clip.paths = {} end
function clip.has() return clip.mode ~= nil and #clip.paths > 0 end

function clip.describe()
    if not clip.has() then return "" end
    local verbo = clip.mode == "cut" and "recortado" or "copiado"
    if #clip.paths == 1 then return fs.getName(clip.paths[1]) .. " " .. verbo end
    return #clip.paths .. " itens " .. verbo
end

-- Cola em `destDir`. Devolve true, ou false e uma mensagem pronta para o msgbox.
-- `progress(i, total, nome)` e' opcional (o ui.busy do Arquivos entra por aqui).
--
-- Falha no meio para: o que ja foi movido fica movido. E' o comportamento honesto sem
-- transacao, e a mensagem diz em qual arquivo parou.
function clip.paste(destDir, progress)
    if not clip.has() then return false, "Nao ha nada na area de transferencia." end
    local dest = norm(destDir)
    if not fs.isDir(dest) and dest ~= "" then return false, "Destino nao e uma pasta." end
    if fs.isReadOnly(dest) then return false, "Essa pasta e somente leitura." end

    local moving = clip.mode == "cut"
    local total = #clip.paths
    for i, src in ipairs(clip.paths) do
        if not fs.exists(src) then
            clip.clear()
            return false, "O original sumiu: /" .. src
        end
        -- Colar uma pasta dentro dela mesma faria o fs entrar em recursao infinita.
        if fs.isDir(src) and (dest == src or dest:sub(1, #src + 1) == src .. "/") then
            return false, "Nao da para colar uma pasta dentro dela mesma."
        end
        local target = fs.combine(dest, fs.getName(src))
        local skip = false
        if target == src then
            -- Recortar e colar no mesmo lugar nao faz nada; copiar vira "nome (2)".
            if moving then skip = true else target = norm(fsx.uniqueName("/" .. target)) end
        elseif fs.exists(target) then
            target = norm(fsx.uniqueName("/" .. target))
        end
        if not skip then
            if progress then progress(i, total, fs.getName(src)) end
            local ok, err = pcall(moving and fs.move or fs.copy, src, target)
            if not ok then
                if moving then clip.clear() end
                return false, tostring(err)
            end
        end
    end
    if moving then clip.clear() end
    return true
end

function clip.demo()
    local root = "/os/var/clipdemo"
    if fs.exists(root) then fs.delete(root) end
    fs.makeDir(root .. "/a")
    fs.makeDir(root .. "/b")
    fsx.write(root .. "/a/nota.txt", "oi")

    clip.clear()
    assert(not clip.has(), "area de transferencia deveria comecar vazia")
    local ok, err = clip.paste(root .. "/b")
    assert(not ok and err, "colar com a area vazia deveria falhar sem quebrar")

    clip.cut(root .. "/a/nota.txt")
    assert(clip.has() and clip.mode == "cut", "o recorte nao ficou guardado")
    assert(clip.paste(root .. "/b"), "colar deveria ter dado certo")
    assert(not fs.exists(root .. "/a/nota.txt"), "recortar deveria mover, nao copiar")
    assert(fs.exists(root .. "/b/nota.txt"), "o arquivo nao chegou no destino")
    assert(not clip.has(), "depois de colar, o recorte tem de sair da area")

    clip.copy(root .. "/b/nota.txt")
    assert(clip.paste(root .. "/b"), "copiar na mesma pasta deveria dar certo")
    assert(fs.exists(root .. "/b/nota (2).txt"), "conflito de nome deveria virar 'nota (2)'")
    assert(clip.has(), "copiar continua valendo depois de colar")

    fs.makeDir(root .. "/b/dentro")
    clip.cut(root .. "/b")
    local ok2, err2 = clip.paste(root .. "/b/dentro")
    assert(not ok2 and err2, "colar uma pasta dentro dela mesma tem de ser recusado")
    assert(fs.exists(root .. "/b"), "a recusa nao pode ter mexido em nada")

    clip.clear()
    fs.delete(root)
    return true
end

return clip
