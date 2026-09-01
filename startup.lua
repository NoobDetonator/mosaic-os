-- Mosaic OS: ponto de entrada. Fica na raiz do computador.
-- Segure CTRL ao ligar? Não existe isso no CC; use o arquivo /os/safemode para pular o boot.
if fs.exists("/os/safemode") then
    print("Mosaic OS: modo seguro (apague /os/safemode para voltar ao normal).")
    return
end

if not fs.exists("/os/boot.lua") then
    printError("Mosaic OS: /os/boot.lua nao encontrado. Rode o instalador novamente.")
    return
end

local ok, err = pcall(shell.run, "/os/boot.lua")
if not ok then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    printError("Mosaic OS falhou ao iniciar:")
    printError(tostring(err))
    print("")
    print("Voce esta no shell da ROM. Digite 'edit /os/boot.lua' para investigar,")
    print("ou crie /os/safemode para pular o boot na proxima vez.")
end
