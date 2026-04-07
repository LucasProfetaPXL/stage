param(
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret
)

Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue

$TokenResponse = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

$Global:MgToken = $TokenResponse.access_token
$SecureToken = [System.Security.SecureString]::new()
foreach ($char in $Global:MgToken.ToCharArray()) { $SecureToken.AppendChar($char) }
Connect-MgGraph -AccessToken $SecureToken -NoWelcome

Write-Host "Verbonden met tenant $TenantId" -ForegroundColor Green

$MainBackupDir = if ($BackupDir -ne "") { $BackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup" }
$MainBackupDir = [System.IO.Path]::GetFullPath($MainBackupDir)

function Export-IntuneObject ($Cmdlet, $Folder) {
    $TargetDir = Join-Path -Path $MainBackupDir -ChildPath $Folder
    if (!(Test-Path $TargetDir)) { 
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null 
    }

    try {
        $Objects = Invoke-Expression $Cmdlet
        if ($null -eq $Objects) { return }

        foreach ($Item in $Objects) {
            $RawName = if ($Item.DisplayName) { $Item.DisplayName } else { $Item.Name }
            if (-not $RawName) { $RawName = $Item.Id }

            $SafeName = ($RawName -replace '[^a-zA-Z0-9]', '_') + ".json"
            $FilePath = Join-Path $TargetDir $SafeName

            $FullObject = Get-MgBetaDeviceManagementDeviceCompliancePolicy `
                -DeviceCompliancePolicyId $Item.Id `
                -ExpandProperty "ScheduledActionsForRule"

            $FullObject | ConvertTo-Json -Depth 100 | Out-File $FilePath -Encoding utf8
            Write-Host "[OK] $SafeName" -ForegroundColor Green
        }
    } catch {
        Write-Host "[FOUT] $Folder : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "--- Starten export Compliance Policies ---" -ForegroundColor Cyan

Export-IntuneObject "Get-MgBetaDeviceManagementDeviceCompliancePolicy -All" "CompliancePolicies"

Write-Host "`nKlaar!" -ForegroundColor Yellow