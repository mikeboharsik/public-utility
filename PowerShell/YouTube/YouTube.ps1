. .\YouTube-OAuth.ps1

$apiBase = "https://www.googleapis.com"

$myChannelEndpoint = "$apiBase/youtube/v3/channels?mine=true&part=contentDetails"

$uploadVideoParameters = "uploadType=resumable&part=snippet,status"
$uploadVideoEndpoint = "$apiBase/upload/youtube/v3/videos?$uploadVideoParameters"

$playlistsEndpoint = "$apiBase/youtube/v3/playlists?mine=true&part=snippet,status&maxResults=50"
$playlistItemsEndpoint = "$apiBase/youtube/v3/playlistItems?playlistId={{playlistId}}&part=contentDetails,snippet,status&maxResults=50"

$videosEndpoint = "$apiBase/youtube/v3/videos?part=snippet,status,fileDetails"

# https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol
function UploadVideo {
  [CmdletBinding(SupportsShouldProcess = $true)]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $VideoPath
  )

  if (!($VideoPath -Match "uploads\\(.*?)\.mp4$")) {
    throw "'$VideoPath' has a filename in an unrecognized format"
  }

  $game, $title, $datetime = $Matches[1] -Split " - "
  $datetime -Match "(\d{4})\.(\d{2})\.(\d{2})T(\d{2})\.(\d{2})\.(\d{2})" | Out-Null

  $year, $month, $day, $hour, $min, $sec = $Matches.Keys | Where-Object { $_ -ne 0 } | Sort-Object | ForEach-Object { $Matches[$_] }

  $datetimeString = "$year-$month-$day $($hour):$($min):$($sec)"

  $descriptionBoilerplate = "Feel free to use this footage for your own purposes. I would simply ask that you include a credit back to me for it."

  $description = @"
$dateTimeString

$descriptionBoilerplate
"@.Trim()

  $now = Get-Date -AsUTC
  $publishAt = $now.AddHours(1)

  try {
    $parts = @{
      snippet = @{
        title = "$game - $title"
        description = $description
        tags = @()
        categoryId = 20 # gaming
      }
      status = @{
        privacyStatus = "private"
        embeddable = $true
        license = "youtube"
        publishAt = $publishAt
      }
    } | ConvertTo-Json

    $cont = Read-Host "Metadata has been configured as:`n$parts`n`nContinue with uploading video?"
    if ($cont.ToLower() -ne "y") { return }

    $headers = (Get-AuthorizationHeader)
    $headers['Content-Type'] = 'application/octet-stream'

    $sessionArgs = @{
      Uri = $uploadVideoEndpoint
      Method = 'POST'
      Headers = $headers
      Body = $parts
    }
    if ($PSCmdlet.ShouldProcess("$uploadVideoEndpoint`n$(ConvertTo-Json $sessionArgs)", "Create upload session")) {
      $res = Invoke-WebRequest @sessionArgs

      if (!$res.Headers.Location) {
        throw "Failed to retrieve video upload URI"
      }

      $sessionResult = $res
    } else {
      $res = @{ Headers = @{ Location = "https://mockurl.com" } }
    }

    $uploadArgs = @{
      Uri = ($res.Headers.Location | Select-Object -First 1)
      Method = 'PUT'
      Headers = $headers
      InFile = $VideoPath
    }
    if ($PSCmdlet.ShouldProcess("$uploadVideoEndpoint`n$(ConvertTo-Json $uploadArgs)", "Upload video bytes")) {
      $res = Invoke-WebRequest @uploadArgs

      $uploadResult = $res
    }

    $config = Get-Content "$PSScriptRoot\trimvideo.config.json" | ConvertFrom-Json -AsHashtable
    $uploadsFolder = $config.uploadsOutputPath
    if (!$uploadsFolder) {
      throw "`$uploadsFolder is not set"
    }

    $completeFolder = "$uploadsFolder\complete"
    if (!(Test-Path $completeFolder)) {
      New-Item -ItemType Directory -Path "$completeFolder" | Out-Null
    }

    Move-Item $VideoPath $completeFolder | Out-Null
  } catch {
    Write-Error $_

    throw $_
  }
}

function Get-MyChannelData {
  [CmdletBinding()]
  Param()

  return Invoke-RestMethod `
    -Uri $myChannelEndpoint `
    -Headers (Get-AuthorizationHeader)
}

function Get-PlaylistItems {
  [CmdletBinding()]
  Param(
    [string] $PlaylistId,
    [string] $PageToken
  )

  $uri = $playlistItemsEndpoint -Replace "{{playlistId}}", $PlaylistId
  if ($PageToken) {
    $uri += "&pageToken=$PageToken"
  }

  return Invoke-RestMethod `
    -Uri $uri `
    -Headers (Get-AuthorizationHeader)
}

