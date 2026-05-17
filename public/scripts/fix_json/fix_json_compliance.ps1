param(
    [string]$BackupBase = ""
)

$BackupDir = if ($BackupBase -ne "") { Join-Path $BackupBase "CompliancePolicies" } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\CompliancePolicies" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)

if (-not (Test-Path $BackupDir)) {
    Write-Host "[INFO] Geen CompliancePolicies-map gevonden op: $BackupDir" -ForegroundColor Yellow
    Write-Host "[INFO] Voer eerst de Export stap uit voordat u Fix JSON uitvoert." -ForegroundColor Yellow
    exit 0
}

$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json
        
        $Type = $Content.AdditionalProperties."@odata.type"
        if ($null -eq $Type) { $Type = $Content."@odata.type" }

        $FixedObject = [ordered]@{
            "@odata.type" = $Type
            "displayName" = $Content.DisplayName
            "description" = if ($Content.Description) { $Content.Description } else { "" }
        }

        if ($null -ne $Content.AdditionalProperties) {
            foreach ($Prop in $Content.AdditionalProperties.PSObject.Properties) {
                $IgnoreSub = @("@odata.context", "@odata.type", "scheduledActionsForRule@odata.context")
                if ($Prop.Name -notin $IgnoreSub) {
                    $FixedObject.Add($Prop.Name, $Prop.Value)
                }
            }
        }

        $IgnoreRoot = @(
            "@odata.type", "displayName", "description", "id",
            "createdDateTime", "lastModifiedDateTime", "version",
            "assignments", "roleScopeTagIds", "scheduledActionsForRule",
            "AdditionalProperties",
            "DeviceSettingStateSummaries", "DeviceStatusOverview", "DeviceStatuses",
            "UserStatusOverview", "UserStatuses"
        )
        foreach ($Prop in $Content.PSObject.Properties) {
            if ($Prop.Name -notin $IgnoreRoot -and -not $FixedObject.Contains($Prop.Name)) {
                $FixedObject.Add($Prop.Name, $Prop.Value)
            }
        }

        if ($null -ne $Content.RoleScopeTagIds) {
            $FixedObject.Add("roleScopeTagIds", $Content.RoleScopeTagIds)
        }

        $DefaultActionConfig = [ordered]@{
            "actionType"                = "block"
            "gracePeriodHours"          = 0
            "notificationTemplateId"    = ""
            "notificationMessageCCList" = @()
        }

        $ActionObj = @([ordered]@{
            "ruleName"                      = $Content.DisplayName
            "scheduledActionConfigurations" = @($DefaultActionConfig)
        })
        
        $FixedObject.Add("scheduledActionsForRule", $ActionObj)

        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }
        $FixedObject | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        
        Write-Host "Gecorrigeerd: $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "Fout bij $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}