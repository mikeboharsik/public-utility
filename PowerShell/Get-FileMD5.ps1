[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true)]
	[string] $FilePath,

	[switch] $AsBase64
)

$res = Get-FileHash -Algorithm md5 $FilePath

if ($AsBase64) {
	# https://web.archive.org/web/20211107175131/https://stackoverflow.com/questions/68503049/converting-a-hex-string-to-base-64-in-powershell/68503559
	return [System.Convert]::ToBase64String(([byte[]]($res.hash -Split '(..)' -ne '' -Replace '^','0x')))
}

return $res.hash