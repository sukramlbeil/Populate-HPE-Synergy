##############################################################################
# Populate_HPE_Synergy.ps1
#
# - Example script for configuring the HPE Synergy Appliance
#
#   VERSION 4.00
#
#   AUTHORS
#   Dave Olker - HPE Global Solutions Engineering
#
# (C) Copyright 2018 Hewlett Packard Enterprise Development LP
##############################################################################
<#
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
#>


function Add_Firmware_Bundle
{
    Write-Output "Adding Firmware Bundles" | Timestamp
    $firmware_bundle = Read-Host "Optional: Specify location of Service Pack for ProLiant ISO file"
    if ($firmware_bundle) {
        if (Test-Path $firmware_bundle) {
            Add-HPOVBaseline -File $firmware_bundle | Wait-HPOVTaskComplete
        }
        else {
            Write-Output "Service Pack for ProLiant file '$firmware_bundle' not found.  Skipping firmware upload."
        }
    }

    Write-Output "Firmware Bundle Added" | Timestamp
}


function Add_Licenses
{
    Write-Output "Adding OneView and Synergy FC Licenses" | Timestamp

    $License_File = Read-Host -Prompt "Optional: Enter Filename Containing OneView and Synergy FC Licenses"
    if ($License_File) {
        New-HPOVLicense -File $License_File
    }

    Write-Output "All Licenses Added" | Timestamp
}


function Configure_Time_and_Locale
{
    Write-Output "Configuring Time and Locale" | Timestamp

    if ($NTPServers)
    {
        Set-HPOVApplianceDateTime -Locale $Locale -NTPServers $NTPServers -PollingInterval $NTPPollingInterval
    }

    Write-Output "Time and Locale Configured" | Timestamp
}


function Configure_SMTP
{
    Write-Output "Configuring SMTP Settings" | Timestamp
    Set-HPOVSmtpConfig -SenderEmailAddress $SMTPEmailAddress -Server $SMTPEmailServer -Port $SMTPEmailPort -ConnectionSecurity $SMTPEmailSecurity
    Add-HPOVSmtpAlertEmailFilter -Name $SMTPAlertName -Emails $SMTPEmailAddress 
    Write-Output "SMTP Settings Configured" | Timestamp
}


function Configure_Address_Pools
{
    Write-Output "Configuring Address Pools for MAC, WWN, and Serial Numbers" | Timestamp

    if ($vMACAddressPoolRangeStart)
    {
        New-HPOVAddressPoolRange    -PoolType vmac                      `
                                    -RangeType Custom                   `
                                    -Start $vMACAddressPoolRangeStart   `
                                    -End $vMACAddressPoolRangeEnd
    } else {
        New-HPOVAddressPoolRange    -PoolType vmac                      `
                                    -RangeType Generated
    }

    if ($vWWNAddressPoolRangeStart)
    {
        New-HPOVAddressPoolRange    -PoolType vwwn                      `
                                    -RangeType Custom                   `
                                    -Start $vWWNAddressPoolRangeStart   `
                                    -End $vWWNAddressPoolRangeEnd
    } else {
        New-HPOVAddressPoolRange    -PoolType vwwn                      `
                                    -RangeType Generated
    }
    
    if ($vSNAddressPoolRangeStart)
    {
        New-HPOVAddressPoolRange    -PoolType vsn                       `
                                    -RangeType Custom                   `
                                    -Start $vSNAddressPoolRangeStart    `
                                    -End $vSNAddressPoolRangeEnd
    } else {
        New-HPOVAddressPoolRange    -PoolType vsn                       `
                                    -RangeType Generated
    }
    
    Write-Output "Address Pool Ranges Configuration Complete" | Timestamp
}


function Disable_VSN_Address_Pools
{
    Write-Output "Disabling Address Pools for Virtual Serial Numbers" | Timestamp
    Send-HPOVRequest -uri "/rest/id-pools/vsn" -method PUT -body @{'type' = 'Pool'; 'enabled' = 'false'}
    Write-Output "Virtual Serial Number Address Pool Ranges Disabled" | Timestamp
}


function Add_Remote_Enclosures
{
    Write-Output "Adding Remote Enclosures" | Timestamp
    Send-HPOVRequest -uri "/rest/enclosures" -method POST -body @{'hostname' = 'fe80::2:0:9:7%eth2'} | Wait-HPOVTaskComplete
    Write-Output "Remote Enclosures Added" | Timestamp
    #
    # Sleep for 10 seconds to allow remote enclosures to quiesce
    #
    Start-Sleep 10
}


function Rename_Enclosures
{
    Write-Output "Renaming Enclosures" | Timestamp
    [array]$EncSerialNums = $EnclosureSerialNumbers.split(",").Trim()
    [array]$EncNames      = $EnclosureNames.split(",").Trim()

    if ($EncSerialNums)
    {
        for ($i = 0; $i -le ($EncSerialNums.Length -1); $i += 1)
        {
            $Enc = Get-HPOVEnclosure -Name $EncSerialNums[$i] -ErrorAction Stop
            Set-HPOVEnclosure -Name $EncNames[$i] -Enclosure $Enc | Wait-HPOVTaskComplete
        }
    }

    Write-Output "All Enclosures Renamed" | Timestamp
}


function PowerOff_All_Servers
{
    Write-Output "Powering Off All Servers" | Timestamp

    $Servers = Get-HPOVServer

    $Servers | ForEach-Object {
        if ($_.PowerState -ne "Off") {
            Write-Host "Server $($_.Name) is $($_.PowerState).  Powering off..." | Timestamp
            Stop-HPOVServer -Server $_ -Force -Confirm:$false | Wait-HPOVTaskComplete
        }
    }

    Write-Output "All Servers Powered Off" | Timestamp
}


function Configure_SAN_Managers
{
    Write-Output "Configuring SAN Managers" | Timestamp

    [array]$SMHostNames         = $SANManagerHostNames.split(",").Trim()
    [array]$SMType              = $SANManagerType.split(",").Trim()
    [array]$SMPort              = $SANManagerPort.split(",").Trim()
    [array]$SMSNMPAuthProtocol  = $SANManagerSNMPAuthProtocol.split(",").Trim()
    [array]$SMSNMPUser          = $SANManagerSNMPUser.split(",").Trim()
    [array]$SMSNMPAuthLevel     = $SANManagerSNMPAuthLevel.split(",").Trim()
    [array]$SMSNMPAuthPassword  = $SANManagerSNMPAuthPassword.split(",").Trim()
    [array]$SMSNMPPrivPassword  = $SANManagerSNMPPrivPassword.split(",").Trim()
    [array]$SMSNMPPrivProtocol  = $SANManagerSNMPPrivProtocol.split(",").Trim()

    if ($SMHostNames)
    {
        for ($i = 0; $i -le ($SMHostNames.Length -1); $i += 1)
        {
            #
            # Need to add case for non-Cisco SAN Managers
            #
            if ($SMType[$i] -eq "Cisco")
            {
                Add-HPOVSanManager  -Hostname $SMHostNames[$i]                  `
                                    -Type $SMType[$i]                           `
                                    -SnmpUserName $SMSNMPUser[$i]               `
                                    -SnmpAuthLevel $SMSNMPAuthLevel[$i]         `
                                    -SnmpAuthPassword $SMSNMPAuthPassword[$i]   `
                                    -SnmpAuthProtocol $SMSNMPAuthProtocol[$i]   `
                                    -SnmpPrivPassword $SMSNMPPrivPassword[$i]   `
                                    -SnmpPrivProtocol $SMSNMPPrivProtocol[$i]   `
                                    -Port $SMPort[$i] | Wait-HPOVTaskComplete
            }
        }
    }

    Write-Output "SAN Manager Configuration Complete" | Timestamp
}


