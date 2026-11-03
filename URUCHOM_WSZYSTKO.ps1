# URUCHOM_WSZYSTKO.ps1
# Jeden skrypt, ktory robi na serwerze po kolei: test sieci, instalacja n8n, Apache, zapora, sprawdzenie.
# Uruchamiac przez URUCHOM_WSZYSTKO.bat (dwuklik) z folderu n8n-migracja-serwer.
# Plik jest celowo bez polskich znakow (PowerShell 5.1 bez BOM).

param(
    [string]$PublicUrl = 'http://192.168.27.202',
    [string]$ApacheRoot = '',
    [string]$ZakresSieci = '192.168.27.0/24'
)

$ErrorActionPreference = 'Continue'
$Folder = $PSScriptRoot
Set-Location $Folder
$Log = Join-Path $Folder ("log_uruchom_wszystko_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $Log | Out-Null

function Zakoncz($kod) {
    Write-Host ""
    Write-Host "Log zapisany w: $Log" -ForegroundColor Cyan
    Stop-Transcript | Out-Null
    Read-Host "Nacisnij Enter, aby zamknac okno"
    exit $kod
}
function Naglowek($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Yellow }
function Pytaj($t) {
    $o = Read-Host "$t [T/N]"
    return ($o -match '^(t|T|tak|TAK|y|Y)$')
}

# --- 0. Uprawnienia administratora ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Brak uprawnien administratora. Uruchamiam ponownie jako administrator..." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" -PublicUrl `"$PublicUrl`" -ZakresSieci `"$ZakresSieci`""
    exit
}

Write-Host "Adres aplikacji: $PublicUrl" -ForegroundColor Cyan
Write-Host "Folder paczki:   $Folder" -ForegroundColor Cyan

# --- 1. Sprawdzenie plikow paczki ---
Naglowek "Sprawdzenie plikow paczki"
$wymagane = @('0_test_sieci_serwera.ps1','2_instalacja_n8n_serwer.ps1','3_sprawdzenie.ps1','apache\n8n-proxy.conf')
$brak = $wymagane | Where-Object { -not (Test-Path (Join-Path $Folder $_)) }
if ($brak) {
    Write-Host "BRAK plikow: $($brak -join ', ')" -ForegroundColor Red
    Write-Host "Rozpakuj caly ZIP (Wyodrebnij wszystkie) i uruchom skrypt z folderu paczki."
    Zakoncz 1
}
if (-not (Test-Path (Join-Path $Folder 'dane'))) {
    Write-Host "BRAK folderu 'dane' w paczce. Wlasciciel musi najpierw wykonac krok 1 na starym komputerze" -ForegroundColor Red
    Write-Host "(1_eksport_danych_z_komputera.ps1) i przekazac folder z podfolderem dane\."
    Zakoncz 1
}
# odblokowanie plikow pobranych z internetu
Get-ChildItem $Folder -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Write-Host "[OK] Pliki paczki i folder dane\ sa na miejscu."

# --- 2. Test gotowosci serwera ---
Naglowek "Krok 0: test gotowosci serwera"
& powershell -ExecutionPolicy Bypass -File (Join-Path $Folder '0_test_sieci_serwera.ps1')
Write-Host ""
if (-not (Pytaj "Czy w tescie nie ma pozycji [BLAD] i mozna przejsc do instalacji")) {
    Write-Host "Przerwano. Popraw bledy z testu i uruchom skrypt ponownie."
    Zakoncz 1
}

# --- 3. Instalacja n8n ---
Naglowek "Krok 2: instalacja n8n (kilka minut)"
if (Get-Service n8n -ErrorAction SilentlyContinue) {
    Write-Host "Usluga 'n8n' juz istnieje." -ForegroundColor Yellow
    if (-not (Pytaj "Uruchomic instalacje ponownie mimo to")) { Write-Host "Pomijam instalacje." }
    else { & powershell -ExecutionPolicy Bypass -File (Join-Path $Folder '2_instalacja_n8n_serwer.ps1') -PublicUrl $PublicUrl }
} else {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Folder '2_instalacja_n8n_serwer.ps1') -PublicUrl $PublicUrl
}
$svc = Get-Service n8n -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "Usluga 'n8n' nie powstala. Instalacja sie nie udala. Zobacz log powyzej." -ForegroundColor Red
    Zakoncz 1
}
Write-Host "[OK] Usluga n8n: $($svc.Status)"

