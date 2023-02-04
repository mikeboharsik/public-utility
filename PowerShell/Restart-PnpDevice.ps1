Param(
	$FriendlyName = 'Realtek PCIe 2.5GbE Family Controller'
)

$device = Get-PnpDevice -FriendlyName $FriendlyName
$id = $device.InstanceId

Disable-PnpDevice $id -Confirm:$false
Enable-PnpDevice $id -Confirm:$false
