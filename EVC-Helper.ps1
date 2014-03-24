<# 
.SYNOPSIS
  Contains functions that facilitate the selection of VM hosts and target EVC mode for a cluster

.NOTES
  This scripts uses the $global:DefaultVIServers variable to retrieve the list with connected VIServers
  This scripts assumes that you have connected to one or more vCenter servers (no direct ESX connections!).   
  
.EXAMPLE
  # Determine the maximum EVC mode that is supported by all VM hosts in a cluster
 
  $vmHosts = Get-VMHost -Location (Get-Cluster cluster)
  Get-MaxEVCModeKey $vmHosts

.EXAMPLE
  # Identify which hosts in a cluster don't have a specific EVC capability 
  # (and thus prevent the cluster from using this EVC mode)

  $vmHosts = Get-VMHost -Location (Get-Cluster cluster)
  Get-VMHostByEVCCompatibility $vmHosts -EvcModeKey 'intel-westmere' -IncompatibleVMHosts

.EXAMPLE
  # Select candidate VM hosts for adding to a cluster with already enabled EVC

  $cluster = Get-Cluster 'Cluster'
  $vmHosts = Get-VMHost -Location 'Datacenter' -Tag 'MyTag'
  Get-VMHostByEVCCompatibility $vmHosts -EvcModeKey $cluster.EVCMode -CompatibleVMHosts
#>


Function Get-MaxEVCModeKey
{   
   <#
      .SYNOPSIS 
      Returns the maximum EVC mode that is supported by all of the specified VM hosts
     
      .PARAMETER VMHost
      Specifies the the VM hosts for which you want to retrieve the maximum EVC mode. All VM hosts must belong to the same vCenter Server.
     
      .OUTPUTS
      System.String. The Key of the maximum EVC mode that is supported by all of the specified VM hosts
      If no VM hosts are the specified or there is no applicable EVC mode for the group of VM hosts, the result is $null.
     
      .EXAMPLE
      $VMHosts = Get-VMHost -Location 'MyCluster'
      Get-MaxEVCModeKey $VMHosts
   #>

   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, Position=0)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$VMHost
   )   

   $server = GetServerFromVIObject -viObject $VMHost[0]
   $maxEvcMode = $null

   foreach($currentVMHost in $VMHost)
   {      
      # Retrieve the EVC mode by key
      $vmHostMaxEvcMode = GetEVCMode -vcServer $server -evcModeKey $currentVMHost.MaxEVCMode
      
      if (!$vmHostMaxEvcMode)
      {
         return $null
      }

      if(!$maxEvcMode)
      {           
         $maxEvcMode = $vmHostMaxEvcMode
      }
      else
      {  
         # If the cluster contains VM hosts with CPUs from different vendors, EVC cannot be used
         if ($vmHostMaxEvcMode.Vendor -ne $maxEvcMode.Vendor)
         {
            return $null
         }
         elseif($vmHostMaxEvcMode.VendorTier -lt $maxEvcMode.VendorTier)
         {
             $maxEvcMode = $vmHostMaxEvcMode
         }         
      }
   }   

   return $maxEvcMode.Key
}

Function Get-VMHostByEVCCompatibility
{  
   <#
      .SYNOPSIS 
      Returns all VM hosts from the specified list that match the specified EVC compatibility criteria
     
      .PARAMETER VMHost
      Specifies the VM hosts which you want to filter by EVC mode. All VM hosts must belong to the same vCenter Server.
     
      .PARAMETER EvcModeKey
      Specifies the key of the EVC mode to use as filter.
      You can list all EVC mode keys available on a vCenter Server using GetAvailableEVCModeKeys.
     
      .OUTPUTS
      One or more VMHost objects that satisfy the specified criteria
     
      .EXAMPLE
      $VMHosts = Get-VMHost -Location 'MyCluster'
      Get-VMHostByEVCCompatibility $VMHosts -EvcModeKey 'intel-merom' -IncompatibleVMHosts
   #>

   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, Position=0)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$VMHost,
	
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [string]$EvcModeKey,

      [Parameter(ParameterSetName='Incompatible', Mandatory=$True)]
      [switch]$IncompatibleVMHosts,

      [Parameter(ParameterSetName='Compatible', Mandatory=$True)]
      [switch]$CompatibleVMHosts
   )        
   
   $server = GetServerFromVIObject -viObject $VMHost[0]
   
   # Validate the EVC mode key, specified by the user
   $evcMode = GetEVCMode -vcServer $server -evcModeKey $EvcModeKey
   if (!$evcMode)
   {
      return
   }
   
   # It is enough to only check the $IncompatibleVMHosts switch  since we can't have both switch parameters specified at the same time.
   $compatibilityTestCondition = !$IncompatibleVMHosts
     
   return $VMHost | ?{(CheckVMHostEVCCompatibility -VMHost $_ -EvcModeKey $EvcModeKey) -eq $compatibilityTestCondition}     
}

