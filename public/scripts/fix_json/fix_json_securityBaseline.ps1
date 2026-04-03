$BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\SecurityBaselines"
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json

        # Fix each setting: flatten AdditionalProperties + fix casing
        $FixedSettings = foreach ($Setting in $Content.settings) {

            $FixedSetting = [ordered]@{
                "definitionId" = $Setting.DefinitionId
                "id"           = $Setting.Id
                "valueJson"    = $Setting.ValueJson
            }

            # Merge AdditionalProperties into the setting object
            if ($null -ne $Setting.AdditionalProperties) {
                foreach ($Prop in $Setting.AdditionalProperties.PSObject.Properties) {
                    if (-not $FixedSetting.Contains($Prop.Name)) {
                        $FixedSetting.Add($Prop.Name, $Prop.Value)
                    }
                }
            }

            $FixedSetting
        }

        # Rebuild the root object
        $FixedObject = [ordered]@{
            "displayName" = $Content.displayName
            "description" = if ($Content.description) { $Content.description } else { "" }
            "templateId"  = $Content.templateId
            "settings"    = @($FixedSettings)
        }

        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }
        $FixedObject | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "Gecorrigeerd: $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "Fout bij $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}