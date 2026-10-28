# AutoInstall - moteur commun (winget, profils, réglages, journal, vérifications)
# Chargé par AutoInstall.ps1, en mode fenêtre comme en ligne de commande.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:LogDir       = Join-Path $ScriptDir 'journaux'
$script:ProfileDir   = Join-Path $ScriptDir 'profils'
$script:CachePath    = Join-Path $ScriptDir 'cache'
$script:BackupDir    = Join-Path $ScriptDir 'sauvegardes'
$script:SettingsPath = Join-Path $ScriptDir 'reglages.json'
$script:CatalogPath  = Join-Path $ScriptDir 'catalogue.json'
$script:LogFile      = Join-Path $LogDir "AutoInstall-$(Get-Date -Format yyyy-MM-dd).log"

$script:Gui             = $false   # $true quand la fenêtre est ouverte (pour ne pas la figer)
$script:Quiet           = $false   # mode sans fenêtre : rien dans la console
$script:LogSink         = $null    # scriptblock appelé à chaque ligne de journal (interface)
$script:CancelRequested = $false
$script:CurrentProcess  = $null

# --- Journal (écran + fichier journaux\AutoInstall-AAAA-MM-JJ.log) ---
function Write-Log([string]$msg) {
    $line = "[$(Get-Date -Format HH:mm:ss)] $msg"
    try {
        if (-not (Test-Path $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
    if ($LogSink) { & $LogSink $line }
    elseif (-not $Quiet) { Write-Host $line }
}

function Wait-Ui {
    if ($Gui) { [Windows.Forms.Application]::DoEvents() }
    Start-Sleep -Milliseconds 100
}

# --- Réglages de l'application (reglages.json) ---
function Read-Settings {
    $s = @{
        Profil = 'Principal'; Theme = 'Clair'; Dossier = ''
        SauterInstalles = $true; RuntimesDabord = $true; PointRestauration = $false
        SupprimerRaccourcis = $false; Redemarrer = $false
        Fenetre = $null; Colonnes = $null; GistId = ''; GistToken = ''
    }
    if (Test-Path $SettingsPath) {
        try {
            $j = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = $p.Value }
        } catch { Write-Log "reglages.json illisible, réglages par défaut utilisés : $_" }
    }
    $s
}

function Save-Settings([hashtable]$s) {
    ConvertTo-Json $s -Depth 5 | Set-Content -Path $SettingsPath -Encoding UTF8
}

# --- Catalogue ---
function Read-Catalog {
    try { $j = Get-Content $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json; @($j) }
    catch { Write-Log "Impossible de lire catalogue.json : $_"; @() }
}

# --- Profils (profils\<nom>.json) ---
function Get-ProfilePath([string]$name) { Join-Path $ProfileDir "$name.json" }

function Get-ProfileNames {
    if (-not (Test-Path $ProfileDir)) { [void](New-Item -ItemType Directory -Path $ProfileDir) }
    $old = Join-Path $ScriptDir 'ma-selection.json'
    if ((Test-Path $old) -and -not (Test-Path (Get-ProfilePath 'Principal'))) {
        Move-Item $old (Get-ProfilePath 'Principal')
        Write-Log 'ma-selection.json a été déplacé dans profils\Principal.json.'
    }
    $names = @(Get-ChildItem $ProfileDir -Filter *.json -File | ForEach-Object BaseName)
    if ($names -notcontains 'Principal') { $names = @('Principal') + $names }
    $names
}

# Lit une sélection : profil AutoInstall (ancien ou nouveau format) ou fichier « winget export »
function Read-SelectionFile([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $j = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j.Sources) {
        return @(foreach ($src in $j.Sources) { foreach ($p in $src.Packages) {
            [pscustomobject]@{ Categorie = 'Importés'; Nom = $p.PackageIdentifier; Id = $p.PackageIdentifier; Version = '' }
        } })
    }
    $list = if ($j.Logiciels) { $j.Logiciels } else { $j }
    @(foreach ($e in $list) {
        if (-not $e.Id) { continue }
        [pscustomobject]@{ Categorie = $(if ($e.Categorie) { $e.Categorie } else { 'Importés' }); Nom = $(if ($e.Nom) { $e.Nom } else { $e.Id }); Id = $e.Id; Version = "$($e.Version)" }
    })
}

function Write-SelectionFile([string]$path, $entries) {
    $data = [ordered]@{
        Application = 'AutoInstall'
        Date        = (Get-Date -Format s)
        Logiciels   = @(foreach ($e in $entries) { [ordered]@{ Categorie = $e.Categorie; Nom = $e.Nom; Id = $e.Id; Version = $e.Version } })
    }
    ConvertTo-Json $data -Depth 5 | Set-Content -Path $path -Encoding UTF8
}

# --- winget ---
# Lance winget sans figer la fenêtre. -Capture renvoie aussi la sortie texte.
function Invoke-Winget([string]$arguments, [switch]$Capture) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'winget'
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($Capture) {
        $psi.RedirectStandardOutput = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    }
    $p = [Diagnostics.Process]::Start($psi)
    $script:CurrentProcess = $p
    $read = if ($Capture) { $p.StandardOutput.ReadToEndAsync() }
    while (-not $p.HasExited) { Wait-Ui }
    $p.WaitForExit()
    $script:CurrentProcess = $null
    if (-not $Capture) { return $p.ExitCode }
    $lines = @($read.Result -split "`n" | ForEach-Object { $_.TrimEnd("`r") -replace '^.*\r', '' })
    [pscustomobject]@{ Code = $p.ExitCode; Lines = $lines }
}

# Arrête net le winget en cours (deuxième clic sur « Annuler »)
function Stop-CurrentWinget {
    $p = $CurrentProcess
    if ($p -and -not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null }
}

# Découpe les tableaux affichés par winget (search, upgrade...) selon la position des titres
function ConvertFrom-WingetTable([string[]]$lines) {
    $rows = New-Object Collections.Generic.List[object]
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^-{10,}') { continue }
        $starts = @([regex]::Matches($lines[$i - 1], '\S+') | ForEach-Object { $_.Index })
        if ($starts.Count -lt 3) { continue }
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $l = $lines[$j]
            if (-not $l.Trim() -or $l -match '^-{10,}') { break }
            if ($l.Length -lt $starts[2]) { continue }
            $cols = @(for ($k = 0; $k -lt $starts.Count; $k++) {
                $a = $starts[$k]
                $b = if ($k + 1 -lt $starts.Count) { [Math]::Min($starts[$k + 1], $l.Length) } else { $l.Length }
                if ($a -ge $l.Length) { '' } else { $l.Substring($a, $b - $a).Trim() }
            })
            if ($cols[1] -notmatch '^\S+\.\S+$') { continue }   # lignes de résumé, pas un ID
            $rows.Add([pscustomobject]@{ Nom = $cols[0]; Id = $cols[1]; Version = $cols[2]; Cols = $cols })
        }
    }
    , $rows.ToArray()
}

