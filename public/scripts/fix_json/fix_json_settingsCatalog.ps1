param(
    [string]$UserBackupDir = ""
)

$BackupDir = if ($UserBackupDir -ne "") { $UserBackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\SettingsCatalog" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

# Verwijder null templateReferences recursief
function Remove-NullTemplateRef {
    param($Obj)
    if ($null -eq $Obj) { return }
    if ($Obj -is [System.Array]) { foreach ($item in $Obj) { Remove-NullTemplateRef $item }; return }
    if ($Obj -isnot [PSCustomObject]) { return }

    foreach ($refProp in @("settingInstanceTemplateReference", "settingValueTemplateReference")) {
        if ($Obj.PSObject.Properties[$refProp]) {
            $ref = $Obj.$refProp
            $idProp = if ($refProp -eq "settingInstanceTemplateReference") { "settingInstanceTemplateId" } else { "settingValueTemplateId" }
            if ($null -eq $ref -or ($ref -is [PSCustomObject] -and $ref.PSObject.Properties[$idProp] -and $null -eq $ref.$idProp)) {
                $Obj.PSObject.Properties.Remove($refProp)
            }
        }
    }
    foreach ($prop in $Obj.PSObject.Properties) {
        $val = $prop.Value
        if ($val -is [PSCustomObject] -or $val -is [System.Array]) { Remove-NullTemplateRef $val }
    }
}

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw -Encoding UTF8
        # Fix CamelCase
        $Content = $Content -replace '"SettingInstanceTemplateId"', '"settingInstanceTemplateId"'
        $Data = $Content | ConvertFrom-Json

        # Sla EPM policies over
        if ($Data.technologies -like "*endpointPrivilege*" -or
            ($Data.templateReference -and $Data.templateReference.templateFamily -like "*EndpointPrivilege*")) {
            Write-Host "[SKIP] EPM overgeslagen: $($File.Name)" -ForegroundColor Yellow
            continue
        }

        # Settings opschonen
        $NewSettings = foreach ($s in $Data.settings) {
            @{ "settingInstance" = $s.settingInstance }
        }

        # Platforms en technologies — zorg dat het strings zijn
        $Platforms    = if ($Data.platforms -is [string] -and $Data.platforms)    { $Data.platforms }    else { "windows10" }
        $Technologies = if ($Data.technologies -is [string] -and $Data.technologies) { $Data.technologies } else { "mdm" }

        $FixedObject = [ordered]@{
            "@odata.type"  = "#microsoft.graph.deviceManagementConfigurationPolicy"
            "name"         = $Data.name
            "description"  = if ($Data.description) { $Data.description } else { "" }
            "platforms"    = $Platforms
            "technologies" = $Technologies
            "settings"     = @($NewSettings)
        }

        # templateReference bewaren als die een templateId heeft
        if ($Data.templateReference -and $Data.templateReference.templateId) {
            $FixedObject["templateReference"] = $Data.templateReference
        }

        # _sourceId voor PolicyMapping (eerst kijken of al aanwezig, anders id gebruiken)
        if ($Data._sourceId)   { $FixedObject["_sourceId"] = $Data._sourceId }
        elseif ($Data.id)      { $FixedObject["_sourceId"] = $Data.id }
        elseif ($Data.Id)      { $FixedObject["_sourceId"] = $Data.Id }

        # Verwijder null templateReferences
        $FixedJson = $FixedObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        Remove-NullTemplateRef $FixedJson

        $FixedJson | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "[OK] $($File.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[FOUT] $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}