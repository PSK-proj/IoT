$LabRoot = Split-Path $PSScriptRoot -Parent

function Start-LabCapture {
    param(
        [ValidateSet('plain','tls','mtls','all')]
        [string]$Mode = 'all',
        [string]$Scenario = '',
        [ValidateRange(5, 86400)]
        [int]$RotateSec = 300,
        [ValidateRange(1, 100)]
        [int]$Files = 6
    )

    Push-Location $LabRoot
    try {
        & docker compose up -d sniffer | Out-Null

        switch ($Mode) {
            'plain' {
                $filter = 'tcp port 1883'
                $label  = 'plain'
            }
            'tls' {
                $filter = 'tcp port 8883'
                $label  = 'tls'
            }
            'mtls' {
                $filter = 'tcp port 8884'
                $label  = 'mtls'
            }
            'all' {
                $filter = 'tcp port 1883 or tcp port 8883 or tcp port 8884'
                $label  = 'all'
            }
        }

        if ([string]::IsNullOrWhiteSpace($Scenario)) {
            $scenarioSegment = ''
        }
        else {
            $scenarioSegment = [regex]::Replace($Scenario.Trim(), '[^A-Za-z0-9_-]', '-')
        }

        if ($scenarioSegment) {
            $nameBase = "$label" + "_" + "$scenarioSegment"
        }
        else {
            $nameBase = $label
        }

        if (-not (Test-Path -LiteralPath "$LabRoot\pcap")) {
            New-Item -ItemType Directory -Path "$LabRoot\pcap" -Force | Out-Null
        }

        $ts = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
        $filename = "${nameBase}_${ts}.pcapng"

        $script = "pgrep -f 'tcpdump -i any -s 0 -U -w /pcap/' >/dev/null 2>&1 && pkill tcpdump >/dev/null 2>&1 || true; tcpdump -i any -s 0 -U -w /pcap/$filename -G $RotateSec -W $Files $filter >/pcap/tcpdump.log 2>&1 & echo started"

        & docker compose exec -T sniffer sh -lc "$script"
        if ($LASTEXITCODE -ne 0) {
            throw "Uruchomienie tcpdump w kontenerze 'sniffer' zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Stop-LabCapture {
    Push-Location $LabRoot
    try {
        $script = "pgrep -f 'tcpdump -i any -s 0 -U -w /pcap/' >/dev/null 2>&1 && pkill -INT tcpdump >/dev/null 2>&1 || true; sleep 1; ls -lh /pcap 2>/dev/null || ls -l /pcap 2>/dev/null || true"
        & docker compose exec -T sniffer sh -lc "$script"
    }
    finally {
        Pop-Location
    }
}

function Get-LabCaptureStatus {
    Push-Location $LabRoot
    try {
        $output = & docker top sniffer 2>$null

        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return 'STOPPED'
        }

        $match = $output | Select-String -SimpleMatch 'tcpdump'

        if ($match) {
            return 'RUNNING'
        }
        else {
            return 'STOPPED'
        }
    }
    catch {
        return 'STOPPED'
    }
    finally {
        Pop-Location
    }
}

function Get-LabCaptureDetails {
    Push-Location $LabRoot
    try {
        $output = & docker top sniffer 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return $null
        }

        $match = $output | Select-String -SimpleMatch 'tcpdump' | Select-Object -First 1
        if (-not $match) {
            return $null
        }

        $line = $match.Line
        $cmdIndex = $line.IndexOf('tcpdump ')
        if ($cmdIndex -lt 0) {
            return $null
        }

        $cmd = $line.Substring($cmdIndex + 'tcpdump '.Length)

        $filename = $null
        if ($cmd -match '-w\s+/pcap/(\S+)') {
            $filename = $matches[1]
        }

        $rotate = $null
        if ($cmd -match '-G\s+(\d+)') {
            $rotate = [int]$matches[1]
        }

        $files = $null
        if ($cmd -match '-W\s+(\d+)') {
            $files = [int]$matches[1]
        }

        $mode = $null
        $scenario = $null

        if ($filename) {
            $nameOnly = $filename
            $dotIndex = $nameOnly.LastIndexOf('.')
            if ($dotIndex -gt 0) {
                $nameOnly = $nameOnly.Substring(0, $dotIndex)
            }

            $parts = $nameOnly -split '_'

            if ($parts.Length -ge 1) {
                $mode = $parts[0]
            }

            if ($parts.Length -ge 3) {
                if ($parts.Length -gt 2) {
                    $scenario = ($parts[1..($parts.Length - 2)] -join '_')
                }
            }
        }

        [pscustomobject]@{
            Mode      = $mode
            Scenario  = $scenario
            RotateSec = $rotate
            Files     = $files
            Filename  = $filename
            Command   = $cmd
        }
    }
    catch {
        return $null
    }
    finally {
        Pop-Location
    }
}

function Get-LabCaptures {
    Push-Location $LabRoot
    try {
        if (-not (Test-Path -LiteralPath "$LabRoot\pcap")) {
            return
        }
        Get-ChildItem -Path "$LabRoot\pcap" -File |
            Where-Object { $_.Extension -in '.pcap', '.pcapng' } |
            Sort-Object LastWriteTime
    }
    finally {
        Pop-Location
    }
}
