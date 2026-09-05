-- Atualizador compartilhado: valida downloads e conserva backup ate concluir.
local update = {}
local TX = "/.mosaic-update"
local function read(path)
    local h = fs.open(path, "rb")
    if not h then return nil end
    local ok, data = pcall(h.readAll)
    pcall(h.close)
    if not ok then error(data, 0) end
    return data
end
local function write(path, data)
    fs.makeDir(fs.getDir(path))
    local h = assert(fs.open(path, "wb"), "Nao consegui gravar " .. path)
    local ok, err = pcall(h.write, data)
    pcall(h.close)
    if not ok then error(err, 0) end
end
function update.sha1(data)
    local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
    local rol = bit32.lrotate
    local function word(n)
        return string.char(bit32.extract(n,24,8),bit32.extract(n,16,8),bit32.extract(n,8,8),band(n,255))
    end
    local bits = #data * 8
    data = data .. string.char(128) .. string.rep("\0",(55-#data)%64)
        .. word(math.floor(bits/4294967296)) .. word(bits%4294967296)
    local h0,h1,h2,h3,h4 = 0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0
    local w = {}
    for off=1,#data,64 do
        for i=0,15 do
            local a,b,c,d = data:byte(off+i*4,off+i*4+3)
            w[i] = a*16777216+b*65536+c*256+d
        end
        for i=16,79 do w[i]=rol(bxor(w[i-3],w[i-8],w[i-14],w[i-16]),1) end
        local a,b,c,d,e = h0,h1,h2,h3,h4
        for i=0,79 do
            local f,k
            if i<20 then f,k=bor(band(b,c),band(bnot(b),d)),0x5a827999
            elseif i<40 then f,k=bxor(b,c,d),0x6ed9eba1
            elseif i<60 then f,k=bor(band(b,c),band(b,d),band(c,d)),0x8f1bbcdc
            else f,k=bxor(b,c,d),0xca62c1d6 end
            local nextA=(rol(a,5)+f+e+k+w[i])%4294967296
            e,d,c,b,a=d,c,rol(b,30),a,nextA
        end
        h0,h1,h2,h3,h4=(h0+a)%4294967296,(h1+b)%4294967296,(h2+c)%4294967296,(h3+d)%4294967296,(h4+e)%4294967296
    end
    return (word(h0)..word(h1)..word(h2)..word(h3)..word(h4)):gsub(".",function(c) return string.format("%02x",c:byte()) end)
end
function update.fetch(base,path)
    if not http then error("API http desativada",0) end
    local h,err=http.get(base.."/"..path,nil,true)
    if not h then error(tostring(err or "Download falhou"),0) end
    local ok,body=pcall(h.readAll)
    pcall(h.close)
    if not ok then error(body,0) end
    return body
end
local function validPath(p)
    return type(p)=="string" and (p=="startup.lua" or p:match("^os/"))
        and not p:find("\\",1,true) and not p:find("//",1,true) and not p:find("%c")
        and fs.combine(p,"")==p and p~="os/var" and not p:match("^os/var/")
end
function update.prepare(base,extras,progress)
    local manifest=textutils.unserialiseJSON(update.fetch(base,"manifest.json"))
    assert(type(manifest)=="table" and type(manifest.files)=="table","Manifest invalido")
    local plan={base=base,version=manifest.version,files={}}
    local seen={}
    for i,entry in ipairs(manifest.files) do
        assert(type(entry)=="table" and validPath(entry.path),"Caminho invalido no manifest")
        assert(not seen[entry.path],"Caminho repetido no manifest")
        seen[entry.path]=true
        assert(type(entry.sha1)=="string" and #entry.sha1==40 and entry.sha1:match("^%x+$"),"Hash invalido")
        if not entry.optional or extras or fs.exists("/"..entry.path) then
            if progress then progress(i,#manifest.files,entry.path) end
            local data=update.fetch(base,entry.path)
            assert((not entry.size or #data==entry.size) and update.sha1(data)==entry.sha1:lower(),
                "Conteudo diverge do manifest: "..entry.path..". Tente novamente.")
            if read("/"..entry.path)~=data then plan.files[#plan.files+1]={target="/"..entry.path,data=data} end
        end
    end
    return plan
end
function update.recover()
    if not fs.exists(TX) then return true end
    local raw=read(TX.."/plan.json")
    if raw then
        local plan=textutils.unserialiseJSON(raw)
        assert(type(plan)=="table" and type(plan.files)=="table","Journal de atualizacao invalido")
        if not fs.exists(TX.."/done") then
            for i,entry in ipairs(plan.files) do
                assert(type(entry.target)=="string" and entry.target:sub(1,1)=="/" and
                    (validPath(entry.target:sub(2)) or entry.target=="/os/var/installed.json"
                    or entry.target=="/startup.old.lua"),"Journal invalido")
                local backup=TX.."/old/"..i
                if fs.exists(backup) then
                    if fs.exists(entry.target) then fs.delete(entry.target) end
                    -- Sem copiar: recuperar tambem funciona quando o disco esta cheio.
                    fs.move(backup,entry.target)
                elseif not entry.existed and fs.exists(entry.target) then fs.delete(entry.target) end
            end
        end
    end
    fs.delete(TX)
    return true
end
function update.apply(plan,progress)
    if fs.exists(TX) then return false,"Atualizacao interrompida: rode o instalador para recuperar." end
    local files={}
    for _,entry in ipairs(plan.files) do files[#files+1]=entry end
    if not fs.exists("/os/boot.lua") and fs.exists("/startup.lua") then
        if fs.exists("/startup.old.lua") then return false,"Guarde /startup.old.lua em outro nome antes de instalar." end
        files[#files+1]={target="/startup.old.lua",data=read("/startup.lua")}
    end
    files[#files+1]={target="/os/var/installed.json",data=textutils.serialiseJSON({version=plan.version,base=plan.base,at=os.epoch("utc")})}
    local journal,dirs,bytes={files={}},{},2500
    for _,entry in ipairs(files) do
        bytes=bytes+math.max(500,#entry.data)
        local dir=fs.getDir(entry.target)
        while dir~="" and dir~="/" do
            if not fs.exists(dir) and not dirs[dir] then dirs[dir]=true;bytes=bytes+500 end
            dir=fs.getDir(dir)
        end
        journal.files[#journal.files+1]={target=entry.target,existed=fs.exists(entry.target)}
    end
    local encoded=textutils.serialiseJSON(journal)
    bytes=bytes+math.max(500,#encoded)
    if fs.getFreeSpace("/")<bytes then return false,"Precisa de "..math.ceil(bytes/1024).." KB livres para atualizar com backup." end
    local ok,err=pcall(function()
        fs.makeDir(TX.."/new");fs.makeDir(TX.."/old")
        for i,entry in ipairs(files) do write(TX.."/new/"..i,entry.data) end
        write(TX.."/plan.tmp",encoded)
        fs.move(TX.."/plan.tmp",TX.."/plan.json")
        for i,entry in ipairs(files) do
            if progress then progress(i,#files,entry.target) end
            fs.makeDir(fs.getDir(entry.target))
            if fs.exists(entry.target) then fs.move(entry.target,TX.."/old/"..i) end
            fs.move(TX.."/new/"..i,entry.target)
        end
        write(TX.."/done","ok")
    end)
    if not ok then
        local restored,recovery=pcall(update.recover)
        return false,tostring(err)..(restored and " (alteracoes desfeitas)" or
            "; recuperacao pendente: "..tostring(recovery)..". Rode o instalador novamente.")
    end
    local clean,cleanup=pcall(update.recover)
    if not clean then return false,"Arquivos gravados; limpeza pendente: "..tostring(cleanup) end
    return true
end
return update
