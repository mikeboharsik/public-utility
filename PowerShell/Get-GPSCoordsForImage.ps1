Param(
	[string] $Filename,

	[switch] $IncludeComma,
	
	[switch] $AsHashtable,
	[switch] $AsDecimal
)

$processedOutput = (exiftool -GPSPosition $Filename).Split('\n') `
	| Where-Object { $_ -Match "GPS Position" } `
	| ForEach-Object { $_.Split(' : ') } `
	| Select-Object -Skip 1 `
	| ForEach-Object { $_.Replace(' deg', '').Replace('''', '').Replace('"', '') }

$lat, $lon = ($processedOutput -Split "," | ForEach-Object { $_.Trim() })

if ($AsDecimal) {
	[double] $latDeg, [double] $latMin, [double] $latSec, $ns = $lat -Split " "
	[double] $lonDeg, [double] $lonMin, [double] $lonSec, $ew = $lon -Split " "

	[double] $latTotal = $latDeg + ($latMin / 60) + ($latSec / 3600)
	[double] $lonTotal = $lonDeg + ($lonMin / 60) + ($lonSec / 3600)

	if ($ns.ToLower() -eq 's') { $latTotal *= -1 }
	if ($ew.ToLower() -eq 'w') { $lonTotal *= -1 }

	$lat = $latTotal
	$lon = $lonTotal
}

if ($AsHashtable) {		
	return @{ latitude = $lat; longitude = $lon }
}

if ($IncludeComma) {
	return "$lat, $lon"
}

return "$lat $lon"
