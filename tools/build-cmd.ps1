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
      No glyph mirroring: reversing already puts "(" at the right-hand end,
      which is where an opening bracket belongs in RTL.
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
            [void]$out.Append($rc[$i]); $i++
        }
    }
    # Escape "!": the script runs under enabledelayedexpansion, where cmd eats
    # a bare "!" as a variable delimiter. It takes TWO carets - verified by
    # experiment; a single "^!" also prints nothing.
    return $out.ToString().Replace('!', '^^!')
}

if ($args -contains '-Test') {
    foreach ($t in @('תפריט','שדרוג גרסה מ-Home ל-Pro','השבתת מצב תרדמה - פינוי מקום','בחר אפשרות (1-9): ')) {
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

$GH = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GB = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GU = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

A '@echo off'
A 'rem ==========================================================================='
A 'rem  Csharf 1.0 - console edition. Pure cmd, no PowerShell anywhere.'
A 'rem'
A 'rem  GENERATED by tools/build-cmd.ps1 - edit that, not this file.'
A 'rem  Code page 862, Hebrew stored in visual order. See the generator header.'
A 'rem ==========================================================================='
A 'setlocal enabledelayedexpansion'
A 'chcp 862 >nul'
A 'color 0A'
A 'title Csharf'
A ''
A 'rem ---------------------------------------------- elevation (BatchGotAdmin) --'
A 'rem Kept as in the original scripts, which worked.'
A 'rem'
A 'rem %~s0 - the SHORT 8.3 path - is load-bearing, not a style choice. %~f0'
A 'rem carries the real folder name, and for a file sitting in something like'
A 'rem C:\Users\<hebrew>\Downloads this batch would write those letters into the'
A 'rem .vbs as CP862 bytes while cscript reads the file back in the system ANSI'
A 'rem code page. The path arrives corrupted, the elevated cmd cannot find the'
A 'rem script, and the window shuts the moment it opens. %~s0 is always ASCII.'
A 'IF "%PROCESSOR_ARCHITECTURE%" EQU "amd64" ('
A '>nul 2>&1 "%SYSTEMROOT%\SysWOW64\icacls.exe" "%SYSTEMROOT%\SysWOW64\config\system"'
A ') ELSE ('
A '>nul 2>&1 "%SYSTEMROOT%\system32\icacls.exe" "%SYSTEMROOT%\system32\config\system"'
A ')'
A 'if %errorlevel% EQU 0 goto :gotAdmin'
A 'if /i "%~1"=="/elevated" goto :noAdmin'
A 'echo.'
A 'echo   Requesting administrative privileges . . .'
A 'echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"'
A 'rem Exactly two quotes around the path: VBS folds each "" into one literal'
A 'rem quote. Four would emit  /c ""C:\...bat""  which cmd cannot parse.'
A 'echo UAC.ShellExecute "cmd.exe", "/c ""%~s0"" /elevated", "", "runas", 1 >> "%temp%\getadmin.vbs"'
A 'cscript //nologo "%temp%\getadmin.vbs" >nul 2>&1'
A 'del "%temp%\getadmin.vbs" >nul 2>&1'
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
A ('set "currentStatus=' + (Vis 'רגיל').PadLeft(6) + '"')
A 'for /f "tokens=1-9" %%a in (''powercfg /getactivescheme'') do ('
A '  for %%t in (%%a %%b %%c %%d %%e %%f %%g %%h %%i) do call :SETSTATE %%t'
A ')'
A ('powercfg /getactivescheme | findstr /I "Ultimate" >nul && set "currentStatus=' + (Vis 'אולטרא').PadLeft(6) + '"')
Top
Centre (Vis 'תפריט')
Mid
# 6 + 6 (currentStatus is padded to 6) + 1 + 23 + 6 = 42 at runtime
Row ('      %currentStatus% ' + (Vis 'כרגע נמצא במצב ביצועים:') + '      ') $W 42
Mid
Item '1' 'מעבר למצב ביצועים גבוהים'
Item '2' 'מעבר למצב ביצועים אולטרא'
Item '3' 'חזרה למצב ביצועים מאוזן'
Item '4' 'פינוי שטח וניקוי יסודי'
Item '5' 'השבתת מצב תרדמה - פינוי מקום'
Item '6' 'הפעלת מצב תרדמה מחדש'
Item '7' 'צור קיצור לתוכנות על שולחן עבודה'
Item '8' 'שדרוג גרסה מ-Home ל-Pro'
Item '9' '--- יציאה ---'
Bot
EB
A ('choice /C 123456789 /N /M "' + (Vis 'בחר אפשרות (1-9): ') + '"')
A 'if errorlevel 9 goto :EXITAPP'
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
A ("if /i `"%~1`"==`"$GH`" set `"currentStatus=" + (Vis 'גבוהים').PadLeft(6) + "`"")
A ("if /i `"%~1`"==`"$GB`" set `"currentStatus=" + (Vis 'מאוזן').PadLeft(6) + "`"")
A 'goto :eof'
A ''

# --- 1 ----------------------------------------------------------------------
A ':HIGHPERF'
A 'cls'
EB
Rule
E 'מעבר למצב ביצועים גבוהים...'
A ("powercfg -duplicatescheme $GH >nul 2>&1")
A ("powercfg /setactive $GH")
E 'מצב ביצועים גבוהים הופעל בהצלחה.'
A 'goto :END'
A ''

# --- 2 ----------------------------------------------------------------------
A ':ULTRAPERF'
A 'cls'
EB
Rule
E 'מתבצע עקיפה - מעבר למצב ביצועים אולטרא...'
A 'rem Step 1: the official scheme.'
A ("powercfg -duplicatescheme $GU >nul 2>&1")
A ("powercfg /setactive $GU >nul 2>&1")
A 'rem Step 2: if it is hidden on this edition, clone High Performance and'
A 'rem push it to ultimate settings.'
A ("powercfg /getactivescheme | findstr /I `"$GU`" >nul")
A 'if not errorlevel 1 goto :ULT_DONE'
A 'set "NEWG="'
A ("for /f `"tokens=1-9`" %%a in ('powercfg -duplicatescheme $GH') do (")
A '  for %%t in (%%a %%b %%c %%d %%e %%f %%g %%h %%i) do call :PICKGUID %%t'
A ')'
A 'if not defined NEWG goto :ULT_DONE'
A 'powercfg -changename !NEWG! "Ultimate Performance" "Csharf" >nul 2>&1'
A 'powercfg -setacvalueindex !NEWG! SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1'
A 'powercfg -setacvalueindex !NEWG! SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1'
A 'powercfg -setacvalueindex !NEWG! SUB_DISK DISKIDLE 0 >nul 2>&1'
A 'powercfg /setactive !NEWG! >nul 2>&1'
A ':ULT_DONE'
E 'מצב ביצועים אולטרא הופעל בהצלחה.'
A 'goto :END'
A ''
A ':PICKGUID'
A 'echo %~1| findstr /R /C:"^[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*$" >nul'
A 'if errorlevel 1 goto :eof'
A 'set "NEWG=%~1"'
A 'goto :eof'
A ''

# --- 3 ----------------------------------------------------------------------
A ':RESTORE_BALANCED'
A 'cls'
EB
Rule
E 'החזרת המערכת למצב מאוזן...'
A ("powercfg /setactive $GB >nul 2>&1")
A 'for /f "tokens=1-9" %%a in (''powercfg /list ^| findstr /I "Ultimate Csharf"'') do ('
A '  for %%t in (%%a %%b %%c %%d %%e %%f %%g %%h %%i) do call :DELSCHEME %%t'
A ')'
E 'בוטל "אולטרא" והמערכת חזרה למצב מאוזן בהצלחה.'
A 'goto :END'
A ''
A 'rem Deletes a scheme only when the token really is a GUID and is not one of'
A 'rem the built-in three.'
A ':DELSCHEME'
A 'echo %~1| findstr /R /C:"^[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*-[0-9a-fA-F][0-9a-fA-F]*$" >nul'
A 'if errorlevel 1 goto :eof'
A ("if /i `"%~1`"==`"$GB`" goto :eof")
A ("if /i `"%~1`"==`"$GH`" goto :eof")
A ("if /i `"%~1`"==`"$GU`" goto :eof")
A 'powercfg /delete %~1 >nul 2>&1'
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
A ('  <nul set /p "=  ' + (Vis 'לתחילת הניקוי נותרו') + ' %%i   "')
A '  timeout /t 1 >nul'
A '  echo.'
A ')'
EB
Rule
E 'מתבצע פינוי שטח וניקוי המערכת...'
Rule
A 'for %%v in ("Active Setup Temp Folders" "BranchCache" "Downloaded Program Files" "Internet Cache Files" "Memory Dump Files" "Old ChkDsk Files" "Previous Installations" "Recycle Bin" "Service Pack Cleanup" "Setup Log Files" "System error memory dump files" "System error minidump files" "Temporary Files" "Update Cleanup" "Windows Error Reporting Files") do ('
A '  reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\%%~v" /v StateFlags0001 /t REG_DWORD /d 2 /f >nul 2>&1'
A ')'
A 'cleanmgr /sagerun:1 >nul 2>&1'
A 'rem No /resetbase - that permanently blocks uninstalling Windows updates.'
A 'dism /online /cleanup-image /startcomponentcleanup >nul 2>&1'
A 'rem Contents only. Deleting and recreating C:\Windows\Temp wipes its ACLs.'
A 'del /s /f /q "%TEMP%\*.*" >nul 2>&1'
A 'for /d %%d in ("%TEMP%\*") do rd /s /q "%%d" >nul 2>&1'
A 'del /s /f /q "%SystemRoot%\Temp\*.*" >nul 2>&1'
A 'for /d %%d in ("%SystemRoot%\Temp\*") do rd /s /q "%%d" >nul 2>&1'
EB
E 'פינוי שטח וניקוי המערכת בוצע בהצלחה.'
A 'goto :END'
A ''

# --- 5 ----------------------------------------------------------------------
A ':HIBER_OFF'
A 'cls'
EB
Rule
E 'השבתת מצב תרדמה ומחיקת hiberfil.sys...'
A 'powercfg -h off'
E 'מצב תרדמה הושבת והקובץ נמחק.'
A 'goto :END'
A ''

# --- 6 ----------------------------------------------------------------------
A ':HIBER_ON'
A 'cls'
EB
Rule
E 'הפעלת מצב תרדמה...'
A 'powercfg -h on'
E 'מצב תרדמה הופעל בהצלחה'
A 'goto :END'
A ''

# --- 7 ----------------------------------------------------------------------
A ':CREATE_SHORTCUT'
A 'cls'
EB
Rule
E 'צור קיצור לרשימת התוכנות...'
A 'set "vbsFile=%temp%\create_shortcut.vbs"'
A '> "%vbsFile%" echo Set WshShell = WScript.CreateObject^("WScript.Shell"^)'
A '>> "%vbsFile%" echo desktopPath = WshShell.SpecialFolders^("Desktop"^)'
A '>> "%vbsFile%" echo shortcutPath = desktopPath ^& "\" ^& ChrW^(1514^) ^& ChrW^(1493^) ^& ChrW^(1499^) ^& ChrW^(1504^) ^& ChrW^(1493^) ^& ChrW^(1514^) ^& ".lnk"'
A '>> "%vbsFile%" echo Set shortcut = WshShell.CreateShortcut^(shortcutPath^)'
A '>> "%vbsFile%" echo shortcut.TargetPath = "C:\Windows\explorer.exe"'
A '>> "%vbsFile%" echo shortcut.Arguments = "shell:appsfolder"'
A '>> "%vbsFile%" echo shortcut.IconLocation = "C:\Windows\system32\imageres.dll,3"'
A '>> "%vbsFile%" echo shortcut.Save'
A 'cscript //nologo "%vbsFile%" >nul'
A 'del "%vbsFile%"'
E 'הקיצור נוצר בהצלחה.'
A 'goto :END'
A ''

# --- 8 ----------------------------------------------------------------------
A ':UPGRADE_PRO'
A 'cls'
EB
Rule
E 'בדיקה אם נדרשת המרת מהדורה ל-Pro...'
A 'set "Edition="'
A 'for /f "tokens=2*" %%a in (''reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID'') do set "Edition=%%b"'
A ('echo      ' + (Vis 'מהדורה נוכחית:') + ' !Edition!')
EB
A 'echo !Edition!| findstr /I /B "Professional" >nul'
A 'if not errorlevel 1 ('
E '  מערכת ההפעלה כבר גרסת Pro.'
A '  goto :END'
A ')'
A 'if not exist "%SystemRoot%\System32\changepk.exe" ('
E '  changepk.exe לא נמצא. שינוי מהדורה אינו נתמך במערכת הזו.'
A '  goto :END'
A ')'
Rule
E 'מתבצע שדרוג אוטומטי לגרסת Windows Pro'
E 'שים לב: זהו שינוי מהדורה בלבד, לא הפעלת רישיון.'
Rule
EB
E 'אנא המתן... פעולה זו עשויה להימשך מספר דקות.'
A 'timeout /t 5 >nul'
A 'rem The errorlevel test follows changepk immediately on purpose: a timeout'
A 'rem in between resets it, which is how later builds always reported success.'
A 'changepk.exe /productkey VK7JG-NPHTM-C97JM-9MPGT-3V66T'
A 'if not "%errorlevel%"=="0" ('
EB
E '  אירעה שגיאה במהלך ניסיון השדרוג.'
E '  בדוק חיבור לאינטרנט והרצה כמנהל מערכת.'
A '  timeout /t 10 >nul'
A '  goto :END'
A ')'
EB
Rule
E 'השדרוג לגרסת Pro הושלם בהצלחה!'
E 'המחשב יופעל מחדש תוך 10 שניות.'
E 'להקפאת האתחול - הקש על מקש X כעת.'
Rule
EB
A 'for /l %%i in (10,-1,1) do ('
A '  choice /c XC /n /t 1 /d C >nul'
A '  if not errorlevel 2 ('
EB
E '    ביטול האתחול לפי בקשת המשתמש.'
A '    timeout /t 2 >nul'
A '    goto :END'
A '  )'
A ('  echo  ' + (Vis 'נותרו') + ' %%i ' + (Vis 'שניות עד להפעלה מחדש... הקש X לביטול'))
A ')'
A 'shutdown /r /t 5'
A 'exit /b'
A ''

# --- END / EXIT -------------------------------------------------------------
A ':END'
EB
Top $W2
Centre (Vis 'הפעולה בוצעה בהצלחה. V') $W2
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
