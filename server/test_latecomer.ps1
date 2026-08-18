# A raid with somebody arriving halfway through it and somebody leaving in the
# middle of a search.
#
#   powershell -File server\test_latecomer.ps1
#
# Two clients start together and the match goes live. One of them kills a guard,
# goes through the body, takes what fits, and pulls the cable out with the screen
# still open. A third client is started half a minute in - long after all of that
# - and has to be told about the body anyway, with what is actually left on it.
#
# The two cross-machine checks neither client can make on its own:
#   * what the watcher sees on the body matches what the killer left, not what
#     the guard died carrying (loot that walked out of the raid is gone)
#   * what the latecomer sees matches the watcher, item for item

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-latecomer-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Start-Client($role) {
	$p = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/latecomer_test.gd', '--', "--role=$role", '--port=27781' `
		-RedirectStandardOutput "$out\$role.log" -RedirectStandardError "$out\$role.err"
	$null = $p.Handle
	return $p
}

# One tagged line out of a client's log, with the tag stripped off.
function Get-Line($role, $what) {
	$line = Get-Content "$out\$role.log" -ErrorAction SilentlyContinue |
		Select-String "\| $what " | Select-Object -First 1
	if ($line) { return ($line.ToString() -replace "^.*\| $what ", '') }
	return '<none>'
}

Write-Host '== starting server on 27781'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27781' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	Write-Host '== killer and watcher (two players - the match starts)'
	$killer = Start-Client 'killer'
	$watcher = Start-Client 'watcher'

	# Long enough for the countdown to run out, a guard to be shot dead, the body
	# to be searched, and the killer to disappear with what it took.
	Start-Sleep -Seconds 45
	Write-Host '== latecomer (arrives to a raid already under way)'
	$late = Start-Client 'latecomer'

	[void]$killer.WaitForExit(180000)
	[void]$late.WaitForExit(180000)
	[void]$watcher.WaitForExit(180000)

	foreach ($n in 'killer', 'watcher', 'latecomer') {
		Write-Host ''
		Write-Host "== $n"
		Get-Content "$out\$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
	}
	Write-Host ''
	Write-Host '== server'
	Get-Content "$out\server.log" -ErrorAction SilentlyContinue | Select-String 'server\]'

	$failed = 0
	foreach ($c in $killer, $watcher, $late) { if ($c.ExitCode -ne 0) { $failed++ } }

	$before = Get-Line 'killer' 'before'
	$left = Get-Line 'killer' 'left'
	$watched = Get-Line 'watcher' 'bodies'
	$arrived = Get-Line 'latecomer' 'bodies'

	Write-Host ''
	# A search that moved nothing would make every check below pass for the wrong
	# reason, so it is the first thing asserted.
	# Non-empty as well as changed: what has to survive the disconnect is a body
	# one item short of what he died with, not one that was simply cleared out.
	if ($before -ne '<none>' -and $left -ne $before -and $left -ne '' -and $left -ne '<none>') {
		Write-Host "== the killer took something off the body and left the rest"
		Write-Host "   before: $before"
		Write-Host "   left:   $left"
	} else {
		Write-Host '== NOTHING WAS TAKEN - the rest of this test proves nothing'
		Write-Host "   before: $before"
		Write-Host "   left:   $left"
		$failed++
	}

	# The duplication check. The killer left with the kit on its own machine; if
	# the body still has it too, it exists twice.
	# Contains, not -like: the manifest is bracketed and [] is a wildcard class.
	if ($watched -ne '<none>' -and $watched.Contains("[$left]")) {
		Write-Host '== and what it took is gone from the body for everybody else'
	} else {
		Write-Host '== LOOT WAS DUPLICATED - the body reverted when the killer left'
		Write-Host "   killer left:  $left"
		Write-Host "   watcher sees: $watched"
		$failed++
	}

	if ($arrived -ne '<none>' -and $arrived -eq $watched) {
		Write-Host '== and the latecomer walked into the same raid:'
		Write-Host "   $arrived"
	} else {
		Write-Host '== THE LATECOMER SEES A DIFFERENT WORLD'
		Write-Host "   watcher:   $watched"
		Write-Host "   latecomer: $arrived"
		$failed++
	}

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - the body outlived the search and the session' }
	else { Write-Host "FAIL - $failed check(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
