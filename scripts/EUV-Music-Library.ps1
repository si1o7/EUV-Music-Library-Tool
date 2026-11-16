#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Install', 'Sync', 'OpenLibrary')]
    [string]$Action = 'Menu',

    [string]$Eu5UserDir = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:ToolName = 'EUV Music Library Tool'
$script:UpstreamCommit = '6e6480d442c365bec7cd2a5dde00966df4f89e81'
$script:UpstreamSha256 = '2f5d7cafc616668f19414077fba8189916c3e350c96b57a7d3f7b002b4c139cf'
$script:UpstreamUrl = "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/$($script:UpstreamCommit)/EU4_Soundtrack_Setup.ps1"
$script:SupportedExtensions = @('.mp3')
$script:ValidMoods = @('both', 'war', 'peace')

if ([string]::IsNullOrWhiteSpace($Eu5UserDir)) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($documents)) {
        throw 'Windows did not report a Documents folder.'
    }
    $Eu5UserDir = Join-Path $documents 'Paradox Interactive\Europa Universalis V'
}

$script:Eu5UserDir = $Eu5UserDir
$script:LibraryDir = Join-Path $script:Eu5UserDir 'music_library'
$script:TracksDir = Join-Path $script:LibraryDir 'tracks'
$script:ManifestPath = Join-Path $script:LibraryDir 'library.json'
$script:StatePath = Join-Path $script:LibraryDir '.generated-state.json'
$script:BackupDir = Join-Path $script:LibraryDir '.sync-backup'
$script:ModDir = Join-Path $script:Eu5UserDir 'mod\euv_music_library'
$script:BanksDir = Join-Path $script:ModDir 'loading_screen\sound\banks\windows'
$script:MediaDir = Join-Path $script:BanksDir 'Media'
$script:TrackDefinitionPath = Join-Path $script:ModDir 'in_game\common\music_player_tracks\euv_music_library.txt'
$script:LocalizationPath = Join-Path $script:ModDir 'main_menu\localization\music_player_gui\euv_music_library_l_english.yml'
$script:CacheDir = Join-Path $env:LOCALAPPDATA 'EUV-Music-Library-Tool'
$script:UpstreamPath = Join-Path $script:CacheDir "EU4_Soundtrack_Setup-$($script:UpstreamCommit).ps1"
$script:PatchedPath = Join-Path $script:CacheDir 'EUV-Music-Library-Generated.ps1'

function Write-Heading([string]$Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * $Text.Length) -ForegroundColor DarkCyan
}

function Write-Success([string]$Text) {
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Notice([string]$Text) {
    Write-Host "[!]  $Text" -ForegroundColor Yellow
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Fnv1Id([string]$Value) {
    [uint64]$hash = 2166136261
    [uint64]$mask = 4294967295
    [uint64]$prime = 16777619
    foreach ($character in $Value.ToLowerInvariant().ToCharArray()) {
        $hash = ($hash * $prime) -band $mask
        $hash = $hash -bxor [uint64][byte][char]$character
    }
    return [uint32]$hash
}

function Get-EventName([string]$TrackId) {
    if ($TrackId -notmatch '^[a-f0-9]{24}$') { throw "Invalid persistent track ID '$TrackId'." }
    return "MusicPlayer_euvlib_$TrackId"
}

function ConvertFrom-Id3Text([byte[]]$Payload) {
    if ($null -eq $Payload -or $Payload.Length -lt 2) { return '' }
    $encodingByte = $Payload[0]
    $data = New-Object byte[] ($Payload.Length - 1)
    [Array]::Copy($Payload, 1, $data, 0, $data.Length)
    switch ($encodingByte) {
        0 { $encoding = [Text.Encoding]::GetEncoding(28591) }
        1 {
            if ($data.Length -ge 2 -and $data[0] -eq 0xfe -and $data[1] -eq 0xff) {
                $encoding = [Text.Encoding]::BigEndianUnicode
            } else {
                $encoding = [Text.Encoding]::Unicode
            }
        }
        2 { $encoding = [Text.Encoding]::BigEndianUnicode }
        3 { $encoding = New-Object Text.UTF8Encoding($false) }
        default { return '' }
    }
    return $encoding.GetString($data).Trim([char]0, [char]0xfeff, [char]0xfffe, ' ')
}

function Get-SynchsafeInteger([byte[]]$Bytes, [int]$Offset) {
    return (($Bytes[$Offset] -band 0x7f) -shl 21) -bor (($Bytes[$Offset + 1] -band 0x7f) -shl 14) -bor
        (($Bytes[$Offset + 2] -band 0x7f) -shl 7) -bor ($Bytes[$Offset + 3] -band 0x7f)
}

function Read-Mp3Metadata([string]$Path) {
    $fallbackTitle = [IO.Path]::GetFileNameWithoutExtension($Path)
    $fallbackArtist = 'Unknown Artist'
    if ($fallbackTitle -match '^(.+?)\s+-\s+(.+)$') {
        $fallbackArtist = $Matches[1].Trim()
        $fallbackTitle = $Matches[2].Trim()
    }
    $title = ''
    $artist = ''

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -ge 10) {
            $reader = New-Object IO.BinaryReader($stream)
            $header = $reader.ReadBytes(10)
            if ($header[0] -eq 0x49 -and $header[1] -eq 0x44 -and $header[2] -eq 0x33) {
                $version = [int]$header[3]
                $tagSize = Get-SynchsafeInteger $header 6
                $tagSize = [Math]::Min($tagSize, [Math]::Max(0, $stream.Length - 10))
                $tag = $reader.ReadBytes($tagSize)
                $offset = 0
                while ($offset -lt $tag.Length) {
                    if ($version -eq 2) {
                        if ($offset + 6 -gt $tag.Length) { break }
                        $frameId = [Text.Encoding]::ASCII.GetString($tag, $offset, 3)
                        $frameSize = (([int]$tag[$offset + 3]) -shl 16) -bor (([int]$tag[$offset + 4]) -shl 8) -bor ([int]$tag[$offset + 5])
                        $headerSize = 6
                    } else {
                        if ($offset + 10 -gt $tag.Length) { break }
                        $frameId = [Text.Encoding]::ASCII.GetString($tag, $offset, 4)
                        if ($version -eq 4) {
                            $frameSize = Get-SynchsafeInteger $tag ($offset + 4)
                        } else {
                            $frameSize = (([int]$tag[$offset + 4]) -shl 24) -bor (([int]$tag[$offset + 5]) -shl 16) -bor
                                (([int]$tag[$offset + 6]) -shl 8) -bor ([int]$tag[$offset + 7])
                        }
                        $headerSize = 10
                    }
                    if ([string]::IsNullOrWhiteSpace($frameId) -or $frameId[0] -eq [char]0 -or $frameSize -le 0) { break }
                    if ($offset + $headerSize + $frameSize -gt $tag.Length) { break }
                    if ($frameId -in @('TIT2', 'TT2', 'TPE1', 'TP1')) {
                        $payload = New-Object byte[] $frameSize
                        [Array]::Copy($tag, $offset + $headerSize, $payload, 0, $frameSize)
                        $value = ConvertFrom-Id3Text $payload
                        if ($frameId -in @('TIT2', 'TT2')) { $title = $value }
                        if ($frameId -in @('TPE1', 'TP1')) { $artist = $value }
                    }
                    $offset += $headerSize + $frameSize
                }
            }
        }

        if (($title -eq '' -or $artist -eq '') -and $stream.Length -ge 128) {
            $stream.Seek(-128, [IO.SeekOrigin]::End) | Out-Null
            $id3v1 = New-Object byte[] 128
            [void]$stream.Read($id3v1, 0, 128)
            if ([Text.Encoding]::ASCII.GetString($id3v1, 0, 3) -eq 'TAG') {
                $latin1 = [Text.Encoding]::GetEncoding(28591)
                if ($title -eq '') { $title = $latin1.GetString($id3v1, 3, 30).Trim([char]0, ' ') }
                if ($artist -eq '') { $artist = $latin1.GetString($id3v1, 33, 30).Trim([char]0, ' ') }
            }
        }
    } finally {
        $stream.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $fallbackTitle }
    if ([string]::IsNullOrWhiteSpace($artist)) { $artist = $fallbackArtist }
    return [PSCustomObject]@{ Title = $title; Artist = $artist }
}

