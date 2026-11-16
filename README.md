# EUV Music Library Tool

A small Windows 11 utility that adds personal MP3 files to Europa Universalis V. Imported songs join EU5's existing war and peace playlists and are registered in the native Music Player with a title and artist.

The tool creates a local EU5 mod. It does not overwrite the Steam installation, run in the background, change Steam launch options, upload music, or include copyrighted audio.

## Current validation status

The library manager, MP3 metadata reader, stable identifiers, generated registrations, transaction recovery, and upstream-converter adaptation have automated checks. The generated mod still needs an end-to-end test on Windows 11 with a current EU5 installation before native-player and dynamic-playback support should be considered verified in game.

The converter currently understands the EU5 sound-bank versions documented for game versions 1.3 (`150`) and 1.4 (`172`). It stops on an unknown version and restores the previous generated mod.

## Requirements

- Windows 11
- Europa Universalis V installed through Steam
- Windows PowerShell 5.1, included with Windows 11
- [FFmpeg](https://ffmpeg.org/)
- Internet access during the first conversion to retrieve pinned conversion components

Install FFmpeg in Windows Terminal:

```powershell
winget install --id Gyan.FFmpeg
```

Restart the utility after installation.

## Use

1. Download this repository and extract it to a permanent folder.
2. Double-click **EUV Music Library Tool.cmd**.
3. Select **Open Music Folder** and copy MP3 files into the folder. Album subfolders are allowed.
4. Return to the utility and select **Refresh**.
5. Review or edit each title and artist, then choose **War**, **Peace**, or **Both**. New songs default to **Both**.
6. Select **Convert and Implement**.
7. Enable **EUV Music Library** in EU5's Mods screen once, then launch EU5 normally through Steam.

The managed source folder is normally:

```text
Documents\Paradox Interactive\Europa Universalis V\music_library\tracks
```

The generated local mod is normally:

```text
Documents\Paradox Interactive\Europa Universalis V\mod\euv_music_library
```

Windows' configured Documents location is detected, including OneDrive redirection. Players who use EU5's `--userdir` option can pass the same location to the utility with `-Eu5UserDir`.

## Metadata and identity

The utility reads ID3v2 and ID3v1 title and artist tags. When tags are absent, a filename such as `Artist - Title.mp3` supplies both values; other filenames become the title with `Unknown Artist`.

Each song receives a persistent internal identifier. Editing metadata or replacing the contents of the same managed file does not duplicate the track. A rename also keeps the identifier when the MP3 contents are unchanged.

**Remove Song** explicitly sends the selected managed MP3 copy to the Windows Recycle Bin. Files outside the managed folder are never touched.

## Generated integration

One converted WEM file and one Wwise event identity are used for both playback paths:

- dynamic insertion into the current EU5 war and/or peace playlist;
- native Music Player registration, search, title localization, composer, and performer fields.

The initial release maps the MP3 artist to both EU5's composer and performer fields because MP3 artist tags do not distinguish those roles. English localization is generated in this release.

Generated files include:

```text
euv_music_library/
├── .metadata/metadata.json
├── loading_screen/sound/banks/windows/
│   ├── eu4_soundtrack_music.bnk
│   ├── eu4_soundtrack_media.bnk
│   ├── SoundbanksInfo.json
│   └── Media/<id>.wem
├── in_game/common/music_player_tracks/euv_music_library.txt
└── main_menu/localization/music_player_gui/euv_music_library_l_english.yml
```

The bank filenames retain the upstream converter's internal names. Disable other music mods that patch the same dynamic bank because EU5 cannot safely combine multiple replacements of that bank.

Before installation, the tool checks the generated bank's binary object graph for EU5's native Music Player container and every generated track event. This prevents a structurally incomplete bank from replacing the last working output.

## Reliability behavior

- Existing valid conversions are reused; new or changed MP3 files are converted.
- Deleted songs are removed from registrations and generated media on the next implementation.
- Removing the final song clears the generated soundtrack.
- Each implementation is transactional. If conversion, validation, or bank rebuilding fails, the previous generated mod is restored.
- An interrupted transaction is recovered the next time the utility runs.
- Unicode filenames are embedded in generated PowerShell with UTF-8 BOM for Windows PowerShell 5.1.
- Requested WEM files and both banks are validated before the new state is committed.
- Re-run **Convert and Implement** after a major EU5 update so the banks are rebuilt from the installed game version.

## Command line

The graphical interface is the normal entry point. A sync can also be run directly:

```bat
"EUV Music Library Tool.cmd" -Action Sync
"EUV Music Library Tool.cmd" -Action Sync -Eu5UserDir "D:\Games\EU5 User Data"
```

Run the independent checks from Windows PowerShell after installing FFmpeg:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

## Technical references and acknowledgments

- [`komoreb11/eu5-music-converter`](https://github.com/komoreb11/eu5-music-converter) documents and implements the dynamic playlist bank format, WEM conversion, and EU5 bank versions 150 and 172. Because that repository currently declares no software license, its source is not copied here. At runtime this utility downloads a pinned, SHA-256-verified copy from the original repository and adapts it locally.
- [`NikolayCoco/eu5_music_player_generator`](https://github.com/NikolayCoco/eu5_music_player_generator) documents Music Player event registration, track definitions, and localization. It is used as a technical reference; its unlicensed implementation and binaries are not copied here.
- [`Europa-Universalis-5-Modding-Co-op/modding-digests`](https://github.com/Europa-Universalis-5-Modding-Co-op/modding-digests) confirms the generated `music_player_tracks` schema and EU5's native Music Player localization layout.
- [`hcs64/ww2ogg`](https://github.com/hcs64/ww2ogg) is the reference for Wwise Vorbis packed codebooks used by the conversion pipeline.

The pinned dynamic converter commit is `6e6480d442c365bec7cd2a5dde00966df4f89e81`, verified as SHA-256 `2f5d7cafc616668f19414077fba8189916c3e350c96b57a7d3f7b002b4c139cf` before execution.
