# Actions hook for test-gui.ps1: every action the GUI offers, run for real,
# and what the log tells the user checked against what Windows actually did.
#
#   !! CHANGES THE MACHINE: power plans, hibernation, Explorer settings,
#   temp files, the recycle bin, reserved storage, the network stack, a
#   restore point. Run it only in a disposable VM (as administrator, see
#   tools\test-actions.ps1), never on a PC you care about.
#
# The yes/no questions are answered from a script per action, and the
# reboot countdown is always cancelled, so nothing restarts the machine.
# The checks are about honesty: whatever the log claims (✔ done / ⚠ / ✖)
# must match the state of Windows afterwards. Saved with a BOM: it holds Hebrew.

$out  = $env:CSHARF_TEST_OUT
$tag  = $env:CSHARF_TEST_TAG
$rep  = New-Object System.Collections.Generic.List[string]
$fail = 0
function Check { param([bool]$Ok, [string]$What) if ($Ok) { $script:rep.Add("  ok    $What") } else { $script:fail++; $script:rep.Add("  FAIL  $What") } }
function Note  { param([string]$What) $script:rep.Add("  note  $What") }

$cc = [System.Windows.Forms.Control].GetMethod('CreateControl',
        [System.Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([bool]), $null)
[void]$cc.Invoke($form, @($true))
$onClick = [System.Windows.Forms.Control].GetMethod('OnClick', [System.Reflection.BindingFlags]'NonPublic,Instance')

$OK   = [string][char]0x2714
$WARN = [string][char]0x26A0
$ERR  = [string][char]0x2716

# --- scripted answers --------------------------------------------------------
$script:Answers = New-Object System.Collections.Generic.Queue[bool]
$script:Asked   = New-Object System.Collections.Generic.List[string]
function Confirm-Action {
    param([string[]]$Lines, [string]$Title)
    $script:Asked.Add($Title)
    if ($script:Answers.Count) { return $script:Answers.Dequeue() }
    return $false
}
function Show-RebootCountdown { $script:Asked.Add('countdown'); return $false }

# --- a watchdog, so one hung tool cannot hang the whole run ------------------
$script:actStart = $null
$script:actLimit = 0
$wd = New-Object System.Windows.Forms.Timer
$wd.Interval = 1000
$wd.Add_Tick({
    if ($script:actStart -and $script:actLimit -gt 0 -and ((Get-Date) - $script:actStart).TotalSeconds -gt $script:actLimit) {
        $script:actLimit = 0
        $script:rep.Add('  FAIL  watchdog: action ran past its limit, pressed Stop')
        $script:fail++
        [void]$onClick.Invoke($bExit, @([EventArgs]::Empty))
    }
})
$wd.Start()

# The report is written after every action, and the action about to run is
# noted first: if one of them takes the machine down, what came before it
# survives and the culprit is named.
function Save-Report {
    $head = "actions: " + $(if ($script:fail) { "$($script:fail) FAILED" } else { 'all ok so far' })
    # A second copy: test-gui's trap writes its message over report-*.txt.
    foreach ($n in "report-$tag.txt", "progress-$tag.txt") {
        [IO.File]::WriteAllLines((Join-Path $out $n), (@($head) + $script:rep), (New-Object Text.UTF8Encoding($true)))
    }
}
function Run {
    param([string]$Name, [scriptblock]$Act, [bool[]]$Answers = @(), [int]$Limit = 300)
    Save-Report
    [IO.File]::WriteAllText((Join-Path $out 'now-running.txt'), ("{0:HH:mm:ss} {1}" -f (Get-Date), $Name), (New-Object Text.UTF8Encoding($true)))
    $script:Answers.Clear(); foreach ($a in $Answers) { $script:Answers.Enqueue($a) }
    $script:Asked.Clear()
    $start = $log.Text.Length
    $script:actStart = Get-Date; $script:actLimit = $Limit
    Invoke-Action $Name $Act
    $secs = [int]((Get-Date) - $script:actStart).TotalSeconds
    $script:actStart = $null
    $text = $log.Text.Substring([Math]::Min($start, $log.Text.Length))
    $script:rep.Add("== $Name  [$secs s]  asked: " + $(if ($script:Asked.Count) { $script:Asked -join ' | ' } else { '-' }))
    foreach ($l in ($text -split "`n")) { if ($l.Trim() -and $l -notmatch '──') { $script:rep.Add('   | ' + $l.TrimEnd()) } }
    return $text
}
function Has([string]$Text, [string]$Mark) { return $Text.Contains($Mark) }

# Not Get-ActiveScheme: the product has a function of that name, and one
# defined here would replace it for the product's own code too.
function Get-ActivePlanGuid { if ((& powercfg.exe /getactivescheme) -match '([0-9a-fA-F-]{36})') { return $Matches[1].ToLower() } }
function Get-Explorers {
    $me = [Diagnostics.Process]::GetCurrentProcess().SessionId
    @(Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 -and $_.SessionId -ne $me })
}
function Read-Lnk([string]$Path) { $s = (New-Object -ComObject WScript.Shell).CreateShortcut($Path); return @{ Target = $s.TargetPath; Args = $s.Arguments } }
function Get-RecycleCount { try { return (New-Object -ComObject Shell.Application).NameSpace(10).Items().Count } catch { return -1 } }

