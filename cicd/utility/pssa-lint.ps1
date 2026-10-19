#==============================================================================
## pssa-lint.ps1
##
##	PSScriptAnalyzer over the files named, with the settings at the repo root.
##	One line per finding, file:line:col first, and exit 1 if there were any.
##	Run from the repo root: pwsh -File cicd/utility/pssa-lint.ps1 FILE...
#==============================================================================

##	Copyright (C) 2026 Jim Collier
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
	[Parameter(Mandatory, ValueFromRemainingArguments)] [string[]]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settings = Join-Path -Path (Get-Location) -ChildPath 'PSScriptAnalyzerSettings.psd1'
$found = 0
foreach ($file in $Path) {
	foreach ($hit in @(Invoke-ScriptAnalyzer -Path $file -Settings $settings)) {
		Write-Output ('{0}:{1}:{2}: {3}: {4} [{5}]' -f $file, $hit.Line, $hit.Column, $hit.Severity.ToString().ToLower(), $hit.Message, $hit.RuleName)
		$found++
	}
}
if ($found) { exit 1 }
