# Geometry hook for test-gui.ps1: shows the window for real (off-screen, no
# taskbar button) and reports every number the layout used, before and after
# the window exists - for sessions where the frame Windows reports differs
# from the one it draws. ASCII only.
$out = $env:CSHARF_TEST_OUT; $tag = $env:CSHARF_TEST_TAG
$r = New-Object System.Collections.Generic.List[string]
$r.Add("scale=$($script:UiScale)  workArea=$($script:WorkArea)  primary=$([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea)")
$r.Add("computed: frameW=$frameW frameH=$frameH colWidth=$colWidth layout=$($choice.Cols -join '|') menuH=$($choice.MenuH) menuW=$($choice.MenuW)")
$r.Add("planned: clientSize=$($form.ClientSize) size=$($form.Size) menuRow=$menuRow logRow=$logRow")
$form.ShowInTaskbar = $false
$form.Location = New-Object System.Drawing.Point(-32000, -32000)
$form.Show(); [System.Windows.Forms.Application]::DoEvents()
$r.Add("shown, before fit: size=$($form.Size) client=$($form.ClientSize) realFrameH=$($form.Height - $form.ClientSize.Height) realFrameW=$($form.Width - $form.ClientSize.Width)")
$r.Add("rows: title=$($root.GetRowHeights()[0]) status=$($root.GetRowHeights()[1]) menu=$($root.GetRowHeights()[2]) log=$($root.GetRowHeights()[3]) bottom=$($root.GetRowHeights()[4])")
$form.Hide(); $form.Dispose()
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $r, (New-Object Text.UTF8Encoding($true)))
exit 0