function Configure_Networks_Pools
{
    Write-Output "Adding IPv4 Prod Subnet" | Timestamp

    [array]$ProdDNS                 = $ProdNetDNSServers.split(",").Trim()
    New-HPOVAddressPoolSubnet       -Domain $ProdNetDomain          `
                                    -Gateway $ProdNetGateway        `
                                    -NetworkId $ProdNetSubnet       `
                                    -SubnetMask $ProdNetMask        `
                                    -DNSServers $ProdDNS

    Get-HPOVAddressPoolSubnet       -NetworkId $ProdNetSubnet |     `
        New-HPOVAddressPoolRange    -Name $ProdNetName              `
                                    -Start $ProdNetPoolStart        `
                                    -End $ProdNetPoolEnd

    Write-Output "Adding IPv4 Deployment Subnet" | Timestamp

    [array]$DeployDNS               = $DeployNetDNSServers.split(",").Trim()
    New-HPOVAddressPoolSubnet       -Domain $DeployNetDomain        `
                                    -Gateway $DeployNetGateway      `
                                    -NetworkId $DeployNetSubnet     `
                                    -SubnetMask $DeployNetMask      `
                                    -DNSServers $DeployDNS
    
    Get-HPOVAddressPoolSubnet       -NetworkId $DeployNetSubnet |   `
        New-HPOVAddressPoolRange    -Name $DeployNetName            `
                                    -Start $DeployNetPoolStart      `
                                    -End $DeployNetPoolEnd

    Write-Output "Network Pools Configuration Complete" | Timestamp
}


function Configure_Ethernet_Networks
{
    Write-Output "Adding Ethernet Networks" | Timestamp

    [array]$ENetName             = $ENetworkName.split(",").Trim()
    [array]$ENetType             = $ENetworkType.split(",").Trim()
    [array]$ENetPurpose          = $ENetworkPurpose.split(",").Trim()
    [array]$ENetMaxBandwidth     = $ENetworkMaxBandwidth.split(",").Trim()
    [array]$ENetTypicalBandwidth = $ENetworkTypicalBandwidth.split(",").Trim()
    [array]$ENetVlanID           = $ENetworkVlanID.split(",").Trim()
    [array]$ENetVlanType         = $ENetworkVlanType.split(",").Trim()

    if ($ENetName)
    {
        for ($i = 0; $i -le ($ENetName.Length -1); $i += 1)
        {
            New-HPOVNetwork     -Name $ENetName[$i]                              `
                                -Type $ENetType[$i]                              `
                                -Purpose $ENetPurpose[$i]                        `
                                -MaximumBandwidth $ENetMaxBandwidth[$i]          `
                                -TypicalBandwidth $ENetTypicalBandwidth[$i]      `
                                -VlanId $ENetVlanID[$i]                          `
                                -VLANType $ENetVlanType[$i]
        }
    }

    $Prod_AddrPool = Get-HPOVAddressPoolSubnet -NetworkId $ProdNetSubnet
    Get-HPOVNetwork -Name $ProdNetName | Set-HPOVNetwork -IPv4Subnet $Prod_AddrPool

    $Deploy_AddrPool = Get-HPOVAddressPoolSubnet -NetworkId $DeployNetSubnet
    Get-HPOVNetwork -Name $DeployNetName | Set-HPOVNetwork -IPv4Subnet $Deploy_AddrPool

    Write-Output "Ethernet Network Configuration Complete" | Timestamp
}


function Configure_FC_Networks
{
    Write-Output "Adding Fibre Channel Networks" | Timestamp

    [array]$FCNetName               = $FCNetworkName.split(",").Trim()
    [array]$FCNetType               = $FCNetworkType.split(",").Trim()
    [array]$FCNetFabricType         = $FCNetworkFabricType.split(",").Trim()
    [array]$FCNetLinkStabilityTime  = $FCNetworkLinkStabilityTime.split(",").Trim()
    [array]$FCNetManagedSAN         = $FCNetworkManagedSAN.split(",").Trim()
    [array]$FCNetMaxBandwidth       = $FCNetworkMaxBandwidth.split(",").Trim()
    [array]$FCNetTypicalBandwidth   = $FCNetworkTypicalBandwidth.split(",").Trim()
    [array]$FCNetAutoLogin          = $FCNetworkAutoLogin.split(",").Trim()

    if ($FCNetName)
    {
        for ($i = 0; $i -le ($FCNetName.Length -1); $i += 1)
        {
            $FCAutoLogin        = [bool]$FCNetAutoLogin[$i]
            New-HPOVNetwork     -Name $FCNetName[$i]                                `
                                -Type $FCNetType[$i]                                `
                                -FabricType $FCNetFabricType[$i]                    `
                                -LinkStabilityTime $FCNetLinkStabilityTime[$i]      `
                                -ManagedSan $FCNetManagedSAN[$i]                    `
                                -MaximumBandwidth $FCNetMaxBandwidth[$i]            `
                                -TypicalBandwidth $FCNetTypicalBandwidth[$i]        `
                                -AutoLoginRedistribution $FCAutoLogin
        }
    }

    Write-Output "FC Network Configuration Complete" | Timestamp
}


function Configure_FCoE_Networks
{
    Write-Output "Adding Fibre Channel over Ethernet Networks" | Timestamp

    [array]$FCoENetName             = $FCoENetworkName.split(",").Trim()
    [array]$FCoENetType             = $FCoENetworkType.split(",").Trim()
    [array]$FCoEVlanID              = $FCoENetworkVlanID.split(",").Trim()
    [array]$FCoEManagedSAN          = $FCoENetworkManagedSAN.split(",").Trim()
    [array]$FCoEMaxBandwidth        = $FCoENetworkMaxBandwidth.split(",").Trim()
    [array]$FCoETypicalBandwidth    = $FCoENetworkTypicalBandwidth.split(",").Trim()

    if ($FCoENetName)
    {
        for ($i = 0; $i -le ($FCoENetName.Length -1); $i += 1)
        {
            New-HPOVNetwork     -Name $FCoENetName[$i]                          `
                                -Type $FCoENetType[$i]                          `
                                -VlanId $FCoEVlanID[$i]                         `
                                -ManagedSan $FCoEManagedSAN[$i]                 `
                                -MaximumBandwidth $FCoEMaxBandwidth[$i]         `
                                -TypicalBandwidth $FCoETypicalBandwidth[$i]
        }
    }

    Write-Output "FC Network Configuration Complete" | Timestamp
}


