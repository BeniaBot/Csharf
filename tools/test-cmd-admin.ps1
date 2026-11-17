# ============================================================================
#  test-cmd-admin.ps1  -  the console edition's admin actions, for real
#
#  !! CHANGES THE MACHINE !!  Hibernation, a desktop shortcut, temp files,
#  the recycle bin, cleanmgr's preset. Run it only inside a disposable
#  virtual machine, as administrator (test-cmd.ps1 is the one for a normal,
#  non-elevated prompt).
#
#  Same test copy as test-cmd.ps1: the admin check skipped, one label run at
#  a time, and the four endings returning 10 ok / 11 failed / 12 cancelled /
#  13 nothing to change. Answers to the 1/2 questions are piped in.
#  The report goes OUTSIDE %TEMP% - the cleanup empties it.
#  ASCII only - Windows PowerShell reads a BOM-less script as ANSI.
# ============================================================================
param(
    [string]$Bat = '',
    [string]$OutDir = (Join-Path $env:SystemDrive 'csharf-cmd-admin-test'),
    [switch]$ThisIsADisposableTestMachine
)
$ErrorActionPreference = 'Stop'
if (-not $ThisIsADisposableTestMachine) { throw 'Run it only in a disposable VM, as administrator, with -ThisIsADisposableTestMachine.' }
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
foreach ($e in @(@('END_OK', 10), @('END_FAIL', 11), @('END_CANCEL', 12), @('END_NOCHANGE', 13))) {
    $text = Replace-Once $text ($nl + ':' + $e[0] + $nl) ($nl + ':' + $e[0] + $nl + 'echo CSHARF-RC=' + $e[1] + $nl + 'exit /b ' + $e[1] + $nl)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$test = Join-Path $OutDir 'csharf-cmd-test.bat'
[IO.File]::WriteAllText($test, $text, $cp)

function Run {
    param([string]$Label, [string]$Answer = '')
    $log = Join-Path $OutDir ('out-' + $Label.TrimStart(':') + '.txt')
    $feed = if ($Answer) { 'echo ' + $Answer + '| ' } else { '' }
    $cmdline = '/d /c "' + $feed + '"' + $test + '" ' + $Label + ' >"' + $log + '" 2>&1"'
    Start-Process -FilePath $env:ComSpec -ArgumentList $cmdline -Wait -NoNewWindow
    $said = [IO.File]::ReadAllText($log, $cp)
    if ($said -match 'CSHARF-RC=(\d+)') { return [int]$Matches[1] }
    return -1
}
$fail = 0
$rep = New-Object System.Collections.Generic.List[string]
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }
function Hib { [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled }

# --- hibernation: whatever the code says must match the registry
$rc = Run ':HIBER_OFF'; $h = Hib
Check (($rc -eq 10 -and -not $h) -or ($rc -eq 11 -and $h)) "HIBER_OFF -> code $rc, enabled=$h"
$rc = Run ':HIBER_ON';  $h = Hib
Check (($rc -eq 10 -and $h) -or ($rc -eq 11 -and -not $h)) "HIBER_ON -> code $rc, enabled=$h"

# --- the all-apps shortcut
$before = @(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Desktop')) -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object Name)
$rc = Run ':CREATE_SHORTCUT'
$new = @(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Desktop')) -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Name })
if ($new.Count -eq 0) { $new = @(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Desktop')) -Filter *.lnk -ErrorAction SilentlyContinue) }
$ok = $false; $desc = 'none'
foreach ($l in $new) { $s = (New-Object -ComObject WScript.Shell).CreateShortcut($l.FullName); $desc = "$($l.Name): $($s.TargetPath) $($s.Arguments)"; if ("$($s.TargetPath) $($s.Arguments)" -match 'AppsFolder') { $ok = $true } }
Check ($rc -eq 10 -and $ok) "CREATE_SHORTCUT -> code $rc, $desc"

# --- cleanup, answering 2 (keep) to the Windows.old question
$tmpU = Join-Path $env:LOCALAPPDATA 'Temp'; $tmpW = Join-Path $env:SystemRoot 'Temp'
foreach ($d in $tmpU, $tmpW) { Set-Content -LiteralPath (Join-Path $d 'csharf-cmd-test.txt') -Value 'x' }
$winOld = Join-Path $env:SystemDrive 'Windows.old'
New-Item -ItemType Directory -Force -Path $winOld | Out-Null
Set-Content -LiteralPath (Join-Path $winOld 'csharf-keep.txt') -Value 'keep me'
$rc = Run ':DISK_CLEANUP' '2'
$said = [IO.File]::ReadAllText((Join-Path $OutDir 'out-DISK_CLEANUP.txt'), $cp)
Check ($said -match 'Windows\.old') 'DISK_CLEANUP asked about Windows.old'
Check (Test-Path -LiteralPath (Join-Path $winOld 'csharf-keep.txt')) "DISK_CLEANUP kept Windows.old on answer 2 (code $rc)"
foreach ($d in $tmpU, $tmpW) { Check (-not (Test-Path -LiteralPath (Join-Path $d 'csharf-cmd-test.txt'))) "DISK_CLEANUP emptied $d" }
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$on = @(Get-ChildItem -LiteralPath $vc | Where-Object { (Get-ItemProperty -LiteralPath $_.PSPath).StateFlags0001 -eq 2 } | ForEach-Object { $_.PSChildName })
Check (-not ($on -contains 'Previous Installations')) 'DISK_CLEANUP: "Previous Installations" not ticked'
$made = @(Get-ChildItem -LiteralPath $vc | Where-Object { $k = Get-Item -LiteralPath $_.PSPath; ($null -eq $k.GetValue('')) -and (@($k.GetValueNames() | Where-Object { $_ -and $_ -notmatch '^StateFlags' }).Count -eq 0) } | ForEach-Object { $_.PSChildName })
$rep.Add('  note  handler keys holding nothing but StateFlags (created by the batch, no handler behind them): ' + $(if ($made) { $made -join ', ' } else { 'none' }))
if (Test-Path -LiteralPath $winOld) { try { [IO.Directory]::Delete($winOld, $true) } catch { } }

# --- this VM is Pro already
$ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
$rc = Run ':UPGRADE_PRO'
if ($ed -match '^Professional') { Check ($rc -eq 13) "UPGRADE_PRO on $ed -> code $rc (no change)" }

# --- restore point, as administrator
$rp0 = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
$rc = Run ':RESTORE_POINT'
$rp1 = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
Check (($rc -eq 10) -eq ($rp1 -gt $rp0)) "RESTORE_POINT -> code $rc, restore points $rp0 -> $rp1"

$rep.Insert(0, "console admin: $(if ($fail) { "$fail FAILED" } else { 'all ok' })")
[IO.File]::WriteAllLines((Join-Path $OutDir 'report.txt'), $rep, (New-Object Text.UTF8Encoding($true)))
$rep
exit $fail
