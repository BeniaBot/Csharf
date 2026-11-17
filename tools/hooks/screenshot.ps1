# Screenshot hook for test-gui.ps1: shows the real window OFF-SCREEN (no
# taskbar button, nothing appears on the desktop), lets Windows paint it with
# its real frame, photographs it with PrintWindow and saves it to
# $env:CSHARF_SHOT. DrawToBitmap is no use here: it never paints the text of
# a RichTextBox, so the log would come out empty, and an unshown window gets
# an old-style frame.
#
# The example log comes from running two real actions through Invoke-Action,
# with the one function that would change the machine (Set-ActiveScheme) and
# the leftover scan replaced by stand-ins - the log shows the product's own
# messages and nothing on this PC changes. ASCII only.

Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public static class ShotPW {
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  // The form has RightToLeftLayout, i.e. a mirrored window DC, and
  // PrintWindow hands over that mirror image - flip it back.
  public static void Save(IntPtr h, int w, int ht, string file) {
    using (var b = new Bitmap(w, ht)) { using (var g = Graphics.FromImage(b)) { var dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); }
      b.RotateFlip(RotateFlipType.RotateNoneFlipX); b.Save(file); }
  }
}
"@

function Set-ActiveScheme { param([string]$Guid) return $true }
function Get-LeftoverSchemes { param([string]$Active) }

$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.Location      = New-Object System.Drawing.Point(-32000, -32000)
$form.Show()
[System.Windows.Forms.Application]::DoEvents()
Update-Status
Invoke-Action $script:MenuButtons[0].Text { Action-HighPerf }
Invoke-Action $script:MenuButtons[2].Text { Action-Balanced }
Update-Status
for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
[ShotPW]::Save($form.Handle, $form.Width, $form.Height, $env:CSHARF_SHOT)
[IO.File]::WriteAllText((Join-Path $env:CSHARF_TEST_OUT "report-$env:CSHARF_TEST_TAG.txt"), "saved $env:CSHARF_SHOT ($($form.Width)x$($form.Height))")
$form.Hide()
$form.Dispose()
exit 0
