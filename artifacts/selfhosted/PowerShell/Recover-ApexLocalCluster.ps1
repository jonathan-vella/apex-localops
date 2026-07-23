#requires -Version 5.1
<#
.SYNOPSIS
  Revalidate and retry only the Azure Local cloud deployment.
.DESCRIPTION
  Runs on the existing cluster host through Azure Managed Run Command after all
  three nested nodes have reached Connected in Azure Arc. The reused lab password
  arrives as an encrypted protected parameter and is cleared before exit.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingConvertToSecureStringWithPlainText',
  '',
  Justification = 'Azure Managed Run Command supplies the lab password as an encrypted protected parameter; recovery converts it only in memory and clears it before exit.'
)]
param(
  [Parameter(Mandatory)] [string]$AdminPassword,
  [ValidateSet('ValidateDeploy', 'DeployOnly')] [string]$Mode = 'ValidateDeploy'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
$buildMutex = New-Object System.Threading.Mutex($false, 'Global\ApexLocalBuild')
$lockAcquired = $false
$recoveryFailed = $false

try {
  $lockAcquired = $buildMutex.WaitOne(0)
  if (-not $lockAcquired) {
    throw 'The main build or another recovery process is already running.'
  }

  New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  Start-Transcript -Path (Join-Path $logsDir "Recovery-$stamp.log") -Force

  Import-Module (Join-Path $rootDir 'ApexLocalOps\ApexLocalOps.psd1') -Force
  $config = Get-ApexConfig -ConfigPath (Join-Path $rootDir 'ApexLocal-Config.psd1')
  $resourceGroup = [Environment]::GetEnvironmentVariable('APEX_ResourceGroup', 'Machine')
  $subscriptionId = [Environment]::GetEnvironmentVariable('APEX_SubscriptionId', 'Machine')
  $clusterName = [Environment]::GetEnvironmentVariable('APEX_ClusterName', 'Machine')
  $instanceLocation = [Environment]::GetEnvironmentVariable('APEX_InstanceLocation', 'Machine')
  $hciRpObjectId = [Environment]::GetEnvironmentVariable('APEX_HciRpObjectId', 'Machine')
  $adminUsername = [Environment]::GetEnvironmentVariable('APEX_AdminUsername', 'Machine')
  $storageAccount = [Environment]::GetEnvironmentVariable('APEX_StagingStorageAccount', 'Machine')
  $logsContainer = [Environment]::GetEnvironmentVariable('APEX_LogsContainer', 'Machine')

  foreach ($requiredValue in @(
      $resourceGroup, $subscriptionId, $clusterName, $instanceLocation,
      $hciRpObjectId, $adminUsername, $storageAccount, $logsContainer
    )) {
    if ([string]::IsNullOrWhiteSpace($requiredValue)) {
      throw 'Required self-hosted deployment context is missing from the host.'
    }
  }

  $securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
  $localCredential = New-Object System.Management.Automation.PSCredential($adminUsername, $securePassword)
  $domainCredential = New-Object System.Management.Automation.PSCredential(
    "$($config.Domain.NetBiosName)\Administrator",
    $securePassword
  )
  $lcmCredential = New-Object System.Management.Automation.PSCredential(
    "$($config.Domain.NetBiosName)\$($config.Domain.LcmUserName)",
    $securePassword
  )

  Connect-ApexAzure -SubscriptionId $subscriptionId | Out-Null
  $nodes = @()
  $startParts = $config.Cluster.NodeStartIp.Split('.')
  for ($index = 1; $index -le $config.Cluster.NodeCount; $index++) {
    $nodeName = "$($config.Cluster.NamePrefix)$index"
    $nodeIp = '{0}.{1}.{2}.{3}' -f $startParts[0], $startParts[1], $startParts[2],
      ([int]$startParts[3] + ($index - 1))
    $vm = Get-VM -Name $nodeName -ErrorAction Stop
    if ($vm.State -ne 'Running') { throw "Nested node '$nodeName' is not running." }
    Wait-ApexVMReady -VmName $nodeName -Credential $localCredential -TimeoutMinutes 5 | Out-Null
    $nodes += [pscustomobject]@{ Name = $nodeName; IpAddress = $nodeIp }
  }

  Invoke-Command -VMName $config.Domain.DcHostName -Credential $domainCredential -ScriptBlock {
    param($fqdn, $lcmUserName)
    Import-Module ActiveDirectory -ErrorAction Stop
    $null = Get-ADDomain -Identity $fqdn -ErrorAction Stop
    $null = Get-ADUser -Identity $lcmUserName -ErrorAction Stop
  } -ArgumentList $config.Domain.Fqdn, $config.Domain.LcmUserName

  $arcIds = @()
  foreach ($node in $nodes) {
    $arcMachine = Get-AzResource -ResourceGroupName $resourceGroup `
      -ResourceType 'Microsoft.HybridCompute/machines' -Name $node.Name `
      -ExpandProperties -ErrorAction Stop
    if ($arcMachine.Properties.status -ne 'Connected') {
      throw "Arc machine '$($node.Name)' is not Connected."
    }
    $arcIds += $arcMachine.ResourceId
  }
  if (@($arcIds | Select-Object -Unique).Count -ne 3) {
    throw 'Recovery requires exactly three unique Connected Arc machines.'
  }

  Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'RecoveryValidating' `
    -Status "Cluster-only recovery mode: $Mode" -Config $config
  if ($Mode -eq 'ValidateDeploy') {
    Test-ApexEnvironmentReadiness -Config $config -SubscriptionId $subscriptionId `
      -ResourceGroup $resourceGroup -ClusterName $clusterName -Nodes $nodes `
      -LocalAdminCredential $localCredential -DomainAdminCredential $domainCredential
  }

  Start-ApexLocalClusterDeployment -Config $config -ResourceGroup $resourceGroup `
    -ClusterName $clusterName -InstanceLocation $instanceLocation `
    -HciResourceProviderObjectId $hciRpObjectId -ArcNodeResourceIds $arcIds `
    -Nodes $nodes -LocalAdminCredential $localCredential -DomainAdminCredential $lcmCredential `
    -TemplatePath (Join-Path $rootDir 'azlocal.json') -SkipValidation:($Mode -eq 'DeployOnly')

  Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'Completed' `
    -Status "Cluster $clusterName recovery succeeded" -Config $config
  Write-ApexLog "Cluster-only recovery completed in mode '$Mode'."
}
catch {
  $recoveryFailed = $true
  if (Get-Command Write-ApexLog -ErrorAction SilentlyContinue) {
    Write-ApexLog "RECOVERY FAILED: $($_.Exception.Message)" -Level ERROR
  }
  if ($resourceGroup -and $config) {
    Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'Failed' `
      -Status "Recovery: $($_.Exception.Message)" -Config $config
  }
}
finally {
  $AdminPassword = $null
  Clear-Variable -Name securePassword, localCredential, domainCredential, lcmCredential -ErrorAction SilentlyContinue
  if ($storageAccount -and $logsContainer -and (Get-Command Send-ApexLogsToStorage -ErrorAction SilentlyContinue)) {
    Send-ApexLogsToStorage -StorageAccountName $storageAccount -Container $logsContainer
  }
  try { Stop-Transcript } catch { }
  if ($lockAcquired) { $buildMutex.ReleaseMutex() }
  $buildMutex.Dispose()
}

if ($recoveryFailed) { exit 1 }
