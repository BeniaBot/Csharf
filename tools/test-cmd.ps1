# ============================================================================
#  test-cmd.ps1  -  runs the console edition's real actions, one at a time
#
#  Makes a test copy of Csharf-CMD.bat (same code page, same bytes apart from
#  these anchored changes, each of which must match exactly once):
#    - the admin check is skipped              (no UAC prompt in a test run)
#    - "Csharf-CMD.bat :LABEL args" runs that one label and returns
#    - each of the four endings returns a code instead of going back to the
#      menu: 10 ok, 11 failed, 12 cancelled, 13 nothing to change
#  Then drives the power-plan actions against the real machine and restores
#  the active plan. Back up first:
#    reg export "HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" before.reg
#
#  Run NON-elevated: what needs admin must then fail cleanly, which is tested
#  too. ASCII only.
# ============================================================================
param(
    [string]$Bat = '',
    [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
if (-not $Bat) { $Bat = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf-CMD.bat' }
$cp   = [Text.Encoding]::GetEncoding(862)
$text = [IO.File]::ReadAllText($Bat, $cp)

function Replace-Once {
    param([string]$Source, [string]$Find, [string]$With)
    $n = ([regex]::Matches($Source, [regex]::Escape($Find))).Count
    if ($n -ne 1) { throw "anchor [$Find] matched $n times, expected 1" }
    return $Source.Replace($Find, $With)
}
$nl = "`r`n"
$text = Replace-Once $text 'if %errorlevel% EQU 0 goto :gotAdmin' 'goto :gotAdmin'
$text = Replace-Once $text ('CD /D "%~dp0"' + $nl) ('CD /D "%~dp0"' + $nl + 'if not "%~1"=="" call %* & exit /b' + $nl)
$text = Replace-Once $text ($nl + ':END_OK' + $nl)       ($nl + ':END_OK' + $nl + 'echo CSHARF-RC=10' + $nl + 'exit /b 10' + $nl)
$text = Replace-Once $text ($nl + ':END_FAIL' + $nl)     ($nl + ':END_FAIL' + $nl + 'echo CSHARF-RC=11' + $nl + 'exit /b 11' + $nl)
$text = Replace-Once $text ($nl + ':END_CANCEL' + $nl)   ($nl + ':END_CANCEL' + $nl + 'echo CSHARF-RC=12' + $nl + 'exit /b 12' + $nl)
$text = Replace-Once $text ($nl + ':END_NOCHANGE' + $nl) ($nl + ':END_NOCHANGE' + $nl + 'echo CSHARF-RC=13' + $nl + 'exit /b 13' + $nl)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$test   = Join-Path $OutDir 'csharf-cmd-test.bat'
[IO.File]::WriteAllText($test, $text, $cp)

function Run {
    param([string]$Label, [string]$Arg = '')
    $log = Join-Path $OutDir ("out-" + $Label.TrimStart(':') + ".txt")
    $cmdline = '/d /c ""' + $test + '" ' + $Label + $(if ($Arg) { ' "' + $Arg + '"' }) + ' >"' + $log + '" 2>&1"'
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList $cmdline -Wait -PassThru -NoNewWindow
    # The ending prints its code: an exit code does not survive "cmd /c" with
    # a redirect reliably.
    $said = [IO.File]::ReadAllText($log, $cp)
    if ($said -match 'CSHARF-RC=(\d+)') { return [int]$Matches[1] }
    return -1
}

$PSR = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$GB  = '381b4222-f694-41f0-9685-ff5bb260df2e'; $GH = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$CSU = 'c54a2f10-7e1b-4d6a-9b3e-5c0a1e2f0001'
function Plans  { @(Get-ChildItem -LiteralPath $PSR).Count }
function Active { if (((cmd /c 'powercfg /getactivescheme') -join ' ') -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] } }
function Has    { param($g) Test-Path -LiteralPath (Join-Path $PSR $g) }
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { "  ok    $What" } else { $script:fail++; "  FAIL  $What" } }

$orig = Active
"start: $(Plans) plans, active $orig"
$made = @()
try {
    # --- leftovers of the kind older versions made, plus one a person named ---
    foreach ($spec in @(@{ n = $null; d = $null }, @{ n = 'Ultimate Performance'; d = 'Csharf' }, @{ n = 'My own plan'; d = 'mine' })) {
        $o = (cmd /c "powercfg -duplicatescheme $GH 2>&1") -join ' '
        if ($o -match '([0-9a-f]{8}-[0-9a-f-]{27})') {
            $g = $Matches[1]; $made += $g
            if ($spec.n) { cmd /c "powercfg -changename $g `"$($spec.n)`" `"$($spec.d)`"" | Out-Null }
        }
    }
    $mine = $made[2]
    $n0 = Plans

    $rc = Run ':HIGHPERF';  Check ($rc -eq 10 -and (Active) -eq $GH) "HIGHPERF -> code $rc, active $(Active)"
    $rc = Run ':HIGHPERF';  Check ($rc -eq 10 -and (Plans) -eq $n0)  "HIGHPERF again -> no new plan ($n0 -> $(Plans))"

    $rc = Run ':ULTRAPERF'; Check ($rc -eq 10 -and (Active) -eq $CSU) "ULTRAPERF -> code $rc, active $(Active)"
    $n1 = Plans
    $rc = Run ':ULTRAPERF'; $rc2 = Run ':ULTRAPERF'
    Check ($rc -eq 10 -and $rc2 -eq 10 -and (Plans) -eq $n1) "ULTRAPERF x3 -> one copy ($n1 -> $(Plans))"

    $rc = Run ':RESTORE_BALANCED'
    Check ($rc -eq 10 -and (Active) -eq $GB) "RESTORE_BALANCED -> code $rc, active $(Active)"
    Check (-not (Has $CSU))      'own Ultimate copy removed'
    Check (-not (Has $made[0]))  'nameless copy of High performance removed'
    Check (-not (Has $made[1]))  'plan described "Csharf" removed'
    Check (Has $mine)            'plan a person named kept'
    foreach ($g in @($GB, $GH)) { Check (Has $g) "built-in kept: $g" }
    $said = [IO.File]::ReadAllLines((Join-Path $OutDir 'out-RESTORE_BALANCED.txt'), $cp)
    "        (printed: $(@($said | Where-Object { $_ -match '\d' }) -join ' / '))"

    # --- needs admin: must report a failure and change nothing ---
    $hib = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled
    $rc = Run ':HIBER_ON'
    $after = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled
    Check ($rc -eq 11 -and $after -eq $hib) "HIBER_ON without admin -> code $rc (failed), hibernate unchanged ($hib)"

    # --- this PC is already Pro: nothing to do ---
    $ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    $rc = Run ':UPGRADE_PRO'
    if ($ed -match '^Professional') { Check ($rc -eq 13) "UPGRADE_PRO on $ed -> code $rc (no change)" }
    else { "        UPGRADE_PRO not run: this PC is $ed" }

    # --- the temp-folder guard, on a substituted drive so a mistake costs nothing ---
    $root = Join-Path $OutDir 'fakedrive'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Temp\sub') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'keep.txt') -Value 'x'
    Set-Content -LiteralPath (Join-Path $root 'Temp\a.tmp') -Value 'x'
    Set-Content -LiteralPath (Join-Path $root 'Temp\sub\b.tmp') -Value 'x'
    $letter = $null
    foreach ($l in 'Q','R','S','T','U','V','W') { if (-not (Test-Path "${l}:\")) { $letter = $l; break } }
    cmd /c "subst ${letter}: `"$root`"" | Out-Null
    try {
        [void](Run ':CLEAN_DIR' "${letter}:\");  Check (Test-Path -LiteralPath (Join-Path $root 'keep.txt')) "CLEAN_DIR refuses a drive root (${letter}:\)"
        [void](Run ':CLEAN_DIR' "${letter}:");   Check (Test-Path -LiteralPath (Join-Path $root 'keep.txt')) "CLEAN_DIR refuses a bare drive (${letter}:)"
        [void](Run ':CLEAN_DIR' '');             Check (Test-Path -LiteralPath (Join-Path $root 'keep.txt')) 'CLEAN_DIR refuses an empty path'
        [void](Run ':CLEAN_DIR' "${letter}:\Temp")
        $leftTemp = @(Get-ChildItem -LiteralPath (Join-Path $root 'Temp') -Force).Count
        Check ($leftTemp -eq 0 -and (Test-Path -LiteralPath (Join-Path $root 'Temp')) -and (Test-Path -LiteralPath (Join-Path $root 'keep.txt'))) "CLEAN_DIR empties a real temp folder and only it ($leftTemp left inside)"
    } finally {
        cmd /c "subst ${letter}: /d" | Out-Null
    }
} finally {
    foreach ($g in $made) { if (Has $g) { cmd /c "powercfg /delete $g" | Out-Null } }
    if ($orig) { cmd /c "powercfg /setactive $orig" | Out-Null }
    "end: $(Plans) plans, active $(Active)"
}
"RESULT: $fail failed"
exit $fail