function New-DefaultManifest {
    return [ordered]@{
        version = 2
        tracks = @()
    }
}

function Read-Manifest {
    if (-not (Test-Path -LiteralPath $script:ManifestPath -PathType Leaf)) {
        return New-DefaultManifest
    }
    try {
        $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "The library manifest is invalid JSON: $($script:ManifestPath)`n$($_.Exception.Message)"
    }
    if ($null -eq $manifest.tracks) {
        throw "The library manifest must contain a 'tracks' array: $($script:ManifestPath)"
    }
    return $manifest
}

function Save-Manifest($Manifest) {
    $json = $Manifest | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($script:ManifestPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Get-SourceFiles {
    if (-not (Test-Path -LiteralPath $script:TracksDir -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:TracksDir -File -Recurse | Where-Object {
        $script:SupportedExtensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object FullName)
}

function Update-ManifestFromFiles {
    $manifest = Read-Manifest
    $existingByPath = @{}
    $existingByHash = @{}
    foreach ($track in @($manifest.tracks)) {
        if ($null -ne $track.file) {
            $existingByPath[[string]$track.file.ToLowerInvariant()] = $track
        }
        if ($null -ne $track.PSObject.Properties['source_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$track.source_sha256)) {
            $hash = ([string]$track.source_sha256).ToLowerInvariant()
            if (-not $existingByHash.ContainsKey($hash)) { $existingByHash[$hash] = @() }
            $existingByHash[$hash] += $track
        }
    }

    $sourceRecords = @()
    foreach ($file in Get-SourceFiles) {
        $relative = $file.FullName.Substring($script:TracksDir.Length).TrimStart('\', '/') -replace '\\', '/'
        $sourceRecords += [PSCustomObject]@{
            File = $file
            Relative = $relative
            Key = $relative.ToLowerInvariant()
            SourceSha256 = Get-FileSha256 $file.FullName
        }
    }

    # Reserve every exact-path identity before content-hash rename matching. Without this
    # first pass, an earlier duplicate copy could steal the identity of a later exact path.
    $reservedExactIds = @{}
    foreach ($record in $sourceRecords) {
        if ($existingByPath.ContainsKey($record.Key)) {
            $candidate = $existingByPath[$record.Key]
            if ($null -ne $candidate.PSObject.Properties['id']) {
                $reservedExactIds[[string]$candidate.id] = $true
            }
        }
    }

    $updated = @()
    $newCount = 0
    $usedIds = @{}
    foreach ($record in $sourceRecords) {
        $file = $record.File
        $relative = $record.Relative
        $sourceSha256 = $record.SourceSha256
        $key = $relative.ToLowerInvariant()
        $track = $null
        if ($existingByPath.ContainsKey($key)) {
            $track = $existingByPath[$key]
        } elseif ($existingByHash.ContainsKey($sourceSha256)) {
            $track = @($existingByHash[$sourceSha256] | Where-Object {
                $null -ne $_.PSObject.Properties['id'] -and
                -not $usedIds.ContainsKey([string]$_.id) -and
                -not $reservedExactIds.ContainsKey([string]$_.id)
            } | Select-Object -First 1)
            if ($track.Count -gt 0) { $track = $track[0] } else { $track = $null }
        }

        if ($null -ne $track) {
            $trackId = if ($null -ne $track.PSObject.Properties['id'] -and ([string]$track.id) -match '^[a-f0-9]{24}$') {
                [string]$track.id
            } else {
                [Guid]::NewGuid().ToString('N').Substring(0, 24)
            }
            $enabled = if ($null -eq $track.PSObject.Properties['enabled']) { $true } else { $track.enabled }
            $mood = if ($null -eq $track.PSObject.Properties['mood'] -or [string]::IsNullOrWhiteSpace([string]$track.mood)) { 'both' } else { [string]$track.mood }
            $metadata = Read-Mp3Metadata $file.FullName
            $title = if ($null -eq $track.PSObject.Properties['title'] -or [string]::IsNullOrWhiteSpace([string]$track.title)) { $metadata.Title } else { [string]$track.title }
            $artist = if ($null -eq $track.PSObject.Properties['artist'] -or [string]::IsNullOrWhiteSpace([string]$track.artist)) { $metadata.Artist } else { [string]$track.artist }
            $updated += [ordered]@{
                id = $trackId
                file = $relative
                title = $title
                artist = $artist
                enabled = $enabled
                mood = $mood
                source_sha256 = $sourceSha256
            }
        } else {
            $metadata = Read-Mp3Metadata $file.FullName
            $trackId = [Guid]::NewGuid().ToString('N').Substring(0, 24)
            $updated += [ordered]@{
                id = $trackId
                file = $relative
                title = $metadata.Title
                artist = $metadata.Artist
                enabled = $true
                mood = 'both'
                source_sha256 = $sourceSha256
            }
            $newCount++
        }
        $usedIds[$trackId] = $true
    }

    $manifest = [ordered]@{ version = 2; tracks = $updated }
    Save-Manifest $manifest
    if ($newCount -gt 0) {
        Write-Success "Added $newCount new track(s) to library.json with mood 'both'."
    }
    return Read-Manifest
}

function Get-ActiveTracks($Manifest) {
    $active = @()
    $seenEvents = @{}
    $seenWemIds = @{}
    foreach ($track in @($Manifest.tracks)) {
        $relative = [string]$track.file
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if ($null -ne $track.PSObject.Properties['enabled'] -and $track.enabled -isnot [bool]) {
            throw "Invalid enabled value for '$relative'. Use the JSON values true or false without quotes."
        }
        $enabled = if ($null -eq $track.PSObject.Properties['enabled']) { $true } else { [bool]$track.enabled }
        if (-not $enabled) { continue }

        $mood = if ($null -eq $track.PSObject.Properties['mood']) { 'both' } else { ([string]$track.mood).ToLowerInvariant() }
        if ($script:ValidMoods -notcontains $mood) {
            throw "Invalid mood '$mood' for '$relative'. Use both, war, or peace."
        }
        $fullPath = Join-Path $script:TracksDir ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Notice "Skipping missing file: $relative"
            continue
        }

        $trackId = if ($null -eq $track.PSObject.Properties['id']) { '' } else { [string]$track.id }
        $eventName = Get-EventName $trackId
        if ($seenEvents.ContainsKey($eventName)) {
            throw "Two tracks generated the same event name: '$relative' and '$($seenEvents[$eventName])'."
        }
        $seenEvents[$eventName] = $relative
        $wemId = Get-Fnv1Id ($eventName + '_wem')
        if ($seenWemIds.ContainsKey([string]$wemId)) {
            throw "WEM ID collision between '$relative' and '$($seenWemIds[[string]$wemId])'. Rename one of the files."
        }
        $seenWemIds[[string]$wemId] = $relative
        $upstreamMood = if ($mood -eq 'both') { 'neutral' } else { $mood }
        $active += [PSCustomObject]@{
            File = $relative
            SourcePath = $fullPath
            SourceSha256 = [string]$track.source_sha256
            TrackId = $trackId
            EventName = $eventName
            EventId = Get-Fnv1Id $eventName
            Title = if ($null -eq $track.PSObject.Properties['title']) { [IO.Path]::GetFileNameWithoutExtension($relative) } else { [string]$track.title }
            Artist = if ($null -eq $track.PSObject.Properties['artist']) { 'Unknown Artist' } else { [string]$track.artist }
            Mood = $upstreamMood
            Culture = ''
            WemId = $wemId
        }
    }
    return $active
}

function Install-LocalMod {
    Ensure-Directory $script:TracksDir
    Ensure-Directory $script:MediaDir
    Ensure-Directory (Join-Path $script:ModDir '.metadata')
    Ensure-Directory $script:CacheDir

    $metadata = [ordered]@{
        name = 'EUV Music Library'
        id = 'euv_music_library'
        version = '1.0.0'
        game_id = 'eu5'
        supported_game_version = '1.*'
        short_description = 'Adds locally owned music to EU5 dynamic war, peace, and cultural playlists.'
        tags = @('Music')
        relationships = @()
        game_custom_data = @{}
    }
    $metadataPath = Join-Path $script:ModDir '.metadata\metadata.json'
    $metadataJson = $metadata | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($metadataPath, $metadataJson + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))

    if (-not (Test-Path -LiteralPath $script:ManifestPath -PathType Leaf)) {
        Save-Manifest (New-DefaultManifest)
    }
    Write-Success "Local mod installed at $($script:ModDir)"
}

function Get-SteamRoots {
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $property = if ($key.StartsWith('HKCU')) { 'SteamPath' } else { 'InstallPath' }
        try { Get-ItemPropertyValue -Path $key -Name $property -ErrorAction Stop } catch { continue }
    }
    Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'
}

function Find-GameBank([string[]]$SteamRoots) {
    $libraries = foreach ($root in $SteamRoots) {
        if (-not $root) { continue }
        $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($line in [IO.File]::ReadLines($vdf)) {
                if ($line -match '^\s*"path"\s+"([^"]+)"') { $Matches[1].Replace('\\', '\') }
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $apps = Join-Path $library 'steamapps'
        $folder = 'Europa Universalis V'
        $manifest = Join-Path $apps 'appmanifest_3450310.acf'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $acf = [IO.File]::ReadAllText($manifest)
            if ($acf -match '(?m)^\s*"installdir"\s+"([^"\\/:]+)"') { $folder = $Matches[1] }
        }
        $bank = Join-Path $apps "common\$folder\game\loading_screen\sound\banks\windows\sb_music_logic.bnk"
        if (Test-Path -LiteralPath $bank -PathType Leaf) { return $bank }
    }
    throw 'EU5 music files could not be found. Open Steam > Library > Europa Universalis V. Select Install or finish pending updates. For an installed game, open Properties > Installed Files > Verify integrity of game files. Retry Install Music.'
}

function Assert-Ffmpeg {
    $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        throw 'FFmpeg is required. Run winget install --id Gyan.FFmpeg --exact, then reopen EUV Music Library Tool.'
    }
}

function Get-VerifiedUpstreamScript {
    Ensure-Directory $script:CacheDir
    $validCache = (Test-Path -LiteralPath $script:UpstreamPath -PathType Leaf) -and ((Get-FileSha256 $script:UpstreamPath) -eq $script:UpstreamSha256)
    if (-not $validCache) {
        Write-Host 'Downloading the pinned EU5 Wwise converter...'
        $temporaryPath = "$($script:UpstreamPath).download"
        Invoke-WebRequest -Uri $script:UpstreamUrl -OutFile $temporaryPath -UseBasicParsing
        $actualHash = Get-FileSha256 $temporaryPath
        if ($actualHash -ne $script:UpstreamSha256) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            throw "The downloaded converter failed integrity verification. Expected $($script:UpstreamSha256), received $actualHash."
        }
        Move-Item -LiteralPath $temporaryPath -Destination $script:UpstreamPath -Force
    }
    return Get-Content -LiteralPath $script:UpstreamPath -Raw -Encoding UTF8
}

function ConvertTo-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-PatchedConverter([object[]]$Tracks, [string]$GameBank) {
    $source = Get-VerifiedUpstreamScript

    $modBlockPattern = '(?s)# Auto-detect eu4_soundtrack Workshop mod via Steam registry \+ libraryfolders\.vdf.*?(?=\$BanksDir\s+=)'
    $modBlockReplacement = @'
# Use the local EUV Music Library mod generated by the wrapper.
$ModDir = $env:EUV_MUSIC_MOD_DIR
if ([string]::IsNullOrWhiteSpace($ModDir) -or -not (Test-Path -LiteralPath $ModDir)) {
    throw "EUV_MUSIC_MOD_DIR is missing or invalid."
}
'@
    $modBlockRegex = New-Object Text.RegularExpressions.Regex($modBlockPattern)
    $patched = $modBlockRegex.Replace($source, [Text.RegularExpressions.MatchEvaluator]{ param($match) $modBlockReplacement }, 1)
    if ($patched -eq $source) { throw 'Could not adapt the upstream mod-directory block.' }

    $trackLines = foreach ($track in $Tracks) {
        $record = "$($track.EventName)|$($track.File)||$($track.Mood)|$($track.Culture)"
        '    ' + (ConvertTo-PowerShellLiteral $record)
    }
    $trackBlock = "`$Tracks = @(`r`n" + ($trackLines -join "`r`n") + "`r`n)"
    $trackPattern = '(?s)\$Tracks\s*=\s*@\(.*?\)\s*(?=# --- FUNCTIONS)'
    $trackRegex = New-Object Text.RegularExpressions.Regex($trackPattern)
    $next = $trackRegex.Replace($patched, [Text.RegularExpressions.MatchEvaluator]{ param($match) $trackBlock + "`r`n`r`n" }, 1)
    if ($next -eq $patched) { throw 'Could not adapt the upstream track list.' }
    $patched = $next

    $findEu4Pattern = '(?s)function Find-EU4Path\s*\{.*?\}\s*(?=# Source of a track:)'
    $findEu4Replacement = @'
function Find-EU4Path {
    if ($env:EUV_MUSIC_SOURCE_DIR -and (Test-Path -LiteralPath $env:EUV_MUSIC_SOURCE_DIR)) {
        return $env:EUV_MUSIC_SOURCE_DIR
    }
    return $null
}

'@
    $findEu4Regex = New-Object Text.RegularExpressions.Regex($findEu4Pattern)
    $next = $findEu4Regex.Replace($patched, [Text.RegularExpressions.MatchEvaluator]{ param($match) $findEu4Replacement }, 1)
    if ($next -eq $patched) { throw 'Could not adapt the upstream source-directory lookup.' }
    $patched = $next

    $findOggPattern = '(?s)function Find-Ogg\(\[string\]\$SourceOgg, \[string\]\$DlcDir, \[string\]\$Eu4Path\)\s*\{.*?\}\s*(?=function Find-EU5MusicBank)'
    $findOggReplacement = @'
function Find-Ogg([string]$SourceOgg, [string]$DlcDir, [string]$Eu4Path) {
    $relative = $SourceOgg -replace '/', '\'
    $path = Join-Path $Eu4Path $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) { return @{Path=$path} }
    return $null
}


'@
    $findOggRegex = New-Object Text.RegularExpressions.Regex($findOggPattern)
    $next = $findOggRegex.Replace($patched, [Text.RegularExpressions.MatchEvaluator]{ param($match) $findOggReplacement }, 1)
    if ($next -eq $patched) { throw 'Could not adapt the upstream audio-file lookup.' }
    $patched = $next

    # Player-triggered segments use the vanilla Music Player random/sequence container as
    # their direct parent. The full EU5 base bank copied by the converter already contains
    # this object (0x3B5AE824), for both supported bank versions.
    $playerSegmentOriginal = 'modObjs.Add(MusicSegment(sid,tid,durMs,0));'
    $playerSegmentIntegrated = 'modObjs.Add(MusicSegment(sid,tid,durMs,0x3B5AE824));'
    if (-not $patched.Contains($playerSegmentOriginal)) {
        throw 'Could not attach imported events to the native Music Player container.'
    }
    $patched = $patched.Replace($playerSegmentOriginal, $playerSegmentIntegrated)

    $patched = $patched.Replace('EU4 Soundtrack for EU5', 'EUV Music Library')
    $patched = $patched.Replace('$eu5Bank = Find-EU5MusicBank', '$eu5Bank = ' + (ConvertTo-PowerShellLiteral $GameBank))
    $patched = $patched.Replace('Locating EU4...', 'Locating the music library...')
    $patched = $patched.Replace('EU4 not found. Make sure Europa Universalis IV is installed on this Steam account.', 'The local music library folder was not found.')
    $patched = $patched.Replace('EU4: $eu4Path', 'Music library: $eu4Path')
    $patched = $patched.Replace('Not found in EU4 folder', 'Not found in music library')

    # Windows PowerShell 5.1 treats BOM-less scripts as the active ANSI code page.
    # A BOM preserves Unicode filenames embedded in the generated track list.
    [IO.File]::WriteAllText($script:PatchedPath, $patched, (New-Object Text.UTF8Encoding($true)))
    return $script:PatchedPath
}

function Write-SoundbanksInfo([object[]]$Tracks) {
    $media = foreach ($track in $Tracks) {
        [ordered]@{
            Id = [string]$track.WemId
            ShortName = "$($track.WemId).wem"
            Path = "Media/$($track.WemId).wem"
        }
    }
    $info = [ordered]@{
        SoundBanksInfo = [ordered]@{
            Platform = 'Windows'
            SoundBanks = @(
                [ordered]@{
                    Id = '1047562068'
                    Language = 'SFX'
                    ShortName = 'eu4_soundtrack_music'
                    Path = 'eu4_soundtrack_music.bnk'
                    Events = @($Tracks | ForEach-Object {
                        $duration = Get-WemDurationSeconds (Join-Path $script:MediaDir "$($_.WemId).wem")
                        $durationText = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F5}', $duration)
                        [ordered]@{
                            Id = [string]$_.EventId
                            Name = $_.EventName
                            GUID = ('{{00000000-0000-0000-0000-{0:000000000000}}}' -f ([uint64]$_.EventId % 1000000000000))
                            DurationType = 'OneShot'
                            DurationMin = $durationText
                            DurationMax = $durationText
                            MediaRefs = @([ordered]@{ Id = [string]$_.WemId })
                        }
                    })
                    Media = @($media)
                },
                [ordered]@{
                    Id = '2567832594'
                    Language = 'SFX'
                    ShortName = 'eu4_soundtrack_media'
                    Path = 'eu4_soundtrack_media.bnk'
                    Media = @($media)
                }
            )
        }
    }
    $json = $info | ConvertTo-Json -Depth 8
    $path = Join-Path $script:BanksDir 'SoundbanksInfo.json'
    [IO.File]::WriteAllText($path, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Get-WemDurationSeconds([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $length = [Math]::Min([int64]65536, $stream.Length)
        $header = New-Object byte[] ([int]$length)
        [void]$stream.Read($header, 0, $header.Length)
    } finally {
        $stream.Dispose()
    }
    $position = 12
    while ($position + 8 -le $header.Length) {
        $chunkSize = [BitConverter]::ToUInt32($header, $position + 4)
        if ($header[$position] -eq 0x66 -and $header[$position + 1] -eq 0x6d -and
            $header[$position + 2] -eq 0x74 -and $header[$position + 3] -eq 0x20) {
            if ($position + 36 -gt $header.Length) { break }
            $sampleRate = [BitConverter]::ToUInt32($header, $position + 12)
            $frames = [BitConverter]::ToUInt32($header, $position + 32)
            if ($sampleRate -gt 0) { return [Math]::Max(0.001, [double]$frames / [double]$sampleRate) }
            break
        }
        $position += 8 + [int]$chunkSize
        if (($chunkSize % 2) -ne 0) { $position++ }
    }
    throw "Could not read duration from converted media: $Path"
}

function ConvertTo-Eu5LocalizedString([string]$Value) {
    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", ' ').Replace("`n", ' ')
}

function Write-MusicPlayerRegistration([object[]]$Tracks) {
    Ensure-Directory (Split-Path $script:TrackDefinitionPath -Parent)
    Ensure-Directory (Split-Path $script:LocalizationPath -Parent)

    $definitions = "# Generated by EUV Music Library Tool.`r`n`r`n"
    $localization = "l_english:`r`n`r`n"
    foreach ($track in ($Tracks | Sort-Object EventName)) {
        $artistKey = "$($track.EventName)_artist"
        $definitions += "$($track.EventName) = {`r`n`tcomposer = $artistKey`r`n`tperformer = $artistKey`r`n}`r`n`r`n"
        $title = ConvertTo-Eu5LocalizedString $track.Title
        $artist = ConvertTo-Eu5LocalizedString $track.Artist
        $localization += " $($track.EventName): `"$title`"`r`n"
        $localization += " ${artistKey}: `"$artist`"`r`n"
    }
    $utf8Bom = New-Object Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($script:TrackDefinitionPath, $definitions, $utf8Bom)
    [IO.File]::WriteAllText($script:LocalizationPath, $localization, $utf8Bom)
}

function Get-ValidatedWemId([object]$Value) {
    $text = [string]$Value
    [uint32]$parsed = 0
    if (-not [uint32]::TryParse($text, [ref]$parsed)) { return $null }
    return [string]$parsed
}

function Restore-SyncBackup {
    if (-not (Test-Path -LiteralPath $script:BackupDir -PathType Container)) { return }
    $transactionPath = Join-Path $script:BackupDir 'transaction.json'
    if (-not (Test-Path -LiteralPath $transactionPath -PathType Leaf)) {
        Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
        return
    }
    $mutableIds = @()
    try {
        $transaction = Get-Content -LiteralPath $transactionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($transaction.initialized -ne $true) { throw 'Transaction was not initialized.' }
        foreach ($value in @($transaction.mutable_wem_ids)) {
            $id = Get-ValidatedWemId $value
            if ($null -ne $id) { $mutableIds += $id }
        }
    } catch {
        Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
        Write-Notice 'Discarded an incomplete sync snapshot without changing the installed mod.'
        return
    }

    foreach ($id in $mutableIds) {
        $path = Join-Path $script:MediaDir "$id.wem"
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    $backupMedia = Join-Path $script:BackupDir 'Media'
    if (Test-Path -LiteralPath $backupMedia -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $backupMedia -File -Filter '*.wem') {
            $id = Get-ValidatedWemId $file.BaseName
            if ($null -ne $id) {
                Move-Item -LiteralPath $file.FullName -Destination (Join-Path $script:MediaDir "$id.wem") -Force
            }
        }
    }
    foreach ($pair in @(
        @((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk'), (Join-Path $script:BackupDir 'eu4_soundtrack_music.bnk')),
        @((Join-Path $script:BanksDir 'eu4_soundtrack_media.bnk'), (Join-Path $script:BackupDir 'eu4_soundtrack_media.bnk')),
        @((Join-Path $script:BanksDir 'SoundbanksInfo.json'), (Join-Path $script:BackupDir 'SoundbanksInfo.json')),
        @($script:TrackDefinitionPath, (Join-Path $script:BackupDir 'music_player_tracks.txt')),
        @($script:LocalizationPath, (Join-Path $script:BackupDir 'localization.yml')),
        @($script:StatePath, (Join-Path $script:BackupDir 'generated-state.json'))
    )) {
        $live = $pair[0]
        $backup = $pair[1]
        if (Test-Path -LiteralPath $live -PathType Leaf) { Remove-Item -LiteralPath $live -Force }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Ensure-Directory (Split-Path $live -Parent)
            Copy-Item -LiteralPath $backup -Destination $live -Force
        }
    }
    Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
    Write-Notice 'Restored the previously working generated soundtrack after an interrupted or failed sync.'
}

function Start-OutputTransaction([object[]]$Tracks) {
    Restore-SyncBackup
    Ensure-Directory $script:BackupDir
    $backupMedia = Join-Path $script:BackupDir 'Media'
    Ensure-Directory $backupMedia

    foreach ($pair in @(
        @((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk'), (Join-Path $script:BackupDir 'eu4_soundtrack_music.bnk')),
        @((Join-Path $script:BanksDir 'eu4_soundtrack_media.bnk'), (Join-Path $script:BackupDir 'eu4_soundtrack_media.bnk')),
        @((Join-Path $script:BanksDir 'SoundbanksInfo.json'), (Join-Path $script:BackupDir 'SoundbanksInfo.json')),
        @($script:TrackDefinitionPath, (Join-Path $script:BackupDir 'music_player_tracks.txt')),
        @($script:LocalizationPath, (Join-Path $script:BackupDir 'localization.yml')),
        @($script:StatePath, (Join-Path $script:BackupDir 'generated-state.json'))
    )) {
        if (Test-Path -LiteralPath $pair[0] -PathType Leaf) {
            Copy-Item -LiteralPath $pair[0] -Destination $pair[1] -Force
        }
    }

    $currentIds = @{}
    foreach ($track in $Tracks) { $currentIds[[string]$track.WemId] = $true }
    $oldTracks = @{}
    $oldIds = @()
    $stateReliable = $false
    if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
        try {
            $oldState = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$oldState.upstream_commit -eq $script:UpstreamCommit -and $null -ne $oldState.tracks) {
                foreach ($oldTrack in @($oldState.tracks)) {
                    $id = Get-ValidatedWemId $oldTrack.wem_id
                    if ($null -ne $id) { $oldTracks[$id] = $oldTrack }
                }
                foreach ($value in @($oldState.generated_wem_ids)) {
                    $id = Get-ValidatedWemId $value
                    if ($null -ne $id) { $oldIds += $id }
                }
                $stateReliable = $true
            }
        } catch {
            $stateReliable = $false
        }
    }
    if (-not $stateReliable) {
        Write-Notice 'Generated-file state is missing or outdated; existing requested media will be reconverted.'
    }

    $mutableIds = @()
    $affectedExistingIds = @()
    foreach ($track in $Tracks) {
        $id = [string]$track.WemId
        $needsConversion = -not $stateReliable -or -not $oldTracks.ContainsKey($id) -or
            ([string]$oldTracks[$id].source_sha256 -ne [string]$track.SourceSha256)
        $live = Join-Path $script:MediaDir "$id.wem"
        if ($needsConversion -or -not (Test-Path -LiteralPath $live -PathType Leaf)) {
            $mutableIds += $id
            if (Test-Path -LiteralPath $live -PathType Leaf) {
                $affectedExistingIds += $id
                Write-Notice "Rebuilding converted media for $($track.File)"
            }
        }
    }
    foreach ($id in $oldIds) {
        if (-not $currentIds.ContainsKey($id)) {
            $live = Join-Path $script:MediaDir "$id.wem"
            if (Test-Path -LiteralPath $live -PathType Leaf) {
                $affectedExistingIds += $id
            }
        }
    }
    if (-not $stateReliable -and (Test-Path -LiteralPath $script:MediaDir -PathType Container)) {
        foreach ($file in Get-ChildItem -LiteralPath $script:MediaDir -File -Filter '*.wem') {
            $id = Get-ValidatedWemId $file.BaseName
            if ($null -ne $id -and $affectedExistingIds -notcontains $id -and -not $currentIds.ContainsKey($id)) {
                $affectedExistingIds += $id
            }
        }
    }

    foreach ($id in $affectedExistingIds) {
        $live = Join-Path $script:MediaDir "$id.wem"
        Copy-Item -LiteralPath $live -Destination (Join-Path $backupMedia "$id.wem") -Force
    }

    $transaction = [ordered]@{ initialized = $true; mutable_wem_ids = @($mutableIds) }
    $json = $transaction | ConvertTo-Json -Depth 3
    $transactionTemporary = Join-Path $script:BackupDir 'transaction.json.tmp'
    $transactionPath = Join-Path $script:BackupDir 'transaction.json'
    [IO.File]::WriteAllText($transactionTemporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $transactionTemporary -Destination $transactionPath -Force

    foreach ($id in $affectedExistingIds) {
        $live = Join-Path $script:MediaDir "$id.wem"
        if (Test-Path -LiteralPath $live -PathType Leaf) { Remove-Item -LiteralPath $live -Force }
    }
}

function Complete-OutputTransaction {
    if (Test-Path -LiteralPath $script:BackupDir -PathType Container) {
        Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
    }
}

function Test-WemFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            if ($stream.Length -le 22) { return $false }
            $bytes = New-Object byte[] 22
            if ($stream.Read($bytes, 0, 22) -ne 22) { return $false }
        } finally {
            $stream.Dispose()
        }
        return $bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and
            $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46 -and $bytes[20] -eq 0xff -and $bytes[21] -eq 0xff
    } catch {
        return $false
    }
}

function New-RiffChunk([string]$Id, [byte[]]$Body) {
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes($Id))
        $writer.Write([uint32]$Body.Length)
        $writer.Write($Body)
        if (($Body.Length % 2) -ne 0) { $writer.Write([byte]0) }
        return ,$stream.ToArray()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Add-WemEventLabel([string]$Path, [string]$EventName) {
    $source = [IO.File]::ReadAllBytes($Path)
    if ($source.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($source, 0, 4) -ne 'RIFF' -or
        [Text.Encoding]::ASCII.GetString($source, 8, 4) -ne 'WAVE') {
        throw "Cannot label an invalid WEM file: $Path"
    }

    $preservedChunks = New-Object 'Collections.Generic.List[byte[]]'
    $dataChunk = $null
    $position = 12
    while ($position + 8 -le $source.Length) {
        $id = [Text.Encoding]::ASCII.GetString($source, $position, 4)
        $size = [BitConverter]::ToUInt32($source, $position + 4)
        $total = 8 + [int64]$size + ($size % 2)
        if ($position + $total -gt $source.Length) { throw "Malformed RIFF chunk in $Path" }
        $raw = New-Object byte[] ([int]$total)
        [Array]::Copy($source, $position, $raw, 0, $raw.Length)
        if ($id -eq 'data') {
            $dataChunk = $raw
        } elseif ($id -notin @('cue ', 'LIST')) {
            $preservedChunks.Add($raw)
        }
        $position += [int]$total
    }
    if ($null -eq $dataChunk) { throw "WEM data chunk was not found: $Path" }

    $cueBody = New-Object byte[] 28
    [BitConverter]::GetBytes([uint32]1).CopyTo($cueBody, 0)
    [Text.Encoding]::ASCII.GetBytes('data').CopyTo($cueBody, 12)
    $cueChunk = New-RiffChunk 'cue ' $cueBody

    $nameBytes = [Text.Encoding]::ASCII.GetBytes($EventName)
    $labelBody = New-Object byte[] (4 + $nameBytes.Length + 1)
    [Array]::Copy($nameBytes, 0, $labelBody, 4, $nameBytes.Length)
    $labelChunk = New-RiffChunk 'labl' $labelBody
    $listBody = New-Object byte[] (4 + $labelChunk.Length)
    [Text.Encoding]::ASCII.GetBytes('adtl').CopyTo($listBody, 0)
    [Array]::Copy($labelChunk, 0, $listBody, 4, $labelChunk.Length)
    $listChunk = New-RiffChunk 'LIST' $listBody

    $outputStream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($outputStream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([uint32]0)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        foreach ($chunk in $preservedChunks) { $writer.Write($chunk) }
        $writer.Write($cueChunk)
        $writer.Write($listChunk)
        $writer.Write($dataChunk)
        $output = $outputStream.ToArray()
    } finally {
        $writer.Dispose()
        $outputStream.Dispose()
    }
    [BitConverter]::GetBytes([uint32]($output.Length - 8)).CopyTo($output, 4)

    $same = $source.Length -eq $output.Length
    if ($same) {
        for ($index = 0; $index -lt $source.Length; $index++) {
            if ($source[$index] -ne $output[$index]) { $same = $false; break }
        }
    }
    if (-not $same) {
        $temporary = "$Path.labeling"
        [IO.File]::WriteAllBytes($temporary, $output)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
        return $true
    }
    return $false
}

function Get-HircObjectMap([string]$BankPath) {
    $bank = [IO.File]::ReadAllBytes($BankPath)
    $chunksPosition = 0
    while ($chunksPosition + 8 -le $bank.Length) {
        $chunkName = [Text.Encoding]::ASCII.GetString($bank, $chunksPosition, 4)
        $chunkSize = [BitConverter]::ToUInt32($bank, $chunksPosition + 4)
        $chunkEnd = $chunksPosition + 8 + [int64]$chunkSize
        if ($chunkEnd -gt $bank.Length) { throw "Malformed sound-bank chunk in $BankPath" }
        if ($chunkName -eq 'HIRC') {
            if ($chunkSize -lt 4) { throw "Malformed HIRC chunk in $BankPath" }
            $count = [BitConverter]::ToUInt32($bank, $chunksPosition + 8)
            $objectPosition = $chunksPosition + 12
            $objects = @{}
            for ([uint32]$index = 0; $index -lt $count; $index++) {
                if ($objectPosition + 9 -gt $chunkEnd) { throw "Truncated HIRC object in $BankPath" }
                $objectType = $bank[$objectPosition]
                $objectSize = [BitConverter]::ToUInt32($bank, $objectPosition + 1)
                if ($objectSize -lt 4 -or $objectPosition + 5 + [int64]$objectSize -gt $chunkEnd) {
                    throw "Invalid HIRC object size in $BankPath"
                }
                $objectId = [BitConverter]::ToUInt32($bank, $objectPosition + 5)
                $objects[[string]$objectId] = [int]$objectType
                $objectPosition += 5 + [int]$objectSize
            }
            return $objects
        }
        $chunksPosition = [int]$chunkEnd
    }
    throw "HIRC chunk was not found in $BankPath"
}

function Assert-GeneratedMusicBank([string]$BankPath, [object[]]$Tracks) {
    $objects = Get-HircObjectMap $BankPath
    $playerPoolId = [string][uint32]0x3B5AE824
    if (-not $objects.ContainsKey($playerPoolId) -or $objects[$playerPoolId] -ne 13) {
        throw 'The generated bank does not contain the expected native Music Player container.'
    }
    foreach ($track in $Tracks) {
        $eventId = [string][uint32]$track.EventId
        if (-not $objects.ContainsKey($eventId) -or $objects[$eventId] -ne 4) {
            throw "The generated bank is missing the Music Player event for '$($track.Title)'."
        }
    }
}

function Clear-GeneratedMod {
    Restore-SyncBackup
    $ids = @()
    if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
        try {
            $oldState = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ids = @($oldState.generated_wem_ids)
        } catch {
            Write-Notice 'The generated-file state could not be read; known bank files will still be cleared.'
        }
    }
    foreach ($id in $ids) {
        $validId = Get-ValidatedWemId $id
        if ($null -eq $validId) { continue }
        $path = Join-Path $script:MediaDir "$validId.wem"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    foreach ($name in @('eu4_soundtrack_music.bnk', 'eu4_soundtrack_media.bnk', 'SoundbanksInfo.json')) {
        $path = Join-Path $script:BanksDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    foreach ($path in @($script:TrackDefinitionPath, $script:LocalizationPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
        Remove-Item -LiteralPath $script:StatePath -Force
    }
}

function Save-GeneratedState([object[]]$Tracks) {
    $state = [ordered]@{
        generated_wem_ids = @($Tracks | ForEach-Object { [string]$_.WemId })
        upstream_commit = $script:UpstreamCommit
        tracks = @($Tracks | ForEach-Object {
            [ordered]@{
                file = $_.File
                wem_id = [string]$_.WemId
                source_sha256 = $_.SourceSha256
            }
        })
    }
    $json = $state | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($script:StatePath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-GeneratedConverter([string]$ConverterPath) {
    $oldModDir = $env:EUV_MUSIC_MOD_DIR
    $oldSourceDir = $env:EUV_MUSIC_SOURCE_DIR
    try {
        $env:EUV_MUSIC_MOD_DIR = $script:ModDir
        $env:EUV_MUSIC_SOURCE_DIR = $script:TracksDir
        $converterOutput = @()
        & powershell.exe -NonInteractive -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ConverterPath 2>&1 |
            Tee-Object -Variable converterOutput | ForEach-Object { Write-Host $_ }
        $converterExitCode = $LASTEXITCODE
        if ($converterExitCode -ne 0) {
            throw "The audio converter exited with code $converterExitCode."
        }
        if (($converterOutput | Out-String) -match '(?im)^\[X\].*(failed|error)|Sound bank build failed') {
            throw 'The converter reported a sound-bank error. The library was not marked as synced.'
        }
    } finally {
        $env:EUV_MUSIC_MOD_DIR = $oldModDir
        $env:EUV_MUSIC_SOURCE_DIR = $oldSourceDir
    }
}

function Sync-Library {
    Write-Heading 'Syncing EUV Music Library'
    Install-LocalMod
    $manifest = Update-ManifestFromFiles
    $tracks = @(Get-ActiveTracks $manifest)
    if ($tracks.Count -eq 0) {
        Clear-GeneratedMod
        Write-Notice "No enabled audio files were found. The generated soundtrack is empty. Add MP3 files to:`n$($script:TracksDir)"
        return $false
    }

    Write-Host "Preparing $($tracks.Count) track(s)..."
    $gameBank = Find-GameBank @(Get-SteamRoots)
    Assert-Ffmpeg
    $converter = New-PatchedConverter $tracks $gameBank
    try {
        Start-OutputTransaction $tracks
        Invoke-GeneratedConverter $converter

        $missingWems = @($tracks | Where-Object { -not (Test-WemFile (Join-Path $script:MediaDir "$($_.WemId).wem")) })
        if ($missingWems.Count -gt 0) {
            $missingNames = ($missingWems | ForEach-Object { $_.File }) -join ', '
            throw "Conversion did not produce valid EU5 media for: $missingNames"
        }
        $labelsChanged = $false
        foreach ($track in $tracks) {
            if (Add-WemEventLabel (Join-Path $script:MediaDir "$($track.WemId).wem") $track.EventName) {
                $labelsChanged = $true
            }
        }
        if ($labelsChanged) {
            Write-Host 'Updating sound-bank prefetch data for Music Player labels...'
            Invoke-GeneratedConverter $converter
        }
        foreach ($bankName in @('eu4_soundtrack_music.bnk', 'eu4_soundtrack_media.bnk')) {
            $bankPath = Join-Path $script:BanksDir $bankName
            if (-not (Test-Path -LiteralPath $bankPath -PathType Leaf) -or (Get-Item -LiteralPath $bankPath).Length -lt 16) {
                throw "The converter did not produce a valid $bankName file."
            }
        }
        Assert-GeneratedMusicBank (Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk') $tracks
        Write-SoundbanksInfo $tracks
        Write-MusicPlayerRegistration $tracks
        Save-GeneratedState $tracks
        Complete-OutputTransaction
    } catch {
        Restore-SyncBackup
        throw
    }

    Write-Success "Synced $($tracks.Count) track(s)."
    Write-Host 'Enable EUV Music Library in EU5 Mods, then restart the game.' -ForegroundColor White
    return $true
}

function Import-LibraryMp3([string]$Path) {
    if ([IO.Path]::GetExtension($Path) -ne '.mp3') { throw 'Select an MP3 audio file.' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $tracks = [IO.Path]::GetFullPath($script:TracksDir).TrimEnd('\') + '\'
    if ($fullPath.StartsWith($tracks, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $destination = Join-Path $tracks ([IO.Path]::GetFileName($Path))
    $suffix = 2
    while ([IO.File]::Exists($destination)) {
        if ((Get-FileSha256 $Path) -eq (Get-FileSha256 $destination)) { return $false }
        $destination = Join-Path $tracks "$name ($suffix).mp3"
        $suffix++
    }
    [IO.File]::Copy($Path, $destination, $false)
    return $true
}

function Open-LibraryFolder {
    Install-LocalMod
    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:TracksDir)
}

function Show-MusicLibraryWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Windows.Forms.Application]::EnableVisualStyles()

    Install-LocalMod
    $form = New-Object Windows.Forms.Form
    $form.Text = $script:ToolName
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(940, 570)
    $form.MinimumSize = New-Object Drawing.Size(760, 480)

    $intro = New-Object Windows.Forms.Label
    $intro.Text = 'Add MP3 files, review the song list, then select Install Music. New songs play during war and peace.'
    $intro.AutoSize = $true
    $intro.Location = New-Object Drawing.Point(16, 16)
    $form.Controls.Add($intro)

    $addButton = New-Object Windows.Forms.Button
    $addButton.Text = 'Add MP3 Files'
    $addButton.Size = New-Object Drawing.Size(120, 32)
    $addButton.Location = New-Object Drawing.Point(16, 46)
    $form.Controls.Add($addButton)

    $openButton = New-Object Windows.Forms.Button
    $openButton.Text = 'Open Music Folder'
    $openButton.Size = New-Object Drawing.Size(145, 32)
    $openButton.Location = New-Object Drawing.Point(145, 46)
    $form.Controls.Add($openButton)

    $refreshButton = New-Object Windows.Forms.Button
    $refreshButton.Text = 'Refresh'
    $refreshButton.Size = New-Object Drawing.Size(90, 32)
    $refreshButton.Location = New-Object Drawing.Point(299, 46)
    $form.Controls.Add($refreshButton)

    $removeButton = New-Object Windows.Forms.Button
    $removeButton.Text = 'Remove Song'
    $removeButton.Size = New-Object Drawing.Size(110, 32)
    $removeButton.Location = New-Object Drawing.Point(398, 46)
    $form.Controls.Add($removeButton)

    $grid = New-Object Windows.Forms.DataGridView
    $grid.Location = New-Object Drawing.Point(16, 90)
    $grid.Size = New-Object Drawing.Size(908, 390)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.AutoGenerateColumns = $false
    $grid.BackgroundColor = [Drawing.SystemColors]::Window
    $grid.BorderStyle = 'Fixed3D'
    $grid.MultiSelect = $true
    $grid.SelectionMode = 'FullRowSelect'
    $grid.RowHeadersVisible = $false

    $idColumn = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $idColumn.Name = 'TrackId'
    $idColumn.Visible = $false
    [void]$grid.Columns.Add($idColumn)

    $titleColumn = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $titleColumn.Name = 'Title'
    $titleColumn.HeaderText = 'Title'
    $titleColumn.Width = 245
    [void]$grid.Columns.Add($titleColumn)

    $artistColumn = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $artistColumn.Name = 'Artist'
    $artistColumn.HeaderText = 'Artist'
    $artistColumn.Width = 200
    [void]$grid.Columns.Add($artistColumn)

    $assignmentColumn = New-Object Windows.Forms.DataGridViewComboBoxColumn
    $assignmentColumn.Name = 'Assignment'
    $assignmentColumn.HeaderText = 'Playback'
    $assignmentColumn.Width = 105
    [void]$assignmentColumn.Items.AddRange([object[]]@('Both', 'War', 'Peace'))
    [void]$grid.Columns.Add($assignmentColumn)

    $fileColumn = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $fileColumn.Name = 'File'
    $fileColumn.HeaderText = 'Managed MP3'
    $fileColumn.ReadOnly = $true
    $fileColumn.AutoSizeMode = 'Fill'
    [void]$grid.Columns.Add($fileColumn)
    $form.Controls.Add($grid)

    $statusLabel = New-Object Windows.Forms.Label
    $statusLabel.Text = 'Ready.'
    $statusLabel.AutoSize = $true
    $statusLabel.Location = New-Object Drawing.Point(16, 498)
    $statusLabel.Anchor = 'Bottom,Left'
    $form.Controls.Add($statusLabel)

    $progress = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(16, 525)
    $progress.Size = New-Object Drawing.Size(610, 22)
    $progress.Anchor = 'Bottom,Left,Right'
    $form.Controls.Add($progress)

    $implementButton = New-Object Windows.Forms.Button
    $implementButton.Text = 'Install Music'
    $implementButton.Size = New-Object Drawing.Size(180, 38)
    $implementButton.Location = New-Object Drawing.Point(744, 512)
    $implementButton.Anchor = 'Bottom,Right'
    $form.Controls.Add($implementButton)

    $pollTimer = New-Object Windows.Forms.Timer
    $pollTimer.Interval = 250

    $loadGrid = {
        $manifest = Update-ManifestFromFiles
        $grid.Rows.Clear()
        foreach ($track in @($manifest.tracks)) {
            $rowIndex = $grid.Rows.Add()
            $row = $grid.Rows[$rowIndex]
            $row.Cells['TrackId'].Value = [string]$track.id
            $row.Cells['Title'].Value = [string]$track.title
            $row.Cells['Artist'].Value = [string]$track.artist
            $row.Cells['Assignment'].Value = (Get-Culture).TextInfo.ToTitleCase(([string]$track.mood).ToLowerInvariant())
            $row.Cells['File'].Value = [string]$track.file
        }
        $statusLabel.Text = "$($grid.Rows.Count) MP3 file(s) detected."
        if ($null -eq $form.Tag) { $implementButton.Enabled = $grid.Rows.Count -gt 0 -or (Test-Path -LiteralPath $script:StatePath) }
    }

    $saveGrid = {
        [void]$grid.EndEdit()
        $manifest = Read-Manifest
        $byId = @{}
        foreach ($track in @($manifest.tracks)) { $byId[[string]$track.id] = $track }
        foreach ($row in $grid.Rows) {
            $id = [string]$row.Cells['TrackId'].Value
            if (-not $byId.ContainsKey($id)) { continue }
            $title = [string]$row.Cells['Title'].Value
            $artist = [string]$row.Cells['Artist'].Value
            if ([string]::IsNullOrWhiteSpace($title)) { throw "Title cannot be empty for $($row.Cells['File'].Value)." }
            if ([string]::IsNullOrWhiteSpace($artist)) { $artist = 'Unknown Artist' }
            $assignment = ([string]$row.Cells['Assignment'].Value).ToLowerInvariant()
            if ($script:ValidMoods -notcontains $assignment) { throw "Choose War, Peace, or Both for '$title'." }
            $byId[$id].title = $title.Trim()
            $byId[$id].artist = $artist.Trim()
            $byId[$id].mood = $assignment
        }
        Save-Manifest $manifest
    }

    $addButton.Add_Click({
        $picker = New-Object Windows.Forms.OpenFileDialog
        try {
            $picker.Title = 'Select MP3 files'
            $picker.Filter = 'MP3 audio (*.mp3)|*.mp3'
            $picker.Multiselect = $true
            if ($picker.ShowDialog($form) -ne 'OK') { return }
            & $saveGrid
            $added = 0
            foreach ($path in $picker.FileNames) {
                if (Import-LibraryMp3 $path) { $added++ }
            }
            & $loadGrid
            $statusLabel.Text = "Added $added MP3 file(s). Select Install Music to update EU5."
        } catch {
            $message = $_.Exception.Message
            & $loadGrid
            [Windows.Forms.MessageBox]::Show($message, $script:ToolName, 'OK', 'Error') | Out-Null
        } finally { $picker.Dispose() }
    })
    $openButton.Add_Click({ Open-LibraryFolder })
    $refreshButton.Add_Click({
        try { & $saveGrid; & $loadGrid } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:ToolName, 'OK', 'Error') | Out-Null }
    })
    $removeButton.Add_Click({
        if ($grid.SelectedRows.Count -eq 0) {
            [Windows.Forms.MessageBox]::Show('Select one or more songs first.', $script:ToolName, 'OK', 'Information') | Out-Null
            return
        }
        $answer = [Windows.Forms.MessageBox]::Show(
            'Move the selected library copies to the Recycle Bin?',
            $script:ToolName, 'YesNo', 'Warning')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        try {
            & $saveGrid
            foreach ($row in $grid.SelectedRows) {
                $relative = [string]$row.Cells['File'].Value
                $path = Join-Path $script:TracksDir ($relative -replace '/', '\')
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                        $path,
                        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                }
            }
            & $loadGrid
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:ToolName, 'OK', 'Error') | Out-Null
        }
    })
    $implementButton.Add_Click({
        try {
            & $saveGrid
            if ($grid.Rows.Count -gt 0 -and -not (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)) {
                $installer = Get-Command winget.exe -ErrorAction SilentlyContinue
                if (-not $installer) { throw 'Install App Installer from Microsoft Store, then reopen EUV Music Library Tool for FFmpeg setup.' }
                $answer = [Windows.Forms.MessageBox]::Show('FFmpeg converts MP3 audio for EU5. Start the FFmpeg installer? After installation, close and reopen EUV Music Library Tool, then select Install Music.', $script:ToolName, 'YesNo', 'Question')
                if ($answer -eq 'Yes') { Start-Process -FilePath $installer.Source -ArgumentList 'install --id Gyan.FFmpeg --exact --source winget' }
                return
            }
            $form.UseWaitCursor = $true
            $grid.Enabled = $false
            $addButton.Enabled = $false
            $implementButton.Enabled = $false
            $openButton.Enabled = $false
            $refreshButton.Enabled = $false
            $removeButton.Enabled = $false
            $progress.Style = 'Marquee'
            $statusLabel.Text = 'Converting and rebuilding the EU5 local mod...'
            [Windows.Forms.Application]::DoEvents()
            $form.Tag = Start-Job -ScriptBlock {
                param($ToolScript, $UserDirectory)
                $output = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ToolScript `
                    -Action Sync -Eu5UserDir $UserDirectory 2>&1)
                if ($LASTEXITCODE -ne 0) { throw (($output | Out-String).Trim()) }
                return $output
            } -ArgumentList $PSCommandPath, $script:Eu5UserDir
            $pollTimer.Start()
        } catch {
            $statusLabel.Text = 'Music installation stopped.'
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:ToolName, 'OK', 'Error') | Out-Null
            $progress.Style = 'Blocks'
            $grid.Enabled = $true
            $addButton.Enabled = $true
            $implementButton.Enabled = $true
            $openButton.Enabled = $true
            $refreshButton.Enabled = $true
            $removeButton.Enabled = $true
            $form.UseWaitCursor = $false
        }
    })

    $pollTimer.Add_Tick({
        $job = $form.Tag
        if ($null -eq $job -or $job.State -notin @('Completed', 'Failed', 'Stopped')) { return }
        $pollTimer.Stop()
        $jobState = $job.State
        $reason = if ($job.ChildJobs.Count -gt 0) { $job.ChildJobs[0].JobStateInfo.Reason } else { $null }
        $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        Remove-Job -Job $job -Force
        $form.Tag = $null
        $grid.Enabled = $true
        $addButton.Enabled = $true
        $progress.Style = 'Blocks'
        $implementButton.Enabled = $true
        $openButton.Enabled = $true
        $refreshButton.Enabled = $true
        $removeButton.Enabled = $true
        $form.UseWaitCursor = $false

        if ($jobState -eq 'Completed') {
            & $loadGrid
            $statusLabel.Text = 'Music library updated.'
            [Windows.Forms.MessageBox]::Show(
                'Library update complete. Open Europa Universalis V through Steam. In Mods, enable EUV Music Library and restart the game.',
                $script:ToolName, 'OK', 'Information') | Out-Null
        } else {
            $message = if ($null -ne $reason -and -not [string]::IsNullOrWhiteSpace($reason.Message)) {
                $reason.Message
            } else {
                ($output | Out-String).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($message)) { $message = 'Conversion failed. See the console output for details.' }
            if ($message.Length -gt 3000) { $message = $message.Substring($message.Length - 3000) }
            $statusLabel.Text = 'Music installation stopped.'
            [Windows.Forms.MessageBox]::Show($message, $script:ToolName, 'OK', 'Error') | Out-Null
        }
    })

    $form.Add_FormClosing({
        param($closingSender, $closingEventArgs)
        if ($null -ne $form.Tag -and $form.Tag.State -in @('Running', 'NotStarted')) {
            $closingEventArgs.Cancel = $true
            [Windows.Forms.MessageBox]::Show('Wait for conversion to finish before closing the utility.', $script:ToolName, 'OK', 'Information') | Out-Null
        }
    })

    & $loadGrid
    [void]$form.ShowDialog()
}

try {
    switch ($Action) {
        'Menu' { Show-MusicLibraryWindow }
        'Install' { Install-LocalMod }
        'Sync' { [void](Sync-Library) }
        'OpenLibrary' { Open-LibraryFolder }
    }
} catch {
    Write-Host ''
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
