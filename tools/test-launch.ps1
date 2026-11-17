# ============================================================================
#  test-launch.ps1  -  "one UAC prompt per start", tested without UAC
#
#  Runs the GUI edition's real launcher (the non-admin branch) from an
#  ordinary, non-elevated PowerShell. The single line that would raise the
#  UAC prompt is swapped for a stand-in that writes one line to a counter
#  file and then "waits for the user" for a few seconds - exactly the window
#  in which a second double-click used to raise a second prompt.
#
#  Must run NON-elevated (the launcher only runs when not admin). ASCII only.
# ============================================================================
param(
    [string]$Bat = '',
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$PromptSeconds = 4
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is not available yet inside a param() default on Windows PowerShell.
if (-not $Bat) { $Bat = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf.bat' }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) { throw 'run this test from a NON-elevated PowerShell' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir  = (Resolve-Path -LiteralPath $OutDir).Path
$counter = Join-Path $OutDir 'prompts.txt'
Set-Content -LiteralPath $counter -Value $null

$marker = '#PS' + 'BODY' + '-ST' + 'ART'
$text   = [IO.File]::ReadAllText($Bat, [Text.Encoding]::UTF8)
$body   = $text.Substring($text.LastIndexOf($marker) + $marker.Length)

# (also matches the pre-2.1 form, "Start-Process ... 'Elevated') | Out-Null",
#  so the same test can be pointed at an old release and seen to fail)
$rx = '(\$elevated = )?Start-Process -FilePath \(Get-Process -Id \$PID\)\.Path -Verb RunAs[^\n]*\n[^\n]*\n[^\n]*''Elevated''\)( \| Out-Null)?'
$m  = [regex]::Matches($body, $rx)
if ($m.Count -ne 1) { throw "UAC line matched $($m.Count) times, expected 1" }
# The stand-in behaves like the real thing: the prompt stays up for a few
# seconds while the person decides, then "the window opens" - it takes the
# same mutex the real window takes and holds it for a while.
$fakeCmd = "Add-Content -LiteralPath ''$counter'' -Value prompt; Start-Sleep -Seconds $PromptSeconds; " +
           "`$m = New-Object System.Threading.Mutex(`$true, ''Local\Csharf-SingleInstance''); Start-Sleep -Seconds 12; `$m.ReleaseMutex()"
$fake = '$elevated = Start-Process -FilePath powershell.exe -PassThru -NoNewWindow -ArgumentList ' +
        "'-NoProfile -Command `"$fakeCmd`"'"
$body = [regex]::Replace($body, $rx, [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $fake })

$n = 0
function Start-Copy {
    # Every start gets its own extracted file, as every double-click does.
    $script:n++
    $f = Join-Path $OutDir "launch-$script:n.ps1"
    [IO.File]::WriteAllText($f, $body, (New-Object Text.UTF8Encoding($true)))
    return Start-Process -FilePath powershell.exe -PassThru -NoNewWindow `
              -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $f))
}
function Prompts { @(Get-Content -LiteralPath $counter -ErrorAction SilentlyContinue | Where-Object { $_ }).Count }
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { "  ok    $What" } else { $script:fail++; "  FAIL  $What" } }

function Wait-Quiet {
    # until no stand-in "window" is left holding the mutex
    for ($i = 0; $i -lt 300; $i++) {
        try { $x = [System.Threading.Mutex]::OpenExisting('Local\Csharf-SingleInstance'); $x.Dispose() } catch { return }
        Start-Sleep -Milliseconds 100
    }
}

# A: three starts 0.7 s apart, while the first one's prompt is still up
$t0 = Get-Date
$a = Start-Copy; Start-Sleep -Milliseconds 700
$b = Start-Copy; Start-Sleep -Milliseconds 700
$c = Start-Copy
foreach ($p in @($a, $b, $c)) { $p.WaitForExit() }
"  timing: three launchers done after {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds
Check ((Prompts) -eq 1) "three quick starts -> $(Prompts) prompt(s)"

# B: starts while the window is open -> no prompt at all
$d = Start-Copy; $d.WaitForExit()
Check ((Prompts) -eq 1) "start while the window is open -> no new prompt (total $(Prompts))"
Wait-Quiet

