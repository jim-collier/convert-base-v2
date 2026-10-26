#==============================================================================
## install.ps1
##
##	One-line installer for convert-base-v2 on Windows, and on Linux, macOS, and
##	FreeBSD under pwsh. Downloads a release binary, verifies its checksum
##	against the release's checksums.txt, and installs it. States its plan and
##	asks first.
##
##	Usage:
##		& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.ps1))) [options]
##	Options:
##		-Release stable|dev ... stable = newest release (default), dev = newest including pre-releases
##		-Target user|system ... user (default) or system, paths below
##		-Yes .................. skip the confirmation prompt
##		-Version .............. print this installer's version
##		-Help ................. this help
##	Where it goes:
##		Windows user .......... %LOCALAPPDATA%\Programs\convert-base-v2, added to the user PATH
##		Windows system ........ %ProgramFiles%\convert-base-v2, added to the machine PATH (elevated shell)
##		Linux, macOS, FreeBSD . ~/.local/bin, or /usr/local/bin for system (uses sudo)
##	Notes:
##		- Needs Windows PowerShell 5.1 or pwsh 7.
##		- The OS and CPU are detected. With no stable release yet, stable takes the newest pre-release.
##		- Re-running is safe; an already-current install is left alone.
##		- Pure ASCII with no byte-order mark, since irm keeps a mark and the parse then fails.
#==============================================================================

##	Copyright (C) 2026 Jim Collier
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

<#
.SYNOPSIS
Installs or updates the convert-base-v2 release binary.
.DESCRIPTION
Downloads a release from GitHub, checks it against the release's checksums.txt, and installs it for this user or for the whole system. States the plan and asks before it touches anything.
.PARAMETER Release
stable (the default) takes the newest full release, or the newest pre-release while there is no full one. dev takes the newest release, pre-releases included.
.PARAMETER Target
user (the default) or system.
.PARAMETER Yes
Skip the confirmation prompt.
.PARAMETER Version
Print the installer's version and exit.
.PARAMETER Help
Print the options and exit.
.EXAMPLE
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.ps1))) -Release dev
#>
[CmdletBinding()]
param(
	[ValidateSet('stable', 'dev')] [string]$Release = 'stable',
	[ValidateSet('user', 'system')] [string]$Target = 'user',
	[switch]$Yes,
	[switch]$Version,
	[switch]$Help
)

