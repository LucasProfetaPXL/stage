param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerTenantId,

    [string]$AppName = "XylosMigration_App"
)

Connect-MgGraph -TenantId $CustomerTenantId -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -UseDeviceCode

$App = New-MgApplication -DisplayName $AppName
$ServicePrincipal = New-MgServicePrincipal -AppId $App.AppId

Write-Host "App is gemaakt met ID= $($App.AppId)" -ForegroundColor Green -BackgroundColor Black
Write-Host "Service Principal ID= $($ServicePrincipal.Id)" -ForegroundColor Green