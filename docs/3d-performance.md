# 3D performance notebook

Every hypothesis about the 3D engine's performance is recorded here with its prediction, its
measurement and its verdict. **A hypothesis that doesn't hold stays here marked as refuted** — that
is what the table is for.

All numbers come from `node tools/craftos.js bench`, in CraftOS-PC, a 51×19 screen, drawing into a
51×15 cell canvas = 4,590 points. Reference: one Minecraft tick = 50 ms.

The bench uses the **median of 5 rounds** with `collectgarbage()` before each, and prints min and
max. It used to be the mean of a single round, and a collector pause inside a 5-iteration loop
dominated the number.

> **Read this before trusting any number below.** These are CraftOS-PC figures — a native process
> on a PC. The same engine measured **40× slower inside the game**. See
> [In-game reality check](#in-game-reality-check) at the end. What holds across both is the
> **ratio** between two measurements taken in the same session, never the absolute value.

---

## Baseline (before any optimisation)

| Measurement | ms |
|---|---:|
| `frame:clear` (canvas + z-buffer) | 0.13 |
| `canvas:render` (output to screen) | **1.68** |
| cube, 12 triangles, clear+draw | 1.22 |
| 7×7 grid, 98 triangles | 0.55 |
| 22×22 grid, 968 triangles | 2.05 |
| 71×71 grid, 10,082 triangles | 17.45 |
| solid circle 15, 828 triangles | 2.20 |
| hollow sphere 15, 3,768 triangles | 11.80 |
| hollow sphere 15, with backface culling | 8.90 |
| building the sphere mesh | 5.60 |
| a full frame the way `calc` does it | 4.35 |

### What the baseline already teaches

**`canvas:render` is the largest fixed cost, and nobody knew.** 1.68 ms, thirteen times `clear`.
For the 12-triangle cube, getting the result to the screen costs more than drawing it. It wasn't
measured anywhere — the three old 3D lines lumped clear and draw into a single number.

**Cost per triangle: 1.69 µs.** The three grids cover the same screen area with 98, 968 and 10,082
triangles, so the difference between them is pure per-triangle cost:
`(17.45 − 2.05) / (10,082 − 968) = 1.69 µs`. That's **~590k triangles per second**.

For comparison: Pine3D advertises 20k polygons at 20 fps in plain Lua, or ~400k per second. Same
order of magnitude — but it measures on an in-game computer and we measure on CraftOS-PC, which is
faster. The honest comparison isn't possible yet.

**Small scenes are pixel-bound; large scenes are triangle-bound.** The cube has 12 triangles and
takes 1.09 ms to draw, because those 12 cover nearly the whole canvas. The 98-triangle grid covers
the same area in 0.42 ms. Optimising the pixel loop helps the first; optimising the per-vertex
transform helps the second.

---

## Hypotheses

| # | Hypothesis | Prediction | Measured | Verdict |
|---|---|---|---|---|
| 1 | Backface culling removes half the work | ~50% | 11.80 → 8.90 = **25%** | **Partial.** See below. |
| 4 | Keeping canvas and frame between draws removes half the fixed cost | ~50% of fixed | 4.35 vs 3.88 summing the parts = **0.47 ms**, ~11% | **Overestimated.** See below. |

### 1 — Backface culling: predicted 50%, got 25%

The error was mine and it's instructive. Half the faces of a closed shell point away from the
camera, so half the **rasterisation** disappears — but a discarded face **has already paid for
transforming its three vertices** before the area test, because culling happens inside the
rasteriser. What's left is: full transform, half the rasterisation.

That changes the order of what's worth attacking: **the per-vertex transform weighs as much as the
fill**, and the per-vertex path was expensive — metatable dispatch in `self:project`, a closure per
object, and eleven table lookups per vertex.

### 4 — Keeping canvas and frame: predicted half, got 11%

A full frame the way the app does it costs 4.35 ms. The parts summed — drawing the circle with
clear (2.20) plus the output (1.68) — give 3.88. The difference, **0.47 ms**, is everything that
creating a new canvas and frame costs per frame. Worth fixing because it's cheap, but I had
predicted far more.

What I hadn't noticed when predicting: `clear` costs 0.13 ms, not the "11,600 table writes" a
static count suggested. **Counting operations on paper is not a substitute for measuring.**

---

## Wave 1 — near-plane clipping

| Measurement | base | clipped (1st attempt) | clipped (final) |
|---|---:|---:|---:|
| 71×71 grid, 10,082 tri | 17.45 | **35.55** | 17.90 |
| 22×22 grid, 968 tri | 2.05 | 3.85 | 2.15 |
| circle 15, 828 tri | 2.20 | 4.25 | 2.05 |
| hollow sphere 15, 3,768 tri | 11.80 | 13.60 | **9.70** |
| full `calc` frame | 4.35 | 4.95 | 4.10 |

### The first attempt doubled the time, and the reason is worth keeping

To clip, a triangle has to become a polygon of up to 4 vertices, and the obvious way to write that
is to pass the vertices through an array: `poly[1..9]`, then a loop projecting into `px[k]`,
`py[k]`, `pw[k]`. That's **21 table operations per triangle** — and I was paying them on **every**
triangle, including the 99.9% that need no clipping at all.

The 10k-triangle scene went from 17.45 to 35.55 ms. Exactly double.

The fix was to split the two paths: when all three vertices are in front of the camera — the common
case — the values go straight from local variables into the rasteriser's arguments, touching no
table at all. The array only exists in the rare branch.

**And then the frame ended up faster than before clipping.** The sphere fell from 11.80 to 9.70 ms,
18%. The gain didn't come from clipping: it came from the restructuring pulling `pcx`, `pcy` and
`escala` out of the `pre` table into locals, and from `camX/camY/camZ` no longer being three hash
lookups in `self.cam` per vertex.

**Lesson:** in Lua without a JIT, the cost of an abstraction on the hot path is measurable and
large. The common path has to be flat.

---

## Wave 2, hypothesis 6 — `canvas:render`

**Prediction:** removing per-cell allocations helps. **Measured: 1.68 → 0.49 ms, 3.4×.**
**Confirmed, and it was the frame's largest fixed cost.**

| Measurement | before | after |
|---|---:|---:|
| `canvas:render` | 1.68 | **0.49** |
| full `calc` frame | 4.35 | **2.80** |

What was expensive, per cell, on a 765-cell screen:

- `pixel.cell` allocated **two tables** (counts and order) and **one closure** (`near`);
- the six sub-pixels went in and out through a `px[1..6]` array — twelve table operations;
- `string.char(128 + code)` and **two** calls to `colors.toBlit`;
- the three row tables (`chars`, `fgs`, `bgs`) were new on every row.

Now: `pixel.cell6` takes the six values loose, the counting scratch is reused and cleared inside the
same loop that picks the two colours, and two tables are built once — the character for each bit
combination and the blit letter for each colour.

**An intermediate attempt achieved nothing, and it's worth recording.** Removing the `px` array, I
wrote the counting loop as `for i = 1, 6 do local c = (i == 1 and p1) or (i == 2 and p2) or ... end`.
That trades twelve table operations for thirty comparisons: it cancels the gain. Unrolling the six
lines by hand is ugly to read and is what makes the number happen.

This gain is **not only the 3D engine's**: wallpaper, icons built from scratch, the calculator's
plot and the block preview all go through the same path.

---

## Wave 2, hypotheses 2 and 3 — the rasteriser

**2. Writing straight into the buffer** instead of going through `canvas:set`. **Confirmed.**
**3. Scanline with edge stepping** instead of a bounding box with a per-point test.
**Confirmed, and the bigger of the two.**

| Measurement | base | +render | +direct write | +scanline | total gain |
|---|---:|---:|---:|---:|---:|
| cube, 12 tri | 1.22 | 1.25 | 0.80 | **0.36** | **3.4×** |
| 7×7 grid, 98 tri | 0.55 | 0.60 | 0.60 | **0.35** | 1.6× |
| 22×22 grid, 968 tri | 2.05 | 2.30 | 2.30 | **1.40** | 1.5× |
| 71×71 grid, 10,082 tri | 17.45 | 17.75 | 17.55 | **12.15** | 1.4× |
| circle 15, 828 tri | 2.20 | 2.20 | 2.00 | **1.35** | 1.6× |
| hollow sphere 15, 3,768 tri | 11.80 | 9.50 | 9.00 | **6.10** | **1.9×** |
| hollow sphere 15 with culling | 8.90 | 8.50 | 6.10 | **5.30** | 1.7× |
| full `calc` frame | 4.35 | 2.80 | 2.70 | **2.10** | **2.1×** |

### What each one did

**Direct writing** helps where fill dominates and almost nothing where triangles dominate: the cube
dropped 36%, the 10k-triangle grid dropped 1%. That makes sense — `canvas:set` cost two
`math.floor`, four bounds tests and one `blitCache = nil` **per point**, for work that is done once
per frame.

**Scanline** helps everywhere, because it removes two things at once: the 21 coverage-test
operations per candidate point, and the bounding-box points the triangle doesn't cover (close to
half, for a typical triangle). The inner loop became `if w > zb[i] then ... end; w = w + A`.