function Configure_Network_Sets
{
    Write-Output "Adding Network Sets" | Timestamp

    [array]$NetSetName              = $NetworkSetName.split(",").Trim()
    [array]$NetSetNetworks          = $NetworkSetNetworks.split(",").Trim()
    [array]$NetSetMaxBandwidth      = $NetworkSetMaxBandwidth.split(",").Trim()
    [array]$NetSetTypicalBandwidth  = $NetworkSetTypicalBandwidth.split(",").Trim()

    if ($NetSetName)
    {
        for ($i = 0; $i -le ($NetSetName.Length -1); $i += 1)
        {
            New-HPOVNetworkSet  -Name $NetSetName[$i]                           `
                                -Networks $NetSetNetworks[$i].Split('|')        `
                                -MaximumBandwidth $NetSetMaxBandwidth[$i]       `
                                -TypicalBandwidth $NetSetTypicalBandwidth[$i]
        }
    }

    Write-Output "Network Set Configuration Complete" | Timestamp
}


function Configure_3PAR_Storage
{
    Write-Output "Adding 3PAR Storage Systems" | Timestamp

    [array]$3PARHostName            = $3PARStorageHostName.split(",").Trim()
    [array]$3PARSystemName          = $3PARStorageSystemName.split(",").Trim()
    [array]$3PARDomain              = $3PARStorageDomain.split(",").Trim()
    [array]$3PARUser                = $3PARStorageUser.split(",").Trim()
    [array]$3PARPassword            = $3PARStoragePassword.split(",").Trim()
    [array]$3PARStoragePools        = $3PARStoragePools.split(",").Trim()

    if ($3PARHostName)
    {
        for ($i = 0; $i -le ($3PARHostName.Length -1); $i += 1)
        {
            Add-HPOVStorageSystem   -Hostname $3PARHostName[$i]         `
                                    -Domain $3PARDomain[$i]             `
                                    -Username $3PARUser[$i]             `
                                    -Password $3PARPassword[$i]
        }
    }
    
    if ($3PARStoragePools)
    {
        for ($i = 0; $i -le ($3PARStoragePools.Length -1); $i += 1)
        {
            Add-HPOVStoragePool     -StorageSystem $3PARSystemName[$i]  `
                                    $3PARStoragePools[$i].Split('|')
        }
    }

    Write-Output "Adding 3PAR Storage Volume Templates" | Timestamp

    [array]$3PSVTName               = $3PARSVTName.split(",").Trim()
    [array]$3PSVTSystem             = $3PARSVTStorageSystem.split(",").Trim()
    [array]$3PSVTCapacity           = $3PARSVTCapacity.split(",").Trim()
    [array]$3PSVTStoragePool        = $3PARSVTStoragePool.split(",").Trim()
    [array]$3PSVTSnapPool           = $3PARSVTSnapStoragePool.split(",").Trim()
    [array]$3PSVTShared             = $3PARSVTShared.split(",").Trim()
    [array]$3PSVTDeDupe             = $3PARSVTDeDupe.split(",").Trim()

    if ($3PSVTName)
    {
        for ($i = 0; $i -le ($3PSVTName.Length -1); $i += 1)
        {
            $DeDupe                 = [bool]$3PSVTDeDupe[$i]

            if ($3PSVTShared[$i] -eq "True")
            {
                New-HPOVStorageVolumeTemplate   -Name $3PSVTName[$i]                        `
                                                -StorageSystem $3PSVTSystem[$i]             `
                                                -Capacity $3PSVTCapacity[$i]                `
                                                -StoragePool $3PSVTStoragePool[$i]          `
                                                -SnapshotStoragePool $3PSVTSnapPool[$i]     `
                                                -EnableDeduplication $DeDupe                `
                                                -Shared    
            } else {
                New-HPOVStorageVolumeTemplate   -Name $3PSVTName[$i]                        `
                                                -StorageSystem $3PSVTSystem[$i]             `
                                                -Capacity $3PSVTCapacity[$i]                `
                                                -StoragePool $3PSVTStoragePool[$i]          `
                                                -SnapshotStoragePool $3PSVTSnapPool[$i]     `
                                                -EnableDeduplication $DeDupe
            }
        }
    }

    Write-Output "Adding 3PAR Storage Volumes" | Timestamp

    [array]$3PVolName               = $3PARVolName.split(",").Trim()
    [array]$3PVolSystem             = $3PARVolStorageSystem.split(",").Trim()
    [array]$3PVolCapacity           = $3PARVolCapacity.split(",").Trim()
    [array]$3PVolStoragePool        = $3PARVolStoragePool.split(",").Trim()
    [array]$3PVolSnapPool           = $3PARVolSnapStoragePool.split(",").Trim()
    [array]$3PVolShared             = $3PARVolShared.split(",").Trim()
    
    if ($3PVolName)
    {
        for ($i = 0; $i -le ($3PVolName.Length -1); $i += 1)
        {
            if ($3PVolShared[$i] -eq "True")
            {
                New-HPOVStorageVolume   -Name $3PVolName[$i]                        `
                                        -StorageSystem $3PVolSystem[$i]             `
                                        -Capacity $3PVolCapacity[$i]                `
                                        -StoragePool $3PVolStoragePool[$i]          `
                                        -SnapshotStoragePool $3PVolSnapPool[$i]     `
                                        -Shared
            } else {
                New-HPOVStorageVolume   -Name $3PVolName[$i]                        `
                                        -StorageSystem $3PVolSystem[$i]             `
                                        -Capacity $3PVolCapacity[$i]                `
                                        -StoragePool $3PVolStoragePool[$i]          `
                                        -SnapshotStoragePool $3PVolSnapPool[$i]
            }
        }
    }

    Write-Output "3PAR Storage Configuration Complete" | Timestamp
}


function Configure_StoreVirtual_Storage
{
    Write-Output "Adding StoreVirtual Storage Systems" | Timestamp

    [array]$SVHostName              = $StoreVirtualHostName.split(",").Trim()
    [array]$SVNetworkName           = $StoreVirtualNetworkName.split(",").Trim()
    [array]$SVUserName              = $StoreVirtualUserName.split(",").Trim()
    [array]$SVPassword              = $StoreVirtualPassword.split(",").Trim()

    if ($SVHostName)
    {
        for ($i = 0; $i -le ($SVHostName.Length -1); $i += 1)
        {
            $SVNet =                    Get-HPOVNetwork -Name $SVNetworkName[$i]
            Add-HPOVStorageSystem       -Hostname $SVHostName[$i]                       `
                                        -Family StoreVirtual                            `
                                        -Username $SVUserName[$i]                       `
                                        -Password $SVPassword[$i]                       `
                                        -VIPS @{ $SVHostName[$i] = $SVNet }
        }
    }

    Write-Output "Adding StoreVirtual Storage Volume Templates" | Timestamp

    [array]$SVSVTName               = $StoreVirtSVTName.split(",").Trim()
    [array]$SVSVTSystem             = $StoreVirtSVTStorageSystem.split(",").Trim()
    [array]$SVSVTCapacity           = $StoreVirtSVTCapacity.split(",").Trim()
    [array]$SVSVTStoragePool        = $StoreVirtSVTStoragePool.split(",").Trim()
    [array]$SVSVTProvisionType      = $StoreVirtSVTProvisionType.split(",").Trim()
    [array]$SVSVTShared             = $StoreVirtSVTShared.split(",").Trim()

    if ($SVSVTName)
    {
        for ($i = 0; $i -le ($SVSVTName.Length -1); $i += 1)
        {
            if ($SVSVTShared[$i] -eq "True")
            {
                New-HPOVStorageVolumeTemplate   -Name $SVSVTName[$i]                        `
                                                -StorageSystem $SVSVTSystem[$i]             `
                                                -Capacity $SVSVTCapacity[$i]                `
                                                -StoragePool $SVSVTStoragePool[$i]          `
                                                -ProvisionType $SVSVTProvisionType[$i]      `
                                                -Shared    
            } else {
                New-HPOVStorageVolumeTemplate   -Name $SVSVTName[$i]                        `
                                                -StorageSystem $SVSVTSystem[$i]             `
                                                -Capacity $SVSVTCapacity[$i]                `
                                                -StoragePool $SVSVTStoragePool[$i]          `
                                                -ProvisionType $SVSVTProvisionType[$i]
            }
        }
    }

    Write-Output "StoreVirtual Configuration Complete" | Timestamp
}


