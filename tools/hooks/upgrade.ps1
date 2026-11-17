# Upgrade hook for test-gui.ps1: "Home -> Pro" for real, on a Home edition.
#
#   !! CHANGES THE WINDOWS EDITION !!  Only on a disposable Home VM.
#
# Answers yes to the question and cancels the reboot countdown, then records
# what the log said and the state Windows is in. The edition itself changes
# only after a restart, so the caller restarts the machine and reads
# EditionID afterwards. ASCII only.

$out = $env:CSHARF_TEST_OUT
$tag = $env:CSHARF_TEST_TAG
$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

$script:Asked = New-Object System.Collections.Generic.List[string]
function Confirm-Action { param([string[]]$Lines, [string]$Title) $script:Asked.Add($Title); return $true }
# CSHARF_UPGRADE_REBOOT=yes lets the countdown run out (the machine is meant to
# restart); anything else cancels it.
function Show-RebootCountdown { $script:Asked.Add('countdown'); return ($env:CSHARF_UPGRADE_REBOOT -eq 'yes') }

$svc = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$before = @{}; foreach ($s in 'LicenseManager', 'wuauserv') { $before[$s] = (Get-ItemProperty -LiteralPath "$svc\$s").Start }
$ed0 = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
$t0 = Get-Date
Invoke-Action 'upgrade test' { Action-UpgradePro }
$secs = [int]((Get-Date) - $t0).TotalSeconds
$after = @{}; foreach ($s in 'LicenseManager', 'wuauserv') { $after[$s] = (Get-ItemProperty -LiteralPath "$svc\$s").Start }

$rep = New-Object System.Collections.Generic.List[string]
$rep.Add("edition before: $ed0   seconds: $secs   asked: " + ($script:Asked -join ' | '))
foreach ($s in 'LicenseManager', 'wuauserv') { $rep.Add("service $s start type: $($before[$s]) -> $($after[$s])") }
$rep.Add("ok mark in log: " + $log.Text.Contains([string][char]0x2714) + "   error mark: " + $log.Text.Contains([string][char]0x2716))
$rep.Add('--- log ---')
$rep.Add($log.Text)
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
