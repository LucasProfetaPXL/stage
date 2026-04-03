# Script staat in: public/scripts/fix_json/
$BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\ConditionalAccess"
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

$SkipAlways = @("id","createdDateTime","modifiedDateTime","deletedDateTime","additionalProperties","templateId")

# Converteer PascalCase naar camelCase recursief en verwijder lege objecten/arrays
function ConvertTo-CleanCamel {
    param($Obj)
    if ($null -eq $Obj) { return $null }

    if ($Obj -is [System.Array]) {
        $result = @()
        foreach ($item in $Obj) {
            if ($item -is [PSCustomObject]) {
                $c = ConvertTo-CleanCamel $item
                if ($c -is [System.Collections.IDictionary] -and $c.Count -gt 0) { $result += $c }
                elseif ($c -isnot [System.Collections.IDictionary]) { $result += $c }
            } else { $result += $item }
        }
        return $result
    }

    if ($Obj -isnot [PSCustomObject]) { return $Obj }

    $output = [ordered]@{}
    foreach ($prop in $Obj.PSObject.Properties) {
        $camel = $prop.Name.Substring(0,1).ToLower() + $prop.Name.Substring(1)
        if ($camel -in $SkipAlways) { continue }

        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }

        if ($val -is [System.Array]) {
            if ($val.Count -eq 0) { continue }
            $cleaned = @()
            foreach ($item in $val) {
                if ($item -is [PSCustomObject]) {
                    $c = ConvertTo-CleanCamel $item
                    if ($c -is [System.Collections.IDictionary] -and $c.Count -gt 0) { $cleaned += $c }
                    elseif ($c -isnot [System.Collections.IDictionary]) { $cleaned += $c }
                } else { $cleaned += $item }
            }
            if ($cleaned.Count -gt 0) { $output[$camel] = $cleaned }
        } elseif ($val -is [PSCustomObject]) {
            $cleanedSub = ConvertTo-CleanCamel $val
            if ($cleanedSub -is [System.Collections.IDictionary] -and $cleanedSub.Count -gt 0) {
                $output[$camel] = $cleanedSub
            }
        } else {
            $output[$camel] = $val
        }
    }
    return $output
}

# CA-specifieke fixes na camelCase conversie
function Fix-CaPolicy {
    param($P)
    $cond = $P["conditions"]
    if ($null -eq $cond) { return }

    # Fix applications
    if ($cond["applications"]) {
        $apps = $cond["applications"]
        foreach ($key in @("applicationFilter","globalSecureAccess","networkAccess")) {
            if ($apps.Contains($key)) {
                $v = $apps[$key]
                if ($v -is [System.Collections.IDictionary] -and $v.Count -eq 0) { $apps.Remove($key) }
            }
        }
    }

    # Fix devices: verwijder als geen rule
    if ($cond.Contains("devices")) {
        $dev = $cond["devices"]
        $hasRule = $dev.Contains("deviceFilter") -and
                   $dev["deviceFilter"].Contains("rule") -and
                   -not [string]::IsNullOrWhiteSpace($dev["deviceFilter"]["rule"])
        if (-not $hasRule) { $cond.Remove("devices") }
    }

    # Fix 1119: users
    if ($cond["users"]) {
        $users = $cond["users"]
        if ($users.Contains("includeUsers")) {
            $inc = @($users["includeUsers"])
            if ($inc -contains "All" -or $inc -contains "None") {
                if ($users.Contains("includeGuestsOrExternalUsers")) { $users.Remove("includeGuestsOrExternalUsers") }
            }
        }
        if ($users.Contains("excludeUsers")) {
            $exc = @($users["excludeUsers"])
            if ($exc -contains "All" -or $exc -contains "GuestsOrExternalUsers") {
                if ($users.Contains("excludeGuestsOrExternalUsers")) { $users.Remove("excludeGuestsOrExternalUsers") }
            }
        }
    }

    # Verwijder lege conditions sub-objecten
    foreach ($key in @("authenticationFlows","deviceStates","clientApplications","agents","times","locations","platforms")) {
        if ($cond.Contains($key)) {
            $v = $cond[$key]
            if ($v -is [System.Collections.IDictionary] -and $v.Count -eq 0) { $cond.Remove($key) }
        }
    }
}

Write-Host "Backup map: $BackupDir" -ForegroundColor Gray
Write-Host "--- Starten met fix van CA JSON bestanden ---" -ForegroundColor Yellow

foreach ($File in $Files) {
    try {
        $RawJson = Get-Content $File.FullName -Raw | ConvertFrom-Json
        $SrcId   = if ($RawJson.PSObject.Properties["_sourceId"]) { $RawJson._sourceId }
                   elseif ($RawJson.PSObject.Properties["Id"])     { $RawJson.Id }
                   elseif ($RawJson.PSObject.Properties["id"])     { $RawJson.id }
                   else { $null }

        # Stap 1: camelCase + lege objecten verwijderen
        $Fixed = ConvertTo-CleanCamel $RawJson

        # Stap 2: CA-specifieke fixes
        Fix-CaPolicy $Fixed

        # Forceer disabled + _sourceId
        $Fixed["state"] = "disabled"
        if ($SrcId) { $Fixed["_sourceId"] = $SrcId }

        $Fixed | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        Write-Host "[OK] $($File.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nKlaar! Voer nu de import uit." -ForegroundColor Cyan