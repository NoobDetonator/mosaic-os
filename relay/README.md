# Relay

A bridge between the in-game computers and your PC. It serves three things on the same port:

- **web dashboard** at `http://localhost:8765/` — watch and control the connected computers
- **HTTP API** at `/api/*` — what the dashboard and the MCP server consume
- **websocket** at `/ws/computer` — where the in-game computers connect

## Try it without Minecraft, with sound

If you just want to hear the thing working, you need none of the setup below. One command arranges
everything (relay up, local address unblocked, speaker and monitors attached) and opens a real
Mosaic you can click around in:

```bash
node tools/craftos.js live
```

## Starting it

```bash
cd relay && npm install
node relay.js
```

On first run it generates a token in `relay/.token` and prints the addresses the in-game computer
can use. Environment variables: `PORT=9000` to change the port, `TOKEN=secret` to pin the token.

## Connecting the in-game computer

In Mosaic OS: `M` menu → **Config** → fill in the URL and token → **Testar** → **Salvar relay** →
`reboot`. `boot.lua` only starts the relay daemon if `mosaic.relay.url` is already set at boot.

From the terminal it's the same:

```
set mosaic.relay.url ws://YOUR_IP:8765/ws/computer
set mosaic.relay.token the-token-from-the-file
reboot
```

The **Testar** button swaps `ws://` for `http://` and hits `/api/ping`, then tries `/api/deps` with
the token. That tests the network **without** depending on the websocket, and tells you which of
the two failed — a valid connection with a bad token used to pass silently and only show up later
as "remote control and music don't work, for no visible reason".

### Which IP to use

The connection is made by the in-game computer, reaching out **from inside the server** to your PC.
So the address has to be one the *server* can see:

| situation | what to use | works without config changes? |
|---|---|---|
| local world / server on the same machine | `ws://localhost:8765/ws/computer` | **no** — `127.*` is blocked |
| server on another machine on your LAN | your PC's LAN IP (`192.168.x.x`) | **no** — private range |
| remote server, with Radmin/Hamachi | the VPN IP (`26.x.x.x` on Radmin, `25.x.x.x` on Hamachi) | **yes** |
| remote server without a VPN | a forwarded port, or a tunnel (Cloudflare Tunnel, ngrok) | **yes** |

> **The trap that costs the most time.** CC:Tweaked blocks private ranges by default — and that
> **includes `localhost`**: the `$private` rule covers `127.0.0.0/8`, `10.*`, `172.16-31.*` and
> `192.168.*`. So testing in a local world with the relay on the same PC **does not work out of the
> box**, even though everything is on one machine. Radmin (`26.x`) and Hamachi (`25.x`) addresses
> fall outside that range, so they pass.

#### Unblocking a local address

The file is at `serverconfig/computercraft-server.toml` **inside the world folder** (that's true for
single-player too, since 1.13). Rules are tested **in order** and the first match wins — so an
allow rule for your address placed *before* the deny is enough, without opening everything else:

```toml
[[http.rules]]
    host = "127.0.0.1"
    action = "allow"

[[http.rules]]
    host = "$private"
    action = "deny"
```

Replace `127.0.0.1` with your PC's IP if the server runs on another LAN machine. Save and restart
Minecraft (or the server) — the config is read when the world loads.

The server also needs `[http] enabled = true` and `websocket_enabled = true` in
`computercraft-server.toml`, and the relay's port open in your PC's firewall (inbound, TCP).

## The gateway to the internet

The relay is also the in-game computer's route to the web. It fetches, cleans and returns ready-made
content — interpreting HTML doesn't fit inside CC (51 columns, Lua 5.1, a 7-second ceiling per step).

| route | what it does |
|---|---|
| `GET /api/web?url=` | fetches the page and returns blocks: heading, paragraph, list, code, image |
| `GET /api/busca?q=` | searches DuckDuckGo and returns results in the same format |
| `GET /api/musica?q=` | resolves a link **or a name**, converts to DFPWM, returns `{id, titulo, duracao, blocos}` |
| `GET /api/audio/<id>/<n>` | the nth 16 KiB chunk of raw audio |
| `GET /api/deps` | reports what's installed on this machine |

All require the token except `/api/ping`.

Text comes back **without accents** on purpose: the CC terminal draws byte by byte, with no UTF-8,
and without stripping them every Portuguese page turns to garbage on screen.

Finding the article is not just reading `<main>`: Wikipedia puts its 143-language selector inside
`<main>`, so the rule is "the largest candidate by text wins — unless a candidate **inside** it
keeps 60% of that text, in which case it only lost the frame".

**Local network addresses are blocked.** The relay runs on your machine; a computer on the server
asking for `192.168.0.1` would turn it into a tunnel into your home network. The block is by
literal IP — a *hostname* that resolves to a private address still passes, so don't expose the
relay to people you don't know.

### Music needs two programs

`yt-dlp` (downloads) and `ffmpeg` 5.1+ (converts to DFPWM). Without them the rest of the relay keeps
working normally, and `/api/musica` says which one is missing.

```bash
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg
```

Converted audio is cached in `relay/cache/` and reused: the same song is only downloaded once.
Searching by name uses `ytsearch1:`, like a music bot — you either paste the link or type the name.

**Preparing a song takes 20–60 seconds, and a CC:T HTTP request dies at 30.** So `/api/musica` does
not wait: it starts the job, answers `{estado, espere=true}` immediately, and the client asks again
until it's ready.

Two things learned the hard way, both encoded in `musica.js`:

- **YouTube hides the audio URL behind a JavaScript challenge.** Without a JS runtime the download
  fails with HTTP 403 while search still works — a very misleading trail. The relay is already Node,
  so it passes `process.execPath` to yt-dlp as the runtime: nothing extra to install.
- **Piping `yt-dlp -o -` into ffmpeg does not work.** The stream comes out fragmented and ffmpeg
  can't read that from a non-seekable pipe ("Invalid data found when processing input"). An
  intermediate file is written and deleted.

## MCP: letting Claude Code drive the computer

```bash
claude mcp add --scope user mosaic -- node /path/to/relay/mcp.js
```

It's **stdio**, not HTTP — pointing an HTTP MCP client at `http://localhost:8765/mcp` won't work,
that route doesn't exist (`relay.js` returns 404 for anything outside `/api/` and `/`). `mcp.js`
reads the relay address from `MOSAIC_RELAY` (default `http://localhost:8765`) and the token from
`MOSAIC_TOKEN` (default: `relay/.token`).

Exposed tools: `list_computers`, `computer_info`, `exec_lua`, `run_shell`, `read_file`,
`write_file`, `list_files`, `delete_file`, `screenshot`, `launch_app`, `list_processes`,
`kill_process`, `notify`, `send_input`.

## Testing without the game

```bash
node tools/test-relay.js      # starts the relay, fakes a computer connecting, exercises the API
node tools/test-gateway.js    # HTML→blocks, address filter, audio chunking — no network needed
```
