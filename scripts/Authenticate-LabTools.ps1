# Compatibility wrapper for the newer authentication helper.
$scriptPath = Join-Path $PSScriptRoot 'Connect-AzureAndGitHub.ps1'
if (-not (Test-Path $scriptPath)) {
    Write-Error "Missing helper script: $scriptPath"
    exit 1
}

& $scriptPath @args
