-- Registro de aplicativos: o que aparece no menu Iniciar e na area de trabalho.
-- Apps do usuario: qualquer .lua em /apps aparece automaticamente.
local registry = {}

registry.builtin = {
    { id = "terminal", name = "Terminal", icon = ">_", color = colors.black, desktop = true, action = "shell" },
    { id = "files", name = "Arquivos", icon = "[]", color = colors.yellow, desktop = true, path = "/os/apps/files.lua" },
    { id = "editor", name = "Editor", icon = "Ed", color = colors.orange, desktop = true, path = "/os/apps/editor.lua" },
    { id = "netcenter", name = "Rede", icon = "()", color = colors.green, desktop = true, path = "/os/apps/netcenter.lua" },
    { id = "periph", name = "Perifericos", icon = "Pf", color = colors.purple, desktop = true, path = "/os/apps/periph.lua" },
    { id = "taskman", name = "Tarefas", icon = "Tk", color = colors.red, desktop = true, path = "/os/apps/taskman.lua" },
    { id = "settings", name = "Config", icon = "Cf", color = colors.gray, desktop = true, path = "/os/apps/settings.lua" },
    { id = "help", name = "Ajuda", icon = "?", color = colors.lightBlue, desktop = true, path = "/os/apps/help.lua" },
    { id = "notes", name = "Notas", icon = "No", color = colors.lime, path = "/os/apps/notes.lua" },
    { id = "calc", name = "Calculadora", icon = "+-", color = colors.cyan, path = "/os/apps/calc.lua" },
    { id = "clock", name = "Relogio", icon = "()", color = colors.blue, path = "/os/apps/clock.lua" },
    { id = "remote", name = "Controle remoto", icon = "Rm", color = colors.magenta, path = "/os/apps/remote.lua" },
    { id = "pkg", name = "Atualizar OS", icon = "Up", color = colors.brown, path = "/os/apps/pkg.lua" },
    { id = "paint", name = "Paint", icon = "Pt", color = colors.pink, path = "/rom/programs/fun/advanced/paint.lua", args = { "/home/desenho.nfp" } },
    { id = "lua", name = "Lua REPL", icon = "Lu", color = colors.lightGray, path = "/rom/programs/lua.lua" },
}

function registry.all()
    local out = {}
    for _, a in ipairs(registry.builtin) do
        if a.action or fs.exists(a.path) then out[#out + 1] = a end
    end
    if fs.isDir("/apps") then
        for _, f in ipairs(fs.list("/apps")) do
            if f:match("%.lua$") then
                local name = f:gsub("%.lua$", "")
                out[#out + 1] = { id = "user:" .. name, name = name, icon = name:sub(1, 2), color = colors.white,
                    path = "/apps/" .. f, user = true, desktop = true }
            end
        end
    end
    return out
end

function registry.open(app)
    if app.action == "shell" then return mosaic.shell() end
    if app.path then
        return mosaic.launchWith({ title = app.name, w = app.w, h = app.h }, app.path, table.unpack(app.args or {}))
    end
end

return registry
