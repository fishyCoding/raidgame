# A scope goes up on one machine; the mark has to appear on the other.
#
#   powershell -File server\test_glint.ps1

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-glint-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27786'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27786' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	$clients = @()
	foreach ($n in 1, 2) {
		$c = Start-Process -FilePath $godot -PassThru -NoNewWindow `
			-ArgumentList '--headless', '--path', $project, `
				'--script', 'res://tools/glint_net_test.gd', '--', "--peer=$n", '--port=27786' `
			-RedirectStandardOutput "$out\client$n.log" -RedirectStandardError "$out\client$n.err"
		$null = $c.Handle
		$clients += $c
		Start-Sleep -Seconds 2
	}

	foreach ($c in $clients) { [void]$c.WaitForExit(240000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\client$n.err" -ErrorAction SilentlyContinue |
			Select-String 'SCRIPT ERROR' | Select-Object -First 5
	}

	$failed = 0
	foreach ($c in $clients) { if ($c.ExitCode -ne 0) { $failed++ } }

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - the glint crosses the wire' }
	else { Write-Host "FAIL - $failed client(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
