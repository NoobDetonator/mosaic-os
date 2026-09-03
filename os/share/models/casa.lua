-- casa: malha 3D, convertida de casa.obj por tools/obj.js.
-- 16 triangulos, 10 vertices, casca fechada (descarte de face e seguro).
-- Carregue com mesh.load("/os/share/models/casa.lua"): v e' a lista de vertices
-- (tres numeros cada) e t a de triangulos (tres indices em v, mais a cor em cores).
return {
    closed = true,
    cores = { colors.gray, colors.lightGray, colors.brown, colors.red },
    v = {
        -1, 0, 1,  1, 0, 1,  1, 0, -1,  -1, 0, -1,
        -1, 1.2, 1,  1, 1.2, 1,  1, 1.2, -1,  -1, 1.2, -1,
        0, 2, 1,  0, 2, -1,
    },
    t = {
        1, 2, 3, 1, 1, 3, 4, 1, 1, 5, 6, 2, 1, 6, 2, 2,
        2, 7, 3, 2, 2, 6, 7, 2, 3, 7, 8, 2, 3, 8, 4, 2,
        4, 8, 5, 2, 4, 5, 1, 2, 5, 9, 6, 3, 8, 7, 10, 3,
        5, 8, 10, 4, 5, 10, 9, 4, 6, 9, 10, 4, 6, 10, 7, 4,
    },
}
