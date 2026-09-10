# Cluster

Several computers behaving as one system. This document covers the wire protocol and the design
decisions behind it; the user-facing guide is [`os/docs/13-cluster.md`](../os/docs/13-cluster.md),
in Portuguese.

## Why it exists

A CC computer is small: 1 MB of disk, a 256-event queue, and a time budget the game cuts at seven
seconds. Those limits belong to the mod, not to Lua — a different language would not lift any of
them. The only way to get more compute **without depending on a machine outside the game** is more
computers.

## The one fact that shaped everything

**When nobody is nearby, the chunk unloads and a CC computer does not pause — it loses its execution
state and restarts at an empty shell.** It does not resume where it left off.

Three consequences run through the whole design:

- **Nodes push; the master never polls.** A node that comes back to life simply resumes sending
  heartbeats, and nothing has to notice it was gone.
- **The master's node table is written to disk**, so restarting the master doesn't erase the fleet.
- **A turtle writes its position after every single step**, not at the end of a task.

## Roles

Set in Settings, under `mosaic.cluster.*`:

| setting | meaning |
|---|---|
| `role` | `mestre` (master) or `no` (node) |
| `group` | free text: `north-mine`, `farm`. One group per computer. |
| `master` | the master's computer ID; empty means broadcast |

The master is **chosen, not elected**. Distributed election is where the hard bugs live — two
masters at once, a duplicated queue — and a fleet in one player's base does not need it.

Node type (`computador`, `turtle`, `pocket`) is detected, not configured.

## The wire

Everything rides on rednet with protocol string `"mosaic"` (`netx.PROTOCOL`).

A request:

```lua
{ type = "ping", id = "<computerID>-<epoch>-<counter>", de = "<name>",
  t = <epoch>, mac = "<hmac>", ... }
```

A reply, one of:

```lua
{ id = <same id>, ok = true,  result = <table> }
{ id = <same id>, ok = false, error = "<message>" }
```

Correlation checks **both** the request id and the sender. `rednet.send` returning `true` does not
mean the message arrived, and there is no ordering guarantee — so every exchange is
request/response with a deadline, and nothing depends on one message getting through. A node that
doesn't answer is not necessarily dead.

The request id is `computerID-epoch-counter`. It used to be `os.epoch("utc")` alone: two requests in
the same millisecond produced the same id, and one's reply satisfied the other's wait. Rare, and
therefore exactly the kind of bug that shows up once a week and nobody reproduces.

### Authentication: the password signs, it does not travel

The password is **never sent**. What travels is an **HMAC-SHA1** of the message content, keyed with
the password. Someone without the password cannot produce the signature, and someone listening does
not learn the password.

This replaced a genuinely dangerous earlier design: the password used to be sent in cleartext inside
the message, and the cluster heartbeat was **broadcast** when no master was configured. The
computer's password went out to the whole network every five seconds, and any computer with an open
modem became the fleet's owner.

Signing alone is not enough, because a captured signed message would still be valid tomorrow. Two
locks handle replay:

- **`t`, the clock.** Every computer on a server reads the same `os.epoch("utc")`, so the window can
  be short — 60 seconds — without risking clock skew.
- **`id`, remembered** until it falls out of that window. A repeat is refused.

The signature also covers `de` (the sender name), checked against the sender rednet reports.
Without that, you could capture another computer's message and resend it as your own.

The signature is verified **before** the id is recorded, or anyone could fill the seen-ids list with
junk.

SHA-1 lives in `lib/update` rather than `lib/netx` because the installer runs *before* the system
exists and has to be self-contained — better to import from there than to keep a second copy of 40
lines of SHA-1 in the repository.

> Unauthenticated requests still get answers to **queries** (`ping`, `info`). Anything that changes
> state requires a valid signature. A computer with no password configured is therefore read-only,
> and that used to be silently confusing, because the settings screen had no field for the password
> at all despite the manual telling you to set one.

## Handlers

Implemented in `os/net/netd.lua`:

