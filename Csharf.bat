@echo off
rem ============================================================================
rem  Csharf  -  Windows Tweaks and Maintenance
rem
rem  Single file. Double-click to run.
rem
rem  This half does one job: extract the PowerShell payload stored below the
rem  marker at the bottom, launch it detached and hidden, and get out of the
rem  way. Elevation lives in the PowerShell half, so there is exactly one UAC
rem  prompt and no console window left sitting behind the GUI.
rem
rem  DO NOT put non-ASCII characters anywhere above that marker. cmd.exe tracks
rem  a byte offset into this file while decoding it through the console code
rem  page, so one multi-byte character up here desyncs the reader: it resumes
rem  mid-line and starts executing the PowerShell payload as batch commands.
rem  The file must also stay UTF-8 WITHOUT BOM, or `@echo off` itself breaks.
rem  No `chcp` here on purpose - this half prints ASCII only, and switching to
rem  65001 makes the same offset bug far more likely.
rem ============================================================================

setlocal

rem ----------------------------------------------- extract embedded script --
rem It is written out as UTF-8 *with* BOM so powershell.exe reads the Hebrew
rem correctly. LastIndexOf so a stray mention of the marker cannot fool it.
set "CSHARF_SELF=%~f0"
set "CSHARF_PS1=%TEMP%\Csharf_%RANDOM%%RANDOM%.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#PS'+'BODY'+'-ST'+'ART'; $s=[IO.File]::ReadAllText($env:CSHARF_SELF,[Text.Encoding]::UTF8); $i=$s.LastIndexOf($m); if($i -lt 0){ exit 1 }; [IO.File]::WriteAllText($env:CSHARF_PS1, $s.Substring($i+$m.Length), (New-Object Text.UTF8Encoding($true)))"
if errorlevel 1 goto :extract_failed
if not exist "%CSHARF_PS1%" goto :extract_failed

rem Launch detached and hidden, then leave immediately - this console must not
rem linger behind the GUI. The script removes itself when the window closes.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%CSHARF_PS1%"
exit /b

:extract_failed
echo.
echo   [!] Failed to extract the embedded script.
echo       Make sure the file was saved as UTF-8 without BOM.
echo.
pause
exit /b 1