function Create_Uplink_Sets
{
    Write-Output "Adding Fibre Channel and FCoE Uplink Sets" | Timestamp
    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $SAN_A_FC = Get-HPOVNetwork -Name "SAN A FC"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-SAN-A-FC" -Type FibreChannel -Networks $SAN_A_FC -UplinkPorts "Enclosure1:BAY3:Q2.1" | Wait-HPOVTaskComplete

    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $SAN_B_FC = Get-HPOVNetwork -Name "SAN B FC"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-SAN-B-FC" -Type FibreChannel -Networks $SAN_B_FC -UplinkPorts "Enclosure2:BAY6:Q2.1" | Wait-HPOVTaskComplete

    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $SAN_A_FCoE = Get-HPOVNetwork -Name "SAN A FCoE"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-SAN-A-FCoE" -Type Ethernet -Networks $SAN_A_FCoE -UplinkPorts "Enclosure1:BAY3:Q1.1" -LacpTimer Short | Wait-HPOVTaskComplete

    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $SAN_B_FCoE = Get-HPOVNetwork -Name "SAN B FCoE"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-SAN-B-FCoE" -Type Ethernet -Networks $SAN_B_FCoE -UplinkPorts "Enclosure2:BAY6:Q1.1" -LacpTimer Short | Wait-HPOVTaskComplete

    Write-Output "Adding FlexFabric Uplink Sets" | Timestamp
    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $ESX_Mgmt = Get-HPOVNetwork -Name "ESX Mgmt"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-ESX-Mgmt" -Type Ethernet -Networks $ESX_Mgmt -UplinkPorts "Enclosure1:Bay3:Q1.2","Enclosure2:Bay6:Q1.2" | Wait-HPOVTaskComplete

    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $ESX_vMotion = Get-HPOVNetwork -Name "ESX vMotion"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-ESX-vMotion" -Type Ethernet -Networks $ESX_vMotion -UplinkPorts "Enclosure1:Bay3:Q1.3","Enclosure2:Bay6:Q1.3" | Wait-HPOVTaskComplete

    $LIGFlex = Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric"
    $Prod_Nets = Get-HPOVNetwork -Name "Prod*"
    New-HPOVUplinkSet -Resource $LIGFlex -Name "US-Prod" -Type Ethernet -Networks $Prod_Nets -UplinkPorts "Enclosure1:Bay3:Q1.4","Enclosure2:Bay6:Q1.4" | Wait-HPOVTaskComplete

    Write-Output "Adding ImageStreamer Uplink Sets" | Timestamp
    $ImageStreamerDeploymentNetworkObject = Get-HPOVNetwork -Name "Deployment" -ErrorAction Stop
    Get-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric" -ErrorAction Stop | New-HPOVUplinkSet -Name "US-Image Streamer" -Type ImageStreamer -Networks $ImageStreamerDeploymentNetworkObject -UplinkPorts "Enclosure1:Bay3:Q5.1","Enclosure1:Bay3:Q6.1","Enclosure2:Bay6:Q5.1","Enclosure2:Bay6:Q6.1" | Wait-HPOVTaskComplete

    Write-Output "All Uplink Sets Configured" | Timestamp
}


function Create_Enclosure_Group
{
    $3FrameVCLIG = Get-HPOVLogicalInterconnectGroup -Name LIG-FlexFabric
    $SasLIG = Get-HPOVLogicalInterconnectGroup -Name LIG-SAS
    $FcLIG = Get-HPOVLogicalInterconnectGroup -Name LIG-FC
    New-HPOVEnclosureGroup -name "EG-Synergy-Local" -LogicalInterconnectGroupMapping @{Frame1 = $3FrameVCLIG,$SasLIG,$FcLIG; Frame2 = $3FrameVCLIG,$SasLIG,$FcLIG; Frame3 = $3FrameVCLIG,$SasLIG,$FcLIG} -EnclosureCount 3 -IPv4AddressType External -DeploymentNetworkType Internal

    Write-Output "Enclosure Group Created" | Timestamp
}


function Create_Enclosure_Group_Remote
{
    $2FrameVCLIG_1 = Get-HPOVLogicalInterconnectGroup -Name LIG-FlexFabric-Remote-1
    $2FrameVCLIG_2 = Get-HPOVLogicalInterconnectGroup -Name LIG-FlexFabric-Remote-2
    $FcLIG = Get-HPOVLogicalInterconnectGroup -Name LIG-FC-Remote
    New-HPOVEnclosureGroup -name "EG-Synergy-Remote" -LogicalInterconnectGroupMapping @{Frame1 = $FcLIG,$2FrameVCLIG_1,$2FrameVCLIG_2; Frame2 = $FcLIG,$2FrameVCLIG_1,$2FrameVCLIG_2} -EnclosureCount 2

    Write-Output "Enclosure Group Created" | Timestamp
}


