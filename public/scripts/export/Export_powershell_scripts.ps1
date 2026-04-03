param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

# Modules vooraf laden (sneller dan auto-import)
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue

$TokenResponse = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

$Global:MgToken = $TokenResponse.access_token
$SecureToken = [System.Security.SecureString]::new()
foreach ($char in $Global:MgToken.ToCharArray()) { $SecureToken.AppendChar($char) }
Connect-MgGraph -AccessToken $SecureToken -NoWelcome

Write-Host "Ophalen van Platform Scripts..." -ForegroundColor Yellow

try {
    $Scripts = Get-MgBetaDeviceManagementScript -All
    Write-Host "Platform Scripts gevonden: $($Scripts.Count)" -ForegroundColor Cyan

    foreach ($Script in $Scripts) {
        $SafeName = ($Script.DisplayName -replace '[^a-zA-Z0-9]', '_') + ".json"
        $Script | ConvertTo-Json -Depth 50 | Out-File (Join-Path $PlatformPath $SafeName) -Encoding utf8
        Write-Host "[OK] $SafeName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FOUT Platform Scripts] $($_.Exception.Message)" -ForegroundColor Red
}

# ── Remediations (deviceHealthScripts) ───────────────────────
$RemediationPath = Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup\Remediations"
$RemediationPath = [System.IO.Path]::GetFullPath($RemediationPath)
if (!(Test-Path $RemediationPath)) { New-Item -ItemType Directory -Path $RemediationPath -Force | Out-Null }

Write-Host "`nRemediations map: $RemediationPath" -ForegroundColor Gray
Write-Host "Ophalen van Remediations..." -ForegroundColor Yellow

try {
    $Remediations = Get-MgBetaDeviceManagementDeviceHealthScript -All
    Write-Host "Remediations gevonden: $($Remediations.Count)" -ForegroundColor Cyan

    foreach ($Remediation in $Remediations) {
        $SafeName = ($Remediation.DisplayName -replace '[^a-zA-Z0-9]', '_') + ".json"
        $Remediation | ConvertTo-Json -Depth 50 | Out-File (Join-Path $RemediationPath $SafeName) -Encoding utf8
        Write-Host "[OK] $SafeName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FOUT Remediations] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nKlaar! Platform Scripts: $($Scripts.Count) | Remediations: $($Remediations.Count)" -ForegroundColor Yellow