function Get-Uploads {
  [CmdletBinding()]
  Param()

  $channelData = Get-MyChannelData

  $uploadsId = $channelData
    | Select-Object -ExpandProperty items
    | Select-Object -First 1
    | Select-Object -ExpandProperty contentDetails
    | Select-Object -ExpandProperty relatedPlaylists
    | Select-Object -ExpandProperty uploads

  $videos = @()
  $pageToken = $null

  do {
    $res = Get-PlaylistItems $uploadsId $pageToken

    $videos += $res.items

    $pageToken = $res.nextPageToken

    Write-Verbose "Set pageToken to $pageToken"
  } while ($pageToken)

  return $videos
}

function Get-AllPlaylistItems {
  Param(
    [string] $PlaylistId
  )

  $items = @()
  $pageToken = $null

  do {
    $res = Get-PlaylistItems $PlaylistId $pageToken

    $items += $res.items

    $pageToken = $res.nextPageToken

    Write-Verbose "Set pageToken to $pageToken"
  } while ($pageToken)

  return $items
}

function Get-Video {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $VideoId
  )

  $uri = "$videosEndpoint&id=$VideoId"

  return Invoke-RestMethod `
    -Uri $uri `
    -Headers (Get-AuthorizationHeader)
    | Select-Object -ExpandProperty items
    | Select-Object -First 1
}

function Get-VideosSearch {
  [CmdletBinding()]
  Param()

  $baseUri = "$apiBase/youtube/v3/search?part=snippet&forMine=true&type=video&maxResults=50&order=date"

  $GetVideosSearchResults = @()
  $videos = @()

  $nextPageToken = $null
  do {
    if ($nextPageToken) {
      $uri = "$baseUri&pageToken=$nextPageToken"
    } else {
      $uri = $baseUri
    }

    Write-Verbose "`$uri = $uri"

    $res = Invoke-RestMethod `
      -Uri $uri `
      -Headers (Get-AuthorizationHeader)

      $GetVideosSearchResults += $res

    $videos += $res.items

    $nextPageToken = $res.nextPageToken
  } while ($nextPageToken)

  return $videos
}

function Get-Videos {
  [CmdletBinding()]
  Param(
    [string[]] $VideoIds
  )

  if (!$VideoIds) {
    return @()
  }

  $baseUri = "$apiBase/youtube/v3/videos?part=status,fileDetails&maxResults=50"
  $pageIndex = 0

  $GetVideosResults = @()

  $videos = @()

  do {
    $ids = $VideoIds[(50 * $pageIndex) .. ((50 * $pageIndex) + 49)]
    if (!$ids.Length) {
      break
    }

    if ($nextPageToken) {
      $uri = "$baseUri&id=$($ids -Join ',')&pageToken=$nextPageToken"
    } else {
      $uri = "$baseUri&id=$($ids -Join ',')"
    }

    Write-Verbose "`$uri = $uri"

    $res = Invoke-RestMethod `
      -Uri $uri `
      -Headers (Get-AuthorizationHeader)

    $GetVideosResults += $res
    $videos += $res.items

    $pageIndex++
  } while ($true)

  return $videos
}

function Update-Video {
  [CmdletBinding(SupportsShouldProcess)]
  Param(
    [Parameter(Mandatory = $true)]
    [string] $Id,

    [Parameter(Mandatory = $false)]
    [string] $CategoryId = '20',

    [Parameter(Mandatory = $true)]
    [string] $Title,

    [Parameter()]
    [string] $Description,

    [Parameter(Mandatory = $true)]
    [string] $PublishAt
  )

  if (!$UpdateVideoResults) {
    $UpdateVideoResults = @()
  }

  $uri = "$apiBase/youtube/v3/videos?part=id,snippet,status"

  $body = @{}

  if ($Id) {
    $body.id = $Id
  }

  if ($CategoryId) {
    if (!$body.snippet) {
      $body.snippet = @{}
    }

    $body.snippet.categoryId = $CategoryId
  }

  if ($Description) {
    if (!$body.snippet) {
      $body.snippet = @{}
    }

    $body.snippet.description = $Description
  }

  if ($Title) {
    if (!$body.snippet) {
      $body.snippet = @{}
    }

    $body.snippet.title = $Title
  }

  if ($PublishAt) {
    $body.status = @{
      privacyStatus = "private"
      publishAt = $PublishAt
    }
  }

  $body = ConvertTo-Json $body -Depth 10 -Compress

  $headers = (Get-AuthorizationHeader)
  $headers['Content-Type'] = 'application/json'

  Write-Verbose "Sending request to '$uri' with body $(ConvertTo-Json -Depth 10 -Compress $body)"

  if ($PSCmdlet.ShouldProcess("PUT $uri $(ConvertTo-Json -Depth 10 -Compress $body)")) {
    $res = Invoke-RestMethod `
      -Uri $uri `
      -Method 'PUT' `
      -Body $body `
      -Headers $headers

    $UpdateVideoResults += @{ id = $Id; result = $res }

    if (!$res) {
      Write-Warning "Make sure you aren't using cached data ( ͡° ͜ʖ ͡°)"
      Write-Host (ConvertFrom-Json $body | ConvertTo-Json)
      throw "Update-Video failed"
    }
  }
}

Write-Verbose "Imported YouTube functions"
