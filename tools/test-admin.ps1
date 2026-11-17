# ============================================================================
#  test-admin.ps1  -  the checks that need administrator rights
#
#  Run it elevated, or let it ask once for elevation itself. It creates two
#  REAL restore points - one through the GUI edition's action, one through
#  the console edition's label, a few seconds apart, which also proves the
#  24-hour limit is lifted - and checks each really appeared and the limit
#  setting came back untouched. Results go to <OutDir>\admin-results.txt.
#  ASCII only.
# ============================================================================
param([Parameter(Mandatory = $true)][string]$OutDir, [switch]$Elevated)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir  = (Resolve-Path -LiteralPath $OutDir).Path
$results = Join-Path $OutDir 'admin-results.txt'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    if ($Elevated) { 'still not admin after elevation' | Set-Content -LiteralPath $results; exit 1 }
    $p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-OutDir', ('"{0}"' -f $OutDir), '-Elevated')
    if (Test-Path -LiteralPath $results) { Get-Content -LiteralPath $results }
    exit $p.ExitCode
}

$lines = New-Object System.Collections.Generic.List[string]
$fail  = 0
try {
    # --- GUI edition ---
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-gui.ps1') `
            -Hook (Join-Path $PSScriptRoot 'hooks\restorepoint.ps1') -OutDir $OutDir -Tag 'gui-restore' 2>&1
    $lines.Add('--- GUI: restore point ---')
    foreach ($l in $o) { $lines.Add([string]$l) }
    if (($o -join ' ') -notmatch 'RESULT: 0 failed') { $fail++ }

    # --- console edition ---
    $lines.Add('--- console: restore point ---')
    $cp   = [Text.Encoding]::GetEncoding(862)
    $text = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf-CMD.bat'), $cp)
    $nl   = "`r`n"
    $text = $text.Replace(('CD /D "%~dp0"' + $nl), ('CD /D "%~dp0"' + $nl + 'if not "%~1"=="" call %* & exit /b' + $nl))
    foreach ($e in @(@(':END_OK', 10), @(':END_FAIL', 11))) {
        $text = $text.Replace(($nl + $e[0] + $nl), ($nl + $e[0] + $nl + "echo CSHARF-RC=$($e[1])" + $nl + "exit /b $($e[1])" + $nl))
    }
    $bat = Join-Path $OutDir 'csharf-cmd-admin.bat'
    [IO.File]::WriteAllText($bat, $text, $cp)
    $key   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freq0 = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    $n0    = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1).SequenceNumber
    $log   = Join-Path $OutDir 'cmd-restore.txt'
    $p = Start-Process -FilePath $env:ComSpec -Wait -PassThru -NoNewWindow -ArgumentList ('/d /c ""' + $bat + '" :RESTORE_POINT >"' + $log + '" 2>&1"')
    $said  = [IO.File]::ReadAllText($log, $cp)
    $rc    = if ($said -match 'CSHARF-RC=(\d+)') { [int]$Matches[1] } else { -1 }
    $n1    = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1).SequenceNumber
    $freq1 = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    foreach ($c in @(
        @(($rc -eq 10), "ending: code $rc (10 = done)"),
        @(($null -ne $n1 -and $n1 -ne $n0), "a new restore point exists (newest $n0 -> $n1)"),
        @(("$freq0" -eq "$freq1"), "24-hour limit setting restored ([$freq0] -> [$freq1])"))) {
        if ($c[0]) { $lines.Add("  ok    $($c[1])") } else { $fail++; $lines.Add("  FAIL  $($c[1])") }
    }
    Remove-Item -LiteralPath $bat -Force -ErrorAction SilentlyContinue
} catch {
    $fail++; $lines.Add("  FAIL  exception: $($_.Exception.Message)")
}
$lines.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines($results, $lines, (New-Object Text.UTF8Encoding($true)))
exit $fail
