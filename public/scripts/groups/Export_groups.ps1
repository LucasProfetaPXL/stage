param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret
)

# Debug output om te zien wat de server precies doorgeeft
Write-Host "--- Starten van Groep Export ---" -ForegroundColor Cyan
Write-Host "TenantId: $TenantId" -ForegroundColor Gray
Write-Host "ClientId: $ClientId" -ForegroundColor Gray

# Controleer of we de minimale info hebben om te verbinden
if ([string]::IsNullOrWhiteSpace($TenantId)) {
    Write-Host "[FOUT] Geen TenantId ontvangen. Controleer de HTML input ID's." -ForegroundColor Red
    return
}

# Authenticatie logica
if (![string]::IsNullOrWhiteSpace($ClientSecret) -and ![string]::IsNullOrWhiteSpace($ClientId)) {
    # Headless mode (Docker/Service Principal)
    Write-Host "Verbinding maken via App Registration (Secret)..." -ForegroundColor Yellow
    $TokenResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
        }

    # Probeer eerst SDK v2+ (plain string), val terug op handmatige SecureString
    try {
        Connect-MgGraph -AccessToken $TokenResponse.access_token -NoWelcome
    } catch {
        Write-Host "Plain string niet ondersteund, SecureString wordt gebouwd..." -ForegroundColor Yellow
        $SecureToken = [System.Security.SecureString]::new()
        foreach ($char in $TokenResponse.access_token.ToCharArray()) {
            $SecureToken.AppendChar($char)
        }
        $SecureToken.MakeReadOnly()
        Connect-MgGraph -AccessToken $SecureToken -NoWelcome
    }
} else {
    # Interactieve mode (Popup)
    Write-Host "Verbinding maken via interactieve login (Popup)..." -ForegroundColor Yellow
    Set-MgGraphOption -DisableLoginByWAM $true
    Connect-MgGraph -TenantId $TenantId -Scopes "Group.Read.All" -NoWelcome
}

# Export pad instellen
$ExportPath = Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup\Groups"
$ExportPath = [System.IO.Path]::GetFullPath($ExportPath)
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

Write-Host "Backup map: $ExportPath" -ForegroundColor Gray
Write-Host "Ophalen van groepen..." -ForegroundColor Yellow

# Haal alle groepen op
$AllGroups = Get-MgGroup -All -Property "id,displayName,description,groupTypes,mailEnabled,mailNickname,securityEnabled,membershipRule,membershipRuleProcessingState,visibility"

Write-Host "Gevonden: $($AllGroups.Count) groepen" -ForegroundColor Cyan

foreach ($Group in $AllGroups) {
    # Bouw het object voor export
    $ExportObj = [ordered]@{
        "displayName"                   = $Group.DisplayName
        "description"                   = if ($Group.Description) { $Group.Description } else { "" }
        "groupTypes"                    = $Group.GroupTypes
        "mailEnabled"                   = $Group.MailEnabled
        "mailNickname"                  = if ($Group.MailNickname) { $Group.MailNickname } else { ($Group.DisplayName -replace '[^a-zA-Z0-9]', '') }
        "securityEnabled"               = $Group.SecurityEnabled
        "visibility"                    = if ($Group.Visibility) { $Group.Visibility } else { "Private" }
        "membershipRule"                = $Group.MembershipRule
        "membershipRuleProcessingState" = $Group.MembershipRuleProcessingState
        # Bewaar de bron ID voor de latere mapping stap
        "_sourceId"                     = $Group.Id
    }

    $SafeName = ($Group.DisplayName -replace '[\\/:*?"<>|]', '_') + ".json"
    $ExportObj | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ExportPath $SafeName) -Encoding utf8 -Force
    Write-Host "[OK] $($Group.DisplayName)" -ForegroundColor Green
}

Write-Host "`nKlaar! $($AllGroups.Count) groepen geëxporteerd." -ForegroundColor Yellow