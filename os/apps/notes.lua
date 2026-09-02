-- Notas: arquivos de texto em /home/notas.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")

local DIR = "/home/notas"
if not fs.exists(DIR) then fs.makeDir(DIR) end

local w, h = term.getSize()
local f = ui.form()
local list, preview, refresh

function refresh()
    local items = {}
    for _, name in ipairs(fs.list(DIR)) do items[#items + 1] = name end
    table.sort(items)
    list:setItems(items, true)
    f.dirty = true
end

-- A fila descobre quantas linhas ocupa; a previa se ancora acima dela e a lista preenche o resto.
local bar = ui.row(f, { bottom = 0, items = {
    { text = "&Abrir", onClick = function()
        local n = list:getSelected()
        if n then list.onActivate(list, n) end
    end },
    { text = "&Nova", alt = true, onClick = function()
        local name = ui.prompt("Titulo da nota:", "", "Nova nota")
        if name and #name > 0 then
            if not name:match("%.%w+$") then name = name .. ".txt" end
            local path = fs.combine(DIR, name)
            if not fs.exists(path) then fsx.write(path, "") end
            refresh()
            mosaic.launchWith({ title = name }, "/rom/programs/edit.lua", path)
        end
    end },
    { text = "&Excluir", alt = true, onClick = function()
        local n = list:getSelected()
        if n and ui.confirm("Excluir a nota " .. n .. "?", "Confirmar") then
            fs.delete(fs.combine(DIR, n))
            refresh()
        end
    end },
    { text = "A&tualizar", alt = true, onClick = function() refresh() end },
} })
preview = f:add(ui.label { x = 1, above = bar, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })
list = f:add(ui.list { x = 1, y = 1, w = "fill", fillTo = preview,
    render = function(n) return " " .. n end })

list.onSelect = function(_, name)
    local data = fsx.read(fs.combine(DIR, name)) or ""
    preview.text = " " .. (data:gsub("\n", " ")):sub(1, list.w - 2)
end
list.onActivate = function(_, name)
    mosaic.launchWith({ title = name }, "/rom/programs/edit.lua", fs.combine(DIR, name))
end

-- Sem onResize: o form reposiciona tudo pelas ancoras.

refresh()
f:run()
