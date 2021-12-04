$clientId = ""
$redirectUri = "http://localhost:8080"

$oauthParams = @(
  "scope=https://www.googleapis.com/auth/youtube"
  "access_type=offline"
  "include_granted_scopes=true"
  "response_type=code"
  "redirect_uri=$redirectUri"
  "client_id=$clientId"
)
$oauthUri = "https://accounts.google.com/o/oauth2/v2/auth?$($oauthParams -Join '&')"

$oauthTokenParams = @(
  "client_secret=0vO-JJKkx45_IHAknWv9ct7j"
  "client_id=$clientId"
  "redirect_uri=$redirectUri"
  "grant_type=authorization_code"
)
$oauthTokenUri = "https://oauth2.googleapis.com/token?code={{code}}&$($oauthTokenParams -Join '&')"

$apiBase = "https://www.googleapis.com"
$uploadVideoParameters = "uploadType=resumable&part=snippet,status"
$uploadVideoEndpoint = "$apiBase/upload/youtube/v3/videos?$uploadVideoParameters"
$myChannelEndpoint = "$apiBase/youtube/v3/channels?mine=true&part=contentDetails"
$playlistsEndpoint = "$apiBase/youtube/v3/playlists?mine=true&part=snippet,status&maxResults=50"
$playlistItemsEndpoint = "$apiBase/youtube/v3/playlistItems?playlistId={{playlistId}}&part=snippet,status&maxResults=50"

$oauthHtml = @"
<html>
  <head>
    <title>Local OAuth</title>
    <style>
      body {
        background-color: black;
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
      }
    </style>
  </head>

  <body>
  You can close this web page now!
  </body>
</html>
"@

function Get-BearerToken {
  [CmdletBinding()]
  Param()

  if (!$script:token) {
    Write-Verbose "Script-scope token has not yet been set"

    return Get-AccessToken
  } else {
    Write-Verbose "Script-scope token has already been set"

    return $script:token
  }
}

function Get-AuthorizationHeader {
  [CmdletBinding()]
  Param()

  $header = @{ "Authorization" = "Bearer $(Get-BearerToken)"}

  Write-Verbose "Using Authorization header: $(ConvertTo-Json $header)"

  return $header
}

function UploadVideo {
  [CmdletBinding()]
  Param(
    [string] $VideoPath,
    [string] $BearerToken
  )

  try {
    $parts = @{
      snippet = @{
        title = "Test Title"
        description = "Description"
        tags = @()
        categoryId = 20 # gaming
      }
      status = @{
        privacyStatus = "private"
        embeddable = $true
        license = "youtube"
        publishAt = ""
      }
    } | ConvertTo-Json -Depth 10

    $cont = Read-Host "Metadata has been configured as:`n`n$parts`n`nContinue with uploading video?"
    if ($cont.ToLower() -ne "y") { return }

    $res = Invoke-WebRequest `
      -Uri $uploadVideoEndpoint `
      -Headers (Get-AuthorizationHeader) `
      -Body $parts
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

  $uploadsId = $channelData.items[0].contentDetails.relatedPlaylists.uploads  

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

function Invoke-OAuthFlow {
  try {
    Write-Verbose "Sending OAuth request to $oauthUri"
  
    Start-Process $oauthUri
  
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:8080/")
    $listener.Start()
  
    $context = $listener.GetContext() 
    
    $data = $context.Request.Url.ToString().Split('?') | ForEach-Object { $_.Split('&') } | Select-Object -Skip 1 | ForEach-Object { $out = @{} } { $tmp = $_.Split("="); $out[$tmp[0]] = $tmp[1] } { $out }
  
    $content = [System.Text.Encoding]::UTF8.GetBytes($oauthHtml)
    $context.Response.OutputStream.Write($content, 0, $content.Length)
    $context.Response.Close()
  
    $tokenUri = $oauthTokenUri -Replace "{{code}}", $data.code
  
    $tokenData = Invoke-RestMethod `
      -Uri $tokenUri `
      -Method 'POST'
  
    Set-Content "access_token.json" (ConvertTo-Json -Depth 10 $tokenData)
  
    return $tokenData.access_token
    } finally {
      $listener.Stop()
  }
}

function Get-AccessToken {
  [CmdletBinding()]
  Param(
    [switch] $ForceGetToken
  )

  $token = $null

  if (!$ForceGetToken) {
    $existingTokenFileData = Get-ChildItem "access_token.json" -ErrorAction SilentlyContinue
    if ($existingTokenFileData) {
      $content = (Get-Content "access_token.json" | ConvertFrom-Json)

      $updated = $existingTokenFileData.LastWriteTime
      $token = $content.access_token
      $validSeconds = $content.expires_in
      $now = Get-Date

      if ($now -ge $updated.AddSeconds($validSeconds)) {
        Write-Verbose "Stored token has expired"
        $token = $null
      } else {
        Write-Verbose "Got existing token from file"

        $script:token = $token
        return $script:token
      }
    } 
  }

  if (!$token) {
    $token = Invoke-OAuthFlow

    Write-Verbose "Got new token from OAuth flow"
  }

  $script:token = $token
  return $script:token
}