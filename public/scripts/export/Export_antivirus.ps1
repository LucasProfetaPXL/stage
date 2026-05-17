param(
    [string]$BackupDir = "",

    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

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
$ExportPath = [System.IO.Path]::GetFullPath((Join-Path $MainBackupDir "Antivirus"))
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

Write-Host "Backup map: $ExportPath" -ForegroundColor Gray
Write-Host "Ophalen van Antivirus configurationPolicies..." -ForegroundColor Yellow

$AntivirusPolicies = @()
$Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"

do {
    $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri
    # FILTER HIER: Alleen policies die behoren tot de Antivirus familie
    $Filtered = $Response.value | Where-Object { 
        $_.templateReference.templateFamily -eq "endpointSecurityAntivirus" -or 
        $_.name -like "*Defender*" -or 
        $_.name -like "*Antivirus*"
    }
    $AntivirusPolicies += $Filtered
    $Uri = $Response.'@odata.nextLink'
} while ($Uri)

Write-Host "Totaal gevonden (gefilterd): $($AntivirusPolicies.Count) policies" -ForegroundColor Cyan
$AntivirusPolicies | ForEach-Object { Write-Host "  - $($_.name) [Family: $($_.templateReference.templateFamily)]" -ForegroundColor Gray }

foreach ($Policy in $AntivirusPolicies) {
    $AllSettings = @()
    $SettingsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($Policy.id)/settings"
    do {
        $SR = Invoke-MgGraphRequest -Method GET -Uri $SettingsUri
        $AllSettings += $SR.value
        $SettingsUri = $SR.'@odata.nextLink'
    } while ($SettingsUri)

    $ExportObject = [ordered]@{
        "name"              = $Policy.name
        "description"       = if ($Policy.description) { $Policy.description } else { "" }
        "platforms"         = $Policy.platforms
        "technologies"      = $Policy.technologies
        "templateReference" = @{
            "templateId"     = $Policy.templateReference.templateId
            "templateFamily" = $Policy.templateReference.templateFamily
        }
        "settings" = @(foreach ($s in $AllSettings) { @{ "settingInstance" = $s.settingInstance } })
    }

    $SafeName = ($Policy.name -replace '[\\/:*?"<>|]', '_') + ".json"
    $ExportObject | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $ExportPath $SafeName) -Encoding utf8 -Force
    Write-Host "[OK] $SafeName" -ForegroundColor Green
}

Write-Host "`nKlaar! $($AntivirusPolicies.Count) Antivirus policies geexporteerd." -ForegroundColor Yellow