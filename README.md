# EUV Music Library Tool

A Windows utility for importing MP3 files into Europa Universalis V as a local music mod. Imported tracks appear in the Music Player and can be assigned to the war playlist, the peace playlist, or both.

## Compatibility and validation

The converter supports EU5 sound-bank versions **150** and **172**, associated with game versions 1.3 and 1.4. The tool checks the installed bank before conversion and stops on an unsupported version. Competing music mods replacing the same music bank must be disabled.

Windows PowerShell 5.1 checks cover metadata, imports, generated registrations, recovery, filename handling, and converter adaptation. Native Music Player and dynamic playlist playback still require an end-to-end in-game test. Compatibility with multiplayer and achievements is unverified.

## Requirements

- Windows 11 with Windows PowerShell 5.1
- Europa Universalis V installed through Steam
- FFmpeg for audio conversion
- Internet access for first-time setup and converter downloads

## Installation

1. Download the repository from **Code → Download ZIP** and extract the archive.
2. Launch **EUV Music Library Tool.cmd** from the extracted folder.

The tool detects the game installation through Steam, including libraries on additional drives. If FFmpeg is missing during the first conversion, accept the installation prompt, wait for setup to finish, then reopen the tool and select **Install Music**.

## Usage

Close EU5 before installing or rebuilding the music mod. First-time conversion downloads the converter and supporting audio tools. Conversion time and temporary disk usage depend on track count and duration.

1. Select **Add MP3 Files** to import tracks. To import album folders, select **Open Music Folder**, copy the folders into the library, then select **Refresh**.
2. Review the **Title** and **Artist** fields. Set **Playback** to **War**, **Peace**, or **Both**. New tracks default to **Both**.
3. Select **Install Music** and wait for **Library update complete**.
4. Enable the mod in EU5 (first install only):
   1. Open EU5 through Steam.
   2. Select the mod manager icon in the bottom-right corner of the main menu screen.
   3. Tick the checkbox on the **EUV Music Library** row.
   4. Select **Save Changes**, then **Apply**.
   5. Select **Ok** on the **Playset issues** warning. The mod adds Music Player entries, which changes the game checksum. The warning concerns multiplayer compatibility only.
   6. Quit and restart EU5. The checksum shown in the top-right version box changes when the mod is active.
5. Start or load a game and open the Music Player. Imported titles are available for selection.

The mod stays enabled across later rebuilds. Restart EU5 after each **Install Music** to load the new songs.

Select **Install Music** after library edits or a major EU5 update to rebuild the mod. **Remove Song** moves selected library copies to the Recycle Bin. Installing an empty library clears the generated soundtrack.

## Library maintenance

The music library and saved assignments reside in the Windows Documents folder, independently of the extracted tool folder. Windows Documents redirection, including OneDrive, is detected automatically.

- **Update the tool.** Close the tool, extract a fresh repository download, and launch the new copy. Existing songs and assignments are reused when the same EU5 user-data directory is selected.
- **Back up the library.** Close the tool and copy the entire `Paradox Interactive\Europa Universalis V\music_library` folder to a backup location. Include `library.json` to preserve titles, artists, and playback assignments.
- **Disable the mod.** Open the mod manager from the bottom-right corner of EU5's main menu, untick **EUV Music Library**, select **Save Changes** and **Apply**, then restart the game.
- **Remove the mod.** Close EU5 and the tool, then delete `Paradox Interactive\Europa Universalis V\mod\euv_music_library`. Delete the extracted tool folder when no longer needed. Retain or back up `music_library` before deleting the source MP3 collection.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| The list is empty after copying songs | Select **Open Music Folder** from the running tool. Check for files ending in `.mp3` in that folder or an album subfolder, then select **Refresh**. The extracted GitHub folder holds the launcher and scripts. |
| FFmpeg setup is unavailable | Install **App Installer** from Microsoft Store, reopen the tool, and retry FFmpeg setup. |
| EU5 music files could not be found | Open **Steam > Library > Europa Universalis V**. Finish installation or pending updates. For an installed game, open **Properties > Installed Files > Verify integrity of game files**, then retry conversion. |
| Unknown sound-bank version | The pinned converter supports bank versions 150 and 172. Check for a converter update after a game patch. |
| **Library update complete** appears, but no imported music plays | The mod is probably not enabled. Open the mod manager from the bottom-right corner of EU5's main menu and confirm **EUV Music Library** is ticked. Select **Save Changes** and **Apply**, then restart EU5. The checksum in the top-right version box changes when the mod is active. |
| A title is missing from the Music Player | Check the title in the tool's song list and confirm conversion completed. Confirm **EUV Music Library** is enabled, disable competing music mods replacing the same bank, then restart EU5. |
| A **Playset issues** warning appears after enabling the mod | Expected. The mod adds Music Player entries, which changes the game checksum. Select **Ok**. The warning concerns multiplayer compatibility only. |

