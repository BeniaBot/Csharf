# ============================================================================
#  build-cmd.ps1  -  generates Csharf-CMD.bat
#
#  Layout and wording follow the original hand-written scripts as closely as
#  the encoding allows. Edit THIS file, never the generated .bat.
#
#  The console applies no bidi: it draws characters left to right in stored
#  order, so Hebrew has to be stored in VISUAL order. Hand-reversing is what
#  corrupted strings in the older versions, so everything below is written in
#  normal logical Hebrew and converted mechanically.
#
#  Output is code page 862 (Hebrew OEM). Beyond glyphs that matters because
#  cmd.exe tracks a byte offset into the .bat while decoding it: multi-byte
#  UTF-8 desyncs that offset until cmd executes the middle of lines as
#  commands. In CP862 every Hebrew letter is one byte.
#
#  CP862 carries the full box-drawing set, so the original frame survives.
#  It has no emoji, so the decorative ones are dropped and the tick becomes V.
# ============================================================================

function ConvertTo-VisualHebrew {
    <#
      Reduced UAX#9, base direction RTL:
        1. classify  R (Hebrew) / L (Latin, digits) / N (rest)
        2. resolve N by nearest strong neighbours - L only when both sides are
           L, otherwise the RTL base
        3. reverse the line, then reverse the LTR runs back
        4. mirror the brackets that ended up in RTL: reversing moves the "("
           of "(1-9)" to the right-hand end, where it has to be drawn as ")"
           - the glyph swap a real bidi renderer does. Up to 1.0 this step
           was missing and the menu prompt read ")1-9(". Brackets inside a
           Latin run are left alone.
    #>
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $ch  = $Text.ToCharArray()
    $cls = New-Object 'char[]' $ch.Length
    for ($i = 0; $i -lt $ch.Length; $i++) {
        $c = [int]$ch[$i]
        if     ($c -ge 0x0590 -and $c -le 0x05FF) { $cls[$i] = 'R' }
        elseif ([char]::IsLetterOrDigit($ch[$i])) { $cls[$i] = 'L' }
        else                                      { $cls[$i] = 'N' }
    }
    for ($i = 0; $i -lt $ch.Length; $i++) {
        if ($cls[$i] -ne 'N') { continue }
        $l = 'R'; $r = 'R'
        for ($j = $i - 1; $j -ge 0;          $j--) { if ($cls[$j] -ne 'N') { $l = $cls[$j]; break } }
        for ($j = $i + 1; $j -lt $ch.Length; $j++) { if ($cls[$j] -ne 'N') { $r = $cls[$j]; break } }
        if ($l -eq 'L' -and $r -eq 'L') { $cls[$i] = 'L' } else { $cls[$i] = 'R' }
    }

    $rc = $ch[($ch.Length - 1)..0]
    $rl = $cls[($cls.Length - 1)..0]
    $out = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $rc.Length) {
        if ($rl[$i] -eq 'L') {
            $s = $i
            while ($i -lt $rc.Length -and $rl[$i] -eq 'L') { $i++ }
            for ($j = $i - 1; $j -ge $s; $j--) { [void]$out.Append($rc[$j]) }
        } else {
            $c = $rc[$i]
            switch ($c) {
                '(' { $c = ')' } ')' { $c = '(' }
                '[' { $c = ']' } ']' { $c = '[' }
                '{' { $c = '}' } '}' { $c = '{' }
                '<' { $c = '>' } '>' { $c = '<' }
            }
            [void]$out.Append($c); $i++
        }
    }
    # Escape "!": the script runs under enabledelayedexpansion, where cmd eats
    # a bare "!" as a variable delimiter. It takes TWO carets - verified by
    # experiment; a single "^!" also prints nothing.
    return $out.ToString().Replace('!', '^^!')
}

if ($args -contains '-Test') {
    foreach ($t in @('תפריט','שדרוג מהדורה מ-Home ל-Pro','השבתת מצב תרדמה - פינוי מקום','בחר אפשרות (0-9): ','תפריט ההקשר (Windows 11)')) {
        '{0,-34} ->  {1}' -f $t, (ConvertTo-VisualHebrew $t)
    }
    return
}

# ============================================================================
#  Emit
# ============================================================================

$L = New-Object System.Collections.Generic.List[string]

function A {
    # Extra positional args mean an unparenthesised concatenation at the call
    # site: PowerShell binds only the first piece and silently drops the rest,
    # writing a truncated batch line. Fail loudly instead.
    param([string]$s, [Parameter(ValueFromRemainingArguments = $true)]$rest)
    if ($rest) { throw "A(): unparenthesised concatenation, dropped: $rest" }
    $L.Add($s)
}
function Vis { param([string]$s) return (ConvertTo-VisualHebrew $s) }
# A Hebrew sentence with a runtime value (%%i, !VAR!) in the middle. The value
# cannot go through Vis - reversing would mangle the variable - so the two
# halves are converted apart and placed in visual order: the part that comes
# LATER in the sentence sits on the LEFT. 1.0 glued them the other way round,
# so its countdowns read "seconds until restart ... 10 left".
function VisWith { param([string]$before, [string]$value, [string]$after)
    return ((Vis $after) + ' ' + $value + ' ' + (Vis $before)).Trim()
}
function E { param([string]$s) A ('echo  ' + (Vis $s)) }      # plain Hebrew line
function EB { A 'echo.' }

