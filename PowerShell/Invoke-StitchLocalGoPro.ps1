[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[string] $StitchedFilename,

	[switch] $DeleteOriginalFiles
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
} finally {
	Remove-Item "files.txt" -ErrorAction SilentlyContinue
}
