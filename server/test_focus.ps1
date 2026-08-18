# Two copies of the game side by side, which is how multiplayer gets tested and
# therefore something that has to work.
#
#   powershell -File server\test_focus.ps1
#
# There is one mouse on the machine. The window being looked at holds it and the
# other one must not - a background instance that keeps the cursor clipped and
# hidden leaves nothing to click the other window with, and a window that cannot
# be focused is never sent a key. It reads as the second copy ignoring the
# keyboard; the mouse is the cause.
#
# Not headless: there are no windows to focus without a display.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-focus-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$procs = @()
foreach ($tag in 'A', 'B') {
	$p = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--path', $project, '--script', 'res://tools/focus_probe.gd', '--', "--tag=$tag" `
		-RedirectStandardOutput "$out\$tag.log" -RedirectStandardError "$out\$tag.err"
	$null = $p.Handle
	$procs += $p
	Start-Sleep -Seconds 4
}

foreach ($p in $procs) { [void]$p.WaitForExit(120000) }

foreach ($tag in 'A', 'B') {
	Get-Content "$out\$tag.log" -ErrorAction SilentlyContinue | Select-String '\|'
}

$failed = 0
foreach ($p in $procs) { if ($p.ExitCode -ne 0) { $failed++ } }

# Which of the two ends up focused is the OS's business - Windows will often
# refuse to hand the foreground to a process that just started - so this asserts
# the invariant rather than which window won: exactly one of them holds the mouse.
$captured = (Get-Content "$out\A.log", "$out\B.log" -ErrorAction SilentlyContinue |
	Select-String 'mouse=CAPTURED').Count

Write-Host ''
if ($captured -eq 1) {
	Write-Host '== exactly one instance is holding the mouse'
} else {
	Write-Host "== WRONG - $captured of 2 instances are holding the mouse"
	$failed++
}

Write-Host ''
if ($failed -eq 0) { Write-Host 'PASS - the mouse follows the focus' }
else { Write-Host "FAIL - $failed check(s) failed" }
exit $failed
