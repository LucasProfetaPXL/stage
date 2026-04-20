param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerTenantId,

    [string]$AppName = "XylosMigration_App"
)

Connect-MgGraph -TenantId $CustomerTenantId -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -UseDeviceCode, "AppRoleAssignment.ReadWrite.All"

Write-Host "App aanmaken: $AppName" -ForegroundColor Cyan
$App = New-MgApplication -DisplayName $AppName
$ServicePrincipal = New-MgServicePrincipal -AppId $App.AppId
Write-Host "App is gemaakt met ID= $($App.AppId)" -ForegroundColor Green

$GraphAppId = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
$Permissions = @(
    "9255e99d-faf5-445e-bbf7-cb71482737c4",  # DeviceManagementScripts.ReadWrite.All
    "7a6ee1e7-141e-4cec-ae74-d9db155731ff",  # DeviceManagementApps.Read.All
    "9241abd9-d0e6-425a-bd4f-47ba86e767a4",  # DeviceManagementConfiguration.ReadWrite.All
    "78145de6-330d-4800-a6ce-494ff2d33d07",  # DeviceManagementApps.ReadWrite.All
    "01c0a623-fc9b-48e9-b794-0756f8e8f067"   # Policy.ReadWrite.ConditionalAccess
)

$GraphApp = Get-MgServicePrincipal -Filter "AppId eq '$GraphAppId'"

$RequiredAccess = @{
    ResourceAppId  = $GraphApp.AppId
    ResourceAccess = foreach ($Id in $Permissions) {
        @{ Id = $Id.Trim(); Type = "Role" }
    }
}

Update-MgApplication -ApplicationId $App.Id -RequiredResourceAccess $RequiredAccess
Write-Host "API-rechten zijn toegevoegd aan de app!" -ForegroundColor Cyan

foreach ($Id in $Permissions) {
    $Params = @{
        PrincipalId = $ServicePrincipal.Id
        ResourceId  = $GraphApp.Id
        AppRoleId   = $Id.Trim()
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -BodyParameter $Params
}

Write-Host "Admin Consent is automatisch verleend!" -ForegroundColor Green
Write-Host "App ID= $($App.AppId)" -ForegroundColor Green