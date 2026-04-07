param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,

    [string]$BackupDir = "",
    [string]$SelectedFiles = "",

    [string]$RenameMap = "{}"
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

# Backup map — scripts zitten in import/, backup in export/GoldenTenant_Backup/
$BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\EndpointPrivilegeManagement"
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)

if (!(Test-Path $BackupDir)) {
    Write-Host "[FOUT] Backup map niet gevonden: $BackupDir" -ForegroundColor Red
    Write-Host "Voer eerst de Export en Fix JSON stap uit." -ForegroundColor Yellow
    exit 1
}


$MappingFilePath = Join-Path $PSScriptRoot "PolicyMapping.json"
$PolicyMapping = @{}
if (Test-Path $MappingFilePath) {
    $RawMapping = Get-Content $MappingFilePath -Raw | ConvertFrom-Json
    foreach ($prop in $RawMapping.PSObject.Properties) { $PolicyMapping[$prop.Name] = $prop.Value }
}

$AllFiles = Get-ChildItem -Path $BackupDir -Filter "*.json"

# Filter op selectie indien opgegeven
if (-not [string]::IsNullOrWhiteSpace($SelectedFiles)) {
    $SelectedList = $SelectedFiles -split ','
    $Files = $AllFiles | Where-Object { $_.Name -in $SelectedList }
    Write-Host "Geselecteerd: $($Files.Count) van $($AllFiles.Count) bestanden" -ForegroundColor Cyan
} else {
    $Files = $AllFiles
    Write-Host "Alle $($Files.Count) bestanden worden geimporteerd" -ForegroundColor Cyan
}

$SuccessCount = 0
$ErrorCount   = 0

# Verwerk herbenoemingen
$RenameDict = @{}
if (-not [string]::IsNullOrWhiteSpace($RenameMap) -and $RenameMap -ne "{}") {
    try {
        $Parsed = $RenameMap | ConvertFrom-Json
        foreach ($Prop in $Parsed.PSObject.Properties) {
            $RenameDict[$Prop.Name] = $Prop.Value
        }
        Write-Host "Herbenoemingen: $($RenameDict.Count)" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] RenameMap kon niet worden geparsed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}


foreach ($File in $Files) {
    try {
        if ((Get-Date) -ge $Auth.ExpiresAt) {
            Write-Host "[INFO] Token vernieuwen..." -ForegroundColor Gray
            $Auth = Get-AuthHeader -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        }

        $RawContent = Get-Content $File.FullName -Raw -Encoding UTF8
        if ($RawContent[0] -eq [char]0xFEFF) { $RawContent = $RawContent.Substring(1) }
        
        $TempObj = $RawContent | ConvertFrom-Json
        $OldId = $TempObj._sourceId

        # Pas hernoeming toe indien opgegeven
        if ($RenameDict.ContainsKey($File.Name)) {
            $NewName = $RenameDict[$File.Name]
            $TempObj = $RawContent | ConvertFrom-Json
            if ($TempObj.PSObject.Properties["displayName"]) { $TempObj.displayName = $NewName }
            if ($TempObj.PSObject.Properties["name"])        { $TempObj.name        = $NewName }
            $RawContent = $TempObj | ConvertTo-Json -Depth 100
            Write-Host "  Hernoemd naar: $NewName" -ForegroundColor Yellow
        }

        # Stuur de JSON direct door (al gefixte structuur)
        $Body = $RawContent

        $Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        Write-Host "Importeren: $($File.BaseName)..." -ForegroundColor White

        $Response = Invoke-RestMethod -Method POST -Uri $Uri -Headers $Auth.Header -Body $Body -ErrorAction Stop

        if ($OldId -and $Response.id) { $PolicyMapping[[string]$OldId] = [string]$Response.id }
        Write-Host "[OK] $($File.BaseName)" -ForegroundColor Green
        $SuccessCount++

    } catch {
        $ErrorMsg = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Host "[FOUT] $($File.Name): $ErrorMsg" -ForegroundColor Red
        $ErrorCount++
    }
}

$PolicyMapping | ConvertTo-Json | Set-Content $MappingFilePath -Force
Write-Host "PolicyMapping.json bijgewerkt: $($PolicyMapping.Count) entries." -ForegroundColor Cyan
Write-Host "`nKlaar! Succes: $SuccessCount | Fouten: $ErrorCount" -ForegroundColor Yellow