#PSBODY-START
# ============================================================================
#  Csharf All-In-One - GUI
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------- elevation ----
# WindowsPrincipal is the canonical admin test: no registry hive and no service
# dependency, unlike `net session` (needs LanmanServer) or reading
# HKU\S-1-5-19 (needs the LocalService profile to be mounted).
# Doing this here rather than in the batch half means one hop and therefore
# exactly one UAC prompt.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($args -contains 'Elevated') {
        # Already came back from a UAC round trip and still not admin - stop,
        # never re-prompt.
        [void][System.Windows.Forms.MessageBox]::Show(
            'הכלי דורש הרשאות מנהל כדי לפעול.', 'Csharf',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        exit 1
    }
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ErrorAction Stop `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA',
                            '-WindowStyle','Hidden','-File', $PSCommandPath, 'Elevated') | Out-Null
    } catch {
        # UAC dismissed - clean up and go quietly.
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    }
    exit
}

# ------------------------------------------------------------- constants ----
$GUID_BALANCED = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GUID_HIGHPERF = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GUID_SAVER    = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$GUID_ULTIMATE = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
# Microsoft's published generic key for a Home -> Pro edition change.
# It changes the edition; it does NOT activate. A real Pro licence /
# digital entitlement is still required afterwards.
$PRO_KEY       = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'

$RX_GUID = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'

# ------------------------------------------------------------- UI palette ----
$C_BG     = [System.Drawing.Color]::FromArgb(12,12,12)
$C_PANEL  = [System.Drawing.Color]::FromArgb(24,26,24)
$C_FG     = [System.Drawing.Color]::FromArgb(0,255,127)
$C_DIM    = [System.Drawing.Color]::FromArgb(130,160,140)
$C_WARN   = [System.Drawing.Color]::FromArgb(255,190,60)
$C_ERR    = [System.Drawing.Color]::FromArgb(255,95,95)
$C_BTN    = [System.Drawing.Color]::FromArgb(32,36,32)

$F_UI     = New-Object System.Drawing.Font('Segoe UI', 10)
$F_BOLD   = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$F_TITLE  = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$F_MONO   = New-Object System.Drawing.Font('Consolas', 9.5)

# ============================================================================
#  Helpers
# ============================================================================

function Get-ActiveScheme {
    # Locale-independent. The old scripts used `for /f "tokens=4"`, which
    # silently breaks on a non-English Windows.
    $out = ''
    try { $out = (& powercfg /getactivescheme 2>$null) -join ' ' } catch { }
    $guid = ''
    $name = ''
    if ($out -match $RX_GUID) { $guid = $Matches[1] }
    if ($out -match '\(([^)]*)\)\s*$') { $name = $Matches[1].Trim() }
    [PSCustomObject]@{ Guid = $guid; Name = $name }
}

function Get-SchemeLabel {
    $s = Get-ActiveScheme
    switch -Regex ($s.Guid) {
        "^$GUID_ULTIMATE$" { return 'ביצועים אולטימטיביים' }
        "^$GUID_HIGHPERF$" { return 'ביצועים גבוהים' }
        "^$GUID_BALANCED$" { return 'מאוזן' }
        "^$GUID_SAVER$"    { return 'חיסכון בסוללה' }
    }
    # A cloned Ultimate scheme keeps its own GUID - fall back to the name.
    if ($s.Name -match 'Ultimate|אולטימ') { return 'ביצועים אולטימטיביים (מותאם)' }
    if ($s.Name) { return $s.Name }
    return 'לא ידוע'
}

function Get-HibernateEnabled {
    # Registry instead of parsing `powercfg /a` output, which is localised.
    # Get-ItemProperty (not Get-ItemPropertyValue) so this also runs on PS 3/4.
    try {
        $k = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
                              -ErrorAction Stop
        return [bool]$k.HibernateEnabled
    } catch { return $false }
}

function Get-CsharfEdition {
    try {
        $k = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        # DisplayVersion exists from 20H2 on; older builds only have ReleaseId.
        $ver = [string]$k.DisplayVersion
        if (-not $ver) { $ver = [string]$k.ReleaseId }
        # Windows 11 still reports ProductName as "Windows 10 ..." - Microsoft
        # never updated the value. Build 22000+ is the only reliable signal.
        $name  = [string]$k.ProductName
        $build = 0
        [void][int]::TryParse([string]$k.CurrentBuildNumber, [ref]$build)
        if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
        return [PSCustomObject]@{
            EditionID   = [string]$k.EditionID
            ProductName = $name
            Display     = $ver
            Build       = $build
        }
    } catch {
        return [PSCustomObject]@{ EditionID = '?'; ProductName = '?'; Display = '' }
    }
}

function Get-FreeSpaceBytes {
    param([string]$Drive = 'C')
    try { return (Get-PSDrive -Name $Drive -ErrorAction Stop).Free } catch { return 0 }
}

function Resolve-SystemExe {
    # A 32-bit PowerShell on 64-bit Windows has System32 redirected to
    # SysWOW64, where 64-bit-only tools such as changepk.exe do not exist.
    # Sysnative bypasses the redirector.
    param([string]$Name)
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
        $sysnative = Join-Path $env:SystemRoot "Sysnative\$Name"
        if (Test-Path -LiteralPath $sysnative) { return $sysnative }
    }
    $sys32 = Join-Path $env:SystemRoot "System32\$Name"
    if (Test-Path -LiteralPath $sys32) { return $sys32 }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $null
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Clear-FolderContents {
    # Deletes the *contents* only. The old scripts did `rd /s /q %TEMP%` and
    # `rd /s /q C:\Windows\Temp` then re-created the folders - that wipes the
    # NTFS ACLs on C:\Windows\Temp and can break Windows services.
    param([string]$Path)
    $freed = 0
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $size = 0
            if ($_.PSIsContainer) {
                $m = Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum
                if ($m) { $size = [double]$m.Sum }
            } else {
                $size = [double]$_.Length
            }
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
            $freed += $size
        } catch {
            # In use / locked - skip silently, that is normal.
        }
    }
    return $freed
}

function Start-Tool {
    # Runs an external tool without freezing the window. Start-Process -Wait
    # blocks the UI thread, which matters a lot for DISM and SFC - those can
    # run for half an hour and the form would look hung the whole time.
    # Returns the exit code, or $null if the process could not be started.
    param([string]$FilePath, [string[]]$ArgumentList)
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
                           -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch {
        return $null
    }
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
    }
    return $p.ExitCode
}

# ============================================================================
#  Form
# ============================================================================

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'Csharf  -  כלי מערכת'
# Two columns of grouped buttons. Tallest column is 3 headings + 9 buttons
# = 3*36 + 9*40 = 468, plus title 46 + status 96 + exit 46 + log 170.
$form.Size            = New-Object System.Drawing.Size(780, 880)
$form.MinimumSize     = New-Object System.Drawing.Size(740, 620)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = $C_BG
$form.ForeColor       = $C_FG
$form.Font            = $F_UI
$form.RightToLeft     = 'Yes'
$form.RightToLeftLayout = $true

$lblTitle             = New-Object System.Windows.Forms.Label
$lblTitle.Text        = '⚡  תפריט כלי מערכת  ⚡'
$lblTitle.Font        = $F_TITLE
$lblTitle.ForeColor   = $C_FG
$lblTitle.Dock        = 'Top'
$lblTitle.Height      = 46
$lblTitle.TextAlign   = 'MiddleCenter'
$form.Controls.Add($lblTitle)

# ---------------------------------------------------------- status strip ----
$pnlStatus            = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock       = 'Top'
$pnlStatus.Height     = 96
$pnlStatus.BackColor  = $C_PANEL
$pnlStatus.Padding    = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

$lblStatus            = New-Object System.Windows.Forms.Label
$lblStatus.Dock       = 'Fill'
$lblStatus.ForeColor  = $C_DIM
$lblStatus.TextAlign  = 'MiddleRight'
$pnlStatus.Controls.Add($lblStatus)
$form.Controls.Add($pnlStatus)

# ------------------------------------------------------------------- log ----
$pnlLog               = New-Object System.Windows.Forms.Panel
$pnlLog.Dock          = 'Bottom'
$pnlLog.Height        = 170
$pnlLog.Padding       = New-Object System.Windows.Forms.Padding(12, 6, 12, 12)

$log                  = New-Object System.Windows.Forms.RichTextBox
$log.Dock             = 'Fill'
$log.ReadOnly         = $true
$log.BackColor        = [System.Drawing.Color]::FromArgb(8,8,8)
$log.ForeColor        = $C_DIM
$log.Font             = $F_MONO
$log.BorderStyle      = 'FixedSingle'
$log.RightToLeft      = 'Yes'
$log.DetectUrls       = $false
$pnlLog.Controls.Add($log)
$form.Controls.Add($pnlLog)

# --------------------------------------------------------------- buttons ----
# Exit button gets its own strip so it never scrolls away with the menu.
$pnlExit              = New-Object System.Windows.Forms.Panel
$pnlExit.Dock         = 'Bottom'
$pnlExit.Height       = 46
$pnlExit.Padding      = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
$form.Controls.Add($pnlExit)

# Two side-by-side columns. Column 0 sits on the right under RightToLeftLayout.
$pnlBtns              = New-Object System.Windows.Forms.TableLayoutPanel
$pnlBtns.Dock         = 'Fill'
$pnlBtns.ColumnCount  = 2
$pnlBtns.RowCount     = 1
$pnlBtns.AutoScroll   = $true
$pnlBtns.Padding      = New-Object System.Windows.Forms.Padding(12, 6, 12, 0)
[void]$pnlBtns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$pnlBtns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$form.Controls.Add($pnlBtns)
$pnlBtns.BringToFront()

$pnlColR              = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlColR.Dock         = 'Fill'
$pnlColR.FlowDirection = 'TopDown'
$pnlColR.WrapContents = $false
$pnlColR.AutoScroll   = $false
$pnlColR.Margin       = New-Object System.Windows.Forms.Padding(0)

$pnlColL              = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlColL.Dock         = 'Fill'
$pnlColL.FlowDirection = 'TopDown'
$pnlColL.WrapContents = $false
$pnlColL.AutoScroll   = $false
$pnlColL.Margin       = New-Object System.Windows.Forms.Padding(0)

$pnlBtns.Controls.Add($pnlColR, 0, 0)
$pnlBtns.Controls.Add($pnlColL, 1, 0)

# ============================================================================
#  Logging / busy state
# ============================================================================

function Write-Log {
    param([string]$Text, [System.Drawing.Color]$Color = $C_DIM)
    $log.SelectionStart  = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor  = $Color
    $log.AppendText(('[{0}]  {1}{2}' -f (Get-Date -Format 'HH:mm:ss'), $Text, [Environment]::NewLine))
    $log.SelectionColor  = $log.ForeColor
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
function Write-Ok   { param([string]$t) Write-Log "✔  $t" $C_FG }
function Write-Warn { param([string]$t) Write-Log "⚠  $t" $C_WARN }
function Write-Err  { param([string]$t) Write-Log "✖  $t" $C_ERR }

function Update-Status {
    $ed   = Get-CsharfEdition
    $hib  = if (Get-HibernateEnabled) { 'פעיל' } else { 'מושבת' }
    $free = Format-Size (Get-FreeSpaceBytes 'C')
    $lblStatus.Text = @(
        "מצב ביצועים נוכחי:  $(Get-SchemeLabel)"
        # No square brackets here: they are bidi-neutral, so around Latin text
        # inside an RTL line they get mirrored and land in the wrong place.
        "מהדורת Windows:  $($ed.ProductName) $($ed.Display)  ·  $($ed.EditionID)"
        "מצב תרדמה:  $hib          מקום פנוי בכונן C:  $free"
    ) -join [Environment]::NewLine
    [System.Windows.Forms.Application]::DoEvents()
}

$script:Busy = $false
function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    foreach ($col in @($pnlColR, $pnlColL)) {
        foreach ($c in $col.Controls) {
            if ($c -is [System.Windows.Forms.Button]) { $c.Enabled = -not $On }
        }
    }
    $form.Cursor = if ($On) { 'WaitCursor' } else { 'Default' }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-Action {
    param([string]$Title, [scriptblock]$Body)
    if ($script:Busy) { return }
    Set-Busy $true
    Write-Log ('── {0} ──' -f $Title) $C_FG
    # finally, not a plain trailing call: if anything in here throws, the
    # buttons must still come back. Otherwise one bad status refresh leaves
    # the whole window dead and the user has to restart it.
    try {
        try { & $Body }       catch { Write-Err "שגיאה: $($_.Exception.Message)" }
        try { Update-Status } catch { Write-Warn 'לא הצלחתי לרענן את שורת הסטטוס.' }
    } finally {
        Set-Busy $false
    }
}

# ============================================================================
#  Actions
# ============================================================================

function Action-HighPerf {
    & powercfg -duplicatescheme $GUID_HIGHPERF 2>&1 | Out-Null
    & powercfg /setactive $GUID_HIGHPERF 2>&1 | Out-Null
    if ((Get-ActiveScheme).Guid -eq $GUID_HIGHPERF) {
        Write-Ok 'מצב ביצועים גבוהים הופעל בהצלחה.'
    } else {
        Write-Err 'לא הצלחתי להפעיל את מצב הביצועים הגבוהים.'
    }
}

function Action-UltraPerf {
    Write-Log 'מנסה להפעיל את סכימת Ultimate Performance הרשמית...'
    & powercfg -duplicatescheme $GUID_ULTIMATE 2>&1 | Out-Null
    & powercfg /setactive $GUID_ULTIMATE 2>&1 | Out-Null

    if ((Get-ActiveScheme).Guid -eq $GUID_ULTIMATE) {
        Write-Ok 'מצב ביצועים אולטימטיביים הופעל (סכימה רשמית).'
        return
    }

    # Fallback: Home / battery-powered devices hide the Ultimate scheme.
    # Clone High Performance and push it to Ultimate-equivalent settings.
    Write-Warn 'הסכימה הרשמית לא זמינה במהדורה הזו - יוצר סכימה מותאמת.'
    $out = (& powercfg -duplicatescheme $GUID_HIGHPERF 2>$null) -join ' '
    if ($out -match $RX_GUID) {
        $new = $Matches[1]
    } else {
        Write-Err 'שכפול סכימת הביצועים הגבוהים נכשל.'
        return
    }

    & powercfg -changename $new 'Ultimate Performance (Csharf)' 'ביצועים אולטימטיביים - מותאם' 2>&1 | Out-Null
    foreach ($p in @(
        @('SUB_PROCESSOR','PROCTHROTTLEMIN',100),
        @('SUB_PROCESSOR','PROCTHROTTLEMAX',100),
        @('SUB_PROCESSOR','IDLEDISABLE',1),
        @('SUB_DISK','DISKIDLE',0),
        @('SUB_SLEEP','STANDBYIDLE',0),
        @('SUB_VIDEO','VIDEOIDLE',0)
    )) {
        & powercfg -setacvalueindex $new $p[0] $p[1] $p[2] 2>&1 | Out-Null
        & powercfg -setdcvalueindex $new $p[0] $p[1] $p[2] 2>&1 | Out-Null
    }
    & powercfg /setactive $new 2>&1 | Out-Null

    if ((Get-ActiveScheme).Guid -eq $new) {
        Write-Ok 'מצב ביצועים אולטימטיביים הופעל (סכימה מותאמת).'
    } else {
        Write-Err 'הפעלת הסכימה המותאמת נכשלה.'
    }
}

function Action-Balanced {
    & powercfg /setactive $GUID_BALANCED 2>&1 | Out-Null
    if ((Get-ActiveScheme).Guid -ne $GUID_BALANCED) {
        Write-Err 'המעבר למצב מאוזן נכשל.'
        return
    }
    Write-Ok 'המערכת חזרה למצב מאוזן.'

    # Clean up leftover Ultimate clones. Only removes duplicates - never the
    # active scheme, and never one of the four built-in GUIDs.
    $builtin = @($GUID_BALANCED, $GUID_HIGHPERF, $GUID_SAVER, $GUID_ULTIMATE)
    $active  = (Get-ActiveScheme).Guid
    $removed = 0
    foreach ($line in (& powercfg /list 2>$null)) {
        if ($line -match $RX_GUID) { $g = $Matches[1] } else { continue }
        if ($g -eq $active -or $builtin -contains $g) { continue }
        if ($line -match 'Ultimate|אולטימ|Csharf') {
            & powercfg /delete $g 2>&1 | Out-Null
            $removed++
        }
    }
    if ($removed -gt 0) { Write-Ok "נמחקו $removed סכימות אולטרא שנוצרו בעבר." }
}

function Action-HibernateOff {
    & powercfg -h off 2>&1 | Out-Null
    Start-Sleep -Milliseconds 400
    if (Get-HibernateEnabled) {
        Write-Err 'השבתת מצב התרדמה נכשלה.'
    } else {
        Write-Ok 'מצב תרדמה הושבת והקובץ hiberfil.sys נמחק.'
    }
}

function Action-HibernateOn {
    & powercfg -h on 2>&1 | Out-Null
    Start-Sleep -Milliseconds 400
    if (Get-HibernateEnabled) {
        Write-Ok 'מצב תרדמה הופעל מחדש.'
    } else {
        Write-Err 'הפעלת מצב התרדמה נכשלה (ייתכן שהחומרה אינה תומכת).'
    }
}

function Action-Shortcut {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = Join-Path $ws.SpecialFolders('Desktop') 'תוכנות.lnk'
    $sc  = $ws.CreateShortcut($lnk)
    $sc.TargetPath   = 'C:\Windows\explorer.exe'
    $sc.Arguments    = 'shell:appsfolder'
    $sc.IconLocation = 'C:\Windows\system32\imageres.dll,3'
    $sc.Description  = 'רשימת כל התוכנות המותקנות'
    $sc.Save()
    if (Test-Path -LiteralPath $lnk) {
        Write-Ok "הקיצור נוצר בהצלחה: $lnk"
    } else {
        Write-Err 'יצירת הקיצור נכשלה.'
    }
}

function Action-RestorePoint {
    # System Restore cmdlets ship on client SKUs only - absent on Windows Server.
    if (-not (Get-Command 'Checkpoint-Computer' -ErrorAction SilentlyContinue)) {
        Write-Warn 'שחזור מערכת אינו נתמך במהדורה הזו (Windows Server).'
        return
    }
    Write-Log 'יוצר נקודת שחזור... (עשוי לקחת דקה)'
    try {
        Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Csharf All-In-One' `
                            -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Ok 'נקודת שחזור נוצרה.'
    } catch {
        Write-Warn 'לא נוצרה נקודת שחזור (שחזור מערכת כבוי, או שכבר נוצרה נקודה ב-24 השעות האחרונות).'
    }
}

