# Combines the various pieces of the Web Services to output a complete object
function Create_WebServices_Outline($templateId,$steps,$variables,$properties)
{ 
    # Create empty arrays if there are no properties/variables
    if(!$properties)
    { $properties = @() }

    if(!$variables)
    { $variables = @() }
    else 
    { $variables = $variables | Sort-Object -Property name -Unique | Select-Object -ExcludeProperty "environment" }

    # Ensure that 1 step is inside an array
    if($steps.Count -eq 1)
    { $steps = @($steps) }

    $webServices = [pscustomobject]@{
                                      "templateid" = $templateId;
                                      "steps" = $steps.Where( { $null -ne $_ } );
                                      "variables" = $variables;
                                      "properties" = $properties
                                    }

    return $webServices
}

# Builds a Web Services step object
function Create_WebServices_Step($function,$url,$headers,$headerPresets,$contentTypeRequest,$contentTypeResponse = "application/json",$body,$variables,$ignoreResult = $false,$requestFilename,$responseFilename,$stepCompletionCode=200,$responseDataCheck)
{  
    $variables | ForEach-Object{
                                  $tempName = $_.name

                                  # Replace any Postman variables to match the Web Services format
                                  if($url -like ("*{{"+$tempName +"}}*"))
                                  { $url = $url.Replace(("{{"+$tempName+"}}"),("@"+$tempName)) }

                                  if($body -like ("*{{"+$tempName+"}}*"))
                                  { $body = $body.Replace(("{{"+$tempName+"}}"),("@"+$tempName)) }

                                  $headers | ForEach-Object{
                                                              if($_.attribute -like ("*{{"+$tempName+"}}*"))
                                                              { $_.attribute = $_.attribute.Replace("{{"+$tempName+"}}",("@"+$tempName)) }

                                                              if($_.value -like ("*{{"+$tempName+"}}*"))
                                                              { $_.value = $_.value.Replace("{{"+$tempName+"}}",("@"+$tempName)) }
                                                           }

                                  $headerPresets | ForEach-Object{
                                                                  if($_.attribute -like ("*{{"+$tempName+"}}*"))
                                                                  { $_.attribute = $_.attribute.Replace("{{"+$tempName+"}}",("@"+$tempName)) }

                                                                  if($_.value -like ("*{{"+$tempName+"}}*"))
                                                                  { $_.value = $_.value.Replace("{{"+$tempName+"}}",("@"+$tempName)) }
                                                                 }
    }

    # Setup Variable array if none exist
    if(!$variables)
    { $variables = New-Object System.Collections.ArrayList }

    # This covers any variables that we could not match
    if($url -like "*{{*}}*") 
    { $url = $url.Replace("{{","@").Replace("}}","") } 
      
    if($body -like "*{{*}}*")
    { $body = $body.Replace("{{","@").Replace("}}","") }

    $headers | ForEach-Object{
                              if($_.attribute -like ("*{{*}}*"))
                              { $_.attribute = $_.attribute.Replace("{{","@").Replace("}}","") }

                              if($_.value -like ("*{{*}}*"))
                              { $_.value = $_.value.Replace("{{","@").Replace("}}","") }
                             }

    # Create empty arrays if none, ensure everything is inside an array
    # and no duplicate variables/headers
    if(!$headers -and !$headerPresets)
    { $headers = @() }
    else
    { 
      if($headerPresets)
      { $headerPresets | ForEach-Object{ 
                                          if($headers.attribute -notcontains "Content-Type")
                                          { $headers.Add( [pscustomobject]@{"attribute"=$_.attribute;"value"=$_.value} ) | Out-Null }
                                          elseif($_.attribute -ne "Content-Type")
                                          { $headers.Add( [pscustomobject]@{"attribute"=$_.attribute;"value"=$_.value} ) | Out-Null } 
                                        } 
      }
    
      $headers = $headers | Sort-Object -property attribute -Unique
      if($headers.Count -eq 1)
      { $headers = @($headers) }
    }

    $variables = $variables | Sort-Object -property name -Unique 
    if($variables.Count -eq 1)
    { $variables = @($variables) }

    $newStep = [pscustomobject]@{
        "function" = $function;
        "url" = $url;
        "request" = @{
          "headers" = $headers;
          "contentType" = $contentTypeRequest;
          "body" = $body;
          "fileName" = $requestFileName
        };
        "response" = @{
          "contentType" = $contentTypeResponse;
          "variables" = @();
          "ignoreResult" = $ignoreResult;
          "stepCompletionCode" = $stepCompletionCode;
          "responseDataCheck" = $responseDataCheck;
          "fileName" = $responseFilename
        }
      }

    return $newStep
}

