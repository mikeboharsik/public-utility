[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[string] $SdCardPath = "P:",
	[string] $ContentPath = "DCIM\100GOPRO",
	[string] $DestinationFolder = "D:\wip"
)

$date = Get-Date -Format "yyyy-MM-dd"

$folderPath = "$PSScriptRoot\$date"
New-Item -ItemType Directory -Path $folderPath -ErrorAction SilentlyContinue | Out-Null

Push-Location $folderPath

$fullContentPath = "$SdCardPath\$ContentPath"
Write-Host $fullContentPath

try {
	$sdCardFiles = Get-ChildItem $fullContentPath
		| Where-Object { $_.Extension -eq ".MP4" }

	Write-Host $sdCardFiles

	Copy-Item -Path $sdCardFiles -Destination $folderPath

	$files = Get-ChildItem $folderPath
		| Sort-Object { $_.LastWriteTime }

	$start = $files[0]

	$data = (exiftool -MediaCreateDate $start.FullName)
	$mediaCreateDate = ($data.Split(': ')[1]) -Replace "(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})", "$($date)_`$4-`$5-`$6"

	$joinedFilename = "$DestinationFolder\$mediaCreateDate.mp4"

	$files | ForEach-Object { Add-Content "files.txt" "file $($_.Name)" }

	ffmpeg -f concat -i "files.txt" -c copy $joinedFilename

	Remove-Item $files
	Remove-Item "$fullContentPath\*"
	(New-Object -ComObject Shell.Application).NameSpace(17).ParseName($SdCardPath).InvokeVerb("Eject")
} finally {
	Remove-Item "files.txt" -ErrorAction SilentlyContinue

	Pop-Location
}
