Function Set-EsxiNtpSource {
    <#
    .SYNOPSIS
        Set NTP Source Servers for ESXi hosts
    .DESCRIPTION
        Stop NTP service temporarily.
        Clear current NTP Source Servers.
        Add current NTP Source Servers.
        Set NTP Service Policy to "on" (Start and stop with host).
        Start NTP Service on ESXi hosts.
    .EXAMPLE
        Set-EsxiNtpSource -vCenter 'vcenter.fqdn.com'
        Set-EsxiNtpSource -vCenter 'vcenter.fqdn.com' -ntpSource "8.8.8.8"
    #>

    param (
        [parameter(Mandatory = $true)]$vCenter,
        [parameter(Mandatory = $false)]$ntpSource
    )
    
    if (!$vCenter) { Read-Host "Please enter the FQDN of the vCenter of the ESXi hosts to update NTP settings." }
    $vc_creds = Get-Credential

    #Connect to vCenter Server
    Connect-VIServer $vCenter -Credential $vc_creds -WarningAction Ignore | Out-Null

    #NTP Source Servers
    if (!$ntpSource) { $ntpSource = "8.8.8.8" }

    #Set NTP settings for hosts
    $EsxCluster = Get-Cluster | Out-GridView -OutputMode Multiple -Title "Select Cluster"
    $EsxHosts = Get-Cluster $EsxCluster | Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" -and $_.CnnectionState -ne "NotResponding" }
        foreach($EsxHost in $EsxHosts){
            $esxcli = Get-EsxCli -V2 -VMHost $EsxHost
            $EsxHost_id = ($EsxHost | Select-Object id).Id.Trim("HostSystem-host")
            $timeService = "HostDateTimeSystem-dateTimeSystem-" + $EsxHost_id
            $esxHostTimeService = Get-View -id $timeService
            $current_ntpSources = @($EsxHost | Get-VMHostNtpServer)
            $curSources = [string]::Join('|',$current_ntpSources)
            $ntpSources = [string]::Join('|',$ntpSource)

            if ($ntpSources -eq $curSources) {
                Write-Host "NTP Source is already up-to-date! " -NoNewline -ForegroundColor Green
                Write-Host "Skipping $EsxHost" -ForegroundColor Yellow
            }else{
                if ($esxcli.system.version.get.Invoke().Version -eq "6.7.0") {
                    #stop ntp service on host
                    Write-Host "Stopping NTP service on $EsxHost" -ForegroundColor Red
                    $ntpService = $EsxHost | Get-VMHostService | Where-Object {$_.key -eq "ntpd"}
                    Stop-VMHostService -HostService $ntpService -confirm:$false | Out-Null
                    Start-Sleep 2
                    
                    #clear current NTP servers
                    Write-Host "Clearing current NTP source(s) on $EsxHost" -ForegroundColor DarkMagenta
                    $current_ntpSources = @($EsxHost | Get-VMHostNtpServer)
                    foreach ($current_ntpSource in $current_ntpSources){
                        Remove-VMHostNtpServer -ntpserver $current_ntpSource -vmhost $EsxHost -confirm:$false | Out-Null
                    }
                    Start-Sleep 2

                    #and set new NTP servers
                    Write-Host "Adding NTP source(s) on $EsxHost" -ForegroundColor Cyan
                    Add-VMHostNtpServer -ntpserver $ntpSource -vmhost $EsxHost -confirm:$false | Out-Null
                    Start-Sleep 2
            
                    #set service policy to start and stop with host
                    Write-Host "Setting NTP service policy to 'on' on $EsxHost" -ForegroundColor Cyan
                    Set-VMHostService -HostService $ntpService -Policy "on" -confirm:$false | Out-Null
                    Start-Sleep 2

                    #start NTP on vmhost
                    Write-Host "Starting NTP service on $EsxHost" -ForegroundColor Green
                    Start-VMHostService -HostService $ntpService -confirm:$false | Out-Null
                    Start-Sleep 2
                    
                    #test NTP time service
                    Write-Host "Testing NTP service on $EsxHost" -ForegroundColor Green
                    $esxHostTimeService.RefreshDateTimeSystem()
                    $getDate = (get-date).ToUniversalTime().ToString("MMddyy HH:mm:ss")
                    $getEsxHostDate = ($esxHostTimeService.QueryDateTime()).ToUniversalTime().ToString("MMddyy HH:mm:ss")
                        if ($getDate -eq $getEsxHostDate) {
                            Write-Host "NTP source(s) and time are working properly." -ForegroundColor Green -NoNewline
                            Write-Host "Time is sycnrhonized." -ForegroundColor Green 
                        }else{
                            Write-Host "Please check that the NTP service is running on the host."
                        }
                }
                if ($esxcli.system.version.get.Invoke().Version -eq "7.0.3") {
                    #stop ntp service on host
                    Write-Host "Stopping NTP service on $EsxHost" -ForegroundColor Red
                    $ntpService = $EsxHost | Get-VMHostService | Where-Object {$_.key -eq "ntpd"}
                    Stop-VMHostService -HostService $ntpService -confirm:$false | Out-Null
                    Start-Sleep 2
                    
                    #clear current NTP servers
                    Write-Host "Clearing current NTP source(s) on $EsxHost" -ForegroundColor DarkMagenta
                    $current_ntpSources = @($EsxHost | Get-VMHostNtpServer)
                    foreach ($current_ntpSource in $current_ntpSources){
                        Remove-VMHostNtpServer -ntpserver $current_ntpSource -vmhost $EsxHost -confirm:$false | Out-Null
                    }
                    Start-Sleep 2
            
                    #and set new NTP servers
                    Write-Host "Adding NTP source(s) on $EsxHost" -ForegroundColor Cyan
                    $esxcli.system.ntp.set.Invoke(@{server = $ntpSource}) | Out-Null
                    Start-Sleep 2
            
                    #set service policy to start and stop with host
                    Write-Host "Setting NTP service policy to 'on' on $EsxHost" -ForegroundColor Cyan
                    Set-VMHostService -HostService $ntpService -Policy "on" -confirm:$false | Out-Null
                    Start-Sleep 2
            
                    #start NTP on vmhost
                    Write-Host "Starting NTP service on $EsxHost" -ForegroundColor Green
                    Start-VMHostService -HostService $ntpService -confirm:$false | Out-Null
                    Start-Sleep 2
                }
            }
        }
    Disconnect-VIServer * -Confirm:$false | Out-Null
}