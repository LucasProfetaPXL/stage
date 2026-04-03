param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret
)

Write-Host "--- Starten van Groep Import ---" -ForegroundColor Cyan
Write-Host "Doel TenantId: $TenantId" -ForegroundColor Gray

# 1. Authenticatie via .NET SecureString
try {
    if ($ClientId -and $ClientSecret) {
        Write-Host "Verbinding maken via App Registration..." -ForegroundColor Yellow

        $TokenParams = @{
            Method      = "POST"
            Uri         = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
            ContentType = "application/x-www-form-urlencoded"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = "https://graph.microsoft.com/.default"
            }
        }

        $TokenResponse = Invoke-RestMethod @TokenParams

        $SecureToken = New-Object System.Security.SecureString
        $TokenResponse.access_token.ToCharArray() | ForEach-Object { $SecureToken.AppendChar($_) }
        $SecureToken.MakeReadOnly()

        Connect-MgGraph -AccessToken $SecureToken -NoWelcome
        Write-Host "[OK] Verbonden met doeltenant." -ForegroundColor Green
    } else {
        Write-Host "[FOUT] ClientId of Secret ontbreekt." -ForegroundColor Red
        return
    }
} catch {
    Write-Host "[FOUT] Verbinding mislukt: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# 2. Paden bepalen
$BackupPath  = Join-Path $PSScriptRoot "GoldenTenant_Backup\Groups"
$MappingFile = Join-Path $PSScriptRoot "GroupMapping.json"

if (!(Test-Path $BackupPath)) {
    Write-Host "[FOUT] Backup map niet gevonden!" -ForegroundColor Red
    Write-Host "Gezocht op: $BackupPath" -ForegroundColor Gray
    return
}

Write-Host "[OK] Backup bestanden gevonden. Starten met verwerken..." -ForegroundColor Gray

# 3. Import & Mapping Logica
$Files        = Get-ChildItem -Path $BackupPath -Filter "*.json"
$GroupMapping = @{}

foreach ($File in $Files) {
    try {
        $GroupData = Get-Content $File.FullName -Raw | ConvertFrom-Json
        Write-Host "Verwerken: $($GroupData.displayName)..." -ForegroundColor White

        # Controleer of groep al bestaat (voorkom duplicaten)
        $ExistingGroup = Get-MgGroup -Filter "displayName eq '$($GroupData.displayName)'" -ErrorAction SilentlyContinue

        if ($ExistingGroup) {
            Write-Host "   - Bestaat al (ID: $($ExistingGroup.Id))" -ForegroundColor Gray
            $NewGroupId = $ExistingGroup.Id
        } else {
            # Basisparameters
            $NewGroupParams = @{
                DisplayName     = $GroupData.displayName
                MailEnabled     = $GroupData.mailEnabled
                SecurityEnabled = $GroupData.securityEnabled
                MailNickname    = $GroupData.mailNickname
                GroupTypes      = @($GroupData.groupTypes)
            }

            # Optioneel: description (mag niet leeg zijn)
            if (![string]::IsNullOrWhiteSpace($GroupData.description)) {
                $NewGroupParams.Description = $GroupData.description
            }

            # Dynamische groep: membershipRule is verplicht, maar alleen bij DynamicMembership
            if ($GroupData.groupTypes -contains "DynamicMembership") {
                $NewGroupParams.MembershipRule                = $GroupData.membershipRule
                $NewGroupParams.MembershipRuleProcessingState = if ($GroupData.membershipRuleProcessingState) { $GroupData.membershipRuleProcessingState } else { "On" }
            }

            $NewGroup   = New-MgGroup @NewGroupParams
            $NewGroupId = $NewGroup.Id
            Write-Host "   - Succesvol aangemaakt (ID: $NewGroupId)" -ForegroundColor Green
        }

        if ($GroupData._sourceId) {
            $GroupMapping[$GroupData._sourceId] = $NewGroupId
        }

    } catch {
        Write-Host "   - [FOUT] Kon $($File.Name) niet importeren: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4. Mapping opslaan voor Assignments stap
$GroupMapping | ConvertTo-Json | Set-Content $MappingFile -Force
Write-Host "`n[KLAAR] Mapping opgeslagen in: $MappingFile" -ForegroundColor Yellow
Write-Host "Je kunt nu de assignments (koppelingen) gaan herstellen." -ForegroundColor Cyan