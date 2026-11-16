#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("euv-music-library-tests-" + [Guid]::NewGuid().ToString('N'))
$scriptPath = Join-Path $PSScriptRoot '..\scripts\EUV-Music-Library.ps1'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

try {
    . $scriptPath -Action Install -Eu5UserDir $testRoot

    $steam = Join-Path $testRoot 'Steam'
    $library = Join-Path $testRoot 'Second Library'
    $apps = Join-Path $library 'steamapps'
    $bank = Join-Path $apps 'common\Custom EU5\game\loading_screen\sound\banks\windows\sb_music_logic.bnk'
    Ensure-Directory (Split-Path $bank)
    Ensure-Directory (Join-Path $steam 'steamapps')
    [IO.File]::WriteAllText((Join-Path $steam 'steamapps\libraryfolders.vdf'), ('"path" "' + $library.Replace('\', '\\') + '"'))
    [IO.File]::WriteAllText((Join-Path $apps 'appmanifest_3450310.acf'), '"installdir" "Custom EU5"')
    [IO.File]::WriteAllBytes($bank, [byte[]]@(0))
    Assert-True ((Find-GameBank @($steam)) -eq $bank) 'Steam library and custom install directory should resolve the game bank'
    Remove-Item -LiteralPath $bank
    $missingMessage = ''
    try { Find-GameBank @($steam) } catch { $missingMessage = $_.Exception.Message }
    Assert-True ($missingMessage -like '*Verify integrity*') 'missing game files should produce Steam repair instructions'

    $sample = Join-Path $testRoot 'sample.mp3'
    [IO.File]::WriteAllBytes($sample, [byte[]]@(1))
    Assert-True (Import-LibraryMp3 $sample) 'first import should copy audio'
    Assert-True (-not (Import-LibraryMp3 $sample)) 'repeat import should skip identical audio'
    [IO.File]::WriteAllBytes($sample, [byte[]]@(2))
    Assert-True (Import-LibraryMp3 $sample) 'a filename collision should preserve both recordings'
    $firstCopy = Join-Path $script:TracksDir 'sample.mp3'
    $secondCopy = Join-Path $script:TracksDir 'sample (2).mp3'
    Assert-True (([IO.File]::ReadAllBytes($firstCopy))[0] -eq 1) 'original library copy should remain intact'
    Assert-True (([IO.File]::ReadAllBytes($secondCopy))[0] -eq 2) 'numbered copy should contain new audio'
    Remove-Item -LiteralPath $firstCopy, $secondCopy

    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) { $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue }
    if (-not $ffmpeg) { throw 'FFmpeg is required to generate the MP3 metadata test fixture.' }

    $fixture = Join-Path $script:TracksDir 'tagged.mp3'
    & $ffmpeg.Source -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=0.1' `
        -metadata 'title=Été Nocturne' -metadata 'artist=Anaïs & Co.' -c:a libmp3lame $fixture -y
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg could not generate the MP3 fixture.' }

    $manifest = Update-ManifestFromFiles
    Assert-True ($manifest.version -eq 2) 'manifest schema should be version 2'
    Assert-True ($manifest.tracks.Count -eq 1) 'one MP3 should be detected'
    $trackId = [string]$manifest.tracks[0].id
    Assert-True ($trackId -match '^[a-f0-9]{24}$') 'track ID should be persistent and path-independent'
    Assert-True ($manifest.tracks[0].title -eq 'Été Nocturne') 'ID3 title should be read as Unicode'
    Assert-True ($manifest.tracks[0].artist -eq 'Anaïs & Co.') 'ID3 artist should be read as Unicode'
    Assert-True ($manifest.tracks[0].mood -eq 'both') 'new tracks should default to Both'

    $largeFrameFixture = Join-Path $script:TracksDir 'large-frame.mp3'
    $tagBytes = New-Object 'Collections.Generic.List[byte]'
    function Add-Id3v23Frame([string]$Name, [byte[]]$Payload) {
        $tagBytes.AddRange([Text.Encoding]::ASCII.GetBytes($Name))
        $size = $Payload.Length
        $tagBytes.Add([byte](($size -shr 24) -band 0xff))
        $tagBytes.Add([byte](($size -shr 16) -band 0xff))
        $tagBytes.Add([byte](($size -shr 8) -band 0xff))
        $tagBytes.Add([byte]($size -band 0xff))
        $tagBytes.Add(0)
        $tagBytes.Add(0)
        $tagBytes.AddRange($Payload)
    }
    Add-Id3v23Frame 'COMM' (New-Object byte[] 300)
    Add-Id3v23Frame 'TIT2' ([byte[]]@(3) + [Text.Encoding]::UTF8.GetBytes('Title After Large Frame'))
    Add-Id3v23Frame 'TPE1' ([byte[]]@(3) + [Text.Encoding]::UTF8.GetBytes('Large Frame Artist'))
    $tagLength = $tagBytes.Count
    $header = [byte[]]@(0x49, 0x44, 0x33, 3, 0, 0,
        (($tagLength -shr 21) -band 0x7f), (($tagLength -shr 14) -band 0x7f),
        (($tagLength -shr 7) -band 0x7f), ($tagLength -band 0x7f))
    [IO.File]::WriteAllBytes($largeFrameFixture, $header + $tagBytes.ToArray())
    $largeMetadata = Read-Mp3Metadata $largeFrameFixture
    Assert-True ($largeMetadata.Title -eq 'Title After Large Frame') 'ID3v2.3 frames after a >255-byte frame should be parsed'
    Assert-True ($largeMetadata.Artist -eq 'Large Frame Artist') 'ID3v2.3 artist after a >255-byte frame should be parsed'
    Remove-Item -LiteralPath $largeFrameFixture -Force

    $duplicate = Join-Path $script:TracksDir 'a-duplicate.mp3'
    Copy-Item -LiteralPath $fixture -Destination $duplicate
    $withDuplicate = Update-ManifestFromFiles
    $duplicateIds = @($withDuplicate.tracks | ForEach-Object { [string]$_.id } | Select-Object -Unique)
    Assert-True ($duplicateIds.Count -eq 2) 'same-content files at different paths must receive distinct IDs'
    $originalAfterDuplicate = @($withDuplicate.tracks | Where-Object { $_.file -eq 'tagged.mp3' })[0]
    Assert-True ($originalAfterDuplicate.id -eq $trackId) 'a duplicate file must not steal an exact-path identity'
    Remove-Item -LiteralPath $duplicate -Force
    $manifest = Update-ManifestFromFiles

    $renamed = Join-Path $script:TracksDir 'renamed.mp3'
    Move-Item -LiteralPath $fixture -Destination $renamed
    $manifest.tracks[0].mood = 'war'
    Save-Manifest $manifest
    $manifest = Update-ManifestFromFiles
    Assert-True ($manifest.tracks[0].id -eq $trackId) 'renaming unchanged audio should preserve its ID'
    Assert-True ($manifest.tracks[0].mood -eq 'war') 'renaming should preserve assignment'

    $active = @(Get-ActiveTracks $manifest)
    Assert-True ($active.Count -eq 1) 'one active track should be generated'
    Assert-True ($active[0].EventName -eq "MusicPlayer_euvlib_$trackId") 'event name should derive from the stable ID'
    Assert-True ($active[0].Mood -eq 'war') 'War assignment should reach the converter'

    $wemPath = Join-Path $script:MediaDir "$($active[0].WemId).wem"
    $wem = New-Object byte[] 100
    [Text.Encoding]::ASCII.GetBytes('RIFF').CopyTo($wem, 0)
    [Text.Encoding]::ASCII.GetBytes('WAVE').CopyTo($wem, 8)
    [Text.Encoding]::ASCII.GetBytes('fmt ').CopyTo($wem, 12)
    [BitConverter]::GetBytes([uint32]66).CopyTo($wem, 16)
    $wem[20] = 0xff
    $wem[21] = 0xff
    [BitConverter]::GetBytes([uint32]48000).CopyTo($wem, 24)
    [BitConverter]::GetBytes([uint32]96000).CopyTo($wem, 44)
    [Text.Encoding]::ASCII.GetBytes('data').CopyTo($wem, 86)
    [BitConverter]::GetBytes([uint32]6).CopyTo($wem, 90)
    [IO.File]::WriteAllBytes($wemPath, $wem)
    Assert-True (Test-WemFile $wemPath) 'fixture should satisfy WEM validation'
    Assert-True ([Math]::Abs((Get-WemDurationSeconds $wemPath) - 2.0) -lt 0.001) 'WEM duration should be read from fmt metadata'
    Assert-True (Add-WemEventLabel $wemPath $active[0].EventName) 'first label pass should update the WEM'
    Assert-True (-not (Add-WemEventLabel $wemPath $active[0].EventName)) 'repeated label pass should be idempotent'
    $labeledWem = [IO.File]::ReadAllBytes($wemPath)
    $validWemLength = $labeledWem.Length
    Assert-True ([Text.Encoding]::ASCII.GetString($labeledWem).Contains($active[0].EventName)) 'WEM cue label should contain the event name'
    Assert-True (Test-WemFile $wemPath) 'labeled WEM should remain valid'

    Write-SoundbanksInfo $active
    Write-MusicPlayerRegistration $active
    $soundbanks = Get-Content -LiteralPath (Join-Path $script:BanksDir 'SoundbanksInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $events = @($soundbanks.SoundBanksInfo.SoundBanks[0].Events)
    Assert-True ($events.Count -eq 1) 'SoundbanksInfo should contain one native-player event'
    Assert-True ($events[0].Name -eq $active[0].EventName) 'event name should match the track registration'

    $hircBodyStream = [IO.MemoryStream]::new()
    $hircBodyWriter = [IO.BinaryWriter]::new($hircBodyStream)
    $hircBodyWriter.Write([uint32]2)
    $hircBodyWriter.Write([byte]13)
    $hircBodyWriter.Write([uint32]4)
    $hircBodyWriter.Write([uint32]0x3B5AE824)
    $hircBodyWriter.Write([byte]4)
    $hircBodyWriter.Write([uint32]4)
    $hircBodyWriter.Write([uint32]$active[0].EventId)
    $hircBodyWriter.Flush()
    $hircBody = $hircBodyStream.ToArray()
    $hircBodyWriter.Dispose()
    $hircBodyStream.Dispose()

    $bankStream = [IO.MemoryStream]::new()
    $bankWriter = [IO.BinaryWriter]::new($bankStream)
    $bankWriter.Write([Text.Encoding]::ASCII.GetBytes('HIRC'))
    $bankWriter.Write([uint32]$hircBody.Length)
    $bankWriter.Write($hircBody)
    $bankWriter.Flush()
    $syntheticBank = Join-Path $testRoot 'native-player-graph.bnk'
    [IO.File]::WriteAllBytes($syntheticBank, $bankStream.ToArray())
    $bankWriter.Dispose()
    $bankStream.Dispose()

    Assert-GeneratedMusicBank $syntheticBank $active
    $hircObjects = Get-HircObjectMap $syntheticBank
    Assert-True ($hircObjects[[string][uint32]0x3B5AE824] -eq 13) 'bank validation should find the native Music Player container'
    Assert-True ($hircObjects[[string][uint32]$active[0].EventId] -eq 4) 'bank validation should find the generated player event'

    $definitionBytes = [IO.File]::ReadAllBytes($script:TrackDefinitionPath)
    Assert-True ($definitionBytes[0] -eq 0xef -and $definitionBytes[1] -eq 0xbb -and $definitionBytes[2] -eq 0xbf) 'track definitions should use UTF-8 BOM'
    $definitions = Get-Content -LiteralPath $script:TrackDefinitionPath -Raw -Encoding UTF8
    Assert-True ($definitions.Contains($active[0].EventName)) 'track definitions should reference the Wwise event'
    $localization = Get-Content -LiteralPath $script:LocalizationPath -Raw -Encoding UTF8
    Assert-True ($script:LocalizationPath -match 'main_menu[\\/]localization[\\/]music_player_gui') 'localization should use EU5 native Music Player discovery path'
    Assert-True ($localization.Contains('Été Nocturne')) 'title should be localized'
    Assert-True ($localization.Contains('Anaïs & Co.')) 'artist should be localized'

    [IO.File]::WriteAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk'), [byte[]](10, 20, 30, 40))
    [IO.File]::WriteAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_media.bnk'), [byte[]](50, 60, 70, 80))
    Save-GeneratedState $active
    $changedTrack = [PSCustomObject]@{
        File = $active[0].File
        WemId = $active[0].WemId
        SourceSha256 = 'changed-source-hash'
    }
    Start-OutputTransaction @($changedTrack)
    Assert-True (-not (Test-Path -LiteralPath $wemPath)) 'changed media should move into the transaction backup'
    [IO.File]::WriteAllBytes($wemPath, [byte[]](9, 9, 9))
    [IO.File]::WriteAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk'), [byte[]](9, 9, 9))
    Save-GeneratedState @($changedTrack)
    Restore-SyncBackup
    Assert-True (([IO.File]::ReadAllBytes($wemPath)).Length -eq $validWemLength) 'failed sync should restore the previous WEM'
    Assert-True (([IO.File]::ReadAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk')))[0] -eq 10) 'failed sync should restore the previous bank'
    $restoredState = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($restoredState.tracks[0].source_sha256 -eq $active[0].SourceSha256) 'failed sync should restore prior source hashes'

    Ensure-Directory $script:BackupDir
    [IO.File]::WriteAllBytes((Join-Path $script:BackupDir 'eu4_soundtrack_music.bnk'), [byte[]](99))
    Restore-SyncBackup
    Assert-True (([IO.File]::ReadAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk')))[0] -eq 10) 'an uninitialized backup must not delete or replace healthy output'

    Save-GeneratedState $active
    [IO.File]::WriteAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_music.bnk'), [byte[]](1, 2, 3))
    [IO.File]::WriteAllBytes((Join-Path $script:BanksDir 'eu4_soundtrack_media.bnk'), [byte[]](1, 2, 3))
    Clear-GeneratedMod
    Assert-True (-not (Test-Path -LiteralPath $wemPath)) 'empty-library cleanup should remove generated media'
    Assert-True (-not (Test-Path -LiteralPath $script:TrackDefinitionPath)) 'empty-library cleanup should remove player registration'
    Assert-True (-not (Test-Path -LiteralPath $script:LocalizationPath)) 'empty-library cleanup should remove localization'

    Write-Host 'All EUV Music Library Tool tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
