[CmdletBinding()]
Param (
  [string] $GroupName = $null,
  [switch] $Toggle,
  [switch] $PlayBeep
)

$username = "VJLs6DrND3al3m-HnWubeRIkMsqBg2jhPB2AzvOr"

$baseUri          = "https://avohue.myfiosgateway.com/api"
$lightsUri        = "$baseUri/$username/lights"
$groupsUri        = "$baseUri/$username/groups"
$configurationUri = "$baseUri/$username/config"

function Get-Group ($name) {
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

  Write-Host "Found [$($groups.Length)] groups"

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
  
  Write-Host "Group state: [$($group.state)]"

  $isOn = !!$group.state.all_on
  Write-Verbose "isOn is [$isOn] - object value is [$($group.state.all_on)]"

  $newState = !$isOn

  $uri = "$groupsUri/$groupId/action"
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
    return Toggle-Group $GroupName
  }

  return ConvertTo-Json (Get-Group $GroupName)
} catch {
  return $_
}