#requires -Version 7.4
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.1' }

<#
  Behavioural unit tests: these EXECUTE the module's pure helpers with real inputs.

  This rung exists because the source-contract suite matches text and cannot observe
  runtime behaviour. Defects that shipped to paid deployments despite a fully green
  contract suite include an invalid character range, an unbounded object walk, and
  serialization of null metadata. Every case below reproduces a real failure.
#>

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
  Import-Module (Join-Path $repoRoot 'artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psd1') -Force
}

AfterAll {
  Remove-Module ApexLocalOps -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ApexCriticalValidationResult' {
  It 'terminates on a report that embeds a timestamp' {
    # Regression: [datetime].Date returns a [datetime], so walking value-type
    # properties recursed forever and failed the build with a call depth overflow
    # after the Connectivity validator had already passed.
    InModuleScope ApexLocalOps {
      $report = [pscustomobject]@{
        Name      = 'Test-Connectivity'
        Severity  = 'Critical'
        Status    = 'Failed'
        Timestamp = [datetime]'2026-07-27T07:28:43Z'
        Duration  = [timespan]::FromMinutes(3)
      }

      $result = @(Get-ApexCriticalValidationResult -InputObject $report)

      $result.Count | Should -Be 1
      $result[0].Name | Should -Be 'Test-Connectivity'
      $result[0].Status | Should -Be 'Failed'
    }
  }

  It 'ignores critical results that passed and non-critical failures' {
    InModuleScope ApexLocalOps {
      $report = @(
        [pscustomobject]@{ Name = 'Passed-Critical'; Severity = 'Critical'; Status = 'Succeeded' }
        [pscustomobject]@{ Name = 'Failed-Warning'; Severity = 'Warning'; Status = 'Failed' }
      )

      @(Get-ApexCriticalValidationResult -InputObject $report).Count | Should -Be 0
    }
  }

  It 'finds critical failures nested inside collections' {
    InModuleScope ApexLocalOps {
      $report = [pscustomobject]@{
        Summary = 'Connectivity'
        Results = @(
          [pscustomobject]@{ Name = 'Test-A'; Severity = 'Critical'; Status = 'Succeeded' }
          [pscustomobject]@{
            Name     = 'Group'
            Children = @(
              [pscustomobject]@{ Name = 'Test-B'; Severity = 'Critical'; Status = 'Failed' }
            )
          }
        )
      }

      $result = @(Get-ApexCriticalValidationResult -InputObject $report)

      $result.Count | Should -Be 1
      $result[0].Name | Should -Be 'Test-B'
    }
  }

  It 'stops walking beyond the depth bound instead of overflowing' {
    InModuleScope ApexLocalOps {
      # Build a graph deeper than the bound; the walk must return, not throw.
      $node = [pscustomobject]@{ Name = 'Deep'; Severity = 'Critical'; Status = 'Failed' }
      foreach ($i in 1..40) {
        $node = [pscustomobject]@{ Child = $node }
      }

      { Get-ApexCriticalValidationResult -InputObject $node } | Should -Not -Throw
    }
  }

  It 'returns nothing for null and scalar input' {
    InModuleScope ApexLocalOps {
      @(Get-ApexCriticalValidationResult -InputObject $null).Count | Should -Be 0
      @(Get-ApexCriticalValidationResult -InputObject 'a string').Count | Should -Be 0
      @(Get-ApexCriticalValidationResult -InputObject 42).Count | Should -Be 0
    }
  }
}
