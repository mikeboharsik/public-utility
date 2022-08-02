Param(
	[Parameter(Mandatory=$true)]
	[string] $FolderPath
)

$FolderPath = Resolve-Path $FolderPath

Push-Location $FolderPath

try {
	$files = Get-ChildItem $FolderPath
		| Where-Object { $_.Extension -eq ".MP4" }
		| Sort-Object { $_.LastWriteTime }

	$start = $files[0]

	$data = (exiftool -MediaCreateDate $start.FullName)
	$date = Get-Date -Format "yyyy-MM-dd"
	$mediaCreateDate = ($data.Split(': ')[1]) -Replace "(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})", "$($date)_`$4-`$5-`$6"

	$joinedFilename = "$mediaCreateDate.mp4"

	$files | ForEach-Object { Add-Content "files.txt" "file $($_.Name)" }

	ffmpeg -f concat -i "files.txt" -c copy $joinedFilename
} finally {
	Remove-Item "files.txt" -ErrorAction SilentlyContinue

	Pop-Location
}