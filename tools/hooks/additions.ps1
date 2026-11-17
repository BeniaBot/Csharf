# Hook for the actions added in 2.2, run through the real functions:
#   - PC details: every line filled in, copied to the clipboard
#   - firmware setup: never reboots here - the question is answered "no",
#     and on a non-UEFI machine the action must stop before even asking
# ASCII only.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))

$script:asked = 0
function Confirm-Action { param([string[]]$Lines, [string]$Title) $script:asked++; return $false }
$script:countdowns = 0
function Show-RebootCountdown { $script:countdowns++; return $false }

# --- PC details ---
$clipBefore = try { [System.Windows.Forms.Clipboard]::GetText() } catch { '' }
$log.Clear()
$t0 = Get-Date
Invoke-Action 'pc info' { Action-PcInfo }
$secs = ((Get-Date) - $t0).TotalSeconds
$lines = @($log.Lines | Where-Object { $_ -match ':\s{2}' })
$rep.Add("        ($([int]$secs)s, $($lines.Count) detail lines)")
foreach ($l in $lines) { $rep.Add("        | $l") }
Check ($lines.Count -ge 6) "PC details: $($lines.Count) lines"
Check (@($lines | Where-Object { $_ -match ':\s{2}\s*$' }).Count -eq 0) 'no detail line is empty after its label'
$clip = try { [System.Windows.Forms.Clipboard]::GetText() } catch { '' }
Check ($clip.Length -gt 40 -and $clip -ne $clipBefore) "copied to the clipboard ($($clip.Length) chars)"
try { if ($clipBefore) { [System.Windows.Forms.Clipboard]::SetText($clipBefore) } else { [System.Windows.Forms.Clipboard]::Clear() } } catch { }

# --- firmware setup ---
$fw = Get-FirmwareType
$rep.Add("        firmware type here: [$fw]")
Invoke-Action 'fw' { Action-FirmwareSetup }
if ($fw -eq 'UEFI') {
    Check ($script:asked -eq 1 -and $script:countdowns -eq 0) 'UEFI: asked first, and "no" stopped it before any countdown'
} else {
    Check ($script:asked -eq 0) 'not UEFI: explained and stopped without asking'
}
# The non-UEFI path, forced.
function Get-FirmwareType { 'Legacy' }
$script:asked = 0
Invoke-Action 'fw legacy' { Action-FirmwareSetup }
Check ($script:asked -eq 0 -and $script:countdowns -eq 0) 'Legacy BIOS: explained, nothing asked, no countdown'

$rep.Add("RESULT: $fail failed")
[IO.File]::WriteAllLines((Join-Path $out "report-$tag.txt"), $rep, (New-Object Text.UTF8Encoding($true)))
$form.Dispose()
exit $fail
