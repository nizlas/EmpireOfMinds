# Cloud 0.1 authority smoke verification (dev convenience).
# Prerequisite: FastAPI app already running (e.g. uvicorn on port 8000).
# Usage from server/: .\scripts\smoke_cloud_01.ps1 [-BaseUrl "http://localhost:8000"]

param(
    [string] $BaseUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"
$Failed = $false

function Write-Pass([string] $Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Write-Fail([string] $Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:Failed = $true
}

$BaseUrl = $BaseUrl.TrimEnd("/")

Write-Host "Cloud 0.1 smoke - BaseUrl=$BaseUrl" -ForegroundColor Cyan

# 1) healthz
try {
    $hz = Invoke-RestMethod -Uri "$BaseUrl/v1/healthz" -Method Get
    if ($hz.ok -eq $true) {
        Write-Pass "GET /v1/healthz -> ok=true"
    }
    else {
        Write-Fail "GET /v1/healthz: expected ok=true, got $($hz | ConvertTo-Json -Compress)"
    }
}
catch {
    Write-Fail "GET /v1/healthz: $($_.Exception.Message)"
}

if ($Failed) {
    exit 1
}

# 2) create match
$matchId = $null
try {
    # Literal empty JSON object (avoid PS 5.1 oddities with @{} | ConvertTo-Json)
    $createBody = "{}"
    $created = Invoke-RestMethod -Uri "$BaseUrl/v1/matches" -Method Post -Body $createBody -ContentType "application/json"
    $matchId = $created.match_id
    if ($matchId) {
        Write-Pass "POST /v1/matches -> match_id=$matchId"
        Write-Host ('       match_id (for inspection): {0}' -f $matchId) -ForegroundColor Yellow
    }
    else {
        Write-Fail "POST /v1/matches: missing match_id"
    }
}
catch {
    Write-Fail "POST /v1/matches: $($_.Exception.Message)"
}

if ($Failed -or -not $matchId) {
    exit 1
}

# 3) P0 end_turn - accepted, revision 1, current_index 1
try {
    $a0 = @{ schema_version = 1; action_type = "end_turn"; actor_id = 0 } | ConvertTo-Json -Compress
    $r1 = Invoke-RestMethod -Uri "$BaseUrl/v1/matches/$matchId/actions" -Method Post -Body $a0 -ContentType "application/json"
    if (
        $r1.accepted -eq $true -and
        $r1.revision -eq 1 -and
        $r1.snapshot.turn_state.current_index -eq 1
    ) {
        Write-Pass "P0 end_turn -> accepted, revision=1, current_index=1"
    }
    else {
        Write-Fail "P0 end_turn: expected accepted=true, revision=1, current_index=1; got $($r1 | ConvertTo-Json -Compress -Depth 6)"
    }
}
catch {
    Write-Fail "P0 end_turn: $($_.Exception.Message)"
}

if ($Failed) {
    exit 1
}

# 4) P0 again - not_current_player
try {
    $a0b = @{ schema_version = 1; action_type = "end_turn"; actor_id = 0 } | ConvertTo-Json -Compress
    $r1b = Invoke-RestMethod -Uri "$BaseUrl/v1/matches/$matchId/actions" -Method Post -Body $a0b -ContentType "application/json"
    if (
        $r1b.accepted -eq $false -and
        $r1b.reason -eq "not_current_player" -and
        $r1b.index -eq -1
    ) {
        Write-Pass "Repeated P0 end_turn -> not_current_player"
    }
    else {
        Write-Fail "Repeated P0: expected accepted=false, reason=not_current_player; got $($r1b | ConvertTo-Json -Compress -Depth 6)"
    }
}
catch {
    Write-Fail "Repeated P0 end_turn: $($_.Exception.Message)"
}

if ($Failed) {
    exit 1
}

# 5) P1 end_turn - accepted, revision 2, current_index 0, turn_number 2
try {
    $a1 = @{ schema_version = 1; action_type = "end_turn"; actor_id = 1 } | ConvertTo-Json -Compress
    $r2 = Invoke-RestMethod -Uri "$BaseUrl/v1/matches/$matchId/actions" -Method Post -Body $a1 -ContentType "application/json"
    if (
        $r2.accepted -eq $true -and
        $r2.revision -eq 2 -and
        $r2.snapshot.turn_state.current_index -eq 0 -and
        $r2.snapshot.turn_state.turn_number -eq 2
    ) {
        Write-Pass "P1 end_turn -> accepted, revision=2, wrap to P0, turn_number=2"
    }
    else {
        Write-Fail "P1 end_turn: expected accepted, rev=2, current_index=0, turn_number=2; got $($r2 | ConvertTo-Json -Compress -Depth 6)"
    }
}
catch {
    Write-Fail "P1 end_turn: $($_.Exception.Message)"
}

if ($Failed) {
    exit 1
}

# 6) events - exactly two accepted rows
try {
    $ev = Invoke-RestMethod -Uri "$BaseUrl/v1/matches/$matchId/events" -Method Get
    $allEvA = @($ev.events)
    $count = $allEvA.Count
    if ($count -eq 2) {
        Write-Pass "GET /v1/matches/{id}/events -> 2 events"
    }
    else {
        Write-Fail "Events: expected count=2, got count=$count"
    }
}
catch {
    Write-Fail "GET events: $($_.Exception.Message)"
}

if ($Failed) {
    exit 1
}

# 7) since=0 - exactly one event, index 1
try {
    $tail = Invoke-RestMethod -Uri "$BaseUrl/v1/matches/$matchId/events?since=0" -Method Get
    $tailA = @($tail.events)
    $tc = $tailA.Count
    $okSince = ($tc -eq 1) -and ($tailA[0].index -eq 1)
    if ($okSince) {
        Write-Pass "GET events?since=0 -> 1 event with index=1"
    }
    else {
        Write-Fail "events?since=0: expected 1 event index=1; got count=$tc $( $tailA | ConvertTo-Json -Compress -Depth 4 )"
    }
}
catch {
    Write-Fail "GET events?since=0: $($_.Exception.Message)"
}

if ($Failed) {
    Write-Host "Smoke finished with failures." -ForegroundColor Red
    exit 1
}

Write-Host "Smoke finished: all checks passed." -ForegroundColor Green
exit 0