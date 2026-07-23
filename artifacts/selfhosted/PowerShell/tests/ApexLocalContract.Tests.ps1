#requires -Version 7.4
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.1' }

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
  $configPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1'
  $modulePath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1'
  $mainBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/main.bicep'
  $hostBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/host/host.bicep'
  $managementBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/mgmt/mgmtVm.bicep'
  $storageBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/mgmt/stagingStorage.bicep'
  $monitoringBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/mgmt/hostMonitoring.bicep'
  $networkBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/network/network.bicep'
  $clusterTemplatePath = Join-Path $repoRoot 'artifacts/selfhosted/azlocal.json'
  $orchestratorPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/New-ApexLocalCluster.ps1'
  $isoPublisherPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Upload-Isos.ps1'
  $bootstrapPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Bootstrap.ps1'
  $jumpboxSetupPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Setup-Jumpbox.ps1'
  $recoveryPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Recover-ApexLocalCluster.ps1'
  $recoveryWrapperPath = Join-Path $repoRoot 'scripts/recover-selfhosted.sh'
  $deployWrapperPath = Join-Path $repoRoot 'scripts/deploy-selfhosted.sh'
  $providerCheckPath = Join-Path $repoRoot 'scripts/check-providers-selfhosted.sh'

  $config = Import-PowerShellDataFile -Path $configPath
  $moduleSource = Get-Content -Path $modulePath -Raw
  $mainBicepSource = Get-Content -Path $mainBicepPath -Raw
  $hostBicepSource = Get-Content -Path $hostBicepPath -Raw
  $managementBicepSource = Get-Content -Path $managementBicepPath -Raw
  $storageBicepSource = Get-Content -Path $storageBicepPath -Raw
  $monitoringBicepSource = Get-Content -Path $monitoringBicepPath -Raw
  $networkBicepSource = Get-Content -Path $networkBicepPath -Raw
  $clusterTemplateSource = Get-Content -Path $clusterTemplatePath -Raw
  $orchestratorSource = Get-Content -Path $orchestratorPath -Raw
  $isoPublisherSource = Get-Content -Path $isoPublisherPath -Raw
  $bootstrapSource = Get-Content -Path $bootstrapPath -Raw
  $jumpboxSetupSource = Get-Content -Path $jumpboxSetupPath -Raw
  $recoverySource = Get-Content -Path $recoveryPath -Raw
  $recoveryWrapperSource = Get-Content -Path $recoveryWrapperPath -Raw
  $deployWrapperSource = Get-Content -Path $deployWrapperPath -Raw
  $providerCheckSource = Get-Content -Path $providerCheckPath -Raw

  $tokens = $null
  $parseErrors = $null
  $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $modulePath,
    [ref]$tokens,
    [ref]$parseErrors
  )
  if ($parseErrors.Count -gt 0) {
    throw "Unable to parse ApexLocalOps.psm1 for contract tests."
  }

  $nodeFunction = $moduleAst.Find(
    { param($ast) $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $ast.Name -eq 'New-ApexLocalNode' },
    $true
  )
  $nodeFunctionSource = $nodeFunction.Extent.Text
  $clusterDeployFunction = $moduleAst.Find(
    { param($ast) $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $ast.Name -eq 'Start-ApexLocalClusterDeployment' },
    $true
  )
  $clusterDeployFunctionSource = $clusterDeployFunction.Extent.Text
}

