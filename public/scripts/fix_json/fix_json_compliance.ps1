param(
    [string]$UserBackupDir = ""
)

$BackupDir = if ($UserBackupDir -ne "") { $UserBackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\CompliancePolicies" }
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json
        
        # 1. Bepaal het hoofdtype (Platform)
        $Type = $Content.AdditionalProperties."@odata.type"
        if ($null -eq $Type) { $Type = $Content."@odata.type" }

        # 2. Hoofdobject opbouwen
        $FixedObject = [ordered]@{
            "@odata.type" = $Type
            "displayName" = $Content.DisplayName
            "description" = if ($Content.Description) { $Content.Description } else { "" }
        }

        # 3. Technische instellingen uit AdditionalProperties overzetten
        if ($null -ne $Content.AdditionalProperties) {
            foreach ($Prop in $Content.AdditionalProperties.PSObject.Properties) {
                $IgnoreSub = @("@odata.context", "@odata.type", "scheduledActionsForRule@odata.context")
                if ($Prop.Name -notin $IgnoreSub) {
                    $FixedObject.Add($Prop.Name, $Prop.Value)
                }
            }
        }

        # 3b. Root-level technische instellingen overzetten (compliance settings)
        $IgnoreRoot = @(
            "@odata.type", "displayName", "description", "id",
            "createdDateTime", "lastModifiedDateTime", "version",
            "assignments", "roleScopeTagIds", "scheduledActionsForRule",
            "AdditionalProperties",
            # Status/rapportage properties die niet mee mogen
            "DeviceSettingStateSummaries", "DeviceStatusOverview", "DeviceStatuses",
            "UserStatusOverview", "UserStatuses"
        )
        foreach ($Prop in $Content.PSObject.Properties) {
            if ($Prop.Name -notin $IgnoreRoot -and -not $FixedObject.Contains($Prop.Name)) {
                $FixedObject.Add($Prop.Name, $Prop.Value)
            }
        }

        # 4. RoleScopeTags behouden
        if ($null -ne $Content.RoleScopeTagIds) {
            $FixedObject.Add("roleScopeTagIds", $Content.RoleScopeTagIds)
        }

        # 5. scheduledActionsForRule zonder @odata.type in de nested config
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

        # 6. Exporteren naar JSON met voldoende diepte
        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }
        $FixedObject | ConvertTo-Json -Depth 100 | Out-File $File.FullName -Encoding utf8 -Force
        
        Write-Host "Gecorrigeerd: $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "Fout bij $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}