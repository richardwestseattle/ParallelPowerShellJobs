# ParallelPowerShellJobs
Run PowerShell background jobs in parallel and append the output to an array of psobject's. 

In this template script, the local function does some basic network connection testing and returns the values as a psobject. This local function (Get-NetworkConnectionInfo) is a placeholder to demonstrate how to call local (custom) functions in background jobs; by using modules. This script can be used to parallelize many time-consuming tasks, e.g. WMI queries on remote machines, using a list of ComputerName's instead of URL's. 

Basic Functionality
1. Import $listOfUrls via get-content.
2. Run 'for' loop to step through items in $listOfUrls.Count.
3. Create a backgroud job for each $url in $listOfUrls, and append it to $arrayofJobs. 
4. Pause the creation of new jobs if $maxConcurrentJobs threshold is reached. Resume job creation when $runningjobs dips below threshold.
5. Following 'for' loop termination, pause and wait for outstanding $runningjobs to complete.
6. Receive output from completed jobs and append to $arrayofData.
