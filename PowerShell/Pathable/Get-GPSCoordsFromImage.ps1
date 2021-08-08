Param(
	[string] $Filename
)

return (exiftool $Filename).Split('\n') `
	| Where-Object { $_ -Match "GPS Position" } `
	| ForEach-Object { $_.Split(' : ') } `
	| Select-Object -Skip 1 `
	| ForEach-Object { $_.Replace(' deg', '').Replace('''', '').Replace('"', '').Replace(',', '') }