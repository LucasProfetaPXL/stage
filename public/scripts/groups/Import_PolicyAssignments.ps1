param(
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$ClientSecret
)

Write-Host "--- Starten Assignments Herstel ---" -ForegroundColor Cyan

$TR = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ grant_type="client_credentials"; client_id=$ClientId; client_secret=$ClientSecret; scope="https://graph.microsoft.com/.default" }

$H = @{ "Authorization" = "Bearer $($TR.access_token)"; "Content-Type" = "application/json" }
Write-Host "[OK] Verbonden met doeltenant." -ForegroundColor Green

$CurrentDir    = $PSScriptRoot
$ParentDir     = Split-Path $CurrentDir -Parent
$GroupMapPath  = Join-Path $CurrentDir "GroupMapping.json"
$PolicyMapPath = Join-Path $ParentDir  "import\PolicyMapping.json"
$AsgFilePath   = Join-Path $CurrentDir "GoldenTenant_Backup\Assignments\PolicyAssignments.json"

# Laden
$GroupMapping  = @{}
$PolicyMapping = @{}

(Get-Content $GroupMapPath  -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $GroupMapping[$_.Name.ToLower()]  = $_.Value }
(Get-Content $PolicyMapPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $PolicyMapping[$_.Name.ToLower()] = $_.Value }

$Assignments = Get-Content $AsgFilePath -Raw | ConvertFrom-Json

Write-Host "Groepen gemapped: $($GroupMapping.Count) | Policies gemapped: $($PolicyMapping.Count)" -ForegroundColor Yellow

# Filter: alleen assignments waar BEIDE gemapped zijn
$ToProcess = $Assignments | Where-Object {
    $GroupMapping[$_.GroupId.ToLower()] -and $PolicyMapping[$_.PolicyId.ToLower()]
}

Write-Host "Assignments na filter: $($ToProcess.Count) van $($Assignments.Count)" -ForegroundColor Cyan

$Success = 0; $Failed = 0

foreach ($Asg in $ToProcess) {
    $NewGroupId  = $GroupMapping[$Asg.GroupId.ToLower()]
    $NewPolicyId = $PolicyMapping[$Asg.PolicyId.ToLower()]

    # Endpoint bepalen: T_ prefix = security baseline (intents), anders configurationPolicies
    if ($NewPolicyId.StartsWith("T_")) {
        $PolicyGuid = $NewPolicyId.Substring(2)
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/intents/$PolicyGuid/assign"
        $Payload = @{ assignments = @(@{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $NewGroupId } }) } | ConvertTo-Json -Depth 10
    } else {
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$NewPolicyId/assign"
        $Payload = @{ assignments = @(@{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $NewGroupId } }) } | ConvertTo-Json -Depth 10
    }

    try {
        Invoke-RestMethod -Method POST -Uri $Uri -Headers $H -Body $Payload -ErrorAction Stop | Out-Null
        Write-Host "[OK] $($Asg.PolicyName) -> $NewGroupId" -ForegroundColor Green
        $Success++
    } catch {
        $ErrMsg = try { ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch { $_.Exception.Message }
        Write-Host "[FOUT] $($Asg.PolicyName): $ErrMsg" -ForegroundColor Red
        $Failed++
    }
}

Write-Host "`nKlaar! Succes: $Success | Fouten: $Failed" -ForegroundColor Cyan