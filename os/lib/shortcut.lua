-- Atalhos (.lnk). Um atalho e uma tabela Lua serializada, nada mais:
--
--   { name = "Arquivos",  app = "files" }                                -- id do apps/registry
--   { name = "Programas", path = "/home/programas", icon = "folder" }    -- pasta
--   { name = "Rodar",     path = "/apps/teste.lua", args = { "-v" } }    -- programa com argumentos
--
-- Esta biblioteca so' le, escreve e da nome: quem resolve `app` para um caminho e' o
-- apps/registry, senao os dois se exigiriam em circulo.
local fsx = require("lib.fsx")

local shortcut = {}
shortcut.EXT = ".lnk"

-- Icone por extensao. O que nao estiver aqui cai em "file"; se o .nfp do icone nao existir,
-- o lib/icons ja cai sozinho no icone generico.
local EXT_ICON = {
    lua = "lua", nfp = "image", nft = "image", bimg = "image",
    txt = "file", md = "file", json = "file", cfg = "file", log = "file",
}

function shortcut.isLink(path)
    return type(path) == "string" and path:lower():sub(-#shortcut.EXT) == shortcut.EXT
end

function shortcut.read(path)
    if not shortcut.isLink(path) then return nil end
    local t = fsx.readTable(path, nil)
    if type(t) ~= "table" then return nil end
    if not t.app and not t.path then return nil end
    return t
end

function shortcut.write(path, spec)
    return fsx.writeTable(path, spec)
end

-- Tira o que nao pode virar nome de arquivo. Sem acento de proposito: a fonte do CC e' byte a
-- byte, e um nome em UTF-8 aparece como lixo na tela.
function shortcut.sanitize(name)
    -- Classe entre colchetes longos: escapar barra invertida dentro de aspas e' pedir bug.
    name = tostring(name or "Atalho"):gsub([=[[/\:*?"<>|]]=], ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Atalho" end
    return name
end

-- Cria o .lnk em `dir` sem sobrescrever nada. Devolve o caminho ou nil, erro.
function shortcut.create(dir, spec)
    if not fs.isDir(dir) then return nil, "Pasta nao existe: /" .. tostring(dir) end
    local path = fsx.uniqueName("/" .. fs.combine(dir, shortcut.sanitize(spec.name) .. shortcut.EXT))
    local ok, err = shortcut.write(path, spec)
    if not ok then return nil, err end
    return path
end

-- Nome mostrado na tela: o do atalho, ou o do arquivo sem a extensao .lnk.
function shortcut.displayName(path, spec)
    if spec and spec.name then return spec.name end
    local name = fs.getName(path)
    if shortcut.isLink(name) then return name:sub(1, #name - #shortcut.EXT) end
    return name
end

-- Nome do icone para uma entrada. `spec` so' vem preenchido quando a entrada e' um atalho.
function shortcut.iconFor(path, isDir, spec)
    if spec then
        if spec.icon then return spec.icon end
        if spec.app then return (tostring(spec.app):gsub("^user:", "")) end
        if spec.path then return shortcut.iconFor(spec.path, fs.isDir(spec.path)) end
        return "app"
    end
    if isDir then return "folder" end
    local ext = tostring(path):lower():match("%.([^.]+)$")
    return EXT_ICON[ext or ""] or "file"
end

function shortcut.demo()
    assert(shortcut.isLink("/home/desktop/Arquivos.lnk"), "deveria reconhecer .lnk")
    assert(not shortcut.isLink("/home/nota.txt"), "txt nao e atalho")
    assert(shortcut.iconFor("/home", true) == "folder", "pasta deveria usar o icone folder")
    assert(shortcut.iconFor("/apps/x.lua") == "lua", "lua deveria usar o icone lua")
    assert(shortcut.iconFor("/home/foto.nfp") == "image", "nfp deveria usar o icone image")
    assert(shortcut.iconFor("/home/leiame") == "file", "sem extensao cai no icone generico")
    assert(shortcut.iconFor(nil, false, { app = "files" }) == "files", "atalho de app usa o id como icone")
    assert(shortcut.iconFor(nil, false, { app = "user:teste" }) == "teste", "o prefixo user: nao entra no icone")
    assert(shortcut.sanitize("a/b:c") == "abc", "nome de arquivo deveria perder os caracteres proibidos")
    assert(shortcut.sanitize("   ") == "Atalho", "nome vazio precisa de um padrao")

    -- Ida e volta em disco, no /os/var que sempre existe.
    local made = assert(shortcut.create("/os/var", { name = "Demo", app = "files" }))
    local back = assert(shortcut.read(made), "atalho gravado nao voltou")
    assert(back.app == "files", "o alvo do atalho se perdeu na ida e volta")
    assert(shortcut.displayName(made, back) == "Demo", "nome mostrado errado")
    fs.delete(made)
    return true
end

return shortcut
