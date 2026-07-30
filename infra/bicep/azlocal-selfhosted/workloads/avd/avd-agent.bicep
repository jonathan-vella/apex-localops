// =============================================================================
// avd-agent.bicep - Register an Azure Local session-host VM with an AVD host pool.
//
// Installs the Azure Virtual Desktop Agent + Agent Boot Loader inside an existing,
// domain-joined Arc VM via a Custom Script Extension (Microsoft.HybridCompute/
// machines/extensions). This is the SAME extension mechanism that performs the AD
// domain join in vm.bicep - it is the reliable in-guest path on Azure Local
// (the HybridCompute runCommands API does NOT dispatch reliably on these VMs).
//
// The session-host VM must already be:
//   - created + correctly sized (vm.bicep),
//   - AD domain-joined (vm.bicep domainToJoin), and
//   - have guest management / the Connected Machine agent healthy (for IMDS).
//
// Deploy AFTER the AVD control plane (avd/main.bicep) exists. Supply the host-pool
// registration token (retrieve it with the REST action, see avd/README or below):
//   TOKEN=$(az rest --method post --url \
//     "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DesktopVirtualization/hostPools/<hp>/retrieveRegistrationToken?api-version=2025-10-10" \
//     --query token -o tsv)
//   az deployment group create -g <rg> --template-file avd-agent.bicep \
//     --parameters vmName=azl-avd-01 registrationToken="$TOKEN"
//
// API version = latest GA HybridCompute 2025-01-13.
// =============================================================================

@description('Name of the existing Arc session-host VM (the Microsoft.HybridCompute/machines resource).')
param vmName string

@description('Azure region (must match the VM/Arc machine location).')
param location string = resourceGroup().location

@secure()
@description('AVD host-pool registration token (retrieve via the retrieveRegistrationToken REST action).')
param registrationToken string

@description('AVD Agent (RDInfraAgent) installer download URL. Default = current production fwlink.')
param agentMsiUri string = 'https://go.microsoft.com/fwlink/?linkid=2310011'

@description('AVD Agent Boot Loader installer download URL. Default = current production fwlink.')
param bootLoaderMsiUri string = 'https://go.microsoft.com/fwlink/?linkid=2311028'

@description('Extension name.')
param extensionName string = 'InstallAvdAgent'

resource machine 'Microsoft.HybridCompute/machines@2025-01-13' existing = {
  name: vmName
}

// In-guest installer: download both MSIs, install the RDInfraAgent WITH the
// registration token, then the Boot Loader. Runs as one PowerShell command so it
// can live in protectedSettings (keeps the token out of logs/plain settings).
// Uses $env:TEMP + Join-Path (no hard-coded backslashes) and only single-quoted
// inner strings, so the Bicep -> ARM -> PowerShell escaping stays correct.
var installScript = 'powershell.exe -ExecutionPolicy Unrestricted -NoProfile -Command "$ErrorActionPreference=\'Stop\'; $d=$env:TEMP; $agent=Join-Path $d \'RDAgent.msi\'; $boot=Join-Path $d \'RDBootLoader.msi\'; Invoke-WebRequest -Uri \'${agentMsiUri}\' -OutFile $agent -UseBasicParsing; Invoke-WebRequest -Uri \'${bootLoaderMsiUri}\' -OutFile $boot -UseBasicParsing; $a=Start-Process msiexec.exe -ArgumentList \'/i\',$agent,\'/quiet\',\'/norestart\',\'REGISTRATIONTOKEN=${registrationToken}\' -Wait -PassThru; $b=Start-Process msiexec.exe -ArgumentList \'/i\',$boot,\'/quiet\',\'/norestart\' -Wait -PassThru; if(($a.ExitCode -ne 0) -or ($b.ExitCode -ne 0)){exit 1}; Write-Output \'AVD_AGENT_INSTALLED\'"'

resource avdAgent 'Microsoft.HybridCompute/machines/extensions@2025-01-13' = {
  parent: machine
  name: extensionName
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    // protectedSettings is encrypted at rest and not returned by GET - keeps the token safe.
    protectedSettings: {
      commandToExecute: installScript
    }
  }
}

@description('The AVD agent extension resource ID.')
output extensionId string = avdAgent.id
