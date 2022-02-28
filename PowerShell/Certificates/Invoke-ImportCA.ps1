#Requires -RunAsAdministrator

Param(
	[Parameter(Mandatory=$false)]
	[string] $OpenSslPath = "C:\Program Files\Git\usr\bin\openssl.exe",

  [Parameter(Mandatory=$false, ParameterSetName="Import")]
  [string] $CertificateAuthorityFile = "$PSScriptRoot\CA.pem",

  [Parameter(Mandatory=$false, ParameterSetName="Import")]
  [string] $TargetCertStoreLocation = "Cert:\LocalMachine\Root"
)

try {
  Import-Certificate -FilePath $CertificateAuthorityFile -CertStoreLocation $TargetCertStoreLocation | Out-Null

  Write-Host "Imported cert '$CertificateAuthorityFile' into the local cert store at '$TargetCertStoreLocation'"
} catch {
  throw $_
}
