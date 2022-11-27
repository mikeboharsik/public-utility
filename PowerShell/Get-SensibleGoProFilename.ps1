[CmdletBinding()]
Param([string] $Filename)

return ($Filename[0..1] -Join '') + '_' + ($Filename[4..7] -Join '') + '_' + ($Filename[2..3] -Join '') + ($Filename[-4..-1] -Join '')