# ---- the frame from the original scripts -----------------------------------
$W  = 42            # inner width of the main menu box
$W2 = 36            # inner width of the closing boxes

function Top  { param([int]$w = $W) A ('echo ' + [char]0x2554 + ([string][char]0x2550) * $w + [char]0x2557) }
function Mid  { param([int]$w = $W) A ('echo ' + [char]0x2560 + ([string][char]0x2550) * $w + [char]0x2563) }
function Bot  { param([int]$w = $W) A ('echo ' + [char]0x255A + ([string][char]0x2550) * $w + [char]0x255D) }
# Width as the console will actually draw it: both carets of an escaped "!"
# are consumed by cmd and occupy no column.
function Shown { param([string]$s) return $s.Replace('^^!', '!').Length }

function Row  {
    param([string]$inner, [int]$w = $W, [int]$expandsTo = -1)
    # $expandsTo: runtime width of an embedded %VAR%, which is shorter than the
    # literal "%currentStatus%" measured here. Without it the row is padded
    # against the wrong length and the text gets cut off at the frame.
    $len = Shown $inner
    if ($expandsTo -ge 0) { $len = $expandsTo }
    if ($len -gt $w) { $inner = $inner.Substring(0, $w); $len = $w }
    A ('echo ' + [char]0x2551 + $inner + (' ' * ($w - $len)) + [char]0x2551)
}
function Centre { param([string]$vis, [int]$w = $W)
    $pad = [Math]::Max(0, [int](($w - (Shown $vis)) / 2))
    Row ((' ' * $pad) + $vis) $w
}
# "  [N]" on the left, Hebrew right-aligned in the remaining field, exactly as
# the original laid it out - only with the column arithmetic done properly, so
# the right edge no longer drifts line to line.
function Item { param([string]$n, [string]$text)
    Row ('  [' + $n + ']' + (Vis $text).PadLeft($W - 8) + '   ')
}
function Rule { A ('echo ' + ([string][char]0x2550) * 43) }

$VERSION = '2.3'
$GH = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GB = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GU = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$GS = 'a1841308-3541-4fab-bc81-f71556f20b4a'
# This tool's own two plans, with FIXED ids - the same ones the GUI edition
# uses. `powercfg -duplicatescheme` without a destination invents a new id on
# every call, and 1.0 called it on every press: one more plan per click.
$CSU = 'c54a2f10-7e1b-4d6a-9b3e-5c0a1e2f0001'
$CSH = 'c54a2f10-7e1b-4d6a-9b3e-5c0a1e2f0002'
$PSR = 'HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'

