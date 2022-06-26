[CmdletBinding()]
Param(
  [Parameter(ParameterSetName = "Automate")]
  [string] $VideoFilePath,

  [Parameter(ParameterSetName = "Automate")]
  [string] $OutputFileName,
  
  [Parameter(ParameterSetName = "Automate")]
  [switch] $Automate,

  [string] $StartTime = "0:00",
  [string] $Length = "1:00:00",
  [string] $VideoBitrate = "68M",
  [string] $AudioBitrate = "384k",
  [int]    $GameAudioDelay = 50,
  [string] $GameVolume = "1.0",
  [string] $MicVolume = "1.0",
  [switch] $MixAudioChannels,
  [switch] $Preview,
  [switch] $KeepOriginal,

  [string] $Game = $null
)

if ((($fileInfo = Get-ChildItem $PSCommandPath) | Select-Object -ExpandProperty LinkType) -eq 'SymbolicLink') {
  Write-Verbose "Detected symlink $fileInfo"
}

$config = Get-Content "$PSScriptRoot\trimvideo.config.json" | ConvertFrom-Json -AsHashtable

$UploadsOutputPath = $config.uploadsOutputPath
Write-Verbose "`$UploadsOutputPath = $UploadsOutputPath"
if (!$UploadsOutputPath) {
  Write-Error "Output path '$UploadsOutputPath' is invalid"
  exit 1
}

$FullPathToFfmpeg = $config.fullPathToFfmpeg
Write-Verbose "`$FullPathToFfmpeg = $FullPathToFfmpeg"
if (!(Test-Path $FullPathToFfmpeg)) {
  Write-Error "ffmpeg path '$FullPathToFfmpeg' is invalid"
  exit 1
}

$FullPathToShadowPlay = $config.fullPathToShadowPlay
Write-Verbose "`$FullPathToShadowPlay = $FullPathToShadowPlay"
if (!(Test-Path $FullPathToShadowPlay)) {
  Write-Error "ShadowPlay path '$FullPathToShadowPlay' is invalid"
  exit 1
}

$FullPathToVlc = $config.fullPathToVlc
Write-Verbose "`$FullPathToVlc = $FullPathToVlc"
if (!(Test-Path $FullPathToVlc)) {
  Write-Error "VLC path '$FullPathToVlc' is invalid"
  exit 1
}

$uploadsPath = "$FullPathToShadowPlay\uploads"
if (!(Test-Path $uploadsPath)) {
  New-Item -Path $uploadsPath -ItemType Directory | Out-Null

  Write-Verbose "Created directory '$uploadsPath'"
}

$trashPath = "$FullPathToShadowPlay\trash"
if (!(Test-Path $trashPath)) {
  New-Item -Name $trashPath -ItemType Directory | Out-Null

  Write-Verbose "Created directory '$trashPath'"
}

function Kill-Vlc {
  $sw = [System.Diagnostics.Stopwatch]::new()
  $sw.Start()

  if (PsList | Select-String 'vlc') {
    PsKill 'vlc.exe' | Out-Null
  }

  while (PsList | Select-String 'vlc') {
    Write-Verbose "VLC still in process list, checking again"

    if ($sw.ElapsedMilliseconds -gt 5000) {
      throw "Failed to kill VLC in a reasonable amount of time"
    }

    Start-Sleep -Milliseconds 500
  }

  $sw.Stop()
}

function SendFileToRecycleBin($path) {
  # prevent VLC from blocking the delete by having a file lock on what we're deleting
  Kill-Vlc

  Move-Item $path $trashPath
}

function Get-VideoFiles {
  $pattern = "$($FullPathToShadowPlay -Replace '\\', '\\')\\(.*)\\"

  return Get-ChildItem $FullPathToShadowPlay -File -Recurse -Include "*mp4"
  | Where-Object { $_.FullName -NotLike '*uploads*' -and $_.FullName -NotLike "*trash*" -and $_.FullName -NotLike '*Temp*' -and $_.FullName -NotLike '*skip*' }
  | ForEach-Object {
    $filename = $_.FullName

    if (!($filename -Match $pattern)) {
      throw "Couldn't determine game name from filename '$filename'"
    }

    return @{
      Path = $_.FullName
      Game = $Matches[1]
    }
  }
}