Report reproducible failures through GitHub Issues with the EU5 version, Windows version, tool commit, exact error message, and reproduction steps. Include whether the failure occurs with a single MP3 or multiple tracks. Review diagnostic text for personal file paths before posting.

## Technical details

- Source MP3s reside under the Windows Documents folder in `Paradox Interactive\Europa Universalis V\music_library\tracks`. The generated mod resides in `Paradox Interactive\Europa Universalis V\mod\euv_music_library`.
- Title and artist come from ID3 tags, with a fallback to `Artist - Title.mp3` or the filename and `Unknown Artist`. The artist supplies the composer and performer fields. Localization is English.
- Each MP3's SHA-256 hash is stored in `library.json` with its size and modification time. Unchanged files reuse the stored hash, so **Refresh** and **Install Music** reread only new or changed audio.
- Stable track identifiers preserve assignments across metadata edits and same-content renames. Conversion reuses valid media and rebuilds the music banks. Transaction recovery restores the previous output after interrupted or failed conversion.
- The tool allows one library window per Windows session and rejects overlapping conversions. The generated converter and audio helpers use a dedicated local cache.

## Command line

For a custom EU5 `--userdir`, pass the matching user-data directory. The launcher also supports unattended sync.

```bat
"EUV Music Library Tool.cmd" -Eu5UserDir "D:\Games\EU5 User Data"
"EUV Music Library Tool.cmd" -Action Sync
```

## Tests

Run the PowerShell test suite with FFmpeg available on PATH.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

The test suite also accepts `-ConverterSource <path>` for a locally downloaded copy of the pinned upstream script. The script's checksum is verified before the generated converter's syntax, quoting, cache isolation, and native invocation are checked. Tests use synthetic audio and bank fixtures. In-game acceptance requires checking imported titles, direct playback, war and peace assignments, and disable/re-enable behavior on the installed EU5 version.

## Credits & Disclosures

### Technical references

- **EU4-to-EU5 Music Converter — komoreb11.** The tool downloads and adapts the pinned converter locally for Wwise audio conversion, dynamic war and peace playlists, soundbank generation, and compatibility with supported EU5 bank versions. [Upstream converter](https://github.com/komoreb11/eu5-music-converter)
- **EU5 Music Player Generator — NikolayCoco.** Technical reference for native Music Player registration, track names, localization, and music event integration. The generator credits **predstavitel_morskogo_narodca** for EU5 audio reverse engineering and conversion tooling. [Generator and upstream credits](https://github.com/NikolayCoco/eu5_music_player_generator#readme)
- **ww2ogg — hcs64.** Technical reference for the Wwise Vorbis format and conversion techniques. The converter downloads the packed codebook from the upstream repository. [ww2ogg](https://github.com/hcs64/ww2ogg)
- **EU5 Modding Co-op.** Additional reference for track definitions and localization paths. [Modding digests](https://github.com/Europa-Universalis-5-Modding-Co-op/modding-digests)

### AI development disclosure

This project was developed with assistance from OpenAI Codex for software implementation, debugging, and technical research. Project requirements, direction, and maintenance are managed by the repository owner.

### Independence and attribution

EUV Music Library Tool is an independent community project. The referenced projects remain the work of their respective authors. Attribution does not imply affiliation, sponsorship, or endorsement.

### Music and licensing

The utility does not distribute music or game files. Users supply MP3 files and are responsible for obtaining the rights required for the intended use.

The MIT License covers the project's original source code and documentation. External components retain the applicable upstream terms. [Project license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
