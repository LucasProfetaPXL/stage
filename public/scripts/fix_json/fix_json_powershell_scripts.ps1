param(
    [string]$BackupBase = ""
)

# fix_json_powershell_scripts.ps1
$BackupDir = if ($BackupBase -ne "") { Join-Path $BackupBase "PowerShellScripts" } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\PowerShellScripts" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"
Write-Host "Backup map: $BackupDir" -ForegroundColor Gray
Write-Host "--- Starten met fix van PowerShell Scripts ---" -ForegroundColor Yellow

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json

        $FixedObject = [ordered]@{}

        $AllowList = @(
            "displayName", "description", "scriptContent",
            "runAsAccount", "enforceSignatureCheck", "fileName",
            "runAs32Bit", "roleScopeTagIds"
        )

        foreach ($Field in $AllowList) {
            $Val = $null
            if ($null -ne $Content.$Field) { $Val = $Content.$Field }
            elseif ($null -ne $Content.($Field.Substring(0,1).ToUpper() + $Field.Substring(1))) {
                $Val = $Content.($Field.Substring(0,1).ToUpper() + $Field.Substring(1))
            } elseif ($Content.AdditionalProperties -and $null -ne $Content.AdditionalProperties.$Field) {
                $Val = $Content.AdditionalProperties.$Field
            }
            if ($null -ne $Val) { $FixedObject[$Field] = $Val }
        }

        if (-not $FixedObject.Contains("displayName") -or [string]::IsNullOrWhiteSpace($FixedObject["displayName"])) {
            Write-Host "[SKIP] Geen displayName in $($File.Name)" -ForegroundColor Yellow
            continue
        }

        if (-not $FixedObject.Contains("description"))          { $FixedObject["description"] = "" }
        if (-not $FixedObject.Contains("enforceSignatureCheck")) { $FixedObject["enforceSignatureCheck"] = $false }
        if (-not $FixedObject.Contains("runAs32Bit"))            { $FixedObject["runAs32Bit"] = $false }

        $raa = $FixedObject["runAsAccount"]
        if ($null -eq $raa -or $raa -isnot [string] -or [string]::IsNullOrWhiteSpace($raa)) {
            $FixedObject["runAsAccount"] = "system"
        }

        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }

        $FixedObject | ConvertTo-Json -Depth 20 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "[OK] $($File.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[FOUT] $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "`nKlaar! Voer nu de import uit." -ForegroundColor Cyan