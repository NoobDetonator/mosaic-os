# Testing

There are four harnesses. Each catches a different class of error, and — more usefully — each has a
blind spot the next one covers. Running only one of them is how bugs get through.

```bash
node tools/lint.js            # syntax + APIs too new for the target
node tools/test.js            # kernel self-check, built-in JS emulator
node tools/craftos.js test    # both suites, on a real CC ROM
node tools/test-gateway.js    # the relay's outward-facing code, no network
node tools/test-relay.js      # the relay end to end, with a fake computer
```

Current expected output:

```
lint         71 files, 0 problems
test.js      Kernel self-check: 245 ok, 0 failures
craftos      Kernel self-check: 248 ok, 0 failures
             Regression self-check: 26 ok, 0 failures
gateway      54 ok, 0 failures
```

The emulator reports 245 and the real ROM 248. That difference is not a bug: three checks only run
where `cc.audio.dfpwm` exists, and the JS emulator's ROM doesn't have it. **A suite that quietly
skips a check with a fake pass is worse than one that skips it visibly.**

## What each harness is for

### `tools/lint.js` — the authority on compatibility

Parses every `.lua` under `os/` with `luaparse` in Lua 5.1 mode, then greps for APIs newer than
CC:T 1.101 and for CraftOS-PC-only extensions.

**This is the only thing that enforces the target version.** CraftOS-PC 2.8+ ships a *newer* ROM
than Minecraft 1.16.5 does (Lua 5.2, CC:T 1.109+), so it will happily run code that would crash
in-game. If lint and CraftOS-PC disagree about whether something is allowed, lint wins.

Blind spot: **it does not catch invalid string escapes.** `"\:"` passes `luaparse` and only fails on
a real ROM. That's why Lua files are written with an editor tool and never with a bash heredoc,
which eats backslashes.

### `tools/test.js` — fast, and it lies about hardware

Runs `tools/test/run.lua` inside `tools/emu/`, a CC implementation written in JavaScript on top of
fengari. It boots the real OS, injects synthetic events, and inspects the composed screen.

It is fast and it needs nothing installed. But its `peripheral`, `rednet` and `http` are stubs that
always fail, its clock is virtual, and it does not reproduce the palette behaviour that shapes the
compositor. Treat it as a logic check, not as proof.

Two properties worth knowing when writing tests against it:

- **Its clock only advances when a timer fires.** Two clicks separated by `proc.step()` land a full
  second apart and never count as a double-click. Use `40,4d` in `tools/debug.js`, which queues the
  events together.
- **Counting `proc.step()` calls does not port to the real ROM**, where each step waits for a real
  event. Wait for a *condition* instead — a loop that counted 80 steps passed in the emulator and
  timed out on CraftOS-PC, with nothing actually broken.

### `tools/craftos.js test` — a real ROM, two suites

Runs the same `run.lua` against [CraftOS-PC](https://www.craftos-pc.cc/), which is a genuine
CC:Tweaked implementation: real ROM, real shell, real `window` API, real `cc.audio.dfpwm`. It
catches integration bugs the JS emulator cannot.

It then runs `tools/test/regression.lua` — the cases that have broken once already: SHA-1, and the
transactional update that swaps OS files with rollback.

**The regression suite only runs here.** The JS emulator's JSON serialiser uses
`string.format("%d")`, which fengari (Lua 5.3) rejects for a float and the in-game CC (5.1) accepts
silently. That's an emulator limitation, not a product one, so the suite lives where it works
instead of the good code being bent to fit the harness.

This suite spent a while **orphaned** — present in the repo with 26 checks and no command that ran
it, covering the most dangerous part of the system. A suite nobody runs is a suite that doesn't
exist.

Blind spots: no peripherals (headless refuses to create monitors), a newer ROM than the target, and
a faster machine than the game.

### `tools/test-gateway.js` — the relay's brain, offline

Covers `relay/webdoc.js` (HTML → blocks), `relay/gateway.js` (the address filter) and
`relay/musica.js` (audio chunking). It runs **without network and without the relay running** — text
in, blocks out.

It covers the things that break quietly: accents turning to garbage on the CC terminal, a link
losing its number, a page whose `<main>` is empty, and an audio chunk one byte off.

### `tools/test-relay.js` — the protocol, end to end

Starts the relay on its own port, connects a fake computer written in JavaScript that speaks exactly
the `os/net/relay.lua` protocol, exercises the HTTP API, and shuts down. That fake is the reference
implementation of the wire contract.

## Fakes

Real hardware can't be tested outside the game, so `tools/test/` provides fakes that overwrite the
relevant globals for the whole process:

| file | fakes |
|---|---|
| `fake-periph.lua` | speaker, monitor, `http`, and a `peripheral` whose `find` returns varargs like the real one |
| `fake-reactor.lua` | a Powah reactor, with values measured on the actual server |
| `fake-cluster.lua` | a fleet: several groups, a turtle with and without fuel, a node that's offline |
| `fake-geo.lua` | a Geo Scanner, with the block names — including modded ones — that came from the server |

They exist so screenshots and tests show something real. A photo of an empty screen proves nothing,
and neither does a test that only asserts "it didn't crash".

## Screenshots

```bash
node tools/craftos.js shot calc            # opens an app through the registry and photographs it
node tools/craftos.js shot cluster --size 80x30
```

Scenarios click and type before the picture is taken. Two apps (`cluster`, `geo`) need `--size
80x30`: below 64 columns they fall back to a short layout and the version and fuel columns
disappear.

## Rules that came from being burned

- **Run `craftos.js test` *before* committing, not after.** Inverting that once pushed a red commit.
- **A smoke test looks at the screen, not just at whether the process died.** With `holdOnError` a
  crashed app stays alive showing its error, so "didn't die" proves nothing.
- **Exit code 0 is not the same as success.** Both `craftos.js test` and the JS emulator used to
  exit 0 when a script aborted before printing its result — a broken script looked like a passing
  one, and the `&&` on the command line marched on. Both now require the result line.
- **Every new app goes in the smoke list** in `tools/test/run.lua`, and every new library gets a
  `demo()` that the same file runs.
- **`craftos.js` mounts `/os` from the repository itself.** Whatever the OS writes into `/os/var`
  lands in your working tree and survives `resetComputer()`. That's why the two harnesses once
  disagreed about a seeded desktop.