function Action-Cleanup {
    $msg = @(
        'הפעולה תמחק קבצים זמניים, תרוקן את סל המיחזור,'
        'ותנקה קבצי עדכונים ישנים של Windows.'
        ''
        'הקבצים שיימחקו לא ניתנים לשחזור. להמשיך?'
    ) -join [Environment]::NewLine
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $msg, 'אזהרה - פינוי שטח',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2,
        [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor
        [System.Windows.Forms.MessageBoxOptions]::RightAlign)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Warn 'הפעולה בוטלה.'
        return
    }

    $before = Get-FreeSpaceBytes 'C'

    Write-Log 'מסמן קטגוריות לניקוי עבור cleanmgr...'
    $caches = @(
        'Active Setup Temp Folders','BranchCache','Downloaded Program Files',
        'Internet Cache Files','Memory Dump Files','Old ChkDsk Files',
        'Previous Installations','Recycle Bin','Service Pack Cleanup',
        'Setup Log Files','System error memory dump files',
        'System error minidump files','Temporary Files','Update Cleanup',
        'User file versions','Windows Error Reporting Files'
    )
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    foreach ($c in $caches) {
        $p = Join-Path $root $c
        if (Test-Path -LiteralPath $p) {
            New-ItemProperty -LiteralPath $p -Name 'StateFlags0001' `
                             -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Write-Log 'מריץ ניקוי דיסק (cleanmgr)... אנא המתן.'
    if ($null -ne (Start-Tool 'cleanmgr.exe' @('/sagerun:1'))) {
        Write-Ok 'ניקוי הדיסק הסתיים.'
    } else {
        Write-Warn 'cleanmgr לא זמין או נכשל - ממשיך.'
    }

    Write-Log 'מנקה תיקיות זמניות...'
    $freed = 0
    $freed += Clear-FolderContents $env:TEMP
    $freed += Clear-FolderContents 'C:\Windows\Temp'
    $freed += Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Temp')
    Write-Ok ("תיקיות זמניות נוקו ({0}). קבצים בשימוש דולגו." -f (Format-Size $freed))

    # Clear-RecycleBin needs PS 5.0; fall back to the raw folder on older hosts.
    if (Get-Command 'Clear-RecycleBin' -ErrorAction SilentlyContinue) {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Ok 'סל המיחזור רוקן.'
        } catch {
            Write-Log 'סל המיחזור כבר היה ריק.'
        }
    } else {
        Get-ChildItem -LiteralPath "$env:SystemDrive\`$Recycle.Bin" -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Ok 'סל המיחזור רוקן.'
    }

    Write-Log 'מנקה רכיבי Windows ישנים (DISM)... זה עשוי לקחת מספר דקות.'
    $dc = Start-Tool 'dism.exe' @('/online','/cleanup-image','/startcomponentcleanup')
    if ($dc -eq 0)          { Write-Ok 'ניקוי רכיבי Windows הושלם.' }
    elseif ($null -eq $dc)  { Write-Warn 'DISM נכשל - ממשיך.' }
    else                    { Write-Warn "DISM הסתיים עם קוד $dc." }

    $after = Get-FreeSpaceBytes 'C'
    $delta = $after - $before
    if ($delta -gt 0) {
        Write-Ok ('סה"כ שוחרר: {0}   (פנוי כעת: {1})' -f (Format-Size $delta), (Format-Size $after))
    } else {
        Write-Ok ('הניקוי הסתיים. פנוי כעת: {0}' -f (Format-Size $after))
    }
    Write-Log 'הערה: /ResetBase לא הורץ, כך שעדיין אפשר להסיר עדכוני Windows.' $C_DIM
}

function Show-RebootCountdown {
    # The X-to-cancel countdown from v1 (Csharf.bat) - it was dropped in the
    # later versions. Rebuilt here as a proper dialog.
    $dlg               = New-Object System.Windows.Forms.Form
    $dlg.Text          = 'הפעלה מחדש'
    $dlg.Size          = New-Object System.Drawing.Size(430, 190)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox   = $false
    $dlg.MinimizeBox   = $false
    $dlg.BackColor     = $C_BG
    $dlg.ForeColor     = $C_FG
    $dlg.Font          = $F_UI
    $dlg.RightToLeft   = 'Yes'
    $dlg.RightToLeftLayout = $true

    $lbl               = New-Object System.Windows.Forms.Label
    $lbl.Dock          = 'Fill'
    $lbl.TextAlign     = 'MiddleCenter'
    $lbl.Font          = $F_BOLD
    $dlg.Controls.Add($lbl)

    $btn               = New-Object System.Windows.Forms.Button
    $btn.Text          = 'ביטול ההפעלה מחדש'
    $btn.Dock          = 'Bottom'
    $btn.Height        = 42
    $btn.FlatStyle     = 'Flat'
    $btn.BackColor     = $C_BTN
    $btn.ForeColor     = $C_WARN
    $dlg.Controls.Add($btn)

    # Event handlers run off the message loop, where this function's local
    # scope is no longer on the lookup chain - so everything a handler touches
    # is kept at script scope.
    $script:cdLeft      = 15
    $script:cdCancelled = $false
    $script:cdDlg       = $dlg
    $script:cdLbl       = $lbl
    $lbl.Text = "המחשב יופעל מחדש בעוד $($script:cdLeft) שניות..."

    $script:cdTimer          = New-Object System.Windows.Forms.Timer
    $script:cdTimer.Interval = 1000
    $script:cdTimer.Add_Tick({
        $script:cdLeft--
        if ($script:cdLeft -le 0) {
            $script:cdTimer.Stop()
            $script:cdDlg.Close()
        } else {
            $script:cdLbl.Text = "המחשב יופעל מחדש בעוד $($script:cdLeft) שניות..."
        }
    })
    $btn.Add_Click({
        $script:cdCancelled = $true
        $script:cdTimer.Stop()
        $script:cdDlg.Close()
    })
    $dlg.Add_Shown({ $script:cdTimer.Start() })
    $dlg.ShowDialog($form) | Out-Null
    $script:cdTimer.Dispose()
    $dlg.Dispose()
    return (-not $script:cdCancelled)
}

function Action-UpgradePro {
    $ed = Get-CsharfEdition
    if ($ed.EditionID -match '^Professional') {
        Write-Ok "מערכת ההפעלה כבר במהדורת Pro ($($ed.EditionID))."
        return
    }
    # v1 simply ran changepk.exe and let it report its own failure. Keep that
    # behaviour - resolve a real path when we can, but never refuse to try.
    $changepk = Resolve-SystemExe 'changepk.exe'
    if (-not $changepk) {
        Write-Warn 'changepk.exe לא אותר בנתיב הרגיל - מנסה בכל זאת.'
        $changepk = 'changepk.exe'
    }

    $msg = @(
        "המהדורה הנוכחית: $($ed.ProductName)  [$($ed.EditionID)]"
        ''
        'הפעולה תשנה את מהדורת Windows ל-Pro ותפעיל את המחשב מחדש.'
        'שמור וסגור את כל המסמכים הפתוחים לפני שתמשיך.'
        ''
        'שים לב: שינוי המהדורה אינו הפעלה (Activation).'
        'לאחר ההפעלה מחדש עדיין יידרש רישיון Pro תקף.'
        ''
        'להמשיך?'
    ) -join [Environment]::NewLine
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $msg, 'שדרוג מהדורה ל-Pro',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2,
        [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor
        [System.Windows.Forms.MessageBoxOptions]::RightAlign)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Warn 'הפעולה בוטלה.'
        return
    }

    Write-Log 'מכין את התשתית לשדרוג (הפעלת שירותים נדרשים)...'
    foreach ($svc in @('LicenseManager','wuauserv')) {
        & sc.exe config $svc start= auto 2>&1 | Out-Null
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }

    Write-Log 'מריץ changepk.exe...'
    # NOTE: kept on Start-Process -Wait rather than Start-Tool. changepk drives
    # its own UI and a reboot; the window must not accept clicks meanwhile.
    # v2/v4 had `timeout /t 5` between changepk and the errorlevel check, which
    # reset ERRORLEVEL - so they always reported success. Fixed by reading the
    # process exit code directly.
    $proc = Start-Process -FilePath $changepk `
                          -ArgumentList '/productkey', $PRO_KEY `
                          -Wait -PassThru -ErrorAction SilentlyContinue
    if (-not $proc -or $proc.ExitCode -ne 0) {
        $code = if ($proc) { $proc.ExitCode } else { 'n/a' }
        Write-Err "שינוי המהדורה נכשל (קוד $code). ודא חיבור לאינטרנט ונסה שוב."
        return
    }

    Write-Ok 'תהליך שינוי המהדורה החל. נדרשת הפעלה מחדש להשלמתו.'
    if (Show-RebootCountdown) {
        Write-Log 'מפעיל מחדש...'
        & shutdown /r /t 5 /c 'שדרוג מהדורה ל-Pro - המחשב מופעל מחדש.' 2>&1 | Out-Null
    } else {
        Write-Warn 'ההפעלה מחדש בוטלה. השדרוג יושלם בהפעלה מחדש הבאה.'
    }
}

# ---------------------------------------------------------------------------
#  Explorer-facing helpers shared by several of the actions below
# ---------------------------------------------------------------------------

function New-DesktopShortcut {
    param([string]$Name, [string]$Target, [string]$Arguments, [string]$Icon, [string]$Description)
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = Join-Path $ws.SpecialFolders('Desktop') "$Name.lnk"
    $sc  = $ws.CreateShortcut($lnk)
    $sc.TargetPath   = $Target
    $sc.Arguments    = $Arguments
    $sc.IconLocation = $Icon
    $sc.Description  = $Description
    $sc.Save()
    return $lnk
}

function Restart-Explorer {
    Write-Log 'מפעיל מחדש את סייר הקבצים כדי להחיל את השינוי...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

function Get-BuildNumber {
    try {
        return [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                     -ErrorAction Stop).CurrentBuildNumber
    } catch { return 0 }
}

# ============================================================================
#  Actions - hidden Windows features
# ============================================================================

function Action-GodMode {
    # One folder listing every Control Panel task Windows has, including the
    # ones with no entry in Settings. Same mechanism as the all-apps shortcut.
    $lnk = New-DesktopShortcut -Name 'כל ההגדרות (God Mode)' `
        -Target 'C:\Windows\explorer.exe' `
        -Arguments 'shell:::{ED7BA470-8E54-465E-825C-99712043E01C}' `
        -Icon 'C:\Windows\system32\imageres.dll,109' `
        -Description 'כל משימות ההגדרה של Windows במקום אחד'
    if (Test-Path -LiteralPath $lnk) {
        Write-Ok "הקיצור נוצר: $lnk"
    } else {
        Write-Err 'יצירת הקיצור נכשלה.'
    }
}

function Action-ClassicMenu {
    # Windows 11 collapsed the right-click menu behind "Show more options".
    # An empty InprocServer32 under this CLSID restores the full Win10 menu.
    if ((Get-BuildNumber) -lt 22000) {
        Write-Warn 'רלוונטי ל-Windows 11 בלבד. במערכת הזו התפריט המלא ממילא פעיל.'
        return
    }
    $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'הוחזר תפריט ההקשר המקוצר של Windows 11.'
    } else {
        # reg.exe /ve writes a genuinely empty default value, which is what the
        # shell checks for. New-Item alone leaves it unset and has no effect.
        & reg.exe add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve 2>&1 | Out-Null
        if (Test-Path -LiteralPath "$key\InprocServer32") {
            Write-Ok 'תפריט ההקשר הישן והמלא הופעל.'
        } else {
            Write-Err 'העדכון ברישום נכשל.'
            return
        }
    }
    Restart-Explorer
    Write-Log 'הערה: ההגדרה חלה על המשתמש שאיתו אושרה ההרצה כמנהל.' $C_DIM
}

function Action-FileExtensions {
    # Buried three dialogs deep in Folder Options, and almost everyone wants
    # it on. Protected OS files stay hidden - only ShowSuperHidden does that,
    # and turning it on is a good way to let someone delete a boot file.
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    try {
        $cur = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        $showing = ($cur.HideFileExt -eq 0 -and $cur.Hidden -eq 1)
        if ($showing) {
            Set-ItemProperty -LiteralPath $key -Name 'HideFileExt' -Value 1
            Set-ItemProperty -LiteralPath $key -Name 'Hidden'      -Value 2
            Write-Ok 'סיומות וקבצים מוסתרים הוחזרו למצב מוסתר.'
        } else {
            Set-ItemProperty -LiteralPath $key -Name 'HideFileExt' -Value 0
            Set-ItemProperty -LiteralPath $key -Name 'Hidden'      -Value 1
            Write-Ok 'סיומות קבצים וקבצים מוסתרים מוצגים כעת.'
        }
        Restart-Explorer
    } catch {
        Write-Err "עדכון הרישום נכשל: $($_.Exception.Message)"
    }
}

function Action-BatteryReport {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $out     = Join-Path $desktop 'battery-report.html'
    Write-Log 'מפיק דוח בריאות סוללה...'
    $code = Start-Tool 'powercfg.exe' @('/batteryreport','/output',$out)
    if ((Test-Path -LiteralPath $out) -and $code -eq 0) {
        Write-Ok "הדוח נשמר בשולחן העבודה: battery-report.html"
        Write-Log 'חפש בדוח את DESIGN CAPACITY מול FULL CHARGE CAPACITY - היחס ביניהם הוא הבלאי.' $C_DIM
        Start-Process $out -ErrorAction SilentlyContinue
    } else {
        Write-Warn 'לא הופק דוח. במחשב נייח ללא סוללה זה צפוי.'
    }
}

function Action-ProductKey {
    # The OEM key burned into the firmware by the manufacturer. Survives a
    # clean install and is not shown anywhere in the Windows UI.
    $key = $null
    try {
        $key = (Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey
    } catch { }
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-Warn 'לא נמצא מפתח צרוב בקושחה. נפוץ במחשבים מורכבים או בשדרוג מגרסה ישנה.'
        return
    }
    Write-Ok "מפתח המוצר מהקושחה:  $key"
    try {
        [System.Windows.Forms.Clipboard]::SetText($key)
        Write-Log 'המפתח הועתק ללוח.' $C_DIM
    } catch { }
}

function Action-NetworkReset {
    $msg = @(
        'הפעולה תאפס את מחסנית הרשת: מטמון DNS, Winsock ו-TCP/IP.'
        ''
        'שימושי כשהאינטרנט מתנהג מוזר אחרי הסרת VPN או אנטי-וירוס.'
        'לאחר מכן תידרש הפעלה מחדש, וייתכן שיהיה צורך להתחבר שוב לרשת.'
        ''
        'להמשיך?'
    ) -join [Environment]::NewLine
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $msg, 'איפוס ערימת הרשת',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2,
        [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor
        [System.Windows.Forms.MessageBoxOptions]::RightAlign)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Warn 'הפעולה בוטלה.'; return }

    foreach ($step in @(
        @('ipconfig.exe', @('/flushdns'),               'מטמון DNS נוקה'),
        @('ipconfig.exe', @('/registerdns'),            'רשומות DNS נרשמו מחדש'),
        @('netsh.exe',    @('winsock','reset'),         'Winsock אופס'),
        @('netsh.exe',    @('int','ip','reset'),        'מחסנית TCP/IPv4 אופסה'),
        @('netsh.exe',    @('int','ipv6','reset'),      'מחסנית TCP/IPv6 אופסה')
    )) {
        $code = Start-Tool $step[0] $step[1]
        if ($null -ne $code) { Write-Ok $step[2] } else { Write-Warn "נכשל: $($step[2])" }
    }
    Write-Warn 'נדרשת הפעלה מחדש כדי שהאיפוס ייכנס לתוקף.'
}

function Action-WifiPasswords {
    # Exporting to XML instead of scraping `netsh ... key=clear` output: the
    # printed labels are translated per language, the XML tag names are not.
    $tmp = Join-Path $env:TEMP ('csharf_wlan_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Start-Tool 'netsh.exe' @('wlan','export','profile','key=clear',"folder=$tmp") | Out-Null
        $files = Get-ChildItem -LiteralPath $tmp -Filter *.xml -ErrorAction SilentlyContinue
        if (-not $files) {
            Write-Warn 'לא נמצאו פרופילי Wi-Fi שמורים.'
            return
        }
        $found = 0
        foreach ($f in $files) {
            try {
                [xml]$x = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                $name = $x.WLANProfile.name
                $pw   = $x.WLANProfile.MSM.security.sharedKey.keyMaterial
                if ($pw) { Write-Ok "$name  →  $pw"; $found++ }
                else     { Write-Log "$name  →  (רשת פתוחה או ללא סיסמה שמורה)" $C_DIM }
            } catch { }
        }
        Write-Log "נמצאו $found רשתות עם סיסמה שמורה." $C_DIM
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Action-ReservedStorage {
    # Windows parks ~7 GB for update staging. Only togglable through DISM.
    if ((Get-BuildNumber) -lt 18362) {
        Write-Warn 'אחסון שמור קיים מ-Windows 10 גרסה 1903 ומעלה בלבד.'
        return
    }
    Write-Log 'בודק את מצב האחסון השמור...'
    $code = Start-Tool 'dism.exe' @('/Online','/Set-ReservedStorageState','/State:Disabled')
    if ($code -eq 0) {
        Write-Ok 'האחסון השמור בוטל. השטח משתחרר לאחר ההפעלה מחדש הבאה.'
    } else {
        Write-Warn "לא ניתן לבטל כעת (קוד $code). זה קורה כשיש עדכוני Windows בהמתנה - השלם אותם ונסה שוב."
    }
}

function Action-RepairSystem {
    Write-Log 'תיקון קבצי מערכת. הפעולה ארוכה - עד כ-30 דקות. החלון יישאר פעיל.'
    Write-Log 'שלב 1/2: DISM /RestoreHealth ...'
    $d = Start-Tool 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth')
    if ($d -eq 0) { Write-Ok 'מאגר הרכיבים תוקן.' } else { Write-Warn "DISM הסתיים עם קוד $d." }
    Write-Log 'שלב 2/2: sfc /scannow ...'
    $s = Start-Tool 'sfc.exe' @('/scannow')
    switch ($s) {
        0       { Write-Ok 'בדיקת קבצי המערכת הסתיימה. לא נמצאו הפרות שלמות.' }
        default { Write-Warn "sfc הסתיים עם קוד $s. פרטים ב-CBS.log." }
    }
}

# ============================================================================
#  Build the menu
# ============================================================================

# Split by group, not by item count - a count-based split can strand a group
# heading at the foot of one column with its buttons in the other.
# Right-hand column first: that is where the eye lands in an RTL layout.
$menuRight = @(
    @{ Group = 'ביצועים וחשמל' }
    @{ Text = 'מעבר למצב ביצועים גבוהים';                 Act = { Action-HighPerf } }
    @{ Text = 'מעבר למצב ביצועים אולטימטיביים';           Act = { Action-UltraPerf } }
    @{ Text = 'חזרה למצב ביצועים מאוזן';                  Act = { Action-Balanced } }
    @{ Text = 'השבתת מצב תרדמה  (מחיקת hiberfil.sys)';    Act = { Action-HibernateOff } }
    @{ Text = 'הפעלת מצב תרדמה מחדש';                     Act = { Action-HibernateOn } }
    @{ Text = 'דוח בריאות סוללה';                         Act = { Action-BatteryReport } }

    @{ Group = 'ניקוי ושטח' }
    @{ Text = 'פינוי שטח וניקוי מערכת יסודי';             Act = { Action-Cleanup };  Hot = $true }
    @{ Text = 'שחרור האחסון השמור של Windows';            Act = { Action-ReservedStorage } }
    @{ Text = 'תיקון קבצי מערכת  (DISM + SFC)';           Act = { Action-RepairSystem } }
)

$menuLeft = @(
    @{ Group = 'גישה מהירה וממשק' }
    @{ Text = 'קיצור לרשימת כל התוכנות';                  Act = { Action-Shortcut } }
    @{ Text = 'קיצור ל-God Mode  (כל ההגדרות)';           Act = { Action-GodMode } }
    @{ Text = 'תפריט ההקשר הישן  (Windows 11)';           Act = { Action-ClassicMenu } }
    @{ Text = 'הצגת סיומות וקבצים מוסתרים';               Act = { Action-FileExtensions } }

    @{ Group = 'רשת' }
    @{ Text = 'איפוס ערימת הרשת';                         Act = { Action-NetworkReset };  Hot = $true }
    @{ Text = 'הצגת סיסמאות ה-Wi-Fi השמורות';             Act = { Action-WifiPasswords } }

    @{ Group = 'מערכת ורישוי' }
    @{ Text = 'יצירת נקודת שחזור';                        Act = { Action-RestorePoint } }
    @{ Text = 'הצגת מפתח המוצר מהקושחה';                  Act = { Action-ProductKey } }
    @{ Text = 'שדרוג מהדורה מ-Home ל-Pro';                Act = { Action-UpgradePro };  Hot = $true }
)

$colWidth = 344

foreach ($pair in @(@{ Items = $menuRight; Panel = $pnlColR },
                    @{ Items = $menuLeft;  Panel = $pnlColL })) {
    $target = $pair.Panel
    foreach ($item in $pair.Items) {

        if ($item.ContainsKey('Group')) {
            $h            = New-Object System.Windows.Forms.Label
            $h.Text       = $item.Group
            $h.Font       = $F_BOLD
            $h.ForeColor  = $C_DIM
            $h.Width      = $colWidth
            $h.Height     = 26
            $h.TextAlign  = 'BottomRight'
            $h.Margin     = New-Object System.Windows.Forms.Padding(0, 8, 0, 2)
            $target.Controls.Add($h)
            continue
        }

        $b               = New-Object System.Windows.Forms.Button
        $b.Text          = $item.Text
        $b.Width         = $colWidth
        $b.Height        = 36
        $b.Margin        = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
        $b.FlatStyle     = 'Flat'
        $b.BackColor     = $C_BTN
        $b.ForeColor     = if ($item.Hot) { $C_WARN } else { $C_FG }
        $b.TextAlign     = 'MiddleRight'
        $b.Padding       = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,70,60)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(48,56,48)
        $b.Cursor        = 'Hand'

        $title  = $item.Text
        $action = $item.Act
        $b.Add_Click({ Invoke-Action $title $action }.GetNewClosure())

        $target.Controls.Add($b)
    }
}

$bExit               = New-Object System.Windows.Forms.Button
$bExit.Text          = 'יציאה'
$bExit.Dock          = 'Fill'
$bExit.Height        = 34
$bExit.FlatStyle     = 'Flat'
$bExit.BackColor     = [System.Drawing.Color]::FromArgb(20,20,20)
$bExit.ForeColor     = $C_DIM
$bExit.TextAlign     = 'MiddleCenter'
$bExit.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,70,60)
$bExit.Cursor        = 'Hand'
$bExit.Add_Click({ $form.Close() })
$pnlExit.Controls.Add($bExit)

# ============================================================================
#  Go
# ============================================================================

$form.Add_Shown({
    Update-Status
    Write-Log 'Csharf 2.0 - מוכן. הרצה כמנהל מערכת אושרה.' $C_FG
})
[void]$form.ShowDialog()
$form.Dispose()

# The extracted copy in %TEMP% has served its purpose. PowerShell has already
# read the whole script into memory, so deleting it here is safe.
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
