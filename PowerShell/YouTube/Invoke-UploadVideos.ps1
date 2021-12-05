# ms https://docs.microsoft.com/en-us/advertising/scripts/examples/authenticating-with-google-services
# playground https://developers.google.com/oauthplayground

[CmdletBinding(SupportsShouldProcess = $true)]
Param()

. './YouTube.ps1'

$config = Get-Content "$PSScriptRoot\trimvideo.config.json" | ConvertFrom-Json -AsHashtable
$uploadsFolder = $config.uploadsOutputPath
if (!$uploadsFolder) {
  throw "`$uploadsFolder is not set, cannot find videos to upload"
}

$uploadsPerDay = 4

function Get-NextUploadTime {
  $today = Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0
  $now = Get-Date

  $uploadInterval = 24 / $uploadsPerDay

  for ($i = 0; $i -lt $uploadsPerDay + 1; $i++) {
    $nextTime = $today.AddHours($uploadInterval * $i)

    if ($nextTime -gt $now) {
      return $nextTime
    }
  }
}

function Get-FileNames {
  return [string[]] (Get-ChildItem -File $uploadsFolder | Where-Object { $_.FullName -like "*.mp4" } | Select-Object -ExpandProperty FullName)
}

function main {
  $fileNames = Get-FileNames  
  if ($fileNames.length -le 0) {
    Write-Host "No files to upload"
    
    return
  }

  UploadVideo -VideoPath $fileNames[0]
}

return main