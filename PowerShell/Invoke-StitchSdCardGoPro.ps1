[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[string] $SdCardPath = "P:",
	[string] $ContentPath = "DCIM/100GOPRO",

	[string] $DestinationPath = "D:/wip/walks",

	[switch] $DeleteOriginalFiles,
	[switch] $SkipEject
)

$OriginalContentPath = "$SdCardPath/$ContentPath"

$originalPath = Get-Location

$date = Get-Date -Format "yyyy-MM-dd"

$outputFolderPath = "$DestinationPath/$date"
New-Item -ItemType Directory -Path $outputFolderPath -ErrorAction SilentlyContinue | Out-Null

Push-Location $outputFolderPath

$outputFolderPath = Resolve-Path $outputFolderPath
Write-Verbose "`$outputFolderPath = $outputFolderPath"

try {
	$originalFiles = Get-ChildItem $OriginalContentPath
		| Where-Object { $_.Extension -eq ".MP4" }

	Copy-Item -Path $originalFiles -Destination $outputFolderPath

	$copiedFiles = Get-ChildItem $outputFolderPath
	foreach ($file in $copiedFiles) {
		$name = $file.Name
		$newName = & (Resolve-Path "$PSScriptRoot/../Get-SensibleGoProFilename.ps1") -Filename $name

		Move-Item $name $newName
	}

	$files = Get-ChildItem $outputFolderPath
		| Sort-Object { $_.Name }

	$initialFile = $files[0]

	$data = (exiftool -api LargeFileSupport=1 -MediaCreateDate $initialFile.FullName)
	$mediaCreateDate = ($data.Split(': ')[1]) -Replace "(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})", "`$1-`$2-`$3_`$4-`$5-`$6"

	& (Resolve-Path "$PSScriptRoot/Invoke-StitchLocalGoPro.ps1") -StitchedFilename $mediaCreateDate

	if ($DeleteOriginalFiles) {
		Remove-Item $files
		Remove-Item "$OriginalContentPath\*"
	}

	if (!$SkipEject) {
		(New-Object -ComObject Shell.Application).NameSpace(17).ParseName($SdCardPath).InvokeVerb("Eject")
	}
} finally {
	Set-Location $originalPath
}