A painted-point counter that was incremented **per point**, and whose return value nobody read,
also disappeared.

### Where that got us

Cost per triangle now: `(12.15 − 1.40) / (10,082 − 968) = 1.18 µs`, or **~847k triangles per
second**, against 1.69 µs and 590k at baseline.

The cube frame in the demo measures **0 ms** — below `os.epoch`'s millisecond resolution.

---

## Wave 2, hypotheses 1 and 4 — culling and a kept frame

**1. Backface culling.** The decision now belongs to the **mesh**, through its `closed` flag, not to
a global switch: `mesh.voxels` and `mesh.cube` declare themselves closed, `plane` and `grid` don't.
With a z-buffer, culling only saves time — provided the mesh really is closed, and the mesh is what
knows. A plane or grid with culling would vanish when seen from below, which is right for terrain
and wrong for a wall.

Measured on the sphere: **6.00 without, 4.70 with** — 22%. Before the other optimisations it was
25%; as the rasteriser got cheaper, the slice culling saves shrank, because the three vertices are
still transformed before the test.

**4. Keeping canvas and frame between draws** (`calc.lua` and the demos). Measured: **1.70 creating,
1.55 reusing**. That's 0.15 ms, against 0.47 at baseline — the gain itself shrank because everything
around it got cheaper. Worth it because it costs eight lines.