function ProcessVideo {
  [CmdletBinding()]
  Param(
    [PSObject] $VideoData,
    [string] $FullPathToVideo
  )

  if (!$FullPathToVideo -and $VideoData) {
    $FullPathToVideo = $VideoData.Path
  }

  Write-Verbose "Processing '$FullPathToVideo'"

  if (!$FullPathToVideo -or $FullPathToVideo -eq '') {
    Write-Error "Cannot process a null or empty video path"
    exit 1
  }

  if ($Preview -or $Automate) {
    if ($VideoData) {
      Write-Host "Game: $($VideoData.Game)"

      if ($VideoData.Game -Match "\\") {
        Write-Verbose "Detected video in sub-folder, skipping"
        return 0
      }
    }

    & $FullPathToVlc $FullPathToVideo

    $NewStartTime = Read-Host "Start time"
    if ($NewStartTime) {
      if ($NewStartTime -eq 's') {
        Kill-Vlc

        $skipPath = (Resolve-Path (Join-Path $FullPathToVideo "..")).Path + "\skip"
        if (!(Test-Path $skipPath)) {
          New-Item -ItemType Directory -Path $skipPath | Out-Null
        }
        Move-Item $FullPathToVideo $skipPath

        return 0
      }

      Write-Verbose "Setting `$StartTime from $StartTime to $NewStartTime"
      $StartTime = $NewStartTime
    }

    $NewLength = Read-Host "Length"
    if ($NewLength) {
      Write-Verbose "Setting `$Length from $Length to $NewLength"
      $Length = $NewLength
    }

    $NewOutputFileName = Read-Host "File name"
    if ($NewOutputFileName) {
      Write-Verbose "Setting `$OutputFileName from $OutputFileName to $NewOutputFileName"
      $OutputFileName = $NewOutputFileName
    }

    $ExtendedOptions = Read-Host "Set extended options?"
    if ($ExtendedOptions.ToLower() -eq 'y') {
      $DeleteWithoutProcessing = Read-Host "Delete without processing?"
      if ($DeleteWithoutProcessing.ToLower() -eq 'y') {
        SendFileToRecycleBin $FullPathToVideo
        return
      }

      $NewMixAudioChannels = Read-Host "Mix audio channels?"
      if ($NewMixAudioChannels.ToLower() -eq 'y') {
        Write-Verbose "Setting `$MixAudioChannels from $MixAudioChannels to $NewMixAudioChannels"
        $MixAudioChannels = $NewMixAudioChannels
      }
      else {
        $MixAudioChannels = $false
      }
    }
  }

  Write-Verbose "Using file path $FullPathToVideo"

  $Date = (Get-ChildItem $FullPathToVideo).CreationTime.ToString("yyyy.MM.ddTHH.mm.ss")

  $OutputFileName = "$($VideoData.Game) - $OutputFileName - $Date"
  if (!($OutputFileName -Match "\.mp4")){
    $OutputFileName += ".mp4"
  }

  if (!(Test-Path $uploadsPath)) {
    New-Item $uploadsPath -ItemType Directory
    Write-Verbose "Created '$uploadsPath'"
  }

  $msg = "Feel free to use this footage for your own purposes. I would simply ask that you include a credit back to me for it."

  [string[]]$opts = @(
    "-i", $FullPathToVideo
    "-ss",  $StartTime
    "-t", $Length
    "-b:v", $VideoBitrate
    "-b:a", $AudioBitrate
    "-movflags", "faststart"
    "-profile:v", "high"
    "-level:v", "4.0"
    "-vf", "scale=3840x2160:flags=lanczos"
  )

  if ($MixAudioChannels) {
    # frame delta appears to be 3, 3 * (1/60) = 50 milliseconds
    $opts = @("-itsoffset", ($GameAudioDelay/1000).ToString()) + $opts
    $opts += "-filter_complex", "[0:a:0]adelay=$GameAudioDelay|$GameAudioDelay,volume=$GameVolume[game];[0:a:1]acopy,volume=$MicVolume[mic];[game][mic]amerge=inputs=2[mix]", "-ac", "2", "-map", "0:v", "-map", "[mix]"
  }

  $opts += "$UploadsOutputPath\$OutputFileName"

  Write-Verbose "Using options: $opts"

  try {
    & $FullPathToFfmpeg @opts

    if ($? -and !$KeepOriginal) {
      SendFileToRecycleBin $FullPathToVideo
    }
  } catch {
    throw $_
  }
}

function main {
  if ($Automate) {
    $files = Get-VideoFiles

    foreach ($file in $files) {
      ProcessVideo $file
    }
  } else {
    ProcessVideo $VideoFilePath
  }
}

main
