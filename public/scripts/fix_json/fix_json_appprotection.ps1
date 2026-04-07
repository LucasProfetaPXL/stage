param(
    [string]$BackupBase = ""
)

$BackupDir = if ($BackupBase -ne "") { Join-Path $BackupBase "AppProtection" } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\AppProtection" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json

        $FixedObject = [ordered]@{
            "@odata.type" = $Content.AdditionalProperties."@odata.type"
            "displayName" = $Content.DisplayName
            "description" = if ($Content.Description) { $Content.Description } else { "" }
        }

        $IgnoreAdditional = @("@odata.type", "deployedAppCount", "isAssigned")
        foreach ($Prop in $Content.AdditionalProperties.PSObject.Properties) {
            if ($Prop.Name -notin $IgnoreAdditional) {
                $FixedObject.Add($Prop.Name, $Prop.Value)
            }
        }

        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }
        $FixedObject | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "Gecorrigeerd: $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "Fout bij $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}