-- casa: malha 3D, convertida de casa.obj por tools/obj.js.
-- 16 triangulos, casca fechada (descarte de face e seguro).
-- Carregue com mesh.load("/os/share/models/casa.lua").
return {
    closed = true,
    tris = {
        { -1, 0, 1, 1, 0, 1, 1, 0, -1, c = colors.gray },
        { -1, 0, 1, 1, 0, -1, -1, 0, -1, c = colors.gray },
        { -1, 0, 1, -1, 1.2, 1, 1, 1.2, 1, c = colors.lightGray },
        { -1, 0, 1, 1, 1.2, 1, 1, 0, 1, c = colors.lightGray },
        { 1, 0, 1, 1, 1.2, -1, 1, 0, -1, c = colors.lightGray },
        { 1, 0, 1, 1, 1.2, 1, 1, 1.2, -1, c = colors.lightGray },
        { 1, 0, -1, 1, 1.2, -1, -1, 1.2, -1, c = colors.lightGray },
        { 1, 0, -1, -1, 1.2, -1, -1, 0, -1, c = colors.lightGray },
        { -1, 0, -1, -1, 1.2, -1, -1, 1.2, 1, c = colors.lightGray },
        { -1, 0, -1, -1, 1.2, 1, -1, 0, 1, c = colors.lightGray },
        { -1, 1.2, 1, 0, 2, 1, 1, 1.2, 1, c = colors.brown },
        { -1, 1.2, -1, 1, 1.2, -1, 0, 2, -1, c = colors.brown },
        { -1, 1.2, 1, -1, 1.2, -1, 0, 2, -1, c = colors.red },
        { -1, 1.2, 1, 0, 2, -1, 0, 2, 1, c = colors.red },
        { 1, 1.2, 1, 0, 2, 1, 0, 2, -1, c = colors.red },
        { 1, 1.2, 1, 0, 2, -1, 1, 1.2, -1, c = colors.red },
    },
}
