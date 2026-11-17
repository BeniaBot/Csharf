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
#  Csharf - GUI edition
# ============================================================================

$CSHARF_VERSION = '2.1'

$ErrorActionPreference = 'Continue'

# This process has no console to print to, so anything that goes wrong before
# the window is up would be completely invisible: the user double-clicks and
# nothing ever happens. Say it out loud instead.
trap {
    $fatal = "Csharf נתקל בשגיאה ולא יכול להמשיך:`r`n`r`n$($_.Exception.Message)"
    try {
        [void][System.Windows.Forms.MessageBox]::Show($fatal, 'Csharf',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch {
        try { [void](New-Object -ComObject WScript.Shell).Popup($fatal, 0, 'Csharf', 16) } catch { }
    }
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# ------------------------------------------------------------ sharp text ----
# Without this Windows treats the process as unaware of display scaling,
# draws the window at 100% and stretches the bitmap - blurry at 125% and up,
# which is what almost every laptop runs at. It has to happen before the
# first window exists. Built through Reflection.Emit rather than Add-Type so
# no C# compiler is started (slower, and blocked on some locked-down PCs).
# Failing here is harmless: the window is merely soft again.
try {
    $asmName = New-Object System.Reflection.AssemblyName('CsharfNative')
    $asm     = [AppDomain]::CurrentDomain.DefineDynamicAssembly($asmName, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $tb      = $asm.DefineDynamicModule('CsharfNative').DefineType('CsharfNative.User32', 'Public,Class')
    $mb      = $tb.DefinePInvokeMethod('SetProcessDPIAware', 'user32.dll',
                   [System.Reflection.MethodAttributes]'Public,Static,PinvokeImpl',
                   [System.Reflection.CallingConventions]::Standard, [bool], [Type[]]@(),
                   [System.Runtime.InteropServices.CallingConvention]::Winapi,
                   [System.Runtime.InteropServices.CharSet]::Auto)
    $mb.SetImplementationFlags($mb.GetMethodImplementationFlags() -bor [System.Reflection.MethodImplAttributes]::PreserveSig)
    [void]$tb.CreateType().GetMethod('SetProcessDPIAware').Invoke($null, @())
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ------------------------------------------------------------- elevation ----
# WindowsPrincipal is the canonical admin test: no registry hive and no service
# dependency, unlike `net session` (needs LanmanServer) or reading
# HKU\S-1-5-19 (needs the LocalService profile to be mounted).
# Doing this here rather than in the batch half means one hop and therefore
# exactly one UAC prompt.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$MUTEX_RUNNING = 'Local\Csharf-SingleInstance'   # held by the open window
$MUTEX_LAUNCH  = 'Local\Csharf-Launch'           # held while a UAC prompt is up

function Test-CsharfRunning {
    # Whether the window is already open. The elevated copy owns that mutex,
    # so from here it usually answers "access denied" - which also means it
    # exists.
    try {
        $m = [System.Threading.Mutex]::OpenExisting($MUTEX_RUNNING)
        $m.Dispose()
        return $true
    } catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $false
    } catch {
        return $true
    }
}

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

    # One UAC prompt per start, however many times the file is opened.
    # From the double-click to the prompt takes two or three seconds in which
    # nothing seems to happen, and a second double-click in that time used to
    # raise a second, identical prompt. Now a start that finds another one
    # waiting for its prompt - or the window already open - just leaves.
    $launch = New-Object System.Threading.Mutex($false, $MUTEX_LAUNCH)
    $mine   = $false
    try { $mine = $launch.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $mine = $true }
    if (-not $mine -or (Test-CsharfRunning)) {
        try { [void](New-Object -ComObject WScript.Shell).AppActivate('Csharf') } catch { }
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        exit
    }

    try {
        # The script path carries its own quotes: Start-Process joins
        # -ArgumentList with plain spaces and adds none, so a profile folder
        # with a space in its name ("C:\Users\Dana Levi\...") would split the
        # path in two and the elevated copy would die before it could say so.
        $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -PassThru -ErrorAction Stop `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA',
                            '-WindowStyle','Hidden','-File', ('"{0}"' -f $PSCommandPath), 'Elevated')
        # Keep the launch lock until the elevated copy holds its own, so there
        # is no moment in which a further click would prompt again.
        $until = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $until -and -not (Test-CsharfRunning)) {
            $gone = $false
            try { $gone = $elevated.HasExited } catch { }
            if ($gone) { break }
            Start-Sleep -Milliseconds 100
        }
    } catch {
        # UAC dismissed - clean up and go quietly.
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    }
    try { $launch.ReleaseMutex() } catch { }
    exit
}

# -------------------------------------------------------- single instance ----
# One window at a time. Two copies driving DISM or powercfg against each other
# help nobody, and a second double-click while the first copy is still loading
# is the usual way to end up with two of them stacked exactly on top of each
# other.
$script:Mutex = New-Object System.Threading.Mutex($false, $MUTEX_RUNNING)
$ownsMutex = $false
try { $ownsMutex = $script:Mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }   # previous copy was killed
if (-not $ownsMutex) {
    try { [void](New-Object -ComObject WScript.Shell).AppActivate('Csharf') } catch { }
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    exit
}

# ------------------------------------------------------------- constants ----
$GUID_BALANCED = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GUID_HIGHPERF = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GUID_SAVER    = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$GUID_ULTIMATE = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
# The two plans this tool may create get FIXED ids of their own. `powercfg
# -duplicatescheme` without a destination invents a fresh id on every call,
# and the versions before 2.1 called it on every click - one extra plan per
# press, dozens over time, and on Modern Standby hardware none of them even
# show in `powercfg /list`. A fixed destination can only ever exist once.
$GUID_CS_ULT   = 'c54a2f10-7e1b-4d6a-9b3e-5c0a1e2f0001'
$GUID_CS_HIGH  = 'c54a2f10-7e1b-4d6a-9b3e-5c0a1e2f0002'
$REG_SCHEMES   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
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

# ---------------------------------------------------------------- scaling ----
# Every size below is written in logical pixels - what it would be at 100% -
# and multiplied by the display scale through S. Fonts are given in pixels for
# the same reason, so text and boxes always grow together.
$script:UiScale  = 1.0
try {
    $gfx = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:UiScale = [double]($gfx.DpiX / 96.0)
    $gfx.Dispose()
} catch { }
# The screen the user is looking at - the one the double-click happened on.
$script:WorkArea = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea

function S {
    param([double]$n)
    return [int][Math]::Round($n * $script:UiScale)
}
function New-UiFont {
    param([string]$Family, [double]$Px, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    return New-Object System.Drawing.Font($Family, [single]($Px * $script:UiScale), $Style,
                                          [System.Drawing.GraphicsUnit]::Pixel)
}

$F_UI     = New-UiFont 'Segoe UI' 13.5
$F_BOLD   = New-UiFont 'Segoe UI' 13.5 ([System.Drawing.FontStyle]::Bold)
$F_TITLE  = New-UiFont 'Segoe UI' 20   ([System.Drawing.FontStyle]::Bold)
$F_MONO   = New-UiFont 'Consolas' 12.5

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
    # Greedy on purpose: a plan called "Ultimate Performance (Csharf)" is
    # printed as "(Ultimate Performance (Csharf))", and a pattern that stops at
    # the first ")" finds no name at all.
    if ($out -match '\((.*)\)\s*$') { $name = $Matches[1].Trim() }
    [PSCustomObject]@{ Guid = $guid; Name = $name }
}

function Get-SchemeLabel {
    $s = Get-ActiveScheme
    switch -Regex ($s.Guid) {
        "^($GUID_ULTIMATE|$GUID_CS_ULT)$"  { return 'ביצועים אולטימטיביים' }
        "^($GUID_HIGHPERF|$GUID_CS_HIGH)$" { return 'ביצועים גבוהים' }
        "^$GUID_BALANCED$"                 { return 'מאוזן' }
        "^$GUID_SAVER$"                    { return 'חיסכון בסוללה' }
    }
    # A plan left behind by an older version keeps a random id - go by name.
    if ($s.Name -match 'Ultimate|אולטימ') { return 'ביצועים אולטימטיביים (מותאם)' }
    if ($s.Name) { return $s.Name }
    return 'לא ידוע'
}

function Test-Scheme {
    param([string]$Guid)
    return (Test-Path -LiteralPath (Join-Path $REG_SCHEMES $Guid))
}

function Get-AllSchemes {
    # Read from the registry, not from `powercfg /list`: on Modern Standby
    # hardware the list shows Balanced plus whatever is active and hides every
    # other plan that exists.
    $all = @()
    Get-ChildItem -LiteralPath $REG_SCHEMES -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $all += [PSCustomObject]@{
            Guid        = ([string]$_.PSChildName).ToLower()
            Name        = [string]$p.FriendlyName
            Description = [string]$p.Description
        }
    }
    return $all
}

function Set-ActiveScheme {
    # True only if the plan really became the active one.
    param([string]$Guid)
    & powercfg.exe /setactive $Guid 2>&1 | Out-Null
    return ((Get-ActiveScheme).Guid -eq $Guid)
}

function Copy-Scheme {
    param([string]$From, [string]$To, [string]$Name, [string]$Description)
    & powercfg.exe -duplicatescheme $From $To 2>&1 | Out-Null
    if (-not (Test-Scheme $To)) { return $false }
    & powercfg.exe -changename $To $Name $Description 2>&1 | Out-Null
    return $true
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
    # Starts with an invisible left-to-right mark. Inside a Hebrew line,
    # "54.08 GB" is otherwise split by the bidi algorithm into a number and a
    # word and shown as "GB 54.08".
    param([double]$Bytes)
    $lrm = [string][char]0x200E
    if ($Bytes -ge 1GB) { return $lrm + ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return $lrm + ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return $lrm + ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return $lrm + ('{0:N0} B' -f $Bytes)
}

function Clear-FolderContents {
    # Deletes the *contents* only. The old scripts did `rd /s /q %TEMP%` and
    # `rd /s /q C:\Windows\Temp` then re-created the folders - that wipes the
    # NTFS ACLs on C:\Windows\Temp and can break Windows services.
    param([string]$Path)
    $freed = 0
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Test-Stop          # outside the try below, which swallows everything
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
    #
    # While it waits, the bottom button turns into "stop" (see Update-ExitButton).
    # Pressing it kills the tool together with its children - DISM and cleanmgr
    # do their real work in child processes - and unwinds the whole action
    # through an OperationCanceledException that Invoke-Action reports. Without
    # this a tool that hangs would lock the window for good, because closing
    # is refused while an action runs.
    #
    # -NoStop: for tools that must never be cut off half way (the edition
    # change). The window still stays alive; it just offers no stop button.
    param([string]$FilePath, [string[]]$ArgumentList, [switch]$NoStop)
    Test-Stop
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList (Join-ProcessArguments $ArgumentList) `
                           -WindowStyle Hidden -PassThru -ErrorAction Stop
        # Touch the handle now. A Process object that never opened one while
        # the process was alive reports an empty ExitCode afterwards.
        $null = $p.Handle
    } catch {
        return $null
    }
    $script:CanStop = -not $NoStop
    try {
        while (-not $p.HasExited) {
            Update-ExitButton
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:StopRequested -and -not $NoStop) {
                & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
                [void]$p.WaitForExit(5000)
                throw (New-Object System.OperationCanceledException)
            }
            Start-Sleep -Milliseconds 40
        }
    } finally {
        $script:CanStop = $false
    }
    return $p.ExitCode
}

function Join-ProcessArguments {
    # Start-Process glues an argument array together with bare spaces, so any
    # argument that contains one - a Desktop inside "OneDrive - Company", a
    # user folder with a space - arrives at the tool cut in two. Quote those
    # the way the C runtime splits a command line back up: backslashes are
    # literal unless they precede a quote.
    param([string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        if ($a -ne '' -and $a -notmatch '[\s"]') { $a; continue }
        $q = [regex]::Replace($a, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
        $q = [regex]::Replace($q, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
        '"' + $q + '"'
    }
    return ($parts -join ' ')
}

function Test-Stop {
    # For the stretches of an action that run in this process rather than in
    # an external tool: keeps the window alive and honours a stop request.
    [System.Windows.Forms.Application]::DoEvents()
    if ($script:StopRequested) { throw (New-Object System.OperationCanceledException) }
}

function Invoke-Background {
    # Runs a script block on a second thread and keeps pumping the window
    # until it returns. For slow cmdlets that have no external process to
    # wait on (Checkpoint-Computer can take a minute); calling them directly
    # would freeze the window and Windows would mark it "not responding".
    param([scriptblock]$Script, [object[]]$Arguments = @())
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript($Script.ToString())
        foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
        $handle = $ps.BeginInvoke()
        while (-not $handle.IsCompleted) {
            Update-ExitButton
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
        }
        return $ps.EndInvoke($handle)
    } finally {
        $ps.Dispose()
    }
}

# ============================================================================
#  Form
# ============================================================================
#
# One vertical stack: title, status, menu, log, bottom button. The menu row
# is exactly as tall as its buttons need and the log takes whatever is left:
# a bigger window means more log, and on a short screen the log gives way
# first, so no button is pushed out of sight while there is still log to
# squeeze. The real sizes are set at the very bottom of this file ("Build the
# menu"), once the captions have been measured.
#
# A note on TextAlign: under RightToLeft = Yes, WinForms reads "Left" as "the
# side a line starts on". MiddleLeft is therefore what puts Hebrew against the
# right edge; MiddleRight - what the versions before 2.1 used - pushes it to
# the left.

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Csharf $CSHARF_VERSION  -  כלי מערכת"
$form.AutoScaleMode   = 'None'          # scaled by hand, through S
$form.StartPosition   = 'Manual'        # placed by hand, on the right screen
$form.BackColor       = $C_BG
$form.ForeColor       = $C_FG
$form.Font            = $F_UI
$form.RightToLeft     = 'Yes'
$form.RightToLeftLayout = $true

$H_TITLE  = S 46
$H_STATUS = S 82
$H_BOTTOM = S 50
$H_LOG    = S 150      # preferred height; the first thing to give on a short screen
$H_LOGMIN = S 88
$PAD      = S 14       # the one side margin everything lines up on

$root                 = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock            = 'Fill'
$root.ColumnCount     = 1
$root.RowCount        = 5
$root.Margin          = New-Object System.Windows.Forms.Padding(0)
[void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $H_TITLE)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $H_STATUS)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (S 300))))   # menu: set for real below
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))        # log
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $H_BOTTOM)))
$form.Controls.Add($root)

$lblTitle             = New-Object System.Windows.Forms.Label
$lblTitle.Text        = '⚡  תפריט כלי מערכת  ⚡'
$lblTitle.Font        = $F_TITLE
$lblTitle.ForeColor   = $C_FG
$lblTitle.Dock        = 'Fill'
$lblTitle.Margin      = New-Object System.Windows.Forms.Padding(0)
$lblTitle.TextAlign   = 'MiddleCenter'
$root.Controls.Add($lblTitle, 0, 0)

# ---------------------------------------------------------- status strip ----
$pnlStatus            = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock       = 'Fill'
$pnlStatus.Margin     = New-Object System.Windows.Forms.Padding(0)
$pnlStatus.BackColor  = $C_PANEL
$pnlStatus.Padding    = New-Object System.Windows.Forms.Padding($PAD, (S 6), $PAD, (S 6))

$lblStatus            = New-Object System.Windows.Forms.Label
$lblStatus.Dock       = 'Fill'
$lblStatus.ForeColor  = $C_DIM
$lblStatus.TextAlign  = 'MiddleLeft'
$pnlStatus.Controls.Add($lblStatus)
$root.Controls.Add($pnlStatus, 0, 1)

# ------------------------------------------------------------------ menu ----
# Scrolls as a last resort only: when even the minimum log does not leave the
# buttons enough room (a very small screen, or a very high display scale).
$pnlMenu              = New-Object System.Windows.Forms.Panel
$pnlMenu.Dock         = 'Fill'
$pnlMenu.Margin       = New-Object System.Windows.Forms.Padding(0)
$pnlMenu.AutoScroll   = $true
$root.Controls.Add($pnlMenu, 0, 2)

# ------------------------------------------------------------------- log ----
$pnlLog               = New-Object System.Windows.Forms.Panel
$pnlLog.Dock          = 'Fill'
$pnlLog.Margin        = New-Object System.Windows.Forms.Padding(0)
$pnlLog.Padding       = New-Object System.Windows.Forms.Padding($PAD, (S 8), $PAD, (S 2))

$log                  = New-Object System.Windows.Forms.RichTextBox
$log.Dock             = 'Fill'
$log.ReadOnly         = $true
$log.BackColor        = [System.Drawing.Color]::FromArgb(8,8,8)
$log.ForeColor        = $C_DIM
$log.Font             = $F_MONO
$log.BorderStyle      = 'None'
$log.RightToLeft      = 'Yes'
$log.DetectUrls       = $false
# A one-pixel frame in the palette's own colour instead of the system's white
# FixedSingle border, which glared against the dark window.
$pnlLogFrame          = New-Object System.Windows.Forms.Panel
$pnlLogFrame.Dock     = 'Fill'
$pnlLogFrame.BackColor = [System.Drawing.Color]::FromArgb(60,70,60)
$pnlLogFrame.Padding  = New-Object System.Windows.Forms.Padding(1)
$pnlLogInner          = New-Object System.Windows.Forms.Panel
$pnlLogInner.Dock     = 'Fill'
$pnlLogInner.BackColor = $log.BackColor
$pnlLogInner.Padding  = New-Object System.Windows.Forms.Padding((S 8), (S 6), (S 8), (S 6))
$pnlLogInner.Controls.Add($log)
$pnlLogFrame.Controls.Add($pnlLogInner)
$pnlLog.Controls.Add($pnlLogFrame)
$root.Controls.Add($pnlLog, 0, 3)

# --------------------------------------------------------- bottom button ----
# "Exit" while idle; the stop button while an action runs (Update-ExitButton).
# It has a row of its own so it can never scroll away with the menu.
$pnlExit              = New-Object System.Windows.Forms.Panel
$pnlExit.Dock         = 'Fill'
$pnlExit.Margin       = New-Object System.Windows.Forms.Padding(0)
$pnlExit.Padding      = New-Object System.Windows.Forms.Padding($PAD, (S 8), $PAD, (S 10))

$bExit               = New-Object System.Windows.Forms.Button
$bExit.Text          = 'יציאה'
$bExit.Dock          = 'Fill'
$bExit.FlatStyle     = 'Flat'
$bExit.BackColor     = [System.Drawing.Color]::FromArgb(20,20,20)
$bExit.ForeColor     = $C_DIM
$bExit.TextAlign     = 'MiddleCenter'
$bExit.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,70,60)
$bExit.Cursor        = 'Hand'
$bExit.Add_Click({
    if (-not $script:Busy)  { $form.Close() }
    elseif ($script:CanStop) { $script:StopRequested = $true; Update-ExitButton }
})
$pnlExit.Controls.Add($bExit)
$root.Controls.Add($pnlExit, 0, 4)

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
    $sys  = ([string]$env:SystemDrive).TrimEnd(':')
    $free = Format-Size (Get-FreeSpaceBytes $sys)
    # Each label is Hebrew only and the value follows the colon. A label that
    # mixes in a Latin word ("מהדורת Windows:") is torn apart by the bidi
    # algorithm: the Latin half travels to the far end of the line together
    # with the value. No square brackets either - they get mirrored.
    $lblStatus.Text = @(
        "מצב ביצועים נוכחי:  $(Get-SchemeLabel)"
        "מערכת ההפעלה:  $($ed.ProductName) $($ed.Display)  ·  $($ed.EditionID)"
        "מצב תרדמה:  $hib          מקום פנוי בכונן המערכת:  $free"
    ) -join [Environment]::NewLine
    Update-Toggles
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------------------------------------------------------- toggle buttons ---
# A switch-like button says what pressing it will DO, given the PC's state
# right now; a button that has nothing to do is greyed out and says why.
# Every caption a button can ever show is listed here, so the column width is
# measured against the longest of them.
$TOGGLE_TEXT = @{
    HibOffDo   = 'השבתת מצב תרדמה  (מחיקת hiberfil.sys)'
    HibOffDone = 'מצב תרדמה כבר מושבת'
    HibOnDo    = 'הפעלת מצב תרדמה מחדש'
    HibOnDone  = 'מצב תרדמה כבר פעיל'
    MenuToOld  = 'תפריט ההקשר המלא והישן  (Windows 11)'
    MenuToNew  = 'החזרת תפריט ההקשר המקוצר  (Windows 11)'
    MenuNA     = 'תפריט ההקשר הישן - רק ב-Windows 11'
    ExtShow    = 'הצגת סיומות וקבצים מוסתרים'
    ExtHide    = 'הסתרת סיומות וקבצים מוסתרים'
}
$script:KeyButtons = @{}

function Test-ClassicMenu {
    return (Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')
}
function Test-ExtensionsShown {
    try {
        $k = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction Stop
        return ($k.HideFileExt -eq 0 -and $k.Hidden -eq 1)
    } catch { return $false }
}

function Set-Toggle {
    param([string]$Key, [string]$Text, [bool]$Applicable)
    $b = $script:KeyButtons[$Key]
    if (-not $b) { return }
    if ($b.Text -ne $Text) { $b.Text = $Text }
    # The Tag survives Set-Busy, which re-enables only what is applicable.
    $b.Tag = if ($Applicable) { $null } else { 'na' }
    $b.Enabled = $Applicable -and -not $script:Busy
}

function Update-Toggles {
    $hib = Get-HibernateEnabled
    Set-Toggle 'HibOff' $(if ($hib) { $TOGGLE_TEXT.HibOffDo } else { $TOGGLE_TEXT.HibOffDone }) $hib
    Set-Toggle 'HibOn'  $(if ($hib) { $TOGGLE_TEXT.HibOnDone } else { $TOGGLE_TEXT.HibOnDo }) (-not $hib)
    if ((Get-BuildNumber) -lt 22000) {
        Set-Toggle 'Menu' $TOGGLE_TEXT.MenuNA $false
    } else {
        Set-Toggle 'Menu' $(if (Test-ClassicMenu) { $TOGGLE_TEXT.MenuToNew } else { $TOGGLE_TEXT.MenuToOld }) $true
    }
    Set-Toggle 'Ext' $(if (Test-ExtensionsShown) { $TOGGLE_TEXT.ExtHide } else { $TOGGLE_TEXT.ExtShow }) $true
}

$script:Busy          = $false
$script:BusySince     = $null
$script:CanStop       = $false   # an external tool is running and may be killed
$script:StopRequested = $false
$script:CloseAfter    = $false   # the user asked to close while an action ran
$script:MenuButtons   = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]

function Update-ExitButton {
    # The bottom button doubles as progress display and stop control. Called
    # from every wait loop; it only touches the control when the caption
    # actually changes, so it can be called as often as the loop spins.
    if (-not $script:Busy) {
        $text = 'יציאה'; $color = $C_DIM; $enabled = $true
    } else {
        $el    = (Get-Date) - $script:BusySince
        $clock = '{0:00}:{1:00}' -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds
        if ($script:StopRequested) { $text = "עוצר...   $clock";            $color = $C_DIM;  $enabled = $false }
        elseif ($script:CanStop)   { $text = "עצירת הפעולה   $clock";      $color = $C_WARN; $enabled = $true  }
        else                       { $text = "פועל, נא להמתין...   $clock"; $color = $C_DIM;  $enabled = $false }
    }
    if ($bExit.Text -ne $text)       { $bExit.Text = $text }
    if ($bExit.ForeColor -ne $color) { $bExit.ForeColor = $color }
    if ($bExit.Enabled -ne $enabled) { $bExit.Enabled = $enabled }
}

function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    # A stop request belongs to the action it was made in. Cleared on both
    # edges, so one can never leak into whatever runs next.
    $script:StopRequested = $false
    $script:CanStop       = $false
    if ($On) { $script:BusySince = Get-Date }
    foreach ($b in $script:MenuButtons) { $b.Enabled = (-not $On) -and ($b.Tag -ne 'na') }
    Update-ExitButton
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
        try { & $Body }
        catch [System.OperationCanceledException] { Write-Warn 'הפעולה נעצרה לפי בקשתך.' }
        catch { Write-Err "שגיאה: $($_.Exception.Message)" }
        try { Update-Status } catch { Write-Warn 'לא הצלחתי לרענן את שורת הסטטוס.' }
    } finally {
        Set-Busy $false
    }
    if ($script:CloseAfter) { $form.Close() }
}

# ============================================================================
#  Actions
# ============================================================================

function Use-OwnScheme {
    # Activates one of the two plans this tool owns, creating it first from
    # $From when it does not exist yet. Exactly one copy can ever exist - the
    # id is fixed - so pressing the button again just switches back to it.
    # A copy that exists but will not activate (half-written by a crash) is
    # removed and made again.
    param([string]$Guid, [string]$From, [string]$Name, [string]$Description, [object[]]$Tune = @())
    if ((Test-Scheme $Guid) -and (Set-ActiveScheme $Guid)) { return 'existing' }
    if (Test-Scheme $Guid) { & powercfg.exe /delete $Guid 2>&1 | Out-Null }
    if (-not (Copy-Scheme $From $Guid $Name $Description)) { return $null }
    # Each tuning entry is @('AC'|'DC'|'BOTH', subgroup, setting, value).
    foreach ($t in $Tune) {
        if ($t[0] -ne 'DC') { & powercfg.exe -setacvalueindex $Guid $t[1] $t[2] $t[3] 2>&1 | Out-Null }
        if ($t[0] -ne 'AC') { & powercfg.exe -setdcvalueindex $Guid $t[1] $t[2] $t[3] 2>&1 | Out-Null }
    }
    if (Set-ActiveScheme $Guid) { return 'created' }
    return $null
}

function Set-ProcessorIdleAllowed {
    # Processor idle states stay ON, on mains and on battery alike. 2.1 turned
    # them off in its stand-in Ultimate plan: the CPU then never rests - hot,
    # loud, a drained battery, and often LESS speed, because a core that never
    # idles leaves no thermal room for turbo. Also repairs a plan 2.1 made.
    param([string]$Guid)
    & powercfg.exe -setacvalueindex $Guid SUB_PROCESSOR IDLEDISABLE 0 2>&1 | Out-Null
    & powercfg.exe -setdcvalueindex $Guid SUB_PROCESSOR IDLEDISABLE 0 2>&1 | Out-Null
    # Changed values of the ACTIVE plan only apply once it is set active again.
    [void](Set-ActiveScheme $Guid)
}

function Action-HighPerf {
    # The built-in plan whenever Windows lets us use it.
    if (Set-ActiveScheme $GUID_HIGHPERF) {
        Write-Ok 'מצב ביצועים גבוהים הופעל.'
        return
    }
    # Some laptops (Modern Standby) and trimmed OEM images refuse it. A copy
    # under this tool's own id stands in: of High Performance when it exists
    # but will not activate, otherwise Balanced with the processor held at full
    # speed while plugged in.
    if (Test-Scheme $GUID_HIGHPERF) {
        $r = Use-OwnScheme $GUID_CS_HIGH $GUID_HIGHPERF 'High Performance (Csharf)' 'ביצועים גבוהים - Csharf'
    } else {
        $r = Use-OwnScheme $GUID_CS_HIGH $GUID_BALANCED 'High Performance (Csharf)' 'ביצועים גבוהים - Csharf' `
                           -Tune @(,@('AC','SUB_PROCESSOR','PROCTHROTTLEMIN',100))
    }
    if ($r) { Write-Ok 'מצב ביצועים גבוהים הופעל (תוכנית מותאמת, כי המחשב חוסם את הרגילה).' }
    else    { Write-Err 'לא הצלחתי להפעיל מצב ביצועים גבוהים במחשב הזה.' }
}

function Action-UltraPerf {
    # The official plan: Windows keeps Ultimate Performance as a hidden
    # template, and copying it is the documented way to turn it on. Versions
    # before 2.1 made the copy and then tried to activate the template itself,
    # which never works - so the official plan was never actually used.
    Write-Log 'מנסה להפעיל את תוכנית החשמל הרשמית של Windows...'
    $r = Use-OwnScheme $GUID_CS_ULT $GUID_ULTIMATE 'Ultimate Performance (Csharf)' 'ביצועים אולטימטיביים - Csharf'
    if ($r) {
        Set-ProcessorIdleAllowed $GUID_CS_ULT
        Write-Ok 'מצב ביצועים אולטימטיביים הופעל.'
        return
    }

    # Home editions and Modern Standby laptops block the template. Build an
    # equivalent from High Performance (or Balanced, where that is missing).
    # Full speed applies on mains power only; on battery the plan keeps the
    # base plan's own values, so a laptop does not cook itself in a bag.
    # The display timeout is left alone everywhere.
    Write-Warn 'המחשב חוסם את התוכנית הרשמית - בונה תוכנית מקבילה.'
    $base = if (Test-Scheme $GUID_HIGHPERF) { $GUID_HIGHPERF } else { $GUID_BALANCED }
    $r = Use-OwnScheme $GUID_CS_ULT $base 'Ultimate Performance (Csharf)' 'ביצועים אולטימטיביים - Csharf' -Tune @(
        @('AC', 'SUB_PROCESSOR', 'PROCTHROTTLEMIN', 100),
        @('AC', 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100),
        @('AC', 'SUB_DISK',      'DISKIDLE',        0),
        @('AC', 'SUB_SLEEP',     'STANDBYIDLE',     0)
    )
    if ($r) {
        Set-ProcessorIdleAllowed $GUID_CS_ULT
        Write-Ok 'מצב ביצועים אולטימטיביים הופעל (תוכנית מקבילה; מהירות מלאה כשהמחשב מחובר לחשמל).'
    } else {
        Write-Err 'לא הצלחתי להפעיל מצב ביצועים אולטימטיביים במחשב הזה.'
    }
}

function Get-LeftoverSchemes {
    # Plans this tool created and no longer needs. Read from the registry,
    # because `powercfg /list` hides most plans on Modern Standby laptops.
    #   - its own two fixed ids
    #   - anything named or described as made by Csharf, by any version
    #   - nameless copies of the stock High Performance / Ultimate plans: what
    #     `powercfg -duplicatescheme` without a destination leaves behind,
    #     which every version before 2.1 did on every click
    # Never a built-in plan, never the active one, never a plan someone named
    # themselves.
    param([string]$Active)
    $builtin = @($GUID_BALANCED, $GUID_HIGHPERF, $GUID_SAVER, $GUID_ULTIMATE)
    foreach ($s in (Get-AllSchemes)) {
        if ($builtin -contains $s.Guid -or $s.Guid -eq $Active) { continue }
        $ours = ($s.Guid -eq $GUID_CS_ULT) -or ($s.Guid -eq $GUID_CS_HIGH) -or
                ($s.Name -match 'Csharf') -or
                ($s.Description -match '^ביצועים (אולטימטיביים|גבוהים) (- מותאם|\(מותאם\)|- Csharf)$')
        $stockCopy = $s.Name -match '^@[^,]*powrprof\.dll,-\d+,(High performance|Ultimate Performance)$'
        if ($ours -or $stockCopy) { $s }
    }
}

function Action-Balanced {
    if (-not (Set-ActiveScheme $GUID_BALANCED)) {
        Write-Err 'המעבר למצב מאוזן נכשל.'
        return
    }
    Write-Ok 'המערכת חזרה למצב מאוזן.'

    $removed = 0
    foreach ($s in @(Get-LeftoverSchemes -Active $GUID_BALANCED)) {
        Test-Stop
        & powercfg.exe /delete $s.Guid 2>&1 | Out-Null
        if (-not (Test-Scheme $s.Guid)) { $removed++ }
    }
    if ($removed -gt 0) { Write-Ok "נוקו $removed תוכניות חשמל כפולות שנשארו מהפעלות קודמות." }
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
    # Runs on a second thread: Checkpoint-Computer is a cmdlet, not a process,
    # so Start-Tool cannot keep the window alive while it works.
    #
    # Two traps the versions before 2.1 fell into:
    #  - Windows silently skips the request when a restore point was made in
    #    the last 24 hours. Checkpoint-Computer then only writes a warning, no
    #    error, and the tool reported "created". So the newest point is
    #    compared before and after, and the 24-hour limit is lifted for this
    #    one request (the documented SystemRestorePointCreationFrequency
    #    value) and put back exactly as it was.
    #  - The drive was hard-coded as C:.
    $res = Invoke-Background -Arguments @("$env:SystemDrive\") -Script {
        param($Drive)
        $key  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $name = 'SystemRestorePointCreationFrequency'
        $had  = $null
        try { $had = (Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction Stop).$name } catch { }
        $newest = { @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) |
                    Sort-Object SequenceNumber | Select-Object -Last 1 -ExpandProperty SequenceNumber }
        $before = & $newest
        $err    = ''
        try {
            Enable-ComputerRestore -Drive $Drive -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath $key -Name $name -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description 'Csharf' -RestorePointType 'MODIFY_SETTINGS' `
                                -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            $err = $_.Exception.Message
        } finally {
            if ($null -eq $had) { Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue }
            else { Set-ItemProperty -LiteralPath $key -Name $name -Value $had -Type DWord -ErrorAction SilentlyContinue }
        }
        $after = & $newest
        [PSCustomObject]@{ Created = ($null -ne $after -and $after -ne $before); Error = $err }
    }
    $res = @($res) | Select-Object -Last 1
    if ($res -and $res.Created) {
        Write-Ok 'נקודת שחזור נוצרה.'
    } elseif ($res -and $res.Error) {
        Write-Warn "לא נוצרה נקודת שחזור: $($res.Error)"
    } else {
        Write-Warn 'לא נוצרה נקודת שחזור. ייתכן ששחזור המערכת כבוי במחשב הזה או חסום על ידי מדיניות.'
    }
}

function Confirm-Action {
    # Yes/No question, "No" preselected, laid out right to left.
    param([string[]]$Lines, [string]$Title)
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $form, ($Lines -join [Environment]::NewLine), $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2,
        [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor
        [System.Windows.Forms.MessageBoxOptions]::RightAlign)
    return ($ans -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Action-Cleanup {
    if (-not (Confirm-Action -Title 'אזהרה - פינוי שטח' -Lines @(
        'הפעולה תמחק:'
        '•  קבצים זמניים של Windows ושל התוכנות'
        '•  את כל מה שנמצא בסל המיחזור'
        '•  קבצי עדכונים ישנים, יומני התקנה ודוחות שגיאה'
        ''
        'הקבצים שיימחקו לא ניתנים לשחזור. להמשיך?'))) {
        Write-Warn 'הפעולה בוטלה.'
        return
    }

    # The previous Windows installation gets a question of its own. Removing
    # it frees a lot of space, but it is also the only way back after a
    # Windows upgrade - not something to take away inside "temporary files".
    $winOld    = Join-Path $env:SystemDrive 'Windows.old'
    $dropOld   = $false
    if (Test-Path -LiteralPath $winOld) {
        $dropOld = Confirm-Action -Title 'התקנה קודמת של Windows' -Lines @(
            'נמצאה במחשב התקנה קודמת של Windows (התיקייה Windows.old).'
            ''
            'מחיקתה מפנה הרבה מקום, אבל אחריה כבר אי אפשר'
            'לחזור לגרסת Windows הקודמת.'
            ''
            'למחוק גם אותה?')
    }

    $sys    = ([string]$env:SystemDrive).TrimEnd(':')
    $before = Get-FreeSpaceBytes $sys

    Write-Log 'מסמן קטגוריות לניקוי עבור cleanmgr...'
    # Left out on purpose:
    #  - "User file versions" is File History - the user's own backup copies.
    #  - "Previous Installations" only when the user agreed above.
    $caches = @(
        'Active Setup Temp Folders','BranchCache','Downloaded Program Files',
        'Internet Cache Files','Memory Dump Files','Old ChkDsk Files',
        'Recycle Bin','Service Pack Cleanup',
        'Setup Log Files','System error memory dump files',
        'System error minidump files','Temporary Files','Update Cleanup',
        'Windows Error Reporting Files'
    )
    if ($dropOld) { $caches += 'Previous Installations' }
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    # Preset 1 is shared with every earlier run, and versions before 2.1 also
    # ticked "Previous Installations" and "User file versions". Clear the
    # whole preset first, so it holds exactly the list above and nothing a
    # previous run left switched on.
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-ItemProperty -LiteralPath $_.PSPath -Name 'StateFlags0001' -ErrorAction SilentlyContinue
    }
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
    $temps = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:LOCALAPPDATA 'Temp')) |
             Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
             ForEach-Object { (Resolve-Path -LiteralPath $_).ProviderPath.TrimEnd('\') } |
             Select-Object -Unique
    foreach ($t in $temps) {
        # A temp folder sitting at the root of a drive would be the whole drive.
        if ($t -match '^[A-Za-z]:$') { continue }
        $freed += Clear-FolderContents $t
    }
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

    $after = Get-FreeSpaceBytes $sys
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
    $dlg.AutoScaleMode = 'None'
    $dlg.ClientSize    = New-Object System.Drawing.Size((S 420), (S 150))
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
    $btn.Height        = S 42
    $btn.FlatStyle     = 'Flat'
    $btn.BackColor     = $C_BTN
    $btn.ForeColor     = $C_WARN
    $dlg.Controls.Add($btn)

    # Event handlers run off the message loop, where this function's local
    # scope is no longer on the lookup chain - so everything a handler touches
    # is kept at script scope.
    $script:cdLeft      = 15
    # Default to cancelled. The title-bar X and Alt+F4 call Form.Close()
    # directly - neither handler below runs, so nothing else would ever set
    # this flag on that path. Proceeding to reboot must be something the
    # timer itself opts into by reaching zero, not the fallback for "the
    # window went away for some unrecognised reason".
    $script:cdCancelled = $true
    $script:cdDlg       = $dlg
    $script:cdLbl       = $lbl
    $lbl.Text = "המחשב יופעל מחדש בעוד $($script:cdLeft) שניות..."

    $script:cdTimer          = New-Object System.Windows.Forms.Timer
    $script:cdTimer.Interval = 1000
    $script:cdTimer.Add_Tick({
        $script:cdLeft--
        if ($script:cdLeft -le 0) {
            $script:cdCancelled = $false
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
    # The generic key moves Home to Pro, nothing else. On Education or
    # Enterprise it would be a step down, and Windows may well go along with it.
    if ($ed.EditionID -notmatch '^Core') {
        Write-Warn "הפעולה מיועדת למהדורת Home בלבד. המהדורה במחשב הזה: $($ed.EditionID). לא בוצע שינוי."
        return
    }
    # v1 simply ran changepk.exe and let it report its own failure. Keep that
    # behaviour - resolve a real path when we can, but never refuse to try.
    $changepk = Resolve-SystemExe 'changepk.exe'
    if (-not $changepk) {
        Write-Warn 'changepk.exe לא אותר בנתיב הרגיל - מנסה בכל זאת.'
        $changepk = 'changepk.exe'
    }

    if (-not (Confirm-Action -Title 'שדרוג מהדורה ל-Pro' -Lines @(
        "המהדורה הנוכחית: $($ed.ProductName)  ·  $($ed.EditionID)"
        ''
        'הפעולה תשנה את מהדורת Windows ל-Pro ותפעיל את המחשב מחדש.'
        'שמור וסגור את כל המסמכים הפתוחים לפני שתמשיך.'
        ''
        'שים לב: שינוי המהדורה אינו הפעלה (Activation).'
        'לאחר ההפעלה מחדש עדיין יידרש רישיון Pro תקף.'
        ''
        'להמשיך?'))) {
        Write-Warn 'הפעולה בוטלה.'
        return
    }

    # changepk needs these two services able to run. Only one that is switched
    # off gets touched, and only for the duration of the change: versions
    # before 2.1 set both to "automatic" for good, which quietly undid anyone's
    # deliberate choice to keep Windows Update off.
    Write-Log 'מכין את התשתית לשדרוג (הפעלת שירותים נדרשים)...'
    $restore = @{}
    foreach ($svc in @('LicenseManager','wuauserv')) {
        $start = $null
        try { $start = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -ErrorAction Stop).Start } catch { }
        if ($start -eq 4) {
            & sc.exe config $svc start= demand 2>&1 | Out-Null
            $restore[$svc] = $true
        }
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }

    Write-Log 'מריץ changepk.exe...'
    # Never stoppable half way (-NoStop), but the window stays responsive.
    # v2/v4 had `timeout /t 5` between changepk and the errorlevel check, which
    # reset ERRORLEVEL - so they always reported success. Fixed by reading the
    # process exit code directly.
    try {
        $code = Start-Tool $changepk @('/productkey', $PRO_KEY) -NoStop
    } finally {
        foreach ($svc in $restore.Keys) { & sc.exe config $svc start= disabled 2>&1 | Out-Null }
    }
    if ($code -ne 0) {
        $shown = if ($null -eq $code) { 'n/a' } else { $code }
        Write-Err "שינוי המהדורה נכשל (קוד $shown). ודא חיבור לאינטרנט ונסה שוב."
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
    # Asked first: the desktop and taskbar blink away and every open folder
    # window closes - not something to spring on anyone mid-work.
    if (-not (Confirm-Action -Title 'הפעלה מחדש של סייר הקבצים' -Lines @(
        'כדי שהשינוי ייכנס לתוקף צריך להפעיל מחדש את סייר הקבצים.'
        'שולחן העבודה ושורת המשימות ייעלמו לרגע, וחלונות תיקיות פתוחים ייסגרו.'
        ''
        'להפעיל מחדש עכשיו?'))) {
        Write-Log 'השינוי יופיע אחרי הפעלה מחדש של סייר הקבצים או של המחשב.' $C_DIM
        return
    }
    Write-Log 'מפעיל מחדש את סייר הקבצים...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    # Windows brings the shell back by itself (AutoRestartShell), as the
    # signed-in user. Up to 2.1 this process started it after two seconds
    # when that had not happened yet - and a shell started from here runs
    # with administrator rights, the whole desktop and everything launched
    # from it. So: wait properly, and as a last resort start it with the
    # administrator rights stripped (runas /trustlevel:0x20000).
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        [System.Windows.Forms.Application]::DoEvents()
        if (Get-Process explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\runas.exe') -WindowStyle Hidden `
                  -ArgumentList @('/trustlevel:0x20000', ('"{0}"' -f (Join-Path $env:SystemRoot 'explorer.exe')))
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
        # Through explorer.exe rather than opening the file directly. This
        # process runs as administrator, and anything it opens would inherit
        # that - a whole web browser with administrator rights. A new
        # explorer.exe hands the file to the user's own, normal shell instead.
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') `
                      -ArgumentList ('"{0}"' -f $out) -ErrorAction SilentlyContinue
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
    if (-not (Confirm-Action -Title 'איפוס הגדרות הרשת' -Lines @(
        'הפעולה תאפס את מחסנית הרשת: מטמון DNS, Winsock ו-TCP/IP.'
        ''
        'שימושי כשהאינטרנט מתנהג מוזר אחרי הסרת VPN או אנטי-וירוס.'
        'לאחר מכן תידרש הפעלה מחדש, וייתכן שיהיה צורך להתחבר שוב לרשת.'
        ''
        'שים לב: כתובת IP קבועה שהוגדרה ידנית תימחק, והחיבור יחזור'
        'לקבל כתובת אוטומטית. אם הגדרת כתובת כזו, רשום אותה לפני כן.'
        ''
        'להמשיך?'))) { Write-Warn 'הפעולה בוטלה.'; return }

    foreach ($step in @(
        @('ipconfig.exe', @('/flushdns'),               'מטמון DNS נוקה'),
        @('ipconfig.exe', @('/registerdns'),            'רשומות DNS נרשמו מחדש'),
        @('netsh.exe',    @('winsock','reset'),         'Winsock אופס'),
        @('netsh.exe',    @('int','ip','reset'),        'מחסנית TCP/IPv4 אופסה'),
        @('netsh.exe',    @('int','ipv6','reset'),      'מחסנית TCP/IPv6 אופסה')
    )) {
        $code = Start-Tool $step[0] $step[1]
        # netsh often resets most of the stack and still returns 1 because one
        # key was locked - "partly", not "done" and not "failed".
        if     ($code -eq 0)    { Write-Ok $step[2] }
        elseif ($null -eq $code) { Write-Err "נכשל: $($step[2])" }
        else                    { Write-Warn "בוצע חלקית (קוד $code): $($step[2])" }
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

$groups = @{
    perf = @{ Title = 'ביצועים וחשמל'; Items = @(
        @{ Text = 'מעבר למצב ביצועים גבוהים';                 Act = { Action-HighPerf } }
        @{ Text = 'מעבר למצב ביצועים אולטימטיביים';           Act = { Action-UltraPerf } }
        @{ Text = 'חזרה למצב ביצועים מאוזן';                  Act = { Action-Balanced } }
        @{ Text = $TOGGLE_TEXT.HibOffDo;                      Act = { Action-HibernateOff }; Key = 'HibOff' }
        @{ Text = $TOGGLE_TEXT.HibOnDo;                       Act = { Action-HibernateOn };  Key = 'HibOn' }
        @{ Text = 'דוח בריאות סוללה';                         Act = { Action-BatteryReport } }
    ) }
    clean = @{ Title = 'ניקוי ושטח'; Items = @(
        @{ Text = 'פינוי שטח וניקוי מערכת יסודי';             Act = { Action-Cleanup };  Hot = $true }
        @{ Text = 'שחרור האחסון השמור של Windows';            Act = { Action-ReservedStorage } }
        @{ Text = 'תיקון קבצי מערכת  (DISM + SFC)';           Act = { Action-RepairSystem } }
    ) }
    access = @{ Title = 'גישה מהירה וממשק'; Items = @(
        @{ Text = 'קיצור לרשימת כל התוכנות';                  Act = { Action-Shortcut } }
        @{ Text = 'קיצור ל-God Mode  (כל ההגדרות)';           Act = { Action-GodMode } }
        @{ Text = $TOGGLE_TEXT.MenuToOld;                     Act = { Action-ClassicMenu };    Key = 'Menu' }
        @{ Text = $TOGGLE_TEXT.ExtShow;                       Act = { Action-FileExtensions }; Key = 'Ext' }
    ) }
    net = @{ Title = 'רשת'; Items = @(
        @{ Text = 'איפוס הגדרות הרשת';                         Act = { Action-NetworkReset };  Hot = $true }
        @{ Text = 'הצגת סיסמאות ה-Wi-Fi השמורות';             Act = { Action-WifiPasswords } }
    ) }
    sys = @{ Title = 'מערכת ורישוי'; Items = @(
        @{ Text = 'יצירת נקודת שחזור';                        Act = { Action-RestorePoint } }
        @{ Text = 'הצגת מפתח המוצר מהקושחה';                  Act = { Action-ProductKey } }
        @{ Text = 'שדרוג מהדורה מ-Home ל-Pro';                Act = { Action-UpgradePro };  Hot = $true }
    ) }
}

# Columns are filled by group, never by item count - a count-based split can
# strand a heading at the foot of one column with its buttons in the next.
# The first column is the right-hand one: that is where an RTL reader starts.
# Two columns when the screen is tall enough; three - a wider, shorter window -
# when it is not, which is the usual 1080p laptop running at 150%.
$layouts = @('perf,clean|access,net,sys', 'perf|clean,net|access,sys')

$H_HEAD   = S 26; $M_HEAD = S 10       # heading height, space above it
$H_BTN    = S 36; $M_BTN  = S 4        # button height, space under it
$HALF     = S 6
$GAP      = 2 * $HALF                  # between columns; even, so it splits cleanly
$PAD_TOP  = S 4
$minCol   = S 300
$maxText  = 0
$captions = @($groups.Values | ForEach-Object { $_.Items } | ForEach-Object { $_.Text }) + @($TOGGLE_TEXT.Values)
foreach ($c in $captions) {
    $w = [System.Windows.Forms.TextRenderer]::MeasureText($c, $F_UI).Width
    if ($w -gt $maxText) { $maxText = $w }
}
# caption + inner padding on both sides + the flat border
$colWidth = [Math]::Max($minCol, $maxText + (S 24) + (S 8))

function Get-ColumnHeight {
    param([string[]]$Keys)
    $h = 0
    foreach ($k in $Keys) { $h += $H_HEAD + $M_HEAD + (S 2) + $groups[$k].Items.Count * ($H_BTN + $M_BTN) }
    return $h
}

# Size of the window frame around the client area, for this display scale.
$form.ClientSize = New-Object System.Drawing.Size(1000, 1000)
$frameW = $form.Width  - 1000
$frameH = $form.Height - 1000

$wa      = $script:WorkArea
$fixedH  = $H_TITLE + $H_STATUS + $H_BOTTOM
$choice  = $null
$fallback = $null
foreach ($lay in $layouts) {
    $cols  = $lay.Split('|')
    $menuH = $PAD_TOP + (($cols | ForEach-Object { Get-ColumnHeight $_.Split(',') } | Measure-Object -Maximum).Maximum) + (S 8)
    $menuW = $cols.Count * ($colWidth + $GAP) + 2 * ($PAD - $HALF)
    $cand  = @{ Cols = $cols; MenuH = $menuH; MenuW = $menuW }
    $fitsW = ($menuW + $frameW) -le $wa.Width
    $fitsH = ($fixedH + $menuH + $H_LOGMIN + $frameH) -le $wa.Height
    if ($fitsW -and $fitsH) { $choice = $cand; break }
    if ($fitsW -and (-not $fallback -or $menuH -lt $fallback.MenuH)) { $fallback = $cand }
}
if (-not $choice) { $choice = if ($fallback) { $fallback } else { @{ Cols = $layouts[0].Split('|'); MenuH = 0; MenuW = 0 } } }
if ($choice.MenuH -eq 0) {
    $c = $choice.Cols
    $choice.MenuH = $PAD_TOP + (($c | ForEach-Object { Get-ColumnHeight $_.Split(',') } | Measure-Object -Maximum).Maximum) + (S 8)
    $choice.MenuW = $c.Count * ($colWidth + $GAP) + 2 * ($PAD - $HALF)
}

# ---- the columns ------------------------------------------------------------
$nCols                = $choice.Cols.Count
$pnlBtns              = New-Object System.Windows.Forms.TableLayoutPanel
$pnlBtns.Dock         = 'Top'
$pnlBtns.Height       = $choice.MenuH
$pnlBtns.ColumnCount  = $nCols
$pnlBtns.RowCount     = 1
$pnlBtns.Margin       = New-Object System.Windows.Forms.Padding(0)
$pnlBtns.Padding      = New-Object System.Windows.Forms.Padding(($PAD - $HALF), $PAD_TOP, ($PAD - $HALF), 0)
# Fixed widths, exactly one button plus the gap. Percent columns round to
# whole pixels on their own and could end up a pixel narrower than the button,
# clipping its far edge. In a wider window the spare room goes to the far
# (left) side, as it should in a right-to-left layout.
for ($i = 0; $i -lt $nCols; $i++) {
    [void]$pnlBtns.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, ($colWidth + $GAP))))
}
[void]$pnlBtns.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$pnlMenu.Controls.Add($pnlBtns)

for ($ci = 0; $ci -lt $nCols; $ci++) {
    $col               = New-Object System.Windows.Forms.FlowLayoutPanel
    $col.Dock          = 'Fill'
    $col.FlowDirection = 'TopDown'
    $col.WrapContents  = $false
    $col.Margin        = New-Object System.Windows.Forms.Padding($HALF, 0, $HALF, 0)
    $pnlBtns.Controls.Add($col, $ci, 0)

    foreach ($key in $choice.Cols[$ci].Split(',')) {
        $g            = $groups[$key]
        $h            = New-Object System.Windows.Forms.Label
        $h.Text       = $g.Title
        $h.Font       = $F_BOLD
        $h.ForeColor  = $C_DIM
        $h.AutoSize   = $false
        $h.Width      = $colWidth
        $h.Height     = $H_HEAD
        $h.TextAlign  = 'BottomLeft'      # = right edge under RightToLeft
        $h.Margin     = New-Object System.Windows.Forms.Padding(0, $M_HEAD, 0, (S 2))
        $col.Controls.Add($h)

        foreach ($item in $g.Items) {
            $b               = New-Object System.Windows.Forms.Button
            $b.Text          = $item.Text
            $b.Width         = $colWidth
            $b.Height        = $H_BTN
            $b.Margin        = New-Object System.Windows.Forms.Padding(0, 0, 0, $M_BTN)
            $b.FlatStyle     = 'Flat'
            $b.BackColor     = $C_BTN
            $b.ForeColor     = if ($item.Hot) { $C_WARN } else { $C_FG }
            $b.TextAlign     = 'MiddleLeft'   # = right edge under RightToLeft
            $b.Padding       = New-Object System.Windows.Forms.Padding((S 12), 0, (S 12), 0)
            $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,70,60)
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(48,56,48)
            $b.Cursor        = 'Hand'

            # The log heading uses the caption as it reads at the moment of the
            # click - a toggle's caption changes with the PC's state.
            $action = $item.Act
            $b.Add_Click({ param($sender, $e) Invoke-Action $sender.Text $action }.GetNewClosure())

            $col.Controls.Add($b)
            $script:MenuButtons.Add($b)
            if ($item.Key) { $script:KeyButtons[$item.Key] = $b }
        }
    }
}

# ---- window size and place --------------------------------------------------
# The log row soaks up whatever height is left. On a screen too short for
# even the smallest log, the menu row is cut down instead and scrolls.
$clientW = [Math]::Max($choice.MenuW, (S 640))
$clientW = [Math]::Min($clientW, $wa.Width - $frameW)
$menuRow = $choice.MenuH
$room    = $wa.Height - $frameH - $fixedH
if ($menuRow + $H_LOGMIN -gt $room) { $menuRow = [Math]::Max((S 120), $room - $H_LOGMIN) }
$logRow  = [Math]::Max($H_LOGMIN, [Math]::Min($H_LOG, $room - $menuRow))
$root.RowStyles[2].Height = $menuRow
$form.ClientSize  = New-Object System.Drawing.Size($clientW, ($fixedH + $menuRow + $logRow))
$form.MinimumSize = New-Object System.Drawing.Size(
    [Math]::Min($form.Width, $wa.Width),
    [Math]::Min(($frameH + $fixedH + $menuRow + (S 60)), $wa.Height))
$form.Location    = New-Object System.Drawing.Point(
    ($wa.X + [Math]::Max(0, [int](($wa.Width  - $form.Width)  / 2))),
    ($wa.Y + [Math]::Max(0, [int](($wa.Height - $form.Height) / 2))))

# Closing while an action runs: an external tool can be stopped first,
# anything else is simply waited for. Either way the window then closes by
# itself, so the person's request is honoured rather than ignored.
$form.Add_FormClosing({
    if (-not $script:Busy) { return }
    $_.Cancel = $true
    if ($script:CloseAfter) { return }
    if ($script:CanStop) {
        if (Confirm-Action -Title 'Csharf' -Lines @('פעולה עדיין רצה.', '', 'לעצור אותה ולסגור את החלון?')) {
            $script:CloseAfter    = $true
            $script:StopRequested = $true
            Update-ExitButton
        }
    } else {
        $script:CloseAfter = $true
        Write-Warn 'אי אפשר לעצור את הפעולה הזו באמצע. החלון ייסגר מעצמו כשהיא תסתיים.'
    }
})

# ============================================================================
#  Go
# ============================================================================

$form.Add_Shown({
    # Started from a hidden background process, the window does not always
    # get the foreground on its own.
    $form.Activate()
    Update-Status
    Write-Log "Csharf $CSHARF_VERSION - מוכן. הרצה כמנהל מערכת אושרה." $C_FG
})
[void]$form.ShowDialog()
$form.Dispose()
try { $script:Mutex.ReleaseMutex() } catch { }

# The extracted copy in %TEMP% has served its purpose. PowerShell has already
# read the whole script into memory, so deleting it here is safe.
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
