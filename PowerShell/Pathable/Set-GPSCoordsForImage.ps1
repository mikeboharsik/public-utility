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
	$Latitude, $Longitude = $Coords -Split ","
}

$exiftoolArgs = @(
	"-GPSLatitude=$Latitude"
	"-GPSLongitude=$Longitude"
	$Filename
)

exiftool @exiftoolArgs