Describe 'Self-hosted release topology' {
  It 'uses exactly three nodes and no witness' {
    $config.Cluster.NodeCount | Should -Be 3
    $config.Cluster.WitnessType | Should -Be 'No Witness'
  }

  It 'does not expose unsupported host or node shape parameters' {
    $mainBicepSource | Should -Not -Match '(?m)^param hostVmSize '
    $mainBicepSource | Should -Not -Match '(?m)^param clusterNodeCount '
    $mainBicepSource | Should -Not -Match '(?m)^param nodeMemoryMB '
    $mainBicepSource | Should -Not -Match '(?m)^param nodeCpuCount '
    $mainBicepSource | Should -Match "Standard_E64s_v6"
    $hostBicepSource | Should -Not -Match "Standard_E32s_v[56]|Standard_E48s_v[56]"
  }

  It 'creates four blank 170 GB S2D disks per node' {
    $config.Cluster.DataDiskCount | Should -Be 4
    $config.Cluster.DataDiskSizeGB | Should -Be 170
    $nodeFunctionSource | Should -Match 'DataDiskSizeGB'
    $nodeFunctionSource | Should -Match 'Add-VMHardDiskDrive'
    $nodeFunctionSource | Should -Match 'DataDiskCount'
  }

  It 'implements the required nested NIC contract' {
    $config.Cluster.FabricAdapter | Should -Be 'FABRIC'
    $config.Cluster.StorageAdapterA | Should -Be 'StorageA'
    $config.Cluster.StorageAdapterB | Should -Be 'StorageB'
    $nodeFunctionSource | Should -Match 'MacAddressSpoofing\s+On'
    $nodeFunctionSource | Should -Match 'AllowTeaming\s+On'
    $nodeFunctionSource | Should -Match 'Set-VMNetworkAdapterVlan[^\r\n]*-Trunk'
    $nodeFunctionSource | Should -Match 'Rename-NetAdapter'
  }
}

Describe 'Self-hosted cloud deployment contract' {
  It 'uses the current LCM password parameter spelling' {
    $clusterTemplateSource | Should -Match 'AzureStackLCMAdminPassword'
    $clusterTemplateSource | Should -Not -Match 'AzureStackLCMAdminPasssword'
    $moduleSource | Should -Match 'AzureStackLCMAdminPassword'
    $moduleSource | Should -Not -Match 'AzureStackLCMAdminPasssword'
  }

  It 'contains no cloud witness resources or key access' {
    $clusterTemplateSource | Should -Not -Match 'witnessStorageAcc|KVWitnessSecret|CloudWithnessStorageAccountIdVar|listKeys'
    $moduleSource | Should -Match "witnessType\s+=\s+'No Witness'"
    $moduleSource | Should -Not -Match 'WitnessStorageAccountName'
  }

  It 'blocks deployment until exactly three Arc machines are discovered' {
    $orchestratorSource | Should -Match 'if\s*\(\$arcIds\.Count\s+-ne\s+3\)'
    $orchestratorSource | Should -Match 'throw'
  }

  It 'cleans bootstrap secrets and exits nonzero after failure' {
    $orchestratorSource | Should -Match 'Clear-ApexBootstrapSecrets'
    $orchestratorSource | Should -Match '(?m)^\s*exit\s+1\s*$'
  }
}

Describe 'Self-hosted infrastructure ordering and access' {
  It 'uses the proven stable API for public IP resources' {
    $networkBicepSource | Should -Match 'Microsoft\.Network/publicIPAddresses@2024-10-01'
    $networkBicepSource | Should -Not -Match 'Microsoft\.Network/publicIPAddresses@2025-07-01'
    $hostBicepSource | Should -Not -Match 'Microsoft\.Network/publicIPAddresses@2025-07-01'
    $providerCheckSource | Should -Match 'AllowBringYourOwnPublicIpAddress'
    $providerCheckSource | Should -Match 'az feature register'
    $deployWrapperSource | Should -Match 'Microsoft\.Network/\$NETWORK_FEATURE registered'
  }

  It 'deploys CSE modules only from main after managed identity roles' {
    $hostBicepSource | Should -Not -Match 'BootstrapApexLocal'
    $managementBicepSource | Should -Not -Match 'SetupJumpbox'
    $mainBicepSource | Should -Match "module hostBootstrapDeployment 'host/bootstrapExtension.bicep'"
    $mainBicepSource | Should -Match 'hostStorageContributor'
    $mainBicepSource | Should -Match 'hostContributor'
    $mainBicepSource | Should -Match 'hostUserAccessAdmin'
    $mainBicepSource | Should -Match "module jumpboxSetupDeployment 'mgmt/jumpboxSetup.bicep'"
  }

  It 'deploys host monitoring after workspace and VM creation' {
    $mainBicepSource | Should -Match "module hostMonitoringDeployment 'mgmt/hostMonitoring.bicep'"
    $mainBicepSource | Should -Match 'hostMonitoringDeployment[\s\S]+dependsOn:\s*\[\s*hostDeployment'
    $hostBicepSource | Should -Not -Match 'AzureMonitorWindowsAgent'
    $monitoringBicepSource | Should -Match 'Microsoft-Event'
    $monitoringBicepSource | Should -Match 'Microsoft-Perf'
  }

  It 'uses OAuth-only staging and no redundant or deployer data roles' {
    $storageBicepSource | Should -Match 'allowSharedKeyAccess:\s*false'
    $storageBicepSource | Should -Match "publicNetworkAccess:\s*'Disabled'"
    $storageBicepSource | Should -Match 'Microsoft\.Network/privateEndpoints@'
    $storageBicepSource | Should -Match "privatelink\.blob\.\$\{environment\(\)\.suffixes\.storage\}"
    $storageBicepSource | Should -Match "groupIds:\s*\[\s*'blob'"
    $mainBicepSource | Should -Not -Match 'hostTagContributor|hostReader|deployerStorageOwner'
  }

  It 'defaults runtime artifacts to the reserved immutable release tag' {
    $mainBicepSource | Should -Match "param artifactRef string = 'v1.3.0-rc.1'"
    $mainBicepSource | Should -Not -Match '(?m)^param githubBranch '
  }
}

