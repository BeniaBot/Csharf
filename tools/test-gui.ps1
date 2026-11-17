# ============================================================================
#  test-gui.ps1  -  runs the GUI edition's real code under test
#
#  Csharf.bat is one file with the PowerShell half embedded, it elevates
#  itself and it ends in a modal window, so it cannot simply be dot-sourced.
#  This script extracts the embedded half exactly as the batch half does and
#  changes three things, each by an anchored replacement that must match
#  exactly once (the run fails loudly otherwise, so a refactor cannot quietly
#  turn the tests into no-ops):
#
#    1. the elevation check is answered "yes"   (no UAC prompt in a test run)
#    2. the modal ShowDialog is replaced by a hook script, dot-sourced in the
#       product's own scope - it sees every function and control
#    3. optionally the display scale and the working area are pinned, so one
#       machine can render the window as a 100% / 125% / 150% / 175% screen
#       of any size would
#
#  Nothing here ships: the released file is Csharf.bat alone.
#
#  Usage:
#    powershell -File tools\test-gui.ps1 -Hook tools\hooks\layout.ps1 `
#               -OutDir out -Scale 1.5 -WorkArea 1280x672
#
#  ASCII only - Windows PowerShell reads a BOM-less script as ANSI.
# ============================================================================
param(
    [string]$Bat = '',
    [Parameter(Mandatory = $true)][string]$Hook,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [double]$Scale = 0,
    [string]$WorkArea = '',
    [string]$Tag = 'run'
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is not available yet inside a param() default on Windows PowerShell.
if (-not $Bat) { $Bat = Join-Path (Split-Path -Parent $PSScriptRoot) 'Csharf.bat' }
$marker = '#PS' + 'BODY' + '-ST' + 'ART'
$text   = [IO.File]::ReadAllText($Bat, [Text.Encoding]::UTF8)
$i      = $text.LastIndexOf($marker)
if ($i -lt 0) { throw "marker not found in $Bat" }
$body   = $text.Substring($i + $marker.Length)

function Replace-Once {
    param([string]$Source, [string]$Pattern, [string]$With, [string]$What)
    $m = [regex]::Matches($Source, $Pattern)
    if ($m.Count -ne 1) { throw "anchor '$What' matched $($m.Count) times, expected exactly 1" }
    # MatchEvaluator: the replacement is taken literally, "$" and all.
    return [regex]::Replace($Source, $Pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $With })
}

$body = Replace-Once $body 'if \(-not \$isAdmin\) \{' '$isAdmin = $true; if (-not $isAdmin) {' 'elevation check'
# A fatal error must land in the report, not in a message box on the desktop
# of whoever is sitting at the machine while the tests run.
if ($body -match '(?m)^trap \{') {
    $body = Replace-Once $body '(?m)^trap \{' ('trap { [IO.File]::WriteAllText((Join-Path $env:CSHARF_TEST_OUT ("report-" + $env:CSHARF_TEST_TAG + ".txt")), ("TRAP: " + $_.Exception.Message + [Environment]::NewLine + $_.InvocationInfo.PositionMessage + [Environment]::NewLine + $_.ScriptStackTrace)); exit 99 }' + [Environment]::NewLine + 'trap {') 'trap'
}
# Versions before 2.1 have no scale or work-area variables to pin. They are
# DPI-unaware, so Windows simply stretches their 100% window by the scale.
if (-not ($body -match '\$script:UiScale')) { $Scale = 0; $WorkArea = '' }
$body = Replace-Once $body '\[void\]\$form\.ShowDialog\(\)' '. $env:CSHARF_TEST_HOOK' 'ShowDialog'

if ($Scale -gt 0) {
    $s = $Scale.ToString([Globalization.CultureInfo]::InvariantCulture)
    $body = Replace-Once $body '\$script:UiScale = \[double\]\(\$gfx\.DpiX / 96\.0\)' ('$script:UiScale = ' + $s) 'display scale'
}
if ($WorkArea) {
    $wh = $WorkArea.Split('x')
    $body = Replace-Once $body '\$script:WorkArea = \[System\.Windows\.Forms\.Screen\]::FromPoint\([^\r\n]*' `
                         ('$script:WorkArea = New-Object System.Drawing.Rectangle(0, 0, ' + $wh[0] + ', ' + $wh[1] + ')') 'working area'
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$ps1    = Join-Path $OutDir "payload-$Tag.ps1"
[IO.File]::WriteAllText($ps1, $body, (New-Object Text.UTF8Encoding($true)))

$env:CSHARF_TEST_HOOK = (Resolve-Path -LiteralPath $Hook).Path
$env:CSHARF_TEST_OUT  = $OutDir
$env:CSHARF_TEST_TAG  = $Tag
$p = Start-Process -FilePath powershell.exe -Wait -PassThru -NoNewWindow `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $ps1))
# The product deletes its own extracted script on the way out, as it should.
if (Test-Path -LiteralPath $ps1) { Remove-Item -LiteralPath $ps1 -Force }
$report = Join-Path $OutDir "report-$Tag.txt"
if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Encoding UTF8 } else { "NO REPORT (exit $($p.ExitCode)) - the payload died before the hook finished" }
exit $p.ExitCode
