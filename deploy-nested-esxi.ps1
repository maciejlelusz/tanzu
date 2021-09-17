# Based on https://github.com/lamw/vsphere-with-tanzu-basic-automated-lab-deployment
# Author: William Lam
# Website: www.williamlam.com

# vCenter Server used to deploy vSphere with Tanzu Basic Lab
$VIServer = "vcsa-mgmt.int.inleo.pl"
$VIUsername = "administrator@inleo.lab"
$VIPassword = "VMware1!"

# Full Path to both the Nested ESXi 7.0 VA, Extracted VCSA 7.0 ISO & HA Proxy OVAs
$NestedESXiApplianceOVA = "C:\Users\Administrator\Desktop\ml\Nested_ESXi7.0u2a_Appliance_Template_v1.ova"

# Nested ESXi VMs to deploy
$NestedESXiHostnameToIPs = @{
    "tanzu-esxi-1" = "192.168.1.221"
    "tanzu-esxi-2" = "192.168.1.222"
    "tanzu-esxi-3" = "192.168.1.223"
}

# Nested ESXi VM Resources
$NestedESXivCPU = "4"
$NestedESXivMEM = "24" #GB
$NestedESXiCachingvDisk = "8" #GB
$NestedESXiCapacityvDisk = "100" #GB

# General Deployment Configuration for Nested ESXi
$VMDatacenter = "INLEO"
$VMCluster = "Podmiejska"
$VMNetwork = "Lab-MGMT"
$VMDatastore = "esxi-1-physical-ds3-nvme"
$VMNetmask = "255.255.255.0"
$VMGateway = "192.168.1.1"
$VMDNS = "192.168.1.30"
$VMNTP = @("time.vmware.com")
$VMPassword = "VMware1!"
$VMDomain = "int.inleo.pl"
$VMSyslog = "192.168.1.30"
$VMFolder = "Tanzu"

# Applicable to Nested ESXi only
$VMSSH = "true"
$VMVMFS = "false"

# Advanced Configurations
# Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
$addHostByDnsName = 1

#### DO NOT EDIT BEYOND HERE ####

$debug = $true
$verboseLogFile = "tanzu-basic-lab-deployment.log"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$VAppName = "Nested-Tanzu-Basic-Lab-$random_string"

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

My-Logger "Connecting to Management vCenter Server $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

$datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
$cluster = Get-Cluster -Server $viConnection -Name $VMCluster
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1

$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
    $VMName = $_.Key
    $VMIPAddress = $_.Value

    $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
    $networkMapLabel = ($ovfconfig.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
    $ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork

    $ovfconfig.common.guestinfo.hostname.value = $VMName
    $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
    $ovfconfig.common.guestinfo.netmask.value = $VMNetmask
    $ovfconfig.common.guestinfo.gateway.value = $VMGateway
    $ovfconfig.common.guestinfo.dns.value = $VMDNS
    $ovfconfig.common.guestinfo.domain.value = $VMDomain
    $ovfconfig.common.guestinfo.ntp.value = $VMNTP
    $ovfconfig.common.guestinfo.syslog.value = $VMSyslog
    $ovfconfig.common.guestinfo.password.value = $VMPassword
    
    if($VMSSH -eq "true") {
        $VMSSHVar = $true
    } else {
        $VMSSHVar = $false
    }
    $ovfconfig.common.guestinfo.ssh.value = $VMSSHVar

    My-Logger "Deploying Nested ESXi VM $VMName ..."
    $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

    My-Logger "Adding vmnic2/vmnic3 for `"$VMNetwork`" and `"$HAProxyWorkloadNetwork`" to passthrough to Nested ESXi VMs ..."
    New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $VMNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $HAProxyWorkloadNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    $vm | New-AdvancedSetting -name "ethernet2.filter4.name" -value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
    $vm | New-AdvancedSetting -Name "ethernet2.filter4.onFailure" -value "failOpen" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile

    $vm | New-AdvancedSetting -name "ethernet3.filter4.name" -value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
    $vm | New-AdvancedSetting -Name "ethernet3.filter4.onFailure" -value "failOpen" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile

    Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Updating vSAN Cache VMDK size to $NestedESXiCachingvDisk GB & Capacity VMDK size to $NestedESXiCapacityvDisk GB ..."
    Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Powering On $vmname ..."
    $vm | Start-Vm -RunAsync | Out-Null
}

My-Logger "Creating vApp $VAppName ..."
$VApp = New-VApp -Name $VAppName -Server $viConnection -Location $cluster

if(-Not (Get-Folder $VMFolder -ErrorAction Ignore)) {
  My-Logger "Creating VM Folder $VMFolder ..."
  $folder = New-Folder -Name $VMFolder -Server $viConnection -Location (Get-Datacenter $VMDatacenter | Get-Folder vm)
}

My-Logger "Moving Nested ESXi VMs into $VAppName vApp ..."
$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
$vm = Get-VM -Name $_.Key -Server $viConnection
Move-VM -VM $vm -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere with Tanzu Basic Lab Deployment Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"
