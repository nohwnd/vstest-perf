function Get-LogEvent {
    [CmdletBinding()]
    param (
        [string] $LogDirectory
    )

    $logs = Get-ChildItem $LogDirectory -Recurse

    $hostLog = $logs | Where-Object Name -Like '*host*.txt' | Get-Content
    $consoleLog = $logs | Where-Object Name -NotLike '*host*.txt' | Get-Content

    # zip the log, to get it in order based on timestamp
    # we know that console log is always first and last, because it 
    # starts the host
    $log = [Collections.Generic.List[string]]@()
    $h = 0 
    $hCount = $hostLog.Length
    $c = 0
    foreach ($l in $consoleLog) {        
        $log.Add($l)

        if ($l -notlike "TpTrace*") { 
            # multiline log item, we added it and go to next line because there 
            # is no timestamp so the line belongs to the item above
            continue 
        }
        # split to max 6 pieces, because we only care about the first 5 items 
        # because timestamp is index 4 (indexed from 0) items
        try {
            $cTime = [long]::Parse(($l -split ", ",6)[4])
        }
        catch { 
            Write-Host "Err parsing console log on index $c, text: '$l'" -ForegroundColor Red
            throw
        }
        
        try {
            # if there is no TpTrace it is a multiline item and belongs to the one above
            # otherwise we take till the timestamp is lower than the one we saw on console log
            while ($h -lt $hCount -and ($hostLog[$h] -notlike "TpTrace*" -or [long]::Parse((($errLine = $hostLog[$h]) -split ", ",6)[4]) -lt $cTime)) {
                $log.Add($hostLog[$h])
                $h++
            }        
        }
        catch { 
            Write-Host "Err on Index: $h, Text '$errLine'" -ForegroundColor Red
            throw
        }

        $c++
    }


    $hostPatterns = @(
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "DotnetTestHostManager: Starting process*" }
            # name of the event
            Name = "TestHostStarting"

            # this is set on end event, to calculate diff from previous event
            # that is defined by the name of the event, e.g. to figure out how long 
            # it took to start testhost by diffing TestHostStarting and TestHostStarted  
            # event timestamps
            Pair = $null
            Found = $false
        }

        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "DefaultEngineInvoker.Invoke: Testhost process started with*"}
            # name of the event
            Name = "TestHostStarted"

            # this is set on end event, to calculate diff from previous event
            # that is defined by the name of the event, e.g. to figure out how long 
            # Discovery took
            Pair = "TestHostStarting"
            # to skip events we already found
            Found = $false
        }

        [PSCustomObject] @{
            # time between we started and connected to console
            Pattern = { param ($Message) $Message -like "DefaultEngineInvoker.StartProcessingAsync: Connected to vstest.console*"}
            Name = "VstestConsoleConnected"
            Pair = "TestHostStarted"
            Found = $false
        }
        
        [PSCustomObject] @{
            # time betwen connecting to console and getting request
            Pattern = { param ($Message) $Message -like "TestRequestHandler.ProcessRequests: received message: (TestExecution.StartWithSources)*"}
            Name = "StartWithSources"
            Pair = "VstestConsoleConnected"
            Found = $false
        }
        
        [PSCustomObject] @{
            # looking up plugins
            Pattern = { param ($Message, $Module) $Module -like "*testhost.dll" -and $Message -like "TestPluginCache.DiscoverTestExtensions: finding test extensions in assemblies *"}
            Name = "LookingUpPlugins"
            Pair = "StartWithSources"
            Found = $false
        }
        
        [PSCustomObject] @{
            # plugin lookup 
            Pattern = { param ($Message) $Message -like "TestExecutorService: Loaded the extensions*"}
            Name = "LookedUpPlugins"
            Pair = "LookingUpPlugins"
            Found = $false
        }
        
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "TestDiscoveryManager: Discovering tests from sources*"}
            Name = "DiscoveringTests"
            Pair = "LookedUpPlugins"
            Found = $false
        }
        
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "BaseRunTests.RunTestInternalWithExecutors: Running tests for*"}
            Name = "RunningTests"
            Pair = "DiscoveringTests"
            Found = $false
        }
        
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "BaseRunTests.RunTests: Run is complete*"}
            Name = "FinishedRunningTests"
            Pair = "RunningTests"
            Found = $false
        }
        
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "Testhost process exiting*"}
            Name = "TestHostExiting"
            Pair = "FinishedRunningTests"
            Found = $false
        }
        
        [PSCustomObject] @{
            Pattern = { param ($Message) $Message -like "TestHostManagerCallbacks.ExitCallBack: Testhost processId:*exited*"}
            Name = "TestHostExited"
            Pair = "TestHostExiting"
            Found = $false
        }

        [PSCustomObject] @{
            # reports the whole time the testhost ran
            Pattern = { param ($Message) $Message -like "SocketClient.PrivateStop: Stop communication from server endpoint*"}
            Name = "TestHostDuration"
            Pair = "TestHostStarted"
            Found = $false
        }
        
        # [PSCustomObject] @{
        #     Pattern = { param ($Message) $Message -like "*"}
        #     Name = ""
        #     Pair = $null
        #     Found = $false
        # }
        
        # [PSCustomObject] @{
        #     Pattern = { param ($Message) $Message -like "*"}
        #     Name = ""
        #     Pair = $null
        #     Found = $false
        # }
        
        # [PSCustomObject] @{
        #     Pattern = { param ($Message) $Message -like "*"}
        #     Name = ""
        #     Pair = $null
        #     Found = $false
        # }
    )
    
    $hostEvents = [Collections.Generic.List[object]]@()
    foreach ($line in $log) { 
        $null, $null, $date, $time, $timeStamp, $module, $message = $line -split ", ",7
        
        foreach ($e in $hostPatterns) {
            if ($e.Found) { 
                # skip events we already found
                continue
            }

            if (-not (& $e.Pattern -Message $message -Module $module -TimeStamp $timeStamp -Line $line)) {
                continue
            }

            $e.Found = $true

            $r = [PSCustomObject] @{
                Pattern = $e.Pattern
                # name of the event
                Name = $e.Name
                # the dll (testhost.dll - index 5)
                Module = $module
                # when it happened (ticks - index 4)
                TimeStamp = [long]::Parse($timeStamp)
                # date + time (index 2 + 3)
                DateTime = "$date $time"
                # message (index 6)
                Message = $message

                # this is set on end event, to calculate diff from previous event
                # that is defined by the name of the event, e.g. to figure out how long 
                # Discovery took
                Pair = $e.Pair
                PairEvent = $null
                Duration = 0 
            }

            $hostEvents.Add($r)
            # one line cannot be more events jump to next line
            break 
        }
    }

    foreach ($r in $hostEvents) {
        if ($r.Pair) { 
            # if we have a pair we look for the last previous occurence of the event (at the moment we will have)
            # only one occurence per event so right now it does not matter if we look for last or first, 
            # but if some could repat in the future we probably want the last, because that is the closest one
            # that happened to the current one so in this sequence start -> end -> start -> end
            # we would find the second start for the second end, not the first start for the second end
            $pair = $hostEvents | Where-Object Name -EQ $r.Pair | Select-Object -First 1
            if (-not $pair) { 
                throw "Could not find pair $($r.Pair) for $($r.Name)."
            }
            $r.PairEvent = $pair
            $r.Duration = [TimeSpan]::FromTicks($r.TimeStamp - $pair.TimeStamp)
        }
    }

    $hostEvents | Sort-Object -Property TimeStamp
}