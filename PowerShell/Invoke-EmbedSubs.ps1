[CmdletBinding()]
Param(
  [string] $InputVideo,
  [string] $InputSubs,
  [string] $OutputName
)

if (!$OutputName) {
  $OutputName = $InputVideo -Replace "\.", ".subbed."
}

$ffmpegArgs = [string[]]@(
  '-i', $InputVideo
  '-i', $InputSubs
  '-c', 'copy'
  '-c:s', 'srt'
  $OutputName
)

ffmpeg @ffmpegArgs