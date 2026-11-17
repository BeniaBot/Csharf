# Power-plan hook for test-gui.ps1 - drives the REAL actions against the real
# machine, so back up first:
#   reg export "HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" before.reg
# Checks that repeated clicks never add plans, that the official / fallback
# Ultimate plan really becomes active, and that "Balanced" clears what older
# versions left behind without touching plans somebody named themselves.
# The originally active plan is restored at the end. ASCII only.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $rep.Add("  ok    $What") } else { $script:fail++; $rep.Add("  FAIL  $What") } }
function N { @(Get-AllSchemes).Count }
function LastLog { ($log.Lines | Where-Object { $_ } | Select-Object -Last 1) }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

$orig    = (Get-ActiveScheme).Guid
$foreign = @(Get-AllSchemes | Where-Object { $_.Name -match 'Benjamin' -or $_.Description -match 'רשמי' } | ForEach-Object Guid)
$rep.Add("start: $(N) plans, active $orig, leftovers $(@(Get-LeftoverSchemes -Active $orig).Count), hand-named kept aside: $($foreign.Count)")
try {
    $n0 = N
    Action-HighPerf;  $rep.Add("  log: $(LastLog)")
    Action-HighPerf
    $n1 = N
    Check ($n1 -le $n0 + 1) "High performance x2: plans $n0 -> $n1 (no growth per click)"
    Check ((Get-SchemeLabel) -eq 'ביצועים גבוהים') "status shows high performance: $(Get-SchemeLabel)"

    Action-UltraPerf; $rep.Add("  log: $(LastLog)")
    $n2 = N
    Action-UltraPerf; Action-UltraPerf
    $n3 = N
    Check ($n3 -eq $n2) "Ultimate x3: plans $n2 -> $n3 (one copy, ever)"
    Check ((Get-ActiveScheme).Guid -eq $GUID_CS_ULT) "Ultimate is the active plan: $((Get-ActiveScheme).Guid)"
    # current AC and DC index of one processor setting = the last two hex numbers
    $q = { param($plan, $set) @([regex]::Matches(((& powercfg.exe /qh $plan SUB_PROCESSOR $set 2>$null) -join ' '), '0x[0-9a-fA-F]{8}') |
             Select-Object -Last 2 | ForEach-Object { [Convert]::ToInt32($_.Value, 16) }) }
    $idle = & $q $GUID_CS_ULT 'IDLEDISABLE'
    Check ($idle.Count -eq 2 -and $idle[0] -eq 0 -and $idle[1] -eq 0) "processor idle states allowed on mains and battery (AC/DC $($idle -join '/'))"
    $pmin = & $q $GUID_CS_ULT 'PROCTHROTTLEMIN'
    $base = & $q $(if (Test-Scheme $GUID_HIGHPERF) { $GUID_HIGHPERF } else { $GUID_BALANCED }) 'PROCTHROTTLEMIN'
    Check ($pmin.Count -eq 2 -and $pmin[0] -eq 100 -and $pmin[1] -eq $base[1]) "full speed on mains only: min CPU AC $($pmin[0])%, DC $($pmin[1])% = base plan's $($base[1])%"
    Check ((Get-SchemeLabel) -eq 'ביצועים אולטימטיביים') "status shows ultimate: $(Get-SchemeLabel)"

    Action-HighPerf
    Check ((Get-ActiveScheme).Guid -in @($GUID_HIGHPERF, $GUID_CS_HIGH)) "back to high performance"

    $left = @(Get-LeftoverSchemes -Active $GUID_BALANCED).Count
    Action-Balanced;  $rep.Add("  log: $(LastLog)")
    $n4 = N
    Check ((Get-ActiveScheme).Guid -eq $GUID_BALANCED) "Balanced is active"
    Check (@(Get-LeftoverSchemes -Active $GUID_BALANCED).Count -eq 0) "leftovers after Balanced: $(@(Get-LeftoverSchemes -Active $GUID_BALANCED).Count) (were $left)"
    Check (-not (Test-Scheme $GUID_CS_ULT)) "own Ultimate copy removed"
    foreach ($g in $foreign) { Check (Test-Scheme $g) "hand-named plan kept: $g" }
    foreach ($g in @($GUID_BALANCED, $GUID_HIGHPERF, $GUID_SAVER)) { if ((Get-AllSchemes).Guid -contains $g -or $g -eq $GUID_BALANCED) { Check (Test-Scheme $g) "built-in kept: $g" } }
    $rep.Add("end: $(N) plans")
} catch {
    $fail++; $rep.Add("  FAIL  exception: $($_.Exception.Message)")
} finally {
    if ($orig) { [void](Set-ActiveScheme $orig) }
    $rep.Add("restored active: $((Get-ActiveScheme).Guid)")
}
$rep.Add("--- full log ---")
foreach ($l in $log.Lines) { if ($l) { $rep.Add("  $l") } }
$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
