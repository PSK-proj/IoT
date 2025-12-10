$LabRoot = Split-Path $PSScriptRoot -Parent

function Get-LabDockerStatus {
    Push-Location $LabRoot
    try {
        try {
            $output = & docker compose ps --all --format json 2>$null
        }
        catch {
            return "off"
        }

        if ($LASTEXITCODE -ne 0) {
            return "off"
        }

        if (-not $output) {
            return "down"
        }

        try {
            $data = $output | ConvertFrom-Json
        }
        catch {
            $text = & docker compose ps --all 2>$null
            if (-not $text) { return "down" }

            $lines = $text -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch 'NAME\s+COMMAND') }
            if (-not $lines -or $lines.Count -eq 0) { return "down" }

            if ($lines -match 'running|Up') {
                return "up"
            }
            else {
                return "stopped"
            }
        }

        if (-not $data) {
            return "down"
        }

        if ($data -isnot [System.Array]) {
            $data = @($data)
        }

        $running = $data | Where-Object { $_.State -eq "running" -or $_.State -like "running*" }
        if ($running) {
            return "up"
        }

        return "stopped"
    }
    catch {
        return "off"
    }
    finally {
        Pop-Location
    }
}

function Start-Lab {
    param(
        [switch]$NoBuild
    )

    Push-Location $LabRoot
    try {
        $args = @("compose", "up", "-d")
        if (-not $NoBuild) {
            $args += "--build"
        }
        & docker @args
        if ($LASTEXITCODE -ne 0) {
            throw "Polecenie 'docker compose up' zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Stop-Lab {
    Push-Location $LabRoot
    try {
        & docker compose down
        if ($LASTEXITCODE -ne 0) {
            throw "Polecenie 'docker compose down' zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Stop-LabContainers {
    Push-Location $LabRoot
    try {
        & docker compose stop
        if ($LASTEXITCODE -ne 0) {
            throw "Polecenie 'docker compose stop' zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Rebuild-Lab {
    Push-Location $LabRoot
    try {
        & docker compose build --no-cache
        if ($LASTEXITCODE -ne 0) {
            throw "Polecenie 'docker compose build --no-cache' zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Show-LabLogs {
    param(
        [string[]]$Services
    )

    Push-Location $LabRoot
    try {
        $args = @("compose", "logs", "-f", "--tail", "200")
        if ($Services -and $Services.Count -gt 0) {
            $args += $Services
        }
        & docker @args
    }
    finally {
        Pop-Location
    }
}

function Show-LabStatus {
    Push-Location $LabRoot
    try {
        & docker compose ps
    }
    finally {
        Pop-Location
    }
}

function Reset-Lab {
    Push-Location $LabRoot
    try {
        & docker compose down -v
        $paths = @(
            "pcap\*.pcap",
            "pcap\*.pcapng"
        )
        foreach ($p in $paths) {
            Remove-Item -Path $p -ErrorAction SilentlyContinue -Force
        }
    }
    finally {
        Pop-Location
    }
}

function Show-BrokerLogs {
    Push-Location $LabRoot
    try {
        & docker logs -f broker
    }
    finally {
        Pop-Location
    }
}