# ============================================================================
# Power
# ============================================================================
$t = Run 'high performance' { Action-HighPerf }
$a = Get-ActivePlanGuid
Check ((Has $t $OK) -eq ($a -in @($GUID_HIGHPERF, $GUID_CS_HIGH))) "high: log says done <=> active plan is High ($a)"

$t = Run 'ultimate performance' { Action-UltraPerf }
$a = Get-ActivePlanGuid
Check ((Has $t $OK) -eq ($a -eq $GUID_CS_ULT)) "ultimate: log says done <=> active plan is the tool's Ultimate ($a)"
# Read from the registry: powercfg's own labels are translated (this VM is Hebrew).
# Absent = the default, which is 0 (idle allowed).
$ik = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$GUID_CS_ULT\54533251-82be-4824-96c1-47b60b740d00\5d76a2ca-e8c0-402f-a133-2158492d58ad"
$iv = Get-ItemProperty -LiteralPath $ik -ErrorAction SilentlyContinue
Check ((-not $iv) -or ([int]$iv.ACSettingIndex -eq 0 -and [int]$iv.DCSettingIndex -eq 0)) "ultimate: processor idle states left on (AC=$($iv.ACSettingIndex) DC=$($iv.DCSettingIndex))"

$t = Run 'balanced' { Action-Balanced }
Check ((Get-ActivePlanGuid) -eq $GUID_BALANCED) 'balanced: active plan is Balanced'
Check (@(Get-LeftoverSchemes -Active $GUID_BALANCED).Count -eq 0) 'balanced: no plan of the tool left behind'

# ============================================================================
# Hibernation
# ============================================================================
$t = Run 'hibernate off' { Action-HibernateOff }
$en = Get-HibernateEnabled; $file = Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys"
if (Has $t $OK) { Check ((-not $en) -and (-not $file)) "hibernate off: claimed done - enabled=$en, hiberfil.sys=$file" }
else            { Check $en "hibernate off: claimed failure - still enabled=$en" }
$t = Run 'hibernate on' { Action-HibernateOn }
$en = Get-HibernateEnabled
if (Has $t $OK) { Check $en "hibernate on: claimed done - enabled=$en" }
else            { Check (-not $en) "hibernate on: claimed failure - enabled=$en" }

# ============================================================================
# Battery report
# ============================================================================
$rpt = Join-Path ([Environment]::GetFolderPath('Desktop')) 'battery-report.html'
Remove-Item -LiteralPath $rpt -ErrorAction SilentlyContinue
$battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count
$t = Run 'battery report' { Action-BatteryReport }
Check ((Has $t $OK) -eq (Test-Path -LiteralPath $rpt)) "battery: log says saved <=> file on the desktop (batteries here: $battery)"

