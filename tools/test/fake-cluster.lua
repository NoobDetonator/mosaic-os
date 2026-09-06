-- Frota de mentira, para conferir o painel do cluster sem levantar cinco computadores.
--
-- No molde do fake-reactor: troca a funcao que o netd publicaria (`mosaic.clusterNodes`) por
-- uma que devolve nos inventados. Cobre o que a tela precisa saber desenhar: mais de um
-- grupo, turtle com e sem combustivel, no fora do ar, nome comprido e o proprio computador.
local M = {}

function M.instalar(api)
    settings.set("mosaic.cluster.role", "mestre")
    settings.set("mosaic.cluster.group", "base")

    local agora = os.epoch("utc")
    local seg = 1000
    local nos = {
        { id = 0, name = "Principal", group = "base", kind = "computador", version = "0.2.0",
          free = 953000000, visto = agora, desde = agora - 3600 * seg,
          peripherals = { "modem", "speaker" } },
        { id = 3, name = "Powah Manager", group = "base", kind = "computador", version = "0.2.0",
          free = 940000000, visto = agora - 2 * seg, desde = agora - 1800 * seg,
          peripherals = { "modem", "powah:reactor_part" } },
        { id = 7, name = "mineradora-norte", group = "mina", kind = "turtle", version = "0.2.0",
          free = 900000000, visto = agora - 1 * seg, desde = agora - 600 * seg,
          fuel = 18450, slot = 1, holding = "minecraft:coal",
          peripherals = { "modem" } },
        { id = 8, name = "mineradora-sul", group = "mina", kind = "turtle", version = "0.2.0",
          free = 900000000, visto = agora - 240 * seg, desde = agora - 900 * seg,
          fuel = 0, peripherals = { "modem" } },
        { id = 12, name = "estufa", group = "fazenda", kind = "turtle", version = "0.1.9",
          free = 880000000, visto = agora - 4 * seg, desde = agora - 120 * seg,
          fuel = -1, peripherals = { "modem" } },
        { id = 21, name = "bolso", group = "fazenda", kind = "pocket", version = "0.2.0",
          free = 500000, visto = agora - 3 * seg, desde = agora - 60 * seg },
    }

    -- `online` e' calculado, nao guardado: e' o que o cluster faz de verdade, e guardar
    -- deixaria a tela mentindo assim que o relogio andasse.
    api.clusterNodes = function()
        -- api.lib e nao require: o `require` cru daqui nao enxerga o /os no package.path, e
        -- este e' o mesmo carregador que os apps usam. Usar o cluster de VERDADE importa -
        -- assim a regra de "quem esta no ar" testada aqui e' a que roda no jogo.
        local cluster = api.lib("cluster")
        local t = cluster.tabela()
        for _, n in ipairs(nos) do
            local corpo = {}
            for k, v in pairs(n) do if k ~= "id" and k ~= "visto" and k ~= "desde" then corpo[k] = v end end
            t:registra(n.id, corpo, n.visto)
            t.nos[n.id].desde = n.desde
        end
        return t:lista(os.epoch("utc")), "mestre"
    end
    api.clusterForget = function(id)
        for i, n in ipairs(nos) do if n.id == id then table.remove(nos, i) return true end end
        return false
    end
end

return M
