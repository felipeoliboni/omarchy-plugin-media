# Now Playing

A now-playing bar widget for [Omarchy](https://omarchy.org) 4.

> **Fork notice.** This is a personal fork of
> [sumdahl/omarchy-plugin-media](https://github.com/sumdahl/omarchy-plugin-media)
> (plugin id `io.github.sumdahl.media`). All credit for the original design —
> the popup, the MPRIS fallback, the keyboard navigation — goes to Sumiran
> Dahal; see [LICENSE](LICENSE). This fork changes how the widget sits in the
> bar (see below) and adds a right-click appearance menu. It is not affiliated
> with, and does not track, the upstream repository.

Instead of a single icon, it shows the current track inline in the bar —
icon + "artist — title" — and opens a popup with the album art, track detail,
a seek bar, and the transport controls when clicked.

## Features

- **Inline track label** in the bar: icon + "artist — title", elided only
  past the configurable widget width (see [Appearance](#appearance)).
- **Album art**, rendered at the display's real pixel density, with a graceful
  placeholder while it loads or when the player supplies none. Optional both
  in the bar (off by default) and in the popup (always on).
- **Track detail** — title, artist, album, and a dim secondary line for album
  artist and track number, each shown only when it exists and differs from
  what's above it.
- **Seek bar** with elapsed and total time, driven by a poll timer while the
  popup is open (Spotify never emits MPRIS `Seeked`, so a plain binding would
  sit still).
- **Transport** — shuffle, previous, play/pause, next, repeat. Repeat cycles
  off → playlist → track, matching Spotify's own control.
- **Source picker** listing every running player when there is more than one,
  so you can switch which one the popup controls.
- **Bar shortcuts** — middle-click to play/pause, scroll to skip tracks,
  right-click for appearance, without opening the popup at all.
- **Spotify accent**, optional: tints the popup's accent to Spotify green
  while Spotify is the active player. Falls back to your theme accent for
  everything else.
- **Keyboard** — a global hotkey to summon the popup (see
  [Keybindings](#keybindings)), then ←/→ to skip, ↑/↓ to move through the
  sources, Enter to activate, Esc to close.

Works with any MPRIS player: Spotify, mpv, Firefox, Chromium, VLC, and so on.

## Install

```bash
omarchy plugin add https://github.com/felipeoliboni/omarchy-plugin-media.git --enable
```

Pick a bar section when prompted (`left` is the default here). Then enable it
later, move it, or change its settings from **Omarchy menu → Setup → Bar**.

Optionally add the `SUPER + CTRL + M` hotkey — see [Keybindings](#keybindings).

## Remove

```bash
omarchy plugin remove felipe.media
```

That deletes `~/.config/omarchy/plugins/felipe.media/` and drops the widget
from the bar. Nothing else on your system is touched.

## Appearance

**Right-click the widget** to open a small settings popup:

| Setting | Default | What it does |
|---|---|---|
| Show album art | off | Small cover thumbnail in the bar, before the icon. |
| Show music icon | on | The play/pause note before the track name. |
| Widget width | `400px` | Maximum width of the "artist — title" label before it elides with `…`. |

These three also show up under **Omarchy menu → Setup → Bar → Now Playing**,
since they're declared in `manifest.json`'s `barWidget.schema` — the
right-click menu is just a faster way to reach the same settings.

## Settings

The rest of the settings only affect the popup (open it with a left-click),
and are reachable from **Omarchy menu → Setup → Bar**:

| Setting | Default | What it does |
|---|---|---|
| `artSize` | `96` | Album art edge length in pixels (48–200, in steps of 8). |
| `showProgress` | `true` | Show the seek bar and the elapsed/total times. |
| `showSourcePicker` | `true` | List the other running players at the bottom of the popup. |
| `spotifyAccent` | `true` | Tint the accent Spotify green while Spotify is the active player. |

## Keybindings

Omarchy plugins cannot install keybindings — a plugin only draws itself, it never
edits your Hyprland config. So this is one manual step, and it is worth doing: the
popup is much more useful when you can summon it without reaching for the mouse.

Add this to `~/.config/hypr/bindings.lua`, then `hyprctl reload`:

```lua
o.bind("SUPER + CTRL + M", "Now Playing", "omarchy-shell shell toggle felipe.media")
```

`SUPER + CTRL + M` now toggles the popup open and closed. The same call works from a
script or another terminal:

```bash
omarchy-shell shell toggle felipe.media
```

`omarchy-shell` ships with Omarchy and forwards an IPC message to the shell process
that is already running — it does not launch anything, and it needs no extra software.

### Once the popup is open

| Key | Action |
|---|---|
| `←` / `→` | Previous / next track |
| `↑` / `↓` | Move through the source list |
| `Enter` | Switch to the selected source |
| `Esc` | Close |

### Without opening the popup

The bar widget responds directly: **middle-click** to play/pause, **scroll** to
skip tracks, **right-click** for appearance.

### Optional: media keys without the popup

If you also want plain transport bindings — the kind that work with no shell popup
involved — the usual approach is [`playerctl`](https://github.com/altdesktop/playerctl),
available from the Arch repositories as the `playerctl` package. **This plugin does not
install it, require it, or call it.**

```lua
o.bind("SUPER + ALT + P", "Play/Pause",    "playerctl play-pause")
o.bind("SUPER + ALT + N", "Next Track",    "playerctl next")
o.bind("SUPER + ALT + B", "Previous Track", "playerctl previous")
```

**This is entirely optional and separate from the plugin.** `playerctl` is *not* a
dependency of this widget — the widget never calls it, and everything above works
without it installed. It is listed here only because these bindings are a common
companion to a now-playing widget, and both talk to the same MPRIS players, so they
stay in sync with each other.

## Requirements

- **Omarchy 4** (Quickshell-based shell)
- **Any MPRIS-capable media player** — Spotify, mpv, Firefox, Chromium, VLC, and so on

That is the complete list. No `playerctl`, no daemons, no Python, no network service.

## How it works, and what it does not do

This plugin is **presentation only**. All MPRIS work is delegated to Omarchy's
first-party `omarchy.media` service, which it reads through
`shell.firstPartyServiceFor("omarchy.media")` — the same handle the built-in media
widget uses, when the host exposes it. Omarchy 4.0.3 only exposes that service to
plugins declaring kind `"bar"`, which this one does not (it's a `"bar-widget"`), so
in practice it falls back to `MediaFallback.qml`, a small adapter over Quickshell's
own MPRIS binding (`Quickshell.Services.Mpris`) — not an Omarchy API, so it isn't
subject to that restriction. Either way, this plugin does not clone, replace, or
disable the first-party service, and the built-in media widget is unaffected if you
also have it enabled.

Consequently:

- **No subprocesses are spawned** — no `playerctl`, no shell-outs, nothing on any hot path.
- **No network access.** Album art is loaded from whatever URL the player itself
  advertises over MPRIS (usually a local file, or the player's own CDN); no other
  requests are made.
- **No file writes.** Settings live in Omarchy's own bar config, written by Omarchy.
- **No privilege escalation.** The plugin requests no elevated permissions, manages no
  services, and ships no bundled binaries.

Like every Omarchy plugin, it runs unsandboxed inside the long-lived `omarchy-shell`
process. The whole thing is one QML file, one plain-JS helper file, and a manifest —
read them.

## Publishing to the Omarchy Plugins marketplace

Notes for whoever maintains this fork, from
[plugins.omarchy.org/publish.html](https://plugins.omarchy.org/publish.html) (the
official marketplace, repo `omacom/omarchy-plugin-marketplace`):

1. **The repo must be public** (it already is) and have, at its root: a valid
   `manifest.json`, a `README.md`, and a `LICENSE`. Install/remove must be safe —
   satisfied above.
2. **Required `manifest.json` fields**: `schemaVersion`, `id` (unique, namespaced —
   `felipe.media` qualifies), `name`, `version`, `author`, `description`, `kinds`,
   `entryPoints`. All present in this repo's `manifest.json`.
3. **Validate before submitting**:
   ```bash
   omarchy plugin clone   # sanity-check the clone path works
   omarchy plugin validate /path/to/this/repo
   ```
4. **Submit** via the "Submit your plugin" GitHub issue form in
   `omacom/omarchy-plugin-marketplace` — repo link, category, tags. A maintainer
   approves after automated checks run against the current commit.
5. The marketplace explicitly does **not** audit plugin security — it validates the
   listing (manifest shape, repo structure), not the code. Say so plainly if anyone
   asks whether a marketplace listing means the plugin was reviewed: it doesn't.

Not yet done here: opening that submission issue. `git log` on this repo is the
source of truth for what's actually been pushed — check it before assuming this
section is up to date.

## License

MIT. See [LICENSE](LICENSE). Copyright retained by the original author, Sumiran
Dahal, per the MIT license terms — this fork's changes do not relicense it.
