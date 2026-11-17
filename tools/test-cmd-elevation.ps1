# ============================================================================
#  test-cmd-elevation.ps1  -  the console edition's way into the admin window
#
#  Runs the real two-stage start of Csharf-CMD.bat with ONE change in a test
#  copy: the VBS asks Windows to "open" instead of "runas", so the second
#  window opens without a UAC prompt (and, not being elevated, stops on the
#  "needs admin" screen - all this test needs). Started through the shell,
#  exactly like a double-click. Checks, for a path with Hebrew letters, a
#  space and brackets, and for a path with an & and no space:
#    - the second stage receives its own path and /elevated intact
#    - it runs in a classic console started through conhost (the font fix),
#      or through plain cmd for the &-without-space path
#    - the temporary font key is gone again once the second stage runs
#    - a font key somebody made themselves is left exactly as it was
#  The registry is read and written through the shell too (a headless
#  console started from a shortcut), so the test sees the same HKCU the
#  product does even inside a sandboxed or packaged session.
#  Photographs the window to <OutDir>\elevated-window.png. Run NON-elevated.
#  ASCII only.
# ============================================================================
param([Parameter(Mandatory = $true)][string]$OutDir, [string]$Bat = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'
if (-not $Bat)     { $Bat = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf-CMD.bat' }
if (-not $WorkDir) { $WorkDir = $env:TEMP }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Drawing;
public static class TE {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public static List<long> Consoles() { var r = new List<long>();
    EnumWindows((h,l) => { var c = new StringBuilder(100); GetClassName(h, c, 100); var k = c.ToString();
      if (IsWindowVisible(h) && (k == "ConsoleWindowClass" || k == "CASCADIA_HOSTING_WINDOW_CLASS")) r.Add(h.ToInt64()); return true; }, IntPtr.Zero); return r; }
  public static string Cls(long hw) { var c = new StringBuilder(100); GetClassName(new IntPtr(hw), c, 100); return c.ToString(); }
  public static void Save(long hw, string f) { var h = new IntPtr(hw); RECT rc; GetWindowRect(h, out rc);
    using (var b = new Bitmap(rc.R - rc.L, rc.B - rc.T)) { using (var g = Graphics.FromImage(b)) { var dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); } b.Save(f); } }
}
"@
[void][TE]::SetProcessDPIAware()
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { "  ok    $What" } else { $script:fail++; "  FAIL  $What" } }

