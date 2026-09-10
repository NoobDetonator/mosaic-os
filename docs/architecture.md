# Architecture

How Mosaic OS is put together, and why the odd-looking parts are the way they are. Most of the
strangeness here comes from one place: **CC:Tweaked is not a normal Lua environment.** It has 16
colours, a 51×19 terminal, 1 MB of disk, no preemption, and it kills any program that runs for 7
seconds without yielding.

## Boot

```
startup.lua      pcall(shell.run, "/os/boot.lua"), falling back to the ROM shell
os/boot.lua      settings → theme → palette → wm.init → proc.init → desktop → daemons → proc.run()
```

`startup.lua` is deliberately tiny and defensive: if `boot.lua` throws, you land in the ROM shell
instead of an unbootable computer. Creating `/os/safemode` skips the boot entirely.

**Order matters in exactly one place, and it cost time to learn.** The palette is applied to the
root terminal *before* `wm.init` creates the canvas. The reason is in the compositor, below.

## The compositor

Three layers: the real terminal (`root`), one full-screen invisible `window` used as an offscreen
canvas, and one `window` per process, all children of the canvas.

Each frame, `wm.render` clears the canvas, draws every process's window into it bottom-to-top, adds
the taskbar and toasts, and then pushes the canvas to the screen **line by line, only where it
changed**.

That last part is not an optimisation for its own sake. The obvious way to show the canvas would be
`canvas.setVisible(true)` — but CC's `window` API **snapshots its parent's palette when created and
re-pushes that snapshot on every redraw**. Using `setVisible` on the canvas would mean 16
`setPaletteColour` calls per frame, silently undoing the Win95 palette. Comparing lines avoids that
and, as a bonus, makes a still frame cost one `blit` (the clock) instead of nineteen.

Two consequences worth knowing:

- **The palette goes on the root terminal, never on a window.** A CC window keeps its palette to
  itself. This works only because the compositor never re-pushes a palette — it just calls `blit`.
- **Anything that touches `wm.resize` must clear `wm.last`**, or stale lines stay on screen.

App windows are copied into the canvas with `setVisible(true); setVisible(false)`, because
`Window.redraw()` does nothing while a window is invisible.

## Processes

A process is a coroutine, plus a window, plus some geometry. `proc.resume` swaps the global
`term.redirect` around each resume and writes it back afterwards:

```lua
local prevTerm = term.redirect(p.term)
local ok, res = coroutine.resume(p.co, ...)
p.term = term.redirect(prevTerm)
```