function Get_Postman_Requests($postmanRequests,$headers,$headerPresets)
{
  $methodArray = Initialize_Method_Array
  $contentTypeArray = Initialize_ContentType_Array

  $requests = New-Object System.Collections.ArrayList
  $postmanRequests | ForEach-Object{
                                      $tempHeaders = New-Object System.Collections.ArrayList
                                      $_.headerData | ForEach-Object{ $tempHeaders.Add( [pscustomobject]@{ "attribute"=$_.key;"value"=$_.value } ) | Out-Null }
                                      $contentType = $tempHeaders.Where({ $_.attribute -eq "Content-Type" })

                                      # If content-type not specified
                                      if(!$contentType)
                                      { $contentType = @([pscustomobject]@{"attribute"="Content-Type";"value"="application/json" }) }

                                      if($contentType.Count -eq 1)
                                      {
                                        if(($contentType.value -in $contentTypeArray) -and ($_.method -in $methodArray))
                                        { $requests.Add( (Create_WebServices_Step -function $_.method -headers $tempHeaders -headerPresets $headerPresets -body $_.rawModeData -url $_.url -contentTypeRequest $contentType.value) ) | Out-Null }
                                        else
                                        { Write-Host "`r`nStep '"$_.name"' not added`r`nMethod ="$_.method"`r`nContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                      }
                                      else 
                                      { Write-Host "`r`nToo many content-types for Step '"$_.name"'`r`nContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }

                                      # If there is a response to an API call, add as a step
                                      if($_ | Get-Member "responses")
                                      { 
                                        $_.responses | ForEach-Object{
                                                $tempHeaders = New-Object System.Collections.ArrayList
                                                $_.requestObject.headerData | ForEach-Object{ $tempHeaders.Add( [pscustomobject]@{ "attribute"=$_.key;"value"=$_.value } ) | Out-Null }
                                                $contentType = $tempHeaders.Where({ $_.attribute -eq "Content-Type"})

                                                # If content-type not specified
                                                if(!$contentType)
                                                { $contentType = @([pscustomobject]@{"attribute"="Content-Type";"value"="application/json" }) }

                                                if($contentType.Count -eq 1)
                                                {
                                                  if(($contentType.value -in $contentTypeArray) -and ($_.requestObject.method -in $methodArray))
                                                  { $requests.Add( (Create_WebServices_Step -function $_.requestObject.method -headers $tempHeaders -headerPresets $headerPresets -body $_.requestObject.rawModeData -url $_.requestObject.url -contentTypeRequest $contentType.value) ) | Out-Null }
                                                  else
                                                  { Write-Host "`r`nStep '"$_.name"' not added`r`nMethod ="$_.requestObject.method" ContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                                }
                                                else 
                                                { Write-Host "`r`nToo many content-types for Step '"$_.name"'`r`nContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                            }
                                      }
                                  }

  return $requests
}

# Create array of currently available Content-Types
function Initialize_ContentType_Array()
{
  # Sets up available content types for a request
  $contentTypeArray = @("application/json","application/xml","application/x-www-form-urlencoded","text/plain")

  return $contentTypeArray
}

# Create array of currently available REST Methods
function Initialize_Method_Array()
{
    # Sets up available method types for a request
    $methodArray = @( "GET","POST","PUT","DELETE")
    
    return $methodArray
}

# Parse Postman Items and convert them into Web Services steps
function Get_Postman_Items($postmanItems,$headers,$headerPresets)
{
  $items = New-Object System.Collections.ArrayList
  if($postmanItems | Get-Member "request")
  {
    $methodArray = Initialize_Method_Array
    $contentTypeArray = Initialize_ContentType_Array

    $postmanItems | ForEach-Object{
                                  $tempHeaders = New-Object System.Collections.ArrayList
                                  $_.request.header | ForEach-Object{ $tempHeaders.Add( [pscustomobject]@{ "attribute"=$_.key;"value"=$_.value } ) | Out-Null }
                                  $contentType = $tempHeaders.Where({ $_.attribute -eq "Content-Type"})

                                  # If content-type not specified
                                  if(!$contentType)
                                  { $contentType = @([pscustomobject]@{"attribute"="Content-Type";"value"="application/json" }) }

                                  if($contentType.Count -eq 1)
                                  { 
                                    if(($contentType.value -in $contentTypeArray) -and ($_.request.method -in $methodArray))
                                    { $items.Add( (Create_WebServices_Step -function $_.request.method -url $_.request.url.raw -headers $tempHeaders -headerPresets $headerPresets -body $_.request.body.raw -contentTypeRequest $contentType.value) ) | Out-Null }
                                    elseif($_.response.Count -gt 0)
                                    {
                                      $_.response | ForEach-Object{
                                                                    $tempHeaders = New-Object System.Collections.ArrayList
                                                                    $_.response.header | ForEach-Object{ $tempHeaders.Add( [pscustomobject]@{ "attribute"=$_.key;"value"=$_.value } ) | Out-Null }
                                                                    $contentType = $tempHeaders.Where({ $_.attribute -eq "Content-Type"})
                                  
                                                                    # If content-type not specified
                                                                    if(!$contentType)
                                                                    { $contentType = @([pscustomobject]@{"attribute"="Content-Type";"value"="application/json" }) }
                                                                    
                                                                    if($contentType.Count -eq 1)
                                                                    {
                                                                      if(($contentType.value -in $contentTypeArray) -and ($_.response.method -in $methodArray))
                                                                      { $items.Add( (Create_WebServices_Step -function $_.response.method -url $_.response.originalRequest.url.raw -headers $tempHeaders -headerPresets $headerPresets -body $_.response.body -contentTypeRequest $contentType.value) ) | Out-Null }
                                                                      else
                                                                      { Write-Host "`r`nStep '"$_.name"' not added`r`nMethod ="$_.response.method" ContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                                                    }
                                                                    else 
                                                                    { Write-Host "`r`nToo many content-types for Step '"$_.name"'`r`nContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                                                  }
                                    }
                                    else
                                    { Write-Host "`r`nStep '"$_.name"' not added`r`nMethod ="$_.request.method" ContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                  }
                                  else 
                                  { Write-Host "`r`nToo many content-types for Step '"$_.name"'`r`nContentType =";$contentType | Out-Host; Write-Host "-----------------------------" }
                                }
  }
  return $items
}

# Combine everything to output the Web Services json file
function Create_WebServices_File($steps,$templateId,$variables,$path)
{
    $templateid = $templateId.Replace("/","_").Replace("\","_")

    # Output WebServices file
    if($steps.Count -gt 0)
    {
      $completeObject = Create_WebServices_Outline -steps $steps -templateId $templateId -variables $variables
      Write-Information ("Creating Web Services template "+$templateId) -InformationAction Continue
      Write-Host "-----------------------------"
      $completeObject | ConvertTo-Json -Depth 10 | Out-File ($path + "\test\" + $templateid + ".json") -Encoding utf8
    }
    else
    { Write-Host "No steps found." }
}

# Grabs variables that weren't matched
function Check_UnKnownVariables($url,$headers,$headerPresets,$stepHeaders,$body,$variables)
{
    $tempVariables = New-Object System.Collections.ArrayList
    if($variables.Count -gt 0)
    {
          $variables | ForEach-Object{
            $tempName = $_.name.TrimStart("@")
            $tempVariables.Add([pscustomobject]@{ "name"=$_.name;"value"=$_.value }) | Out-Null

            # Replace any Postman variables to match the Web Services format
            $url = $url.Replace(("{{"+$tempName +"}}"),"??????")

            if(($body -ne "") -and ($body -ne @{}) -and ($body.Length -gt 0))
            { 
              try
              { $body = $body.Replace("{{"+$tempName +"}}","??????") }
              catch
              { $null }
            }

            $headers | ForEach-Object{
                                      if($_.attribute -like ("*{{"+$tempName +"}}*"))
                                      { $_.attribute = $_.attribute.Replace("{{"+$tempName +"}}","??????") }

                                      if($_.value -like ("*{{"+$tempName +"}}*"))
                                      { $_.value = $_.value.Replace("{{"+$tempName +"}}","??????") }
                                     }

            $headerPresets | ForEach-Object{
                                            if($_.attribute -like ("*{{"+$tempName +"}}*"))
                                            { $_.attribute = $_.attribute.Replace("{{"+$tempName +"}}","??????") }

                                            if($_.value -like ("*{{"+$tempName +"}}*"))
                                            { $_.value = $_.value.Replace("{{"+$tempName +"}}","??????") }
                                           }

            $stepHeaders | ForEach-Object{
                                            if($_.key -like ("*{{"+$tempName +"}}*"))
                                            { $_.key = $_.key.Replace("{{"+$tempName +"}}","??????") }

                                            if($_.value -like ("*{{"+$tempName +"}}*"))
                                            { $_.value = $_.value.Replace("{{"+$tempName +"}}","??????") }
                                         }
          }
    }

    # Parse through url variables not matched to variables
    $url | ForEach-Object{
                          $tempURL = $_
                          while($tempURL -like "*{{*}}*")
                          { 
                            $tempVariables.Add([pscustomobject]@{ "name"="@"+ ($tempURL.Substring($tempURL.IndexOf("{{")+2,$tempURL.IndexOf("}}") - ($tempURL.IndexOf("{{")+2) ));"value"="??????" }) | Out-Null

                            if(($tempURL.IndexOf("}}")+2) -ne $tempURL.Length)
                            { $tempURL = $tempURL.Substring($tempURL.IndexOf("}}")+2 ) }
                            else
                            { break }
                          }
                        }

    # Parse through body variables not matched to variables
    $body | ForEach-Object{
                            $tempBody = $_
                            while($tempBody -like ("*{{*}}*"))
                            { 
                              $tempVariables.Add([pscustomobject]@{ "name"="@" + ($tempBody.Substring($tempBody.IndexOf("{{")+2,$tempBody.IndexOf("}}")-($tempBody.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                              
                              if(($tempBody.IndexOf("}}")+2) -ne $tempBody.Length)
                              { $tempBody = $tempBody.Substring($tempBody.IndexOf("}}")+2 ) }
                              else
                              { break }
                            }
                          }

    # Parse through headers not matched to variables
    $headers | ForEach-Object{
                              while($_.attribute -like ("*{{*}}*"))
                              { 
                                $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.attribute.Substring($_.attribute.IndexOf("{{")+2,$_.attribute.IndexOf("}}")-($_.attribute.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                
                                if(($_.attribute.IndexOf("}}")+2) -ne $_.attribute.Length)
                                { $_.attribute = $_.attribute.Substring($_.attribute.IndexOf("}}")+2 ) }
                                else
                                { break }
                              }

                              while($_.value -like ("*{{*}}*"))
                              { 
                                $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.value.Substring($_.value.IndexOf("{{")+2,$_.value.IndexOf("}}")-($_.value.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                
                                if(($_.value.IndexOf("}}")+2) -ne $_.value.Length)
                                { $_.value = $_.value.Substring($_.value.IndexOf("}}")+2 ) }
                                else
                                { break }
                              }
                             }

    # Parse through HeaderPresets not matched to variables
    $headerPresets | ForEach-Object{
                                      while($_.attribute -like ("*{{*}}*"))
                                      { 
                                        $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.attribute.Substring($_.attribute.IndexOf("{{")+2,$_.attribute.IndexOf("}}")-($_.attribute.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                        
                                        if(($_.attribute.IndexOf("}}")+2) -ne $_.attribute.Length)
                                        { $_.attribute = $_.attribute.Substring($_.attribute.IndexOf("}}")+2 ) }
                                        else
                                        { break }
                                      }

                                      while($_.value -like ("*{{*}}*"))
                                      { 
                                        $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.value.Substring($_.value.IndexOf("{{")+2,$_.value.IndexOf("}}")-($_.value.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                        
                                        if(($_.value.IndexOf("}}")+2) -ne $_.value.Length)
                                        { $_.value = $_.value.Substring($_.value.IndexOf("}}")+2 ) }
                                        else
                                        { break }
                                      }
                                    }

    # Parse through Headers in steps not matched to variables
    $stepHeaders | ForEach-Object{
                                    while($_.key -like ("*{{*}}*"))
                                    { 
                                      $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.key.Substring($_.key.IndexOf("{{")+2,$_.key.IndexOf("}}")-($_.key.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                      
                                      if(($_.key.IndexOf("}}")+2) -ne $_.key.Length)
                                      { $_.key = $_.key.Substring($_.key.IndexOf("}}")+2 ) }
                                      else
                                      { break }
                                    }

                                    while($_.value -like ("*{{*}}*"))
                                    { 
                                      $tempVariables.Add([pscustomobject]@{ "name"="@" + ($_.value.Substring($_.value.IndexOf("{{")+2,$_.value.IndexOf("}}")-($_.value.IndexOf("{{")+2)));"value"="??????" }) | Out-Null 
                                      
                                      if(($_.value.IndexOf("}}")+2) -ne $_.value.Length)
                                      { $_.value = $_.value.Substring($_.value.IndexOf("}}")+2 ) }
                                      else
                                      { break }
                                    }
                                 }    

  return $tempVariables
}

# Future work
<#
$nestedItems = $_
  while($nestedItems | Get-Member "item")
  {
    $tempName = $nestedItems.name
    $nestedItems = $nestedItems.item
    $nestedItems | Out-Host
    if($nestedItems | Get-Member "request")
    {
      write-host "got here"
      $steps = New-Object System.Collections.ArrayList
      $nestedItems | ForEach-Object{ $steps.Add( (Get_Postman_Items -postmanItems $_ -headers $headers -headerPresets $headerPresets) ) | Out-Null }
      #$steps.Count | Out-Host;exit
      if($steps.Count -gt 0)
      {
        $totalVariables = Check_UnKnownVariables -url $nestedItems.request.url.raw -headers $headers -headerPresets $headerPresets -stepHeaders $nestedItems.request.header -body $nestedItems.request.body.raw -variables $variables
        Create_WebServices_File -steps $steps -templateId $tempName -variables $totalVariables -path (($MyInvocation.MyCommand).Path | Split-Path -Parent)
      }
    }
  }
#>