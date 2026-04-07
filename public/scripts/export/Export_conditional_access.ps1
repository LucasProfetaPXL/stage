param(
    [string]$BackupDir = "",

    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

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

$MainBackupDir = if ($BackupDir -ne "") { $BackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup" }
$MainBackupDir = [System.IO.Path]::GetFullPath($MainBackupDir)

Write-Host "Backup map: $MainBackupDir" -ForegroundColor Gray

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
            $Item | ConvertTo-Json -Depth 100 | Out-File $FilePath -Encoding utf8
            Write-Host "[$Folder] Geexporteerd: $SafeName" -ForegroundColor Green
        }
    } catch {
        Write-Host "Fout bij $Folder : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "--- Starten export Conditional Access ---" -ForegroundColor Cyan
Export-IntuneObject "Get-MgBetaIdentityConditionalAccessPolicy -All" "ConditionalAccess"
Write-Host "`nKlaar!" -ForegroundColor Yellow