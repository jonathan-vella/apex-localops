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
  $resumePath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/Resume-ApexLocalCluster.ps1'
  $resumeWrapperPath = Join-Path $repoRoot 'scripts/resume-selfhosted.sh'
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
  $resumeSource = Get-Content -Path $resumePath -Raw
  $resumeWrapperSource = Get-Content -Path $resumeWrapperPath -Raw
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

  It 'never announces success it has not actually observed' {
    $monitorSource = Get-Content -Path (Join-Path $repoRoot 'scripts/monitor-selfhosted.sh') -Raw
    # Re-reading the tag after is_done let a resume flip it mid-check, so the monitor
    # fell through and reported a cluster that did not exist.
    $monitorSource | Should -Match 'DONE_REASON="failed"'
    $monitorSource | Should -Match 'DONE_REASON="succeeded"'
    $monitorSource | Should -Match 'if \[\[ "\$DONE_REASON" == "failed" \]\]'
    # Success is only ever claimed from the real cluster state.
    $monitorSource | Should -Match 'provisioningState'
    $monitorSource | Should -Match '\$prov" == "Succeeded" && "\$conn" == "Connected"'
    # A resume must clear the previous attempt's terminal tag immediately.
    $resumeWrapperSource | Should -Match 'az tag update --resource-id "\$RG_ID" --operation merge'
    $resumeWrapperSource | Should -Match 'ApexProgress=Building'
  }

  It 'resolves both perishable ISO pins before anything starts billing' {
    # A dead pin discovered during staging means the host and its 12 Premium disks
    # have already been billing for ~20 minutes.
    $deployWrapperSource | Should -Match 'aka\.ms/hcireleaseimage/\$\{AZURE_LOCAL_RELEASE_CODE\}'
    $deployWrapperSource | Should -Match 'WINDOWS_SERVER_ISO_ALIAS'
    $deployWrapperSource | Should -Match 'both pinned ISO aliases resolve to approved hosts'

    # The approved hosts must not drift between the preflight and the downloaders.
    foreach ($approvedHost in @('azurestackreleases.download.prss.microsoft.com',
        'software-static.download.prss.microsoft.com')) {
      $deployWrapperSource.Contains($approvedHost) | Should -BeTrue
    }
    $isoDownloaderSource.Contains('azurestackreleases.download.prss.microsoft.com') | Should -BeTrue
    $windowsIsoDownloaderSource.Contains('software-static.download.prss.microsoft.com') | Should -BeTrue

    # The release code the preflight checks must be the one staging downloads.
    $deployWrapperSource | Should -Match 'AZURE_LOCAL_RELEASE_CODE="2607"'
    $deployWrapperSource | Should -Match '--azure-local-release-code "\$AZURE_LOCAL_RELEASE_CODE"'
    # Preflight must prove the recovery surface exists at the ref too, or a stranger
    # discovers a missing resume script only after a failure.
    $deployWrapperSource | Should -Match 'Resume-ApexLocalCluster\.ps1'
    $deployWrapperSource | Should -Match 'Recover-ApexLocalCluster\.ps1'
  }

  It 'passes exactly what the vendored cluster template declares' {
    # Stage 10 runs after hours of build. A parameter typo or a refreshed vendored
    # template must fail here, not three hours into a paid run.
    $template = Get-Content -Path (Join-Path $repoRoot 'artifacts/selfhosted/azlocal.json') -Raw |
      ConvertFrom-Json
    $templateParamNames = @($template.parameters.PSObject.Properties.Name)

    $block = [regex]::Match($moduleSource, '(?s)\$common = @\{(.*?)\n  \}').Groups[1].Value
    $splatKeys = @([regex]::Matches($block, '(?m)^\s{4}(\w+)\s+=') | ForEach-Object { $_.Groups[1].Value })
    $splatKeys.Count | Should -BeGreaterThan 20

    # deploymentMode is supplied separately on each of the Validate and Deploy calls.
    $passed = @($splatKeys | Where-Object { $_ -notin @('ResourceGroupName', 'TemplateFile') }) +
    'deploymentMode'
    foreach ($name in $passed) {
      $templateParamNames | Should -Contain $name
    }

    $required = @($template.parameters.PSObject.Properties |
      Where-Object { -not $_.Value.PSObject.Properties.Name.Contains('defaultValue') } |
      ForEach-Object { $_.Name })
    foreach ($name in $required) {
      $passed | Should -Contain $name
    }

    # Every constrained value the deploy hard-codes must be in the allowed set.
    $template.parameters.witnessType.allowedValues | Should -Contain 'No Witness'
    $template.parameters.securityLevel.allowedValues | Should -Contain 'Recommended'
    $template.parameters.configurationMode.allowedValues | Should -Contain 'Express'
    $template.parameters.networkingType.allowedValues | Should -Contain 'switchedMultiServerDeployment'
    $template.parameters.deploymentMode.allowedValues | Should -Contain 'Validate'
    $template.parameters.deploymentMode.allowedValues | Should -Contain 'Deploy'
  }

  It 'bounds Arc initialization and verifies the guest command surface' {
    # Arc init falls back to an interactive device-code prompt if the token is rejected,
    # and that prompt is invisible over PowerShell Direct.
    $moduleSource | Should -Match 'Invoke-Command -VMName \$VmName -Credential \$Credential -AsJob'
    $moduleSource | Should -Match 'Wait-Job -Job \$arcJob -Timeout \$TimeoutSeconds'
    $moduleSource | Should -Match 'Stop-Job -Job \$arcJob'
    $moduleSource | Should -Match '\[int\]\$TimeoutSeconds = 2700'
    # The host-side contract gate cannot see a command that only exists on the node.
    $moduleSource | Should -Match 'Invoke-AzStackHciArcInitialization does not expose'
    # The token must still be passed, or every run turns into a device-code prompt.
    $moduleSource | Should -Match 'ArmAccessToken = \$token'
    # Exit code alone is not proof: the command can succeed while onboarding nothing.
    $moduleSource.Contains('Agent Status\s*:\s*Connected') | Should -BeTrue
    $moduleSource | Should -Match 'reported success but the agent is not Connected'
  }

  It 'stores the lab password so a resume never needs it retyped' {
    # The build scrubs the credential on failure; without a vault every resume is manual.
    $mainBicep = Get-Content -Path (Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/main.bicep') -Raw
    $labSecrets = Get-Content -Path (Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/mgmt/labSecrets.bicep') -Raw
    $mainBicep | Should -Match "module labSecretsDeployment 'mgmt/labSecrets\.bicep'"
    $mainBicep | Should -Match 'adminPassword: windowsAdminPassword'
    $labSecrets | Should -Match "name: 'lab-admin-password'"
    $labSecrets | Should -Match 'enableRbacAuthorization: true'
    # Reading it back must require an explicit data-plane grant, not just RG ownership.
    $labSecrets | Should -Match '4633458b-17de-408a-b874-0445c86b69e6'
    $resumeWrapperSource | Should -Match 'az keyvault secret show --vault-name'
    $resumeWrapperSource | Should -Match '--name lab-admin-password'
    $deployWrapperSource | Should -Match 'operatorPrincipalId=\$OPERATOR_PRINCIPAL_ID'
    # Soft delete reserves the name, so cleanup must purge or redeploy collides.
    $cleanupSource = Get-Content -Path (Join-Path $repoRoot 'scripts/cleanup-selfhosted.sh') -Raw
    $cleanupSource | Should -Match 'az keyvault purge --name'
  }

  It 'runs Arc integration validation on a node, where it is supported' {
    # Proven on the live lab: run on the outer host every check returns
    # "ARC Integration validation is only supported on HCI OS", and
    # Get-AzureStackHCISubscriptionStatus does not exist there.
    $moduleSource | Should -Match 'only runs on the Azure Local OS'
    $moduleSource | Should -Match 'Invoke-Command -Session \$arcSession'
    $moduleSource | Should -Match 'Copy-Item -FromSession \$arcSession'
    # The node has no Azure identity of its own, so the host must hand it a token.
    $moduleSource | Should -Match 'ArmAccessToken                = \$token'
    $moduleSource | Should -Match "Get-AzAccessToken -ResourceUrl 'https://management\.azure\.com/'"
    # The token must be cleared in both scopes.
    $moduleSource | Should -Match '\$arguments\.ArmAccessToken = \$null'
    $moduleSource | Should -Match '\$armToken = \$null'
    # Region is the Azure Local instance region, threaded from the orchestrator.
    $moduleSource | Should -Match 'Region                        = \$region'
    $orchestratorSource.Contains("-Phase 'ArcIntegration' -InstanceLocation `$instanceLoc") |
      Should -BeTrue

    # Passing ArmAccessToken selects the ARMToken parameter set, whose mandatory
    # members include AzureEnvironment and AccountId. Missing either one prompts, and
    # a prompt inside a remote session is invisible.
    $moduleSource | Should -Match "AzureEnvironment              = 'AzureCloud'"
    $moduleSource | Should -Match 'AccountId                     = \$account'
    $moduleSource | Should -Match "ARMToken set also requires"
    $moduleSource | Should -Match '\$_\.IsMandatory -and -not \$arguments\.ContainsKey'
    # A missing account id must fail loudly instead of silently dropping the parameter.
    $moduleSource | Should -Match 'Could not resolve the host account id'

    # The validator calls Get-AzResource internally and the Azure Local image ships
    # Az.Accounts but not Az.Resources, so both are side-loaded from the host.
    $moduleSource | Should -Match "@\{ Name = 'Az\.Accounts'; Version = \`$moduleVersions\.AzAccounts \}"
    $moduleSource | Should -Match "@\{ Name = 'Az\.Resources'; Version = \`$moduleVersions\.AzResources \}"
    $moduleSource | Should -Match 'Install-ApexGuestModule -Name \$guestModule\.Name'
    # Those pins must exist, since the node has no PSGallery to fall back on.
    $moduleVersionsPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ModuleVersions.psd1'
    $pins = Import-PowerShellDataFile -Path $moduleVersionsPath
    $pins.AzAccounts | Should -Not -BeNullOrEmpty
    $pins.AzResources | Should -Not -BeNullOrEmpty
  }

  It 'discovers Arc machines through the provider API, not the generic one' {
    # Proven on the live lab: az resource list / Get-AzResource do not return
    # Microsoft.HybridCompute/machines here, so the old lookup reported 0/3 for the
    # full 30 minute wait while all three nodes were genuinely Connected.
    $orchestratorSource | Should -Match 'Invoke-AzRestMethod -Method GET -Path'
    $orchestratorSource | Should -Match 'Microsoft\.HybridCompute/machines/\$\(\$n\.Name\)'
    $orchestratorSource | Should -Match "api-version=\d{4}-\d{2}-\d{2}"
    $orchestratorSource | Should -Match "\`$machine\.properties\.status -eq 'Connected'"
    # The generic resources API must not come back for this lookup.
    $orchestratorSource | Should -Not -Match "Get-AzResource[^\r\n]*HybridCompute"
  }

  It 'lets the Azure Local region be chosen and proves it before billing' {
    # A region the subscription may not use fails Arc onboarding with
    # RequestDisallowedByAzure 403 ~90 minutes in, and the agent blames credentials.
    $mainBicep = Get-Content -Path (Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/main.bicep') -Raw
    $bootstrapExt = Get-Content -Path (Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/host/bootstrapExtension.bicep') -Raw

    $mainBicep | Should -Match "param azureLocalInstanceLocation string = 'westeurope'"
    $mainBicep | Should -Match 'azureLocalInstanceLocation: azureLocalInstanceLocation'
    # The region must no longer be hard-coded into the bootstrap command line.
    $bootstrapExt | Should -Match '-azureLocalInstanceLocation \$\{azureLocalInstanceLocation\}'
    $bootstrapExt | Should -Not -Match '-azureLocalInstanceLocation westeurope'

    $deployWrapperSource | Should -Match '--azure-local-location\) AZURE_LOCAL_INSTANCE_LOCATION='
    $deployWrapperSource | Should -Match 'azureLocalInstanceLocation=\$AZURE_LOCAL_INSTANCE_LOCATION'
    # Preflight must prove the subscription can actually use the region.
    $deployWrapperSource | Should -Match 'subscription cannot create resources in'
    $deployWrapperSource | Should -Match 'apexlocal-regionprobe-'

    # The allowed list must match between bicep and the wrapper. [^\]]* keeps the match
    # from spanning earlier @allowed blocks in the file.
    $bicepRegions = @([regex]::Matches(
        [regex]::Match($mainBicep, "@allowed\(\[([^\]]*)\]\)\s*param azureLocalInstanceLocation").Groups[1].Value,
        "'([a-z]+)'") | ForEach-Object { $_.Groups[1].Value })
    $wrapperRegions = @([regex]::Match($deployWrapperSource,
        'AZURE_LOCAL_REGIONS=\(([^)]*)\)').Groups[1].Value -split '\s+' | Where-Object { $_ })
    $bicepRegions.Count | Should -BeGreaterThan 5
    Compare-Object $bicepRegions $wrapperRegions | Should -BeNullOrEmpty
  }

  It 'waives only the criticals nested virtualization makes unavoidable' {
    $waived = @($config.Validation.AllowedCriticalTests)
    # Each entry was observed failing on the live lab and is impossible to remediate
    # in a nested topology. The list must stay closed so new criticals still block.
    $waived | Should -HaveCount 4
    $waived | Should -Contain 'AzStackHci_Hardware_MemoryProperties'
    $waived | Should -Contain 'AzStackHci_Hardware_PhysicalDisk'
    $waived | Should -Contain 'AzStackHci_Hardware_Test_NetAdapter'
    $waived | Should -Contain 'AzStackHci_ExternalActiveDirectory_Test_OrganizationalUnit_ExecutingAsDeploymentUser'
    # No wildcards: a waiver must name one exact test id.
    foreach ($entry in $waived) {
      $entry | Should -Not -Match '[\*\?]'
      $entry | Should -Match '^AzStackHci_'
    }
  }

  It 'rebuilds node sessions for every validator that consumes them' {
    # EnsureTestSessionOpen removes the sessions it is handed and keeps the replacements,
    # so a session reused across steps is Closed by the time the next validator runs.
    $moduleSource | Should -Match 'function Reset-ApexNodeSession'
    $moduleSource | Should -Match '\$nodeSessions \| Remove-PSSession -ErrorAction SilentlyContinue'
    # One refresh per session-consuming step: Connectivity, Software, Network, Hardware,
    # plus the node session the post-Arc validator runs inside.
    ([regex]::Matches($moduleSource, '\$nodeSessions = Reset-ApexNodeSession')).Count |
      Should -Be 5
    # Every -PsSession argument must be the refreshed variable.
    foreach ($validator in 'Invoke-AzStackHciConnectivityValidation',
      'Invoke-AzStackHciSoftwareValidation', 'Invoke-AzStackHciHardwareValidation') {
      $moduleSource | Should -Match "$validator -PsSession \`$nodeSessions"
    }
  }

  It 'runs the Arc integration pre-check before onboarding creates the machines' {
    # It is a PRE-registration check: it fails with "Arc machine(s) ... already exists
    # in the Resource Group" if it runs after onboarding. It also only works on the
    # Azure Local OS, so it runs in a node session rather than on the host.
    $moduleSource.Contains("[ValidateSet('HostChecks', 'ArcIntegration')] [string]`$Phase = 'HostChecks'") |
      Should -BeTrue
    $orchestratorSource.Contains("-Phase 'ArcIntegration' -InstanceLocation `$instanceLoc") |
      Should -BeTrue

    # It must sit inside the Readiness stage, ahead of the Arc onboarding loop.
    $arcCheckIndex = $orchestratorSource.IndexOf("-Phase 'ArcIntegration'")
    $onboardIndex = $orchestratorSource.IndexOf('Connect-ApexNodeToArc')
    $arcCheckIndex | Should -BeGreaterThan 0
    $arcCheckIndex | Should -BeLessThan $onboardIndex
  }

  It 'validates Arc integration only after the Arc machines exist' -Skip {
    # Superseded: proven on the live lab to be a pre-registration check.
  }

  It 'reads each validator report from where that validator actually writes it' {
    # -OutputPath redirects the network report away from the profile location the
    # other validators use, so the harness must be told, not assume.
    $moduleSource | Should -Match '\[string\]\$ReportPath = \$sourceReport'
    $moduleSource.Contains("Invoke-ValidationStep -Name 'Network' -ReportPath (Join-Path `$reportDirectory 'AzStackHciEnvironmentReport.json')") |
      Should -BeTrue
    $moduleSource | Should -Match 'Remove-Item -Path \$ReportPath'
    $moduleSource | Should -Match 'Copy-Item -Path \$ReportPath'
    # The failure must name the path it looked in.
    $moduleSource | Should -Match "did not write its JSON report to '\`$ReportPath'"
  }

  It 'gives each ATC intent the override flags the checker hard-casts' {
    # The checker does [Boolean] $x = $intent.OverrideAdapterProperty, so a missing
    # property fails with 'Cannot convert value "" to type System.Boolean'.
    $intentBlock = [regex]::Match($moduleSource, '(?s)\$atcHostIntents = @\((.*?)\n    \)').Groups[1].Value
    $intentBlock | Should -Not -BeNullOrEmpty
    foreach ($flag in 'OverrideAdapterProperty', 'OverrideQoSPolicy',
      'OverrideVirtualSwitchConfiguration') {
      # Once per intent, and both must be $false to match the no-RDMA nested adapters.
      ([regex]::Matches($intentBlock, [regex]::Escape($flag) + '\s+= \$false')).Count |
        Should -Be 2
    }
    foreach ($bag in 'AdapterPropertyOverrides', 'QoSPolicyOverrides',
      'VirtualSwitchConfigurationOverrides') {
      ([regex]::Matches($intentBlock, [regex]::Escape($bag) + '\s+= \$null')).Count |
        Should -Be 2
    }
  }

  It 'hands the checker WinRM sessions it can rebuild, not PowerShell Direct' {
    # EnvValidatorNwkLibEnsureTestSessionOpen destroys every supplied session and
    # rebuilds it from ComputerName + ConnectionInfo.Credential. PowerShell Direct
    # carries no reusable credential there, so the rebuild ran as SYSTEM and failed.
    $moduleSource.Contains('$fresh += New-PSSession -ComputerName $node.Name') |
      Should -BeFalse
    $moduleSource | Should -Match '\$candidate = New-PSSession -ComputerName \$node\.Name'
    $moduleSource | Should -Match '-Credential \$networkAdminCredential -ErrorAction Stop'
    $moduleSource.Contains('New-PSSession -VMName $node.Name') | Should -BeFalse
    $moduleSource | Should -Match 'EnvValidatorNwkLibEnsureTestSessionOpen'
    # A rebuilt node can reboot mid-specialize, leaving a Broken session.
    $moduleSource | Should -Match "if \(\`$candidate\.State -ne 'Opened'\)"
    $moduleSource | Should -Match 'Could not open a usable WinRM session'
  }

  It 'machine-qualifies the credential the network validator dials nodes with' {
    # Proven on the live lab: bare 'Administrator' fails NTLM to a workgroup node with
    # 0x8009030d, while '.\Administrator' succeeds against every node.
    $moduleSource.Contains('$networkAdminCredential = New-Object System.Management.Automation.PSCredential(') |
      Should -BeTrue
    $moduleSource | Should -Match '-ConnectionLocalAdminCredential \$networkAdminCredential'
    $moduleSource | Should -Match '0x8009030d'
    # PowerShell Direct must keep the original credential, which is already proven.
    $moduleSource | Should -Match '-VMName \$node\.Name -Credential \$LocalAdminCredential|PowerShell Direct is'
  }

  It 'pins node names to management addresses instead of trusting LLMNR' {
    # Workgroup nodes have no DC records, so LLMNR answers with whichever adapter
    # replies first - an APIPA address on a storage adapter - and the validator
    # then opens its sessions to 169.254.x.x.
    $moduleSource | Should -Match 'function Set-ApexNodeNameResolution'
    $moduleSource.Contains("System32\drivers\etc\hosts") | Should -BeTrue
    $moduleSource | Should -Match '# BEGIN ApexLocal nested nodes'
    $moduleSource | Should -Match '# END ApexLocal nested nodes'
    # Rewriting the block in place keeps repeated runs from stacking stale addresses.
    $moduleSource | Should -Match 'Set-Content -Path \$hostsPath'
    $moduleSource.Contains('Set-ApexNodeNameResolution -Nodes $Nodes -DomainFqdn $Config.Domain.Fqdn') |
      Should -BeTrue
    # Resolution must be pinned before trust is granted and the validators run.
    $resolutionIndex = $moduleSource.IndexOf('Set-ApexNodeNameResolution -Nodes $Nodes')
    $validatorIndex = $moduleSource.IndexOf('Invoke-AzStackHciNetworkValidation')
    $resolutionIndex | Should -BeGreaterThan 0
    $resolutionIndex | Should -BeLessThan $validatorIndex
  }

  It 'trusts the nested nodes explicitly so the network validator can dial them' {
    # The validator opens its own sessions by name; a workgroup host refuses NTLM
    # to an untrusted target, so passing -PSSession alone is not enough.
    $moduleSource | Should -Match 'function Set-ApexNodeWinRmTrust'
    $moduleSource.Contains('WSMan:\localhost\Client\TrustedHosts') | Should -BeTrue
    $moduleSource.Contains('Set-ApexNodeWinRmTrust -Nodes $Nodes -DomainFqdn $Config.Domain.Fqdn') |
      Should -BeTrue
    # A wildcard trust list would let the host authenticate to anything.
    $moduleSource.Contains("-ne '*'") | Should -BeTrue
  }

  It 'can run the whole lab from one command once licences are accepted' {
    # Forgetting the separate staging step strands the build in Wait-ApexStagedIso.
    $deployWrapperSource | Should -Match '--accept-azure-local-license-terms\) ACCEPT_AZURE_LOCAL_TERMS=true'
    $deployWrapperSource | Should -Match '--accept-windows-server-evaluation-terms\) ACCEPT_WINDOWS_SERVER_TERMS=true'
    $deployWrapperSource | Should -Match 'STAGE_ISOS="\$SCRIPT_DIR/stage-selfhosted-isos\.sh"'
    # Acceptance must never be defaulted on for the operator.
    $deployWrapperSource | Should -Match 'ACCEPT_AZURE_LOCAL_TERMS=false'
    $deployWrapperSource | Should -Match 'ACCEPT_WINDOWS_SERVER_TERMS=false'
  }

  It 'turns a failure into a named stage the operator can resume from' {
    # A stranger must not have to read a transcript over Bastion to recover.
    $orchestratorSource | Should -Match "Stage '\`$failedStage' failed:"
    $orchestratorSource | Should -Match '\$script:currentStage = \$Name'
    $monitorSource = Get-Content -Path (Join-Path $repoRoot 'scripts/monitor-selfhosted.sh') -Raw
    $monitorSource | Should -Match 'resume-selfhosted\.sh --stage'

    # The monitor parses the stage back out of the tag; prove the round trip.
    $tagValue = "Stage 'Readiness' failed: something broke"
    ($tagValue -match "^Stage '([A-Za-z]*)' failed:") | Should -BeTrue
    $Matches[1] | Should -Be 'Readiness'
  }

  It 'supports stage resume without exposing the lab password' {
    # Resume must reuse what the previous attempt built, so a defect costs one stage.
    $resumeWrapperSource | Should -Match '--protected-parameters AdminPassword='
    $resumeWrapperSource | Should -Match '--async-execution true'
    $resumeWrapperSource | Should -Match 'ARTIFACT_REF'
    # Never embed the credential in the script body or command line.
    $resumeSource | Should -Not -Match 'ToBase64String\(\[Text\.Encoding\]::UTF8\.GetBytes\(.Pass'
    $resumeSource | Should -Match '\[Parameter\(Mandatory\)\] \[string\]\$AdminPassword'
    $resumeSource | Should -Match "Remove-Variable -Name AdminPassword"
    # A resumed build must be non-interactive and must refresh the manifest too.
    $resumeSource | Should -Match "'-NonInteractive'"
    $resumeSource | Should -Match 'ApexLocalOps/ApexLocalOps\.psd1'
    $resumeSource | Should -Match 'A build or recovery process is already running'

    # The wrapper and the orchestrator must agree on the stage list exactly.
    $stageBlock = [regex]::Match($orchestratorSource, '(?s)\$stageOrder = @\((.*?)\)').Groups[1].Value
    $orchestratorStages = @([regex]::Matches($stageBlock, "'([^']+)'") |
      ForEach-Object { $_.Groups[1].Value })
    $wrapperStages = @([regex]::Match($resumeWrapperSource,
        'STAGES=\(([^)]*)\)').Groups[1].Value -split '\s+' | Where-Object { $_ })
    $orchestratorStages.Count | Should -BeGreaterThan 0
    Compare-Object $orchestratorStages $wrapperStages | Should -BeNullOrEmpty
  }

  It 'never lets the build block on an invisible prompt' {
    # The build runs as SYSTEM with no console. A missing mandatory parameter would
    # prompt and hang forever, which is exactly how network validation stalled.
    $bootstrapSource | Should -Match '-ExecutionPolicy Bypass -NoProfile -NonInteractive -File'
    $bootstrapSource | Should -Match '-ExecutionPolicy Bypass -NoProfile -NonInteractive -WindowStyle Hidden -File'
    $moduleSource | Should -Match '-NodesInCluster \(\[int16\]\$Nodes\.Count\)'
  }

  It 'verifies external command signatures before building anything' {
    $moduleSource | Should -Match 'function Test-ApexCommandContract'
    $orchestratorSource | Should -Match 'Test-ApexCommandContract -Contract'
    # Must run before the first stage, so a bad signature costs seconds not minutes.
    $contractIndex = $orchestratorSource.IndexOf('Test-ApexCommandContract -Contract')
    $firstStageIndex = $orchestratorSource.IndexOf("Test-ApexStage 'HostFabric'")
    $contractIndex | Should -BeGreaterThan 0
    $contractIndex | Should -BeLessThan $firstStageIndex
    # The four signatures that previously failed mid-build must be covered.
    $orchestratorSource | Should -Match "'Get-VMSecurity'"
    $orchestratorSource | Should -Match 'SnapshotFileLocation'
    $orchestratorSource | Should -Match 'ConnectionLocalAdminCredential'
    $orchestratorSource | Should -Match "'New-VM'"
  }

  It 'calls each Environment Checker validator with parameters it actually exposes' {
    # Every name below was verified against Get-Command on the pinned module version;
    # a wrong parameter only surfaces mid-deployment, after earlier validators pass.
    $moduleSource | Should -Match '-ConnectionLocalAdminCredential \$networkAdminCredential'
    $moduleSource | Should -Not -Match '-SessionCredential'
    $moduleSource | Should -Match 'Invoke-AzStackHciConnectivityValidation -PsSession \$nodeSessions'
    $moduleSource | Should -Match 'Invoke-AzStackHciHardwareValidation -PsSession \$nodeSessions'
    $moduleSource | Should -Match 'Invoke-AzStackHciArcIntegrationValidation @arguments'
    foreach ($argument in 'SubscriptionID', 'TenantID', 'ArcResourceGroupName',
      'RegistrationResourceGroupName', 'Region', 'NodeNames', 'ArmAccessToken', 'OutputPath') {
      $moduleSource | Should -Match "$argument\s+= \`$"
    }
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
    # Setting the time source is not the same as being in sync: a freshly built node
    # needs several resync attempts before AzStackHci_Software_NtpServer-Sync passes.
    # While the Hyper-V integration service is on, the VM IC provider outranks the
    # configured peer, the DC never becomes reliable, and every node then fails
    # AzStackHci_Software_NtpServer-Sync despite reaching the DC fine.
    $moduleSource.Contains("Disable-VMIntegrationService -VMName `$dom.DcHostName -Name 'Time Synchronization'") |
      Should -BeTrue
    $moduleSource | Should -Match 'Domain controller is not an authoritative time source'
    $moduleSource | Should -Match 'did not synchronize time with DC'
    $moduleSource.Contains('Last Successful Sync Time:\s*unspecified') | Should -BeTrue
    $moduleSource | Should -Match '\$deadline = \(Get-Date\)\.AddMinutes\(10\)'
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
