# EUV Music Library Tool

Add your own music to Europa Universalis V's dynamic soundtrack on Windows 11. Tracks can play during war, peace, both, and optionally for one of EU5's broad cultural music groups.

The tool creates a local mod under your EU5 Documents folder. It does not edit the game installation or redistribute your audio.

## Status

This is an early Windows-only release. It targets Steam EU5 1.x and the Wwise sound-bank formats used by EU5 1.3 and 1.4. A later EU5 update may require a converter update.

## Requirements

- Europa Universalis V installed through Steam on Windows 11
- Windows PowerShell 5.1, included with Windows 11
- [FFmpeg](https://ffmpeg.org/)
- Internet access during the first sync so the pinned converter and its audio dependencies can be downloaded

Install FFmpeg in Windows Terminal:

```powershell
winget install --id Gyan.FFmpeg
```

Restart Steam and any open terminals after installation.

## Quick start

1. Download this repository and extract it to a permanent folder.
2. Double-click **EUV Music Library Tool.cmd**.
3. Choose **Open music folder** and copy your `.mp3`, `.flac`, `.wav`, `.ogg`, `.m4a`, `.aac`, `.opus`, or `.wma` files into it.
4. Choose **Sync library**. New tracks default to playing during both war and peace.
5. Start EU5, open **Mods**, enable **EUV Music Library**, and restart the game.

After the first setup, **Sync and launch EU5** updates the library before starting the game.

The source folder is normally:

```text
Documents\Paradox Interactive\Europa Universalis V\music_library\tracks
```

The generated local mod is normally:

```text
Documents\Paradox Interactive\Europa Universalis V\mod\euv_music_library
```

Windows' actual Documents location is detected, including a redirected OneDrive Documents folder.

## Assign tracks

Choose **Edit track assignments** to open `library.json`. Each track has this shape:

```json
{
  "file": "My Album/Example.flac",
  "enabled": true,
  "mood": "both",
  "culture": ""
}
```

`mood` accepts:

- `both`: add the track to war and peace playlists
- `war`: play only while the player is at war
- `peace`: play only while the player is at peace

`culture` is optional. Leave it empty for no cultural restriction, or use one of:

- `european`
- `east_asian`
- `african`
- `middle_east`
- `indian`
- `north_american`
- `south_american`

A culture-assigned track is also included according to its `mood`. Culture routing gives it an additional opportunity to play when that cultural playlist is active.

Files removed from the tracks folder are removed from `library.json` on the next sync. Set `enabled` to `false` to keep a file in the folder without adding it to the game.

## How it works

EU5 uses Wwise sound banks rather than a folder of ordinary music files. This project manages the library, generates stable track identifiers, creates EU5 mod metadata, and rebuilds the sound-bank manifest.

For the low-level OGG-to-WEM conversion and playlist-bank patching, the tool downloads a pinned, SHA-256-verified copy of [`komoreb11/eu5-music-converter`](https://github.com/komoreb11/eu5-music-converter) directly from its original repository. That project currently has no declared software license, so its implementation is not copied into this repository. The downloaded script is adapted locally in the user's cache for personal source files.

Generated audio is stored only on the user's computer. The tool never uploads music.

## Behavior and limitations

- Added music plays alongside the original EU5 soundtrack.
- EU5's **Next** control can skip an added track.
- Custom titles do not currently appear in the in-game music-player list.
- Disable other mods that replace or patch `sb_music_logic.bnk`; only one can reliably control those playlists.
- Run Sync again after a major EU5 update. The tool builds from the currently installed EU5 bank rather than editing it.
- Filenames may contain spaces and Unicode. The `|` character is unsupported in a source filename or folder name.
- Keep backups of music you care about. The generated mod contains converted copies, not originals.

## Command-line actions

The launcher accepts an optional action:

```bat
"EUV Music Library Tool.cmd" -Action Sync
"EUV Music Library Tool.cmd" -Action SyncAndLaunch
"EUV Music Library Tool.cmd" -Action OpenLibrary
"EUV Music Library Tool.cmd" -Action EditManifest
```

Players who launch EU5 with a custom `--userdir` can point the tool at the same folder:

```bat
"EUV Music Library Tool.cmd" -Action Sync -Eu5UserDir "D:\Games\EU5 User Data"
```

## Security and provenance

The converter is pinned to commit `6e6480d442c365bec7cd2a5dde00966df4f89e81` and must match SHA-256 `2f5d7cafc616668f19414077fba8189916c3e350c96b57a7d3f7b002b4c139cf`. A mismatch stops the sync.

The first conversion also downloads the encoder components required by the upstream converter. Review that project's source and download behavior before running it if you need a fully audited dependency chain.
