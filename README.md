EVC-Helper-Script
=================

EVC Helper Script as blogged on https://blogs.vmware.com/PowerCLI/2014/03/evc-powercli-5-5-r2part-2.html

Detect what is the maximum EVC mode that can be set on an existing cluster

This is helpful when you want to determine your cluster EVC readiness depending on the EVC capabilities of the hosts in that cluster.

Function name: Get-MaxEVCModeKey
Returns the maximum EVC mode that is supported by all of the specified VM hosts
Usage:

$VMHosts = Get-VMHost -Location ‘MyCluster’

Get-MaxEVCModeKey $VMHosts

Select a group of hosts with common EVC capability

This is applicable in two different scenarios:

· To identify compatible hosts that can be added to an EVC enabled cluster

· To identify hosts that are incompatible with a given EVC mode and prevent the cluster from running in that EVC mode

Function name: Get-VMHostByEVCCompatibility

Returns all VM hosts from the specified list that match the specified EVC compatibility criteria

Usage:

$VMHosts = Get-VMHost -Location ‘MyCluster’

Get-VMHostByEVCCompatibility $VMHosts -EvcModeKey ‘intel-westmere’ -IncompatibleVMHosts

$VMHosts = Get-VMHost -Location ‘MyCluster’

Get-VMHostByEVCCompatibility $VMHosts -EvcModeKey ‘intel-westmere’ -CompatibleVMHosts

Check host’s compatibility with a particular EVC mode

Function name: CheckVMHostEVCCompatibility
Checks whether the specified VM host is compatible with the specified EVC mode

List available EVC modes

Function name:GetAvailableEVCModeKeys
Retrieves the keys of all EVC modes that are supported by the specified vCenter Server