function Create_Logical_Enclosure
{
    Write-Output "Creating Local Logical Enclosure" | Timestamp
    $EG = Get-HPOVEnclosureGroup -Name EG-Synergy-Local
    $Encl = Get-HPOVEnclosure -Name Synergy-Encl-1
    New-HPOVLogicalEnclosure -EnclosureGroup $EG -Name LE-Synergy-Local -Enclosure $Encl | Wait-HPOVTaskComplete
    Write-Output "Logical Enclosure Created" | Timestamp
}


function Create_Logical_Enclosure_Remote
{
    Write-Output "Creating Remote Logical Enclosure" | Timestamp
    $EG = Get-HPOVEnclosureGroup -Name EG-Synergy-Remote
    $Encl = Get-HPOVEnclosure -Name Synergy-Encl-4
    New-HPOVLogicalEnclosure -EnclosureGroup $EG -Name LE-Synergy-Remote -Enclosure $Encl | Wait-HPOVTaskComplete
    Write-Output "Logical Enclosure Created" | Timestamp
}


function Create_Logical_Interconnect_Groups
{
    Write-Output "Creating Local Logical Interconnect Groups" | Timestamp
    New-HPOVLogicalInterconnectGroup -Name "LIG-SAS" -FrameCount 1 -InterconnectBaySet 1 -FabricModuleType "SAS" -Bays @{Frame1 = @{Bay1 = "SE12SAS" ; Bay4 = "SE12SAS"}}
    New-HPOVLogicalInterconnectGroup -Name "LIG-FC" -FrameCount 1 -InterconnectBaySet 2 -FabricModuleType "SEVCFC" -Bays @{Frame1 = @{Bay2 = "SEVC16GbFC" ; Bay5 = "SEVC16GbFC"}}
    New-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric" -FrameCount 3 -InterconnectBaySet 3 -FabricModuleType "SEVC40F8" -Bays @{Frame1 = @{Bay3 = "SEVC40f8" ; Bay6 = "SE20ILM"};Frame2 = @{Bay3 = "SE20ILM"; Bay6 = "SEVC40f8" };Frame3 = @{Bay3 = "SE20ILM"; Bay6 = "SE20ILM"}} -FabricRedundancy "HighlyAvailable"
    Write-Output "Logical Interconnect Groups Created" | Timestamp
}


function Create_Logical_Interconnect_Groups_Remote
{
    Write-Output "Creating Remote Logical Interconnect Groups" | Timestamp
    New-HPOVLogicalInterconnectGroup -Name "LIG-FC-Remote" -FrameCount 1 -InterconnectBaySet 1 -FabricModuleType "SEVCFC" -Bays @{Frame1 = @{Bay1 = "SEVC16GbFC" ; Bay4 = "SEVC16GbFC"}}
    New-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric-Remote-1" -FrameCount 2 -InterconnectBaySet 2 -FabricModuleType "SEVC40F8" -Bays @{Frame1 = @{Bay2 = "SEVC40f8" ; Bay5 = "SE20ILM"};Frame2 = @{Bay2 = "SE20ILM"; Bay5 = "SEVC40F8" }} -FabricRedundancy "HighlyAvailable"
    New-HPOVLogicalInterconnectGroup -Name "LIG-FlexFabric-Remote-2" -FrameCount 2 -InterconnectBaySet 3 -FabricModuleType "SEVC40F8" -Bays @{Frame1 = @{Bay3 = "SEVC40f8" ; Bay6 = "SE20ILM"};Frame2 = @{Bay3 = "SE20ILM"; Bay6 = "SEVC40F8" }} -FabricRedundancy "HighlyAvailable"
    Write-Output "Logical Interconnect Groups Created" | Timestamp
}


function Create_OS_Deployment_Server
{
    Write-Output "Configuring OS Deployment Servers" | Timestamp
    $ManagementNetwork = Get-HPOVNetwork -Type Ethernet -Name "Mgmt"
    Get-HPOVImageStreamerAppliance | Select-Object -First 1 | New-HPOVOSDeploymentServer -Name "LE1 Image Streamer" -ManagementNetwork $ManagementNetwork -Description "Image Streamer for Logical Enclosure 1" | Wait-HPOVTaskComplete
    Write-Output "OS Deployment Server Configured" | Timestamp
}


function Create_Server_Profile_Template_SY480_Gen9_RHEL_Local_Boot
{
    Write-Output "Creating SY480 Gen9 with Local Boot for RHEL Server Profile Template" | Timestamp

    $SHT               = Get-HPOVServerHardwareTypes -Name "SY 480 Gen9 1" -ErrorAction Stop
    $EnclGroup         = Get-HPOVEnclosureGroup -Name "EG-Synergy-Local" -ErrorAction Stop
    $Eth1              = Get-HPOVNetwork -Name "Prod_1101" | New-HPOVServerProfileConnection -ConnectionID 1 -Name 'Prod-1101' -PortId "Mezz 3:1-c"
    $Eth2              = Get-HPOVNetwork -Name "Prod_1102" | New-HPOVServerProfileConnection -ConnectionID 2 -Name 'Prod-1102' -PortId "Mezz 3:2-c"
    $Deploy1           = Get-HPOVNetwork -Name "Deployment" | New-HPOVServerProfileConnection -ConnectionID 3 -Name 'Deployment Network A' -PortId "Mezz 3:1-a" -Bootable -Priority Primary
    $Deploy2           = Get-HPOVNetwork -Name "Deployment" | New-HPOVServerProfileConnection -ConnectionID 4 -Name 'Deployment Network B' -PortId "Mezz 3:2-a" -Bootable -Priority Secondary
    $LogicalDisk       = New-HPOVServerProfileLogicalDisk -Name "SAS RAID1 SSD" -RAID RAID1 -NumberofDrives 2 -DriveType SASSSD -Bootable $True
    $StorageController = New-HPOVServerProfileLogicalDiskController -ControllerID Embedded -Mode RAID -Initialize -LogicalDisk $LogicalDisk

    $params = @{
        Affinity                 = "Bay";
        BootMode                 = "BIOS";
        BootOrder                = "HardDisk";
        Connections              = $Eth1, $Eth2, $Deploy1, $Deploy2;
        Description              = "Server Profile Template for HPE Synergy 480 Gen9 Compute Module with Local Boot for RHEL";
        EnclosureGroup           = $EnclGroup;
        Firmware                 = $False;
        FirmwareMode             = "FirmwareOffline";
        HideUnusedFlexNics       = $True;
        LocalStorage             = $True;
        HostOStype               = "RHEL";
        ManageBoot               = $True;
        Name                     = "HPE Synergy 480 Gen9 with Local Boot for RHEL Template";
        SANStorage               = $False;
        ServerHardwareType       = $SHT;
        ServerProfileDescription = "Server Profile for HPE Synergy 480 Gen9 Compute Module with Local Boot for RHEL";
        StorageController        = $StorageController;
        StorageVolume            = $LogicalDisk
    }

    New-HPOVServerProfileTemplate @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen9 with Local Boot for RHEL Server Profile Template Created" | Timestamp
}


