<#
	PSScriptAnalyzer settings for the PowerShell files here. Kept in a file so a
	run by hand gets the same answer the pipeline does.
#>
@{
	Severity = @('Error', 'Warning')

	Rules = @{
		## The installer has to run on the Windows PowerShell that ships with
		## Windows, not just on 7. This covers syntax only, not which .NET
		## members exist, so $IsWindows and friends still need a version test.
		PSUseCompatibleSyntax = @{
			Enable         = $true
			TargetVersions = @('5.1', '7.0')
		}
		PSUseConsistentIndentation = @{
			Enable              = $true
			Kind                = 'tab'
			PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
		}
	}
}