Describe 'Self-hosted ISO integrity contract' {
  It 'publishes the manifest only after hashing and verifying both mandatory ISOs' {
    $isoPublisherSource | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$AzureLocalIsoPath'
    $isoPublisherSource | Should -Match '\[Parameter\(Mandatory\)\]\s*\[string\]\$WindowsServerIsoPath'
    $isoPublisherSource | Should -Match 'Get-FileHash[^\r\n]+SHA256'
    $isoPublisherSource.IndexOf('Set-AzStorageBlobContent -File $manifestPath') |
    Should -BeGreaterThan $isoPublisherSource.IndexOf('foreach ($u in $uploads)')
  }

  It 'treats the manifest-producing jumpbox tool as required' {
    $jumpboxSetupSource | Should -Match 'throw "Could not stage the required Upload-Isos\.ps1 tool'
  }

  It 'requires a valid manifest with both ISO entries before declaring readiness' {
    $moduleSource | Should -Match "ManifestBlob = 'iso-manifest.json'"
    $moduleSource | Should -Match 'Get-ApexIsoManifest[^\r\n]+RequiredBlobs'
    $moduleSource | Should -Match 'schemaVersion\s+-ne\s+1'
    $moduleSource | Should -Match 'contains duplicate blob'
    $moduleSource | Should -Match 'contains no image metadata'
  }

  It 'verifies byte length and SHA-256 before atomically promoting a download' {
    $moduleSource | Should -Match 'Get-FileHash[^\r\n]+SHA256'
    $moduleSource | Should -Match 'Downloaded SHA-256 mismatch'
    $moduleSource | Should -Match '\$partialPath\s*=\s*"\$Destination\.partial"'
    $moduleSource | Should -Match 'Move-Item -LiteralPath \$partialPath -Destination \$Destination'
  }

  It 'builds and validates VHDX images transactionally with explicit image selection' {
    $moduleSource | Should -Match "ParameterSetName = 'ByIndex'"
    $orchestratorSource | Should -Match 'Convert-ApexIsoToVhdx[^\r\n]+azurelocal-base\.vhdx[^\r\n]*\)?\s*`?[\r\n]+\s*-ImageIndex 1'
    $moduleSource | Should -Match '\.partial\.vhdx'
    $moduleSource | Should -Match 'bcdboot failed with exit code'
    $moduleSource | Should -Match 'EFI\\Microsoft\\Boot\\BCD'
    $moduleSource | Should -Match 'Test-BootableVhdx'
    $moduleSource | Should -Not -Match 'BootFromIso'
  }
}

