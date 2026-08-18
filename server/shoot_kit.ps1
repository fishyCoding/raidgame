# Photographs the kit screen.
#
#   powershell -File server\shoot_kit.ps1
#
# One process now. The screen used to exist only during a match countdown, which
# took a server and a second player to bring up; you kit out before you queue, so
# it is simply the menu.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-kit-shot'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$shot = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--path', $project, '--script', 'res://tools/kit_shot.gd' `
	-RedirectStandardOutput "$out\shot.log" -RedirectStandardError "$out\shot.err"
$null = $shot.Handle
[void]$shot.WaitForExit(120000)

Get-Content "$out\shot.log" -ErrorAction SilentlyContinue | Select-String 'kit_shot'
exit $shot.ExitCode
