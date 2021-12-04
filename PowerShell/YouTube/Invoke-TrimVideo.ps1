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
  [string] $VideoBitrate = "24M",
  [string] $AudioBitrate = "384k",
  [string] $OutputPath = "D:\ShadowPlay\upload",
  [int]    $GameAudioDelay = 50,
  [string] $GameVolume = "1.0",
  [string] $MicVolume = "1.0",
  [switch] $MixAudioChannels,
  [switch] $Preview,
  [switch] $KeepOriginal,

  [string] $FullPathToFfmpeg = "C:\ProgramData\chocolatey\bin\ffmpeg.exe",
  [string] $FullPathToShadowPlay = "D:\ShadowPlay",
  [string] $FullPathToVlc = "C:\Program Files\VideoLAN\VLC\vlc.exe",

  [string] $Game = $null
)

Write-Verbose "`$FullPathToFfmpeg = $FullPathToFfmpeg"
if (!(Test-Path $FullPathToFfmpeg)) {
  Write-Error "ffmpeg path '$FullPathToFfmpeg' is invalid"
  exit 1
}

Write-Verbose "`$FullPathToShadowPlay = $FullPathToShadowPlay"
if (!(Test-Path $FullPathToShadowPlay)) {
  Write-Error "ShadowPlay path '$FullPathToShadowPlay' is invalid"
  exit 1
}

Write-Verbose "`$FullPathToVlc = $FullPathToVlc"
if (!(Test-Path $FullPathToVlc)) {
  Write-Error "VLC path '$FullPathToVlc' is invalid"
  exit 1
}

$uploadPath = "$FullPathToShadowPlay\upload"
if (!(Test-Path $uploadPath)) {
  New-Item -Name $uploadPath -ItemType Directory

  Write-Verbose "Created directory '$uploadPath'"
}

$trashPath = "$FullPathToShadowPlay\trash"
if (!(Test-Path $trashPath)) {
  New-Item -Name $trashPath -ItemType Directory

  Write-Verbose "Created directory '$trashPath'"
}

function SendFileToRecycleBin($path) {
  # prevent VLC from blocking the delete by having a file lock on what we're deleting
  if (PsList | Select-String 'vlc') { PsKill 'vlc.exe' }

  Move-Item $path $trashPath
}

function Get-VideoFiles {
  $pattern = "$($FullPathToShadowPlay -Replace '\\', '\\')\\(.*)\\"

  return Get-ChildItem $FullPathToShadowPlay -File -Recurse -Include "*mp4"
  | Where-Object { $_.FullName -NotLike '*upload*' -and $_.FullName -NotLike "*trash*" -and $_.FullName -NotLike '*Temp*' }
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
    & $FullPathToVlc $FullPathToVideo

    if ($VideoData) {
      Write-Host "Game: $($VideoData.Game)"
    }
    $NewStartTime = Read-Host "Start time"
    if ($NewStartTime) {
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

  Write-Verbose $FullPathToVideo
  $FullPathToVideo -Match "(\d{4}\.\d{2}\.\d{2}) - (\d{2}\.\d{2}\.\d{2})\.\d{2}\.DVR\.mp4" | Out-Null

  $Date = $Matches[1]
  if (!$?) {
    throw "Failed to parse date from video path '$FullPathToVideo'"
  }

  $Time = $Matches[2]
  if (!$?) {
    throw "Failed to parse time from video path '$FullPathToVideo'"
  }

  $OutputFileName = "$($VideoData.Game) - $OutputFileName - $Date`T$Time"
  if (!($OutputFileName -Match "\.mp4")){
    $OutputFileName += ".mp4"
  }

  if (!(Test-Path $uploadPath)) {
    New-Item $uploadPath -ItemType Directory
    Write-Verbose "Created '$uploadPath'"
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
  )

  if ($MixAudioChannels) {
    # frame delta appears to be 3, 3 * (1/60) = 50 milliseconds
    $opts = @("-itsoffset", ($GameAudioDelay/1000).ToString()) + $opts
    $opts += "-filter_complex", "[0:a:0]adelay=$GameAudioDelay|$GameAudioDelay,volume=$GameVolume[game];[0:a:1]acopy,volume=$MicVolume[mic];[game][mic]amerge=inputs=2[mix]", "-ac", "2", "-map", "0:v", "-map", "[mix]"
  }

  $opts += "$OutputPath\$OutputFileName"

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