## The body runs in its own scope, so strict mode and the preference variables
## stay out of the shell that ran the one-liner. There `exit` would close that
## shell, so only a run of this file exits; any other run returns or throws.
& {
	## ShowVersion, not Version: names ignore case, and $version would clash.
	param([string]$Release, [string]$Target, [bool]$Yes, [bool]$ShowVersion, [bool]$Help, [bool]$invokedAsFile)

	Set-StrictMode -Version Latest
	$ErrorActionPreference = 'Stop'
	## 5.1 repaints the bar per chunk, which slows a download a lot.
	$ProgressPreference = 'SilentlyContinue'

	$installerVersion = '1.0.1'
	$pkg = 'convert-base-v2'
	$repo = 'jim-collier/convert-base-v2'

	if ($ShowVersion) {
		Write-Output "$pkg installer v$installerVersion"
		return
	}

	## Written out rather than left to Get-Help, since the one-liner leaves no
	## file to ask about.
	if ($Help) {
		@"
Usage:
	& ([scriptblock]::Create((irm https://raw.githubusercontent.com/$repo/main/install.ps1))) [options]
Options:
	-Release stable|dev ... stable = newest release (default), dev = newest including pre-releases
	-Target user|system ... user (default) or system, paths below
	-Yes .................. skip the confirmation prompt
	-Version .............. print this installer's version
	-Help ................. this help
Where it goes:
	Windows user .......... %LOCALAPPDATA%\Programs\$pkg, added to the user PATH
	Windows system ........ %ProgramFiles%\$pkg, added to the machine PATH (elevated shell)
	Linux, macOS, FreeBSD . ~/.local/bin, or /usr/local/bin for system (uses sudo)
Notes:
	- Needs Windows PowerShell 5.1 or pwsh 7.
	- The OS and CPU are detected. With no stable release yet, stable takes the newest pre-release.
	- Re-running is safe; an already-current install is left alone.
"@ | Write-Output
		return
	}

	Write-Output ''

	function Exit-Install {
		[CmdletBinding()]
		param([string]$Message)
		if ($invokedAsFile) {
			[Console]::Error.WriteLine("[ ERROR: $Message ]")
			[Console]::Error.WriteLine('')
			exit 1
		}
		throw "install.ps1: $Message"
	}

	## A property that may not be there, without strict mode throwing on it.
	function Get-Field {
		[CmdletBinding()]
		param($Object, [string]$Name)
		if ($null -eq $Object) { return $null }
		$prop = $Object.PSObject.Properties[$Name]
		if ($prop) { return $prop.Value }
		return $null
	}

	## Why a web request failed, short. pwsh 7 throws with no Response member and
	## 5.1 with a null one, and strict mode throws on reading either.
	function Get-WebFailure {
		[CmdletBinding()]
		param([System.Management.Automation.ErrorRecord]$ErrorRecord)
		$response = Get-Field -Object $ErrorRecord.Exception -Name 'Response'
		if ($response) { return "HTTP $([int]$response.StatusCode)" }
		$ex = $ErrorRecord.Exception
		while ($ex.InnerException) { $ex = $ex.InnerException }
		return $ex.Message
	}

	## Sorts like install.bash: numbers compare as numbers, a pre-release sorts
	## below its final, and digit runs in the suffix pad out, so beta10 > beta9.
	function Get-VersionKey {
		[CmdletBinding()]
		param([string]$Tag)
		$m = [regex]::Match($Tag, '^v?(\d+)\.(\d+)\.(\d+)(?:-(.+))?$')
		if (-not $m.Success) { return $null }
		$key = $m.Groups[1].Value.PadLeft(8, '0') + $m.Groups[2].Value.PadLeft(8, '0') + $m.Groups[3].Value.PadLeft(8, '0')
		if (-not $m.Groups[4].Success) { return $key + '1' }
		$pad = [Text.RegularExpressions.MatchEvaluator] { param($digits) $digits.Value.PadLeft(8, '0') }
		return $key + '0' + [regex]::Replace($m.Groups[4].Value, '\d+', $pad)
	}

	function Select-Newest {
		[CmdletBinding()]
		param([object[]]$From)
		$best = $null
		foreach ($candidate in $From) {
			if ($null -eq $best -or [string]::CompareOrdinal($candidate.Key, $best.Key) -gt 0) { $best = $candidate }
		}
		return $best
	}

	## The first line of a program's --version, or '' when it won't run. Started directly, never
	## through `&`, which on Linux hands a non-executable file to xdg-open.
	function Get-ProgramVersion {
		[CmdletBinding()]
		param([string]$Path)
		try {
			$psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo -ArgumentList $Path, '--version'
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			$psi.CreateNoWindow = $true
			$proc = [Diagnostics.Process]::Start($psi)
			$text = $proc.StandardOutput.ReadToEnd()
			$null = $proc.StandardError.ReadToEnd()
			if (-not $proc.WaitForExit(10000)) { $proc.Kill(); return '' }
			if ($proc.ExitCode -ne 0) { return '' }
			return ($text.Trim() -split '\r?\n')[0].Trim()
		} catch {
			return ''
		}
	}

	## Why this user can't write the install, or $null when it can. Asked before
	## the download, so a read-only folder fails early with a reason.
	function Test-InstallTarget {
		[CmdletBinding()]
		param([string]$Dir, [string]$Exe)
		$near = $Dir
		while ($near -and -not (Test-Path -LiteralPath $near)) { $near = Split-Path -Path $near -Parent }
		if (-not $near) { return "can't write to $Dir - no part of that path exists" }
		$probe = Join-Path -Path $near -ChildPath ('.cbv2-probe-' + [IO.Path]::GetRandomFileName())
		try {
			[IO.File]::Create($probe, 1, [IO.FileOptions]::DeleteOnClose).Dispose()
		} catch {
			return "can't write to $near - permission denied"
		}
		## A running exe on Windows can't be replaced, and that reads as access
		## denied at the move. Opening it unshared tells the two apart.
		if (Test-Path -LiteralPath $Exe -PathType Leaf) {
			try {
				[IO.File]::Open($Exe, 'Open', 'ReadWrite', 'None').Dispose()
			} catch {
				$ex = $_.Exception
				while ($ex.InnerException) { $ex = $ex.InnerException }
				if ($ex -is [UnauthorizedAccessException]) { return "can't replace $Exe - permission denied" }
				return "can't replace $Exe - it's in use. Close it and run this again"
			}
		}
		return $null
	}

	## Straight at the registry: [Environment]::SetEnvironmentVariable writes
	## PATH back as REG_SZ, which breaks every %VAR% in it.
	function Get-PathKey {
		[CmdletBinding()]
		param([string]$Scope, [bool]$Writable)
		if ($Scope -eq 'Machine') {
			return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $Writable)
		}
		return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $Writable)
	}

	function Test-PathEntry {
		[CmdletBinding()]
		param([string]$Scope, [string]$Dir)
		$envKey = Get-PathKey -Scope $Scope -Writable $false
		try {
			$current = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
			return ($current -split ';') -contains $Dir
		} finally {
			$envKey.Close()
		}
	}

	function Add-PathEntry {
		[CmdletBinding()]
		param([string]$Scope, [string]$Dir)
		$envKey = Get-PathKey -Scope $Scope -Writable $true
		try {
			$current = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
			$joined = if ($current -and -not $current.EndsWith(';')) { "$current;$Dir" } else { "$current$Dir" }
			$envKey.SetValue('Path', $joined, [Microsoft.Win32.RegistryValueKind]::ExpandString)
		} finally {
			$envKey.Close()
		}
	}

	if ($PSVersionTable.PSVersion -lt [version]'5.1') {
		Exit-Install "needs Windows PowerShell 5.1 or pwsh 7, and this is $($PSVersionTable.PSVersion)"
	}

	## What to fetch and where to put it. $IsWindows doesn't exist on 5.1, which
	## only runs on Windows, so it's read only on 6 and up.
	$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
	$useSudo = $false
	$pathScope = $null
	if ($onWindows) {
		## A 32-bit shell on a 64-bit OS reports x86; ARCHITEW6432 has the real CPU.
		$archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
		$arch = switch ($archRaw) { 'AMD64' { 'x86_64' } 'ARM64' { 'arm64' } default { $null } }
		if (-not $arch) { Exit-Install "unsupported CPU '$archRaw'. Builds exist for x86_64 and arm64." }
		$exeName = "$pkg.exe"
		$asset = "$pkg-windows-$arch.exe"
		if ($Target -eq 'system') {
			$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
			if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
				Exit-Install 'a system install needs an elevated shell (Run as administrator), or use -Target user'
			}
			## ProgramFiles is the x86 one in a 32-bit shell.
			$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
			$destDir = Join-Path -Path $programFiles -ChildPath $pkg
			$pathScope = 'Machine'
		} else {
			$destDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Programs\$pkg"
			$pathScope = 'User'
		}
	} else {
		$osRaw = [string](uname -s)
		$os = switch ($osRaw) { 'Linux' { 'linux' } 'Darwin' { 'darwin' } 'FreeBSD' { 'freebsd' } default { $null } }
		if (-not $os) { Exit-Install "unsupported OS '$osRaw'" }
		$archRaw = [string](uname -m)
		$arch = switch ($archRaw) { 'x86_64' { 'x86_64' } 'amd64' { 'x86_64' } 'aarch64' { 'arm64' } 'arm64' { 'arm64' } default { $null } }
		if (-not $arch) { Exit-Install "unsupported CPU '$archRaw'. Builds exist for x86_64 and arm64." }
		$exeName = $pkg
		$asset = "$pkg-$os-$arch"
		if ($Target -eq 'system') {
			$destDir = '/usr/local/bin'
			$useSudo = ([string](id -u)) -ne '0'
		} else {
			$destDir = Join-Path -Path $HOME -ChildPath '.local/bin'
		}
	}
	$destPath = Join-Path -Path $destDir -ChildPath $exeName

	## 5.1 may not offer TLS 1.2 by default, and GitHub requires it.
	if ($PSVersionTable.PSVersion.Major -lt 6) {
		[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	}

	Write-Output "[ Looking up the newest $Release release ]"
	## The list, not releases/latest, which is stable-only and 404s while every
	## release is a pre-release.
	try {
		$listing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=100" -UseBasicParsing
	} catch {
		Exit-Install "couldn't reach the GitHub API (offline, or rate-limited?): $(Get-WebFailure -ErrorRecord $_)"
	}
	## Assigned first: 5.1 hands a JSON array down the pipeline as one object.
	$candidates = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in @($listing)) {
		$tagName = [string](Get-Field -Object $entry -Name 'tag_name')
		if (-not $tagName -or (Get-Field -Object $entry -Name 'draft') -eq $true) { continue }
		$key = Get-VersionKey -Tag $tagName
		if (-not $key) { continue }
		$candidates.Add([PSCustomObject]@{ Tag = $tagName; Key = $key; Pre = [bool](Get-Field -Object $entry -Name 'prerelease') })
	}
	if ($Release -eq 'stable') {
		$pick = Select-Newest -From @($candidates | Where-Object { -not $_.Pre })
		if (-not $pick) {
			$pick = Select-Newest -From $candidates.ToArray()
			if ($pick) { Write-Output '[ No stable release yet, so this takes the newest pre-release ]' }
		}
	} else {
		$pick = Select-Newest -From $candidates.ToArray()
	}
	if (-not $pick) { Exit-Install "couldn't determine the $Release release tag" }
	$tag = $pick.Tag
	$base = "https://github.com/$repo/releases/download/$tag"
	$url = "$base/$asset"

	## Already current? Then there is nothing to do. --version says
	## "convert-base-v2 v3.1.0 build dbrk8", and before 3.0.1 had no name in front.
	$haveVer = ''
	if (Test-Path -LiteralPath $destPath -PathType Leaf) {
		$haveVer = Get-ProgramVersion -Path $destPath
		$haveTag = (($haveVer -replace ('^' + [regex]::Escape($pkg) + ' '), '') -split ' ')[0]
		if ($haveTag -ceq $tag) {
			Write-Output "[ $destPath is already $tag; nothing to do ]"
			Write-Output ''
			return
		}
	}

	$pathMissing = $false
	if ($pathScope) { $pathMissing = -not (Test-PathEntry -Scope $pathScope -Dir $destDir) }

	Write-Output ''
	Write-Output '[ Plan ]'
	Write-Output "    Release: $tag ($Release)"
	Write-Output "    Download: $url"
	Write-Output "    Verify: sha256 against the release's checksums.txt"
	if (Test-Path -LiteralPath $destPath -PathType Leaf) {
		$was = if ($haveVer) { $haveVer } else { 'an unknown version' }
		Write-Output "    Install: $destPath (replacing $was)"
	} else {
		Write-Output "    Install: $destPath"
	}
	if ($onWindows -and (Test-Path -LiteralPath (Join-Path -Path $destDir -ChildPath 'uninstall.exe'))) {
		Write-Output '    The setup .exe installed the copy there. Add/Remove Programs keeps showing its version.'
	}
	if ($pathMissing) { Write-Output "    PATH: adds $destDir to the $($pathScope.ToLower()) PATH" }
	if ($useSudo) { Write-Output '    Uses sudo for the final copy.' }
	Write-Output ''

	if (-not $Yes) {
		## No answer, a closed stdin, or a shell that can't prompt all read as no.
		$answer = ''
		try { $answer = [string](Read-Host -Prompt 'Proceed? [y/N]') } catch { $answer = '' }
		if ($answer -notmatch '^\s*(y|yes)\s*$') {
			Write-Output '[ aborted; nothing was touched ]'
			Write-Output ''
			if ($invokedAsFile) { exit 1 }
			return
		}
		Write-Output ''
	}

	if (-not $useSudo) {
		$problem = Test-InstallTarget -Dir $destDir -Exe $destPath
		if ($problem) {
			if ($onWindows -and $Target -eq 'system') { Exit-Install $problem }
			if ($onWindows) { Exit-Install "$problem (is the folder read-only, or is antivirus blocking it?)" }
			Exit-Install "$problem (check the folder's owner and mode)"
		}
	}

	$work = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('cbv2-install-' + [IO.Path]::GetRandomFileName())
	$null = New-Item -ItemType Directory -Path $work
	try {
		$download = Join-Path -Path $work -ChildPath $asset
		$sums = Join-Path -Path $work -ChildPath 'checksums.txt'

		Write-Output "[ Downloading $asset $tag ]"
		try { Invoke-WebRequest -Uri $url -OutFile $download -UseBasicParsing } catch { Exit-Install "download failed: $url ($(Get-WebFailure -ErrorRecord $_))" }
		try { Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile $sums -UseBasicParsing } catch { Exit-Install "download failed: checksums.txt for $tag ($(Get-WebFailure -ErrorRecord $_))" }

		Write-Output '[ Verifying checksum ]'
		## Matched on the whole name, since one asset name can hold another.
		$want = $null
		foreach ($line in [IO.File]::ReadAllLines($sums)) {
			$m = [regex]::Match($line, '^([0-9A-Fa-f]{64}) [ *](.+)$')
			if ($m.Success -and $m.Groups[2].Value -ceq $asset) { $want = $m.Groups[1].Value.ToLowerInvariant(); break }
		}
		if (-not $want) { Exit-Install "no checksum for $asset in checksums.txt" }
		$got = (Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash.ToLowerInvariant()
		if ($got -ne $want) { Exit-Install "checksum mismatch (expected $want, got $got)" }

		Write-Output "[ Installing to $destPath ]"
		if ($useSudo) {
			& sudo install -m 0755 $download $destPath
			if ($LASTEXITCODE -ne 0) { Exit-Install "sudo install failed, exit $LASTEXITCODE" }
		} else {
			## Staged beside it, then renamed over, so nothing ever runs a half copy.
			$staged = Join-Path -Path $destDir -ChildPath ".$exeName.new"
			try {
				$null = New-Item -ItemType Directory -Force -Path $destDir
				Copy-Item -LiteralPath $download -Destination $staged -Force
				if (-not $onWindows) {
					& chmod 0755 $staged
					if ($LASTEXITCODE -ne 0) { throw "chmod failed, exit $LASTEXITCODE" }
				}
				Move-Item -LiteralPath $staged -Destination $destPath -Force
			} catch {
				$ex = $_.Exception
				while ($ex.InnerException) { $ex = $ex.InnerException }
				Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
				Exit-Install "couldn't write $destPath - $($ex.Message)"
			}
		}

		if ($pathMissing) {
			Add-PathEntry -Scope $pathScope -Dir $destDir
			Write-Output "[ Added $destDir to the $($pathScope.ToLower()) PATH ]"
			## Tell Explorer, so shells started from it get the new PATH.
			try {
				$sig = '[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
				$user32 = Add-Type -MemberDefinition $sig -Name 'Cbv2EnvBroadcast' -Namespace 'Win32' -PassThru
				$sent = [UIntPtr]::Zero
				$null = $user32::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$sent)
			} catch {
				Write-Output '[ NOTE: open a new shell to pick up the PATH change ]'
			}
		}
		## This shell too, when the one-liner ran in it.
		if ($pathScope -and -not ((([string]$env:Path) -split ';') -contains $destDir)) {
			$env:Path = ([string]$env:Path).TrimEnd(';') + ";$destDir"
		}

		$now = Get-ProgramVersion -Path $destPath
		if ($now) { Write-Output "[ Installed: $now ]" } else { Write-Output "[ Installed: $destPath, though it didn't answer --version ]" }
		if (-not $onWindows -and -not ((([string]$env:PATH) -split ':') -contains $destDir)) {
			Write-Output "[ NOTE: $destDir isn't in your PATH ]"
		}
		$first = Get-Command -Name $pkg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($first -and $first.Source -ne $destPath) {
			Write-Output "[ NOTE: $pkg on your PATH is $($first.Source), which comes first ]"
		}
		Write-Output ''
	} finally {
		## Only the one folder made above, under the temp folder it named, and never through a link.
		$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
		$workItem = Get-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
		$inTemp = ([IO.Path]::GetFullPath($work)).StartsWith((Join-Path -Path $tempRoot -ChildPath 'cbv2-install-'), [StringComparison]::Ordinal)
		if ($inTemp -and $workItem -and $workItem.PSIsContainer -and -not ($workItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
			Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
} $Release $Target $Yes $Version $Help ($MyInvocation.MyCommand -is [Management.Automation.ExternalScriptInfo] -and $MyInvocation.MyCommand.Path -eq $PSCommandPath)
