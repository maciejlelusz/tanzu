# Author: William Lam
# Website: www.williamlam.com

# TKG Content Library URL
$TKGContentLibraryName = "TKG-Content-Library"
$TKGContentLibraryURL = "https://wp-content.vmware.com/v2/latest/lib.json"

# Nested ESXi VMs IP's
$NestedESXiHostnameToIPs = @{
    "tanzu-esxi-1" = "192.168.1.221"
    "tanzu-esxi-2" = "192.168.1.222"
    "tanzu-esxi-3" = "192.168.1.223"
}

# VCSA Configuration
$VCSADisplayName = "vcsa-mgmt"
$VCSAIPAddress = "192.168.1.35"
$VCSAHostname = "vcsa-mgmt.int.inleo.pl" #Change to IP if you don't have valid DNS
$VCSAPrefix = "24"
$VCSASSODomainName = "inleo.lab"
$VCSASSOPassword = "XXX"
$VCSARootPassword = "XXX"

# Advanced Configurations
# Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
$addHostByDnsName = 1

#### DO NOT EDIT BEYOND HERE ####

$debug = $true
$verboseLogFile = "tanzu-basic-lab-deployment.log"

$esxiTotalCPU = 0
$vcsaTotalCPU = 0
$esxiTotalMemory = 0
$vcsaTotalMemory = 0
$esxiTotalStorage = 0
$vcsaTotalStorage = 0

$StartTime = Get-Date

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

My-Logger "Connecting to the new VCSA ..."
$vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

$d = Get-Datacenter -Server $vc $NewVCDatacenterName -ErrorAction Ignore
if( -Not $d) {
    My-Logger "Creating Datacenter $NewVCDatacenterName ..."
    New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
}

$c = Get-Cluster -Server $vc $NewVCVSANClusterName -ErrorAction Ignore
if( -Not $c) {
    My-Logger "Creating VSAN Cluster $NewVCVSANClusterName ..."
    New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled -HAEnabled -VsanEnabled | Out-File -Append -LiteralPath $verboseLogFile
    (Get-Cluster $NewVCVSANClusterName) | New-AdvancedSetting -Name "das.ignoreRedundantNetWarning" -Type ClusterHA -Value $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
}

$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
    $VMName = $_.Key
    $VMIPAddress = $_.Value

    $targetVMHost = $VMIPAddress
    if($addHostByDnsName -eq 1) {
        $targetVMHost = $VMName
    }
    My-Logger "Adding ESXi host $targetVMHost to Cluster ..."
    Add-VMHost -Server $vc -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
}

$haRuntime = (Get-Cluster $NewVCVSANClusterName).ExtensionData.RetrieveDasAdvancedRuntimeInfo
$totalHaHosts = $haRuntime.TotalHosts
$totalHaGoodHosts = $haRuntime.TotalGoodHosts
while($totalHaGoodHosts -ne $totalHaHosts) {
    My-Logger "Waiting for vSphere HA configuration to complete ..."
    Start-Sleep -Seconds 60
    $haRuntime = (Get-Cluster $NewVCVSANClusterName).ExtensionData.RetrieveDasAdvancedRuntimeInfo
    $totalHaHosts = $haRuntime.TotalHosts
    $totalHaGoodHosts = $haRuntime.TotalGoodHosts
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere with Tanzu Basic Lab Deployment Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"
