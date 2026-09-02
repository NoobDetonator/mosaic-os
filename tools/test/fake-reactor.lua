-- Reator do Powah falso, para conferir o painel no emulador sem entrar no jogo.
-- Reproduz o que foi medido no servidor: inventario + tanque + energy_storage,
-- buffer caindo 132 FE/s, e um Energy Detector que marca 0 (esta fora da linha).
-- Instala por cima das funcoes globais de peripheral, entao vale para o processo todo.

-- O emulador roda em fengari (5.3) e o CC em 5.1: cobre os dois.
local unpack = table.unpack or unpack

local M = {}

function M.instalar()
    local energia = 9714354
    local uraninita = 47
    local agua = 780

    local reator = {
        size = function() return 5 end,
        list = function()
            return {
                [2] = { name = "powah:uraninite", count = uraninita },
                [3] = { name = "minecraft:coal_block", count = 15 },
                [5] = { name = "powah:dry_ice", count = 29 },
            }
        end,
        tanks = function() return { { name = "minecraft:water", amount = agua } } end,
        -- Cada leitura consome um pouco: assim o historico varia e o grafico
        -- tem o que desenhar, como acontece no servidor.
        getEnergy = function()
            energia = energia - 132
            if energia % 900 < 132 then uraninita = math.max(0, uraninita - 1) end
            agua = math.max(0, agua - 3)
            return energia
        end,
        getEnergyCapacity = function() return 10000000 end,
        pushItems = function() return 0 end,
        pullItems = function() return 0 end,
    }
    local detector = {
        getTransferRate = function() return 0 end,
        getTransferRateLimit = function() return 2147483647 end,
    }
    local leitor = {
        getBlockName = function() return "powah:reactor_hardened" end,
        getBlockData = function()
            return { built = 1, variant = 2, extractor = 1, id = "powah:reactor_part",
                     x = 554, y = 95, z = -6497, core_pos = { X = 554, Y = 95, Z = -6496 } }
        end,
    }
    local chat = { sendMessage = function() return true end }

    local porNome = {
        ["powah:reactor_part_0"] = reator,
        ["energyDetector_0"] = detector,
        ["blockReader_0"] = leitor,
        ["chatBox_0"] = chat,
    }
    local tipos = {
        ["powah:reactor_part_0"] = { "powah:reactor_part", "inventory", "energy_storage", "fluid_storage" },
        ["energyDetector_0"] = { "energyDetector" },
        ["blockReader_0"] = { "blockReader" },
        ["chatBox_0"] = { "chatBox" },
    }

    peripheral.getNames = function()
        local n = {}
        for k in pairs(porNome) do n[#n + 1] = k end
        table.sort(n)
        return n
    end
    peripheral.wrap = function(name) return porNome[name] end
    peripheral.getType = function(name) return unpack(tipos[name] or {}) end
    peripheral.getMethods = function(name)
        local m = {}
        for k in pairs(porNome[name] or {}) do m[#m + 1] = k end
        return m
    end
    peripheral.getName = function(p)
        for k, v in pairs(porNome) do if v == p then return k end end
    end
    peripheral.find = function(tipo)
        for name, ts in pairs(tipos) do
            for _, t in ipairs(ts) do
                if t == tipo then return porNome[name], name end
            end
        end
    end
end

return M
