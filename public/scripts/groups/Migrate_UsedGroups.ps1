param(
    [string]$SrcTenantId,
    [string]$SrcClientId,
    [string]$SrcClientSecret,
    [string]$DstTenantId,
    [string]$DstClientId,
    [string]$DstClientSecret
)

$AssignmentsPath = Join-Path $PSScriptRoot "GoldenTenant_Backup\Assignments\PolicyAssignments.json"
$GroupMappingPath = Join-Path $PSScriptRoot "GroupMapping.json"

if (-not $SrcTenantId -or -not $SrcClientId -or -not $SrcClientSecret -or
    -not $DstTenantId -or -not $DstClientId -or -not $DstClientSecret) {
    Write-Host "[FOUT] Vul alle credentials in (SrcTenantId, SrcClientId, SrcClientSecret, DstTenantId, DstClientId, DstClientSecret)." -ForegroundColor Red
    exit 1
}

function Get-Token($TenantId, $ClientId, $ClientSecret) {
    $TR = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{ grant_type="client_credentials"; client_id=$ClientId; client_secret=$ClientSecret; scope="https://graph.microsoft.com/.default" }
    return @{ "Authorization" = "Bearer $($TR.access_token)" }
}

Write-Host "Verbinden met brontenant..." -ForegroundColor Yellow
$SrcH = Get-Token $SrcTenantId $SrcClientId $SrcClientSecret
Write-Host "Verbonden met brontenant $SrcTenantId" -ForegroundColor Green

Write-Host "Verbinden met doeltenant..." -ForegroundColor Yellow
$DstH = Get-Token $DstTenantId $DstClientId $DstClientSecret
Write-Host "Verbonden met doeltenant $DstTenantId" -ForegroundColor Green

if (-not (Test-Path $AssignmentsPath)) {
    Write-Host "[FOUT] PolicyAssignments.json niet gevonden: $AssignmentsPath" -ForegroundColor Red
    exit 1
}

$Assignments  = Get-Content $AssignmentsPath -Raw | ConvertFrom-Json
$UniqueGroupIds = $Assignments | Select-Object -ExpandProperty GroupId -Unique
Write-Host "Unieke groepen in gebruik: $($UniqueGroupIds.Count)" -ForegroundColor Cyan

$GroupMapping = @{}
if (Test-Path $GroupMappingPath) {
    $Existing = Get-Content $GroupMappingPath -Raw | ConvertFrom-Json
    foreach ($Prop in $Existing.PSObject.Properties) { $GroupMapping[$Prop.Name] = $Prop.Value }
    Write-Host "Bestaande GroupMapping: $($GroupMapping.Count) entries" -ForegroundColor Gray
}

$Success = 0; $Skipped = 0; $Failed = 0

foreach ($GroupId in $UniqueGroupIds) {
    if ($GroupMapping.ContainsKey($GroupId)) {
        Write-Host "[SKIP] Al gemapped: $GroupId" -ForegroundColor Gray
        $Skipped++; continue
    }

    try {
        $SrcGroup = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId" -Headers $SrcH
    } catch {
        Write-Host "[FOUT] Kan groep niet ophalen: $GroupId" -ForegroundColor Red
        $Failed++; continue
    }

    Write-Host "Migreren: $($SrcGroup.displayName)" -ForegroundColor Yellow

    # Controleer of al bestaat in doeltenant
    try {
        $SafeName = $SrcGroup.displayName -replace "'", "''"
        $Search = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$SafeName'" -Headers $DstH
        if ($Search.value.Count -gt 0) {
            Write-Host "[BESTAAND] $($SrcGroup.displayName) -> $($Search.value[0].id)" -ForegroundColor Cyan
            $GroupMapping[$GroupId] = $Search.value[0].id
            $Success++; continue
        }
    } catch {}

    $NewGroup = @{
        displayName     = $SrcGroup.displayName
        mailEnabled     = $false
        mailNickname    = ($SrcGroup.displayName -replace '[^a-zA-Z0-9]', '')
        securityEnabled = $true
    }
    if ($SrcGroup.description) { $NewGroup["description"] = $SrcGroup.description }

    if ($SrcGroup.groupTypes -contains "DynamicMembership") {
        $NewGroup["groupTypes"]                   = @("DynamicMembership")
        $NewGroup["membershipRule"]               = $SrcGroup.membershipRule
        $NewGroup["membershipRuleProcessingState"] = "On"
    }

    try {
        $DstH2 = $DstH + @{"Content-Type" = "application/json"}
        $Created = Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Headers $DstH2 -Body ($NewGroup | ConvertTo-Json -Depth 10)
        $GroupMapping[$GroupId] = $Created.id
        Write-Host "[OK] $($SrcGroup.displayName) -> $($Created.id)" -ForegroundColor Green
        $Success++
    } catch {
        $ErrMsg = if ($_.ErrorDetails.Message) {
            try { ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch { $_.ErrorDetails.Message }
        } else { $_.Exception.Message }
        Write-Host "[FOUT] $($SrcGroup.displayName): $ErrMsg" -ForegroundColor Red
        $Failed++
    }
}

$GroupMapping | ConvertTo-Json -Depth 5 | Out-File $GroupMappingPath -Encoding utf8 -Force
Write-Host "GroupMapping opgeslagen: $($GroupMapping.Count) entries" -ForegroundColor Gray
Write-Host "Klaar! Succes: $Success | Overgeslagen: $Skipped | Fouten: $Failed" -ForegroundColor Cyan