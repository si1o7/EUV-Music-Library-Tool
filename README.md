# EUV Music Library Tool

A Windows utility for importing MP3 files into Europa Universalis V as a local music mod. Imported tracks appear in the Music Player and can be assigned to the war playlist, the peace playlist, or both.

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

1. Select **Add MP3 Files** to import tracks. To import album folders, select **Open Music Folder**, copy the folders into the library, then select **Refresh**.
2. Review the **Title** and **Artist** fields. Set **Playback** to **War**, **Peace**, or **Both**. New tracks default to **Both**.
3. Select **Install Music** and wait for **Library update complete**.
4. Open EU5 through Steam, enable **EUV Music Library** in **Mods**, and restart the game. Imported titles are available for selection in the Music Player.

Select **Install Music** after library edits or a major EU5 update to rebuild the mod. **Remove Song** moves selected library copies to the Recycle Bin. Installing an empty library clears the generated soundtrack.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| The list is empty after copying songs | Select **Open Music Folder** from the running tool. Check for files ending in `.mp3` in that folder or an album subfolder, then select **Refresh**. The extracted GitHub folder holds the launcher and scripts. |
| FFmpeg setup is unavailable | Install **App Installer** from Microsoft Store, reopen the tool, and retry FFmpeg setup. |
| EU5 music files could not be found | Open **Steam > Library > Europa Universalis V**. Finish installation or pending updates. For an installed game, open **Properties > Installed Files > Verify integrity of game files**, then retry conversion. |
| Unknown sound-bank version | The pinned converter supports bank versions 150 and 172. Check for a converter update after a game patch. |
| A title is missing from the Music Player | Check the title in the tool's song list and confirm conversion completed. Enable **EUV Music Library** in **Mods**, disable competing music mods replacing the same bank, then restart EU5. |

## Technical details

- Source MP3s reside under the Windows Documents folder in `Paradox Interactive\Europa Universalis V\music_library\tracks`. The generated mod resides in `Paradox Interactive\Europa Universalis V\mod\euv_music_library`.
- Title and artist come from ID3 tags, with a fallback to `Artist - Title.mp3` or the filename and `Unknown Artist`. The artist supplies the composer and performer fields. Localization is English.
- Stable track identifiers preserve assignments across metadata edits and same-content renames. Conversion reuses valid media and rebuilds the music banks. Transaction recovery restores the previous output after interrupted or failed conversion.
- Automated checks cover library management, metadata, generated registrations, and recovery. Native Music Player and dynamic playback still require an in-game test on a supported EU5 installation.

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
