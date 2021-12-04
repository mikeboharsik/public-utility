Param(
	[Parameter(Mandatory = $true)]
	[string] $Filename,

	[Parameter(Mandatory = $true, ParameterSetName = "Coords")]
	[string] $Coords,

	[Parameter(Mandatory = $true, ParameterSetName = "LatLon")]
	[double] $Latitude,

	[Parameter(Mandatory = $true, ParameterSetName = "LatLon")]
	[double] $Longitude
)

if (!(Test-Path $Filename)) {
	throw "'$Filename' does not exist"
}

if ($Coords) {
	[double] $Latitude, [double] $Longitude = $Coords -Split ","
}

if ($Latitude -lt 0) {
	$latitudeRef = "South"
} else {
	$latitudeRef = "North"
}

if ($Longitude -lt 0) {
	$longitudeRef = "West"
} else {
	$longitudeRef = "East"
}

$exiftoolArgs = @(
	"-GPSLatitude=$Latitude"
	"-GPSLatitudeRef=$latitudeRef"
	"-GPSLongitude=$Longitude"
	"-GPSLongitudeRef=$longitudeRef"
	$Filename
)

exiftool @exiftoolArgs
