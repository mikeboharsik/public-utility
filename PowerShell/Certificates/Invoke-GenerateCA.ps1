#Requires -RunAsAdministrator

<# Adapted from https://web.archive.org/web/20200812184945/https://systemcenterdudes.com/powershell-generate-certificates-lab/ #>

Param(
	[Parameter(Mandatory=$false)]
	[string] $OpenSslPath = "C:\Program Files\Git\usr\bin\openssl.exe",

	[Parameter(Mandatory=$false)]
  [string] $GeneratedPath = "$PSScriptRoot\generated",

  [Parameter(Mandatory=$true)]
  [string] $CAName,

  [Parameter(Mandatory=$false)]
  [string] $CAOutPath = "$GeneratedPath\CA-gen.pfx",

  [Parameter(Mandatory=$false)]
  [string] $ServerOutPath = "$GeneratedPath\Server-gen.pfx",

  [Parameter(Mandatory=$false)]
  [string] $GeneratedFilesOutputPath = $PSScriptRoot,

	[Parameter(Mandatory=$true)]
	[string] $CreatorEmailAddress,

	[Parameter(Mandatory=$true)]
	[string] $CAPass = "WhoEvenCares13333131313NobodyWillTryToReadThis",

	[Parameter(Mandatory=$true)]
	[string[]] $DnsNames
)

if (!(Test-Path $OpenSslPath)) {
	Write-Error "Could not find openssl.exe at '$OpenSslPath', please provide a valid path"
	exit 1
}

try {
	$now = Get-Date
	$expires = $now.AddYears(5)

	$CA = New-SelfSignedCertificate `
		-DnsName $CAName `
		-KeyUsage CertSign `
		-NotAfter $expires `
		-KeyAlgorithm RSA `
		-KeyLength 2048 `
		-TextExtension @("2.5.29.30={text}Email=$CreatorEmailAddress")

	Write-host "Certificate Thumbprint: $($CA.Thumbprint)"

	if (Test-Path $GeneratedPath) {
		Remove-Item "$GeneratedPath\*"
	} else {
		mkdir $GeneratedPath | Out-Null
	}

	$pass = ConvertTo-SecureString -String $CAPass -AsPlainText
	Export-PfxCertificate -Cert $CA -FilePath $CAOutPath -Password $pass  | Out-Null

	& $OpenSslPath pkcs12 -in $CAOutPath -nokeys -out "$GeneratedPath\CA.pem" -nodes

	$ServerCert = New-SelfSignedCertificate `
		-DnsName $DnsNames `
		-Signer $CA `
		-NotAfter $expires `
		-TextExtension @("2.5.29.30={text}Email=$CreatorEmailAddress")

	Export-PfxCertificate -Cert $ServerCert -FilePath $ServerOutPath -Password $pass | Out-Null

	& $OpenSslPath pkcs12 -in $ServerOutPath -nocerts -out "$GeneratedPath\raw-private-key.key" -nodes
	& $OpenSslPath pkcs12 -in $ServerOutPath -nokeys -out "$GeneratedPath\certificate.pem" -nodes
	& $OpenSslPath rsa -in "$GeneratedPath\raw-private-key.key" -out "$GeneratedPath\private-key.key"

	Remove-Item "$GeneratedPath\*.pfx"

	Move-Item "$GeneratedPath\CA.pem" "$GeneratedFilesOutputPath\CA.pem" -Force
	Move-Item "$GeneratedPath\private-key.key" "$GeneratedFilesOutputPath\private-key.key" -Force
	Move-Item "$GeneratedPath\certificate.pem" "$GeneratedFilesOutputPath\certificate.crt" -Force
} catch {
	throw $_
}
