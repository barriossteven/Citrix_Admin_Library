cls
#region header
$Var_Style = Get-Content "Style.txt"
$Var_Snapins = @("Citrix.Broker.Admin.v2")
$Var_Modules = @("PoshRSJob","vmware.vimautomation.core")
$Var_Controllers = @("server01")
$Var_vCenter = "vcenter"
$Var_Site = "site"
$Var_Elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$Var_TranscriptPath = "transcript-"+$(Get-Date -format "yyyyMMddHHmmss")+".txt"
$Var_IntRelay = "email"
$Var_Sender = "sender"
$Var_Recipients = @("recip")

Start-Transcript -Path $Var_TranscriptPath
Clear-Host
Write-Output "################################################################"
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting Reregistration Execution"
#endregion

#region Snapins_Modules
$Var_Snapins | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Importing Snapin $_"
	Remove-PSSnapin $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	Add-PSSnapin $_ -ErrorAction Stop -WarningAction SilentlyContinue
}
$Var_Modules | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Importing Module $_"
	Remove-Module $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	Import-Module $_ -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false | Out-Null
}

#endregion


#region StringEncryption
#$EncryptedString = Get-Content -Path  "Pass.txt"
#$string = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString -String $EncryptedString)))
#endregion

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting vCenter Connection"
Connect-VIServer -Server $Var_vCenter -User "svc_acc" -Password "encrystring" | Out-Null

$MaxParallel = 50
$TimeOut = 120
$ObjectRunspaceScriptBlock = {
		$MachineObj = New-Object -TypeName PSObject    
		$MachineObj | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.hostedmachinename
		
		if($_.powerstate -eq "On"){
			#powered on
				 try { 
		            Get-Service -ComputerName $_.hostedmachinename -DisplayName "Citrix*" | Start-Service | Out-Null	
		         	$MachineObj | Add-Member -MemberType NoteProperty -Name "Registration" -Value "SVC"    
		        } catch {
		               $MachineObj | Add-Member -MemberType NoteProperty -Name "Registration" -Value "RPC"  
		        }
		}elseif($_.powerstate -eq "Off"){
			$MachineObj | Add-Member -MemberType NoteProperty -Name "Registration" -Value "OFF"  
		}
		
		$MachineObj
}

function get-machinesunregistered {
	Param ([String]$Param_DLC)
		Get-BrokerMachine -AdminAddress $Param_DLC -MaxRecordCount 10000 -SessionSupport SingleSession -InMaintenanceMode $false -RegistrationState Unregistered 
}

function send-email {
Param ([int]$Param_Before,[int]$Param_After)
	 Send-MailMessage -from $Var_Sender `
	                           -to $Var_Recipients `
	                           -subject "XEN Vm Registration Check" `
	                           -body ("
	                              Me,<br /><br />
	                              Machines powered on with no users and 'unregistered' before script execution = $Param_Before  <br /><br />
								  Machines powered on with no users and 'unregistered' after script execution = $Param_After  <br /><br />
	                              Thank you<br/><br/> ")`
	                            -smtpServer $Var_IntRelay -BodyAsHtml 
	
}

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Getting list of unregistered machines"
$MachinesBefore = get-machinesunregistered -Param_DLC $($Var_Controllers | Get-Random)
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Machines unregistered"
$MachinesBefore | select Hostedmachinename, desktopgroupname, sessionusername | Sort-Object desktopgroupname | Out-Default

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Sending list of unregistered machines into threads"
$MachinesBefore | Start-RSJob -ScriptBlock $ObjectRunspaceScriptBlock -Throttle $MaxParallel | Out-Null
Get-RSJob | Wait-RSJob -ShowProgress -Timeout $TimeOut | Out-Null
$Results = Get-RSJob -State Completed | Receive-RSJob
Get-RSJob | Remove-RSJob -Force

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Sleeping 60 seconds"
Start-Sleep -Seconds 60

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Handling RPC machines and powered off machines"
$Results | foreach{
	if($_.registration -contains "RPC"){
		Restart-VM -VM $_.name -Confirm:$false -RunAsync | Out-Null
	}elseif($_.registration -contains "OFF"){
		Start-VM -VM $_.name -Confirm:$false -RunAsync | Out-Null
	}
}

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Sleeping 340 seconds"
Start-Sleep -Seconds 340

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Getting list of unregistered machines after execution"
$MachinesAfter = get-machinesunregistered -Param_DLC $($Var_Controllers | Get-Random)
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Machines unregistered after handling"
$MachinesAfter | select Hostedmachinename, desktopgroupname, sessionusername | Sort-Object desktopgroupname | Out-Default

$Var_Modules | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Removing Module $_"
	Remove-Module $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

Write-Output "################################################################"
Write-Output "Execution time: $($Var_Elapsed.Elapsed.ToString())" 
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Prepping email notification"
Stop-Transcript | Out-Null
send-email -Param_Before $MachinesBefore.Count -Param_After $MachinesAfter.count
