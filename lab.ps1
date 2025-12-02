Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptsDir = Join-Path $ScriptRoot "scripts"

. (Join-Path $ScriptsDir "lab-certs.ps1")
. (Join-Path $ScriptsDir "lab-docker.ps1")
. (Join-Path $ScriptsDir "lab-sniffer.ps1")

function Pause {
    param(
        [string]$Message = "Nacisnij Enter, aby powrocic do menu..."
    )
    [void](Read-Host $Message)
}

function Write-MenuItem {
    param(
        [string]$Label,
        [string]$Text,
        [bool]$Enabled = $true
    )
    if ($Enabled) {
        Write-Host ("{0} {1}" -f $Label, $Text)
    }
    else {
        Write-Host ("{0} {1}" -f $Label, $Text) -ForegroundColor DarkGray
    }
}

function Invoke-StartLabFull {
    Clear-Host
    Write-Host "== Start lab ==" -ForegroundColor Cyan
    try {
        Write-Host "Generowanie certyfikatow..." -ForegroundColor Yellow
        New-LabCerts

        Write-Host "Uruchamianie kontenerow (docker compose up)..." -ForegroundColor Yellow
        Start-Lab

        Write-Host "Aktualny status kontenerow:" -ForegroundColor Yellow
        Show-LabStatus
    }
    catch {
        Write-Host "Blad podczas uruchamiania labu: $_" -ForegroundColor Red
    }
    Pause
}

