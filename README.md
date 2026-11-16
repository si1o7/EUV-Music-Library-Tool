# EUV Music Library Tool

Add MP3 songs to the Europa Universalis V Music Player and the war and peace playlists. Requires Windows 11, the Steam edition of EU5, and internet access for first-time setup.

## Quick start

1. **Open the tool.** On GitHub, select **Code > Download ZIP**. In Downloads, right-click the ZIP, select **Extract All**, then **Extract**. Open the extracted folder and double-click **EUV Music Library Tool.cmd**.
2. **Add songs.** Select **Add MP3 Files**, select MP3 songs, then select **Open**. Hold **Ctrl** to select several songs. The tool copies the files into the music library and lists the titles automatically.
3. **Choose playback.** Leave **Both** for music during war and peace. For a different assignment, select **War** or **Peace** in the **Playback** column. Title and artist fields also support editing.
4. **Install the music.** Select **Install Music**. If an FFmpeg setup prompt appears, select **Yes** and follow the installer prompts. After installation finishes, close and reopen the tool, then select **Install Music** again. Wait for **Library update complete**.
5. **Enable the mod.** Open EU5 through Steam. In **Mods**, enable **EUV Music Library**, then restart EU5. Open the Music Player and look for an imported title.

Steam supplies the game location, including libraries on additional drives. Windows supplies the Documents location, including OneDrive redirection. Game-folder selection is automatic.

## Updating the library

- **Add songs** with **Add MP3 Files**. Repeated imports of identical MP3 files under the same name skip the extra copy. Different recordings with matching filenames receive numbered copies.
- **Remove songs** with **Remove Song**. Removal sends the selected library copies to the Recycle Bin.
- Select **Install Music** after additions, edits, removals, or a major game update. Installing an empty library clears previously generated music.
- For album folders, select **Open Music Folder**, copy the album folders into the open window, then select **Refresh** in the tool.

## Troubleshooting

| Message or symptom | Next step |
| --- | --- |
| EU5 music files could not be found | Open **Steam > Library > Europa Universalis V**. Finish installation or pending updates. For an installed game, open **Properties > Installed Files > Verify integrity of game files**. Retry **Install Music**. |
| FFmpeg setup unavailable | Install **App Installer** from Microsoft Store, reopen the tool, then select **Install Music**. |
| Unknown sound-bank version | The pinned converter supports bank versions 150 and 172. Check for a converter update after a game patch. |
| Imported titles missing | Enable **EUV Music Library** in **Mods**, disable competing music mods replacing the same sound bank, and restart EU5. |

## Technical details

- Source MP3s reside under the Windows Documents folder in `Paradox Interactive\Europa Universalis V\music_library\tracks`. The generated mod resides in `Paradox Interactive\Europa Universalis V\mod\euv_music_library`.
- Title and artist come from ID3 tags, with a fallback to `Artist - Title.mp3` or the filename and `Unknown Artist`. The artist supplies the composer and performer fields. Localization is English.
- Stable track identifiers preserve assignments across metadata edits and same-content renames. Conversion reuses valid media and rebuilds the music banks. Transaction recovery restores the previous output after interrupted or failed conversion.
- Automated checks cover library management, metadata, generated registrations, and recovery. Native Music Player and dynamic playback still require an in-game test on a supported EU5 installation.

### Command line

For a custom EU5 `--userdir`, pass the matching user-data directory. The launcher also supports unattended sync.

```bat
"EUV Music Library Tool.cmd" -Eu5UserDir "D:\Games\EU5 User Data"
"EUV Music Library Tool.cmd" -Action Sync
```

Run the checks with FFmpeg available on PATH.

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