---

## Where wave 2 ended

| Measurement | base | now | gain |
|---|---:|---:|---:|
| `canvas:render` | 1.68 | 0.48 | 3.5× |
| cube, 12 tri | 1.22 | 0.26 | **4.7×** |
| 7×7 grid, 98 tri | 0.55 | 0.35 | 1.6× |
| 22×22 grid, 968 tri | 2.05 | 1.30 | 1.6× |
| 71×71 grid, 10,082 tri | 17.45 | 11.70 | 1.5× |
| circle 15, 828 tri | 2.20 | 1.00 | 2.2× |
| hollow sphere 15, 3,768 tri | 11.80 | 4.70 | **2.5×** |
| full frame | 4.35 | 1.55 | **2.8×** |

Cost per triangle: **1.69 → 1.14 µs**, or from 590k to **~877k triangles per second**.

The drawing did not change: the cube screenshot before and after is identical, and the z-buffer test
still passes in both draw orders.

---

## Wave 3 — lighting

`os/lib/shade.lua`: per-face Lambert, with the normal precomputed into the model (`tri[11..13]`,
once per mesh and not per frame), and the result landing on a step of a ramp.

Per face and not per vertex, deliberately: with 16 colours there is no gradient, and interpolating
tone between vertices would only increase the number of cells holding three colours. A sub-pixel
cell accepts two — the result would be worse, not better.