# ============================================================================
# Shortcuts
# ============================================================================
$desk = [Environment]::GetFolderPath('Desktop')
$t = Run 'all-apps shortcut' { Action-Shortcut }
$l = Join-Path $desk 'תוכנות.lnk'
if (Test-Path -LiteralPath $l) { $s = Read-Lnk $l; Check (($s.Target -match '\\explorer\.exe$') -and ($s.Args -eq 'shell:appsfolder')) "all-apps: $($s.Target) $($s.Args)" }
else { Check $false 'all-apps: shortcut missing' }
$t = Run 'God Mode shortcut' { Action-GodMode }
$l = Join-Path $desk 'כל ההגדרות (God Mode).lnk'
if (Test-Path -LiteralPath $l) { $s = Read-Lnk $l; Check (($s.Target -match '\\explorer\.exe$') -and ($s.Args -eq 'shell:::{ED7BA470-8E54-465E-825C-99712043E01C}')) "God Mode: $($s.Target) $($s.Args)" }
else { Check $false 'God Mode: shortcut missing' }

# ============================================================================
# Explorer settings - classic menu and file extensions, each there and back
# ============================================================================
$menuKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$ex0 = Get-Explorers
Note ("explorer before: " + (($ex0 | ForEach-Object { "pid $($_.Id) $($_.UserName) session $($_.SessionId)" }) -join '; '))
$t = Run 'classic menu on (restart explorer: yes)' { Action-ClassicMenu } -Answers @($true)
# The shell wants the default value present AND empty; "not set" does nothing.
$dv = $null
try { $dv = (Get-Item -LiteralPath "$menuKey\InprocServer32" -ErrorAction Stop).GetValue('') } catch { }
Check ((Has $t $OK) -and ($null -ne $dv) -and ($dv -eq '')) ("classic menu: default value present and empty (" + $(if ($null -eq $dv) { 'not set' } else { "'$dv'" }) + ')')
Start-Sleep 3
$ex1 = Get-Explorers
Note ("explorer after: " + (($ex1 | ForEach-Object { "pid $($_.Id) $($_.UserName) session $($_.SessionId)" }) -join '; '))
Check ($ex1.Count -ge 1 -and (@($ex1.Id) -join ',') -ne (@($ex0.Id) -join ',')) 'classic menu: Explorer restarted in the user session'
$t = Run 'classic menu off (restart explorer: no)' { Action-ClassicMenu } -Answers @($false)
Check ((Has $t $OK) -and -not (Test-Path -LiteralPath $menuKey)) 'classic menu: back to the Windows 11 menu, key removed'

$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$b = Get-ItemProperty -LiteralPath $adv
Note "extensions before: HideFileExt=$($b.HideFileExt) Hidden=$($b.Hidden) ShowSuperHidden=$($b.ShowSuperHidden)"
$t = Run 'show extensions (restart explorer: no)' { Action-FileExtensions } -Answers @($false)
$c = Get-ItemProperty -LiteralPath $adv
Check ((Has $t $OK) -and $c.HideFileExt -eq 0 -and $c.Hidden -eq 1) "extensions: shown (HideFileExt=$($c.HideFileExt) Hidden=$($c.Hidden))"
Check ($c.ShowSuperHidden -eq $b.ShowSuperHidden) 'extensions: protected system files untouched'
$t = Run 'hide extensions again (restart explorer: no)' { Action-FileExtensions } -Answers @($false)
$c = Get-ItemProperty -LiteralPath $adv
Check ((Has $t $OK) -and $c.HideFileExt -eq 1 -and $c.Hidden -eq 2) "extensions: hidden again (HideFileExt=$($c.HideFileExt) Hidden=$($c.Hidden))"

