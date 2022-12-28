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

$baseUri = "https://$hostname/api"

function Invoke-GenerateUsername {
  $result = $null
  $randomNumber = (Get-Random) % 10000

  # 40 characters max
  $name = "PowerShell#$randomNumber"

  Write-Host "Press the link button on the Hue bridge"

  do {
    $res = Invoke-RestMethod `
      -Uri $baseUri `
      -Method POST `
      -Body (ConvertTo-Json @{ devicetype = $name }) `
      -SkipCertificateCheck

    if ($res.success) {
      $result = $res.success.username
    } else {
      Write-Verbose "Failed to get username, retrying"
      Start-Sleep 1
    }
  } while ($null -eq $result)

  Set-Content $configPath (ConvertTo-Json @{ username = $result })

  Write-Verbose "Generated username '$result'"
}

function Get-Username {
  $username = Get-ConfigValue('username')

  Write-Verbose "Loaded username '$username'"

  return $username
}

function Get-LightsUri {
  return "$baseUri/$(Get-Username)/lights"
}

function Get-GroupsUri {
  return "$baseUri/$(Get-Username)/groups"
}

function Get-ConfigUri {
  return "$baseUri/$(Get-Username)/config"
}

function Get-Group ($name) {
  $groupsUri = Get-GroupsUri

  Write-Verbose "Getting groups with [$groupsUri]"

  $groups = Invoke-RestMethod `
    -Uri $groupsUri `
    -Method GET `
    -SkipCertificateCheck

  $tmp = @()
  foreach ($info in $groups.PSObject.Properties) {
    $info.Value | Add-Member -MemberType NoteProperty -Name id -Value $info.Name
    $tmp += $info.Value
  }
  $groups = $tmp

  $groupNames = ($groups | Select-Object -ExpandProperty Name) -Join ", "

  Write-Verbose "Found [$($groups.Length)] groups [$groupNames]"

  $group = $groups | Where-Object { $_.name -eq $name }

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
  
  Write-Verbose "Group state: [$($group.state)]"

  $isOn = !!$group.state.all_on
  Write-Verbose "isOn is [$isOn] - object value is [$($group.state.all_on)]"

  $newState = !$isOn

  $uri = "$(Get-GroupsUri)/$groupId/action"
  $body = ConvertTo-Json -Compress @{ on = $newState }

  Write-Verbose "Updating group state with [$uri]`nbody = $body"

  $res = Invoke-RestMethod `
    -Uri $uri `
    -Method PUT `
    -Body $body `
    -SkipCertificateCheck

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
	$response
    
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
