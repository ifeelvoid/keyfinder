# Use KeyFinder with an AI assistant

KeyFinder includes `keyfinder-mcp`, a Model Context Protocol (MCP) server. An AI assistant
that supports MCP (the ChatGPT desktop app, Claude Desktop, Codex, Cursor) can call it to
analyze your music and act as a DJ and production assistant:

- "Build a 60-minute set from my Techno folder that peaks around minute 40."
- "What in this folder mixes out of this track?"
- "How do I make this loop fit my 8A, 124 BPM project?"

**Privacy:** analysis runs on your Mac. Audio never leaves your computer; the assistant
receives only the results (file names, keys, tempos). KeyFinder reads only the folders you
allow (your Music folder by default; see below), and never changes or deletes files.

The server is at:

```
/Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp
```

## ChatGPT desktop app

Open **Settings → MCP servers → Add server**. Name it `keyfinder`, choose **STDIO**, enter
the path above as the command, save, then click **Restart**. The same setting can go in
`~/.codex/config.toml`, which the ChatGPT desktop app shares with Codex:

```toml
[mcp_servers.keyfinder]
command = "/Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp"
```

ChatGPT on the web cannot reach programs on your Mac; use the desktop app.

## Claude Desktop

Open **Settings → Developer → Edit Config** and add KeyFinder to
`claude_desktop_config.json`, then restart Claude:

```json
{
  "mcpServers": {
    "keyfinder": {
      "command": "/Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp"
    }
  }
}
```

## Choosing which folders assistants can read

Open **KeyFinder → Settings… → AI Assistant** (⌘,). Click **Add Folder…** to allow a folder
(a sample library, an external drive), select one and click **Remove** to take it away, or
**Reset to Music Folder**. Changes apply to the assistant's next request; no restart needed.
If the assistant reports a path is "outside the folders KeyFinder may read", add it here.

The same tab has **Copy ChatGPT Setup** and **Copy Claude Setup** buttons that copy the
configuration shown above with the correct path filled in.

Advanced: `KEYFINDER_MCP_ROOTS` (colon-separated) adds folders on top of the list, for
assistants whose configuration can set environment variables.

## What the assistant can do

| Tool | What it does |
|---|---|
| `analyze_track` | Key, Camelot, BPM, confidence, energy, key changes for one file |
| `analyze_folder` | The same for every audio file in a folder (up to 500 per request) |
| `find_compatible` | Tracks that mix out of a track: same key, ±1, relative major/minor, within a BPM tolerance |
| `build_set` | An ordered harmonic set with an energy shape: build, flat or peak |
| `fit_sample` | Semitones to transpose and time-stretch needed to fit a sample to your project |

Results are cached, so a folder analyzes slowly once and quickly after that. Tempo
matching treats half- and double-time as the same groove.

## If the assistant cannot start KeyFinder

- Check the path: run `/Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp --version`
  in Terminal. It should print the version.
- If macOS says the program cannot be verified, open **System Settings → Privacy &
  Security** and allow it, then restart the assistant.

