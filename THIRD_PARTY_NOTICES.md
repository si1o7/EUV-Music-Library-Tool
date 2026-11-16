# Third-party notices

The repository distributes the EUV Music Library Tool scripts, tests, and documentation. Third-party executables, libraries, codebooks, EU5 game assets, and user-supplied audio are excluded from the source download.

## Runtime components

| Component | Source and use | License information |
| --- | --- | --- |
| EU4-to-EU5 Music Converter | The tool downloads and adapts the PowerShell converter locally. The converter also compiles a local helper DLL. [Pinned source](https://github.com/komoreb11/eu5-music-converter/tree/6e6480d442c365bec7cd2a5dde00966df4f89e81) | No license file was identified at the pinned revision. The project MIT License grants no rights to the converter. |
| FFmpeg | Audio decoding through a separate installation. The Windows setup prompt offers the Gyan.FFmpeg package. [Windows builds](https://www.gyan.dev/ffmpeg/builds/) | LGPL-2.1-or-later or GPL, depending on build configuration. Run `ffmpeg -L` for the installed executable's license. [FFmpeg licensing](https://ffmpeg.org/legal.html) |
| ww2ogg packed codebook | The converter retrieves `packed_codebooks_aoTuV_603.bin` from hcs64/ww2ogg. | The repository publishes BSD-3-Clause terms credited to the Xiph.org Foundation and Adam Gashlin. [Upstream notice](https://github.com/hcs64/ww2ogg/blob/master/COPYING) |
| oggenc2 2.88 with aoTuV b6.03 | The converter retrieves the RareWares Windows encoder for Ogg Vorbis encoding. [RareWares encoder builds](https://www.rarewares.org/ogg-oggenc.php) | Xiph publishes libvorbis under a BSD license. Consult the upstream distribution for the encoder build's component terms. [Vorbis licensing](https://xiph.org/vorbis/) |
| libFLAC 1.5.0 | The converter retrieves the RareWares libFLAC DLL for the encoder. | Xiph's reference library uses the BSD 3-Clause License. [FLAC licensing](https://xiph.org/flac/license.html) |

The launcher verifies the pinned converter script against SHA-256 `2f5d7cafc616668f19414077fba8189916c3e350c96b57a7d3f7b002b4c139cf`. The digest covers the script alone.

Record the source, version, applicable license, and required notices here before adding a third-party component to a release.