A '@echo off'
A 'rem ==========================================================================='
A "rem  Csharf $VERSION - console edition. Plain cmd; PowerShell only as a fallback"
A 'rem  for the elevation prompt on a Windows without VBScript.'
A 'rem'
A 'rem  GENERATED by tools/build-cmd.ps1 - edit that, not this file.'
A 'rem  Code page 862, Hebrew stored in visual order. See the generator header.'
A 'rem ==========================================================================='
A 'setlocal enabledelayedexpansion'
A 'chcp 862 >nul'
A 'color 0A'
A "title Csharf $VERSION"
A ''
A 'rem ---------------------------------------------- elevation (BatchGotAdmin) --'
A 'rem The path of this file travels to the elevated copy as a command-line'
A 'rem ARGUMENT, never as text written into the .vbs. Written into the file, the'
A 'rem letters of a folder such as D:\<hebrew> are stored as CP862 bytes and read'
A 'rem back by cscript in the ANSI code page: the elevated cmd gets a corrupted'
A 'rem path and the window closes the moment it opens. 1.0 relied on the 8.3'
A 'rem short name to dodge this, but drives other than C: usually have short'
A 'rem names switched off, and then there is none. An argument stays Unicode.'
A 'rem Second stage: the window exists, so the temporary font key (see below)'
A 'rem has done its job. Removed first thing - whether this copy got admin rights'
A 'rem or not - and only when it carries our mark.'
A 'if /i "%~1"=="/elevated" reg query "HKCU\Console\%%SystemRoot%%_System32_conhost.exe" /v CsharfTemporary >nul 2>&1 && reg delete "HKCU\Console\%%SystemRoot%%_System32_conhost.exe" /f >nul 2>&1'
A 'IF "%PROCESSOR_ARCHITECTURE%" EQU "amd64" ('
A '>nul 2>&1 "%SYSTEMROOT%\SysWOW64\icacls.exe" "%SYSTEMROOT%\SysWOW64\config\system"'
A ') ELSE ('
A '>nul 2>&1 "%SYSTEMROOT%\system32\icacls.exe" "%SYSTEMROOT%\system32\config\system"'
A ')'
A 'if %errorlevel% EQU 0 goto :gotAdmin'
A 'if /i "%~1"=="/elevated" goto :noAdmin'
A 'echo.'
A 'echo   Requesting administrative privileges . . .'
A 'set "CSHARF_SELF=%~f0"'
A 'rem The elevated copy runs in a classic console window. Its usual font,'
A 'rem Consolas, has no Hebrew letters; Windows borrows narrower ones from another'
A 'rem font and every word shows gaps. So the window is opened through'
A 'rem conhost.exe directly: such a console reads its settings from a registry'
A 'rem key of its own, which nothing else normally uses. That key is given a font'
A 'rem with real Hebrew letters (Courier New) for the moment the window is'
A 'rem created, marked CsharfTemporary, and the elevated copy removes it again'
A 'rem (see :gotAdmin). A key somebody made themselves is never touched.'
A 'set "CSHARF_CONKEY=HKCU\Console\%%SystemRoot%%_System32_conhost.exe"'
A 'set "CSHARF_OWN=0"'
A 'reg query "%CSHARF_CONKEY%" >nul 2>&1 || set "CSHARF_OWN=1"'
A 'reg query "%CSHARF_CONKEY%" /v CsharfTemporary >nul 2>&1 && set "CSHARF_OWN=1"'
A 'if "%CSHARF_OWN%"=="1" ('
A '  reg add "%CSHARF_CONKEY%" /v FaceName /t REG_SZ /d "Courier New" /f >nul 2>&1'
A '  reg add "%CSHARF_CONKEY%" /v FontFamily /t REG_DWORD /d 0x36 /f >nul 2>&1'
A '  reg add "%CSHARF_CONKEY%" /v FontWeight /t REG_DWORD /d 700 /f >nul 2>&1'
A '  reg add "%CSHARF_CONKEY%" /v FontSize /t REG_DWORD /d 0x00120000 /f >nul 2>&1'
A '  reg add "%CSHARF_CONKEY%" /v CsharfTemporary /t REG_DWORD /d 1 /f >nul 2>&1'
A ')'
A 'rem The second stage starts as   cmd.exe /c call "<path>" /elevated'
A 'rem After /c the line does not begin with a quote, so cmd strips none and the'
A 'rem path survives spaces, ( ) and & alike. (The older  /c ""<path>" ..."  form'
A 'rem cannot be used here: conhost splits its command line into arguments and'
A 'rem joins them again, quoting each one that holds a space and turning inner'
A 'rem quotes into \" - which cmd does not understand.) One case conhost cannot'
A 'rem carry: a path with an & but no space is passed on unquoted. That rare'
A 'rem path goes the plain cmd.exe way, without the font, which passes the line'
A 'rem untouched.'
A 'rem conhost.exe is 64-bit only; a 32-bit cmd sees SysWOW64 as System32.'
A 'set "CSHARF_HOST=%SystemRoot%\System32\conhost.exe"'
A 'if exist "%SystemRoot%\Sysnative\conhost.exe" set "CSHARF_HOST=%SystemRoot%\Sysnative\conhost.exe"'
A 'if not exist "%CSHARF_HOST%" set "CSHARF_HOST=cmd.exe"'
A 'if "!CSHARF_SELF: =!"=="!CSHARF_SELF!" if not "!CSHARF_SELF:&=!"=="!CSHARF_SELF!" set "CSHARF_HOST=cmd.exe"'
A 'set "CSHARF_PRE=cmd.exe /c call"'
A 'if /i "%CSHARF_HOST%"=="cmd.exe" set "CSHARF_PRE=/c call"'
A 'echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"'
A 'echo UAC.ShellExecute WScript.Arguments^(1^), WScript.Arguments^(2^) ^& " """ ^& WScript.Arguments^(0^) ^& """ /elevated", "", "runas", 1 >> "%temp%\getadmin.vbs"'
A 'cscript //nologo "%temp%\getadmin.vbs" "%~f0" "%CSHARF_HOST%" "%CSHARF_PRE%" >nul 2>&1'
A 'set "CSHARF_VBS=%errorlevel%"'
A 'del "%temp%\getadmin.vbs" >nul 2>&1'
A 'if "%CSHARF_VBS%"=="0" exit /B'
A 'rem No VBScript on this Windows (Microsoft is phasing it out). Same request'
A 'rem through PowerShell; [char]34 is a quote, which spares a layer of escaping.'
A 'powershell -NoProfile -Command "try { $q=[char]34; Start-Process -FilePath $env:CSHARF_HOST -Verb RunAs -ErrorAction Stop -ArgumentList ($env:CSHARF_PRE + '' '' + $q + $env:CSHARF_SELF + $q + '' /elevated'') } catch { exit 1 }" >nul 2>&1'
A 'if errorlevel 1 goto :noAdmin'
A 'exit /B'
A ''
A ':noAdmin'
A 'cls'
EB
E 'הכלי דורש הרשאות מנהל.'
E 'לחץ ימני על הקובץ ובחר "הפעל כמנהל".'
EB
A 'pause >nul'
A 'exit /B 1'
A ''
A ':gotAdmin'
A 'pushd "%CD%"'
A 'CD /D "%~dp0"'
A ''

