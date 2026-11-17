# Progress hook for test-gui.ps1: the percentage a long tool prints reaches
# the bottom button, for both encodings the real tools use - DISM writes in
# the console code page with carriage returns, SFC writes UTF-16 - and the
# stop button still works while the output is being read. The tools are
# stand-ins that print exactly that way. ASCII only.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))
$onClick = [System.Windows.Forms.Control].GetMethod('OnClick', [System.Reflection.BindingFlags]'NonPublic,Instance')

$dismLike = Join-Path $out 'fake-dism.ps1'
Set-Content -LiteralPath $dismLike -Encoding Ascii -Value @'
param([int]$Steps = 10)
for ($i = 1; $i -le $Steps; $i++) {
    $pct = [Math]::Round($i * 100.0 / $Steps, 1)
    [Console]::Out.Write(("[{0}{1} {2:0.0}% ]`r" -f ('=' * $i), (' ' * ($Steps - $i)), $pct))
    [Console]::Out.Flush()
    Start-Sleep -Milliseconds 350
}
[Console]::Out.WriteLine(''); [Console]::Out.WriteLine('The operation completed successfully.')
exit 0
'@
$sfcLike = Join-Path $out 'fake-sfc.ps1'
Set-Content -LiteralPath $sfcLike -Encoding Ascii -Value @'
$o = [Console]::OpenStandardOutput()
foreach ($p in 5, 20, 35, 50, 65, 80, 95, 100) {
    $b = [Text.Encoding]::Unicode.GetBytes("Verification $p% complete.`r")
    $o.Write($b, 0, $b.Length); $o.Flush()
    Start-Sleep -Milliseconds 350
}
exit 3
'@

function Watch-Run {
    param([string]$Script, [string[]]$Extra = @(), [int]$StopAfterMs = 0)
    $script:seen = New-Object System.Collections.Generic.List[int]
    $tm = New-Object System.Windows.Forms.Timer
    $tm.Interval = 150
    $script:t0 = Get-Date
    $script:stopAt = $StopAfterMs
    $tm.Add_Tick({
        if ($bExit.Text -match '(\d{1,3})%') { $v = [int]$Matches[1]; if ($script:seen.Count -eq 0 -or $script:seen[$script:seen.Count - 1] -ne $v) { $script:seen.Add($v) } }
        if ($script:stopAt -gt 0 -and ((Get-Date) - $script:t0).TotalMilliseconds -gt $script:stopAt) { $script:stopAt = 0; [void]$onClick.Invoke($bExit, @([EventArgs]::Empty)) }
    })
    $tm.Start()
    $res = @{ Code = 'not set' }
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Extra
    Invoke-Action 'progress test' { $res.Code = Start-Tool 'powershell.exe' $args2 -Progress }.GetNewClosure()
    $script:code = $res.Code
    $tm.Stop(); $tm.Dispose()
    return ((Get-Date) - $script:t0).TotalSeconds
}

# 1. DISM-style output
$secs = Watch-Run $dismLike
Check ($script:seen.Count -ge 4) "DISM-style: percentages shown on the button: $($script:seen -join ', ')"
Check ((@($script:seen) -join ',') -eq (@($script:seen | Sort-Object) -join ',')) 'DISM-style: never goes backwards'
Check ($script:code -eq 0) "DISM-style: exit code passed through ($($script:code))"
Check ($bExit.Text -notmatch '%') 'DISM-style: percentage cleared once the tool ended'

# 2. SFC-style output (UTF-16)
$secs = Watch-Run $sfcLike
Check ($script:seen.Count -ge 4) "SFC-style (UTF-16): percentages shown: $($script:seen -join ', ')"
Check ($script:code -eq 3) "SFC-style: exit code passed through ($($script:code))"

# 3. Stop while the output is being read
$before = @(Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object Id)
$secs = Watch-Run $dismLike @('-Steps', '60') 1500
$left = @(Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id -and $_.Id -ne $PID })
Check ($secs -lt 5) ("stop during progress: ended after {0:N1}s of ~21s" -f $secs)
Check ($left.Count -eq 0) "stand-in tool killed ($($left.Count) left)"
Check (-not $script:Busy -and $bExit.Text -notmatch '%') 'idle again, no stale percentage'

$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