### The darkest step was the background

The grey ramp starts at **black**, and the 3D canvas background is black. With ambient 0.2, faces
turned away landed on the first step and **vanished into the background**: the demo cube became a
flattened lozenge, because only the top survived. It took a screenshot to notice.

Fix: ambient 0.3 never reaches the first step of a four-step ramp, and that became a test.
`applyTinted` now measures levels **after** removing the ambient, so the darkest possible face lands
on grey and never on black.

### The palette experiment: **confirmed**

The ramp the Win95 palette offers is 0, 128, 192, 255 — the first jump is double the other two. In
practice, with rounding to steps, two adjacent cube faces landed on the same tone and the cube
looked flat.

The `palette.render3d` map **fills the gaps instead of replacing**: brown, purple, magenta and pink
— four colours the theme doesn't use — become 48, 90, 160 and 224. The ramp becomes
**0, 48, 90, 128, 160, 192, 224, 255**, eight steps, largest jump 48 instead of 128.

Black, grey, light grey and white stay where they were, so **the taskbar, the button bevels and the
title bar don't change colour** — confirmed by screenshot, with the taskbar and the desktop teal
intact next to the cube.

The palette is applied to the **root** terminal, never to a window: a CC window keeps its palette to
itself. It works because the compositor never re-pushes the palette — it only calls `blit`. And it
is restored on exit, both via Q and via the window's X (`terminate` restores too). Verified with a
screenshot of the desktop after exiting: icons normal.

### What did NOT work: directional light on voxels

I applied the same lighting to the calculator's block preview and it got **worse**. A voxel's faces
are all axis-aligned, so there are only six normals; a four-step ramp throws the terraces into very
different tones and the sphere becomes hard banding.

The `top / side / bottom` that `mesh.voxels` already painted is **orientation, not direction**: the
four sides stay in the same tone, so there's no asymmetry between left and right and the terrace
doesn't jump. For a stepped shape, that beats Lambert.

Reverted in the calculator, kept in the cube and terrain demos, where it helps.

---

## Wave 4 — Blender models

No speed hypothesis in this wave: the bottleneck here is **disk**, not frame time.

### File format: 105 KB → 33 KB

Suzanne exported from 5.2 has **507 vertices and 968 triangles**. Writing each triangle with its
nine numbers repeats each vertex about six times:

| Format | Size | Suzanne |
|---|---:|---|
| triangles with nine numbers | 105 KB | the first one I wrote |
| indexed (`v` + `t`) | 33 KB | 3.2× smaller |

Not a detail: a CC:T computer has **1 MB of disk in total** and the whole OS takes ~610 KB. In the
old format, one model ate 10% of the machine's disk.

Unfolding happens once, in `mesh.load`, and never shows up in a frame measurement: the cost is at
load time and the rasteriser still receives flat triangles, the way it wants them.

### Drawing: 3 ms for 968 triangles

Consistent with the wave 0 sweep (the 828-triangle circle was 1.00 ms; Suzanne has more screen
coverage per triangle). Comfortably inside a 50 ms tick.

### What did NOT work: `applyTinted` alone on a coloured model

The test house has four materials and came out **monochrome**. `applyTinted` sent every face out of
direct light to light grey and grey, so red, brown and grey became the same thing as soon as they
left the brightest step.

The way out was `shade.darker`: the darker relative of each colour **within the 16** (red → brown,
lime → green, pink → magenta, light blue → cyan). The floor is still grey and never black — a colour
already too dark for the background (blue, purple, brown) lands on grey even though grey is
lighter, because vanishing into the background is worse than getting lighter.

