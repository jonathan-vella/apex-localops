#requires -Version 7.4
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.1' }

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
  $modulePath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1'
  $manifestPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psd1'
  $orchestratorPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/New-ApexLocalCluster.ps1'
  $versionsPath = Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ModuleVersions.psd1'

  $moduleSource = Get-Content -Path $modulePath -Raw
  $orchestratorSource = Get-Content -Path $orchestratorPath -Raw
  $manifest = Import-PowerShellDataFile -Path $manifestPath
  $versions = Import-PowerShellDataFile -Path $versionsPath
}

Describe 'Pinned Microsoft Azure Local preparation' {
  It 'locks the supported AD and Environment Checker module versions' {
    $versions.AsHciADArtifactsPreCreationTool | Should -Be '10.2402'
    $versions.AzStackHciEnvironmentChecker | Should -Be '10.2605.0.2006'
  }

  It 'exports and invokes the supported AD preparation function' {
    $manifest.FunctionsToExport | Should -Contain 'Initialize-ApexActiveDirectory'
    $moduleSource | Should -Match 'New-HciAdObjectsPreCreation'
    $orchestratorSource | Should -Match 'Initialize-ApexActiveDirectory'
    $orchestratorSource | Should -Match 'DomainAdminCredential\s+\$lcmCredential'
  }

  It 'runs all required readiness validators before Arc initialization' {
    $manifest.FunctionsToExport | Should -Contain 'Invoke-ApexEnvironmentValidation'
    foreach ($commandName in @(
      'Invoke-AzStackHciConnectivityValidation',
      'Invoke-AzStackHciSoftwareValidation',
      'Invoke-AzStackHciExternalActiveDirectoryValidation',
      'Invoke-AzStackHciNetworkValidation',
      'Invoke-AzStackHciArcIntegrationValidation',
      'Invoke-AzStackHciHardwareValidation'
    )) {
      $moduleSource | Should -Match $commandName
    }

    $readinessIndex = $orchestratorSource.IndexOf('Invoke-ApexEnvironmentValidation')
    $arcIndex = $orchestratorSource.IndexOf('Connect-ApexNodeToArc')
    $readinessIndex | Should -BeGreaterOrEqual 0
    $arcIndex | Should -BeGreaterThan $readinessIndex
  }

  It 'uses only the OS-bundled Azure Local Arc initialization command' {
    $moduleSource | Should -Match 'Invoke-AzStackHciArcInitialization'
    $moduleSource | Should -Not -Match 'AzureConnectedMachineAgent|azcmagent\s+connect'
    $moduleSource | Should -Match 'ArmAccessToken\s*=\s*\$null'
  }
}