Describe 'Self-hosted orchestration safety' {
  It 'exports Windows Defender-safe orchestration function names' {
    $moduleSource | Should -Match 'function Test-ApexEnvironmentReadiness'
    $moduleSource | Should -Match 'function Start-ApexLocalClusterDeployment'
    $moduleSource | Should -Not -Match 'Invoke-ApexEnvironmentValidation|Invoke-ApexLocalClusterDeploy'
  }

  It 'permits only one cluster build process at a time' {
    $orchestratorSource | Should -Match ([regex]::Escape("System.Threading.Mutex(`$false, 'Global\ApexLocalBuild')"))
    $orchestratorSource | Should -Match '\$buildMutex\.WaitOne\(0\)'
    $orchestratorSource | Should -Match '\$buildMutex\.ReleaseMutex\(\)'
  }

  It 'fails fast without the data volume and allows the full build window' {
    $bootstrapSource | Should -Match '\$expectedDataDiskCount = 12'
    $bootstrapSource | Should -Match '\$expectedDataDiskSize = 256GB'
    $bootstrapSource | Should -Match '-not \$disk\.IsBoot -and -not \$disk\.IsSystem'
    $bootstrapSource | Should -Match "PartitionStyle -eq 'RAW'"
    $bootstrapSource | Should -Match 'Expected exactly \$expectedDataDiskCount raw, non-system 256-GB data disks'
    $bootstrapSource | Should -Match "throw 'Required V: drive is unavailable"
    $bootstrapSource | Should -Match 'ExecutionTimeLimit \(New-TimeSpan -Hours 24\)'
    $answerDirectoryIndex = $bootstrapSource.IndexOf('$cfg.Paths.AnswerDir')
    $volumeGuardIndex = $bootstrapSource.IndexOf("if (-not (Test-Path 'V:\'))")
    $answerDirectoryIndex | Should -BeGreaterThan $volumeGuardIndex
  }

  It 'uses XML APIs for unattended setup values' {
    $moduleSource | Should -Match 'System\.Xml\.XmlNamespaceManager'
    $moduleSource | Should -Match '\$passwordNode\.InnerText = \$AdminPassword'
    $moduleSource | Should -Match 'System\.Xml\.XmlWriter'
    $moduleSource | Should -Not -Match '<Value>\$AdminPassword</Value>'
  }

  It 'verifies router, domain, and node time readiness' {
    $moduleSource | Should -Match 'Router forwarding, NAT, or default-route verification failed'
    $moduleSource | Should -Match 'Get-ADDomain -Identity \$fqdn'
    $moduleSource | Should -Match 'Resolve-DnsName -Name \$fqdn'
    $moduleSource | Should -Match 'Node is using an invalid time source'
    $moduleSource | Should -Match 'Hyper-V time synchronization is still enabled'
  }

  It 'declares success only after authoritative cluster state is healthy' {
    $moduleSource | Should -Match "ResourceType 'Microsoft\.AzureStackHCI/clusters'"
    $moduleSource | Should -Match "provisioningState -ne 'Succeeded'"
    $moduleSource | Should -Match "connectionState -ne 'Connected'"
    $moduleSource | Should -Match "reached Succeeded/Connected"
  }

  It 'reuses deterministic cluster resource names during recovery' {
    $mainBicepSource | Should -Match 'clusterResourceSuffix = take\(uniqueString\(resourceGroup\(\)\.id, clusterName\), 6\)'
    $bootstrapSource | Should -Match 'APEX_ClusterResourceSuffix'
    $moduleSource | Should -Match "GetEnvironmentVariable\('APEX_ClusterResourceSuffix', 'Machine'\)"
    $clusterDeployFunctionSource | Should -Not -Match '\[guid\]::NewGuid\(\)'
  }

  It 'supports protected cluster-only recovery without persisted credentials' {
    $recoveryWrapperSource | Should -Match '--protected-parameters AdminPassword='
    $recoveryWrapperSource | Should -Match '--async-execution true'
    $recoveryWrapperSource | Should -Not -Match 'read -r|read -s|cat <<'
    $recoverySource | Should -Match "Global\\ApexLocalBuild"
    $recoverySource | Should -Match 'Test-ApexEnvironmentReadiness'
    $recoverySource | Should -Match "Properties\.status -ne 'Connected'"
    $recoverySource | Should -Match '\$AdminPassword = \$null'
    $recoverySource | Should -Match "ValidateSet\('ValidateDeploy', 'DeployOnly'\)"
  }
}
