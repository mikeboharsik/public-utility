[CmdletBinding()]
Param(
  [string] $WorldName = "Default",
  [int] $IntervalSeconds = 60 * 3
)


function Log {
  [CmdletBinding()]
  Param(
    [string] $msg
  )

  Write-Host "$(Get-Date -AsUtc -UFormat '%FZ%T') => $msg"
}

function Log-Verbose {
  [CmdletBinding()]
  Param(
    [string] $msg
  )

  Write-Verbose "$(Get-Date -AsUtc -UFormat '%FZ%T') => $msg"
}

$TerraMap = "$env:ProgramFiles\TerraMap\TerraMapCmd.exe"

$myDocumentsPath = [Environment]::GetFolderPath("MyDocuments")
$worldsPath = "$myDocumentsPath\My Games\Terraria\Worlds"
$WorldName = $WorldName -Replace "\s","_"
$worldPath = "$worldsPath\$WorldName.wld"
$outputDir = "D:\TerrariaSnapshots"

$script:currentJob = $null

if (!(Test-Path $WorldPath)) {
  throw "World '$WorldPath' does not exist!"
}

function GetLatestSnapshotDateTime {
  $latestSnapshot = Get-ChildItem -Path $outputDir
    | Sort-Object -Descending -Property LastWriteTime
    | Select-Object -First 1 -ExpandProperty Name

  $didMatch = $latestSnapshot -Match "_(\d+-\d+-\d+)-(\d+-\d+-\d+)\."
  if ($didMatch) {
    $date = $Matches[1]
    $time = $Matches[2] -Replace "-",":"

    return (Get-Date "$date $time")
  }

  return $null
}

function GetWorldUpdateDateTime {
  return Get-ChildItem $worldPath | Select-Object -ExpandProperty LastWriteTime | Get-Date -AsUtc
}

function GenerateSnapshot {
  $script:currentJob = Start-Job -ScriptBlock {
    $dateString = (Get-Date -AsUTC).ToString() -Replace "[ :]","-"
    $outputFile = "$using:outputDir\$($using:WorldName)_$dateString.png"

    $arg = [string[]]@(
      "-i", $using:worldPath
      "-o", $outputFile
    )
    
    $stdout = & $using:TerraMap $arg

    return ($stdout -Join "`n")
  }
}

while ($true) {
  if ($script:currentJob -ne $null) {
    if ($script:currentJob.State -ne 'Running') {
      $result = Receive-Job $script:currentJob

      Log "Result of prior job '$($script:currentJob.Name)': $result"

      $script:currentJob = $null 
    }
  }

  $lastSnapshotTime = GetLatestSnapshotDateTime
  $worldUpdateTime = GetWorldUpdateDateTime

  $now = Get-Date
  if ($lastSnapshotTime) {
    $updateDiff = [Math]::Abs(($now - $lastSnapshotTime).TotalSeconds)
  }

  $beenLongEnough = $lastSnapshotTime -eq $null ? $true : $updateDiff -gt $IntervalSeconds

  Log-Verbose "`$script:currentJob = $script:currentJob"
  Log-Verbose "'$worldUpdateTime' -gt '$lastSnapshotTime' = $($worldUpdateTime -gt $lastSnapshotTime)"
  Log-Verbose "`$beenLongEnough = $beenLongEnough"

  if ($script:currentJob -eq $null -and $beenLongEnough -and $worldUpdateTime -gt $lastSnapshotTime) {
    Log "`$worldUpdateTime '$worldUpdateTime' is greater than `$lastSnapshotTime '$lastSnapshotTime'"
    GenerateSnapshot
    $lastUpdateTime = $now
  }

  Start-Sleep -Seconds 5
}