### What did NOT work: a fixed light in a model viewer

I twice tried letting the light rotate on its own while the model spins. Both times the house came
out **entirely grey** in the screenshot — the second because the angle's sign put the light exactly
behind the model. In a viewer, what rotates is the model: the light has to come from the **same
formula as the camera** (`-sin`, `-cos`) plus a shoulder.

Along with it, the light's vertical component had to drop from 0.8 to 0.5. The vector is normalised,
so a light too far overhead leaves nothing for the sides, and the two visible walls (90° apart, 45°
to the light) both landed on **0.55** — exactly on `applyTinted`'s cut.

### A false positive in the normal check

The converter checks each face's winding against the file's `vn`. On Suzanne it flagged two inverted
faces; on inspection they are two slivers of **area 0.0006** whose cross product sits 4° from the
declared normal — rounding noise, not an exporter error.

Fixed with a threshold: only invert when the disagreement exceeds about 6°. Without it the "faces
corrected" warning becomes noise and loses its use, which is pointing at a strange exporter. The
house, which has one deliberately inverted wall, still reports its two faces.

---

## Wave 5 — wireframe and monitors

### Line clipping, measured by what it avoids

`Canvas:line` walked point by point even off-screen, with `Canvas:set` discarding silently. A single
`line(-100000, 3, 100000, 3)` call makes **200,000 Bresenham steps** on a canvas 8 points wide: the
CC 7-second abort fires first. With Liang–Barsky in front, it's 8 steps.

There is no "before and after" in milliseconds here because the before **never finishes**. That is
the number.

### Wireframe is slower than filled: 6 ms against 3

It contradicted intuition, and the reason is simple once seen:

- every edge between two faces is drawn **twice**, once per triangle;
- there is no z-buffer to skip an already-covered pixel — in the filled path, half of Suzanne's
  pixels fail the depth test;
- and culling doesn't help much: it removes the face, but its edges are usually shared with a
  visible one.

Wireframe is for seeing a small mesh's topology, not for gaining speed.

### Monitor: 204×114 points for 7 ms

| Target | Points | Suzanne |
|---|---:|---:|
| 50×17 window | 100×48 | 3 ms |
| 102×38 monitor at scale 0.5 | 204×114 | 7 ms |

4.8× the area for 2.3× the time — the per-point cost **falls**, because the fixed per-triangle cost
(transform three vertices, project, test area) is the same in both. Even so, 7 ms out of a 50 ms
frame is expensive for a demo that also draws in a window: `modelo.lua` draws to the monitor every
fourth frame.

### Framing: `normalizeScale` is not what it looks like

It puts the **largest dimension** at 1. That does not mean the model fits: a cube seen from a corner
occupies the diagonal, 1.73. And `three`'s scale derives from `w/2` on **both** axes (CC's sub-pixel
is square), so in a window wider than tall it's the height that squeezes.

At a fixed distance of 1.7 the wireframe house came out with all four corners off-screen. The right
calculation uses the model's bounding sphere against the **smaller** half of the canvas:

    dist = radius * begin().escala / (min(w, h) / 2) * 1.08

A sphere and not a box: a box would frame more tightly, but it would change with every angle, and
framing that breathes is worse than framing that's loose.

---

## The cost of wireframe on the hot path, and a warning about the machine

`wire` entered as one `if` per triangle inside the engine's hottest loop. Measured:

| Scene | without the `if` | with the `if` |
|---|---:|---:|
| 71×71 grid, 10,082 triangles | 15.25 ms | 15.95 ms |
| circle 15, 828 triangles | 1.35 ms | 1.40 ms |

**4.5% in the worst case**, 0.07 µs per triangle. It could be driven to zero by duplicating the
whole loop into two versions, and it isn't worth it: 60 lines of the engine's most delicate code to
gain 4.5% in a scene nobody draws. Passing the decision through a function would be worse — wave 2
already showed that a call per triangle costs more than a branch per triangle.

