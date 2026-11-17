# Restore-point hook for test-gui.ps1 - needs ADMIN (run through
# test-admin.ps1). Creates a real restore point and checks that it really
# appeared, that the log says "created", and that the 24-hour limit setting
# is exactly as before. ASCII only.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

$key   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$freq0 = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
$n0    = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1).SequenceNumber
$log.Clear()
Invoke-Action 'restore point' { Action-RestorePoint }
$n1    = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1).SequenceNumber
$freq1 = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
$said  = ($log.Lines | Where-Object { $_ }) -join ' / '
$rep.Add("        log: $said")
Check ($null -ne $n1 -and $n1 -ne $n0) "a new restore point exists (newest $n0 -> $n1)"
Check ($log.Text.Contains([string][char]0x2714)) 'the log reports success'
Check ("$freq0" -eq "$freq1") "24-hour limit setting restored ([$freq0] -> [$freq1])"

$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
