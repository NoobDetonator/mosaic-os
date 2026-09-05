-- Som do Mosaic: alto-falantes, notas do sistema e fluxo de audio DFPWM.
-- `local audio = mosaic.lib("audio")`
--
-- Tres camadas, da mais barata para a mais cara:
--
--   audio.sfx("clique")        um som do sistema. Uma nota, sem custo nenhum.
--   audio.note("bell", 3, 12)  uma nota crua.
--   audio.stream(nome)         a fila de PCM, para musica.
--
-- Nada aqui levanta erro por falta de hardware: sem alto-falante, tudo vira silencio.
-- O OS toca som em evento de janela, e um `error` ali derrubaria o compositor.
local audio = {}

-- Numeros do CC:T, nao escolhas nossas:
--   o alto-falante toca a 48 kHz, amostra de 8 bits com sinal (-128 a 127);
--   uma chamada de playAudio aceita no maximo 128*1024 amostras (~2,7 s);
--   o DFPWM gasta 1 bit por amostra, entao 16*1024 bytes dao exatamente esse maximo.
audio.RATE = 48000
audio.MAX_SAMPLES = 128 * 1024
audio.CHUNK = 16 * 1024

-- Os 16 instrumentos do bloco musical. playNote levanta erro em nome desconhecido, e o
-- erro sai como crash de app: melhor conferir aqui.
audio.instruments = {
    harp = true, basedrum = true, snare = true, hat = true, bass = true, flute = true,
    bell = true, guitar = true, chime = true, xylophone = true, iron_xylophone = true,
    cow_bell = true, didgeridoo = true, bit = true, banjo = true, pling = true,
}

