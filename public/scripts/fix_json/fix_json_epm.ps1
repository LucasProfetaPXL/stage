$BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "..\export\GoldenTenant_Backup\EndpointPrivilegeManagement"
$BackupDir = [System.IO.Path]::GetFullPath($BackupDir)
$Files = Get-ChildItem -Path $BackupDir -Filter "*.json"

foreach ($File in $Files) {
    try {
        $Content = Get-Content $File.FullName -Raw | ConvertFrom-Json
        $CleanSettings = @()
        
        foreach ($Setting in $Content.settings) {
            $Instance = if ($Setting.SettingInstance) { $Setting.SettingInstance } else { $Setting.settingInstance }
            $DefId = $Instance.SettingDefinitionId
            
            if ($DefId -eq "device_vendor_msft_policy_elevationclientsettings_enableepm") {
                
                # 1. Default Elevation Response (Nieuw toegevoegd voor 'Require support approval')
                $ResponseDefId = "device_vendor_msft_policy_elevationclientsettings_defaultelevationresponse"
                $ResponseSetting = [ordered]@{
                    "@odata.type"         = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                    "settingDefinitionId" = $ResponseDefId
                    "choiceSettingValue"  = [ordered]@{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                        "value"       = "$($ResponseDefId)_2" # _2 staat voor 'Require support approval'
                    }
                }

                # 2. Reporting Scope (Aangepast naar 'Diagnostic data and all endpoint elevations')
                $ScopeDefId = "device_vendor_msft_policy_elevationclientsettings_reportingscope"
                $ReportingScopeSetting = [ordered]@{
                    "@odata.type"         = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                    "settingDefinitionId" = $ScopeDefId
                    "choiceSettingValue"  = [ordered]@{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                        "value"       = "$($ScopeDefId)_1" # _1 is 'All endpoint elevations' (was _0)
                    }
                }

                # 3. Send Data (Bevat nu beide bovenstaande als kinderen)
                $SendDataDefId = "device_vendor_msft_policy_elevationclientsettings_senddata"
                $SendDataSetting = [ordered]@{
                    "@odata.type"         = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                    "settingDefinitionId" = $SendDataDefId
                    "choiceSettingValue"  = [ordered]@{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                        "value"       = "$($SendDataDefId)_1"
                        "children"    = @($ReportingScopeSetting) # Reporting scope hoort hieronder
                    }
                }

                # 4. Hoofdinstelling (Enable EPM)
                $MainSetting = [ordered]@{
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
                    "settingInstance" = [ordered]@{
                        "@odata.type"         = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                        "settingDefinitionId" = $DefId
                        "settingInstanceTemplateReference" = [ordered]@{
                            "settingInstanceTemplateId" = "58a79a4b-ba9b-4923-a7a5-6dc1a9f638a4"
                        }
                        "choiceSettingValue"  = [ordered]@{
                            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                            "value"       = "$($DefId)_1"
                            "children"    = @($SendDataSetting, $ResponseSetting) # Voeg hier beide kinderen toe
                        }
                    }
                }

                $CleanSettings += $MainSetting
            }
        }

        # Finale opbouw (identiek aan vorige stap)
        $FixedObject = [ordered]@{
            "name"          = $Content.name
            "description"   = if ($Content.description) { $Content.description } else { "" }
            "platforms"     = "windows10"
            "technologies"  = "mdm,endpointPrivilegeManagement"
            "settings"      = $CleanSettings
            "templateReference" = [ordered]@{
                "templateId"             = "e7dcaba4-959b-46ed-88f0-16ba39b14fd8_1"
                "templateFamily"         = "endpointSecurityEndpointPrivilegeManagement"
                "templateDisplayName"    = "Elevation settings policy"
                "templateDisplayVersion" = "Version 1"
            }
        }

        $SrcId = if ($Content.id) { $Content.id } elseif ($Content.Id) { $Content.Id } else { $null }
        if ($SrcId) { $FixedObject["_sourceId"] = $SrcId }
        $JsonOutput = $FixedObject | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($File.FullName, $JsonOutput)
        Write-Host "Gecorrigeerd naar volledige configuratie: $($File.Name)" -ForegroundColor Green

    } catch {
        Write-Host "Fout bij $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}