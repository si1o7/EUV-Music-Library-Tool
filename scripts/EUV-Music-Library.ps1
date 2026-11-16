#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Install', 'Sync', 'SyncAndLaunch', 'OpenLibrary', 'EditManifest')]
    [string]$Action = 'Menu',

    [string]$Eu5UserDir = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:ToolName = 'EUV Music Library Tool'
$script:UpstreamCommit = '6e6480d442c365bec7cd2a5dde00966df4f89e81'
$script:UpstreamSha256 = '2f5d7cafc616668f19414077fba8189916c3e350c96b57a7d3f7b002b4c139cf'
$script:UpstreamUrl = "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/$($script:UpstreamCommit)/EU4_Soundtrack_Setup.ps1"
$script:SupportedExtensions = @('.mp3', '.flac', '.wav', '.ogg', '.m4a', '.aac', '.opus', '.wma')
$script:ValidMoods = @('both', 'war', 'peace')
$script:ValidCultures = @('', 'european', 'east_asian', 'african', 'middle_east', 'indian', 'north_american', 'south_american')

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

function Get-EventName([string]$RelativePath) {
    $name = [IO.Path]::GetFileNameWithoutExtension($RelativePath).ToLowerInvariant()
    $slug = [regex]::Replace($name, '[^a-z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'track' }
    if ($slug.Length -gt 36) { $slug = $slug.Substring(0, 36).TrimEnd('_') }

    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($RelativePath.ToLowerInvariant())
        $suffix = ([BitConverter]::ToString($sha1.ComputeHash($bytes))).Replace('-', '').Substring(0, 10).ToLowerInvariant()
    } finally {
        $sha1.Dispose()
    }
    return "MusicPlayer_euvlib_${slug}_${suffix}"
}

