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

$ExportPath = Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup\DeviceConfigurations"
$ExportPath = [System.IO.Path]::GetFullPath($ExportPath)
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

Write-Host "Backup map: $ExportPath" -ForegroundColor Gray
Write-Host "Ophalen van Device Configurations..." -ForegroundColor Yellow

try {
    $Configs = Get-MgDeviceManagementDeviceConfiguration -All
    Write-Host "Gevonden: $($Configs.Count)" -ForegroundColor Cyan

    foreach ($Config in $Configs) {
        $RawName = if ($Config.DisplayName) { $Config.DisplayName } else { $Config.Id }
        $SafeName = ($RawName -replace '[^a-zA-Z0-9]', '_') + ".json"
        $Config | ConvertTo-Json -Depth 50 | Out-File (Join-Path $ExportPath $SafeName) -Encoding utf8
        Write-Host "[OK] $SafeName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FOUT] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nKlaar! $($Configs.Count) configuraties geexporteerd." -ForegroundColor Yellow