# The way in, from the menu: two players kit out, press one button each, and
# end up in the same raid holding what they bought.
#
#   powershell -File server\test_queue.ps1
#
# The second client is started ten seconds late on purpose. The first one has to
# sit there waiting, and that wait is half of what is being tested.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-queue-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27783'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27783' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	Write-Host '== client 1 (alone - should wait)'
	$c1 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/queue_test.gd', '--', '--peer=1', '--port=27783' `
		-RedirectStandardOutput "$out\client1.log" -RedirectStandardError "$out\client1.err"
	$null = $c1.Handle

	Start-Sleep -Seconds 10
	Write-Host '== client 2 (arrives - should start the countdown)'
	$c2 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/queue_test.gd', '--', '--peer=2', '--port=27783' `
		-RedirectStandardOutput "$out\client2.log" -RedirectStandardError "$out\client2.err"
	$null = $c2.Handle

	foreach ($c in $c1, $c2) { [void]$c.WaitForExit(240000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\client$n.err" -ErrorAction SilentlyContinue |
			Select-String 'SCRIPT ERROR|ERROR' | Select-Object -First 5
	}
	Write-Host ''
	Write-Host '== server'
	Get-Content "$out\server.log" -ErrorAction SilentlyContinue | Select-String 'server\]'

	$failed = 0
	foreach ($c in $c1, $c2) { if ($c.ExitCode -ne 0) { $failed++ } }

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - one button, and both of them went in kitted' }
	else { Write-Host "FAIL - $failed client(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
