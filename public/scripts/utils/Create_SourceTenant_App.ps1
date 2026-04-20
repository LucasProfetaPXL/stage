param(
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [string]$AppName = "XylosMigration_Source"
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
    "7a6ee1e7-141e-4cec-ae74-d9db155731ff",  # DeviceManagementApps.Read.All
    "78145de6-330d-4800-a6ce-494ff2d33d07",  # DeviceManagementApps.ReadWrite.All
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4",  # DeviceManagementConfiguration.Read.All
    "dc377aa6-52d8-4e23-b271-2a7ae04cedf3",  # DeviceManagementConfiguration.ReadWrite.All
    "e330c4f0-4170-414e-a55a-2175fe3a0b5e",  # DeviceManagementManagedDevices.PrivilegedOperations.All
    "dc377aa6-52d8-4e23-b271-2a7ae04cedf3",  # DeviceManagementManagedDevices.Read.All
    "243333ab-4d21-40cb-a475-36241daa0842",  # DeviceManagementManagedDevices.ReadWrite.All
    "9255e99d-faf5-445e-bbf7-cb71482737c4",  # DeviceManagementScripts.Read.All
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4",  # DeviceManagementServiceConfig.Read.All
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4",  # DeviceManagementServiceConfig.ReadWrite.All
    "62a82d76-70ea-41e2-9197-370581804d09",  # Group.ReadWrite.All
    "df021288-bdef-4463-88db-98f22de89214",  # User.Read.All
    "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8",  # UserAuthenticationMethod.ReadWrite.All
    "246dd0d5-5bd0-4def-940b-0421030a5b68"# Policy.Read.All
)

# Delegated permissions (Scope)
$Scopes = @(
    "7a6ee1e7-141e-4cec-ae74-d9db155731ff",  # DeviceManagementApps.Read.All
    "78145de6-330d-4800-a6ce-494ff2d33d07",  # DeviceManagementApps.ReadWrite.All
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4",  # DeviceManagementConfiguration.Read.All
    "dc377aa6-52d8-4e23-b271-2a7ae04cedf3",  # DeviceManagementConfiguration.ReadWrite.All
    "e330c4f0-4170-414e-a55a-2175fe3a0b5e",  # DeviceManagementManagedDevices.PrivilegedOperations.All
    "f1493658-876a-4c87-8729-b9edd9813786",  # DeviceManagementManagedDevices.Read.All
    "9255e99d-faf5-445e-bbf7-cb71482737c4",  # DeviceManagementScripts.Read.All
    "8696daa5-bce5-4b79-b176-f9bc7af28f91",  # DeviceManagementServiceConfig.Read.All
    "62a82d76-70ea-41e2-9197-370581804d09",  # Group.ReadWrite.All
    "5b567255-7703-4780-807c-7be8301ae99b",  # Group.Read.All
    "a154be20-db9c-4678-8ab7-66f6cc099a59",  # User.Read.All
    "7427e0e9-2fba-42fe-b0c0-848c9e6a8182",  # offline_access
    "37f7f235-527c-4136-accd-4a02d197296e",  # openid
    "14dad69e-099b-42c9-810b-d002981feec1",  # profile
    "e1fe6dd8-ba31-4d61-89e7-88639da4683d",  # User.Read
    "572fea84-0151-49b2-9301-11cb16974376",  # DeviceManagementRBAC.Read.All
    "246dd0d5-5bd0-4def-940b-0421030a5b68"# Policy.Read.All
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