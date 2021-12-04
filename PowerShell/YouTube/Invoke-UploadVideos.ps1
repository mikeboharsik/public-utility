# ms https://docs.microsoft.com/en-us/advertising/scripts/examples/authenticating-with-google-services
# playground https://developers.google.com/oauthplayground

[CmdletBinding()]
Param(
  [string] $BearerToken
)

. './YouTube.ps1'

$uploadFolder = "D:\ShadowPlay\upload"

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
  return [string[]] (Get-ChildItem -File -Name -Include "*.mp4" $uploadFolder)
}

function main {
  [CmdletBinding()]
  Param()

  $fileNames = Get-FileNames  
  if ($fileNames.length -le 0) {
    Write-Host "No files to upload"
    
    return
  }

  return Get-NextUploadTime
}

return main