function Create_Server_Profile_SY480_Gen9_RHEL_Local_Boot
{
    Write-Output "Creating SY480 Gen9 Local Boot for RHEL Server Profile" | Timestamp

    $SHT            = Get-HPOVServerHardwareTypes -Name "SY 480 Gen9 1" -ErrorAction Stop
    $Template       = Get-HPOVServerProfileTemplate -Name "HPE Synergy 480 Gen9 with Local Boot for RHEL Template" -ErrorAction Stop
    $Server         = Get-HPOVServer -ServerHardwareType $SHT -NoProfile -ErrorAction Stop | Select-Object -First 1

    $params = @{
        AssignmentType        = "Server";
        Description           = "HPE Synergy 480 Gen9 Server with Local Boot for RHEL";
        Name                  = "SY480-Gen9-RHEL-Local-Boot";
        Server                = $Server;
        ServerProfileTemplate = $Template
    }

    New-HPOVServerProfile @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen9 Local Boot for RHEL Server Profile Created" | Timestamp
}


function Create_Server_Profile_Template_SY660_Gen9_Windows_SAN_Storage
{
    Write-Output "Creating SY660 Gen9 with Local Boot and SAN Storage for Windows Server Profile Template" | Timestamp

    $SHT               = Get-HPOVServerHardwareTypes -Name "SY 660 Gen9 1" -ErrorAction Stop
    $EnclGroup         = Get-HPOVEnclosureGroup -Name "EG-Synergy-Local" -ErrorAction Stop
    $Eth1              = Get-HPOVNetwork -Name "Prod_1101" | New-HPOVServerProfileConnection -ConnectionID 1 -Name 'Prod-1101' -PortId "Mezz 3:1-c"
    $Eth2              = Get-HPOVNetwork -Name "Prod_1102" | New-HPOVServerProfileConnection -ConnectionID 2 -Name 'Prod-1102' -PortId "Mezz 3:2-c"
    $FC1               = Get-HPOVNetwork -Name 'SAN A FC' | New-HPOVServerProfileConnection -connectionId 3
    $FC2               = Get-HPOVNetwork -Name 'SAN B FC' | New-HPOVServerProfileConnection -connectionId 4
    $LogicalDisk       = New-HPOVServerProfileLogicalDisk -Name "SAS RAID5 SSD" -RAID RAID5 -NumberofDrives 3 -DriveType SASSSD -Bootable $True
    $SANVol            = Get-HPOVStorageVolume -Name "Shared-Volume-2" | New-HPOVProfileAttachVolume -LunIdType Manual -LunID 0
    $StorageController = New-HPOVServerProfileLogicalDiskController -ControllerID Embedded -Mode RAID -Initialize -LogicalDisk $LogicalDisk

    $params = @{
        Affinity                 = "Bay";
        BootMode                 = "BIOS";
        BootOrder                = "HardDisk";
        Connections              = $Eth1, $Eth2, $FC1, $FC2;
        Description              = "Server Profile Template for HPE Synergy 660 Gen9 Compute Module with Local Boot and SAN Storage for Windows";
        EnclosureGroup           = $EnclGroup;
        Firmware                 = $False;
        FirmwareMode             = "FirmwareOffline";
        HideUnusedFlexNics       = $True;
        LocalStorage             = $True;
        HostOStype               = "Win2k12";
        ManageBoot               = $True;
        Name                     = "HPE Synergy 660 Gen9 with Local Boot and SAN Storage for Windows Template";
        SANStorage               = $True;
        ServerHardwareType       = $SHT;
        ServerProfileDescription = "Server Profile for HPE Synergy 660 Gen9 Compute Module with Local Boot and SAN Storage for Windows";
        StorageController        = $StorageController;
        StorageVolume            = $SANVol
    }

    New-HPOVServerProfileTemplate @params | Wait-HPOVTaskComplete
    Write-Output "SY660 Gen9 with Local Boot and SAN Storage for Windows Server Profile Template Created" | Timestamp
}


function Create_Server_Profile_SY660_Gen9_Windows_SAN_Storage
{
    Write-Output "Creating SY660 Gen9 with Local Boot and SAN Storage for Windows Server Profile" | Timestamp

    $SHT            = Get-HPOVServerHardwareTypes -Name "SY 660 Gen9 1" -ErrorAction Stop
    $Template       = Get-HPOVServerProfileTemplate -Name "HPE Synergy 660 Gen9 with Local Boot and SAN Storage for Windows Template" -ErrorAction Stop
    $Server         = Get-HPOVServer -ServerHardwareType $SHT -NoProfile -ErrorAction Stop | Select-Object -First 1

    $params = @{
        AssignmentType        = "Server";
        Description           = "HPE Synergy 660 Gen9 Server with Local Boot and SAN Storage for Windows";
        Name                  = "SY660-Gen9-Windows-Local-Boot-and-SAN-Storage";
        Server                = $Server;
        ServerProfileTemplate = $Template
    }

    New-HPOVServerProfile @params | Wait-HPOVTaskComplete
    Write-Output "SY660 Gen9 with Local Boot and SAN Storage for Windows Server Profile Created" | Timestamp
}


