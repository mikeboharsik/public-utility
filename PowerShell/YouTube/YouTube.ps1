$apiBase = "https://www.googleapis.com"
$uploadVideoParameters = "uploadType=resumable&part=snippet,status"
$uploadVideoEndpoint = "$apiBase/upload/youtube/v3/videos?$uploadVideoParameters"
$myChannelEndpoint = "$apiBase/youtube/v3/channels?mine=true&part=contentDetails"
$playlistsEndpoint = "$apiBase/youtube/v3/playlists?mine=true&part=snippet,status&maxResults=50"
$playlistItemsEndpoint = "$apiBase/youtube/v3/playlistItems?playlistId={{playlistId}}&part=snippet,status&maxResults=50"

function Get-AccessTokenPath {
  return "$PSScriptRoot\access_token.json"
}

function Get-OAuthHtml {
  return @"
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
}

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

  $header = @{"Authorization" = "Bearer $(Get-BearerToken)"}

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

function Get-RedirectUri {
  [CmdletBinding()]
  Param()

  $data = Get-ClientData
  $uri = $data.clientRedirectUri

  return $uri
}

function Get-ClientData {
  [CmdletBinding()]
  Param()
  $configPath = "$PSScriptRoot\youtube.config.json"

  if (!(Test-Path $configPath)) {
    throw "'$configPath' is missing"
  }

  $config = Get-Content $configPath | ConvertFrom-Json -AsHashtable

  $required = @("clientId", "clientRedirectUri", "clientSecret")
  $found = @{}
  $missing = @()

  foreach ($key in $required) {
    $curVal = $config[$key]

    if (!$curVal) {
      $missing += $key
      continue
    }

    $found[$key] = $curVal

    Write-Host $config[$key]
  }

  if ($missing.Length -eq 0) {
    Write-Verbose ($found | ConvertTo-Json -Compress)

    return $found
  }

  throw "Missing config settings from '$configPath': [$($missing -Join ', ')]"
}

function Get-OAuthUri {
  [CmdletBinding()]
  Param()

  $clientId = (Get-ClientData).clientId

  $oauthParams = @(
    "access_type=offline"
    "client_id=$clientId"
    "include_granted_scopes=true"
    "redirect_uri=$(Get-RedirectUri)"
    "response_type=code"
    "scope=https://www.googleapis.com/auth/youtube"
  )
  
  return "https://accounts.google.com/o/oauth2/v2/auth?$($oauthParams -Join '&')"
}

function Get-OAuthTokenUri {
  [CmdletBinding()]
  Param()

  $clientData = Get-ClientData

  $clientId = $clientData.clientId
  $clientSecret = $clientData.clientSecret

  $oauthTokenParams = @(
    "client_id=$clientId"
    "client_secret=$clientSecret"
    "grant_type=authorization_code"
    "redirect_uri=$(Get-RedirectUri)"
  )

  return "https://oauth2.googleapis.com/token?code={{code}}&$($oauthTokenParams -Join '&')"
}

function Invoke-OAuthFlow { 
  [CmdletBinding()]
  Param()

  try {
    $oauthUri = Get-OAuthUri

    Write-Verbose "Sending OAuth request to $oauthUri"
    Start-Process $oauthUri

    $localUri = "$(Get-RedirectUri)/"

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($localUri)

    $listener.Start()

    $context = $listener.GetContext()
    
    $data = $context.Request.Url.ToString().Split('?')
      | ForEach-Object { $_.Split('&') }
      | Select-Object -Skip 1
      | ForEach-Object { $out = @{} } { $tmp = $_.Split("="); $out[$tmp[0]] = $tmp[1] } { $out }
  
    $content = [System.Text.Encoding]::UTF8.GetBytes((Get-OAuthHtml))
    $context.Response.OutputStream.Write($content, 0, $content.Length)
    $context.Response.Close()
  
    $tokenUri = (Get-OAuthTokenUri) -Replace "{{code}}", $data.code
  
    $tokenData = Invoke-RestMethod `
      -Uri $tokenUri `
      -Method 'POST'
  
    Set-Content (Get-AccessTokenPath) (ConvertTo-Json -Depth 10 $tokenData)
  
    return $tokenData.access_token
  } finally {
    if ($listener -and $listener.IsListening) {
      $listener.Stop()
    }
  }
}

function Get-AccessToken {
  [CmdletBinding()]
  Param(
    [switch] $ForceGetToken
  )

  $token = $null

  if (!$ForceGetToken) {
    $existingTokenFileData = Get-ChildItem (Get-AccessTokenPath) -ErrorAction SilentlyContinue
    if ($existingTokenFileData) {
      $content = (Get-Content (Get-AccessTokenPath) | ConvertFrom-Json)

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
    Write-Verbose "Getting new OAuth token"

    $token = Invoke-OAuthFlow

    Write-Verbose "Got new token from OAuth flow"
  }

  $script:token = $token
  return $script:token
}
