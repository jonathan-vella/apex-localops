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
  $isoDownloaderPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Get-ApexAzureLocalIso.ps1'
  $windowsIsoDownloaderPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Get-ApexWindowsServerIso.ps1'
  $isoStagerPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Stage-ApexIsos.ps1'
  $bootstrapPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Bootstrap.ps1'
  $jumpboxSetupPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Setup-Jumpbox.ps1'
  $recoveryPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Recover-ApexLocalCluster.ps1'
  $recoveryWrapperPath = Join-Path $repoRoot 'scripts/recover-selfhosted.sh'
  $deployWrapperPath = Join-Path $repoRoot 'scripts/deploy-selfhosted.sh'
  $providerCheckPath = Join-Path $repoRoot 'scripts/check-providers-selfhosted.sh'
  $isoStagingWrapperPath = Join-Path $repoRoot 'scripts/stage-selfhosted-isos.sh'

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
  $isoDownloaderSource = Get-Content -Path $isoDownloaderPath -Raw
  $windowsIsoDownloaderSource = Get-Content -Path $windowsIsoDownloaderPath -Raw
  $isoStagerSource = Get-Content -Path $isoStagerPath -Raw
  $bootstrapSource = Get-Content -Path $bootstrapPath -Raw
  $jumpboxSetupSource = Get-Content -Path $jumpboxSetupPath -Raw
  $recoverySource = Get-Content -Path $recoveryPath -Raw
  $recoveryWrapperSource = Get-Content -Path $recoveryWrapperPath -Raw
  $deployWrapperSource = Get-Content -Path $deployWrapperPath -Raw
  $providerCheckSource = Get-Content -Path $providerCheckPath -Raw
  $isoStagingWrapperSource = Get-Content -Path $isoStagingWrapperPath -Raw

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
    $orchestratorSource.IndexOf('Stop-Transcript') |
    Should -BeLessThan $orchestratorSource.IndexOf('Send-ApexLogsToStorage')
    $moduleSource | Should -Match '\$Status\.Length -gt 256'
    $moduleSource | Should -Match '\$Status\.Substring\(0, 256\)'
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
    $isoPublisherSource | Should -Match 'if \(\$null -ne \$_\.Version\)'
    $isoPublisherSource | Should -Match 'if \(\$null -ne \$_\.Architecture\)'
  }

  It 'downloads the pinned Azure Local ISO only from the official release host' {
    $isoDownloaderSource | Should -Match "ReleaseCode = '2607'"
    $isoDownloaderSource | Should -Match 'Add-Type -AssemblyName System\.Net\.Http'
    $isoDownloaderSource | Should -Match 'https://aka\.ms/hcireleaseimage/\$ReleaseCode'
    $isoDownloaderSource | Should -Match "allowedDownloadHost = 'azurestackreleases\.download\.prss\.microsoft\.com'"
    $isoDownloaderSource | Should -Match '\[Parameter\(Mandatory\)\] \[switch\]\$AcceptLicenseTerms'
    $isoDownloaderSource | Should -Match 'if \(\$ResolveOnly\)'
    $isoDownloaderSource | Should -Match '\$partialPath = "\$destination\.partial"'
    $isoDownloaderSource | Should -Match 'ContentRange'
    $isoDownloaderSource | Should -Match 'CD001'
    $isoDownloaderSource | Should -Match 'Get-FileHash[^\r\n]+SHA256'
    $jumpboxSetupSource | Should -Match "'Get-ApexAzureLocalIso\.ps1'"
    $jumpboxSetupSource | Should -Match "'Get-ApexWindowsServerIso\.ps1'"
    $jumpboxSetupSource | Should -Match "'Stage-ApexIsos\.ps1'"
    $jumpboxSetupSource | Should -Match "'Upload-Isos\.ps1'"
    $deployWrapperSource | Should -Match 'Get-ApexAzureLocalIso\.ps1'
  }

  It 'downloads the pinned Windows Server ISO only from the official release host' {
    $windowsIsoDownloaderSource | Should -Match 'linkid=2293312'
    $windowsIsoDownloaderSource | Should -Match "allowedDownloadHost = 'software-static\.download\.prss\.microsoft\.com'"
    $windowsIsoDownloaderSource | Should -Match '\[Parameter\(Mandatory\)\] \[switch\]\$AcceptEvaluationTerms'
    $windowsIsoDownloaderSource | Should -Match '\$partialPath = "\$destination\.partial"'
    $windowsIsoDownloaderSource | Should -Match 'ContentRange'
    $windowsIsoDownloaderSource | Should -Match 'CD001'
    $windowsIsoDownloaderSource | Should -Match 'Get-FileHash[^\r\n]+SHA256'
  }

  It 'supports unattended download and publication through managed run command' {
    $isoStagerSource | Should -Match 'Get-ApexAzureLocalIso\.ps1'
    $isoStagerSource | Should -Match 'Get-ApexWindowsServerIso\.ps1'
    $isoStagerSource | Should -Match 'Upload-Isos\.ps1'
    $isoStagerSource | Should -Match "ValidateSet\('Accepted'\)"
    $isoStagingWrapperSource | Should -Match '--async-execution true'
    $isoStagingWrapperSource | Should -Match '--accept-azure-local-license-terms'
    $isoStagingWrapperSource | Should -Match '--accept-windows-server-evaluation-terms'
    $isoStagingWrapperSource | Should -Not -Match 'read -r|read -s|password'
    $deployWrapperSource | Should -Match 'Get-ApexWindowsServerIso\.ps1'
    $deployWrapperSource | Should -Match 'Stage-ApexIsos\.ps1'
  }

  It 'treats the manifest-producing jumpbox tool as required' {
    $jumpboxSetupSource | Should -Match 'throw "Could not stage the required ISO tools'
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
    $orchestratorSource | Should -Match "\`$azlBase = Join-Path \`$cfg\.Paths\.BaseVhdDir 'azurelocal-base\.vhdx'"
    $orchestratorSource | Should -Match "\`$wsBase = Join-Path \`$cfg\.Paths\.BaseVhdDir 'windowsserver-base\.vhdx'"
    $orchestratorSource | Should -Match 'Convert-ApexIsoToVhdx -IsoPath \$azlIso -VhdxPath \$azlBase[^\r\n]*`?[\r\n]+\s*-ImageIndex 1'
    $moduleSource | Should -Match '\.partial\.vhdx'
    $moduleSource | Should -Match 'bcdboot failed with exit code'
    $moduleSource | Should -Match 'EFI\\Microsoft\\Boot\\BCD'
    $moduleSource | Should -Match 'Test-BootableVhdx'
    $moduleSource | Should -Not -Match 'BootFromIso'
    $orchestratorSource | Should -Match "Windows Server 2025 Datacenter Evaluation \(Desktop Experience\)"
    $convertingIndex = $orchestratorSource.IndexOf("-Progress 'BaseImagesConverting'")
    $convertedIndex = $orchestratorSource.IndexOf("-Progress 'BaseImagesConverted'")
    $convertedIndex | Should -BeGreaterThan $convertingIndex
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

  It 'never acquires PowerShell modules inside a nested guest' {
    # Freshly applied offline images have no registered PSGallery and no NuGet
    # provider, and their only egress runs through the lab's own nested router.
    $moduleSource | Should -Match 'function Install-ApexGuestModule'
    $moduleSource | Should -Match 'Save-Module -Name \$Name -RequiredVersion \$RequiredVersion'
    $moduleSource | Should -Match 'Copy-Item -Path \$versionPath -Destination \$guestModuleRoot -ToSession \$Session'
    $moduleSource | Should -Match "Install-ApexGuestModule -Name 'AsHciADArtifactsPreCreationTool'"
    $moduleSource | Should -Match 'Guest import of'
    $guestScript = [regex]::Match(
      $moduleSource,
      '(?s)function Initialize-ApexActiveDirectory.*?\n\}').Value
    $guestScript | Should -Not -Match 'Install-PackageProvider'
    $guestScript | Should -Not -Match 'Set-PSRepository'
    $guestScript | Should -Not -Match 'Install-Module'
    # The function must return only the LCM credential.
    $guestScript | Should -Match '\$null = Invoke-Command -Session \$session'
    $guestScript | Should -Match '\$null = New-HciAdObjectsPreCreation'
  }

  It 'stores nested VM configuration and paging files on the pooled volume' {
    # Hyper-V writes a .VMRS file the size of the VM's RAM beside the configuration,
    # so a 96-GB node cannot be configured on the small OS disk.
    $moduleSource | Should -Match '\[Parameter\(Mandatory\)\] \[string\]\$VmConfigDir'
    $moduleSource | Should -Match '-VHDPath \$diff -SwitchName \$SwitchName -Path \$VmConfigDir'
    $moduleSource | Should -Match 'Set-VM -Name \$VmName -SmartPagingFilePath \$VmConfigDir -SnapshotFileLocation \$VmConfigDir'
    $config.Paths.VmDir | Should -Match '^V:'
    ([regex]::Matches($moduleSource, '-VmConfigDir \$paths\.VmDir')).Count | Should -Be 3
  }

  It 'applies IMDS deny ACLs idempotently across every nested adapter' {
    # Hyper-V rejects a duplicate port ACL with 0x800700B7. Nodes inherit an
    # already-denied fabric adapter and then add storage adapters.
    $moduleSource | Should -Match 'function Add-ApexImdsDenyAcl'
    $moduleSource | Should -Match 'Get-VMNetworkAdapterAcl -VMNetworkAdapter \$VMNetworkAdapter'
    $moduleSource | Should -Match 'if \(\$alreadyApplied\.Count -eq 0\)'
    $moduleSource | Should -Match 'Add-ApexImdsDenyAcl -VMNetworkAdapter \$adapter -RemoteIPAddress \$ImdsAddress'
    $moduleSource | Should -Match 'Add-ApexImdsDenyAcl -VMNetworkAdapter \$nodeAdapter -RemoteIPAddress \$net\.ImdsAddress'
    # No caller may add the deny rules unconditionally.
    $moduleSource | Should -Not -Match 'Add-VMNetworkAdapterAcl -VMNetworkAdapter \$adapter'
    $moduleSource | Should -Not -Match 'Add-VMNetworkAdapterAcl -VMNetworkAdapter \$nodeAdapter'
  }

  It 'calls each Environment Checker validator with parameters it actually exposes' {
    # Every name below was verified against Get-Command on the pinned module version;
    # a wrong parameter only surfaces mid-deployment, after earlier validators pass.
    $moduleSource | Should -Match '-ConnectionLocalAdminCredential \$LocalAdminCredential'
    $moduleSource | Should -Not -Match '-SessionCredential'
    $moduleSource | Should -Match 'Invoke-AzStackHciConnectivityValidation -PsSession \$nodeSessions'
    $moduleSource | Should -Match 'Invoke-AzStackHciHardwareValidation -PsSession \$nodeSessions'
    $moduleSource | Should -Match 'Invoke-AzStackHciArcIntegrationValidation -SubscriptionID \$SubscriptionId'
  }

  It 'authenticates the AD validator with a UPN and normalises severity ordinals' {
    # Kerberos rejects DOMAIN\user on the isolated lab network, and the report
    # encodes severity/status as enum ordinals in the AD section.
    $moduleSource | Should -Match '\$adUserName = \(\$DomainAdminCredential\.UserName -split'
    $moduleSource | Should -Match '-ActiveDirectoryCredentials \$adCredential'
    $moduleSource | Should -Match ([regex]::Escape("`$criticalSeverities = @('Critical', '2')"))
    $moduleSource | Should -Match ([regex]::Escape("`$passedStatuses = @('Succeeded', 'Success', 'Passed', '0')"))
    # Every waiver must be an exact test ID, never a blanket bypass.
    $config.Validation.AllowedCriticalTests |
      Should -Contain 'AzStackHci_ExternalActiveDirectory_Test_OrganizationalUnit_ExecutingAsDeploymentUser'
  }

  It 'parses validator reports without case-folding their keys' {
    # Windows PowerShell's ConvertFrom-Json throws when one object carries both
    # 'value' and 'Value', which the Software validator emits.
    $moduleSource | Should -Match 'function ConvertFrom-ApexReportJson'
    $moduleSource | Should -Match 'JavaScriptSerializer'
    $moduleSource | Should -Match '\$report = ConvertFrom-ApexReportJson -Path \$destination'
    $moduleSource | Should -Not -Match 'Get-Content -Path \$destination -Raw \| ConvertFrom-Json'
    $moduleSource | Should -Match '\$InputObject -is \[System\.Collections\.IDictionary\]'
  }

  It 'verifies node Secure Boot and vTPM with supported Hyper-V cmdlets' {
    $moduleSource | Should -Match 'Get-VMSecurity -VMName \$name'
    $moduleSource | Should -Match '-not \$security\.TpmEnabled'
    # Get-VMTPM does not exist in the Hyper-V module.
    $moduleSource | Should -Not -Match 'Get-VMTPM'
  }

  It 'claims the progress tag before any stage reports' {
    # A resumed run must not inherit the previous attempt's terminal Failed tag.
    $orchestratorSource | Should -Match "-Progress 'Building'"
    $claimIndex = $orchestratorSource.IndexOf("-Progress 'Building'")
    $firstStageIndex = $orchestratorSource.IndexOf("Test-ApexStage 'HostFabric'")
    $claimIndex | Should -BeGreaterThan 0
    $claimIndex | Should -BeLessThan $firstStageIndex
  }

  It 'resumes at a named stage instead of forcing a full rebuild' {
    $orchestratorSource | Should -Match '\[string\]\$StartAtStage = ''HostFabric'''
    $orchestratorSource | Should -Match 'function Test-ApexStage'
    foreach ($stage in @('HostFabric', 'Isos', 'BaseImages', 'Router', 'DomainController',
        'ActiveDirectory', 'Nodes', 'Readiness', 'Arc', 'ClusterDeploy')) {
      $orchestratorSource | Should -Match ([regex]::Escape("Test-ApexStage '$stage'"))
    }
    # Skipped stages must reconstruct their outputs rather than leaving them empty.
    $orchestratorSource | Should -Match 'Cannot resume at .\$StartAtStage.: staged ISOs are missing'
    $orchestratorSource | Should -Match 'Cannot resume at .\$StartAtStage.: base VHDX images are missing'
    $orchestratorSource | Should -Match '\$domainAdminCred = New-Object System\.Management\.Automation\.PSCredential'
    $orchestratorSource | Should -Match '\$lcmCredential = New-Object System\.Management\.Automation\.PSCredential'
    $orchestratorSource | Should -Match '\$cfg\.Cluster\.NodeStartIp\.Split'
  }

  It 'extends the OS volume across the provisioned OS disk' {
    # The image partition is ~127 GB while the disk is 1024 GB; nothing else grows it.
    $bootstrapSource | Should -Match 'Get-PartitionSupportedSize -DiskNumber \$osPartition\.DiskNumber'
    $bootstrapSource | Should -Match 'Resize-Partition -DiskNumber \$osPartition\.DiskNumber'
    $resizeIndex = $bootstrapSource.IndexOf('Resize-Partition')
    $poolIndex = $bootstrapSource.IndexOf('Pooling the data disks')
    $resizeIndex | Should -BeGreaterThan 0
    $resizeIndex | Should -BeLessThan $poolIndex
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
    $moduleSource | Should -Match "GptType -eq '\{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7\}'"
    $moduleSource | Should -Match 'Set-Partition -NewDriveLetter \$driveLetter'
    $moduleSource | Should -Match 'Remove-PartitionAccessPath'
    $moduleSource | Should -Match '@\(68\.\.90 \| ForEach-Object \{ \[char\]\$_ \}\)'
    $moduleSource | Should -Not -Match "'D'\.\.'Z'"
    $moduleSource | Should -Match 'Unattend injection verification failed'
    $moduleSource | Should -Match "SecureBootTemplate 'MicrosoftWindows'"
    $moduleSource | Should -Not -Match "SecureBootTemplate 'MicrosoftUEFICertificateAuthority'"
  }

  It 'verifies router, domain, and node time readiness' {
    $moduleSource | Should -Match 'Router forwarding, NAT, or default-route verification failed'
    $moduleSource | Should -Match 'Get-ADDomain -Identity \$fqdn'
    $moduleSource | Should -Match 'Get-Service -Name ADWS, DNS, NTDS'
    $moduleSource | Should -Match '\$healthDeadline = \(Get-Date\)\.AddMinutes\(15\)'
    $moduleSource | Should -Match 'Domain controller services are not ready; retrying in 20s'
    $moduleSource | Should -Match '\$null = Invoke-Command -VMName \$dom\.DcHostName -Credential \$domainCred'
    $moduleSource | Should -Match 'return \$domainCred'
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