# ============================================================================
# Cleanup - first refused, then accepted with "keep Windows.old"
# ============================================================================
# The long form of the user's temp folder: %TEMP% holds the 8.3 name here
# (C:\Users\0AC8~1\...), and Windows PowerShell 5.1 answers Remove-Item on a
# missing file under an 8.3 path with a terminating "C:\Users\0AC8~1 does not
# exist" that -ErrorAction cannot silence.
$tmpU = Join-Path $env:LOCALAPPDATA 'Temp'; $tmpW = Join-Path $env:SystemRoot 'Temp'
$files = @{}
foreach ($d in $tmpU, $tmpW) {
    foreach ($age in 'old', 'new') {
        $p = Join-Path $d "csharf-test-$age.txt"
        Set-Content -LiteralPath $p -Value ('x' * 4096)
        if ($age -eq 'old') { $it = Get-Item -LiteralPath $p; $it.CreationTime = (Get-Date).AddDays(-10); $it.LastWriteTime = (Get-Date).AddDays(-10) }
        $files["$d|$age"] = $p
    }
}
# A junction in the temp folder pointing at an old canary outside it: the
# cleanup may skip it, never follow it.
$canaryDir = Join-Path $out 'canary'
New-Item -ItemType Directory -Force -Path $canaryDir | Out-Null
Set-Content -LiteralPath (Join-Path $canaryDir 'canary.txt') -Value 'must survive'
$it = Get-Item -LiteralPath (Join-Path $canaryDir 'canary.txt'); $it.CreationTime = (Get-Date).AddDays(-10); $it.LastWriteTime = (Get-Date).AddDays(-10)
cmd /c "mklink /J ""$tmpU\csharf-link"" ""$canaryDir""" | Out-Null
$lockedPath = Join-Path $tmpU 'csharf-test-locked.txt'
Set-Content -LiteralPath $lockedPath -Value 'locked'
$lock = [IO.File]::Open($lockedPath, 'Open', 'Read', 'None')
$binFile = Join-Path $tmpU 'csharf-test-recycled.txt'
Set-Content -LiteralPath $binFile -Value 'to the bin'
Add-Type -AssemblyName Microsoft.VisualBasic
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($binFile, 'OnlyErrorDialogs', 'SendToRecycleBin')
$winOld = Join-Path $env:SystemDrive 'Windows.old'
New-Item -ItemType Directory -Force -Path $winOld | Out-Null
Set-Content -LiteralPath (Join-Path $winOld 'csharf-keep.txt') -Value 'keep me'
Note "recycle bin before: $(Get-RecycleCount) item(s)"

$t = Run 'cleanup (answer: no)' { Action-Cleanup } -Answers @($false)
Check ((Has $t $WARN) -and (@($files.Values | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 4)) 'cleanup refused: nothing deleted'

$t = Run 'cleanup (answers: yes, keep Windows.old)' { Action-Cleanup } -Answers @($true, $false) -Limit 1800
$lock.Dispose()
Check ($script:Asked -contains 'התקנה קודמת של Windows') 'cleanup: asked separately about Windows.old'
Check (Test-Path -LiteralPath (Join-Path $winOld 'csharf-keep.txt')) 'cleanup: Windows.old kept when the answer was no'
Check (Test-Path -LiteralPath $lockedPath) 'cleanup: a file in use was skipped, not forced'
Check (Test-Path -LiteralPath (Join-Path $canaryDir 'canary.txt')) 'cleanup: did not follow a junction out of the temp folder'
foreach ($k in $files.Keys) { $kept = Test-Path -LiteralPath $files[$k]; if ($k -match '\|old$') { Check (-not $kept) "cleanup: temp file older than a day deleted ($k)" } else { Check $kept "cleanup: temp file from the last 24 hours kept ($k)" } }
Check ((Get-RecycleCount) -eq 0) "cleanup: recycle bin empty ($(Get-RecycleCount))"
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$on = @(Get-ChildItem -LiteralPath $vc | Where-Object { (Get-ItemProperty -LiteralPath $_.PSPath).StateFlags0001 -eq 2 } | ForEach-Object { $_.PSChildName })
Note ('cleanmgr categories ticked: ' + ($on -join ', '))
Check (-not ($on -contains 'Previous Installations')) 'cleanup: "Previous Installations" not ticked'
Check (-not ($on -contains 'User file versions')) 'cleanup: File History ("User file versions") not ticked'
foreach ($p in $winOld, $lockedPath) { if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } catch { } } }

