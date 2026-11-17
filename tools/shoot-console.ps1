# ============================================================================
#  shoot-console.ps1  -  photograph the console edition's menu
#
#  Opens a test copy of Csharf-CMD.bat (admin check skipped) through the
#  shell, so it lands in the default terminal - Windows Terminal on Windows 11
#  - photographs the window with PrintWindow, crops it to the menu, and then
#  closes the WINDOW (WM_CLOSE). Killing cmd alone leaves "choice" holding the
#  window open. Nothing on the machine changes. ASCII only.
#
#  powershell -File tools\shoot-console.ps1 -Out docs\screenshot-console.png
# ============================================================================
param([Parameter(Mandatory = $true)][string]$Out, [string]$Bat = '', [int]$CropWidth = 600, [int]$CropHeight = 560)
$ErrorActionPreference = 'Stop'
if (-not $Bat) { $Bat = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf-CMD.bat' }
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Drawing;
public static class SC {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public static List<long> Find(string t) { var r = new List<long>();
    EnumWindows((h,l) => { var s = new StringBuilder(300); GetWindowText(h, s, 300); if (IsWindowVisible(h) && s.ToString().Contains(t)) r.Add(h.ToInt64()); return true; }, IntPtr.Zero); return r; }
  public static void Save(long hw, string f, int cw, int ch) { var h = new IntPtr(hw); RECT rc; GetWindowRect(h, out rc); int w = rc.R - rc.L, ht = rc.B - rc.T;
    using (var b = new Bitmap(w, ht)) { using (var g = Graphics.FromImage(b)) { var dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); }
      using (var c = b.Clone(new Rectangle(0, 0, Math.Min(cw, w), Math.Min(ch, ht)), b.PixelFormat)) c.Save(f); } }
}
"@
[void][SC]::SetProcessDPIAware()
$cp   = [Text.Encoding]::GetEncoding(862)
$text = [IO.File]::ReadAllText($Bat, $cp)
if (-not $text.Contains('if %errorlevel% EQU 0 goto :gotAdmin')) { throw 'admin-check anchor not found' }
$copy = Join-Path $env:TEMP ('csharf-shot-' + [guid]::NewGuid().ToString('N') + '.bat')
[IO.File]::WriteAllText($copy, $text.Replace('if %errorlevel% EQU 0 goto :gotAdmin', 'goto :gotAdmin'), $cp)
$title = 'Csharf '
$before = [SC]::Find($title)
try {
    Start-Process explorer.exe -ArgumentList ('"' + $copy + '"')
    $hw = $null
    for ($i = 0; $i -lt 75 -and -not $hw; $i++) { Start-Sleep -Milliseconds 200; foreach ($w in [SC]::Find($title)) { if ($before -notcontains $w) { $hw = $w } } }
    if (-not $hw) { throw 'the console window never appeared' }
    Start-Sleep -Milliseconds 2500
    [SC]::Save($hw, $Out, $CropWidth, $CropHeight)
    "saved $Out"
    [void][SC]::PostMessage([IntPtr]$hw, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 1000
    "window closed: $(-not [SC]::IsWindow([IntPtr]$hw))"
} finally {
    Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
}