function Create_Server_Profile_Template_SY480_Gen9_ESX_SAN_Boot
{
    Write-Output "Creating SY480 Gen9 with SAN Boot for ESX Server Profile Template" | Timestamp

    $SHT               = Get-HPOVServerHardwareTypes -Name "SY 480 Gen9 2" -ErrorAction Stop
    $EnclGroup         = Get-HPOVEnclosureGroup -Name "EG-Synergy-Local" -ErrorAction Stop
    $Eth1              = Get-HPOVNetwork -Name "Prod_1101" | New-HPOVServerProfileConnection -ConnectionID 1 -Name 'Prod-1101' -PortId "Mezz 3:1-c"
    $Eth2              = Get-HPOVNetwork -Name "Prod_1102" | New-HPOVServerProfileConnection -ConnectionID 2 -Name 'Prod-1102' -PortId "Mezz 3:2-c"
    $FC1               = Get-HPOVNetwork -Name 'SAN A FC' | New-HPOVServerProfileConnection -ConnectionID 3 -Bootable -Priority Primary -BootVolumeSource ManagedVolume -ConnectionType FibreChannel
    $FC2               = Get-HPOVNetwork -Name 'SAN B FC' | New-HPOVServerProfileConnection -ConnectionID 4 -Bootable -Priority Secondary -BootVolumeSource ManagedVolume -ConnectionType FibreChannel
    $StoragePool       = Get-HPOVStoragePool -Name FST_CPG1 -StorageSystem ThreePAR-1 -ErrorAction Stop
    $SANVol            = New-HPOVServerProfileAttachVolume -Name BootVol -StoragePool $StoragePool -BootVolume -Capacity 100 -LunIdType Auto

    $params = @{
        Affinity                 = "Bay";
        BootMode                 = "BIOS";
        BootOrder                = "HardDisk";
        Connections              = $Eth1, $Eth2, $FC1, $FC2;
        Description              = "Server Profile Template for HPE Synergy 480 Gen9 Compute Module with SAN Boot for ESX";
        EnclosureGroup           = $EnclGroup;
        Firmware                 = $False;
        FirmwareMode             = "FirmwareOffline";
        HideUnusedFlexNics       = $True;
        LocalStorage             = $True;
        HostOStype               = "VMware";
        ManageBoot               = $True;
        Name                     = "HPE Synergy 480 Gen9 with SAN Boot for ESX Template";
        SANStorage               = $True;
        ServerHardwareType       = $SHT;
        ServerProfileDescription = "Server Profile for HPE Synergy 480 Gen9 Compute Module with SAN Boot for ESX";
        StorageVolume            = $SANVol
    }

    New-HPOVServerProfileTemplate @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen9 with SAN Boot for ESX Server Profile Template Created" | Timestamp
}


function Create_Server_Profile_SY480_Gen9_ESX_SAN_Boot
{
    Write-Output "Creating SY480 Gen9 SAN Boot for ESX Server Profile" | Timestamp

    $SHT            = Get-HPOVServerHardwareTypes -Name "SY 480 Gen9 2" -ErrorAction Stop
    $Template       = Get-HPOVServerProfileTemplate -Name "HPE Synergy 480 Gen9 with SAN Boot for ESX Template" -ErrorAction Stop
    $Server         = Get-HPOVServer -ServerHardwareType $SHT -NoProfile -ErrorAction Stop | Select-Object -First 1

    $params = @{
        AssignmentType        = "Server";
        Description           = "HPE Synergy 480 Gen9 Server with SAN Boot for ESX";
        Name                  = "SY480-Gen9-ESX-SAN-Boot";
        Server                = $Server;
        ServerProfileTemplate = $Template
    }

    New-HPOVServerProfile @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen9 with SAN Boot for ESX Server Profile Created" | Timestamp
}


function Create_Server_Profile_Template_SY480_Gen10_ESX_SAN_Boot
{
    Write-Output "Creating SY480 Gen10 with SAN Boot for ESX Server Profile Template" | Timestamp

    $SHT               = Get-HPOVServerHardwareTypes -Name "SY 480 Gen10 1" -ErrorAction Stop
    $EnclGroup         = Get-HPOVEnclosureGroup -Name "EG-Synergy-Local" -ErrorAction Stop
    $Eth1              = Get-HPOVNetwork -Name "Prod_1101" | New-HPOVServerProfileConnection -ConnectionID 1 -Name 'Prod-1101' -PortId "Mezz 3:1-c"
    $Eth2              = Get-HPOVNetwork -Name "Prod_1102" | New-HPOVServerProfileConnection -ConnectionID 2 -Name 'Prod-1102' -PortId "Mezz 3:2-c"
    $FC1               = Get-HPOVNetwork -Name 'SAN A FC' | New-HPOVServerProfileConnection -ConnectionID 3 -Bootable -Priority Primary -BootVolumeSource ManagedVolume -ConnectionType FibreChannel
    $FC2               = Get-HPOVNetwork -Name 'SAN B FC' | New-HPOVServerProfileConnection -ConnectionID 4 -Bootable -Priority Secondary -BootVolumeSource ManagedVolume -ConnectionType FibreChannel
    $StoragePool       = Get-HPOVStoragePool -Name FST_CPG1 -StorageSystem ThreePAR-2 -ErrorAction Stop
    $SANVol            = New-HPOVServerProfileAttachVolume -Name BootVol-Gen10 -StoragePool $StoragePool -BootVolume -Capacity 100 -LunIdType Auto

    #
    # Check if firmware bundles are installed.  If there are, select the last one
    # and modify the firmware-related variables in the Server Profile Template
    #
    $FW = Get-HPOVBaseline | Measure-Object
    if ($FW.Count -ge 1) {
        $FWBaseline = Get-HPOVBaseline | Select-Object -Last 1
        $params = @{
            Affinity                 = "Bay";
            Baseline                 = $FWBaseline;
            BootMode                 = "BIOS";
            BootOrder                = "HardDisk";
            Connections              = $Eth1, $Eth2, $FC1, $FC2;
            Description              = "Server Profile Template for HPE Synergy 480 Gen10 Compute Module with SAN Boot for ESX";
            EnclosureGroup           = $EnclGroup;
            Firmware                 = $True;
            FirmwareMode             = "FirmwareOffline";
            HideUnusedFlexNics       = $True;
            LocalStorage             = $True;
            HostOStype               = "VMware";
            ManageBoot               = $True;
            Name                     = "HPE Synergy 480 Gen10 with SAN Boot for ESX Template";
            SANStorage               = $True;
            ServerHardwareType       = $SHT;
            ServerProfileDescription = "Server Profile for HPE Synergy 480 Gen10 Compute Module with SAN Boot for ESX";
            StorageVolume            = $SANVol
        }
    } else {
        $params = @{
            Affinity                 = "Bay";
            BootMode                 = "BIOS";
            BootOrder                = "HardDisk";
            Connections              = $Eth1, $Eth2, $FC1, $FC2;
            Description              = "Server Profile Template for HPE Synergy 480 Gen10 Compute Module with SAN Boot for ESX";
            EnclosureGroup           = $EnclGroup;
            Firmware                 = $False;
            HideUnusedFlexNics       = $True;
            LocalStorage             = $True;
            HostOStype               = "VMware";
            ManageBoot               = $True;
            Name                     = "HPE Synergy 480 Gen10 with SAN Boot for ESX Template";
            SANStorage               = $True;
            ServerHardwareType       = $SHT;
            ServerProfileDescription = "Server Profile for HPE Synergy 480 Gen10 Compute Module with SAN Boot for ESX";
            StorageVolume            = $SANVol
        }
    }

    New-HPOVServerProfileTemplate @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen10 with SAN Boot for ESX Server Profile Template Created" | Timestamp
}


