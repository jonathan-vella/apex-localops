#requires -Version 7.4

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$powerShellRoot = Split-Path -Parent $PSScriptRoot
$sourceFiles = Get-ChildItem -Path $powerShellRoot -Recurse -File |
Where-Object {
  $_.Extension -in @('.ps1', '.psm1', '.psd1') -and
  $_.FullName -notlike "$PSScriptRoot*"
}

$parseFailures = @()
foreach ($sourceFile in $sourceFiles) {
  $tokens = $null
  $parseErrors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile(
    $sourceFile.FullName,
    [ref]$tokens,
    [ref]$parseErrors
  )

  foreach ($parseError in $parseErrors) {
    $parseFailures += [pscustomobject]@{
      File    = $sourceFile.FullName
      Line    = $parseError.Extent.StartLineNumber
      Message = $parseError.Message
    }
  }
}

if ($parseFailures.Count -gt 0) {
  $parseFailures | Format-Table -AutoSize
  throw "PowerShell parsing failed with $($parseFailures.Count) error(s)."
}

$manifestPath = Join-Path $powerShellRoot 'ApexLocalOps/ApexLocalOps.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
if ($manifest.PowerShellVersion -ne [version]'5.1') {
  throw "ApexLocalOps must retain Windows PowerShell 5.1 compatibility; found $($manifest.PowerShellVersion)."
}

Write-Output "Parsed $($sourceFiles.Count) self-hosted PowerShell source files."
Write-Output "Validated module manifest: $manifestPath"