# ============================================================================
# Reserved storage - twice: the second time it is already off
# ============================================================================
$rs0 = (Get-WindowsReservedStorageState -ErrorAction SilentlyContinue).ReservedStorageState
$free0 = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
$t = Run 'reserved storage' { Action-ReservedStorage }
$rs1 = (Get-WindowsReservedStorageState -ErrorAction SilentlyContinue).ReservedStorageState
$free1 = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
Note ("reserved storage: {0} -> {1}; free space changed by {2:N2} GB without a restart" -f $rs0, $rs1, (($free1 - $free0) / 1GB))
if (Has $t $OK) { Check ("$rs1" -match 'Disabled') 'reserved storage: claimed off <=> state Disabled' }
Check ($t -notmatch 'הפעלה מחדש') 'reserved storage: no claim about a restart'
$t = Run 'reserved storage again' { Action-ReservedStorage }
Check ($t -match 'כבר מבוטל') 'reserved storage again: says it was already off'

# ============================================================================
# Restore point, PC info, product key, Wi-Fi
# ============================================================================
$rp0 = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
$t = Run 'restore point' { Action-RestorePoint } -Limit 600
$rp1 = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
Check ((Has $t $OK) -eq ($rp1 -gt $rp0)) "restore point: log says created <=> count $rp0 -> $rp1"

$t = Run 'PC info' { Action-PcInfo }
Check ((Has $t $OK) -and $t -match 'מעבד:') 'PC info: lines written'

$oa = (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
$t = Run 'firmware product key' { Action-ProductKey }
Check ((Has $t $OK) -eq [bool]$oa) "product key: log shows a key <=> firmware has one ($([bool]$oa))"

$t = Run 'Wi-Fi passwords' { Action-WifiPasswords }
Note ("Wi-Fi: wlansvc = " + ((Get-Service wlansvc -ErrorAction SilentlyContinue).Status) + ", adapters = " + @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802\.11' }).Count)
Check (-not (Has $t $ERR)) 'Wi-Fi: no error in the log'
Check (@(Get-ChildItem -LiteralPath $tmpU -Filter 'csharf_wlan_*' -Force -ErrorAction SilentlyContinue).Count -eq 0) 'Wi-Fi: the export folder (passwords in plain text) is gone'

# ============================================================================
# Firmware setup and edition change - reboots cancelled / not applicable
# ============================================================================
$t = Run 'firmware setup (yes, then cancel the countdown)' { Action-FirmwareSetup } -Answers @($true)
Note ("firmware type: " + (Get-FirmwareType))
if ((Get-FirmwareType) -eq 'UEFI') { Check (($script:Asked -contains 'countdown') -and (Has $t $WARN)) 'firmware: asked, counted down, cancelled' }

$ed = Get-CsharfEdition
$t = Run 'edition Home -> Pro' { Action-UpgradePro } -Answers @($false)
Note "edition here: $($ed.EditionID)"
if ($ed.EditionID -match '^Professional') { Check ((Has $t $OK) -and $script:Asked.Count -eq 0) 'Pro: already Pro, nothing asked, nothing changed' }

# ============================================================================
# Network reset - last
# ============================================================================
$t = Run 'network reset (yes)' { Action-NetworkReset } -Answers @($true) -Limit 600
Check ($t -match 'נדרשת הפעלה מחדש') 'network reset: says a restart is needed'

$wd.Stop()
$rep.Add('== done')
Save-Report
[IO.File]::WriteAllText((Join-Path $out 'now-running.txt'), ("{0:HH:mm:ss} finished" -f (Get-Date)), (New-Object Text.UTF8Encoding($true)))
