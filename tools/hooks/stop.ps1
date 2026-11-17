# Busy-state hook for test-gui.ps1: the stop button, the -NoStop guard, the
# argument quoting and the background-thread helper - all through the real
# functions and the real click handler. ASCII only (Hebrew is matched by
# code point, since this file has no BOM).

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))
$onClick = [System.Windows.Forms.Control].GetMethod('OnClick', [System.Reflection.BindingFlags]'NonPublic,Instance')
function Click-Bottom { [void]$onClick.Invoke($bExit, @([EventArgs]::Empty)) }

$HE_STOPPED = -join ([char[]](0x05E0,0x05E2,0x05E6,0x05E8,0x05D4))   # "stopped" (feminine)
$HE_EXIT    = -join ([char[]](0x05D9,0x05E6,0x05D9,0x05D0,0x05D4))   # "exit"

# ---- 1. stop a long external tool from the bottom button ---------------------
$script:seen = @{}
$tm = New-Object System.Windows.Forms.Timer
$tm.Interval = 1500
$tm.Add_Tick({
    $tm.Stop()
    $script:seen.Busy        = $script:Busy
    $script:seen.ExitEnabled = $bExit.Enabled
    $script:seen.ExitText    = $bExit.Text
    $script:seen.MenuOff     = -not ($script:MenuButtons | Where-Object { $_.Enabled })
    $script:seen.Ping        = @(Get-Process ping -ErrorAction SilentlyContinue).Count
    Click-Bottom
})
$tm.Start()
$t0 = Get-Date
Invoke-Action 'test' { Start-Tool 'ping.exe' @('-n', '30', '127.0.0.1') | Out-Null; Write-Ok 'SHOULD-NOT-APPEAR' }
$secs = ((Get-Date) - $t0).TotalSeconds
Start-Sleep -Milliseconds 300
Check ($script:seen.Busy -eq $true)        'while running: busy'
Check ($script:seen.MenuOff -eq $true)     'while running: every menu button disabled'
Check ($script:seen.ExitEnabled -eq $true) "while running: bottom button enabled, caption [$($script:seen.ExitText)]"
Check ($script:seen.Ping -ge 1)            "while running: ping.exe alive ($($script:seen.Ping))"
Check ($secs -lt 6)                        ("stopped after {0:N1}s of a 30s tool" -f $secs)
Check (@(Get-Process ping -ErrorAction SilentlyContinue).Count -eq 0) 'ping.exe killed'
Check ($log.Text -notmatch 'SHOULD-NOT-APPEAR') 'action did not carry on after the stop'
Check ($log.Text.Contains($HE_STOPPED))    'log says the action was stopped'
Check (-not $script:Busy)                  'idle again'
Check (-not ($script:MenuButtons | Where-Object { -not $_.Enabled })) 'menu buttons enabled again'
Check ($bExit.Text -eq $HE_EXIT)           "bottom button back to exit [$($bExit.Text)]"

# ---- 2. -NoStop: the button must not be able to cut it off --------------------
$script:seen = @{}
$tm2 = New-Object System.Windows.Forms.Timer
$tm2.Interval = 800
$tm2.Add_Tick({
    $tm2.Stop()
    $script:seen.ExitEnabled = $bExit.Enabled
    $script:seen.CanStop     = $script:CanStop
    Click-Bottom
})
$tm2.Start()
$t0 = Get-Date
Invoke-Action 'test2' { $script:code2 = Start-Tool 'ping.exe' @('-n', '3', '127.0.0.1') -NoStop; Write-Ok 'NOSTOP-FINISHED' }
$secs = ((Get-Date) - $t0).TotalSeconds
Check ($script:seen.ExitEnabled -eq $false) 'no-stop: bottom button disabled while running'
Check ($script:seen.CanStop -eq $false)     'no-stop: CanStop false'
Check ($log.Text -match 'NOSTOP-FINISHED' -and $script:code2 -eq 0) ("no-stop: ran to the end ({0:N1}s, exit {1})" -f $secs, $script:code2)

# ---- 3. argument quoting, unit and end to end --------------------------------
$cases = @(
    @('plain', 'plain'),
    @('a b', '"a b"'),
    @('C:\x y\', '"C:\x y\\"'),
    @('say "hi"', '"say \"hi\""'),
    @('', '""')
)
foreach ($c in $cases) {
    $got = Join-ProcessArguments @($c[0])
    Check ($got -eq $c[1]) "quote [$($c[0])] -> [$got]"
}
$dump = Join-Path $out 'argv.txt'
$printer = Join-Path $out 'printargs.ps1'
Set-Content -LiteralPath $printer -Value ('$args | ForEach-Object { "<$_>" } | Set-Content -LiteralPath ''' + $dump + '''') -Encoding ASCII
$weird = 'C:\Users\Dana Levi\OneDrive - Company\Desktop\battery-report.html'
$code = Start-Tool 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $printer, $weird, 'second')
$got = @(Get-Content -LiteralPath $dump -ErrorAction SilentlyContinue)
Check ($code -eq 0 -and $got.Count -eq 2 -and $got[0] -eq "<$weird>" -and $got[1] -eq '<second>') "end to end, the tool received: $($got -join ' ')"

# ---- 4. background thread helper ----------------------------------------------
$r = Invoke-Background -Arguments @(21) -Script { param($x) Start-Sleep -Milliseconds 300; [PSCustomObject]@{ A = $x * 2 } }
Check ((@($r) | Select-Object -Last 1).A -eq 42) "Invoke-Background returned $((@($r) | Select-Object -Last 1).A)"

$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
