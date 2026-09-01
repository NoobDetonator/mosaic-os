-- Notas: arquivos de texto em /home/notas.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")

local DIR = "/home/notas"
if not fs.exists(DIR) then fs.makeDir(DIR) end

local w, h = term.getSize()
local f = ui.form()
local list = f:add(ui.list { x = 1, y = 1, w = w, h = h - 2, render = function(n) return " " .. n end })
local preview = f:add(ui.label { x = 1, y = h, w = w, text = "", bg = theme.taskbarBg, fg = theme.taskbarFg })

local function refresh()
    local items = {}
    for _, name in ipairs(fs.list(DIR)) do items[#items + 1] = name end
    table.sort(items)
    list:setItems(items, true)
    f.dirty = true
end

list.onSelect = function(_, name)
    local data = fsx.read(fs.combine(DIR, name)) or ""
    preview.text = " " .. (data:gsub("\n", " ")):sub(1, w - 2)
end
list.onActivate = function(_, name)
    mosaic.launchWith({ title = name }, "/rom/programs/edit.lua", fs.combine(DIR, name))
end

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h - 1, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("Abrir", function() local n = list:getSelected() if n then list.onActivate(list, n) end end)
addBtn("Nova", function()
    local name = ui.prompt("Titulo da nota:", "", "Nova nota")
    if name and #name > 0 then
        if not name:match("%.%w+$") then name = name .. ".txt" end
        local path = fs.combine(DIR, name)
        if not fs.exists(path) then fsx.write(path, "") end
        refresh()
        mosaic.launchWith({ title = name }, "/rom/programs/edit.lua", path)
    end
end, true)
addBtn("Excluir", function()
    local n = list:getSelected()
    if n and ui.confirm("Excluir a nota " .. n .. "?", "Confirmar") then
        fs.delete(fs.combine(DIR, n))
        refresh()
    end
end, true)
addBtn("Atualizar", refresh, true)

f.onEvent = function(_, ev)
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 3
        preview.y, preview.w = h, w
        f.dirty = true
        return true
    end
end

refresh()
f:run()
