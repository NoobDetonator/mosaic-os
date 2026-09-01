-- Shim de cc.require para o emulador (mesma semantica basica do CC:T 1.88+).
local M = {}

function M.make(env, dir)
    local package = {}
    package.loaded = { _G = _G, string = string, table = table, math = math, coroutine = coroutine, os = os, io = io }
    package.path = "?;?.lua;?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"
    package.preload = {}
    local function loader(name)
        local fname = name:gsub("%.", "/")
        local tried = {}
        for pattern in package.path:gmatch("[^;]+") do
            local p = pattern:gsub("%?", fname)
            if p:sub(1, 1) ~= "/" then p = fs.combine(dir, p) end
            if fs.exists(p) and not fs.isDir(p) then
                local fn, err = loadfile(p, "t", env)
                if not fn then error(err, 0) end
                return fn, p
            end
            tried[#tried + 1] = p
        end
        return nil, "no file '" .. table.concat(tried, "'\n\tno file '") .. "'"
    end
    package.loaders = { function(name) return package.preload[name] end, loader }
    local function require(name)
        if package.loaded[name] ~= nil then return package.loaded[name] end
        local errs = {}
        for _, l in ipairs(package.loaders) do
            local fn, extra = l(name)
            if fn then
                local res = fn(name, extra)
                if res == nil then res = true end
                package.loaded[name] = res
                return res
            elseif extra then errs[#errs + 1] = extra end
        end
        error("module '" .. name .. "' not found:\n\t" .. table.concat(errs, "\n\t"), 2)
    end
    env.package = package
    return require, package
end

return M
