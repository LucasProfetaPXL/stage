param(
    [string]$UserBackupDir = ""
)

$BackupDir = if ($UserBackupDir -ne "") { $UserBackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\Antivirus" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

Write-Host "Backup map: $BackupDir" -ForegroundColor Gray
Write-Host "--- Starten met fix van Antivirus policies ---" -ForegroundColor Yellow

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw
        $Content = $Content -replace '"SettingInstanceTemplateId"', '"settingInstanceTemplateId"'
        $Data = $Content | ConvertFrom-Json

        $NewSettings = foreach ($s in $Data.settings) {
            $Instance = if ($s.settingInstance) { $s.settingInstance } else { $s.SettingInstance }
            @{ "settingInstance" = $Instance }
        }

        $Technologies = if ($Data.technologies) { $Data.technologies } else { "mdm,microsoftSense" }
        $Platforms    = if ($Data.platforms)    { $Data.platforms }    else { "windows10" }

        $FixedObject = [ordered]@{
            "@odata.type"  = "#microsoft.graph.deviceManagementConfigurationPolicy"
            "name"         = if ($Data.name)        { $Data.name }        else { $Data.displayName }
            "description"  = if ($Data.description) { $Data.description } else { "" }
            "platforms"    = $Platforms
            "technologies" = $Technologies
            "settings"     = @($NewSettings)
        }

        if ($Data.templateReference) { $FixedObject["templateReference"] = $Data.templateReference }

        # _sourceId extraheren uit bestaand id veld
        $SrcId = if ($Data.id) { $Data.id } elseif ($Data.Id) { $Data.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }

        $FixedObject | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "[OK] $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "[FOUT] $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nKlaar! Voer nu de import uit." -ForegroundColor Cyan