# --- 4. Apache ---
Naglowek "Krok 3: Apache"
if (-not $ApacheRoot) {
    $kandydaci = @('C:\Apache24','C:\Apache2','C:\xampp\apache','C:\Program Files\Apache24','C:\Program Files (x86)\Apache24','C:\Program Files\Apache Group\Apache2')
    $ApacheRoot = $kandydaci | Where-Object { Test-Path (Join-Path $_ 'bin\httpd.exe') } | Select-Object -First 1
    if (-not $ApacheRoot) {
        $uslugaA = Get-CimInstance Win32_Service | Where-Object { $_.PathName -match 'httpd\.exe' } | Select-Object -First 1
        if ($uslugaA -and $uslugaA.PathName -match '^"?([^"]*?)\\bin\\httpd\.exe') { $ApacheRoot = $Matches[1] }
    }
}
$apacheOk = $false
if (-not $ApacheRoot -or -not (Test-Path (Join-Path $ApacheRoot 'bin\httpd.exe'))) {
    Write-Host "Nie znaleziono Apache automatycznie." -ForegroundColor Red
    $ApacheRoot = Read-Host "Podaj folder Apache (np. C:\Apache24) albo Enter, aby pominac"
}
if ($ApacheRoot -and (Test-Path (Join-Path $ApacheRoot 'bin\httpd.exe'))) {
    Write-Host "Apache: $ApacheRoot"
    $httpd = Join-Path $ApacheRoot 'bin\httpd.exe'
    $httpdConf = Join-Path $ApacheRoot 'conf\httpd.conf'
    $extra = Join-Path $ApacheRoot 'conf\extra'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $kopia = "$httpdConf.bak_$stamp"
    Copy-Item $httpdConf $kopia
    Write-Host "Kopia httpd.conf: $kopia"

    # konfiguracja proxy z podmiana adresu
    $adres = ($PublicUrl -replace '^https?://','') -replace '/.*$',''
    $conf = Get-Content (Join-Path $Folder 'apache\n8n-proxy.conf') -Raw
    $conf = $conf -replace 'n8n\.ohi\.local', $adres
    if (-not (Test-Path $extra)) { New-Item -ItemType Directory -Path $extra | Out-Null }
    $celConf = Join-Path $extra 'n8n-proxy.conf'
    Set-Content -Path $celConf -Value $conf -Encoding ASCII
    Write-Host "Skopiowano konfiguracje do $celConf (adres: $adres)"

    # moduly + Include
    $tekst = Get-Content $httpdConf -Raw
    $moduly = 'proxy_module','proxy_http_module','proxy_wstunnel_module','rewrite_module','headers_module'
    foreach ($m in $moduly) {
        if ($tekst -match "(?m)^\s*LoadModule\s+$m\s") { continue }
        if ($tekst -match "(?m)^\s*#\s*LoadModule\s+$m\s") {
            $tekst = $tekst -replace "(?m)^\s*#\s*(LoadModule\s+$m\s)", '$1'
            Write-Host "Wlaczono modul $m"
        } else {
            Write-Host "UWAGA: w httpd.conf nie ma linii LoadModule dla $m (mozliwe, ze brak pliku modulu)." -ForegroundColor Yellow
        }
    }
    if ($tekst -notmatch '(?m)^\s*Include\s+conf/extra/n8n-proxy\.conf') {
        $tekst = $tekst.TrimEnd() + "`r`nInclude conf/extra/n8n-proxy.conf`r`n"
        Write-Host "Dopisano Include conf/extra/n8n-proxy.conf"
    }
    Set-Content -Path $httpdConf -Value $tekst -Encoding ASCII

    Write-Host "Sprawdzam konfiguracje Apache (httpd -t)..."
    & $httpd -t 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BLAD konfiguracji Apache. Przywracam httpd.conf z kopii." -ForegroundColor Red
        Copy-Item $kopia $httpdConf -Force
        Remove-Item $celConf -ErrorAction SilentlyContinue
    } else {
        $usl = Get-Service | Where-Object { $_.Name -match '^(Apache|httpd)' -or $_.DisplayName -match 'Apache' } | Select-Object -First 1
        if ($usl) {
            Restart-Service $usl.Name -Force
            Write-Host "[OK] Zrestartowano usluge Apache: $($usl.Name)"
            $apacheOk = $true
        } else {
            Write-Host "Nie znaleziono uslugi Apache. Zrestartuj Apache recznie." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Pominieto Apache. Skonfiguruj go recznie wedlug apache\n8n-proxy.conf." -ForegroundColor Yellow
}

# --- 5. Zapora ---
Naglowek "Zapora Windows"
$regula = 'Apache n8n'
if (-not (Get-NetFirewallRule -DisplayName $regula -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $regula -Direction Inbound -Protocol TCP -LocalPort 80 -RemoteAddress $ZakresSieci -Action Allow | Out-Null
    Write-Host "[OK] Dodano regule: port 80 z $ZakresSieci"
} else {
    Write-Host "Regula '$regula' juz istnieje, pomijam."
}

# --- 6. Sprawdzenie ---
Naglowek "Krok 4: sprawdzenie"
Start-Sleep -Seconds 10
& powershell -ExecutionPolicy Bypass -File (Join-Path $Folder '3_sprawdzenie.ps1') -PublicUrl $PublicUrl

Naglowek "Podsumowanie"
Write-Host "Aplikacja:        $PublicUrl/webhook/magazyn"
Write-Host "Test MCP (z innego komputera): curl.exe -i $PublicUrl/mcp-server/http  (ma byc 401)"
Write-Host "Jesli testy nie przechodza po ok. 45 minutach: Stop-Service n8n i dac znac wlascicielowi."
Zakoncz 0
