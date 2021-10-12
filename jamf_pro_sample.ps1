param($eventHubMessages, $TriggerMetadata)


#Jamf Pro Variables
$JamfBaseURL = "https://myserver.jamfcloud.com" 
$credPair = "apiuser:apipassword"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($credpair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"

###
### For Information on Jamf Pro API see https://developer.jamf.com
###


#The eventHubMessage is significant nested JSON so we need to cycle for the correct object
$eventHubMessages | ForEach-Object { 
    
    #Cycle sub content of {records[]} 
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

                #Write-Host "Processed Properties Keys: $($_.Keys)"
                #Write-Host "Processed Properties Values: $($_.Values)"
            
                $targetResources = $($_['targetResources'])
                $targetResources | ForEach-Object {
                    $userPrincipalName = $($_['userPrincipalName'])
                    Write-Host "The Target UPN is: $userPrincipalName"
                    
                    #in my environment the Jamf Username is everything before the @ symbol ie daniel.maclaughlin not daniel.maclaughlin@jamf.com
                    # you may need to remove of edit accordingly to convert the IDP field to match username
                    $Username =  $($userPrincipalName  -split '@')
                    $Username = $Username[0]

                    #Build Jamf Pro URL
                    $JamfUsersURL = $($JamfBaseURL + "/JSSResource/users/name/" + $Username)

                    #time to query Jamf Pro
                    $headers = @{"Authorization" = $basicAuthValue; "Accept" = "application/json"}
                    $result = Invoke-WebRequest -Method Get -Uri $JamfUsersURL -Headers $headers | ConvertFrom-Json

                    #computer Results as array
                    $computers = $($result.user.links.computers)
                    
                    #mobile devices as array
                    $mobile_devices = $($result.user.links.mobile_devices)
                    
                    # As a user could have multiple devices we retrive the results from Jamf Pro as an array then send the appropriate API command
                    foreach($computer in $computers){
                        $computer_ID = $computer.id
                        
                        #API Head changing to XML as we are using the Classic API which only supports xml for PUT, POST and DELETE
                        $headers = @{"Authorization" = $basicAuthValue; "Content-Type" = "application/xml"}
                        
                        #You will need to change the EA ID value to match your server's 
                        $computer_EA_Value = "<computer><extension_attributes><extension_attribute><id>13</id><value>True</value></extension_attribute></extension_attributes></computer>"
                        
                        
                        #Optional if you don't have Jamf Connect or wanted to post lock command instead here is that alternative
                        #time to Post Lock Command to Jamf Pro
                        #$computer_lock_xml = "<computer_command><general><command>DeviceLock</command><passcode>123456</passcode></general><computers><computer><id>$computer_ID</id></computer></computers></computer_command>"

                        #Destination URL, note if changing to lock command the url will need to change to https://YOUR_JAMF_PRO_URL/JSSResource/computercommands/command/DeviceLock see https://developer.jamf.com for more information
                        
                        $JamfComputerURL = $($JamfBaseURL + "/JSSResource/computers/id/$computer_ID")
                        
                        $result = Invoke-WebRequest -Method POST -Uri $JamfComputerURL -Headers $headers -Body $computer_EA_Value
                        #Write-Host "Jamf Pro response is $result"
                    }

                    foreach($mobile_device in $mobile_devices){
                        $device_ID = $mobile_device.id

                        $JamfDeviceURL = $($JamfBaseURL + "/JSSResource/mobiledevicecommands/command/EnableLostMode")
                        $headers = @{"Authorization" = $basicAuthValue; "Content-Type" = "application/xml"}
                        $device_lostmode_xml = "<mobile_device_command><lost_mode_message>Device has been reported as Lost</lost_mode_message><mobile_devices><mobile_device><id>$device_ID</id></mobile_device></mobile_devices></mobile_device_command>"

                        #$result = Invoke-WebRequest -Method POST -Uri $JamfDeviceURL -Headers $headers -Body $device_lostmode_xml
                        Write-Host "Jamf Pro response is $result"
                    }
                }
            }
        } else {
            Write-Host "Nothing to Action"
        }
        #Write-Host "Properties: $properties"
    }
}