Function CheckVMHostEVCCompatibility
{
    <#
      .SYNOPSIS 
      Checks whether the specified VM host is compatible with the specified EVC mode
     
      .PARAMETER VMHost
      Specifies the VM host which you want to check for compatibility with a specified EVC mode.
     
      .PARAMETER EvcModeKey
      Specifies the key of the EVC mode that you want to use for compatibility check.
      You can list all EVC mode keys available on a vCenter Server using GetAvailableEVCModeKeys.
     
      .OUTPUTS
      System.Boolean
     
      .EXAMPLE
      Get-VMHost 'MyVMHost' | CheckVMHostEVCCompatibility -EVCModeKey 'intel-merom'
   #>
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, ValueFromPipeline=$True, Position=0)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost,
	
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [string]$EVCModeKey
   )
      
   $server = GetServerFromVIObject -viObject $VMHost
   $hostMaxEvcMode = GetEVCMode -vcServer $server -evcMode $VMHost.MaxEVCMode
   $targetEvcMode = GetEVCMode -vcServer $server -evcMode $EVCModeKey   

   if ($targetEvcMode -and $hostMaxEvcMode)
   {
      return ($targetEvcMode.Vendor -eq $hostMaxEvcMode.Vendor) -and ($targetEvcMode.VendorTier -le $hostMaxEvcMode.VendorTier)   
   }   
}

#region Helper Functions

Function GetAvailableEVCModeKeys
{
   <#
      .SYNOPSIS 
      Retrieves all EVC mode keys that are supported by the specified vCenter Server.
      The supported EVC modes vary by vCenter Server version.
   #>
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.ViCore.Types.V1.VIServer]$vcServer)
   
   return $vcServer.ExtensionData.Capability.SupportedEVCMode | select -ExpandProperty 'Key'
}

Function GetEVCMode
{
   <#
      .SYNOPSIS 
      Retrieves the full EVC mode object for the specified EVC mode key 
   #>
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.ViCore.Types.V1.VIServer]$vcServer,


      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [string]$evcModeKey	
   )

   $availableEVCModes = $server.ExtensionData.Capability.SupportedEVCMode
   $evcMode = $availableEVCModes | ?{$_.Key -eq $evcModeKey}

   if($evcMode -ne $null)
   {
      return $evcMode
   }
   else
   {  
      $allEVCModeKeysFormated = [String]::Join(", ", (GetAvailableEVCModeKeys -vcServer $server))
      $errorMessage = "$evcModeKey is either not a valid EVC mode or not supported by this vCenter Server instance. " + 
                      "The available EVC modes are: $allEVCModeKeysFormated"
      
      ThrowInvalidArgumentError -message $errorMessage -target $evcModeKey            
   }
}

Function GetServerFromVIObject
{
   <#
      .SYNOPSIS 
      Retrieves the VIServer to which the specified VIObject belongs 
   #>
    Param(
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [VMware.VimAutomation.Sdk.Types.V1.VIObject]$viObject)

   $viObjectUid = $UidUtil.GetConnectionUid($viObject.Uid)
   return $global:DefaultVIServers | ?{$_.Uid -eq $viObjectUid}
}

function ThrowInvalidArgumentError
{
   <#
      .SYNOPSIS 
      Helper method for throwing an InvalidArgumentError terminating error
   #>
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [string]$message,

      [Parameter(Mandatory=$True)]
      [ValidateNotNullOrEmpty()]
      [System.Object]$target      
   )

   $exception = New-Object ArgumentException $message
   $errorId = 'Invalid_EVC_Mode_Specified'
   $errorCategory = [Management.Automation.ErrorCategory]::InvalidArgument
   $errorRecord = New-Object Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $target
   $PSCmdlet.ThrowTerminatingError($errorRecord)
}

#endregion
