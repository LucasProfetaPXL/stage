param(
    [string]$BackupDir = "",

    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

$TokenResponse = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

$Global:MgToken = $TokenResponse.access_token
$SecureToken = [System.Security.SecureString]::new()
foreach ($char in $Global:MgToken.ToCharArray()) { $SecureToken.AppendChar($char) }
Connect-MgGraph -AccessToken $SecureToken -NoWelcome

$MainBackupDir = if ($BackupDir -ne "") { $BackupDir } else { Join-Path -Path $PSScriptRoot -ChildPath "GoldenTenant_Backup" }
$MainBackupDir = [System.IO.Path]::GetFullPath($MainBackupDir)

Write-Host "Backup map: $MainBackupDir" -ForegroundColor Gray

function Export-IntuneObject ($Cmdlet, $Folder) {
    $TargetDir = Join-Path -Path $MainBackupDir -ChildPath $Folder
    if (!(Test-Path $TargetDir)) { 
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null 
    }

    try {
        $Objects = Invoke-Expression $Cmdlet
        if ($null -eq $Objects) { return }

        foreach ($Item in $Objects) {
            $RawName = if ($Item.DisplayName) { $Item.DisplayName } else { $Item.Name }
            if (-not $RawName) { $RawName = $Item.Id }

            $SafeName = ($RawName -replace '[^a-zA-Z0-9]', '_') + ".json"
            $FilePath = Join-Path $TargetDir $SafeName
            
            $FullObject = $Item

            # --- DIEPE EXPORT LOGICA VOOR SETTINGS CATALOG ---
            if ($Folder -eq "SettingsCatalog") {

                if ($Item.TemplateReference.TemplateFamily -eq "endpointSecurityEndpointPrivilegeManagement") {
                    Write-Host "  -> Overgeslagen (EPM): $($RawName)" -ForegroundColor DarkGray
                    continue
                }

                Write-Host "  -> export voor Settings Catalog: $($RawName)" -ForegroundColor Gray
                
                $SettingsData = Get-MgBetaDeviceManagementConfigurationPolicySetting -DeviceManagementConfigurationPolicyId $Item.Id -All
                
                $CleanSettings = foreach ($Setting in $SettingsData) {
                    $Instance = $Setting.SettingInstance
                    
                    $InstanceObj = @{
                        "settingDefinitionId" = $Instance.SettingDefinitionId
                    }

                    if ($Instance.AdditionalProperties) {
                        foreach ($key in $Instance.AdditionalProperties.Keys) {
                            $InstanceObj[$key] = $Instance.AdditionalProperties[$key]
                        }
                    }

                    if ($Instance.SettingInstanceTemplateReference) {
                        $InstanceObj["settingInstanceTemplateReference"] = $Instance.SettingInstanceTemplateReference
                    }

                    if (-not $InstanceObj.ContainsKey("@odata.type")) {
                        $InstanceObj["@odata.type"] = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                    }

                    @{
                        "@odata.type"     = "#microsoft.graph.deviceManagementConfigurationPolicySetting"
                        "settingInstance" = $InstanceObj
                    }
                }

                $FullObject = [PSCustomObject]@{
                    "@odata.type"  = "#microsoft.graph.deviceManagementConfigurationPolicy"
                    "name"         = $Item.Name
                    "description"  = $Item.Description
                    "platforms"    = $Item.Platforms
                    "technologies" = $Item.Technologies
                    "settings"     = $CleanSettings
                }
            }

            # --- DIEPE EXPORT LOGICA VOOR ENDPOINT PRIVILEGE MANAGEMENT ---
            elseif ($Folder -eq "EndpointPrivilegeManagement") {

                if ($Item.TemplateReference.TemplateFamily -ne "endpointSecurityEndpointPrivilegeManagement") {
                    Write-Host "  -> Overgeslagen (geen EPM): $($RawName)" -ForegroundColor DarkGray
                    continue
                }

                Write-Host "  -> export voor EPM: $($RawName)" -ForegroundColor Gray

                $SettingsData = Get-MgBetaDeviceManagementConfigurationPolicySetting -DeviceManagementConfigurationPolicyId $Item.Id -All

                $FullObject = [PSCustomObject]@{
                    "name"              = $Item.Name
                    "description"       = $Item.Description
                    "platforms"         = $Item.Platforms
                    "technologies"      = $Item.Technologies
                    "templateReference" = $Item.TemplateReference
                    "settings"          = $SettingsData
                }
            }

            # --- DIEPE EXPORT LOGICA VOOR SECURITY BASELINES ---
            elseif ($Folder -eq "SecurityBaselines") {
                Write-Host "  -> export voor Security Baseline: $($RawName)" -ForegroundColor Gray
                $FullSettings = Get-MgBetaDeviceManagementIntentSetting -DeviceManagementIntentId $Item.Id -All
                $FullObject = [PSCustomObject]@{
                    "displayName" = $Item.DisplayName
                    "description" = $Item.Description
                    "templateId"  = $Item.TemplateId
                    "settings"    = $FullSettings
                }
            }

            # --- DIEPE EXPORT LOGICA VOOR COMPLIANCE POLICIES ---
            elseif ($Folder -eq "CompliancePolicies") {
                $FullObject = Get-MgBetaDeviceManagementDeviceCompliancePolicy -DeviceCompliancePolicyId $Item.Id -ExpandProperty "ScheduledActionsForRule"
            }

            $FullObject | ConvertTo-Json -Depth 100 | Out-File $FilePath -Encoding utf8
            Write-Host "[$Folder] Geëxporteerd: $SafeName" -ForegroundColor Green
        }
    } catch {
        Write-Host "Fout bij export van $Folder : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "--- Starten van volledige diepte-export ---" -ForegroundColor Cyan

Export-IntuneObject "Get-MgBetaDeviceManagementConfigurationPolicy -All" "SettingsCatalog"
Export-IntuneObject "Get-MgBetaDeviceManagementConfigurationPolicy -All" "EndpointPrivilegeManagement"

Write-Host "`nKlaar! Controleer je JSON-bestanden." -ForegroundColor Yellow