# C: nothing pending, nothing open -> a new start prompts again
$e = Start-Copy; $e.WaitForExit()
Check ((Prompts) -eq 2) "a later, separate start prompts normally (total $(Prompts))"
Wait-Quiet

# The copies that stepped aside deleted their extracted file. The ones that
# prompted leave it for the elevated window, which deletes it on exit.
$left = @(Get-ChildItem -LiteralPath $OutDir -Filter 'launch-*.ps1').Count
Check ($left -eq (Prompts)) "extracted files left = prompts ($left)"
Get-ChildItem -LiteralPath $OutDir -Filter 'launch-*.ps1' | Remove-Item -Force

# D: the WHOLE file - batch half included - opened twice within one second,
#    the way a double-click registered twice does it. Here the stand-in for
#    the prompt also checks, at the moment of "approval", that the script
#    the elevated copy will run still exists. 2.1 extracted both starts to
#    the same %RANDOM%-named file and the second start deleted it: the
#    prompt was approved and no window ever opened.
$fullCounter = Join-Path $OutDir 'full.txt'
Set-Content -LiteralPath $fullCounter -Value $null
$fakeFull = @'
$elevated = Start-Process -FilePath powershell.exe -PassThru -NoNewWindow -ArgumentList ('-NoProfile -Command "Add-Content -LiteralPath ''COUNTER'' -Value prompt; Start-Sleep -Seconds 4; if (Test-Path -LiteralPath ''' + $PSCommandPath + ''') { Add-Content -LiteralPath ''COUNTER'' -Value present } else { Add-Content -LiteralPath ''COUNTER'' -Value MISSING }; $m = New-Object System.Threading.Mutex($true, ''Local\Csharf-SingleInstance''); Start-Sleep -Seconds 8; $m.ReleaseMutex()"')
'@
$fakeFull = $fakeFull.Replace('COUNTER', $fullCounter)
$whole = [IO.File]::ReadAllText($Bat, (New-Object Text.UTF8Encoding($false)))
$at    = $whole.LastIndexOf($marker) + $marker.Length
$head  = $whole.Substring(0, $at)
$tail  = [regex]::Replace($whole.Substring($at), $rx, [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $fakeFull })
$fullBat = Join-Path $OutDir 'Csharf-full-test.bat'
[IO.File]::WriteAllText($fullBat, $head + $tail, (New-Object Text.UTF8Encoding($false)))
# The race depends on timing, so it runs three times; one lost script is a failure.
$prompts = 0; $present = 0; $missing = 0
for ($round = 1; $round -le 3; $round++) {
    Set-Content -LiteralPath $fullCounter -Value $null
    # Both starts inside one clock second - cmd seeds %RANDOM% from whole
    # seconds, which is what made 2.1's two starts share a file. Start right
    # after a second ticks over, back to back.
    $t0 = Get-Date; while ((Get-Date).Second -eq $t0.Second) { Start-Sleep -Milliseconds 5 }
    $s1 = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ""' + $fullBat + '""') -PassThru -NoNewWindow
    $s2 = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ""' + $fullBat + '""') -PassThru -NoNewWindow
    $s1.WaitForExit(); $s2.WaitForExit()
    Start-Sleep -Seconds 7
    Wait-Quiet
    $said = @(Get-Content -LiteralPath $fullCounter | Where-Object { $_ })
    "  round {0}: {1}" -f $round, ($said -join ', ')
    $prompts += @($said | Where-Object { $_ -eq 'prompt' }).Count
    $present += @($said | Where-Object { $_ -eq 'present' }).Count
    $missing += @($said | Where-Object { $_ -eq 'MISSING' }).Count
}
Check ($prompts -eq 3) "the whole file opened twice in one second, three times -> $prompts prompt(s)"
Check ($present -eq 3 -and $missing -eq 0) "at every approval the script is still there (present $present, missing $missing)"
Get-ChildItem -LiteralPath $env:TEMP -Filter 'Csharf_*.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-3) } | Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $fullBat -Force -ErrorAction SilentlyContinue
"RESULT: $fail failed"
exit $fail
