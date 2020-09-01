param(
    $postmanFile = ((($MyInvocation.MyCommand).Path | Split-Path -Parent) + "\<filename>.json")
    ,$postmanModule = ((($MyInvocation.MyCommand).Path | Split-Path -Parent) + "\PostmanModule.psm1")
)

if((Test-Path $postmanFile) -and (Test-Path $postmanModule))
{
    Import-Module $postmanModule -Force

    # Get Postman contents to PS Object
    $postmanObject = Get-Content $postmanFile -Raw | ConvertFrom-Json

    # Setup script variables
    $variables = New-Object System.Collections.ArrayList
    $headers = New-Object System.Collections.ArrayList

    # Get Postman variables 
    if($postmanObject | Get-Member "variable")
    { $postmanObject.variable | ForEach-Object{ $variables.Add( [pscustomobject]@{ "name"=$_.key;"value"=$_.value } ) | Out-Null } }
    
    # Get Postman environment variables
    if($postmanObject | Get-Member "environments")
    { $postmanObject.environments | ForEach-Object{ 
                                                    $environment = $_.name
                                                    $_.values.Where( { $_.enabled -eq $true } ) | ForEach-Object{ 
                                                                                                                  $variables.Add( [pscustomobject]@{ "environment"=$environment;"name"=$_.key;"value"=$_.value } ) | Out-Null 
                                                                                                                }                             
                                                  }
    }

    # Get Postman Auth details
    if($postmanObject | Get-Member "auth")
    {
      $authType = $postmanObject.auth.type
      $tempObject = [pscustomobject]@{"attribute"="";"value"="" }
      For($x=0;$x -lt $postmanObject.auth.$authType.Count;$x++)
      {
        if($postmanObject.auth.$authType[$x].key -eq "key")
        { $tempObject.attribute = $postmanObject.auth.$authType[$x].value }

        if($postmanObject.auth.$authType[$x].key -eq "value")
        { $tempObject.value = $postmanObject.auth.$authType[$x].value }
          
        if($tempObject.attribute -ne "" -and $tempObject.value -ne "")
        { 
          $headers.Add( $tempObject ) | Out-Null  
          $tempObject = [pscustomobject]@{"attribute"="";"value"="" } 
        }
      }
    }

    # Get Postman HeaderPresets
    if($postmanObject | Get-Member "headerPresets")
    { 
        $headerPresets = New-Object System.Collections.ArrayList
        $postmanObject.headerPresets.headers.Where({ $_.enabled -eq $true}) | ForEach-Object{ $headerPresets.Add( [pscustomobject]@{"attribute"=$_.key;"value"=$_.value} ) | Out-Null } 
    }

    # Finish setting up properties and variables
    if($variables -ne "")
    { 
        $variables.Where({$_.value -eq ""}) | ForEach-Object{ $_.value = "??????" }
        $variables | ForEach-Object{ $_.name = "@" + $_.name }
    }

    # Get Postman Step and Body details from Item
    if($postmanObject | Get-Member "item")
    { 
      $postmanObject.item | ForEach-object{
                                            if($_ | Get-Member "item")  # support more nests?
                                            {                     
                                                $steps = New-Object System.Collections.ArrayList
                                                $_.item | ForEach-Object{ $steps.Add( (Get_Postman_Items -postmanItems $_ -headers $headers -headerPresets $headerPresets) ) | Out-Null }

                                                if($steps.Count -gt 0)
                                                {
                                                  $totalVariables = Check_UnKnownVariables -url $_.item.request.url.raw -headers $headers -headerPresets $headerPresets -stepHeaders $_.item.request.header -body $_.item.request.body.raw -variables $variables
                                                  Create_WebServices_File -steps $steps -templateId $_.name -variables $totalVariables -path (($MyInvocation.MyCommand).Path | Split-Path -Parent)
                                                }
                                            }
                                            else 
                                            {
                                                $steps = New-Object System.Collections.ArrayList
                                                $steps.Add( (Get_Postman_Items -postmanItems $_ -headers $headers -headerPresets $headerPresets) ) | Out-Null
                                                
                                                if($steps.Count -gt 0)
                                                {
                                                  $totalVariables = Check_UnKnownVariables -url $_.request.url.raw -headers $headers -headerPresets $headerPresets -stepHeaders $_.request.header -body $_.request.body.raw -variables $variables
                                                  Create_WebServices_File -steps $steps -templateId $_.name -variables $totalVariables -path (($MyInvocation.MyCommand).Path | Split-Path -Parent)  
                                                }
                                            }
                                          }
    }

    # Get Postman steps from collection
    if($postmanObject | Get-Member "collections")
    {
        $collections = $postmanObject.collections
        $collections | ForEach-Object{
                                        $collectionId = $_.id
                                        $folders = $postmanObject.collections.folders.Where( { $_.collectionid -eq $collectionId } )
                                        $folders | ForEach-Object{
                                                                    $folderId = $_.folderid
                                                                    $steps = New-Object System.Collections.ArrayList
                                                                    $postmanObject.collections.requests.Where( { $_.folder -eq $folderId } ) | ForEach-Object{ $steps.Add( (Get_Postman_Requests -headers $headers -headerPresets $headerPresets -postmanRequests $_) ) | Out-Null }
                                                                    
                                                                    if($steps.Count -gt 0)
                                                                    {
                                                                      $totalVariables = Check_UnKnownVariables -url (($postmanObject.collections.requests.Where( { $_.folder -eq $folderId } )).url) -headers $headers -headerPresets $headerPresets -stepHeaders (($postmanObject.collections.requests.Where( { $_.folder -eq $folderId } )).headerData) -body (($postmanObject.collections.requests.Where( { $_.folder -eq $folderId } )).rawModeData) -variables $variables
                                                                      Create_WebServices_File -steps $steps -templateId $_.name -variables $totalVariables -path (($MyInvocation.MyCommand).Path | Split-Path -Parent)
                                                                    }
                                                                 }
                                     }
    }
}
else 
{
    Write-Host "Bad path specified for file: $postmanFile"
    Exit 1  
}