function Create_Server_Profile_SY480_Gen10_ESX_SAN_Boot
{
    Write-Output "Creating SY480 Gen10 SAN Boot for ESX Server Profile" | Timestamp

    $SHT            = Get-HPOVServerHardwareTypes -Name "SY 480 Gen10 1" -ErrorAction Stop
    $Template       = Get-HPOVServerProfileTemplate -Name "HPE Synergy 480 Gen10 with SAN Boot for ESX Template" -ErrorAction Stop
    $Server         = Get-HPOVServer -ServerHardwareType $SHT -NoProfile -ErrorAction Stop | Select-Object -First 1

    $params = @{
        AssignmentType        = "Server";
        Description           = "HPE Synergy 480 Gen10 Server with SAN Boot for ESX";
        Name                  = "SY480-Gen10-ESX-SAN-Boot";
        Server                = $Server;
        ServerProfileTemplate = $Template
    }

    New-HPOVServerProfile @params | Wait-HPOVTaskComplete
    Write-Output "SY480 Gen10 with SAN Boot for ESX Server Profile Created" | Timestamp
}


function Add_Users
{
    Write-Output "Adding New Users" | Timestamp

    New-HPOVUser -UserName BackupAdmin -FullName "Backup Administrator" -Password BackupPasswd -Roles "Backup Administrator" -EmailAddress "backup@hpe.com" -OfficePhone "(111) 111-1111" -MobilePhone "(999) 999-9999"
    New-HPOVUser -UserName NetworkAdmin -FullName "Network Administrator" -Password NetworkPasswd -Roles "Network Administrator" -EmailAddress "network@hpe.com" -OfficePhone "(222) 222-2222" -MobilePhone "(888) 888-8888"
    New-HPOVUser -UserName ServerAdmin -FullName "Server Administrator" -Password ServerPasswd -Roles "Server Administrator" -EmailAddress "server@hpe.com" -OfficePhone "(333) 333-3333" -MobilePhone "(777) 777-7777"
    New-HPOVUser -UserName StorageAdmin -FullName "Storage Administrator" -Password StoragePasswd -Roles "Storage Administrator" -EmailAddress "storage@hpe.com" -OfficePhone "(444) 444-4444" -MobilePhone "(666) 666-6666"
    New-HPOVUser -UserName SoftwareAdmin -FullName "Software Administrator" -Password SoftwarePasswd -Roles "Software Administrator" -EmailAddress "software@hpe.com" -OfficePhone "(555) 555-5555" -MobilePhone "(123) 234-3456"

    Write-Output "All New Users Added" | Timestamp
}


function Add_Scopes
{
    Write-Output "Adding New Scopes" | Timestamp

    New-HPOVScope -Name FinanceScope -Description "Finance Scope of Resources"
    $Resources += Get-HPOVNetwork -Name Prod*
    $Resources += Get-HPOVEnclosure -Name Synergy-Encl-1
    Get-HPOVScope -Name FinanceScope | Add-HPOVResourceToScope -InputObject $Resources

    Write-Output "All New Scopes Added" | Timestamp
}


##############################################################################
#
# Main Program
#
##############################################################################

#
# Unload any earlier versions of the HPOneView POSH modules
#
Remove-Module -ErrorAction SilentlyContinue HPOneView.120
Remove-Module -ErrorAction SilentlyContinue HPOneView.200
Remove-Module -ErrorAction SilentlyContinue HPOneView.300
Remove-Module -ErrorAction SilentlyContinue HPOneView.310
Remove-Module -ErrorAction SilentlyContinue HPOneView.400

if (-not (get-module HPOneview.410))
{
    Import-Module -Name HPOneView.410
}

if (-not $ConnectedSessions)
{
	$Appliance = Read-Host 'ApplianceName'
	$Username  = Read-Host 'Username'
	$Password  = Read-Host 'Password' -AsSecureString

    Connect-HPOVMgmt -Hostname $Appliance -Username $Username -Password $Password

    if (-not $ConnectedSessions)
    {
        Write-Output "Login to Synergy Appliance failed.  Exiting."
        Exit
    }
    else {
        Import-HPOVSslCertificate
    }
}

filter Timestamp {"$(Get-Date -Format G): $_"}


##########################################################################
#
# Process variables in the Populate_HPE_Synergy-Params.txt file.
#
##########################################################################
New-Variable -Name config_file -Value .\Populate_HPE_Synergy-Params-DCS.txt -Scope Global -Force

#
# Remove blank lines and comments from the Params file
#
if (Test-Path $config_file) {
    Get-Content $config_file | Where-Object { $_ -and !$_.StartsWith("#") } | Foreach-Object {
        $var = $_.Split('=')
        New-Variable -Name $var[0].Trim() -Value $var[1].Trim() -Scope Global -Force
    }
} else {
    Write-Output "Configuration file '$config_file' not found.  Exiting." | Timestamp
    Exit
}


Write-Output "Configuring HPE Synergy Appliance" | Timestamp

#Add_Firmware_Bundle
#Add_Licenses
#Configure_Time_and_Locale
#Configure_SMTP
#Configure_Address_Pools
#Disable_VSN_Address_Pools

#*** Not Working
#Add_Remote_Enclosures
#***

#Rename_Enclosures
#PowerOff_All_Servers
#Configure_SAN_Managers
#Configure_Networks_Pools
#Configure_Ethernet_Networks
#Configure_FC_Networks
#Configure_FCoE_Networks
#Configure_Network_Sets
#Configure_3PAR_Storage
#Configure_StoreVirtual_Storage

### Working up to Here
Add_Users

#Create_OS_Deployment_Server
#Create_Logical_Interconnect_Groups
#Create_Uplink_Sets
#Create_Enclosure_Group
#Create_Logical_Enclosure
#Add_Scopes
#Create_Server_Profile_Template_SY480_Gen9_RHEL_Local_Boot
#Create_Server_Profile_Template_SY660_Gen9_Windows_SAN_Storage
#Create_Server_Profile_Template_SY480_Gen9_ESX_SAN_Boot
#Create_Server_Profile_Template_SY480_Gen10_ESX_SAN_Boot
#Create_Server_Profile_SY480_Gen9_RHEL_Local_Boot
#Create_Server_Profile_SY660_Gen9_Windows_SAN_Storage
#Create_Server_Profile_SY480_Gen9_ESX_SAN_Boot
#Create_Server_Profile_SY480_Gen10_ESX_SAN_Boot

#
# Add Second Enclosure Group for Remote Enclosures
#
#Create_Logical_Interconnect_Groups_Remote
#Create_Enclosure_Group_Remote
#Create_Logical_Enclosure_Remote

Write-Output "HPE Synergy Appliance Configuration Complete" | Timestamp
