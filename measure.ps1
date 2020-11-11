$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Get-ChildItem obj, dir -Directory -Recurse | Remove-Item -Recurse -Force -Confirm:$false

$dotnetVersion = dotnet --version
$history = "$PSScriptRoot/history/$now"

$null = New-Item $history -ItemType Directory -Force

if ($dotnetVersion -notlike "3.1*") { 
    throw "$dotnetVersion is used, but 3.1.xxx should be used"
}

Write-Host "Using dotnet $dotnetVersion"

$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH-mm-ss")

$projects = Get-ChildItem *.csproj -Recurse

$framework = "MSTest"

$classes = 100
$tests = 100
$tries = 3


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

            try {
                # get testhost execution time
                $hostLog = Get-ChildItem $logDirectory -Filter '*host*'
                $hostLogContent = Get-Content $hostLog
                $hostStart = [long]::Parse(($hostLogContent[0] -split ",", 6)[4])
                $hostEnd = [long]::Parse(($hostLogContent[-1] -split ",", 6)[4])
                $hostDuration = [TimeSpan]::FromTicks($hostEnd - $hostStart)
            }
            catch { 
                $hostDuration = [TimeSpan]::Zero
            }

            $duration = $sw.Elapsed
            Write-Host "Time $($duration.TotalMilliseconds) ms"
            $entry = [PSCustomObject] @{
                ObjectVersion = "4"
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
            }

            $entries += $entry
            $entry | ConvertTo-Json | Set-Content "$log.json"
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
}

$entriesFromFastest | Format-Table PercentDiff, DurationDiff, DurationMs, Project, Try, Tests, Classes, Total, HostDuration
 