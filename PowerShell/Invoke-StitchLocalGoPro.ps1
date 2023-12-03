[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[string] $StitchedFilename,

	[switch] $DeleteOriginalFiles,
	[switch] $SkipBackup
)

$outputFolderPath = Get-Location

$outputFolderPath = Resolve-Path $outputFolderPath
Write-Verbose "`$outputFolderPath = $outputFolderPath"

try {
	if (Get-ChildItem | Where-Object { $_.Extension.ToLower() -ne ".mp4" }) {
		throw "Expected folder [$outputFolderPath] to contain only .mp4 files, cannot continue"
	}

	$files = Get-ChildItem $outputFolderPath
		| Sort-Object { $_.Name }

	foreach ($file in $files) {
		Add-Content "files.txt" "file $($file.Name)"
	}

	if (!$StitchedFilename) {
		$StitchedFilename = $files[0].BaseName + "_merged"
	}

	$outputFilename = "$outputFolderPath/$StitchedFilename.mp4"

	ffmpeg -f concat -i "files.txt" -c copy $outputFilename

	if ($DeleteOriginalFiles) {
		Remove-Item $files
	}

	if (!$SkipBackup) {
		Write-Host "Backing up [$outputFilename]"

		$localArchiveDir = "H:/do_not_backup/walks"
		$remoteArchiveDir = "gs://walk-videos"

		Write-Host "Writing to [$localArchiveDir]..."
		Copy-Item $outputFilename $localArchiveDir
		Write-Host "Done."

		Write-Host "Writing to [$remoteArchiveDir]..."
		gsutil cp $outputFilename $remoteArchiveDir
		Write-Host "Done."
	}

	Add-Type -AssemblyName PresentationCore,PresentationFramework
	[System.Windows.MessageBox]::Show("Backup has completed", "Invoke-StitchLocalGoPro.ps1", 0) | Out-Null
} finally {
	Remove-Item "files.txt" -ErrorAction SilentlyContinue
}
