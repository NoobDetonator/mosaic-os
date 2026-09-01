-- Editor: pergunta o arquivo e entrega para o `edit` da ROM, na mesma janela.
-- ponytail: o edit da ROM ja e um editor completo; so falta o seletor de arquivo.
local ui = mosaic.ui
local args = { ... }
local path = args[1]

if not path then
    path = ui.prompt("Arquivo para editar:", "/home/novo.lua", "Editor")
    if not path then return end
end
if path == "" then return end
path = path:gsub("^/", "")
local dir = fs.getDir(path)
if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end

mosaic.setTitle(nil, "Editar " .. fs.getName(path))
shell.run("/rom/programs/edit.lua", path)
