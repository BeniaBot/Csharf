# ============================================================================
#  test-repair.ps1  -  "repair system files" against real damage
#
#  !! DAMAGES WINDOWS ON PURPOSE !!  Run it only inside a disposable virtual
#  machine (restore the snapshot afterwards), as administrator, with no
#  network adapter - the "failed" case is about an offline PC.
#
#  It puts Windows in one of three states and then runs the GUI edition's
#  real action through test-gui.ps1 + hooks\repair.ps1, which checks what the
#  log tells the user:
#    clean     nothing is damaged
#    repaired  System32\calc.exe is damaged, the stored copy in WinSxS is fine
#              (the hard link between them is broken first)
#    failed    the stored copy is damaged too, so SFC cannot repair it and
#              DISM, offline, cannot fetch a clean one
#
#  Each case runs DISM and SFC for real: a few minutes apiece.
#  ASCII only - Windows PowerShell reads a BOM-less script as ANSI.
# ============================================================================
param(
    [Parameter(Mandatory = $true)][ValidateSet('clean', 'repaired', 'failed')][string]$Scenario,
    [string]$OutDir = (Join-Path $env:TEMP 'csharf-repair-test'),
    [switch]$ThisIsADisposableTestMachine
)
$ErrorActionPreference = 'Stop'
if (-not $ThisIsADisposableTestMachine) {
    throw 'This script corrupts a Windows system file on purpose. Run it only in a disposable VM, with -ThisIsADisposableTestMachine.'
}

$sys = Join-Path $env:windir 'System32\calc.exe'

function Open-ForWrite([string]$Path) {
    & takeown.exe /f $Path | Out-Null
    & icacls.exe $Path /grant '*S-1-5-32-544:F' | Out-Null
}
function Get-Damaged([byte[]]$Bytes) {
    for ($i = 0x400; $i -lt 0x440; $i++) { $Bytes[$i] = $Bytes[$i] -bxor 0xFF }
    return ,$Bytes
}

switch ($Scenario) {
    'repaired' {
        Open-ForWrite $sys
        $b = Get-Damaged ([IO.File]::ReadAllBytes($sys))
        Remove-Item -LiteralPath $sys -Force          # only the System32 name of the hard link
        [IO.File]::WriteAllBytes($sys, $b)
    }
    'failed' {
        $good   = (Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash
        $stored = Get-ChildItem (Join-Path $env:windir 'WinSxS\amd64_microsoft-windows-calc_31bf3856ad364e35_*\calc.exe')
        foreach ($s in $stored) {
            Open-ForWrite $s.FullName
            [IO.File]::WriteAllBytes($s.FullName, (Get-Damaged ([IO.File]::ReadAllBytes($s.FullName))))
        }
        # Still hard-linked, the System32 name is damaged by now as well;
        # flipping it a second time would undo the damage.
        if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash -eq $good) {
            Open-ForWrite $sys
            [IO.File]::WriteAllBytes($sys, (Get-Damaged ([IO.File]::ReadAllBytes($sys))))
        }
    }
}

$env:CSHARF_REPAIR_EXPECT = $Scenario
& (Join-Path $PSScriptRoot 'test-gui.ps1') -Hook (Join-Path $PSScriptRoot 'hooks\repair.ps1') -OutDir $OutDir -Tag "repair-$Scenario"
