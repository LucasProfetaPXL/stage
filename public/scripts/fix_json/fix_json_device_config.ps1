param(
    [string]$UserBackupDir = ""
)

# fix_json_device_config.ps1
$BackupDir = if ($UserBackupDir -ne "") { $UserBackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\DeviceConfigurations" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

Write-Host "Backup map: $BackupDir" -ForegroundColor Gray
Write-Host "--- Starten met fix van Device Configurations ---" -ForegroundColor Yellow

$IgnoreProps = @(
    "id", "Id", "createdDateTime", "lastModifiedDateTime", "version",
    "assignments", "groupAssignments", "supportsScopeTags",
    "DeviceStatusOverview", "DeviceStatuses", "UserStatusOverview",
    "UserStatuses", "DeviceSettingStateSummaries", "AdditionalProperties",
    "_sourceId"
)

foreach ($File in $Files) {
    try {
        $Raw = Get-Content $File.FullName -Raw -Encoding UTF8
        if ($Raw[0] -eq [char]0xFEFF) { $Raw = $Raw.Substring(1) }

        $Data = $Raw | ConvertFrom-Json

        # Haal _sourceId op
        $SrcId = if ($Data._sourceId) { $Data._sourceId }
                 elseif ($Data.id)    { $Data.id }
                 elseif ($Data.Id)    { $Data.Id }
                 else { $null }

        # Bouw plat object op
        $Fixed = [ordered]@{}

        # @odata.type uit AdditionalProperties of root
        if ($Data.AdditionalProperties -and $Data.AdditionalProperties."@odata.type") {
            $Fixed["@odata.type"] = $Data.AdditionalProperties."@odata.type"
        } elseif ($Data."@odata.type") {
            $Fixed["@odata.type"] = $Data."@odata.type"
        }

        # displayName en description
        $Fixed["displayName"] = if ($Data.displayName) { $Data.displayName } elseif ($Data.DisplayName) { $Data.DisplayName } else { "" }
        $Fixed["description"]  = if ($Data.description) { $Data.description } elseif ($Data.Description) { $Data.Description } else { "" }

        # Root properties (geen blacklist)
        foreach ($Prop in $Data.PSObject.Properties) {
            if ($Prop.Name -in $IgnoreProps) { continue }
            if ($Prop.Name -in @("@odata.type", "displayName", "DisplayName", "description", "Description")) { continue }
            if ($null -eq $Prop.Value) { continue }
            $Fixed[$Prop.Name] = $Prop.Value
        }

        # AdditionalProperties uitpakken naar root
        if ($Data.AdditionalProperties) {
            foreach ($Prop in $Data.AdditionalProperties.PSObject.Properties) {
                if ($Prop.Name -eq "@odata.type") { continue }
                if ($Fixed.Contains($Prop.Name))  { continue }
                $Fixed[$Prop.Name] = $Prop.Value
            }
        }

        # _sourceId bewaren
        if ($SrcId) { $Fixed["_sourceId"] = $SrcId }

        $Fixed | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "[OK] $($File.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[FOUT] $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nKlaar! Voer nu de import uit." -ForegroundColor Cyan