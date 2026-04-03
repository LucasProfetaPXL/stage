param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret
)

Write-Host "--- Starten Assignments Export ---" -ForegroundColor Cyan

# 1. Veilige .NET Verbinding
try {
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

    # GEFIXT: Connect-MgGraph gebruiken in plaats van Beta variant
    Connect-MgGraph -AccessToken $SecureToken -NoWelcome
    Write-Host "[OK] Verbonden met Bron Tenant: $TenantId" -ForegroundColor Green
} catch {
    Write-Host "[FOUT] Verbinding mislukt: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# 2. Paden instellen
$CurrentDir = $PSScriptRoot
$ExportPath = Join-Path $CurrentDir "GoldenTenant_Backup\Assignments"
if (!(Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }

# 3. Assignments ophalen
Write-Host "Bezig met ophalen van Intune Policy Assignments..." -ForegroundColor Yellow
$AssignmentList = New-Object System.Collections.Generic.List[PSObject]

try {
    $Policies = Get-MgBetaDeviceManagementConfigurationPolicy -All
    foreach ($Policy in $Policies) {
        Write-Host "Exporteren: $($Policy.DisplayName)" -ForegroundColor Gray
        $Assignments = Get-MgBetaDeviceManagementConfigurationPolicyAssignment -DeviceManagementConfigurationPolicyId $Policy.Id
        foreach ($Asg in $Assignments) {
            $GroupId = $Asg.Target.AdditionalProperties.groupId
            if ($GroupId) {
                $AssignmentList.Add([pscustomobject]@{
                    PolicyName = $Policy.DisplayName
                    PolicyId   = $Policy.Id
                    GroupId    = $GroupId
                    TargetType = "Group"
                })
            }
        }
    }
} catch {
    Write-Host "[FOUT] Kon assignments niet ophalen: $($_.Exception.Message)" -ForegroundColor Red
}

$OutputFile = Join-Path $ExportPath "PolicyAssignments.json"
$AssignmentList | ConvertTo-Json -Depth 10 | Set-Content $OutputFile -Force
Write-Host "`n[KLAAR] $($AssignmentList.Count) assignments opgeslagen." -ForegroundColor Yellow