
#region header
Param(
     [parameter(Mandatory=$true)]
     [ValidateSet("Disable", "Enable")]
     [String[]]$login
   )
	
$Var_Snapins = @("Citrix.Broker.Admin.v2")
$Var_Controllers = @("Server01")
$Var_Site = "Site"
$Var_Elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$Var_TranscriptPath = "$($PSScriptRoot)\transcript-"+$(Get-Date -format "yyyyMMddHHmmss")+".txt"
$Var_IntRelay = "email"
$Var_Sender = "sender"
$Var_Recipients = @("recip")

$Var_Snapins | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Importing Snapin $_"
	Remove-PSSnapin $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	Add-PSSnapin $_ -ErrorAction Stop -WarningAction SilentlyContinue
}
$Var_DeliveryGroups = @("   ") #targetted deliverygroups are entered here
$Var_Machines = $Var_DeliveryGroups | %{
	Get-BrokerMachine -AdminAddress $($Var_Controllers|Get-Random) -MaxRecordCount 10000  -DesktopGroupName $_
}

#endregion

Function Invoke-RemoteDosCommand {  
  [CmdletBinding()]Param(
    [Parameter(Mandatory=$true)][System.String]$MachineName,
    #[Parameter()][System.Management.Automation.PSCredential]$MachineCredential = $(New-Object System.Management.Automation.PSCredential("prod-am\zcompbuild",$(ConvertTo-SecureString "Sp1cyTun@" -AsPlainText -Force))),
    [Parameter(Mandatory=$true)][System.String]$DosCommand
  )
  $Cmd = "cmd /c $DosCommand"
  #Run the command      
  try {
    $ExecutionData += "Running remote command $DosCommand on $MachineName and retrieving process ID. "
    $Process = (Invoke-WmiMethod <#-Credential $MachineCredential#> -Class win32_process -Name create -ArgumentList $Cmd -ComputerName $MachineName -ErrorAction Stop)
    $ProcessID = $Process.ProcessID
  }
  catch {
    $ExceptionData = $_
  }
  #Wait for completion
  If(!$ExceptionData){
    $ExecutionData += "Waiting for process $processID to complete..."
    do {
      try {
        $ExecutionData += "Waiting..." 
        $RunningCheck = Get-WmiObject -Class Win32_Process -Filter "ProcessId='$ProcessId'" -ComputerName $MachineName -ErrorAction SilentlyContinue | ? { ($_.ProcessName -eq 'cmd.exe') } 
      }
      catch {
        $ExceptionData = $_
      }
    } while ($RunningCheck -ne $null)
    $ExecutionData += "Process return value is $($Process.ReturnValue)"
  }
  #Return results or exception
  If($ExceptionData){
      return $ExceptionData
      } else {
            return $ExecutionData
      }
}


function enable-logins ([System.Object[]] $Machines) {
	Write-Output "################################################################"
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Taking machines out of maintenance mode and registering them"
	$machines | %{
		$_ | Set-BrokerMachineMaintenanceMode -MaintenanceMode $false
		
		if($_.registrationstate -ne "Registered" ){
			if($_.powerstate -eq "On" ){
				New-BrokerHostingPowerAction -MachineName $_.hostedmachinename -Action Reset
			}elseif($_.powerstate -eq "Off"){
				New-BrokerHostingPowerAction -MachineName $_.hostedmachinename -Action TurnOn
			}
		}
	}
	
}


function disable-logins ([System.Object[]] $Machines) {

	Write-Output "################################################################"
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Placing machines into maintenance mode and sending reboot command"
	
	$machines | %{
		$_ | Set-BrokerMachineMaintenanceMode -MaintenanceMode $true
		
		$msg = "The desktop you are connected to will shutdown in 60 minutes.  Please save your work, close open applications, and log off your desktop. Thank you."
		Invoke-WmiMethod -Path Win32_Process -Name Create -ArgumentList "msg * /time:3600 $msg" -ComputerName $_.HostedMachineName | Out-Null
		Invoke-RemoteDosCommand -DosCommand "Shutdown -r -t 3600" -MachineName $_.hostedmachinename | Out-Null

	}

}


Start-Transcript -Path $Var_TranscriptPath
#Clear-Host

Write-Output "################################################################"
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Machines before processing"
$Var_Machines | select sessionusername, desktopgroupname, sessionstarttime,hostedmachinename,inmaintenancemode,registrationstate | Sort-Object sessionstarttime -Descending | ft | Out-Default

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Parameter entered: $login"
if($login -eq "Enable"){
	Enable-Logins -Machines $Var_Machines
}elseif( $login -eq "Disable"){
	Disable-logins -Machines $Var_Machines
}


$Var_Elapsed.Stop()

sleep -Seconds 10
Write-Output "################################################################"
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:MM:ss') Machines after processing"

$Var_DeliveryGroups = @("LockedDown Desktop")
$Var_Machines = $Var_DeliveryGroups | %{
	Get-BrokerMachine -AdminAddress $($Var_Controllers|Get-Random) -MaxRecordCount 10000  -DesktopGroupName $_
}
$Var_Machines | select sessionusername, desktopgroupname, sessionstarttime,hostedmachinename,inmaintenancemode,registrationstate | Sort-Object sessionstarttime -Descending | ft | Out-Default


Write-Output "################################################################"
Write-Output "Execution time: $($Var_Elapsed.Elapsed.ToString())" 

Stop-Transcript | Out-Null

Send-MailMessage -from $Var_Sender `
                    -to $Var_Recipients `
                    -subject "LockedDown VDI - $Login" `
                    -body ("
                        Team,<br /><br />
                        Thanks<br /><br /> 
                                                                                          
                    "  )` -Attachments $Var_TranscriptPath -smtpServer $Var_IntRelay -BodyAsHtml 

  
    
    




















