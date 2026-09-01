-- Shell simplificado do emulador: imita o comportamento relevante do rom/programs/shell.lua do CC:T.
-- - Sem argumentos: roda o script inicial (host.opts.script) e depois um prompt interativo.
-- - Com argumentos: executa o programa e sai.
-- - Le `multishell` do proprio ambiente (como o shell real) e chama multishell.setTitle ao rodar programas.
local multishell = multishell
local parentShell = shell
local parentTerm = term.current()
local tArgs = { ... }

local shell = {}
local running = true
local dir = parentShell and parentShell.dir() or ""
local path = parentShell and parentShell.path() or ".:/rom/programs"
local aliases = parentShell and parentShell.aliases() or {}
local programStack = {}

local ccrequire = dofile("/rom/modules/main/cc/require.lua")
local function makeRequire(env, d)
    return ccrequire.make(env, d)
end

local function createShellEnv(d)
    local env = { shell = shell, multishell = multishell }
    env.require, env.package = makeRequire(env, d)
    return env
end

function shell.dir() return dir end
function shell.setDir(d) dir = d end
function shell.path() return path end
function shell.setPath(p) path = p end
function shell.resolve(p)
    if p:sub(1, 1) == "/" then return fs.combine("", p) end
    return fs.combine(dir, p)
end
function shell.resolveProgram(cmd)
    if aliases[cmd] then cmd = aliases[cmd] end
    if cmd:find("/") then
        local p = shell.resolve(cmd)
        if fs.exists(p) and not fs.isDir(p) then return p end
        if fs.exists(p .. ".lua") then return p .. ".lua" end
        return nil
    end
    for seg in path:gmatch("[^:]+") do
        local base = seg == "." and dir or seg
        local p = fs.combine(base, cmd)
        if fs.exists(p) and not fs.isDir(p) then return p end
        if fs.exists(p .. ".lua") then return p .. ".lua" end
    end
    return nil
end
function shell.programs() return {} end
function shell.getRunningProgram() return programStack[#programStack] end
function shell.setAlias(a, b) aliases[a] = b end
function shell.clearAlias(a) aliases[a] = nil end
function shell.aliases() return aliases end
function shell.exit() running = false end
function shell.complete() return {} end
function shell.completeProgram() return {} end
function shell.setCompletionFunction() end
function shell.getCompletionInfo() return {} end

function shell.execute(cmd, ...)
    local p = shell.resolveProgram(cmd)
    if not p then printError("No such program") return false end
    if multishell then
        multishell.setTitle(multishell.getCurrent(), (fs.getName(p):gsub("%.lua$", "")))
    end
    programStack[#programStack + 1] = p
    local env = createShellEnv(fs.getDir(p))
    env.arg = { [0] = cmd, ... }
    local ok = os.run(env, p, ...)
    programStack[#programStack] = nil
    return ok
end

function shell.run(...)
    local line = table.concat({ ... }, " ")
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return false end
    return shell.execute(table.unpack(words))
end

function shell.openTab(...)
    if not multishell then return nil end
    local words = {}
    for w in table.concat({ ... }, " "):gmatch("%S+") do words[#words + 1] = w end
    local p = shell.resolveProgram(words[1])
    if not p then printError("No such program") return nil end
    local env = createShellEnv(fs.getDir(p))
    return multishell.launch(env, "/rom/programs/shell.lua", table.unpack(words))
end
function shell.switchTab(n) if multishell then multishell.setFocus(n) end end

if #tArgs > 0 then
    shell.run(table.unpack(tArgs))
    return
end

-- Shell de topo: roda o script inicial (equivale ao rom/startup.lua) e entra no prompt.
if not parentShell then
    local script = host.opts.script
    if fs.exists(script) then shell.run(script) end
    -- se o script terminou, o computador "desliga" (headless)
    if host.opts.show then host.print(term.screenText()) end
    host.exit(0)
end

print(os.version())
while running do
    term.setTextColor(colors.yellow)
    write((dir == "" and "" or dir) .. "> ")
    term.setTextColor(colors.white)
    local line = read()
    if line and line:match("%S") then shell.run(line) end
end
