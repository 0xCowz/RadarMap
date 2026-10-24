# install-windows.ps1 — Installe RadarMap sur iPhone depuis Windows 11
# Prérequis : iTunes installé (pas la version Microsoft Store, la version Apple directe)
# Téléchargement : https://www.apple.com/itunes/download/win64
#
# Usage :
#   1. Télécharge RadarMap-unsigned.ipa depuis GitHub Actions (onglet Actions > dernier run > Artifacts)
#   2. Re-signe le .ipa avec AltStore / Sideloadly (voir ci-dessous)
#   3. Lance ce script : .\install-windows.ps1 -IpaPath .\RadarMap-unsigned.ipa

param(
    [Parameter(Mandatory=$false)]
    [string]$IpaPath = "RadarMap-unsigned.ipa"
)

# ── Vérifications ────────────────────────────────────────────────────────────

if (-not (Test-Path $IpaPath)) {
    Write-Error "Fichier introuvable : $IpaPath"
    Write-Host ""
    Write-Host "ÉTAPES POUR INSTALLER RADARMAP :" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Option A — Sideloadly (recommandé, gratuit) :" -ForegroundColor Yellow
    Write-Host "    1. Télécharge Sideloadly : https://sideloadly.io"
    Write-Host "    2. Connecte ton iPhone en USB"
    Write-Host "    3. Glisse le fichier RadarMap-unsigned.ipa dans Sideloadly"
    Write-Host "    4. Connecte-toi avec ton Apple ID gratuit"
    Write-Host "    5. Clique Install"
    Write-Host "    Note : l'app expire au bout de 7 jours (limite compte gratuit),"
    Write-Host "           relance Sideloadly pour renouveler."
    Write-Host ""
    Write-Host "  Option B — AltStore (renouvellement auto) :" -ForegroundColor Yellow
    Write-Host "    1. Installe AltServer sur Windows : https://altstore.io"
    Write-Host "    2. Installe AltStore sur ton iPhone via AltServer"
    Write-Host "    3. Ouvre AltStore > My Apps > + > choisis le .ipa"
    Write-Host "    Note : AltServer doit tourner en arrière-plan pour le renouvellement auto."
    Write-Host ""
    exit 1
}

# ── Détection d'iTunes / libimobiledevice ────────────────────────────────────

$ideviceinstaller = Get-Command ideviceinstaller -ErrorAction SilentlyContinue
if ($ideviceinstaller) {
    Write-Host "ideviceinstaller trouvé, installation directe..." -ForegroundColor Green
    ideviceinstaller -i $IpaPath
} else {
    Write-Host "ideviceinstaller non trouvé." -ForegroundColor Yellow
    Write-Host "→ Utilise Sideloadly ou AltStore pour installer le .ipa (voir instructions ci-dessus)." -ForegroundColor Cyan
}
