# https://developers.meethue.com/develop/hue-api/

[CmdletBinding()]
Param (
  [string] $GroupName = $null,
  [switch] $Toggle,
  [switch] $PlayBeep
)

$configPath = "$PSScriptRoot\Invoke-Hue.config.json"

function Get-ConfigValue($key) {
  $config = Get-Content $configPath 
  if (!$config) {
    throw "Failed to load config from '$configPath'"
  }

  $config = $config | ConvertFrom-Json -AsHashtable

  return $config[$key]
}

$hostname = Get-ConfigValue('hostname')
if (!$hostname) {
  throw "Failed to load hostname from '$configPath'"
}

$baseUri = "https://$hostname/clip/v2"

function Get-Username {
  $username = Get-ConfigValue('username')

  Write-Verbose "Loaded username '$username'"

  return $username
}

function Get-LightsUri {
  return "/resource/light"
}

function Get-GroupsUri {
  return "/resource/grouped_light"
}

function Get-RoomsUri {
  return "/resource/room"
}

function Get-ConfigUri {
  throw "Not Implemented"
}

function Invoke-HueRequest {
  Param(
    [string] $ResourcePath,
    [string] $Method = 'GET',
    [string] $Body = ''
  )

  $username = Get-Username
  if (!$username) {
    throw "Failed to load username from '$configPath'"
  }

  $Uri = "$($baseUri)$ResourcePath"
  $Headers = @{
    'Content-Type' = 'application/json'
    'hue-application-key' = Get-ConfigValue('username')
  }

  Write-Verbose (@{ uri = $Uri; headers = $Headers; body = $Body } | ConvertTo-Json -Depth 10)

  return Invoke-RestMethod `
    -Uri $Uri `
    -Method $Method `
    -Headers $Headers `
    -Body $Body `
    -SkipCertificateCheck
}

function Invoke-GenerateUsername {
  $result = $null
  $randomNumber = (Get-Random) % 10000

  # 40 characters max
  $name = "PowerShell#$randomNumber"

  Write-Host "Press the link button on the Hue bridge"

  do {
    $res = Invoke-RestMethod `
      -Uri "https://$hostname/api" `
      -Method POST `
      -Body (ConvertTo-Json @{ devicetype = $name; generateclientkey = $true }) `
      -SkipCertificateCheck

    if ($res.success) {
      $result = $res[0].success.username
    } else {
      Write-Verbose "Failed to get username, retrying"
      Start-Sleep 1
    }
  } while ($null -eq $result)

  Set-Content $configPath (ConvertTo-Json @{ username = $result })

  Write-Verbose "Generated username '$result'"
}

function Get-Group ($name) {
  $roomsUri = Get-RoomsUri
  $groupsUri = Get-GroupsUri

  Write-Verbose "Getting rooms with [$roomsUri] and groups with [$groupsUri]"

  $rooms = (Invoke-HueRequest -ResourcePath $roomsUri).data

  $room = $rooms | Where-Object { $_.metadata.name -eq $name }
  if (!$room) {
    throw "Failed to find room with name [$name]"
  }

  $groupedLightId = $room.services[0].rid
  $group = (Invoke-HueRequest -ResourcePath "$groupsUri/$groupedLightId").data[0]

  Write-Verbose ($groups | ConvertTo-Json -Depth 5)

  return $group
}

function Toggle-Group ($name) {
  Write-Verbose "Toggling Group [$name]"

  $group = Get-Group $name
  if (!$group) {
    Write-Warning "Group '$name' not found"
    return
  }

  $groupId = $group.id
  
  $currentGroupOnState = $group.on.on

  Write-Verbose "Group state: [$currentGroupOnState]"

  $isOn = !!$currentGroupOnState
  Write-Verbose "isOn is [$isOn] - object value is [$($group.state.all_on)]"

  $newState = !$isOn

  $uri = "$(Get-GroupsUri)/$groupId"
  $body = ConvertTo-Json -Compress @{ on = @{ on = $newState } }

  Write-Verbose "Updating group state with [$uri]`nbody = $body"

  $res = Invoke-HueRequest `
    -ResourcePath $uri `
    -Method PUT `
    -Body $body `

  if ($PlayBeep) {
    if ($newState) {
      [Console]::Beep(2000, 250)
    } else {
      [Console]::Beep(500, 250)
    }
  }

  return $res | ConvertTo-Json -Compress
}

try {
  if ($Toggle) {
    $success = $false
    $retries = 3
    
    while ($success -eq $false -and $retries -gt 0) {
      try {
        $response = Toggle-Group $GroupName
        $success = $true
      } catch {
        $retries -= 1
        Write-Error $_.Exception
      }
    }
    
    return $response
  }

  return ConvertTo-Json (Get-Group $GroupName)
} catch {
  return $_
}
