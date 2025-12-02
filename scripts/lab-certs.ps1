$LabRoot = Split-Path $PSScriptRoot -Parent

function New-LabCerts {
    param(
        [string[]]$Clients
    )

    Push-Location $LabRoot
    try {
        $args = @(
            "compose",
            "--profile", "tools",
            "-f", "docker-compose.yml",
            "-f", "docker-compose.tools.yml",
            "run",
            "--rm"
        )

        if ($Clients -and $Clients.Count -gt 0) {
            $list = [string]::Join(",", $Clients)
            $args += @("-e", "CLIENT_CN_LIST=$list")
        }

        $args += "certgen"
        & docker @args
        if ($LASTEXITCODE -ne 0) {
            throw "Generowanie certyfikatow (docker compose 'certgen') zakonczylo sie kodem wyjscia $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Clean-LabCerts {
    Push-Location $LabRoot
    try {
        $paths = @(
            "certs\*.crt",
            "certs\*.key",
            "certs\*.srl",
            "certs\openssl.server.cnf",
            "certs\clients\*.crt",
            "certs\clients\*.key"
        )
        foreach ($p in $paths) {
            Remove-Item -Path $p -ErrorAction SilentlyContinue -Force
        }
    }
    finally {
        Pop-Location
    }
}
