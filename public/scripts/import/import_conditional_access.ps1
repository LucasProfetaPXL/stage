param(
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret,
    [string]$SelectedFiles = "",
    [string]$RenameMap = ""
)

function Get-AuthHeader {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    $Token = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
        }
    return @{
        Header    = @{ "Authorization" = "Bearer $($Token.access_token)"; "Content-Type" = "application/json" }
        ExpiresAt = (Get-Date).AddSeconds($Token.expires_in - 60)
    }
}

$Auth = Get-AuthHeader -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
Write-Host "Verbonden met tenant $TenantId" -ForegroundColor Green

$BackupDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\export\GoldenTenant_Backup\ConditionalAccess"))
if (!(Test-Path $BackupDir)) {
    Write-Host "[FOUT] Backup map niet gevonden: $BackupDir" -ForegroundColor Red
    exit 1
}

$MappingFilePath = Join-Path $PSScriptRoot "PolicyMapping.json"
$PolicyMapping = @{}
if (Test-Path $MappingFilePath) {
    $Raw = Get-Content $MappingFilePath -Raw | ConvertFrom-Json
    foreach ($p in $Raw.PSObject.Properties) { $PolicyMapping[$p.Name] = $p.Value }
}

$AllFiles = Get-ChildItem -Path $BackupDir -Filter "*.json"
if (-not [string]::IsNullOrWhiteSpace($SelectedFiles)) {
    $SelectedList = $SelectedFiles -split ","
    $Files = $AllFiles | Where-Object { $_.Name -in $SelectedList }
    Write-Host "Geselecteerd: $($Files.Count) van $($AllFiles.Count) bestanden" -ForegroundColor Cyan
} else {
    $Files = $AllFiles
    Write-Host "Alle $($Files.Count) bestanden worden geimporteerd" -ForegroundColor Cyan
}

# Mapping van bekende ingebouwde authenticationStrength namen naar IDs
$StrengthMap = @{
    "Multifactor authentication" = "00000000-0000-0000-0000-000000000002"
    "Passwordless MFA"           = "00000000-0000-0000-0000-000000000003"
    "Phishing-resistant MFA"     = "00000000-0000-0000-0000-000000000004"
}

$SuccessCount = 0
$ErrorCount   = 0

foreach ($File in $Files) {
    try {
        # Vernieuw token als het bijna verlopen is
        if ((Get-Date) -ge $Auth.ExpiresAt) {
            Write-Host "[INFO] Token vernieuwen..." -ForegroundColor Gray
            $Auth = Get-AuthHeader -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        }

        $RawContent = Get-Content $File.FullName -Raw -Encoding UTF8
        if ($RawContent[0] -eq [char]0xFEFF) { $RawContent = $RawContent.Substring(1) }

        # Haal _sourceId op voor mapping
        $BodyObj = $RawContent | ConvertFrom-Json
        $OldId   = $BodyObj._sourceId

        # Verwijder read-only velden
        $Body = $RawContent `
            -replace ',?\s*"_sourceId"\s*:\s*"[^"]*"', '' `
            -replace ',?\s*"policyType"\s*:\s*"[^"]*"', '' `
            -replace ',?\s*"createdDateTime"\s*:\s*"[^"]*"', '' `
            -replace ',?\s*"modifiedDateTime"\s*:\s*"[^"]*"', ''

        # Fix authenticationStrength: vervang door ID-referentie
        $BodyObj = $Body | ConvertFrom-Json
        if ($BodyObj.grantControls -and $BodyObj.grantControls.authenticationStrength) {
            $as   = $BodyObj.grantControls.authenticationStrength
            $name = $as.displayName
            $sid  = if ($name -and $StrengthMap.ContainsKey($name)) { $StrengthMap[$name] } else { "00000000-0000-0000-0000-000000000002" }
            $BodyObj.grantControls.PSObject.Properties.Remove("authenticationStrength")
            $BodyObj.grantControls | Add-Member -NotePropertyName "authenticationStrength" -NotePropertyValue @{ "id" = $sid }
            $Body = $BodyObj | ConvertTo-Json -Depth 100 -Compress
        }

        Write-Host "Importeren: $($File.BaseName)..." -ForegroundColor White

        $Response = Invoke-RestMethod -Method POST `
            -Uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" `
            -Headers $Auth.Header -Body $Body -ErrorAction Stop

        if ($OldId -and $Response.id) { $PolicyMapping[[string]$OldId] = [string]$Response.id }
        Write-Host "[OK] $($File.BaseName)" -ForegroundColor Green
        $SuccessCount++

    } catch {
        $ErrMsg = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Host "[FOUT] $($File.BaseName): $ErrMsg" -ForegroundColor Red
        $ErrorCount++
    }
}

$PolicyMapping | ConvertTo-Json | Set-Content $MappingFilePath -Force
Write-Host "PolicyMapping.json bijgewerkt: $($PolicyMapping.Count) entries." -ForegroundColor Cyan
Write-Host "Klaar! Succes: $SuccessCount | Fouten: $ErrorCount" -ForegroundColor Yellow