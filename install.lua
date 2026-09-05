-- Instalador independente. Bootstrap da mesma origem confiavel do wget run.
local args={...}
local base=(args[2]~="extras" and args[2]) or "https://raw.githubusercontent.com/NoobDetonator/mosaic-os/master"
local extras=args[1]=="extras" or args[2]=="extras"
print("Mosaic OS - instalador")
if not http then printError("API http desativada no servidor.") return end
local response,err=http.get(base.."/os/lib/update.lua",nil,true)
if not response then printError(tostring(err)) return end
local ok,code=pcall(response.readAll)
pcall(response.close)
if not ok then printError(tostring(code)) return end
local fn,syntax=load(code,"=mosaic-installer","t",_G)
if not fn then printError(tostring(syntax)) return end
local success,result=pcall(function()
    local update=fn()
    update.recover()
    local plan=update.prepare(base,extras,function(i,n,path) print(string.format("[%d/%d] %s",i,n,path)) end)
    local applied,why=update.apply(plan)
    if not applied then error(why,0) end
    return #plan.files
end)
if not success then printError("Nao concluido: "..tostring(result)) return end
print("Concluido: "..result.." arquivos atualizados. Reinicie com reboot.")