**Warning for anyone diffing `bench-ultimo.txt`:** today's measurements sit ~30% above wave 2's **on
the same code**. I ran the pre-wireframe `three.lua` to check: the 10k grid gave 15.25 ms today
against 11.70 ms recorded in wave 2. What also rose was code nobody touched — `one kernel step`
(0.23 → 0.28) and `icon built from scratch` (0.25 → 0.35) — so it's the machine, not the code.

The lesson is worth more than the number: **this bench measures ratios, not absolute values.**
Comparing two measurements taken on different days says nothing. Before and after in the same
session, yes.

---

## In-game reality check

Measured on the server with real scanner data: **5,204 triangles cost 247 ms per frame** on a
160×108-point canvas. That's **~21k triangles/second**.

This notebook says ~877k/s. The gap is **40×**, and it is not a bug — the bench runs as a native
process on a PC, and the game runs Cobalt inside a Minecraft server sharing time with everything
else.

**Do not use the numbers above to decide what fits in an in-game app.** Use them to compare two
versions of the same code.

What that measurement changed in the product:

- the 3D chunk scene's ceiling dropped from 3,000 to 800 blocks (~5k triangles, ~240 ms);
- auto-rotation now paces itself by the **cost of the last frame** — it waits three times what that
  frame took, between 0.3 s and 3 s. A light scene spins smoothly; a heavy one spins slowly instead
  of eating the computer. Spinning faster than you can draw only queues work.

---

## CraftOS-PC's graphics mode, and why it stays out

Worth measuring to know the size of the temptation, and worth recording so nobody falls for it.

CraftOS-PC has a **graphics mode** that in-game CC:Tweaked does not: `term.setGraphicsMode`,
`setPixel`, `drawPixels`, `getPixels`. Measured in CraftOS-PC 2.8.3 graphical, on a 51×19 terminal:

| | graphics mode (emulator) | our sub-pixels (game) |
|---|---:|---:|
| resolution | 306×171 | 102×57 |
| pixels | 52,326 | 5,814 |
| colours | 256, palettised | 16 |
| colours per cell | no cells | **2** |
| full screen | <1 ms (`drawPixels` with a string) | 0.60 ms (`canvas:render`) |
| full screen, one pixel at a time | 5.6 ms (`setPixel`) | — |

Nine times the pixels, sixteen times the colours, and the drawing goes out through a `memcpy` in C
instead of packing six sub-pixels into a teletext character. All of `pixel.lua`'s work — `cell6`,
choosing the two colours, the per-row `blit` — exists **only** because the game doesn't have this.

**And the game doesn't have it, in any version.** CC:Tweaked's `term` is `write`, `blit`, `clear`,
`setCursorPos`, the colours and the palette. There is no pixel function. Verified against the
CC:Tweaked reference: zero occurrences of `setPixel`, `drawPixels` or `GraphicsMode`.

Two observations that reinforce the decision:

- **Graphics mode ignores the WM's architecture.** It is a global pixel plane, not per window: the
  documentation itself says entering it hides the text terminal and that `window` API buffers are
  not cleared. No z-order, no taskbar, no compositor. Adopting it would mean throwing away `wm.lua`
  in that mode.
- **Even inside CraftOS-PC it isn't stable.** Headless, `term.getSize(1)` returns 51×19 and not
  306×171 — there is no pixel surface there. A drawing path that only works in the emulator's
  graphics mode wouldn't even survive `craftos.js test`.

The legitimate path to more area inside the game is a **monitor**, and wave 5 already did that: a
102×38 monitor at scale 0.5 gives 204×114 points, 3.5× the computer's screen, with the same 16
colours.

So nobody has to remember any of this, the ten functions are on `tools/lint.js`'s forbidden list.