That write-back is what makes a program that redirects its own terminal keep that redirect across
resumes — and it is the whole mechanism behind [wall screens](#wall-screens).

Scheduling is **cooperative**. There is no preemption, so every loop must yield (`os.pullEvent`,
`sleep`) or CC aborts the computer after ~7 seconds. Events are routed rather than broadcast:
keyboard goes to the focused process, mouse goes through hit-testing, and anything the kernel
doesn't recognise is broadcast to everyone.

`spec.term` lets a process have a terminal that isn't its desktop window. The relay daemon uses that
for a headless remote shell; wall screens use it for monitors.

## Widgets

`os/kernel/ui.lua` is the house toolkit — there is no Basalt here, by rule.

The part worth understanding is **anchored layout**. A widget declares where it wants to be, and
`Form:layout` resolves that against the current terminal size:

| key | meaning |
|---|---|
| `w = 20` | 20 columns |
| `w = -3` | terminal width minus 3 |
| `w = "fill"` | the whole width |
| `right = 0` | flush to the right edge |
| `bottom = 0` | the last row |
| `above = other` | the row just above another widget |
| `fillTo = other` | height up to where another widget starts |

Three traps live here, all of them found the hard way:

- **`x` is not an anchor key.** Only `w`, `h`, `right`, `bottom`, `above` and `fillTo` are. `x = -20`
  does not stick to the right — it draws off-screen, silently.
- **`w = "fill"` and `w = -3` are a string and a negative number until `Form:layout` runs.** Reading
  `widget.w` before that gives you the string, and `"fill" - 2` crashes the app.
- **`fillTo` only sees widgets added earlier**, so order of `f:add` matters.

`Form:draw` re-runs the layout whenever the terminal reports a different size, with no `term_resize`
event needed. That is why pointing a form at a different-sized surface just works — and it's why
apps survive being sent to a monitor without knowing anything about monitors.

Forms scroll by themselves: `Form:draw` shifts each widget's `y` while drawing and puts it back, and
`Form:handle` adds the scroll offset to mouse coordinates. No widget knows scrolling exists.
`pinned = true` opts a widget out — that's how fixed tab bars and footers are built.

## Drawing

`os/lib/pixel.lua` gives roughly 2× the resolution the terminal advertises, using CC's teletext
characters: **2×3 sub-pixels per cell**, so a 51×19 screen becomes 102×57 points.

The hard limit is that **a cell holds exactly two colours and no text**. When six sub-pixels contain
three or more colours, the two most frequent win and the rest are approximated. That single
constraint explains a lot of decisions elsewhere — for instance, why 3D lighting is per-face and not
per-vertex: a smooth gradient would just increase the number of three-colour cells.

`os/lib/three.lua` builds on that: meshes with chainable transforms, orbit and free cameras,
near-plane clipping, and a scanline rasteriser with a 1/z depth buffer. Its hot path deliberately
**touches no table** — see [3d-performance.md](3d-performance.md) for what that's worth in
milliseconds, and for the 40× gap between the bench and the actual game.

## Wall screens

An app "on a wall" is an app whose `p.term` **is** the monitor. It does not go through the
compositor at all — no z-order, no taskbar, no window on top.

That was a deliberate simplification, and the reason is a platform limit: `monitor_touch` is a
right-click and nothing else. There is no drag, no release, and no keyboard. Managing overlapping
windows on a wall would be bad, not merely hard — so one monitor shows one app, full screen.

It works because of two pieces that already existed: `p.term` can be any terminal, and `Form:draw`
re-lays itself out when the size changes. `wm.render` skips any process with `p.monitor` set, or the
desktop would show that window frozen at its last frame.

Monitors have their own palette, so it has to be applied per monitor.

## Networking

Three separate things, often confused:

| | what it is | needs |
|---|---|---|
| `os/net/netd.lua` | rednet: computer ↔ computer, inside the game | a modem |
| `os/net/relay.lua` | websocket to a Node server on your PC | `http` enabled |
| `os/net/musicd.lua` | the music queue and playback | a speaker + the relay |

The cluster layer (roles, groups, heartbeats, software distribution) lives inside `netd` rather than
in a second daemon, because `rednet_message` is broadcast to every process and two daemons answering
the same request would be a mess. See [cluster.md](cluster.md).

The relay is what makes the browser and music possible: interpreting HTML or transcoding audio does
not fit inside a CC computer, so a Node process on your PC does the work and sends ready-made
results. See [relay/README.md](../relay/README.md).

## Persistence

State lives in three places, with different lifetimes:

- **`settings`** (the ROM API, saved to `/.settings`) — user configuration, all keys under
  `mosaic.*`, all defined in `boot.lua`.
- **`/os/var/`** — runtime state as JSON: which shortcuts have been seeded, the installed version,
  the cluster's node table, a turtle's position, logs.
- **`/home/`** — the user's files. The desktop *is* `/home/desktop`, so a shortcut is a real file.

Anything a chunk unload could interrupt must be on disk, not in memory. When nobody is nearby, a CC
computer **does not pause** — it loses its execution state and restarts at an empty shell. That fact
shapes the whole cluster design, and it's why a turtle writes its position after every single step.

## Where to look

| path | what |
|---|---|
| `os/boot.lua` | startup order and settings definitions |
| `os/kernel/proc.lua` | scheduler, event routing, the global `mosaic` API |
| `os/kernel/wm.lua` | compositor, z-order, taskbar, hit testing |
| `os/kernel/ui.lua` | widgets, anchored layout, modals |
| `os/lib/` | libraries — see the table in the README |
| `os/apps/registry.lua` | what an app is, and what opens which file type |
| `tools/` | lint, emulator, test harnesses, bench, manifest generator |
