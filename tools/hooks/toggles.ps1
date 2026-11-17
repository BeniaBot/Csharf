# Toggle-button hook for test-gui.ps1: captions follow the PC's state, a
# button with nothing to do stays greyed out through an action, and a toggle
# that needs Explorer restarted asks first (answered "no" here, so Explorer
# is never touched). Flips the file-extension setting and flips it back.
# ASCII only: every Hebrew caption is read from the product's $TOGGLE_TEXT.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

# Every question gets "no" - and is counted.
$script:asked = 0
function Confirm-Action { param([string[]]$Lines, [string]$Title) $script:asked++; return $false }

Update-Status
$kb  = $script:KeyButtons
$hib = Get-HibernateEnabled
Check ($kb.Count -eq 4) "4 toggle buttons registered ($($kb.Count))"
if ($hib) {
    Check ($kb.HibOff.Enabled -and $kb.HibOff.Text -eq $TOGGLE_TEXT.HibOffDo)        'hibernate on: "turn off" offered'
    Check (-not $kb.HibOn.Enabled -and $kb.HibOn.Text -eq $TOGGLE_TEXT.HibOnDone)    'hibernate on: "turn on" greyed, says already on'
} else {
    Check (-not $kb.HibOff.Enabled -and $kb.HibOff.Text -eq $TOGGLE_TEXT.HibOffDone) 'hibernate off: "turn off" greyed, says already off'
    Check ($kb.HibOn.Enabled -and $kb.HibOn.Text -eq $TOGGLE_TEXT.HibOnDo)           'hibernate off: "turn on" offered'
}
$menuWant = if ((Get-BuildNumber) -lt 22000) { $TOGGLE_TEXT.MenuNA } elseif (Test-ClassicMenu) { $TOGGLE_TEXT.MenuToNew } else { $TOGGLE_TEXT.MenuToOld }
Check ($kb.Menu.Text -eq $menuWant) 'context-menu caption matches the current state'

# A greyed button must stay greyed after an action re-enables the menu.
$greyed = @($kb.Values | Where-Object { $_.Tag -eq 'na' })
Invoke-Action 'noop' { }
Check (@($greyed | Where-Object { $_.Enabled }).Count -eq 0) "$($greyed.Count) greyed button(s) still greyed after an action"
Check (@($script:MenuButtons | Where-Object { $_.Tag -ne 'na' -and -not $_.Enabled }).Count -eq 0) 'every other button enabled again'

# Flip file extensions through the real button handler, then flip back.
$explorerBefore = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object Id) | Sort-Object
$onClick = [System.Windows.Forms.Control].GetMethod('OnClick', [System.Reflection.BindingFlags]'NonPublic,Instance')
$shown0  = Test-ExtensionsShown
$cap0    = $kb.Ext.Text
[void]$onClick.Invoke($kb.Ext, @([EventArgs]::Empty))
$shown1  = Test-ExtensionsShown
$cap1    = $kb.Ext.Text
[void]$onClick.Invoke($kb.Ext, @([EventArgs]::Empty))
$shown2  = Test-ExtensionsShown
Check ($shown1 -ne $shown0 -and $shown2 -eq $shown0) "extensions flipped and restored ($shown0 -> $shown1 -> $shown2)"
Check ($cap1 -ne $cap0 -and $kb.Ext.Text -eq $cap0) 'caption followed each flip'
Check ($script:asked -eq 2) "asked before restarting Explorer each time ($script:asked)"
$explorerAfter = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object Id) | Sort-Object
Check ((@($explorerBefore) -join ',') -eq (@($explorerAfter) -join ',')) 'Explorer left running untouched after "no"'
Check ($log.Text -match [regex]::Escape($cap0)) 'log heading uses the caption at the moment of the click'

$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
