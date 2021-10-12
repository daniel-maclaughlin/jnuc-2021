param($eventHubMessages, $TriggerMetadata)


#Jamf School Variables
$JamfBaseURL = "https://myjamfschoolurl.jamfcloud.com/api/devices"
$credPair = "NetworkID:APIKEY"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($credpair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"

###
### For Information on Jamf School API see https://developer.jamf.com
###

#The eventHubMessage is significant nested JSON so we need to cycle for the correct object
$eventHubMessages | ForEach-Object { 
    
    $records = $($_.Values)
    $records | ForEach-Object {
    
        # Write-Host "Processed Keys: $($_.Keys)" #this spits out top level keys such as operationName
        # Write-Host "Processed Values: $($_.Values)" #this spits out all the top level values like Disable account
        
        $operationName = $($_['operationName']) #this show the value like Update user
        #Write out to the log, useful for testing events
        Write-Host "Operation is $operationName"
        
        #Checking for the Operation other operations that can be used are "Enable account" and "Update user"
        if ($operationName -eq "Disable account"){

            $properties = $($_['properties'])
            $properties | ForEach-Object {

                $targetResources = $($_['targetResources'])
                $targetResources | ForEach-Object {
                    
                    $userPrincipalName = $($_['userPrincipalName'])
                    Write-Host "The Target UPN is: $userPrincipalName"
                    #in my environment the Jamf Username is everything before the @ symbol ie daniel.maclaughlin not daniel.maclaughlin@jamf.com
                    # you may need to remove of edit accordingly to convert the IDP field to match username
                    
                    $Username =  $($userPrincipalName  -split '@')
                    $Username = $Username[0]


                    #Build Jamf Pro URL
                    $JamfUsersURL = $($JamfBaseURL + "?name=" + $userPrincipalName)

                    #time to query Jamf Pro
                    $headers = @{"Authorization" = $basicAuthValue; "Accept" = "application/json"}
                    $result = Invoke-WebRequest -Method Get -Uri $JamfUsersURL -Headers $headers | ConvertFrom-Json

                    #All devices as array
                    $devices = $($result.devices)
                    
                    #As Jamf School returns all devices we need to seperate out based on device type
                    foreach($device in $devices){
                        $device_Type = $($device.class)
                        $device_UDID =  $($device.UDID)

                        $headers = @{"Authorization" = $basicAuthValue; "Content-Type" = "application/json"}
                        if ($device_Type -eq "mac"){
                        
                            #Action to tke on macOS devices
                            #Post data to the Notes field via the API for Smart Group calculation
                            
                            $JamfDeviceURL = $($JamfBaseURL + "/" + $device_UDID + "/details")
                            $JamfSchoolNotes = @{"notes" =  "User_Decommissioned"}
                            $JamfSchoolNotes = $JamfSchoolNotes | Convertto-Json
                            $result = Invoke-WebRequest -Method POST -Uri $JamfDeviceURL -Headers $headers -Body $JamfSchoolNotes

                            #Setting the URL to be a Restart Command after Updating Status Via API
                            $JamfDeviceURL = $($JamfBaseURL + "/" + $device_UDID + "/restart")
                        } else {
                            #All iOS devices
                            $device_Supervised = $($device.isSupervised)
                            if ($device_Supervised -eq "true"){
                                #device is supervised so Wipe
                                $JamfDeviceURL = $($JamfBaseURL + "/" + $device_UDID + "/wipe")
                            } else {
                                #device is no Supervised so possibly BYOD will Unmanage instead
                                $JamfDeviceURL = $($JamfBaseURL + "/" + $device_UDID + "/unenroll")
                            }
                        }
                        $result = Invoke-WebRequest -Method POST -Uri $JamfDeviceURL -Headers $headers -Body $device_lostmode_xml
                        Write-Host "Jamf School response is $result"
                    }

                    #Write-Host "Jamf School API response $result"
                }
            }
        } else {
            Write-Host "Nothing to Action"
        }
    }
}