function New-DefaultManifest {
    return [ordered]@{
        version = 1
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
    $existing = @{}
    foreach ($track in @($manifest.tracks)) {
        if ($null -ne $track.file) {
            $existing[[string]$track.file.ToLowerInvariant()] = $track
        }
    }

    $updated = @()
    $newCount = 0
    foreach ($file in Get-SourceFiles) {
        $relative = $file.FullName.Substring($script:TracksDir.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($relative.Contains('|')) {
            Write-Notice "Skipped '$relative': the | character is not supported in track paths."
            continue
        }
        $key = $relative.ToLowerInvariant()
        if ($existing.ContainsKey($key)) {
            $track = $existing[$key]
            $enabled = if ($null -eq $track.PSObject.Properties['enabled']) { $true } else { $track.enabled }
            $mood = if ($null -eq $track.PSObject.Properties['mood'] -or [string]::IsNullOrWhiteSpace([string]$track.mood)) { 'both' } else { [string]$track.mood }
            $culture = if ($null -eq $track.PSObject.Properties['culture']) { '' } else { [string]$track.culture }
            $updated += [ordered]@{
                file = $relative
                enabled = $enabled
                mood = $mood
                culture = $culture
            }
        } else {
            $updated += [ordered]@{
                file = $relative
                enabled = $true
                mood = 'both'
                culture = ''
            }
            $newCount++
        }
    }

    $manifest = [ordered]@{ version = 1; tracks = $updated }
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
        $culture = if ($null -eq $track.PSObject.Properties['culture']) { '' } else { ([string]$track.culture).ToLowerInvariant() }
        if ($script:ValidCultures -notcontains $culture) {
            throw "Invalid culture '$culture' for '$relative'. See README.md for supported values."
        }

        $fullPath = Join-Path $script:TracksDir ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Notice "Skipping missing file: $relative"
            continue
        }

        $eventName = Get-EventName $relative
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
            SourceSha256 = Get-FileSha256 $fullPath
            EventName = $eventName
            Mood = $upstreamMood
            Culture = $culture
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

function Assert-Ffmpeg {
    $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        throw "FFmpeg was not found. Install it in Windows Terminal with:`nwinget install --id Gyan.FFmpeg`nThen restart this tool."
    }
}

function Get-VerifiedUpstreamScript {
    Ensure-Directory $script:CacheDir
    $validCache = (Test-Path -LiteralPath $script:UpstreamPath -PathType Leaf) -and ((Get-FileSha256 $script:UpstreamPath) -eq $script:UpstreamSha256)
    if (-not $validCache) {
        Write-Host 'Downloading the pinned EU5 Wwise converter from its original repository...'
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

function New-PatchedConverter([object[]]$Tracks) {
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

    $patched = $patched.Replace('EU4 Soundtrack for EU5', 'EUV Music Library')
    $patched = $patched.Replace('Locating EU4...', 'Locating your music library...')
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

function Get-ValidatedWemId([object]$Value) {
    $text = [string]$Value
    [uint32]$parsed = 0
    if (-not [uint32]::TryParse($text, [ref]$parsed)) { return $null }
    return [string]$parsed
}

function Restore-SyncBackup {
    if (-not (Test-Path -LiteralPath $script:BackupDir -PathType Container)) { return }
    $transactionPath = Join-Path $script:BackupDir 'transaction.json'
    $mutableIds = @()
    if (Test-Path -LiteralPath $transactionPath -PathType Leaf) {
        try {
            $transaction = Get-Content -LiteralPath $transactionPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($value in @($transaction.mutable_wem_ids)) {
                $id = Get-ValidatedWemId $value
                if ($null -ne $id) { $mutableIds += $id }
            }
        } catch {
            Write-Notice 'The interrupted-sync record was unreadable; restoring the known bank files and media backup.'
        }
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
    foreach ($name in @('eu4_soundtrack_music.bnk', 'eu4_soundtrack_media.bnk', 'SoundbanksInfo.json')) {
        $live = Join-Path $script:BanksDir $name
        $backup = Join-Path $script:BackupDir $name
        if (Test-Path -LiteralPath $live -PathType Leaf) { Remove-Item -LiteralPath $live -Force }
        if (Test-Path -LiteralPath $backup -PathType Leaf) { Copy-Item -LiteralPath $backup -Destination $live -Force }
    }
    Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
    Write-Notice 'Restored the previously working generated soundtrack after an interrupted or failed sync.'
}

function Start-OutputTransaction([object[]]$Tracks) {
    Restore-SyncBackup
    Ensure-Directory $script:BackupDir
    $backupMedia = Join-Path $script:BackupDir 'Media'
    Ensure-Directory $backupMedia

    foreach ($name in @('eu4_soundtrack_music.bnk', 'eu4_soundtrack_media.bnk', 'SoundbanksInfo.json')) {
        $live = Join-Path $script:BanksDir $name
        if (Test-Path -LiteralPath $live -PathType Leaf) {
            Copy-Item -LiteralPath $live -Destination (Join-Path $script:BackupDir $name) -Force
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
    foreach ($track in $Tracks) {
        $id = [string]$track.WemId
        $needsConversion = -not $stateReliable -or -not $oldTracks.ContainsKey($id) -or
            ([string]$oldTracks[$id].source_sha256 -ne [string]$track.SourceSha256)
        $live = Join-Path $script:MediaDir "$id.wem"
        if ($needsConversion -or -not (Test-Path -LiteralPath $live -PathType Leaf)) {
            $mutableIds += $id
            if (Test-Path -LiteralPath $live -PathType Leaf) {
                Move-Item -LiteralPath $live -Destination (Join-Path $backupMedia "$id.wem") -Force
                Write-Notice "Rebuilding converted media for $($track.File)"
            }
        }
    }
    foreach ($id in $oldIds) {
        if (-not $currentIds.ContainsKey($id)) {
            $live = Join-Path $script:MediaDir "$id.wem"
            if (Test-Path -LiteralPath $live -PathType Leaf) {
                Move-Item -LiteralPath $live -Destination (Join-Path $backupMedia "$id.wem") -Force
            }
        }
    }

    $transaction = [ordered]@{ mutable_wem_ids = @($mutableIds) }
    $json = $transaction | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText((Join-Path $script:BackupDir 'transaction.json'), $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Complete-OutputTransaction {
    if (Test-Path -LiteralPath $script:BackupDir -PathType Container) {
        Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
    }
}

function Test-WemFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        return $bytes.Length -gt 22 -and $bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and
            $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46 -and $bytes[20] -eq 0xff -and $bytes[21] -eq 0xff
    } catch {
        return $false
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

function Sync-Library {
    Write-Heading 'Syncing EUV Music Library'
    Install-LocalMod
    Assert-Ffmpeg
    $manifest = Update-ManifestFromFiles
    $tracks = @(Get-ActiveTracks $manifest)
    if ($tracks.Count -eq 0) {
        Clear-GeneratedMod
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:TracksDir)
        Write-Notice "No enabled audio files were found. The generated soundtrack is empty. Add MP3 files to:`n$($script:TracksDir)"
        return $false
    }

    Write-Host "Preparing $($tracks.Count) track(s)..."
    $converter = New-PatchedConverter $tracks
    Start-OutputTransaction $tracks
    try {
        $oldModDir = $env:EUV_MUSIC_MOD_DIR
        $oldSourceDir = $env:EUV_MUSIC_SOURCE_DIR
        try {
            $env:EUV_MUSIC_MOD_DIR = $script:ModDir
            $env:EUV_MUSIC_SOURCE_DIR = $script:TracksDir
            $converterOutput = @()
            & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $converter 2>&1 |
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

        $missingWems = @($tracks | Where-Object { -not (Test-WemFile (Join-Path $script:MediaDir "$($_.WemId).wem")) })
        if ($missingWems.Count -gt 0) {
            $missingNames = ($missingWems | ForEach-Object { $_.File }) -join ', '
            throw "Conversion did not produce valid EU5 media for: $missingNames"
        }
        foreach ($bankName in @('eu4_soundtrack_music.bnk', 'eu4_soundtrack_media.bnk')) {
            $bankPath = Join-Path $script:BanksDir $bankName
            if (-not (Test-Path -LiteralPath $bankPath -PathType Leaf) -or (Get-Item -LiteralPath $bankPath).Length -lt 16) {
                throw "The converter did not produce a valid $bankName file."
            }
        }
        Write-SoundbanksInfo $tracks
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

function Open-LibraryFolder {
    Install-LocalMod
    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:TracksDir)
}

function Edit-ManifestFile {
    Install-LocalMod
    Update-ManifestFromFiles | Out-Null
    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ManifestPath)
}

function Launch-Eu5 {
    Start-Process 'steam://rungameid/3450310'
}

function Show-Menu {
    while ($true) {
        Write-Heading $script:ToolName
        Write-Host '1. Sync library'
        Write-Host '2. Sync and launch EU5'
        Write-Host '3. Open music folder'
        Write-Host '4. Edit track assignments'
        Write-Host '5. Exit'
        Write-Host ''
        $choice = Read-Host 'Choose an option'
        switch ($choice) {
            '1' { [void](Sync-Library); Read-Host 'Press Enter to return to the menu' | Out-Null }
            '2' { if (Sync-Library) { Launch-Eu5 }; return }
            '3' { Open-LibraryFolder }
            '4' { Edit-ManifestFile }
            '5' { return }
            default { Write-Notice 'Enter a number from 1 to 5.' }
        }
    }
}

try {
    switch ($Action) {
        'Menu' { Show-Menu }
        'Install' { Install-LocalMod }
        'Sync' { [void](Sync-Library) }
        'SyncAndLaunch' { if (Sync-Library) { Launch-Eu5 } }
        'OpenLibrary' { Open-LibraryFolder }
        'EditManifest' { Edit-ManifestFile }
    }
} catch {
    Write-Host ''
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