function Search-Winget([string]$query) {
    $r = Invoke-Winget "search `"$query`" --source winget --accept-source-agreements --disable-interactivity" -Capture
    @(ConvertFrom-WingetTable $r.Lines)
}

# IDs installés et leur version (winget export donne des IDs exacts)
function Get-InstalledPackages {
    $map = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $tmp = Join-Path $env:TEMP "autoinstall-export-$PID.json"
    [void](Invoke-Winget "export -o `"$tmp`" --source winget --include-versions --accept-source-agreements --disable-interactivity")
    if (Test-Path $tmp) {
        try {
            $data = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($src in $data.Sources) { foreach ($p in $src.Packages) { $map[$p.PackageIdentifier] = "$($p.Version)" } }
        } catch { Write-Log "Impossible de lire la liste des logiciels installés : $_" }
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    , $map
}

# Mises à jour disponibles : ID -> nouvelle version
function Get-AvailableUpgrades {
    $map = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $r = Invoke-Winget 'upgrade --source winget --accept-source-agreements --disable-interactivity' -Capture
    foreach ($row in (ConvertFrom-WingetTable $r.Lines)) {
        if ($row.Cols.Count -ge 4 -and $row.Cols[3]) { $map[$row.Id.TrimEnd([char]0x2026)] = $row.Cols[3] }
    }
    , $map
}

# Retrouve une valeur même si winget a tronqué l'ID avec « … »
function Find-ById($map, [string]$id) {
    if ($map.ContainsKey($id)) { return $map[$id] }
    foreach ($k in $map.Keys) { if ($k.Length -ge 10 -and $id.StartsWith($k, [StringComparison]::OrdinalIgnoreCase)) { return $map[$k] } }
    $null
}

function Get-PackageVersions([string]$id) {
    $r = Invoke-Winget "show --id `"$id`" --exact --versions --source winget --accept-source-agreements --disable-interactivity" -Capture
    $sep = -1
    for ($i = 0; $i -lt $r.Lines.Count; $i++) { if ($r.Lines[$i] -match '^-{3,}\s*$') { $sep = $i; break } }
    if ($sep -lt 0) { return @() }
    @($r.Lines[($sep + 1)..($r.Lines.Count - 1)] | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# --- Codes de retour winget expliqués en français ---
$script:WingetCodes = @{
    0          = @($true,  'OK',                          '')
    3010       = @($true,  'OK (redémarrage requis)',     'Windows doit redémarrer pour terminer.')
    0x8A150109 = @($true,  'OK (redémarrage requis)',     'Windows doit redémarrer pour terminer.')
    0x8A15002B = @($true,  'Déjà à jour',                 'La dernière version est déjà installée.')
    0x8A150061 = @($true,  'Déjà installé',               'Ce logiciel est déjà installé.')
    0x8A15010D = @($true,  'Déjà installé',               'Ce logiciel est déjà installé.')
    0x8A150014 = @($false, 'Introuvable',                 "Cet ID n'existe pas (ou plus) dans winget. Cherche le logiciel avec « Chercher un autre logiciel »." )
    0x8A150008 = @($false, 'Téléchargement échoué',       'Le téléchargement a échoué. Vérifie ta connexion Internet puis réessaie.')
    0x8A150011 = @($false, 'Fichier différent',           "Le fichier téléchargé ne correspond pas à celui attendu (l'éditeur vient sans doute de changer son installeur). Réessaie dans un jour ou deux.")
    0x8A150101 = @($false, 'Logiciel ouvert',             'Le logiciel est en cours d''utilisation. Ferme-le puis réessaie.')
    0x8A150102 = @($false, 'Autre installation en cours', "Une autre installation est en cours. Attends qu'elle se termine puis réessaie.")
    0x8A150103 = @($false, 'Fichier utilisé',             'Un fichier est utilisé par un autre programme. Ferme tes programmes puis réessaie.')
    0x8A150104 = @($false, 'Dépendance manquante',        'Il manque un composant nécessaire à ce logiciel.')
    0x8A150105 = @($false, 'Disque plein',                "Il n'y a plus assez de place sur le disque. Libère de l'espace puis réessaie.")
    0x8A150106 = @($false, 'Mémoire insuffisante',        "Il n'y a pas assez de mémoire. Ferme des programmes puis réessaie.")
    0x8A150107 = @($false, 'Pas de réseau',               "L'installeur n'a pas accès à Internet.")
    0x8A15010A = @($false, 'Redémarrage nécessaire',      'Windows doit redémarrer avant de pouvoir installer ce logiciel.')
    0x8A15010C = @($false, 'Annulé',                      "L'installation a été annulée.")
    0x8A15010E = @($false, 'Version plus récente',        'Une version plus récente est déjà installée.')
    0x8A15010F = @($false, 'Bloqué',                      "Bloqué par une règle de l'administrateur du PC.")
    0x8A150113 = @($false, 'Incompatible',                "Ce logiciel n'est pas compatible avec ce PC.")
    1602       = @($false, 'Annulé',                      "L'installation a été annulée.")
    1603       = @($false, 'Échec de l''installeur',      "L'installeur a échoué. Redémarre le PC puis réessaie.")
    1618       = @($false, 'Autre installation en cours', "Une autre installation est en cours. Attends qu'elle se termine puis réessaie.")
}

function Get-WingetResult([int]$code, [string]$action = 'install') {
    $c = $WingetCodes[$code]
    if (-not $c) { $c = @($false, ('Erreur 0x{0:X8}' -f $code), "Erreur inconnue. Le détail est dans le journal de winget (%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir).") }
    $status = $c[1]
    if ($code -eq 0) { $status = @{ install = 'Installé'; upgrade = 'Mis à jour'; uninstall = 'Désinstallé' }[$action] }
    [pscustomobject]@{ Code = $code; Ok = $c[0]; Status = $status; Explication = $c[2] }
}

# --- Vérifications avant installation ---
function Test-Internet {
    try {
        $req = [Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $req.Timeout = 6000
        $req.GetResponse().Close()
        $true
    } catch { $false }
}

function Get-FreeSpaceGB([string]$path) {
    $root = if ($path) { [IO.Path]::GetPathRoot($path) } else { $env:SystemDrive }
    try { [Math]::Round((New-Object IO.DriveInfo $root).AvailableFreeSpace / 1GB, 1) } catch { -1 }
}

# Renvoie un message d'erreur, ou $null si tout va bien
function Test-Prerequisites([string]$location) {
    Write-Log 'Vérification de la connexion Internet...'
    if (-not (Test-Internet)) { return "Pas de connexion Internet. Branche le PC au réseau puis réessaie." }
    $free = Get-FreeSpaceGB $location
    if ($free -ge 0 -and $free -lt 2) { return "Il ne reste que $free Go sur le disque. Libère de l'espace avant d'installer." }
    if ($free -ge 0 -and $free -lt 10) { Write-Log "Attention : il ne reste que $free Go d'espace libre." }
    $null
}

function New-RestorePoint {
    Write-Log 'Création d''un point de restauration (peut prendre une minute)...'
    $job = Start-Job { Checkpoint-Computer -Description 'AutoInstall' -RestorePointType APPLICATION_INSTALL -ErrorAction Stop -WarningAction Continue }
    while ($job.State -eq 'Running') { Wait-Ui }
    $warn = $null
    try {
        Receive-Job $job -ErrorAction Stop -WarningVariable warn -WarningAction SilentlyContinue | Out-Null
        if ($warn) { Write-Log "Point de restauration non créé : $warn" } else { Write-Log 'Point de restauration créé.' }
    } catch {
        Write-Log "Point de restauration impossible : $($_.Exception.Message) (la protection du système est peut-être désactivée)."
    }
    Remove-Job $job -Force
}

# --- Raccourcis bureau ajoutés par les installeurs ---
function Get-DesktopShortcuts {
    @(foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        if ($d -and (Test-Path $d)) { Get-ChildItem $d -Filter *.lnk -File | ForEach-Object FullName }
    })
}

function Remove-NewDesktopShortcuts([string[]]$before) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    foreach ($f in Get-DesktopShortcuts) {
        if ($before -contains $f) { continue }
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f, 'OnlyErrorDialogs', 'SendToRecycleBin')
            Write-Log "Raccourci du bureau mis à la corbeille : $([IO.Path]::GetFileNameWithoutExtension($f))"
        } catch { Write-Log "Impossible de supprimer le raccourci $f : $_" }
    }
}

# --- Installe / met à jour / désinstalle une liste ---
# Entrées : objets { Categorie, Nom, Id, Version, Installe }
# $OnItem : appelé avec ($entree, 'start'|'done'|'skip', $resultat, $infos)
function Invoke-PackageBatch {
    param($Entries, [string]$Action = 'install', [hashtable]$Options = @{}, [scriptblock]$OnItem)
    $script:CancelRequested = $false
    $todo = @($Entries)
    $results = New-Object Collections.Generic.List[object]
    $verb = @{ install = 'Installation'; upgrade = 'Mise à jour'; uninstall = 'Désinstallation' }[$Action]

    if ($Action -eq 'install' -and $Options.SauterInstalles) {
        foreach ($e in $todo | Where-Object { $_.Installe }) {
            if ($OnItem) { & $OnItem $e 'skip' $null $null }
            Write-Log "$($e.Nom) : déjà installé, ignoré."
        }
        $todo = @($todo | Where-Object { -not $_.Installe })
    }
    if ($Action -ne 'uninstall' -and $Options.RuntimesDabord) {
        $todo = @($todo | Where-Object { $_.Categorie -eq 'Runtimes' }) + @($todo | Where-Object { $_.Categorie -ne 'Runtimes' })
    }
    if ($todo.Count -eq 0) { Write-Log 'Rien à faire.'; return , $results.ToArray() }

    if ($Options.PointRestauration) { New-RestorePoint }
    $shortcuts = if ($Options.SupprimerRaccourcis) { Get-DesktopShortcuts }

    $started = Get-Date
    for ($i = 0; $i -lt $todo.Count; $i++) {
        $e = $todo[$i]
        $eta = if ($i -gt 0) { [TimeSpan]::FromSeconds(((Get-Date) - $started).TotalSeconds / $i * ($todo.Count - $i)) }
        $info = @{ Index = $i; Total = $todo.Count; Restant = $eta }
        if ($CancelRequested) {
            $r = [pscustomobject]@{ Code = -1; Ok = $false; Status = 'Annulé'; Explication = 'Annulé par toi.' }
            $results.Add([pscustomobject]@{ Entree = $e; Resultat = $r })
            if ($OnItem) { & $OnItem $e 'done' $r $info }
            continue
        }
        if ($OnItem) { & $OnItem $e 'start' $null $info }
        Write-Log "$verb de $($e.Nom)..."
        $a = switch ($Action) {
            'install'   { "install --id `"$($e.Id)`" --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" }
            'upgrade'   { "upgrade --id `"$($e.Id)`" --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --include-unknown" }
            'uninstall' { "uninstall --id `"$($e.Id)`" --exact --silent --accept-source-agreements --disable-interactivity" }
        }
        if ($Action -eq 'install' -and $e.Version) { $a += " --version `"$($e.Version)`"" }
        if ($Action -eq 'install' -and $Options.Dossier) { $a += " --location `"$(Join-Path $Options.Dossier ($e.Nom -replace '[\\/:*?"<>|]', ''))`"" }
        $r = Get-WingetResult (Invoke-Winget $a) $Action
        if ($CancelRequested -and -not $r.Ok) { $r.Status = 'Annulé'; $r.Explication = 'Arrêté par toi.' }
        Write-Log "  -> $($r.Status)$(if ($r.Explication -and -not $r.Ok) { " : $($r.Explication)" })"
        $results.Add([pscustomobject]@{ Entree = $e; Resultat = $r })
        if ($OnItem) { & $OnItem $e 'done' $r $info }
    }

    if ($Options.SupprimerRaccourcis) { Remove-NewDesktopShortcuts $shortcuts }
    $ok = @($results | Where-Object { $_.Resultat.Ok }).Count
    Write-Log "Terminé en $([int]((Get-Date) - $started).TotalMinutes) min : $ok réussi(s), $($results.Count - $ok) échec(s)."
    , $results.ToArray()
}

function Restart-ComputerSoon {
    Write-Log 'Redémarrage du PC dans 60 secondes (tape « shutdown /a » pour annuler).'
    & shutdown.exe /r /t 60 /c "AutoInstall a terminé. Redémarrage dans 60 secondes." | Out-Null
}
