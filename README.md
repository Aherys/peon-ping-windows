# peon-ping-windows

![Windows](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude_Code-hooks-blueviolet)

**Your Peon works on Windows too.** Warcraft III voice lines for Claude Code -- now ported to PowerShell.

---

## The Problem

Claude Code doesn't beep, ping, or notify you when it finishes working, needs permission, or hits an error. You tab away, forget about it, and come back 10 minutes later to find it's been waiting on you the whole time.

**peon-ping-windows** fixes that by playing classic Warcraft III Peon voice lines at key moments -- and sending Windows toast notifications when your terminal isn't focused.

> *"Something need doing?"* -- Your Peon, after Claude finishes and you're still on Reddit.

---

## Install

### From a cloned repo (recommended)

```powershell
git clone https://github.com/Aherys/peon-ping-windows.git
cd peon-ping-windows
powershell -ExecutionPolicy Bypass -File download-sounds.ps1
powershell -ExecutionPolicy Bypass -File install.ps1
```

This will:
1. Download all 7 sound packs (111 audio files) from the original peon-ping repo
2. Copy everything to `~/.claude/hooks/peon-ping/`
3. Register hooks in `~/.claude/settings.json`
4. Add `peon` command to your PowerShell profile

---

## What You'll Hear

| Event | When | What the Peon Says |
|-------|------|---------------------|
| **Session Start** | You open Claude Code | *"Ready to work?"* |
| **Prompt Submit** | You send a message | *"Work, work."* (acknowledge) |
| **Task Complete** | Claude finishes | *"Something need doing?"* |
| **Permission Needed** | A tool needs approval | *"What you want?"* |
| **Idle** | Claude is waiting for you | Toast notification + tab title change |
| **Annoyed** | You spam prompts too fast | *"Me busy, leave me alone!"* (replaces normal prompt) |

---

## Quick Controls

### CLI Commands

```powershell
peon --pause       # Silence the Peon (sounds off, hooks still run)
peon --resume      # Let the Peon speak again
peon --toggle      # Toggle pause/resume
peon --status      # Check if paused or active
```

---

## Configuration

Edit `~/.claude/hooks/peon-ping/config.json`:

```json
{
  "active_pack": "peon",
  "volume": 0.5,
  "enabled": true,
  "categories": {
    "greeting": true,
    "acknowledge": true,
    "complete": true,
    "error": true,
    "permission": true,
    "resource_limit": true,
    "annoyed": true
  },
  "annoyed_threshold": 3,
  "annoyed_window_seconds": 10
}
```

| Option | Default | Description |
|--------|---------|-------------|
| `active_pack` | `"peon"` | Which sound pack to use (see below) |
| `volume` | `0.5` | Volume level, 0.0 - 1.0 (matches macOS scale) |
| `enabled` | `true` | Master on/off switch |
| `categories.*` | `true` | Enable/disable individual sound categories |
| `annoyed_threshold` | `3` | Number of rapid prompts before the Peon gets annoyed |
| `annoyed_window_seconds` | `10` | Time window (seconds) for counting rapid prompts |

---

## Sound Packs

| Pack | Character | Universe |
|------|-----------|----------|
| `peon` | Orc Peon | Warcraft III |
| `peon_fr` | Orc Peon (French) | Warcraft III |
| `peasant` | Human Peasant | Warcraft III |
| `peasant_fr` | Human Peasant (French) | Warcraft III |
| `ra2_soviet_engineer` | Soviet Engineer | Red Alert 2 |
| `sc_battlecruiser` | Battlecruiser | StarCraft |
| `sc_kerrigan` | Sarah Kerrigan | StarCraft |

Switch packs by changing `active_pack` in `config.json`:

```json
{
  "active_pack": "sc_kerrigan"
}
```

---

## Windows-Specific Features

### Toast Notifications

