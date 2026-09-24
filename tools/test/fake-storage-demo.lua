-- Rede de baus falsa para capturas de tela do app Armazem.
-- Nenhum inventario do mundo e consultado ou modificado.
local M = {}

function M.instalar()
    local fake = dofile("/test/fake-periph.lua")
    local function chest(name, slots)
        local p = {}
        p.size = function() return 27 end
        p.list = function()
            local out = {}
            for slot, item in pairs(slots) do
                out[slot] = { name = item.name, count = item.count, nbt = item.nbt }
            end
            return out
        end
        p.getItemDetail = function(slot)
            local item = slots[slot]
            if not item then return nil end
            return { name = item.name, count = item.count, nbt = item.nbt,
                displayName = item.displayName, maxCount = item.maxCount or 64 }
        end
        p.pushItems = function() return 0 end
        fake.add(name, { "minecraft:chest", "inventory" }, p)
    end

    chest("minecraft:chest_0", {
        [1] = { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 64 },
        [2] = { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 39 },
        [3] = { name = "minecraft:diamond", displayName = "Diamond", count = 42 },
        [4] = { name = "minecraft:redstone", displayName = "Redstone Dust", count = 64 },
        [5] = { name = "minecraft:oak_log", displayName = "Oak Log", count = 64 },
    })
    chest("minecraft:chest_1", {
        [1] = { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
        [2] = { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
        [3] = { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
        [4] = { name = "minecraft:gold_ingot", displayName = "Gold Ingot", count = 27 },
        [5] = { name = "minecraft:emerald", displayName = "Emerald", count = 12 },
    })
    chest("minecraft:chest_2", {
        [1] = { name = "minecraft:enchanted_book", nbt = "a1", displayName = "Enchanted Book", count = 1, maxCount = 1 },
        [2] = { name = "minecraft:enchanted_book", nbt = "b2", displayName = "Enchanted Book", count = 1, maxCount = 1 },
        [3] = { name = "minecraft:lapis_lazuli", displayName = "Lapis Lazuli", count = 48 },
        [4] = { name = "minecraft:coal", displayName = "Coal", count = 64 },
        [5] = { name = "minecraft:torch", displayName = "Torch", count = 64 },
    })
    chest("minecraft:chest_input", {})
    chest("minecraft:chest_output", {})
    fake.instalar()
    os.queueEvent("peripheral", "minecraft:chest_0")
end

return M