# ---------------------------------------------------------------- menu ------
A ':MENU'
A 'cls'
EB
A 'rem Status is padded to a fixed width so the box edge cannot drift.'
A ('set "currentStatus=' + (Vis 'רגיל').PadLeft(11) + '"')
A 'for /f "tokens=1-9" %%a in (''powercfg /getactivescheme'') do ('
A '  for %%t in (%%a %%b %%c %%d %%e %%f %%g %%h %%i) do call :SETSTATE %%t'
A ')'
A ('powercfg /getactivescheme | findstr /I "Ultimate" >nul && set "currentStatus=' + (Vis 'אולטימטיביים').PadLeft(11) + '"')
Top
Centre (Vis 'תפריט')
Mid
# 3 + 11 (currentStatus is padded to 11) + 1 + 23 + 4 = 42 at runtime
Row ('   %currentStatus% ' + (Vis 'כרגע נמצא במצב ביצועים:') + '    ') $W 42
Mid
Item '1' 'מעבר למצב ביצועים גבוהים'
Item '2' 'מעבר למצב ביצועים אולטימטיביים'
Item '3' 'חזרה למצב ביצועים מאוזן'
Item '4' 'פינוי שטח וניקוי מערכת יסודי'
Item '5' 'השבתת מצב תרדמה - פינוי מקום'
Item '6' 'הפעלת מצב תרדמה מחדש'
Item '7' 'קיצור לרשימת כל התוכנות'
Item '8' 'שדרוג מהדורה מ-Home ל-Pro'
Item '9' 'יצירת נקודת שחזור'
Item '0' '--- יציאה ---'
Bot
EB
A ('choice /C 1234567890 /N /M "' + (Vis 'בחר אפשרות (0-9): ') + '"')
A 'rem The 0 key is the tenth choice, so errorlevel 10.'
A 'if errorlevel 10 goto :EXITAPP'
A 'if errorlevel 9 goto :RESTORE_POINT'
A 'if errorlevel 8 goto :UPGRADE_PRO'
A 'if errorlevel 7 goto :CREATE_SHORTCUT'
A 'if errorlevel 6 goto :HIBER_ON'
A 'if errorlevel 5 goto :HIBER_OFF'
A 'if errorlevel 4 goto :DISK_CLEANUP'
A 'if errorlevel 3 goto :RESTORE_BALANCED'
A 'if errorlevel 2 goto :ULTRAPERF'
A 'goto :HIGHPERF'
A ''
A 'rem Matches the active scheme by GUID rather than by token position, which'
A 'rem is locale-dependent - powercfg words its output differently per language.'
A ':SETSTATE'
A ("if /i `"%~1`"==`"$GH`" set `"currentStatus=" + (Vis 'גבוהים').PadLeft(11) + "`"")
A ("if /i `"%~1`"==`"$CSH`" set `"currentStatus=" + (Vis 'גבוהים').PadLeft(11) + "`"")
A ("if /i `"%~1`"==`"$GB`" set `"currentStatus=" + (Vis 'מאוזן').PadLeft(11) + "`"")
A ("if /i `"%~1`"==`"$CSU`" set `"currentStatus=" + (Vis 'אולטימטיביים').PadLeft(11) + "`"")
A 'goto :eof'
A ''
A 'rem errorlevel 0 when the plan given is the active one.'
A ':ISACTIVE'
A 'powercfg /getactivescheme | findstr /I /C:"%~1" >nul'
A 'exit /b %errorlevel%'
A ''
A 'rem errorlevel 0 when a plan with this id exists. Read from the registry:'
A 'rem powercfg /list hides most plans on Modern Standby laptops.'
A ':HASPLAN'
A ("reg query `"$PSR\%~1`" >nul 2>&1")
A 'exit /b %errorlevel%'
A ''

# --- 1 ----------------------------------------------------------------------
A ':HIGHPERF'
A 'cls'
EB
Rule
E 'מעבר למצב ביצועים גבוהים...'
A ("powercfg /setactive $GH >nul 2>&1")
A ("call :ISACTIVE $GH && goto :END_OK")
A 'rem Refused here (Modern Standby laptops, trimmed OEM images): use this'
A 'rem tool''s own copy instead, made once and then only switched back on.'
A ("call :HASPLAN $CSH || powercfg -duplicatescheme $GH $CSH >nul 2>&1")
A ("call :HASPLAN $CSH || powercfg -duplicatescheme $GB $CSH >nul 2>&1")
A ("call :HASPLAN $CSH || goto :END_FAIL")
A ("powercfg -changename $CSH `"High Performance (Csharf)`" `"Csharf`" >nul 2>&1")
A ("powercfg -setacvalueindex $CSH SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1")
A ("powercfg /setactive $CSH >nul 2>&1")
A ("call :ISACTIVE $CSH && goto :END_OK")
A 'goto :END_FAIL'
A ''