$cp    = [Text.Encoding]::GetEncoding(862)
$base  = Join-Path $WorkDir ('csharf-elev-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $base | Out-Null
$KEY   = 'HKCU\Console\%%SystemRoot%%_System32_conhost.exe'

function Invoke-Outside {
    # Runs batch lines the way the product runs: started by the shell. A
    # shortcut to a headless console host keeps it windowless.
    param([string[]]$Lines)
    $id   = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $out  = Join-Path $base "o-$id.txt"
    $bat  = Join-Path $base "x-$id.bat"
    $lnk  = Join-Path $base "x-$id.lnk"
    [IO.File]::WriteAllText($bat, ("@echo off`r`n(`r`n" + ($Lines -join "`r`n") + "`r`n) > `"$out`" 2>&1`r`n"), $cp)
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = "$env:SystemRoot\System32\conhost.exe"
    $sc.Arguments  = "--headless cmd.exe /d /c call `"$bat`""
    $sc.WindowStyle = 7
    $sc.Save()
    Start-Process explorer.exe -ArgumentList ('"' + $lnk + '"')
    for ($i = 0; $i -lt 60 -and -not (Test-Path -LiteralPath $out); $i++) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Milliseconds 300
    $text = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out, $cp) } else { '<<no output>>' }
    Remove-Item -LiteralPath $out, $bat, $lnk -Force -ErrorAction SilentlyContinue
    return $text
}
function Get-RealKey { Invoke-Outside @("reg query `"$KEY`"") }

$initial = Get-RealKey
if ($initial -match 'FaceName' -and $initial -notmatch 'CsharfTemporary') {
    "  SKIP  a font key of your own exists in HKCU\Console - not touching it, test not run"
    exit 0
}
if ($initial -match 'CsharfTemporary') { [void](Invoke-Outside @("reg delete `"$KEY`" /f")) }

$text  = [IO.File]::ReadAllText($Bat, $cp)
$runas = '"", "runas", 1 >> "%temp%\getadmin.vbs"'
if (([regex]::Matches($text, [regex]::Escape($runas))).Count -ne 1) { throw 'runas anchor not found exactly once' }
$openText = $text.Replace($runas, '"", "open", 1 >> "%temp%\getadmin.vbs"')

function Run-Stage {
    param([string]$Path, [string]$Shot, [string]$WantHost)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $openText, $cp)
    $before = [TE]::Consoles()
    Start-Process explorer.exe -ArgumentList ('"' + $Path + '"')
    $stage2 = $null
    for ($i = 0; $i -lt 75 -and -not $stage2; $i++) {
        Start-Sleep -Milliseconds 200
        $stage2 = Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $_.CommandLine -like '*/elevated*' -and $_.CommandLine.Contains($Path) } | Select-Object -First 1
    }
    Check ($null -ne $stage2) "second stage started for  $Path"
    if (-not $stage2) { return }
    "        its command line: $($stage2.CommandLine)"
    # conhost quotes an argument only when it holds a space - a path without
    # one arrives bare, which is fine for it (the &-without-space path is the
    # one that goes through plain cmd instead).
    $want = if ($WantHost -eq 'conhost' -and $Path -notmatch ' ') { "/c call $Path /elevated" } else { "/c call `"$Path`" /elevated" }
    Check ($stage2.CommandLine.EndsWith($want)) 'path and /elevated arrived intact'
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($stage2.ParentProcessId)"
    if ($WantHost -eq 'conhost') { Check ($parent.Name -eq 'conhost.exe') "started through conhost (parent: $($parent.Name))" }
    else                         { Check ($parent.Name -ne 'conhost.exe') "started through plain cmd (parent: $($parent.Name))" }
    Start-Sleep -Milliseconds 1500
    $new = @([TE]::Consoles() | Where-Object { $before -notcontains $_ })
    $hw  = $new | Where-Object { [TE]::Cls($_) -eq 'ConsoleWindowClass' } | Select-Object -First 1
    if ($hw -and $Shot) { [TE]::Save($hw, $Shot); "        photo: $Shot" }
    foreach ($w in $new) { [void][TE]::PostMessage([IntPtr]$w, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
    Start-Sleep -Milliseconds 800
    Check (@($new | Where-Object { [TE]::IsWindow([IntPtr]$_) }).Count -eq 0) 'its windows closed again'
    Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Path) } |
        ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>&1 | Out-Null }
}

try {
    $hard = Join-Path $base ('csharf ' + [char]0x05D1 + [char]0x05D3 + [char]0x05D9 + [char]0x05E7 + [char]0x05D4 + ' (1)\Csharf-CMD (1).bat')
    Run-Stage -Path $hard -Shot (Join-Path $OutDir 'elevated-window.png') -WantHost 'conhost'
    $k = Get-RealKey
    Check ($k -notmatch 'CsharfTemporary') 'the temporary font key is gone once the second stage runs'

    $amp = Join-Path $base 'a&b\Csharf-CMD.bat'
    Run-Stage -Path $amp -Shot '' -WantHost 'cmd'
    [void](Invoke-Outside @("reg query `"$KEY`" /v CsharfTemporary >nul 2>&1 && reg delete `"$KEY`" /f"))

    # Somebody's own key: left exactly as it was, through both stages.
    [void](Invoke-Outside @("reg add `"$KEY`" /v FaceName /t REG_SZ /d `"Lucida Console`" /f"))
    Run-Stage -Path (Join-Path $base 'own\Csharf-CMD.bat') -Shot '' -WantHost 'conhost'
    $k = Get-RealKey
    Check ($k -match 'Lucida Console' -and $k -notmatch 'CsharfTemporary') 'a key without our mark is left exactly as it was'
} finally {
    # Back to how the machine was: no key, or our own leftover removed.
    [void](Invoke-Outside @("reg query `"$KEY`" /v FaceName 2>nul | findstr /C:`"Lucida Console`" >nul && reg delete `"$KEY`" /f", "reg query `"$KEY`" /v CsharfTemporary >nul 2>&1 && reg delete `"$KEY`" /f"))
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT: $fail failed"
exit $fail
