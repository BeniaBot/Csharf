# Layout hook for test-gui.ps1 - dot-sourced in place of ShowDialog.
#
# Draws the real window into a PNG without ever showing it, and checks what a
# user would notice at a glance:
#   - the whole window fits the working area of the screen
#   - every menu button is reachable (inside the visible part of the menu)
#   - no button caption is wider than its button
#   - captions and headings sit against the RIGHT edge (Hebrew reads from there)
# Exit code = number of failed checks. ASCII only.
#
# NB: dot-sourced, so $PSCommandPath here is THIS file - never delete it.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $rep.Add("  ok    $What") } else { $script:fail++; $rep.Add("  FAIL  $What") } }

# Create the handles of a window that is never shown. The public
# CreateControl() does nothing for an invisible form; the internal overload
# with fIgnoreVisible does.
$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))
$form.PerformLayout()
# what the window does once it is shown (2.2 and up)
if (Get-Command Fit-ToScreen -ErrorAction SilentlyContinue) { Fit-ToScreen; $form.PerformLayout() }
try { Update-Status } catch { }
try { Write-Log 'layout test' } catch { }
[System.Windows.Forms.Application]::DoEvents()

$wa = if ($script:WorkArea) { $script:WorkArea } else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
# A simulated screen bigger than the real one cannot be tested here: Windows
# caps a window at the size of the monitor it is actually on.
$real = [System.Windows.Forms.SystemInformation]::VirtualScreen
if ($form.Height -ge $real.Height -and $wa.Height -gt $real.Height) {
    $rep.Add("SKIP: simulated work area $($wa.Width)x$($wa.Height) is taller than this machine's screen $($real.Width)x$($real.Height); the window was capped")
    [IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
    $form.Dispose()
    exit 0
}
$rep.Add("window $($form.Width)x$($form.Height)  client $($form.ClientSize.Width)x$($form.ClientSize.Height)  work area $($wa.Width)x$($wa.Height)  scale $($script:UiScale)")
Check ($form.Width  -le $wa.Width)  "window width  $($form.Width) fits work area $($wa.Width)"
Check ($form.Height -le $wa.Height) "window height $($form.Height) fits work area $($wa.Height)"

function Get-AllControls { param($c) foreach ($k in $c.Controls) { $k; Get-AllControls $k } }
$all     = @(Get-AllControls $form)
$buttons = @($all | Where-Object { $_ -is [System.Windows.Forms.Button] })
$formScreen = $form.RectangleToScreen($form.ClientRectangle)
$hidden = 0; $clipped = 0
foreach ($b in $buttons) {
    $r = $b.RectangleToScreen($b.ClientRectangle)
    # visible = inside the form's client area and inside every parent on the way up
    $vis = $formScreen.Contains($r)
    $par = $b.Parent
    while ($par -and $par -ne $form) {
        if (-not $par.RectangleToScreen($par.ClientRectangle).Contains($r)) { $vis = $false }
        $par = $par.Parent
    }
    if (-not $vis) { $hidden++; $rep.Add("        unreachable: $($b.Text)") }
    $need = [System.Windows.Forms.TextRenderer]::MeasureText($b.Text, $b.Font).Width
    $have = $b.ClientSize.Width - $b.Padding.Horizontal
    if ($need -gt $have) { $clipped++; $rep.Add("        caption needs $need px, button gives $have : $($b.Text)") }
}
Check ($buttons.Count -ge 19) "found $($buttons.Count) buttons (18 actions + exit)"
Check ($hidden -eq 0)  "$hidden buttons unreachable without scrolling"
Check ($clipped -eq 0) "$clipped button captions wider than their button"

$bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
$form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))

# Where the ink actually is inside each menu button, measured on the drawn
# image (not on what the code meant to draw): Hebrew captions must hug the
# right edge, so the empty margin on the right has to be the smaller one.
$origin = $form.PointToScreen([System.Drawing.Point]::Empty)
$winOrg = New-Object System.Drawing.Point($form.Left, $form.Top)
$offX = $origin.X - $form.Left; $offY = $origin.Y - $form.Top
$leftHeavy = 0; $measured = 0
$maxRight = [int](30 * $(if ($script:UiScale) { $script:UiScale } else { 1 }))
foreach ($b in $buttons) {
    if ($b -eq $bExit) { continue }   # centred on purpose
    $r = $b.RectangleToScreen($b.ClientRectangle)
    $x0 = $r.X - $origin.X + $offX; $y0 = $r.Y - $origin.Y + $offY
    if ($x0 -lt 0 -or $y0 -lt 0 -or ($x0 + $r.Width) -gt $bmp.Width -or ($y0 + $r.Height) -gt $bmp.Height) { continue }
    $bg = $b.BackColor
    $minX = $null; $maxX = $null
    for ($x = $x0 + 3; $x -lt $x0 + $r.Width - 3; $x++) {
        for ($y = $y0 + [int]($r.Height * 0.3); $y -lt $y0 + [int]($r.Height * 0.7); $y += 2) {
            $c = $bmp.GetPixel($x, $y)
            if ([Math]::Abs($c.R - $bg.R) + [Math]::Abs($c.G - $bg.G) + [Math]::Abs($c.B - $bg.B) -gt 45) {
                if ($null -eq $minX) { $minX = $x }; $maxX = $x; break
            }
        }
    }
    if ($null -eq $minX) { $rep.Add("        no ink found in: $($b.Text) (enabled: $($b.Enabled))"); continue }
    $measured++
    $leftGap = $minX - $x0; $rightGap = ($x0 + $r.Width) - $maxX
    # Hugs the right edge: the right margin is the smaller one, or - for a
    # caption that fills the whole button - no wider than the padding.
    if ($rightGap -gt $leftGap -and $rightGap -gt $maxRight) { $leftHeavy++; $rep.Add("        not against the right edge (left $leftGap px, right $rightGap px): $($b.Text)") }
}
Check ($measured -ge 18 -and $leftHeavy -eq 0) "captions against the right edge: $($measured - $leftHeavy) of $measured"

$png = Join-Path $out "layout-$tag.png"
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$rep.Add("image: $png")
$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
