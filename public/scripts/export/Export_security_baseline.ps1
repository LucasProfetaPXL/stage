param(
    [string]$BackupDir = "",

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

$MainBackupDir = if ($BackupDir -ne "") { $BackupDir } else { Join-Path $PSScriptRoot "GoldenTenant_Backup" }
$ExportPath = [System.IO.Path]::GetFullPath((Join-Path $MainBackupDir "SecurityBaselines"))
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

Write-Host "Backup map: $ExportPath" -ForegroundColor Gray
Write-Host "Ophalen van Security Baselines..." -ForegroundColor Yellow

try {
    $Baselines = Get-MgBetaDeviceManagementIntent -All
    Write-Host "Gevonden: $($Baselines.Count)" -ForegroundColor Cyan

    foreach ($Baseline in $Baselines) {
        $RawName = if ($Baseline.DisplayName) { $Baseline.DisplayName } else { $Baseline.Id }
        $SafeName = ($RawName -replace '[^a-zA-Z0-9]', '_') + ".json"

        $FullSettings = Get-MgBetaDeviceManagementIntentSetting -DeviceManagementIntentId $Baseline.Id -All
        $FullObject = [PSCustomObject]@{
            "displayName" = $Baseline.DisplayName
            "description" = $Baseline.Description
            "templateId"  = $Baseline.TemplateId
            "settings"    = $FullSettings
        }

        $FullObject | ConvertTo-Json -Depth 50 | Out-File (Join-Path $ExportPath $SafeName) -Encoding utf8
        Write-Host "[OK] $SafeName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FOUT] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nKlaar! $($Baselines.Count) baselines geëxporteerd." -ForegroundColor Yellow