# --- 2 ----------------------------------------------------------------------
A ':ULTRAPERF'
A 'cls'
EB
Rule
E 'מעבר למצב ביצועים אולטימטיביים...'
A 'rem A copy made earlier is simply switched back on - never a second one.'
A ("call :HASPLAN $CSU && powercfg /setactive $CSU >nul 2>&1")
A ("call :ISACTIVE $CSU && goto :END_OK")
A ("call :HASPLAN $CSU && powercfg /delete $CSU >nul 2>&1")
A 'rem Step 1: the official plan. Windows keeps it as a hidden template, and'
A 'rem copying it is the documented way to turn it on. (1.0 made the copy and'
A 'rem then tried to switch on the template itself, which never works.)'
A ("powercfg -duplicatescheme $GU $CSU >nul 2>&1")
A ("call :HASPLAN $CSU && goto :ULT_NAME")
A 'rem Step 2: blocked on this PC. Build an equivalent from High Performance,'
A 'rem or from Balanced where even that is missing.'
E 'התוכנית הרשמית חסומה במחשב הזה - בונה תוכנית מקבילה...'
A ("powercfg -duplicatescheme $GH $CSU >nul 2>&1")
A ("call :HASPLAN $CSU || powercfg -duplicatescheme $GB $CSU >nul 2>&1")
A ("call :HASPLAN $CSU || goto :END_FAIL")
A 'rem Full speed on mains power only (setacvalueindex); on battery the plan'
A 'rem keeps the values of the plan it was copied from.'
A ("powercfg -setacvalueindex $CSU SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1")
A ("powercfg -setacvalueindex $CSU SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1")
A ("powercfg -setacvalueindex $CSU SUB_DISK DISKIDLE 0 >nul 2>&1")
A ("powercfg -setacvalueindex $CSU SUB_SLEEP STANDBYIDLE 0 >nul 2>&1")
A ':ULT_NAME'
A ("powercfg -changename $CSU `"Ultimate Performance (Csharf)`" `"Csharf`" >nul 2>&1")
A 'rem Processor idle states stay on: a CPU that never rests runs hot and leaves'
A 'rem no thermal room for turbo. (The GUI''s first 2.1 build switched them off.)'
A ("powercfg -setacvalueindex $CSU SUB_PROCESSOR IDLEDISABLE 0 >nul 2>&1")
A ("powercfg -setdcvalueindex $CSU SUB_PROCESSOR IDLEDISABLE 0 >nul 2>&1")
A ("powercfg /setactive $CSU >nul 2>&1")
A ("call :ISACTIVE $CSU && goto :END_OK")
A 'goto :END_FAIL'
A ''

# --- 3 ----------------------------------------------------------------------
A ':RESTORE_BALANCED'
A 'cls'
EB
Rule
E 'החזרת המערכת למצב מאוזן...'
A ("powercfg /setactive $GB >nul 2>&1")
A ("call :ISACTIVE $GB || goto :END_FAIL")
A 'rem Then clear away the plans older versions left behind (see :MAYBE_DEL).'
A 'set "REMOVED=0"'
A ("for /f `"delims=`" %%k in ('reg query `"$PSR`" 2^>nul') do call :MAYBE_DEL `"%%~nxk`"")
A ('if !REMOVED! GTR 0 echo  ' + (VisWith 'נוקו' '!REMOVED!' 'תוכניות חשמל כפולות שנשארו מהפעלות קודמות.'))
A 'goto :END_OK'
A ''
A 'rem Removes a plan only when it is clearly a leftover of this tool: its own'
A 'rem fixed ids, anything named or described "Csharf", and nameless copies of'
A 'rem the stock High Performance / Ultimate plans - what -duplicatescheme'
A 'rem without a destination leaves, on every click in 1.0.'
A 'rem Never a built-in plan, never the active one, never one somebody named.'
A ':MAYBE_DEL'
A 'set "G=%~1"'
A 'echo %G%| findstr /R /I /X /C:"[0-9a-f][0-9a-f]*-[0-9a-f][0-9a-f]*-[0-9a-f][0-9a-f]*-[0-9a-f][0-9a-f]*-[0-9a-f][0-9a-f]*" >nul || goto :eof'
A ("for %%b in ($GB $GH $GU $GS) do if /i `"%G%`"==`"%%b`" goto :eof")
A 'call :ISACTIVE %G% && goto :eof'
A ("reg query `"$PSR\%G%`" /v FriendlyName 2>nul | findstr /I /C:`"Csharf`" /C:`"powrprof.dll,-13,High performance`" >nul && goto :DEL_PLAN")
A ("reg query `"$PSR\%G%`" /v Description 2>nul | findstr /I /C:`"Csharf`" >nul && goto :DEL_PLAN")
A ("reg query `"$PSR\%G%`" /v FriendlyName 2>nul | findstr /I /R /C:`"powrprof\.dll,-[0-9]*,Ultimate Performance`" >nul && goto :DEL_PLAN")
A 'goto :eof'
A ':DEL_PLAN'
A 'powercfg /delete %G% >nul 2>&1'
A 'call :HASPLAN %G% || set /a REMOVED+=1'
A 'goto :eof'
A ''

# --- 4 ----------------------------------------------------------------------
A ':DISK_CLEANUP'
A 'cls'
EB
Rule
# plain centred text, not a boxed row: the lines around it are bare rules
A ('echo ' + (' ' * [int]((43 - (Vis 'אזהרה חשובה').Length) / 2)) + (Vis 'אזהרה חשובה'))
Rule
EB
E 'תהליך זה ימחק קבצים זמניים, ירוקן את סל המיחזור ועוד.'
E 'לביטול יש לסגור את התוכנה - ללחוץ על X.'
EB
A 'for /l %%i in (6,-1,1) do ('
A ('  <nul set /p "=  %%i ' + (Vis 'לתחילת הניקוי נותרו') + '   "')
A '  timeout /t 1 >nul'
A '  echo.'
A ')'
A 'rem The previous Windows installation gets a question of its own: removing'
A 'rem it frees a lot of space, but it is the only way back after an upgrade.'
A 'set "DROP_OLD=0"'
A 'if not exist "%SystemDrive%\Windows.old\" goto :CLEAN_GO'
EB
E 'נמצאה במחשב התקנה קודמת של Windows - התיקייה Windows.old.'
E 'מחיקתה מפנה הרבה מקום, אבל אחריה אי אפשר לחזור לגרסה הקודמת.'
A ('choice /C 12 /N /M "' + (Vis 'למחוק גם אותה? 1 = כן, 2 = לא: ') + '"')
A 'if not errorlevel 2 set "DROP_OLD=1"'
A ':CLEAN_GO'
EB
Rule
E 'מתבצע פינוי שטח וניקוי המערכת...'
Rule
A 'rem Preset 1 is shared with every earlier run, and 1.0 also ticked'
A 'rem "Previous Installations". Clear the whole preset, then set this list.'
A 'for /f "delims=" %%k in (''reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches" 2^>nul'') do reg delete "%%k" /v StateFlags0001 /f >nul 2>&1'
A 'for %%v in ("Active Setup Temp Folders" "BranchCache" "Downloaded Program Files" "Internet Cache Files" "Memory Dump Files" "Old ChkDsk Files" "Recycle Bin" "Service Pack Cleanup" "Setup Log Files" "System error memory dump files" "System error minidump files" "Temporary Files" "Update Cleanup" "Windows Error Reporting Files") do ('
A '  reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\%%~v" /v StateFlags0001 /t REG_DWORD /d 2 /f >nul 2>&1'
A ')'
A 'if "%DROP_OLD%"=="1" reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations" /v StateFlags0001 /t REG_DWORD /d 2 /f >nul 2>&1'
A 'cleanmgr /sagerun:1 >nul 2>&1'
A 'rem No /resetbase - that permanently blocks uninstalling Windows updates.'
A 'dism /online /cleanup-image /startcomponentcleanup >nul 2>&1'
A 'call :CLEAN_DIR "%TEMP%"'
A 'call :CLEAN_DIR "%SystemRoot%\Temp"'
EB
E 'פינוי שטח וניקוי המערכת בוצע בהצלחה.'
A 'goto :END_OK'
A ''
A 'rem Empties a temp folder, contents only - deleting and recreating'
A 'rem C:\Windows\Temp wipes its ACLs. Refuses anything that is not a full'
A 'rem path below a drive root: with an empty or odd variable, "del /s \*.*"'
A 'rem would be the whole drive.'
A ':CLEAN_DIR'
A 'set "CD_T=%~1"'
A 'if not defined CD_T goto :eof'
A 'if not "!CD_T:~1,2!"==":\" goto :eof'
A 'if "!CD_T:~3!"=="" goto :eof'
A 'if not exist "!CD_T!\" goto :eof'
A 'del /s /f /q "!CD_T!\*.*" >nul 2>&1'
A 'for /d %%d in ("!CD_T!\*") do rd /s /q "%%d" >nul 2>&1'
A 'goto :eof'
A ''

# --- 5 ----------------------------------------------------------------------
A ':HIBER_OFF'
A 'cls'
EB
Rule
E 'השבתת מצב תרדמה ומחיקת hiberfil.sys...'
A 'powercfg -h off >nul 2>&1'
A 'reg query "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v HibernateEnabled 2>nul | findstr /I /C:"0x0" >nul && goto :END_OK'
A 'goto :END_FAIL'
A ''

# --- 6 ----------------------------------------------------------------------
A ':HIBER_ON'
A 'cls'
EB
Rule
E 'הפעלת מצב תרדמה...'
A 'powercfg -h on >nul 2>&1'
A 'reg query "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v HibernateEnabled 2>nul | findstr /I /C:"0x1" >nul && goto :END_OK'
E 'ייתכן שהחומרה של המחשב הזה אינה תומכת במצב תרדמה.'
A 'goto :END_FAIL'
A ''

# --- 7 ----------------------------------------------------------------------
A ':CREATE_SHORTCUT'
A 'cls'
EB
Rule
E 'יוצר קיצור לרשימת כל התוכנות...'
A 'set "vbsFile=%temp%\create_shortcut.vbs"'
A '> "%vbsFile%" echo Set WshShell = WScript.CreateObject^("WScript.Shell"^)'
A '>> "%vbsFile%" echo desktopPath = WshShell.SpecialFolders^("Desktop"^)'
A '>> "%vbsFile%" echo shortcutPath = desktopPath ^& "\" ^& ChrW^(1514^) ^& ChrW^(1493^) ^& ChrW^(1499^) ^& ChrW^(1504^) ^& ChrW^(1493^) ^& ChrW^(1514^) ^& ".lnk"'
A '>> "%vbsFile%" echo Set shortcut = WshShell.CreateShortcut^(shortcutPath^)'
A '>> "%vbsFile%" echo shortcut.TargetPath = "C:\Windows\explorer.exe"'
A '>> "%vbsFile%" echo shortcut.Arguments = "shell:appsfolder"'
A '>> "%vbsFile%" echo shortcut.IconLocation = "C:\Windows\system32\imageres.dll,3"'
A '>> "%vbsFile%" echo shortcut.Save'
A 'rem The script reports whether the file really exists now - 1.0 announced'
A 'rem success whatever happened.'
A '>> "%vbsFile%" echo If CreateObject^("Scripting.FileSystemObject"^).FileExists^(shortcutPath^) Then WScript.Quit 0 Else WScript.Quit 1'
A 'cscript //nologo "%vbsFile%" >nul 2>&1'
A 'set "SC_RC=%errorlevel%"'
A 'del "%vbsFile%" >nul 2>&1'
A 'if "%SC_RC%"=="0" goto :END_OK'
A 'goto :END_FAIL'
A ''

# --- 8 ----------------------------------------------------------------------
A ':UPGRADE_PRO'
A 'cls'
EB
Rule
E 'בדיקה אם נדרשת המרת מהדורה ל-Pro...'
A 'set "Edition="'
A 'for /f "tokens=2*" %%a in (''reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID'') do set "Edition=%%b"'
A ('echo      !Edition! ' + (Vis 'מהדורה נוכחית:'))
EB
A 'echo !Edition!| findstr /I /B "Professional" >nul && goto :PRO_ALREADY'
A 'rem The generic key moves Home to Pro and nothing else. On Education or'
A 'rem Enterprise it would be a step down.'
A 'echo !Edition!| findstr /I /B "Core" >nul || goto :PRO_NOT_HOME'
A 'rem A 32-bit cmd sees SysWOW64 as System32, and changepk is 64-bit only.'
A 'set "CPK=%SystemRoot%\System32\changepk.exe"'
A 'if exist "%SystemRoot%\Sysnative\changepk.exe" set "CPK=%SystemRoot%\Sysnative\changepk.exe"'
A 'if not exist "%CPK%" goto :PRO_NO_TOOL'
Rule
E 'הפעולה תשנה את מהדורת Windows ל-Pro ותפעיל את המחשב מחדש.'
E 'שמור וסגור את כל המסמכים הפתוחים לפני שתמשיך.'
E 'שים לב: זהו שינוי מהדורה בלבד, לא הפעלת רישיון.'
E 'לאחר ההפעלה מחדש עדיין יידרש רישיון Pro תקף.'
Rule
EB
A 'rem Asked first: 1.0 started straight away, and its key sat next to Exit.'
A ('choice /C 12 /N /M "' + (Vis 'להמשיך? 1 = כן, 2 = לא: ') + '"')
A 'if errorlevel 2 goto :END_CANCEL'
EB
E 'אנא המתן... פעולה זו עשויה להימשך מספר דקות.'
A 'rem The errorlevel test follows changepk immediately on purpose: a timeout'
A 'rem in between resets it, which is how later builds always reported success.'
A '"%CPK%" /productkey VK7JG-NPHTM-C97JM-9MPGT-3V66T'
A 'if not "%errorlevel%"=="0" goto :PRO_FAILED'
EB
Rule
E 'שינוי המהדורה התחיל. נדרשת הפעלה מחדש כדי להשלים אותו.'
E 'המחשב יופעל מחדש תוך 15 שניות.'
E 'לביטול ההפעלה מחדש - הקש 0.'
Rule
EB
A 'rem A digit, not a letter: with the Hebrew keyboard layout active the X key'
A 'rem types a Hebrew letter that "choice /c X" never accepts, so in 1.0 the'
A 'rem countdown could not be cancelled at all in that layout.'
A 'for /l %%i in (15,-1,1) do ('
A ('  echo  ' + (VisWith 'נותרו' '%%i' 'שניות עד להפעלה מחדש... הקש 0 לביטול'))
A '  choice /c 01 /n /t 1 /d 1 >nul'
A '  if not errorlevel 2 goto :PRO_REBOOT_CANCELLED'
A ')'
A 'shutdown /r /t 5'
A 'exit /b'
A ''
A ':PRO_REBOOT_CANCELLED'
EB
E 'ההפעלה מחדש בוטלה. השדרוג יושלם בהפעלה מחדש הבאה.'
A 'goto :END_OK'
A ':PRO_ALREADY'
E 'מערכת ההפעלה כבר במהדורת Pro. אין צורך בשינוי.'
A 'goto :END_NOCHANGE'
A ':PRO_NOT_HOME'
E 'הפעולה מיועדת למהדורת Home בלבד.'
A 'goto :END_NOCHANGE'
A ':PRO_NO_TOOL'
E 'changepk.exe לא נמצא. שינוי מהדורה אינו נתמך במערכת הזו.'
A 'goto :END_FAIL'
A ':PRO_FAILED'
EB
E 'שינוי המהדורה נכשל. בדוק חיבור לאינטרנט ונסה שוב.'
A 'goto :END_FAIL'
A ''

# --- 9 ----------------------------------------------------------------------
A ':RESTORE_POINT'
A 'cls'
EB
Rule
E 'יוצר נקודת שחזור... זה עשוי לקחת דקה.'
Rule
A 'rem Windows silently skips a restore point when one was made in the last'
A 'rem 24 hours. The limit is lifted for this one request and put back exactly'
A 'rem as it was, and the newest point is compared before and after - so the'
A 'rem ending says what really happened.'
A 'set "SRKEY=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"'
A 'set "SRFREQ="'
A 'for /f "tokens=3" %%v in (''reg query "%SRKEY%" /v SystemRestorePointCreationFrequency 2^>nul ^| findstr /I "SystemRestorePointCreationFrequency"'') do set "SRFREQ=%%v"'
A 'reg add "%SRKEY%" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f >nul 2>&1'
A 'rem First PowerShell''s own Checkpoint-Computer - the call the GUI edition'
A 'rem makes, proven to work. The same request sent from VBS was answered'
A 'rem "done" on a Windows 11 test machine without any restore point appearing.'
A 'rem Exit codes: 0 a new point exists, 2 Windows made none, 1 failed.'
A 'rem PowerShell blocked or missing gives anything else - then the VBS way.'
A 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$n = { @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1).SequenceNumber }; $b = & $n; try { Enable-ComputerRestore -Drive ($env:SystemDrive + ''\'') -ErrorAction SilentlyContinue; Checkpoint-Computer -Description ''Csharf'' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue } catch { exit 1 }; $a = & $n; if ($a -and $a -ne $b) { exit 0 } else { exit 2 }" >nul 2>&1'
A 'set "RP_RC=%errorlevel%"'
A 'if "%RP_RC%"=="0" goto :RP_END'
A 'if "%RP_RC%"=="2" goto :RP_END'
A 'set "vbsFile=%temp%\csharf_restore.vbs"'
A '> "%vbsFile%" echo On Error Resume Next'
A '>> "%vbsFile%" echo Set sr = GetObject^("winmgmts:\\.\root\default:SystemRestore"^)'
A '>> "%vbsFile%" echo If Err.Number ^<^> 0 Then WScript.Quit 3'
A '>> "%vbsFile%" echo Set svc = GetObject^("winmgmts:\\.\root\default"^)'
A '>> "%vbsFile%" echo n0 = 0'
A '>> "%vbsFile%" echo For Each p In svc.ExecQuery^("SELECT * FROM SystemRestore"^)'
A '>> "%vbsFile%" echo   If p.SequenceNumber ^> n0 Then n0 = p.SequenceNumber'
A '>> "%vbsFile%" echo Next'
A '>> "%vbsFile%" echo sr.Enable "%SystemDrive%\"'
A '>> "%vbsFile%" echo rc = sr.CreateRestorePoint^("Csharf", 12, 100^)'
A '>> "%vbsFile%" echo If Err.Number ^<^> 0 Then WScript.Quit 1'
A '>> "%vbsFile%" echo n1 = 0'
A '>> "%vbsFile%" echo For Each p In svc.ExecQuery^("SELECT * FROM SystemRestore"^)'
A '>> "%vbsFile%" echo   If p.SequenceNumber ^> n1 Then n1 = p.SequenceNumber'
A '>> "%vbsFile%" echo Next'
A '>> "%vbsFile%" echo If n1 ^> n0 Then WScript.Quit 0'
A '>> "%vbsFile%" echo If rc ^<^> 0 Then WScript.Quit 1'
A '>> "%vbsFile%" echo WScript.Quit 2'
A 'cscript //nologo "%vbsFile%" >nul 2>&1'
A 'set "RP_RC=%errorlevel%"'
A 'del "%vbsFile%" >nul 2>&1'
A ':RP_END'
A 'if defined SRFREQ (reg add "%SRKEY%" /v SystemRestorePointCreationFrequency /t REG_DWORD /d %SRFREQ% /f >nul 2>&1) else reg delete "%SRKEY%" /v SystemRestorePointCreationFrequency /f >nul 2>&1'
A 'if "%RP_RC%"=="0" goto :END_OK'
A 'if "%RP_RC%"=="2" goto :RP_SKIPPED'
EB
E 'שחזור המערכת כבוי, חסום או לא זמין במחשב הזה.'
A 'goto :END_FAIL'
A ':RP_SKIPPED'
EB
E 'Windows לא יצר נקודה חדשה. ייתכן ששחזור המערכת מוגבל במחשב הזה.'
A 'goto :END_FAIL'
A ''

# --- END / EXIT -------------------------------------------------------------
# Every action ends in exactly one of these. 1.0 had a single ending that said
# "done successfully" after failures and cancellations alike.
A ':END_OK'
EB
Top $W2
Centre (Vis 'הפעולה בוצעה בהצלחה. V') $W2
Centre (Vis 'חוזר לתפריט בעוד 3 שניות...') $W2
Bot $W2
A 'timeout /t 3 >nul'
A 'goto :MENU'
A ''
A ':END_FAIL'
A 'color 0C'
EB
Top $W2
Centre (Vis 'הפעולה לא הצליחה. X') $W2
Centre (Vis 'חוזר לתפריט בעוד 5 שניות...') $W2
Bot $W2
A 'timeout /t 5 >nul'
A 'color 0A'
A 'goto :MENU'
A ''
A ':END_CANCEL'
EB
Top $W2
Centre (Vis 'הפעולה בוטלה.') $W2
Centre (Vis 'חוזר לתפריט בעוד 3 שניות...') $W2
Bot $W2
A 'timeout /t 3 >nul'
A 'goto :MENU'
A ''
A ':END_NOCHANGE'
EB
Top $W2
Centre (Vis 'לא בוצע שינוי.') $W2
Centre (Vis 'חוזר לתפריט בעוד 3 שניות...') $W2
Bot $W2
A 'timeout /t 3 >nul'
A 'goto :MENU'
A ''
A ':EXITAPP'
A 'cls'
EB
Top $W2
Centre (Vis 'תודה שהשתמשתם בתוכנה') $W2
Centre (Vis 'יום טוב והמשך מוצלח!') $W2
Bot $W2
A 'timeout /t 2 >nul'
A 'cls'
A 'exit /b 0'

$outPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf-CMD.bat'
$text = ($L -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($outPath, $text, [System.Text.Encoding]::GetEncoding(862))
"wrote $outPath  ($((Get-Item $outPath).Length) bytes, CP862, $($L.Count) lines)"