When Claude needs attention (permission prompt or idle), peon-ping-windows sends a native **Windows toast notification** using the WinRT `Windows.UI.Notifications` API. Toast notifications always appear regardless of which window is focused, so you never miss an alert. Works on Windows 10 and later without any extra modules.

### Windows Terminal Tab Titles

Tab titles update to reflect Claude's state:

| State | Tab Title |
|-------|-----------|
| Session started | `myproject: ready` |
| Working | `myproject: working` |
| Done | `* myproject: done` |
| Needs permission | `* myproject: needs approval` |

The `*` prefix makes it easy to spot tabs that need your attention.

### Audio Playback

`.wav` files are played using `System.Media.SoundPlayer.PlaySync()` for guaranteed full playback. For other formats (MP3, etc.), an STA runspace with `System.Windows.Media.MediaPlayer` is used with volume control. Peon voice lines are short (<2s), well within the 10-second hook timeout.

---

## Differences from macOS

| Feature | macOS (`peon.sh`) | Windows (`peon.ps1`) |
|---------|-------------------|----------------------|
| Shell | Bash | PowerShell 5.1+ |
| Audio player | `afplay` | `SoundPlayer` (WAV) / `MediaPlayer` (other) |
| Volume scale | 0.0 - 1.0 (float) | 0.0 - 1.0 (float) |
| Notifications | `osascript` / AppleScript | WinRT toast (`Windows.UI.Notifications`) |
| Notifications | Only when terminal unfocused | Always shown |
| Config parsing | Python + `eval` | Native `ConvertFrom-Json` |
| Background audio | `nohup afplay &` | `SoundPlayer.Play()` / STA runspace |
| CLI alias | Shell alias in `.zshrc` | PowerShell function in `$PROFILE` |
| Hook command prefix | `bash` | `powershell -ExecutionPolicy Bypass -File` |
| Agent detection | Python state file | Native PowerShell JSON state |
| Update check | `curl` | `Invoke-RestMethod` |

---

## Requirements

- **Windows 10** or later (Windows 11 recommended)
- **PowerShell 5.1+** (included with Windows 10/11)
- **Claude Code** with hooks support
- **.NET Framework** (included with Windows -- needed for audio playback)

---

## How It Works

peon-ping-windows is a **Claude Code hook** -- a script that runs automatically at key events during your Claude Code session.

1. **Registration**: The installer adds hook entries to `~/.claude/settings.json` for four events: `SessionStart`, `UserPromptSubmit`, `Stop`, and `Notification`.

2. **Invocation**: When an event fires, Claude Code runs:
   ```
   powershell -ExecutionPolicy Bypass -File ~/.claude/hooks/peon-ping/peon.ps1
   ```
   It passes event data as JSON on **stdin** with these fields:
   - `hook_event_name` -- which event fired
   - `notification_type` -- for Notification events: `permission_prompt` or `idle_prompt`
   - `cwd` -- current working directory
   - `session_id` -- unique session identifier
   - `permission_mode` -- current permission mode (used for agent detection)

3. **Processing**: The script reads config, maps the event to a sound category, picks a random sound from the active pack (avoiding repeats), and plays it asynchronously.

4. **Notifications**: For permission/idle events, a Windows toast notification is always sent so you never miss it.

5. **Timeout**: Hooks have a 10-second timeout. Peon voice lines are <2s, so playback completes well within limits.

---

## Uninstall

```powershell
& "$env:USERPROFILE\.claude\hooks\peon-ping\uninstall.ps1"
```

This removes the hook registrations from `settings.json`, deletes the peon-ping directory, and removes the CLI alias from your PowerShell profile.

---

## Credits

- Original [peon-ping](https://github.com/tonyyont/peon-ping) by [@tonyyont](https://github.com/tonyyont) -- the macOS version that started it all
- Windows port by the peon-ping-windows contributors
- Sound effects from Warcraft III, StarCraft, and Red Alert 2 are property of their respective owners (Blizzard Entertainment, EA). Used here for personal, non-commercial fun.

---

## License

[MIT](LICENSE) -- Work, work.
