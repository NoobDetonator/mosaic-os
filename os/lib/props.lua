-- Janela de propriedades de um arquivo, pasta ou atalho.
-- Usada pelo Arquivos, pela area de trabalho e pelo menu Iniciar.
local fsx = require("lib.fsx")
local strutil = require("lib.strutil")
local shortcut = require("lib.shortcut")

local props = {}

local function stamp(ms)
    if type(ms) ~= "number" then return nil end
    local ok, s = pcall(os.date, "%d/%m/%Y %H:%M", math.floor(ms / 1000))
    return ok and s or nil
end

-- Devolve { {rotulo, valor}, ... }. Separado do desenho para dar para testar sem tela.
function props.lines(path, spec)
    local out = {}
    local function row(label, value) if value then out[#out + 1] = { label, tostring(value) } end end

    local isDir = fs.isDir(path)
    row("Nome", shortcut.displayName(path, spec))
    row("Local", "/" .. fs.getDir(path))

    if spec then
        row("Tipo", "Atalho")
        if spec.app then row("Abre", "app " .. tostring(spec.app)) end
        if spec.path then
            row("Alvo", "/" .. fs.combine(spec.path, ""))
            if not fs.exists(spec.path) then row("Aviso", "o alvo nao existe mais") end
        end
        if spec.args and #spec.args > 0 then row("Argumentos", table.concat(spec.args, " ")) end
    elseif isDir then
        local n = 0
        for _ in ipairs(fs.list(path)) do n = n + 1 end
        row("Tipo", "Pasta")
        row("Conteudo", n .. (n == 1 and " item" or " itens"))
        row("Tamanho", strutil.bytes(fsx.treeSize(path)))
    else
        row("Tipo", (path:lower():match("%.([^.]+)$") or "arquivo"):upper())
        row("Tamanho", strutil.bytes(fs.getSize(path)))
    end

    row("Somente leitura", fs.isReadOnly(path) and "sim" or "nao")
    local ok, attr = pcall(fs.attributes, path)   -- fs.attributes so' existe do CC:T 1.87 pra ca
    if ok and type(attr) == "table" then
        row("Modificado", stamp(attr.modified or attr.modification))
        row("Criado", stamp(attr.created or attr.creation))
    end
    return out
end

function props.show(path, spec)
    local ui = mosaic.ui
    local theme = mosaic.theme
    if not fs.exists(path) then ui.msgbox("Esse item nao existe mais.", "Propriedades") return end

    local rows = props.lines(path, spec)
    local W = term.current().getSize()
    local w = math.min(math.max(34, W - 4), W)
    local labelW = 0
    for _, r in ipairs(rows) do labelW = math.max(labelW, #r[1]) end

    ui.dialog {
        w = w, h = #rows + 5, title = "Propriedades",
        build = function(form, dlg)
            form:add(ui.group { x = 1, y = dlg.contentY, w = dlg.w, h = #rows + 2,
                text = shortcut.displayName(path, spec) })
            local y = dlg.contentY + 1
            for _, r in ipairs(rows) do
                form:add(ui.label { x = 3, y = y, text = r[1] .. ":", fg = theme.mutedFg })
                form:add(ui.label { x = 3 + labelW + 2, y = y, w = dlg.w - labelW - 5,
                    text = strutil.ellipsis(r[2], math.max(1, dlg.w - labelW - 5)) })
                y = y + 1
            end
            local b = form:add(ui.button { x = dlg.w - 7, y = dlg.h - 1, text = "&OK",
                onClick = function() dlg.close(true) end })
            form.defaultButton, form.cancelButton = b, b
            form:setFocus(b)
        end,
    }
end

function props.demo()
    local path = "/os/var/propsdemo.txt"
    fsx.write(path, "12345")
    local rows = props.lines(path)
    local seen = {}
    for _, r in ipairs(rows) do seen[r[1]] = r[2] end
    assert(seen["Nome"] == "propsdemo.txt", "nome errado nas propriedades")
    assert(seen["Tipo"] == "TXT", "tipo deveria vir da extensao")
    assert(seen["Somente leitura"] == "nao", "arquivo em /os/var nao e somente leitura")
    fs.delete(path)

    local dirRows = props.lines("/os/var")
    local kind
    for _, r in ipairs(dirRows) do if r[1] == "Tipo" then kind = r[2] end end
    assert(kind == "Pasta", "pasta deveria ser reconhecida como pasta")

    local lnkRows = props.lines("/home/x.lnk", { name = "X", app = "files" })
    local target
    for _, r in ipairs(lnkRows) do if r[1] == "Abre" then target = r[2] end end
    assert(target == "app files", "atalho deveria mostrar o app que abre")
    return true
end

return props