| type | auth | what it does |
|---|---|---|
| `ping` | no | name, id, label, OS version, uptime |
| `info` | no | free disk, peripherals, process count, in-game time |
| `whoami` | no | role, group, master, node type |
| `beat` | yes | a node's heartbeat, sent to the master |
| `inventory` | yes | the file list with SHA-1 per file |
| `exec` | yes | run Lua, return output |
| `launch` | yes | start an app |
| `chat` / `notify` | no | show a message |
| `sendFile` / `getFile` | yes | push/pull a file, chunked |
| `deleteFile` | yes | remove a file the master no longer has |
| `reboot` / `shutdown` | yes | `mosaic.lib` caches modules, so new code needs a reboot |

## Heartbeat and liveness

A node pushes a beat every `cluster.INTERVALO` (5 s) carrying: name, group, type, Mosaic version,
peripherals, and — for turtles — fuel, position and current task.

The master records the time of last contact and marks a node offline after `cluster.FALTAS` (3)
missed beats. Three is deliberate: one miss is the network, two is bad luck, three is absence.

The table is persisted to `/os/var/cluster/nos.json`.

> **Questions about the world are answered on call, not cached.** "Is there a speaker?" and "is the
> relay configured?" are computed inside the status function, not stored when the daemon starts —
> at boot there is no peripheral yet, and a cached answer would say "no speaker" forever. In-game
> this matters more than it sounds: people attach peripherals while the computer is running.

## Distributing software

The master is the only computer that needs internet.

It reads its own manifest, asks a node for its `inventory` (path → SHA-1), and pushes only the files
that differ. Then it reboots the node, because `mosaic.lib` caches modules and a freshly written
`.lua` has no effect until then.

**SHA-1 in Lua is fast enough for the whole system**, which was not obvious. The plan assumed it
would be too slow and proposed comparing version + size instead. Measured on the server (CC:T
1.101.3): **341 KB/s**, so **1.8 s** of CPU for the system's 605 KB and **147 ms** for the largest
file (`ui.lua`, 50 KB) — against a 7-second-per-resume ceiling. Four times the headroom, and
same-size-different-content stops slipping through.

Two details that are not incidental:

- **Updates are transactional.** If a write fails partway, the original file comes back. That path
  is what `tools/test/regression.lua` covers.
- **`startup.lua` is always sent last** (`cluster.diferenca` orders it that way). A node interrupted
  mid-update still boots with the old startup rather than a half-updated system.

## Turtles

A turtle is a computer that walks. Install Mosaic, equip a modem, and it joins the fleet like any
other node — with fuel and position in the panel.

`os/lib/turtlex.lua` provides capability detection, movement that reports *why* it failed (block,
mob, no fuel), and position that survives a restart. GPS when four hosts are in range; dead
reckoning otherwise.

Two API notes for the 1.101 target: `turtle.getEquippedLeft/Right` is 1.116 (so the tool is
discovered by probing instead), and `rednet.lookup`'s timeout parameter is 1.118.

`getFuelLevel()` can return the string `"unlimited"`, which is not a number — handle it.

A turtle's screen is 39×13, too small for a windowed desktop, so it opens a status panel instead.

## Physical limits, which no code can fix

- **Chunk unloading.** If nobody is nearby, the computer stops existing until someone returns. In a
  spread-out base this is problem number one; the answer is a chunk loader or accepting that the
  distant arm sleeps.
- **Modem range.** Wireless reaches 64 blocks, growing with altitude to 384 at world height. An
  *ender* modem has no limit and crosses dimensions — for a spread-out fleet it is effectively
  mandatory. The same applies to GPS, which needs four hosts in range.
- **The network is open.** Any computer in range hears the traffic. The signature stops anyone
  issuing commands in your name, but message contents travel in the clear.

## Testing

The protocol logic — roles, the node table, liveness, the diff — lives in `os/lib/cluster.lua` with
**no network and no disk in the path**, so it can be tested without standing up two computers. The
panel and the daemon are thin layers over it.

`tools/test/fake-cluster.lua` supplies a fleet with several groups, a turtle with and without fuel,
and an offline node, which is what the panel needs to know how to draw.
