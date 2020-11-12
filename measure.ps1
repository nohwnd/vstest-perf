$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. "$PSScriptRoot/process-logs.ps1"

Get-ChildItem obj, dir -Directory -Recurse | Remove-Item -Recurse -Force -Confirm:$false

$dotnetVersion = dotnet --version
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH-mm-ss")
$history = "$PSScriptRoot/history/$now"

$null = New-Item $history -ItemType Directory -Force

if ($dotnetVersion -notlike "3.1*") { 
    throw "$dotnetVersion is used, but 3.1.xxx should be used"
}

Write-Host "Using dotnet $dotnetVersion"

$versions = @("16.5", "16.6.1", "16.7.1", "16.8.0")
# uncomment to use all
# $versions = @()

$framework = "MSTest"

$classes = 60
$tests = 60

$tries = 5 # try 1 will build the dll from scratch
$showFirstTry = $true

####

$projects = Get-ChildItem '*.csproj' -Recurse | Where-Object { 
    if ($null -eq $versions -or 0 -eq $versions.Count) { 
        $true 
    }
    else { 
        $name = $_.BaseName
        $any = $versions | Where-Object { $name -like "*$_*" } 
        # true when there are any items
        [bool] $any
    } 
}

$total = 0
$content =  
@"
using Microsoft.VisualStudio.TestTools.UnitTesting;
namespace PerfTesting
{
    $(foreach ($c in 1..$classes) {
    "[TestClass]
    public class UnitTest$c
    {
        $(foreach ($t in 1..$tests) {
            # increasing it by one instead of multiplying classes by tests
            # to get the real count in case I make an error in the generation process
            $total++
"       [TestMethod]
        public void TestMethod$t()
        {
        }`n`n"})
    }`n"})
}
"@

foreach ($project in $projects.Directory) { 
    $content | Set-Content "$project/UnitTest.cs" -Encoding UTF8
}

$entries = @()
foreach ($try in 1..$tries) {
    foreach ($project in $projects) {
        $sw = [Diagnostics.StopWatch]::StartNew()
        try {
            $err = $null
            $failed = $false

            $p = $project.BaseName
            $logDirectory = "$history/$p/$try"
            $log = "$logDirectory/log_${p}_${now}_${try}"
            $logPath = "$log.txt"
            
            $command = { dotnet test $project --diag:"$logPath" }
            & $command
            $sw.Stop()
        }  
        catch {
            $sw.Stop()
            $err = $_
            $failed = $true
            throw
        }
        finally {
            $sw.Stop()

            # avoid throws when we did not set a variable because we failed early
            Set-StrictMode -Off
            $duration = $sw.Elapsed
            Write-Host "Execution time $($duration.TotalSeconds) s"
            $l = [Diagnostics.StopWatch]::StartNew()
            Write-Host -ForegroundColor Magenta "Processing logs..."
            $logEntries = Get-LogEvent $logDirectory
            Write-Host -ForegroundColor Magenta "Done. Took $($l.Elapsed.TotalSeconds.ToString("0.00")) s"

            $entry = [PSCustomObject] @{
                ObjectVersion = "5"
                Now = [string] $now
                Try = $try
                HostDuration = $hostDuration
                HostDurationTicks = $hostDuration.Ticks
                HostDurationMs = $hostDuration.TotalMilliseconds
                DurationTicks = $duration.Ticks
                DurationMs = $duration.TotalMilliseconds
                Duration = $duration
                Project = $p
                DotnetVerson = $dotnetVersion
                Command = $command
                Error = $err
                Failed = $failed
                Classes = $classes
                Total = $total
                Tests = $tests
                Framework = $framework
                Log = $logEntries
            }

            $entries += $entry
            $entry | ConvertTo-Json | Set-Content "$log.json"

            Set-StrictMode -Version Latest
        }
    }
}
 

$fastest = $null
$entriesFromFastest = $entries | Sort-Object -Property DurationMs
foreach ($e in $entriesFromFastest) {
    if ($null -eq $fastest) {
        $fastest = $e
    }
    
    $durationDelta = ($e.DurationMs - $fastest.DurationMs).ToString("+0 ms").PadLeft(10) 
    $percentDelta = if (-not $fastest.DurationTicks) { 
            "ERR %" 
        } 
        else { 
            ((($e.DurationTicks / $fastest.DurationTicks) - 1)).ToString("+0.000 %").PadLeft(10) 
        }

    $e | 
        Add-Member -Name DurationDiff -MemberType NoteProperty -Value $durationDelta -PassThru |
        Add-Member -Name PercentDiff -MemberType NoteProperty -Value $percentDelta

    $eventNames = @()
    foreach ($event in $e.Log) { 
        $n = "_$($event.Name)"
        $eventNames += $n
        $e | Add-Member -Name $n -MemberType NoteProperty -Value $event.Duration
        
    }

    $thd, $sum = $e.Log | ForEach-Object { $thd = $null; $d = [timespan]::Zero} { if ($_.Name -eq "TestHostDuration") { $thd = $_.Duration } else {  $d+= $_.Duration } } { $thd, $d}
    $e | Add-Member -Name CapturedDuration -MemberType NoteProperty -Value ($sum)
    $e | Add-Member -Name NonCapturedDuration -MemberType NoteProperty -Value ($thd-$sum)

    # the time spend in non-host things. To see if the vstest.console overhead varies based on the testhost version (it shouldn't)
    $e | Add-Member -Name NonHostTime -MemberType NoteProperty -Value ($thd-$e.Duration)
}


$entriesFromFastest | Where-Object { 1 -ne $_.Try -or $showFirstTry } | Format-Table (@("PercentDiff", "DurationDiff", "DurationMs", "Project", "Try", "Tests", "Classes", "Total", "NonHostTime") + $eventNames + @("CapturedDuration", "NonCapturedDuration"))
 