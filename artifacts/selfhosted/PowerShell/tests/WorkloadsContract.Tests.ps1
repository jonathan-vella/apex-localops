#requires -Version 7.4
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.1' }

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
  $workloadsDir = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/workloads'
  $configPath = Join-Path $workloadsDir 'Workloads-Config.psd1'
  $modulePath = Join-Path $workloadsDir 'AzLocalWorkloads.psm1'
  $orchestratorPath = Join-Path $workloadsDir 'Deploy-AzLocalWorkloads.ps1'
  $vmBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/workloads/vm.bicep'
  $avdBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/workloads/avd/main.bicep'
  $insightsBicepPath = Join-Path $repoRoot 'infra/bicep/azlocal-selfhosted/mgmt/insights.bicep'
  $wrapperPath = Join-Path $repoRoot 'scripts/deploy-workloads-selfhosted.sh'

  $config = Import-PowerShellDataFile -Path $configPath
  $moduleSource = Get-Content -Path $modulePath -Raw
  $orchestratorSource = Get-Content -Path $orchestratorPath -Raw
  $vmBicepSource = Get-Content -Path $vmBicepPath -Raw
  $avdBicepSource = Get-Content -Path $avdBicepPath -Raw
  $insightsBicepSource = Get-Content -Path $insightsBicepPath -Raw
  $wrapperSource = Get-Content -Path $wrapperPath -Raw
}

Describe 'Self-hosted workloads config' {
  It 'leaves identity/cluster values blank for runtime resolution (reusable)' {
    $config.SubscriptionId | Should -BeNullOrEmpty
    $config.Location | Should -BeNullOrEmpty
    $config.CustomLocationName | Should -BeNullOrEmpty
    $config.VmLogicalNetworkName | Should -BeNullOrEmpty
    $config.ResourceGroup | Should -Be 'rg-apexlocal'
    $config.VmSwitchName | Should -Be 'ConvergedSwitch(compute_management)'
  }

  It 'creates a dedicated tenant VM lnet and pre-creates the AKS lnet' {
    $config.LogicalNetworks.Vm.Name | Should -Be 'apexlocal-vmlnet'
    $config.LogicalNetworks.Vm.ReuseExisting | Should -BeFalse
    $config.LogicalNetworks.Vm.AddressPrefix | Should -BeNullOrEmpty
    $config.LogicalNetworks.Aks.ReuseExisting | Should -BeFalse
    $config.LogicalNetworks.Aks.Vlan | Should -Be 110
    $config.LogicalNetworks.Aks.AddressPrefix | Should -Be '10.10.0.0/24'
  }

  It 'defines the three Gen2 marketplace images (WS2025 smalldisk)' {
    $config.Images.WindowsServer2025.Urn | Should -Be 'microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition-smalldisk:latest'
    $config.Images.Sql2022.Urn | Should -Be 'microsoftsqlserver:sql2022-ws2022:standard-gen2:latest'
    $config.Images.Win11Avd.Urn | Should -Be 'microsoftwindowsdesktop:office-365:win11-25h2-avd-m365:latest'
  }

  It 'defines two domain-joined WS2025 VMs with static tenant-lnet IPs' {
    $config.Vms.WindowsServer2025_1.Name | Should -Be 'apexws01'
    $config.Vms.WindowsServer2025_1.PrivateIp | Should -Be '192.168.1.60'
    $config.Vms.WindowsServer2025_1.LogicalNetworkName | Should -BeNullOrEmpty
    $config.Vms.WindowsServer2025_2.Name | Should -Be 'apexws02'
    $config.Vms.WindowsServer2025_2.PrivateIp | Should -Be '192.168.1.61'
    foreach ($k in 'WindowsServer2025_1', 'WindowsServer2025_2', 'AvdHost') {
      $config.Vms[$k].DomainJoin | Should -BeTrue
    }
    $config.Domain.Fqdn | Should -Be 'apexlocal.local'
    $config.Vms.AvdHost.Name | Should -Be 'apexavd01'
    $config.Vms.AvdHost.PrivateIp | Should -Be '192.168.1.70'
  }

  It 'sets AVD metadata to canadacentral' {
    $config.Avd.MetadataLocation | Should -Be 'canadacentral'
    $config.Avd.HostPoolName | Should -Be 'apexlocal-hp01'
  }
}

