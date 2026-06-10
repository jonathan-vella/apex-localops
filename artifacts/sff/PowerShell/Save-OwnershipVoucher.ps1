#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - store the SFF ownership voucher (.pem) in the Key Vault.

.DESCRIPTION
  Run on the host after downloading the ownership voucher from the nested VM via the
  Configurator App. Stores the voucher as a base64 secret in the SFF Key Vault using
  the host managed identity (Key Vault Secrets Officer), so it never lingers on disk
  in the clear. Tags SffProgress=VoucherStored.

.EXAMPLE
  ./Save-OwnershipVoucher.ps1 -Path C:\Users\arcdemo\Downloads\ownership-voucher.pem
#>
param(
  [Parameter(Mandatory)] [string]$Path,
  [string]$SecretName = 'sff-ownership-voucher',
  [string]$KeyVaultName,
  [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

$rootDir = 'C:\LocalSFF'
. (Join-Path $rootDir 'Sff-Common.ps1')
$cfg = Get-SffConfig -ConfigPath (Join-Path $rootDir 'SffConfig.psd1')

if (-not (Test-Path $Path)) { throw "Voucher file not found: $Path" }
if (-not $KeyVaultName)  { $KeyVaultName  = [Environment]::GetEnvironmentVariable('SFF_KeyVaultName', 'Machine') }
if (-not $ResourceGroup) { $ResourceGroup = [Environment]::GetEnvironmentVariable('SFF_ResourceGroup', 'Machine') }
if (-not $KeyVaultName)  { throw 'KeyVaultName not provided and SFF_KeyVaultName env var is empty.' }

Connect-SffAzure | Out-Null
Import-Module Az.KeyVault -ErrorAction Stop

$bytes = [System.IO.File]::ReadAllBytes($Path)
$b64 = [System.Convert]::ToBase64String($bytes)
$secure = ConvertTo-SecureString -String $b64 -AsPlainText -Force

Write-SffLog "Storing ownership voucher as secret '$SecretName' in Key Vault '$KeyVaultName'."
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $secure `
  -ContentType 'application/x-pem-file;base64' | Out-Null

if ($ResourceGroup) {
  Set-SffProgress -ResourceGroup $ResourceGroup -Progress 'VoucherStored' -Status "Voucher saved to $KeyVaultName" -Config $cfg
}
Write-SffLog "Ownership voucher stored. Continue with portal machine provisioning (docs/sff-runbook.md)."
Write-Host "To retrieve later:  az keyvault secret show --vault-name $KeyVaultName --name $SecretName --query value -o tsv | base64 -d > voucher.pem"
