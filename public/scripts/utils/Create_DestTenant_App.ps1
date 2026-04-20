param(
    [Parameter(Mandatory=$true)]
    [Alias('CustomerTenantId')]
    [string]$TenantId,
    [string]$AppName = "XylosMigration_Destination"
)

Write-Host "Verbinden met tenant $TenantId..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -UseDeviceCode

Write-Host "App aanmaken: $AppName" -ForegroundColor Cyan
$App = New-MgApplication -DisplayName $AppName
$SP  = New-MgServicePrincipal -AppId $App.AppId
Write-Host "App aangemaakt: $($App.AppId)" -ForegroundColor Green

$GraphAppId = "00000003-0000-0000-c000-000000000000"
$GraphSP = Get-MgServicePrincipal -Filter "AppId eq '$GraphAppId'"

# Application permissions (Role)
$AppRoles = @(
    "9785d16f-d89d-4f31-a06c-e09c5dd8bf09",  # Application.Read.All
    "7a6ee1e7-141e-4cec-ae74-d9db155731ff",  # DeviceManagementApps.Read.All
    "78145de6-330d-4800-a6ce-494ff2d33d07",  # DeviceManagementApps.ReadWrite.All
    "dc377aa6-52d8-4e23-b271-2a7ae04cedf3",  # DeviceManagementConfiguration.ReadWrite.All
    "243333ab-4d21-40cb-a475-36241daa0842",  # DeviceManagementManagedDevices.ReadWrite.All
    "06a5fe6d-c49d-46a7-b082-56b1b14103c7",  # DeviceManagementScripts.ReadWrite.All
    "62a82d76-70ea-41e2-9197-370581804d09",  # Group.ReadWrite.All
    "246dd0d5-5bd0-4def-940b-0421030a5b68",  # Policy.Read.All
    "01c0a623-fc9b-48e9-b794-0756f8e8f067",  # Policy.ReadWrite.ConditionalAccess
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4"# DeviceManagementServiceConfig.ReadWrite.All
)

# Delegated permissions (Scope)
$Scopes = @(
    "c79f8feb-a9db-4090-85f9-90d820caa0eb",  # Application.Read.All
    "78145de6-330d-4800-a6ce-494ff2d33d07",  # DeviceManagementApps.ReadWrite.All
    "dc377aa6-52d8-4e23-b271-2a7ae04cedf3",  # DeviceManagementConfiguration.ReadWrite.All
    "572fea84-0151-49b2-9301-11cb16974376",  # DeviceManagementRBAC.Read.All
    "5b567255-7703-4780-807c-7be8301ae99b",  # Group.Read.All
    "7427e0e9-2fba-42fe-b0c0-848c9e6a8182",  # offline_access
    "741f803b-c850-494e-b5df-cde7c675a1ca"# Policy.ReadWrite.ConditionalAccess
)

$ResourceAccess = @()
foreach ($Id in ($AppRoles | Select-Object -Unique)) {
    $ResourceAccess += @{ Id = $Id; Type = "Role" }
}
foreach ($Id in ($Scopes | Select-Object -Unique)) {
    $ResourceAccess += @{ Id = $Id; Type = "Scope" }
}

$RequiredAccess = @{
    ResourceAppId  = $GraphAppId
    ResourceAccess = $ResourceAccess
}

Update-MgApplication -ApplicationId $App.Id -RequiredResourceAccess $RequiredAccess
Write-Host "API-rechten toegevoegd." -ForegroundColor Cyan

# Admin consent voor Application permissions
foreach ($Id in ($AppRoles | Select-Object -Unique)) {
    try {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SP.Id -BodyParameter @{
            PrincipalId = $SP.Id
            ResourceId  = $GraphSP.Id
            AppRoleId   = $Id
        } | Out-Null
    } catch {}
}

Write-Host "Admin consent verleend." -ForegroundColor Green

# Client Secret aanmaken
$Secret = Add-MgApplicationPassword -ApplicationId $App.Id -PasswordCredential @{ DisplayName = "MigrationSecret"; EndDateTime = (Get-Date).AddYears(2) }

Write-Host ""
Write-Host "════════════════════════════════════" -ForegroundColor Yellow
Write-Host "App Name    : $AppName" -ForegroundColor White
Write-Host "Tenant ID   : $TenantId" -ForegroundColor White
Write-Host "Client ID   : $($App.AppId)" -ForegroundColor Green
Write-Host "Client Secret: $($Secret.SecretText)" -ForegroundColor Green
Write-Host "════════════════════════════════════" -ForegroundColor Yellow
Write-Host "Kopieer deze waarden naar de GUI!" -ForegroundColor Cyan