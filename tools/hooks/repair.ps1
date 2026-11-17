# Repair hook for test-gui.ps1: runs the real "repair system files" action
# (DISM + SFC - needs admin, takes minutes) and checks what the log tells the
# user against the state the test put Windows in beforehand:
#   CSHARF_REPAIR_EXPECT = clean     nothing is damaged
#                          repaired  a system file is damaged, its stored copy is fine
#                          failed    the stored copy is damaged too, and there is no network
# tools\test-repair.ps1 sets that state and runs this hook - in a disposable
# VM only, never on a PC you care about. Saved with a BOM: it holds Hebrew.

$out    = $env:CSHARF_TEST_OUT
$tag    = $env:CSHARF_TEST_TAG
$expect = $env:CSHARF_REPAIR_EXPECT
$rep    = New-Object System.Collections.Generic.List[string]
$fail   = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

$t0 = Get-Date
Invoke-Action 'repair test' { Action-RepairSystem }
$secs = [int]((Get-Date) - $t0).TotalSeconds
$txt  = $log.Text

switch ($expect) {
    'clean' {
        Check ($txt -match 'DISM הסתיים בהצלחה')       'DISM: success'
        Check ($txt -match 'לא נמצאו קבצים פגומים')    'SFC: reported clean'
        Check ($txt -notmatch 'לא הצליח לתקן')         'SFC: no failure reported'
    }
    'repaired' {
        Check ($txt -match 'DISM הסתיים בהצלחה')       'DISM: success'
        Check ($txt -match 'והוא תוקן|וכולם תוקנו')    'SFC: reported repaired'
        Check ($txt -notmatch 'לא נמצאו קבצים פגומים') 'SFC: not reported clean'
    }
    'failed' {
        Check ($txt -match 'לא הצליח להשיג קבצים תקינים') 'DISM: says it could not get clean files'
        Check ($txt -match 'לא הצליח לתקן')              'SFC: reported unrepaired'
        Check ($txt -match 'חברו את המחשב לאינטרנט')     'tells the user to connect and run again'
        Check ($txt -notmatch 'לא נמצאו קבצים פגומים')   'SFC: not reported clean'
    }
    default { Check $false "unknown CSHARF_REPAIR_EXPECT '$expect'" }
}

$rep.Insert(0, ("repair [{0}] {1} s - {2}" -f $expect, $secs, $(if ($fail) { "$fail FAILED" } else { 'all ok' })))
$rep.Add('--- log ---')
$rep.Add($txt)
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
