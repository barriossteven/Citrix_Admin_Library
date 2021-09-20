cls

$Var_IntRelay = "email"
$Var_Sender = "sender"
$Var_Recipients = @("recip")

#Threshold capacity that deliverygroups should not exceed (%).
$Var_threshold = 90

#import stylesheet for formatting email
#$style = Get-Content

Import-Module "C:\Program Files\Citrix\PowerShellModules\Citrix.Broker.Commands\Citrix.Broker.Commands.psd1" -ErrorAction SilentlyContinue

<#
Server info can be imported using a centralized json file or by providing a list of servers
    $Servers = Get-Content -Raw -Path servers.json | ConvertFrom-Json
    $Servers = @("Server01", "Server02")
#> 

$Servers = @("server01")

$DeliveryGroups = Get-BrokerDesktopGroup -AdminAddress $($Servers|Get-Random) -SessionSupport SingleSession -InMaintenanceMode $false | ?{$_.tags -contains "Production" -or $_.tags -contains "QA"} 
$metrics = @()

$DeliveryGroups| foreach{

	$DG_Obj = New-Object -TypeName PSObject    
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.name
	$DG_Machines = (Get-BrokerMachine -AdminAddress $($Servers|Get-Random) -MaxRecordCount 10000 -DesktopGroupName $_.name)
	
	$DesktopsAvailable = ($DG_Machines | ?{$_.inmaintenancemode -eq $False -and $_.powerstate -eq "On" -and $_.RegistrationState -eq "Registered" -and $_.sessionusername -eq $null }).count
	
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "GroupUsage" -Value ([int]((1-($DesktopsAvailable/$_.totaldesktops))*100))
	
	$pad = ([int](((100*$DesktopsAvailable)-(10*$_.totaldesktops))/(-90)))
	if($pad -eq 0 ){$pad = 1}
	
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "Padding" -Value $pad
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "TotalDesktops" -Value $_.TotalDesktops
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "DesktopsAvailable" -Value $DesktopsAvailable
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "DesktopsUnregistered" -Value $_.DesktopsUnregistered
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "MaintenanceMode" -Value ($DG_Machines | ?{$_.inmaintenancemode -eq $True}).count
	$DG_Obj | Add-Member -MemberType NoteProperty -Name "DesktopsOff" -Value ($DG_Machines | ?{$_.powerstate -eq $True}).count
	$metrics += $DG_Obj
	#[int](((100*$_.desktopsavailable)-(10*$_.totaldesktops))/(-90)) is (avail + x)/(total+x) = 10/100
}

$Above_thresh = $metrics | Where-Object {$_.groupusage -gt $Var_threshold}

 if($Above_thresh -ne $null){
 	$output = $Above_thresh | Select name , @{Name="Group Usage (%)";Expression={ $_.groupusage }} , @{Name="VMs Needed for 10% Padding";Expression={ $_.Padding }}, Totaldesktops , desktopsavailable,  @{Name="Desktops On but Unregistered";Expression={ $_.desktopsunregistered }}, maintenancemode, desktopsoff | ConvertTo-Html -Head $style
 
    Send-MailMessage -from $Var_Sender `
                           -to $Var_Recipients `
                           -subject "Virtual Machine Usage Warning" `
                           -body ("
                              Team,<br /><br />
                              The Delivery Groups below are above $Var_threshold% capacity. Please follow the steps listed to address the issue. <br /><br />

                                <ol>
                                <li>Turn off 'Maintenance Mode' on any machines.</li>
                                <li>Restart any machines that read 'Unregistered.'</li>
                                <li>Allocate space on datastore/host then provision more machines. </li>
                                </ol>  

                              Thank you<br/><br/> " + $output)`
                           -smtpServer $Var_IntRelay  -BodyAsHtml 
}