function Invoke-ShowBrokerLogsOnce {
    Clear-Host
    Write-Host "== Logi brokera (ostatnie 200 linii) ==" -ForegroundColor Cyan
    try {
        Push-Location $ScriptRoot
        docker logs --tail 200 broker
    }
    catch {
        Write-Host "Blad podczas pobierania logow brokera: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
    Pause
}

function Invoke-ShowBrokerLogsLive {
    Clear-Host
    Write-Host "== Logi brokera na zywo (osobne okno) ==" -ForegroundColor Cyan

    $cmd = "cd '$ScriptRoot'; docker logs -f broker"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd | Out-Null
}

function Invoke-StartSniffer {
    Clear-Host
    Write-Host "== Start sniffera ==" -ForegroundColor Cyan

    $mode = Read-Host "Tryb [plain|tls|mtls|all] (domyslnie: all)"
    if ([string]::IsNullOrWhiteSpace($mode)) {
        $mode = 'all'
    }

    $scenario = Read-Host "Etykieta scenariusza (np. test-plain)"

    $rotateSecRaw = Read-Host "RotateSec - czas rotacji pliku (s, domyslnie: 300)"
    if ([string]::IsNullOrWhiteSpace($rotateSecRaw)) {
        $rotateSec = 300
    }
    else {
        $rotateSec = [int]$rotateSecRaw
    }

    $filesRaw = Read-Host "Files - liczba plikow rotacyjnych (domyslnie: 6)"
    if ([string]::IsNullOrWhiteSpace($filesRaw)) {
        $files = 6
    }
    else {
        $files = [int]$filesRaw
    }

    try {
        Start-LabCapture -Mode $mode -Scenario $scenario -RotateSec $rotateSec -Files $files
    }
    catch {
        Write-Host "Blad podczas uruchamiania sniffera: $_" -ForegroundColor Red
    }

    Pause
}

function Invoke-ShowCaptures {
    Clear-Host
    Write-Host "== Archiwalne pliki pcap ==" -ForegroundColor Cyan
    try {
        $captures = Get-LabCaptures
        if ($captures) {
            $captures | Sort-Object LastWriteTime |
                Format-Table Name, Length, LastWriteTime -AutoSize
        }
        else {
            Write-Host "Brak plikow pcap w katalogu 'pcap'." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Blad podczas pobierania listy plikow pcap: $_" -ForegroundColor Red
    }
    Pause
}

function Write-ManualHelp {
    Write-Host "== Tryb reczny ==" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Sekcja 1. Certyfikaty i lab (docker compose)" -ForegroundColor Green
    Write-Host '  . .\scripts\lab-certs.ps1'
    Write-Host '  . .\scripts\lab-docker.ps1'
    Write-Host '  New-LabCerts'
    Write-Host '  Start-Lab [-NoBuild]'
    Write-Host '  Show-LabStatus'
    Write-Host '  Stop-Lab'
    Write-Host '  Stop-LabContainers'
    Write-Host '  Reset-Lab'
    Write-Host '  Rebuild-Lab'
    Write-Host '  Show-BrokerLogs   # strumieniowe logi brokera (Ctrl+C aby przerwac)'
    Write-Host ""

    Write-Host "Sekcja 2. Sniffer (tcpdump w kontenerze 'sniffer')" -ForegroundColor Green
    Write-Host '  . .\scripts\lab-sniffer.ps1'
    Write-Host '  Start-LabCapture -Mode plain -Scenario "test-plain"'
    Write-Host '  Start-LabCapture -Mode tls   -Scenario "tls-latency" -RotateSec 120 -Files 10'
    Write-Host '  Start-LabCapture -Mode mtls  -Scenario "handshake"'
    Write-Host '  Start-LabCapture -Mode all   -Scenario "test"'
    Write-Host '  Get-LabCaptureStatus'
    Write-Host '  Stop-LabCapture'
    Write-Host '  Get-LabCaptures'
    Write-Host ""

    Write-Host "Sekcja 3. Polecenia przykladowe" -ForegroundColor Green
    Write-Host '  Start-Lab'
    Write-Host '  Show-LabStatus'
    Write-Host '  Start-LabCapture -Mode tls -Scenario "test" -RotateSec 120 -Files 10'
    Write-Host ""
    Write-Host "Pusta linia powoduje powrot do menu." -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-ManualCommand {
    Clear-Host
    Write-ManualHelp

    while ($true) {
        $cmd = Read-Host "lab>"

        if ([string]::IsNullOrWhiteSpace($cmd)) {
            break
        }

        try {
            Invoke-Expression $cmd
        }
        catch {
            Write-Host "Blad podczas wykonywania polecenia: $_" -ForegroundColor Red
        }
    }
}

function Get-SnifferStatusLabel {
    try {
        $status = Get-LabCaptureStatus 2>$null
        $status = ($status | Out-String).Trim()

        if ($status -eq "RUNNING") {
            return "aktywny"
        }
        else {
            return "nieaktywny"
        }
    }
    catch {
        return "nieaktywny"
    }
}

while ($true) {
    $dockerStatus  = Get-LabDockerStatus
    $snifferStatus = Get-SnifferStatusLabel

    $dockerColor = switch ($dockerStatus) {
        'up'      { 'Green' }
        'stopped' { 'Yellow' }
        'down'    { 'DarkGray' }
        'off'     { 'Red' }
        default   { 'DarkGray' }
    }

    $dockerIsOff = $dockerStatus -eq 'off'

    $snifferColor = if ($dockerIsOff) {
        'DarkGray'
    }
    elseif ($snifferStatus -eq 'aktywny') {
        'Green'
    }
    else {
        'DarkGray'
    }

    $canStartLab       = -not $dockerIsOff -and $dockerStatus -in @('down', 'stopped')
    $canStopLab        = -not $dockerIsOff -and $dockerStatus -in @('up', 'stopped')
    $canStopContainers = -not $dockerIsOff -and $dockerStatus -eq 'up'
    $canResetLab       = -not $dockerIsOff
    $canRebuildLab     = -not $dockerIsOff
    $canShowStatus     = -not $dockerIsOff
    $canShowLogs       = -not $dockerIsOff -and $dockerStatus -in @('up', 'stopped')
    $canShowLiveLogs   = $canShowLogs

    $canStartSniffer   = (-not $dockerIsOff) -and ($dockerStatus -eq 'up') -and ($snifferStatus -ne 'aktywny')
    $canStopSniffer    = (-not $dockerIsOff) -and ($snifferStatus -eq 'aktywny')

    Clear-Host
    Write-Host "=== Mini-lab IoT - menu ===" -ForegroundColor Green
    Write-Host ""

    Write-Host "---- Docker ---- [" -NoNewline
    Write-Host ($dockerStatus.ToUpper()) -ForegroundColor $dockerColor -NoNewline
    Write-Host "]"

    Write-MenuItem "[1]" "Start lab (New-LabCerts + Start-Lab + status)"              $canStartLab
    Write-MenuItem "[2]" "Stop lab (docker compose down)"                              $canStopLab
    Write-MenuItem "[S]" "Zatrzymaj kontenery (docker compose stop - bez usuwania)"    $canStopContainers
    Write-MenuItem "[3]" "Reset lab (down -v + czyszczenie pcap)"                      $canResetLab
    Write-MenuItem "[4]" "Rebuild lab (docker compose build --no-cache)"               $canRebuildLab
    Write-MenuItem "[5]" "Pokaz status kontenerow"                                     $canShowStatus
    Write-MenuItem "[6]" "Logi brokera (snapshot, 200 linii)"                          $canShowLogs
    Write-MenuItem "[L]" "Logi brokera na zywo (osobne okno)"                          $canShowLiveLogs
    Write-Host ""

    Write-Host "---- Sniffer ---- [" -NoNewline
    Write-Host $snifferStatus -ForegroundColor $snifferColor -NoNewline
    Write-Host "]"

    if (-not $dockerIsOff -and $snifferStatus -eq 'aktywny') {
        $info = Get-LabCaptureDetails
        if ($info) {
            $modeText = if ($info.Mode)      { $info.Mode }      else { "-" }
            $scText   = if ($info.Scenario)  { $info.Scenario }  else { "-" }
            $rText    = if ($info.RotateSec) { $info.RotateSec } else { "?" }
            $wText    = if ($info.Files)     { $info.Files }     else { "?" }

            Write-Host ("  (profil: {0}, scenariusz: {1}, R={2}s, W={3})" -f `
                $modeText, $scText, $rText, $wText) -ForegroundColor Yellow
        }
    }


    Write-MenuItem "[7]" "Start sniffera (wybor trybu, scenariusza, RotateSec, Files)" $canStartSniffer
    Write-MenuItem "[8]" "Stop sniffera"                                               $canStopSniffer
    Write-MenuItem "[9]" "Lista plikow pcap"                                           $true
    Write-Host ""
    Write-Host "---- Inne ----"
    Write-MenuItem "[M]" "Tryb reczny - pomoc + wprowadzanie polecen" $true
    Write-MenuItem "[Q]" "Wyjscie" $true
    Write-Host ""

    $choice = Read-Host "Wybierz opcje"

    switch ($choice.ToUpper()) {
        '1' {
            if (-not $canStartLab) {
                Clear-Host
                Write-Host "== Start lab ==" -ForegroundColor Cyan
                Write-Host "Operacja niedostepna w aktualnym stanie (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Invoke-StartLabFull
            }
        }
        '2' {
            if (-not $canStopLab) {
                Clear-Host
                Write-Host "== Stop lab ==" -ForegroundColor Cyan
                Write-Host "Operacja 'docker compose down' jest niedostepna w aktualnym stanie (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Stop lab ==" -ForegroundColor Cyan
                try {
                    Stop-Lab
                }
                catch {
                    Write-Host "Blad podczas zatrzymywania labu: $_" -ForegroundColor Red
                }
                Pause
            }
        }
        'S' {
            if (-not $canStopContainers) {
                Clear-Host
                Write-Host "== Zatrzymanie kontenerow ==" -ForegroundColor Cyan
                Write-Host "Brak uruchomionych kontenerow. 'docker compose stop' jest niedostepne w aktualnym stanie." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Zatrzymanie kontenerow (docker compose stop) ==" -ForegroundColor Cyan
                try {
                    Stop-LabContainers
                }
                catch {
                    Write-Host "Blad podczas zatrzymywania kontenerow: $_" -ForegroundColor Red
                }
                Pause
            }
        }
        '3' {
            if (-not $canResetLab) {
                Clear-Host
                Write-Host "== Reset lab ==" -ForegroundColor Cyan
                Write-Host "Reset lab wymaga dostepnego Dockera (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Reset lab ==" -ForegroundColor Cyan
                try {
                    Reset-Lab
                }
                catch {
                    Write-Host "Blad podczas resetowania labu: $_" -ForegroundColor Red
                }
                Pause
            }
        }
        '4' {
            if (-not $canRebuildLab) {
                Clear-Host
                Write-Host "== Rebuild lab ==" -ForegroundColor Cyan
                Write-Host "Rebuild lab wymaga dostepnego Dockera (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Rebuild lab ==" -ForegroundColor Cyan
                try {
                    Rebuild-Lab
                }
                catch {
                    Write-Host "Blad podczas przebudowy labu: $_" -ForegroundColor Red
                }
                Pause
            }
        }
        '5' {
            if (-not $canShowStatus) {
                Clear-Host
                Write-Host "== Status kontenerow ==" -ForegroundColor Cyan
                Write-Host "Nie mozna pobrac statusu kontenerow - Docker jest w stanie OFF." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Status kontenerow ==" -ForegroundColor Cyan
                Show-LabStatus
                Pause
            }
        }
        '6' {
            if (-not $canShowLogs) {
                Clear-Host
                Write-Host "== Logi brokera (snapshot) ==" -ForegroundColor Cyan
                Write-Host "Brak logow brokera w aktualnym stanie (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Invoke-ShowBrokerLogsOnce
            }
        }
        'L' {
            if (-not $canShowLiveLogs) {
                Clear-Host
                Write-Host "== Logi brokera na zywo ==" -ForegroundColor Cyan
                Write-Host "Nie mozna uruchomic logow na zywo - broker nie jest dostepny (status Docker: $dockerStatus)." -ForegroundColor Yellow
                Pause
            }
            else {
                Invoke-ShowBrokerLogsLive
            }
        }
        '7' {
            if (-not $canStartSniffer) {
                Clear-Host
                Write-Host "== Start sniffera ==" -ForegroundColor Cyan
                Write-Host "Start sniffera jest niedostepny w aktualnym stanie." -ForegroundColor Yellow
                Write-Host "Wymagany stan: Docker=UP, sniffer=nieaktywny." -ForegroundColor Yellow
                Write-Host "Aktualny stan: Docker=$dockerStatus, sniffer=$snifferStatus." -ForegroundColor Yellow
                Pause
            }
            else {
                Invoke-StartSniffer
            }
        }
        '8' {
            if (-not $canStopSniffer) {
                Clear-Host
                Write-Host "== Stop sniffera ==" -ForegroundColor Cyan
                Write-Host "Zatrzymanie sniffera jest niedostepne w aktualnym stanie." -ForegroundColor Yellow
                Write-Host "Wymagany stan: Docker!=OFF, sniffer=aktywny." -ForegroundColor Yellow
                Write-Host "Aktualny stan: Docker=$dockerStatus, sniffer=$snifferStatus." -ForegroundColor Yellow
                Pause
            }
            else {
                Clear-Host
                Write-Host "== Stop sniffera ==" -ForegroundColor Cyan
                try {
                    Stop-LabCapture
                }
                catch {
                    Write-Host "Blad podczas zatrzymywania sniffera: $_" -ForegroundColor Red
                }
                Pause
            }
        }
        '9' {
            Invoke-ShowCaptures
        }
        'M' {
            Invoke-ManualCommand
        }
        'Q' {
            return
        }
        default {
            Write-Host "Nieznana opcja. Wybierz pozycje z listy." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
