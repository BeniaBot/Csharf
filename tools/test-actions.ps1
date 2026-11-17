# ============================================================================
#  test-actions.ps1  -  every GUI action, for real, checked for honesty
#
#  !! CHANGES THE MACHINE !!  Power plans, hibernation, Explorer settings,
#  temp files, the recycle bin, reserved storage, the network stack, a
#  restore point. Run it only inside a disposable virtual machine (restore
#  the snapshot afterwards), as administrator.
#
#  Runs the GUI edition's real code through test-gui.ps1 + hooks\actions.ps1:
#  each action is clicked with scripted answers to its questions (reboots are
#  always cancelled), and whatever the log claims is compared with what
#  Windows actually did.
#
#  The report goes OUTSIDE %TEMP% on purpose - the cleanup action empties it.
#  ASCII only - Windows PowerShell reads a BOM-less script as ANSI.
# ============================================================================
param(
    [string]$OutDir = (Join-Path $env:SystemDrive 'csharf-actions-test'),
    [switch]$ThisIsADisposableTestMachine
)
$ErrorActionPreference = 'Stop'
if (-not $ThisIsADisposableTestMachine) {
    throw 'This script changes many Windows settings on purpose. Run it only in a disposable VM, with -ThisIsADisposableTestMachine.'
}
& (Join-Path $PSScriptRoot 'test-gui.ps1') -Hook (Join-Path $PSScriptRoot 'hooks\actions.ps1') -OutDir $OutDir -Tag 'actions'
