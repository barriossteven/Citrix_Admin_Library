cls

$Var_IntRelay = "email"
$Var_Sender = "sender"
$Var_Recipients = @("rec")

$VM_Prefix = "site*"

$Vcenter = "vcenter"
$Citrix_DLC = "controller"
$Citrix_PVS = "pvs"


$Date = $(Get-Date -Format 'yyyy-MM-dd_HH_mm')
$Information_CSV = $PSScriptRoot + "\VM_Information.csv"

Import-Module "C:\Program Files\Citrix\PowerShellModules\Citrix.Broker.Commands\Citrix.Broker.Commands.psd1" -ErrorAction SilentlyContinue
Import-Module activedirectory -ErrorAction SilentlyContinue
Import-Module "C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll" -ErrorAction SilentlyContinue
Import-module "vmware.vimautomation.core" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Connecting to $vcenter"
$Var_VC = Connect-VIServer -Server $Vcenter -User "svc_acc" -WarningAction SilentlyContinue
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Extracting VM objects"
$Var_VMs = Get-View -ViewType VirtualMachine -Server $Var_VC | ? {$_.name -like $VM_Prefix }
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Updating VM views"
$Var_VMs.updateviewdata("runtime.host.name", "datastore.name","network.name")
$Var_VMs = $Var_VMs | Select-Object name , @{Name="VC_Host";Expression={$_.runtime.linkedview.host.name}},  @{Name="VC_Disk";Expression={$_.linkedview.datastore.name}},  @{Name="VC_Vlan";Expression={$_.linkedview.network.name}}

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Getting machine objects from $Citrix_DLC "
$machines = Get-BrokerMachine -MaxRecordCount 10000 -AdminAddress $Citrix_DLC -SessionSupport SingleSession -DesktopKind Shared -HypervisorConnectionName $vcenter
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Getting AD objects"
$AD_List = Get-ADComputer -Filter 'name -like $VM_prefix' -Properties canonicalname | Where-Object{$_.CANONICALNAME -LIKE "masterOU*"}
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Connecting to $Citrix_PVS"
Set-PvsConnection -Server $Citrix_PVS
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Getting device info from $Citrix_PVS"
$PVS_Devices = Get-PvsDeviceInfo 
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting VM inventory"

$VM_Table = @{}
$Machines | ForEach-Object { $VM_Table[$_.hostedmachinename] = $_ }

foreach($device in $PVS_Devices){
    $VM_Table[$device.devicename] | Add-Member -notepropertymembers @{
        PVS_Collectionname = $device.collectionname
        PVS_Disklocatorname = $device.disklocatorname
        PVS_Diskversion = $device.diskversion
        PVS_Servername = $device.servername
    } 
}

foreach($computer in $AD_List){
    $VM_Table[$computer.name] | Add-Member -notepropertymembers @{
        AD_Canonicalname = $computer.canonicalname
    } 
}

foreach($VM in $Var_VMs){
    $VM_Table[$VM.name] | Add-Member -notepropertymembers @{
        VC_Host = $VM.vc_host
        VC_Disk = $VM.vc_disk
        VC_Vlan = $VM.vc_vlan
    } 
}

				  
$list = $VM_Table.values | sort-object -property MachineCatalog 
$list | Export-Csv $Information_CSV  -NoTypeInformation

    Send-MailMessage -from $Var_Sender `
                           -to $Var_Recipients  `
                           -subject "Virtual Machine Information Report" `
                           -body (" 							
							Attached is the virtual machine information report<br/><br/> 
													 " 
							  )`
                          -Attachments $Information_CSV -smtpServer $Var_IntRelay -BodyAsHtml 



                     