-- Sons do sistema: { instrumento, volume, tom }. Tom em semitons, 0 a 24 (12 = Fa#).
-- Curtos de proposito. Som de sistema que dura e som de sistema que irrita.
audio.sounds = {
    clique   = { "hat", 0.4, 18 },
    abrir    = { "bell", 0.6, 16 },
    fechar   = { "bell", 0.6, 10 },
    erro     = { "bass", 1.0, 2 },
    aviso    = { "pling", 0.8, 14 },
    boot     = { "chime", 1.0, 12 },
}

-- ---------------------------------------------------------------- hardware

-- Todos os alto-falantes, COM o nome. O nome nao e enfeite: o evento
-- `speaker_audio_empty` diz qual alto-falante vagou, e o laco canonico da documentacao
-- ("while not playAudio do pullEvent end") ignora isso e trava com mais de um.
--
-- Por isso nao uso hal.findAll: ele devolve os objetos e perde o nome.
function audio.speakers()
    local out = {}
    if not peripheral then return out end
    local ok, names = pcall(peripheral.getNames)
    if not ok or not names then return out end
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "speaker" then
            local p = peripheral.wrap(name)
            if p then out[#out + 1] = { name = name, p = p } end
        end
    end
    return out
end

function audio.first()
    local list = audio.speakers()
    return list[1]
end

function audio.has() return audio.first() ~= nil end

-- Ligado ou nao. A chave nao existe no emulador (o settings da ROM esta la, mas quem
-- define as chaves e o boot), entao a falta dela vale como ligado.
function audio.enabled()
    if not settings then return true end
    local v = settings.get("mosaic.som.enabled")
    if v == nil then return true end
    return v and true or false
end

function audio.volume()
    local v = settings and tonumber(settings.get("mosaic.som.volume"))
    if not v then return 1.0 end
    if v < 0 then return 0 end
    if v > 3 then return 3 end
    return v
end

-- ---------------------------------------------------------------- notas

-- Uma nota. Devolve true se saiu som.
--
-- Limite do jogo: 8 notas por tique por alto-falante. Passou disso, playNote devolve false
-- em vez de tocar - nao e erro, e' a fila cheia.
function audio.note(instrument, volume, pitch, spk)
    if not audio.enabled() then return false end
    if not audio.instruments[instrument] then return false end
    spk = spk or audio.first()
    if not spk then return false end
    local vol = (volume or 1) * audio.volume()
    if vol <= 0 then return false end
    if vol > 3 then vol = 3 end
    local ok, played = pcall(spk.p.playNote, instrument, vol, pitch or 12)
    return ok and played == true
end

-- Um som do jogo, pelo nome do evento ("minecraft:entity.player.levelup").
-- So um por vez: se ja tem som tocando, devolve false.
function audio.sound(name, volume, pitch, spk)
    if not audio.enabled() then return false end
    spk = spk or audio.first()
    if not spk then return false end
    local vol = (volume or 1) * audio.volume()
    if vol <= 0 then return false end
    if vol > 3 then vol = 3 end
    local p = pitch or 1
    if p < 0.5 then p = 0.5 elseif p > 2 then p = 2 end
    local ok, played = pcall(spk.p.playSound, name, vol, p)
    return ok and played == true
end

-- Som do sistema pelo apelido. E' este que o kernel chama.
function audio.sfx(name, spk)
    local s = audio.sounds[name]
    if not s then return false end
    return audio.note(s[1], s[2], s[3], spk)
end

-- ---------------------------------------------------------------- codec

-- O decodificador de DFPWM vem da ROM (cc.audio.dfpwm, CC:T 1.100+). O nosso emulador nao
-- tem essa ROM, entao a falta dele nao pode ser erro: devolve nil e quem chamou decide.
function audio.decoder()
    if not require then return nil, "sem require" end
    local ok, dfpwm = pcall(require, "cc.audio.dfpwm")
    if not ok or type(dfpwm) ~= "table" or not dfpwm.make_decoder then
        return nil, "cc.audio.dfpwm indisponivel"
    end
    return dfpwm.make_decoder()
end

-- ---------------------------------------------------------------- fluxo

local Stream = {}
Stream.__index = Stream

-- Um fluxo de audio para UM alto-falante.
--
-- Nao tem laco por dentro de proposito. Processo do Mosaic e corrotina cooperativa: um
-- "while not playAudio do pullEvent end" aqui dentro comeria os eventos do app e travaria
-- o resto. Quem chama e o dono do laco:
--
--   local st = audio.stream()
--   st:offer(pedaco)                      -- devolve false se o alto-falante encheu
--   ...no evento speaker_audio_empty:
--   if st:owns(nomeDoEvento) then st:retry() end
--
-- opts.decoder existe para o teste: injetando um decodificador falso, toda a logica de
-- fila roda no emulador, que nao tem o codec de verdade.
function audio.stream(spk, opts)
    opts = opts or {}
    spk = spk or audio.first()
    local dec = opts.decoder
    local err
    if not dec then dec, err = audio.decoder() end
    return setmetatable({
        spk = spk,
        name = spk and spk.name or nil,
        decode = dec,
        injected = opts.decoder ~= nil,
        err = (not dec) and (err or "sem decodificador") or nil,
        pending = nil,      -- buffer decodificado que o alto-falante recusou
        samples = 0,        -- total ja aceito, para o app mostrar o tempo
        volume = opts.volume,
    }, Stream)
end

function Stream:ok() return self.spk ~= nil and self.decode ~= nil end

-- O evento speaker_audio_empty carrega o nome do alto-falante que vagou.
function Stream:owns(name) return name == nil or name == self.name end

-- Empurra o que estiver preso. true = vazio, pode mandar o proximo pedaco.
function Stream:retry()
    if not self.pending then return true end
    if not self:ok() then return false end
    -- `or 1` e nao `and ... or nil`: sem isto, um fluxo criado sem volume proprio - que e'
    -- exatamente como o musicd cria o da musica - mandava nil para o playAudio, o jogo
    -- assumia 1.0, e o seletor de volume das Configuracoes nao valia NADA para a musica.
    -- Os bipes obedeciam (passam por audio.note/sound), e por isso parecia que funcionava.
    local vol = (self.volume or 1) * audio.volume()
    if vol > 3 then vol = 3 end
    local ok, accepted = pcall(self.spk.p.playAudio, self.pending, vol)
    if not ok then self.err = tostring(accepted) return false end
    if not accepted then return false end
    self.samples = self.samples + #self.pending
    self.pending = nil
    return true
end

-- Oferece um pedaco de DFPWM cru. Devolve true se o alto-falante aceitou.
-- Falso NAO e erro: e' a fila cheia. Guarde e chame retry() no proximo
-- speaker_audio_empty. Chamar offer com algo preso levanta erro, porque perder audio
-- calado vira estalo no som e ninguem acha a causa.
function Stream:offer(chunk)
    if not self:ok() then return false end
    if self.pending then error("offer com pedaco pendente: chame retry primeiro", 2) end
    if type(chunk) ~= "string" or #chunk == 0 then return false end
    local ok, buf = pcall(self.decode, chunk)
    if not ok or type(buf) ~= "table" then
        self.err = "falha ao decodificar"
        return false
    end
    self.pending = buf
    return self:retry()
end

-- Corta o som e zera a fila. O decodificador NAO e reaproveitado: ele guarda estado do
-- fluxo, e continuar com ele na proxima musica sai com o som errado (a documentacao do
-- cc.audio.dfpwm avisa isso em caixa).
function Stream:stop()
    self.pending = nil
    self.samples = 0
    if self.spk then pcall(self.spk.p.stop) end
    -- Decodificador injetado (teste) fica: trocar por um da ROM mataria o fluxo falso.
    if not self.injected then self.decode = audio.decoder() end
end

-- Segundos ja tocados, para a barra de progresso.
function Stream:seconds() return self.samples / audio.RATE end

-- ---------------------------------------------------------------- self-check

function audio.demo()
    assert(audio.CHUNK * 8 == audio.MAX_SAMPLES,
        "a conta do DFPWM quebrou: 1 bit por amostra")
    assert(audio.instruments.harp and not audio.instruments.violino,
        "tabela de instrumentos errada")
    for nome, s in pairs(audio.sounds) do
        assert(audio.instruments[s[1]], "som do sistema com instrumento invalido: " .. nome)
        assert(s[2] >= 0 and s[2] <= 3, "volume fora de 0..3 em " .. nome)
        assert(s[3] >= 0 and s[3] <= 24, "tom fora de 0..24 em " .. nome)
    end

    -- Sem hardware nada disso pode levantar erro, so devolver false.
    assert(audio.note("harp") == false or audio.has(), "note sem alto-falante deveria dar false")
    assert(audio.sfx("inexistente") == false, "sfx aceitou apelido que nao existe")

    -- A fila, com alto-falante e decodificador falsos: e a logica que o emulador consegue
    -- cobrir. O decodificador de verdade so' existe na ROM, e quem o exercita e o CraftOS.
    local aceitos, volumes, cheio = {}, {}, true
    local fake = { name = "speaker_7", p = {
        playAudio = function(buf, vol)
            if cheio then return false end
            aceitos[#aceitos + 1] = #buf
            volumes[#volumes + 1] = vol
            return true
        end,
        stop = function() end,
    } }
    local st = audio.stream(fake, { decoder = function(s) return { #s } end })
    assert(st:ok(), "fluxo com pecas falsas deveria estar pronto")
    assert(st:owns("speaker_7"), "fluxo nao reconheceu o proprio alto-falante")
    assert(not st:owns("speaker_1"), "fluxo aceitou evento de outro alto-falante")

    -- Alto-falante cheio: offer devolve false e o pedaco fica preso, nao some.
    assert(st:offer("abc") == false, "offer deveria falhar com o alto-falante cheio")
    assert(st.pending ~= nil, "o pedaco recusado sumiu em vez de ficar pendente")
    assert(st.samples == 0, "contou amostra que nao foi tocada")

    -- Vagou: o pendente entra, e nada foi perdido no caminho.
    cheio = false
    assert(st:retry() == true, "retry falhou com o alto-falante livre")
    assert(#aceitos == 1 and aceitos[1] == 1, "o buffer que entrou nao e o que estava preso")
    assert(st.pending == nil, "pendente nao foi limpo depois de tocar")
    assert(st.samples == 1, "contagem de amostras errada: " .. st.samples)

    -- O VOLUME DAS CONFIGURACOES TEM DE CHEGAR AO ALTO-FALANTE. Um fluxo sem volume proprio
    -- e' o caso da musica, e era justamente ele que mandava nil e ignorava o seletor.
    assert(volumes[1] ~= nil, "o fluxo mandou nil de volume; o seletor das Configuracoes nao vale nada")
    local volAntes = settings and settings.get("mosaic.som.volume")
    if settings then
        settings.set("mosaic.som.volume", 2)
        cheio = false
        st:offer("q")
        assert(volumes[#volumes] == 2, "volume 2 nao chegou ao playAudio: " .. tostring(volumes[#volumes]))
        settings.set("mosaic.som.volume", 0)
        st:offer("w")
        assert(volumes[#volumes] == 0, "volume 0 nao chegou ao playAudio: " .. tostring(volumes[#volumes]))
        if volAntes then settings.set("mosaic.som.volume", volAntes)
        else settings.unset("mosaic.som.volume") end
    end

    -- Oferecer com algo preso e erro de programacao, nao silencio.
    cheio = true
    st:offer("xy")
    local okErr = pcall(st.offer, st, "zz")
    assert(not okErr, "offer com pendente deveria levantar erro")

    return true
end

return audio
