#==============================================================================
## remote-setup.ps1
##
##	The Windows setup check for remote-hosts.bash, run on the box, elevated.
##	Installs the setup .exe quietly, runs the cases .cmd with the installed exe
##	into installed.txt beside it, installs again, and uninstalls. The machine
##	PATH is checked after each, and put back at the end whatever happened,
##	since the setup once wiped a long one (2026102519371715). An existing
##	install is left alone.
##	Prints RESULT PASS|FAIL|SKIP lines, then FINAL and DONE.
##	powershell -NoProfile -ExecutionPolicy Bypass -File remote-setup.ps1 -Setup SETUP -Cases CMD
#==============================================================================

##	Copyright (C) 2026 Jim Collier
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
	[Parameter(Mandatory)] [string]$Setup,
	[Parameter(Mandatory)] [string]$Cases
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'

$envKeyPath = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$instDir = Join-Path -Path $env:ProgramFiles -ChildPath 'convert-base-v2'
$instExe = Join-Path -Path $instDir -ChildPath 'convert-base-v2.exe'
$arpKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\convert-base-v2'
$work = Split-Path -Parent $Setup

function Get-MachinePath {
	$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($envKeyPath, $false)
	try { [pscustomobject]@{ Value = [string]$k.GetValue('Path', '', 'DoNotExpandEnvironmentNames'); Kind = $k.GetValueKind('Path') } }
	finally { $k.Close() }
}
function Restore-MachinePath($saved) {
	$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($envKeyPath, $true)
	try { $k.SetValue('Path', $saved.Value, $saved.Kind) } finally { $k.Close() }
}
function Test-SamePath($label, $want, $got) {
	if ($got.Value -ceq $want.Value -and $got.Kind -eq $want.Kind) { "RESULT PASS $label" }
	else { "RESULT FAIL $label, now $($got.Kind) of $($got.Value.Length) characters" }
}
function Test-Gone {
	-not (Test-Path -LiteralPath $instExe) -and -not (Test-Path -LiteralPath $arpKey)
}
function Invoke-Quiet($exe) {
	(Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru).ExitCode
}

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { 'RESULT SKIP the login is not elevated'; 'DONE'; exit 0 }
if ((Test-Path -LiteralPath $instDir) -or (Test-Path -LiteralPath $arpKey)) { "RESULT SKIP already installed at $instDir, so it's left alone"; 'DONE'; exit 0 }

$before = Get-MachinePath
[IO.File]::WriteAllText((Join-Path -Path $work -ChildPath 'machine-path.txt'), "$($before.Kind)`r`n$($before.Value)")
$sep = if ($before.Value -eq '' -or $before.Value.EndsWith(';')) { '' } else { ';' }
$added = [pscustomobject]@{ Value = "$($before.Value)$sep$instDir"; Kind = $before.Kind }
try {
	$rc = Invoke-Quiet $Setup
	if ($rc -ne 0) { "RESULT FAIL install exit $rc" }
	Test-SamePath 'install keeps the PATH and adds its folder once' $added (Get-MachinePath)
	Start-Process -FilePath $env:ComSpec -ArgumentList '/d', '/c', $Cases, "`"$instExe`"" -NoNewWindow -Wait `
		-RedirectStandardOutput (Join-Path -Path $work -ChildPath 'installed.txt') -RedirectStandardError (Join-Path -Path $work -ChildPath 'installed.err')
	$rc = Invoke-Quiet $Setup
	if ($rc -ne 0) { "RESULT FAIL second install exit $rc" }
	Test-SamePath 'a second install changes nothing' $added (Get-MachinePath)
	# The uninstaller hands off to a copy of itself and returns at once.
	$rc = Invoke-Quiet (Join-Path -Path $instDir -ChildPath 'uninstall.exe')
	for ($i = 0; $i -lt 60 -and -not (Test-Gone); $i++) { Start-Sleep -Milliseconds 500 }
	Start-Sleep -Seconds 2
	Test-SamePath 'uninstall puts the PATH back' $before (Get-MachinePath)
	if (Test-Gone) { 'RESULT PASS uninstall leaves no exe or Programs entry' } else { "RESULT FAIL uninstall left the exe or its Programs entry (exit $rc)" }
}
finally {
	# Nothing was installed before, so nothing of ours stays.
	$un = Join-Path -Path $instDir -ChildPath 'uninstall.exe'
	if (Test-Path -LiteralPath $un) {
		Invoke-Quiet $un | Out-Null
		for ($i = 0; $i -lt 60 -and -not (Test-Gone); $i++) { Start-Sleep -Milliseconds 500 }
	}
	$now = Get-MachinePath
	if ($now.Value -cne $before.Value -or $now.Kind -ne $before.Kind) {
		Restore-MachinePath $before
		'RESULT FAIL the machine PATH had to be put back'
	}
	$now = Get-MachinePath
	"FINAL $(if ($now.Value -ceq $before.Value -and $now.Kind -eq $before.Kind) { 'PATH as before' } else { 'PATH DIFFERS' })"
	'DONE'
}
