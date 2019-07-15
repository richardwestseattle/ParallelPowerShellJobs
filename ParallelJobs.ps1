[int]$maxConcurrentJobs = 40
[int]$timeLimitperJob = 5 #minutes
[int]$statusUpdateInterval = 1 #seconds. This applies when job count has reached maxJobs threshold.

$moduleDefinition =
{
    Function Get-NetworkConnectionInfo($url)
    {
        $returnArray = @();

        $result = Test-NetConnection $url | Select-Object PingSucceeded, RemoteAddress, @{Name = "RoundTripTime"; Expression = { $_.PingReplyDetails.RoundTripTime }}
        $hopCount = (Test-NetConnection -TraceRoute -ComputerName $url).traceroute.count 

        $item =  New-Object psobject
        $item | Add-Member -NotePropertyName "URL" -NotePropertyValue $url
        $item | Add-Member -NotePropertyName "PingSucceeded" -NotePropertyValue $null
        $item | Add-Member -NotePropertyName "RemoteAddress" -NotePropertyValue $null
        $item | Add-Member -NotePropertyName "RoundTripTime" -NotePropertyValue $null
        $item | Add-Member -NotePropertyName "HopCount" -NotePropertyValue $null

        if($result)
        {
            $item.PingSucceeded = $result.PingSucceeded
            $item.RemoteAddress = $result.RemoteAddress
            $item.RoundTripTime = $result.RoundTripTime
        }
            else
            {
                $item.PingSucceeded = $false;
                $item.RemoteAddress = (Resolve-DnsName $url -type A)[0].IPAddress
            }

        if($hopCount)
        {
            $item.HopCount = $hopCount
        }

        $returnArray += $item;
        return $returnArray;
    }
}

Function PrintStatus()
{
    Param([int]$NumOfItems)

    $completedjobs = (get-job -State Completed).Count
    $runningjobs = (get-job -State Running).Count
    
    write-host "[Running Jobs: $($runningjobs)]/[Completed Jobs: $($completedjobs)]/[Total Items: $($NumOfItems)]/) | [$([math]::Round((100*($completedjobs/$NumOfItems)), 2))%]" 
}

Function CancelOutStandingJobs()
{
    $runningjobs = get-job -State Running
    
    foreach($job in $runningjobs)
    {
        $job.StopJob();
        $job.Dispose();
    }
    get-job | remove-job
}


Function ThrottleJobs()
{
    Param([int]$NumOfItems)

    #The number of concurrent jobs allowed is set by an integer at the beginning of script.
    #This loop essentially blocks the start of new jobs whenever the maximum number of jobs is already running.
    while((Get-Job -State Running).Count -ge $maxConcurrentJobs)
    {               
        $runningjobs = get-job -State Running

        PrintStatus -NumOfItems $NumOfItems
                    
        foreach($job in $runningjobs)
        {
            #dispose of jobs that are stuck. Time limit is defined at start of script. 
            if(((get-date).AddMinutes(-$timeLimitperJob) -ge $job.PSBeginTime))
            {
                $job.StopJob();
                $job.Dispose();
            }
        }
        start-sleep $statusUpdateInterval
    }
}


function WaitforCompletion()
{
    Param([int]$NumOfItems)

    #Wait for running jobs to complete.
    while(get-job -State Running)
    {
        $runningjobs = (get-job -State Running)

        PrintStatus -NumOfItems $NumOfItems

        foreach($job in $runningjobs)
        {
            #dispose of jobs that are stuck. Time limit is defined at start of script. 
            if(((get-date).AddMinutes(-$timeLimitperJob) -ge $job.PSBeginTime))
            {
                $job.StopJob();
                $job.Dispose();
            }
        }
        Start-Sleep $statusUpdateInterval
    }
}

function runJobs()
{   
    Param([array]$listOfUrls)

    $arrayofJobs = @();
    $arrayofData = @();
    $NumOfItems = $listOfUrls.Count

    for($index=0; $index -lt $listOfUrls.Count ; $index++)
    {
         
        $thisUrl = $listOfUrls[$index].ToString().Trim();

        PrintStatus -NumOfItems $NumOfItems    
        
        #Call function to assess job count, and throttle if applicable.   
        ThrottleJobs -NumOfItems $NumOfItems

            #Create a new background job. Because PowerShell does not allow controlling the ID attribute of a job, instead we name the jobs
            #with a controllable integer. Since we are stepping through an array of elements, we name each job by it's $index.
            $arrayofJobs += 
            Start-Job -Name $index -ScriptBlock{
                $modDef = [ScriptBlock]::Create($Using:moduleDefinition)    
                New-Module -Name MyFunctions -ScriptBlock $modDef | out-null; 

                Get-NetworkConnectionInfo @args
            } -ArgumentList $thisUrl
    }

    #Wait for running jobs to complete.
    WaitforCompletion -NumOfItems $NumOfItems

    write-host "100% Complete"

    foreach($job in $arrayofJobs)
    {
        $arrayofData += Receive-Job -Name $job.Name
    }

    return $arrayofData
}

#Import a list of URL's from an external txt file in the same folder as this script.
$listofUrls = Get-Content -Path "$($PSScriptRoot)\listOfUrls.txt"

#Terminate any already running jobs, prior to execution.
CancelOutStandingJobs

runJobs -listOfUrls $listofUrls | Select-Object URL, PingSucceeded, RemoteAddress, RoundTripTime, HopCount | Format-Table

#Terminate any lingering jobs - there should not be any though. 
CancelOutStandingJobs