Describe 'Self-hosted workloads module + orchestrator' {
  It 'reads the self-hosted password env var' {
    $moduleSource | Should -Match "LOCALSELF_ADMIN_PASSWORD"
    $moduleSource | Should -Not -Match "'LOCALBOX_ADMIN_PASSWORD'"
  }

  It 'supports multi-lnet with ReuseExisting and per-VM static IP' {
    $moduleSource | Should -Match '\$Config\.LogicalNetworks\.Keys'
    $moduleSource | Should -Match 'ReuseExisting'
    $moduleSource | Should -Match 'privateIPAddress=\$\(\$Vm\.PrivateIp\)'
    $moduleSource | Should -Match 'hciLogicalNetworkName=\$lnetName'
  }

  It 'decouples domain join from VM creation (waits for the Arc agent, defers on timeout)' {
    $moduleSource | Should -Match 'function Wait-VmAgentConnected'
    $moduleSource | Should -Match 'Phase 1: create the VM instance \(no domain join\)'
    $moduleSource | Should -Match 'Phase 2: domain join \(decoupled \+ retryable\)'
    $moduleSource | Should -Match 'Wait-VmAgentConnected -Config \$Config -VmName \$Vm\.Name'
    $moduleSource | Should -Match 'domain join DEFERRED'
    $moduleSource | Should -Match 'Wait-VmAgentConnected'  # exported for reuse
  }

  It 'points at the self-hosted vm.bicep' {
    $moduleSource | Should -Match 'infra/bicep/azlocal-selfhosted/workloads/vm\.bicep'
    $moduleSource | Should -Not -Match 'azlocal-js/workloads/vm\.bicep'
  }

  It 'deploys two WS2025 VMs in the ws2025 and all stages' {
    $orchestratorSource | Should -Match "Invoke-StageVm 'WindowsServer2025_1'"
    $orchestratorSource | Should -Match "Invoke-StageVm 'WindowsServer2025_2'"
  }

  It 'resolves subscription + cluster names at runtime (reusable across tenants)' {
    $moduleSource | Should -Match 'function Resolve-ClusterContext'
    $moduleSource | Should -Match "ends_with\(name,'InfraLNET'\)"
    $orchestratorSource | Should -Match 'Resolve-ClusterContext -Config \$Config'
    $wrapperSource | Should -Match 'reportedProperties\.nodes\[\]\.name'
    $wrapperSource | Should -Not -Match "starts_with\(name,'apexlocal-n'\)"
  }
}

Describe 'Self-hosted workloads bicep' {
  It 'vm.bicep supports an optional static private IP and keeps vmSize Custom' {
    $vmBicepSource | Should -Match "param privateIPAddress string = ''"
    $vmBicepSource | Should -Match 'empty\(privateIPAddress\)'
    $vmBicepSource | Should -Match "vmSize: 'Custom'"
  }

  It 'insights.bicep installs AMA + the Azure Local Insights DCR on the Arc cluster nodes' {
    $insightsBicepSource | Should -Match 'param nodeNames array'
    $insightsBicepSource | Should -Match 'Microsoft.HybridCompute/machines/extensions'
    $insightsBicepSource | Should -Match "type: 'AzureMonitorWindowsAgent'"
    $insightsBicepSource | Should -Match 'Microsoft.Insights/dataCollectionRules'
    $insightsBicepSource | Should -Match 'Microsoft.Insights/dataCollectionRuleAssociations'
    # The DCR must carry the Azure Local Insights data sources for the portal blade + workbook.
    $insightsBicepSource | Should -Match 'Microsoft-Windows-Health/Operational'
    $insightsBicepSource | Should -Match 'Microsoft-Windows-SDDC-Management/Operational'
    $insightsBicepSource | Should -Match 'AzureStackHCI-'
  }

  It 'avd main.bicep defaults to canadacentral + apexlocal names' {
    $avdBicepSource | Should -Match "param location string = 'canadacentral'"
    $avdBicepSource | Should -Match "param hostPoolName string = 'apexlocal-hp01'"
    $avdBicepSource | Should -Match "hostPoolType: 'Pooled'"
  }
}

Describe 'Self-hosted workloads wrapper' {
  It 'exposes the insights stage and self-hosted paths + env' {
    $wrapperSource | Should -Match 'insights\)\s+do_insights'
    $wrapperSource | Should -Match 'LOCALSELF_ADMIN_PASSWORD'
    $wrapperSource | Should -Match 'artifacts/selfhosted/PowerShell/workloads'
    $wrapperSource | Should -Match 'azlocal-selfhosted/mgmt/insights\.bicep'
    $wrapperSource | Should -Match 'RESOURCE_GROUP="rg-apexlocal"'
    # Resolves the HCI RP object id in THIS subscription (no hard-coded LocalBox id).
    $wrapperSource | Should -Match '1412d89f-b8a8-4111-b4fd-e82905cbd85d'
    $wrapperSource | Should -Not -Match 'bd244008-3ffc-40de-9cc9-032054b76e22'
  }
}
