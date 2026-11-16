# EUV Music Library Tool

Add MP3 songs to the Europa Universalis V Music Player and the war and peace playlists. Requires Windows 11, the Steam edition of EU5, and internet access for first-time setup.

## Quick start

### Songs already in the music folder

1. Return to **EUV Music Library Tool** and select **Refresh**. MP3s copied through **Open Music Folder** should appear in the song list, including MP3s inside album folders.
2. Review the **Title**, **Artist**, and **Playback** columns. Correct any missing tags directly in the list. Leave **Both** for war and peace, or choose **War** or **Peace** for a single playlist.
3. Select **Convert and Implement** in the older interface or **Install Music** in the current interface. Both buttons build the local EU5 music mod. Keep the tool open until the success message appears. For an FFmpeg prompt, follow the setup instructions below.
4. Open **Europa Universalis V** through Steam. In **Mods**, enable **EUV Music Library**, then restart the game. Open the in-game **Music Player** and look for a title from the song list. Select the title to check playback directly; hearing a song through a war or peace playlist can take longer.

### Starting with an empty library

1. On GitHub, select **Code > Download ZIP**. In Downloads, right-click the ZIP, select **Extract All**, then **Extract**. Open the extracted folder and double-click **EUV Music Library Tool.cmd**.
2. Select **Add MP3 Files**, choose the songs, and select **Open**. The tool copies the MP3s into the library and fills in the song list. For a full album folder, select **Open Music Folder**, copy the album folder into the open window, then select **Refresh**.
3. Review the list and continue from step 2 under **Songs already in the music folder**. Steam supplies the installed game location, including libraries on additional drives.

### First conversion and FFmpeg

FFmpeg converts MP3 audio into a format the game can use. In the current tool, select **Yes** at the FFmpeg setup prompt and let installation finish. Close and reopen **EUV Music Library Tool.cmd**, then select **Install Music** again.

If the older tool displays a command instead, open **Windows Terminal** from Start and run:

```powershell
winget install --id Gyan.FFmpeg --exact
```

After installation finishes, reopen the tool, select **Refresh**, then **Convert and Implement**.

## Updating the library or the tool

- **Add or edit songs.** Import more MP3s or copy files through **Open Music Folder** and select **Refresh**. After changing titles, artists, or playback settings, run the install or conversion button again to update the mod.
- **Remove songs.** Select the library entries and choose **Remove Song**. The selected library copies move to the Recycle Bin. Run **Install Music** in the current tool to update the mod, including after removing the final song.
- **Upgrade from the older interface.** Close the older tool, extract the current ZIP into a new folder, and launch the new copy. Both interfaces use the same music library under Documents. With the same EU5 user-data location, existing MP3s and saved assignments carry over. Select **Refresh** to check the list.
- **After a major EU5 update**, run **Install Music** again to rebuild the music banks for the installed game version.

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
