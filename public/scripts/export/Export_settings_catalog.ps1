param(
    [string]$BackupDir = "",
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret
)

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
$ExportPath = [System.IO.Path]::GetFullPath((Join-Path $MainBackupDir "SettingsCatalog"))
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

Write-Host "Backup map: $ExportPath" -ForegroundColor Gray
Write-Host "Ophalen van Settings Catalog policies..." -ForegroundColor Yellow

try {
    $Policies = Get-MgBetaDeviceManagementConfigurationPolicy -All | Where-Object {
        $_.TemplateReference.TemplateFamily -ne "endpointSecurityEndpointPrivilegeManagement"
    }
    Write-Host "Gevonden: $($Policies.Count)" -ForegroundColor Cyan

    foreach ($Policy in $Policies) {
        $RawName  = if ($Policy.Name) { $Policy.Name } else { $Policy.Id }
        $SafeName = ($RawName -replace '[^a-zA-Z0-9]', '_') + ".json"

        # Haal settings op via REST zodat we ruwe JSON krijgen zonder enum objecten
        $SettingsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($Policy.Id)/settings"
        $SettingsResponse = Invoke-MgGraphRequest -Method GET -Uri $SettingsUri
        $RawSettings = $SettingsResponse.value

        # Haal policy details op via REST voor correcte string waarden
        $PolicyUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($Policy.Id)"
        $RawPolicy = Invoke-MgGraphRequest -Method GET -Uri $PolicyUri

        $ExportObj = [ordered]@{
            "id"                = $RawPolicy.id
            "name"              = $RawPolicy.name
            "description"       = if ($RawPolicy.description) { $RawPolicy.description } else { "" }
            "platforms"         = $RawPolicy.platforms
            "technologies"      = $RawPolicy.technologies
            "templateReference" = $RawPolicy.templateReference
            "settings"          = @($RawSettings | ForEach-Object { @{ "settingInstance" = $_.settingInstance } })
        }

        $ExportObj | ConvertTo-Json -Depth 100 | Out-File (Join-Path $ExportPath $SafeName) -Encoding utf8
        Write-Host "[OK] $SafeName" -ForegroundColor Green
    }
} catch {
    Write-Host "[FOUT] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nKlaar! $($Policies.Count) policies geexporteerd." -ForegroundColor Yellow