# AutoInstall - outils système : nettoyage, démarrage, réglages Windows,
# sauvegarde des réglages des logiciels, synchronisation GitHub Gist, clé USB.

# --- Nettoyage PC neuf : applications préinstallées (réinstallables depuis le Microsoft Store) ---
# Nom du paquet, libellé, coché par défaut
$script:BloatApps = @(
    @('Microsoft.BingNews',                      'Actualités (Microsoft News)',      $true),
    @('Microsoft.BingWeather',                   'Météo',                            $false),
    @('Microsoft.GetHelp',                       'Obtenir de l''aide',               $true),
    @('Microsoft.Getstarted',                    'Astuces',                          $true),
    @('Microsoft.MicrosoftSolitaireCollection',  'Solitaire Collection',             $true),
    @('Microsoft.People',                        'Contacts',                         $true),
    @('Microsoft.WindowsFeedbackHub',            'Hub de commentaires',              $true),
    @('Microsoft.WindowsMaps',                   'Cartes',                           $true),
    @('Microsoft.MicrosoftOfficeHub',            'Office (application de pub)',      $true),
    @('Microsoft.SkypeApp',                      'Skype',                            $true),
    @('Microsoft.PowerAutomateDesktop',          'Power Automate',                   $true),
    @('Microsoft.549981C3F5F10',                 'Cortana',                          $true),
    @('Microsoft.MixedReality.Portal',           'Portail de réalité mixte',         $true),
    @('Microsoft.Microsoft3DViewer',             'Visionneuse 3D',                   $true),
    @('Clipchamp.Clipchamp',                     'Clipchamp (montage vidéo)',        $false),
    @('Microsoft.Todos',                         'Microsoft To Do',                  $false),
    @('Microsoft.BingSearch',                    'Recherche Bing',                   $false),
    @('Microsoft.ZuneVideo',                     'Films et TV',                      $false),
    @('Microsoft.MicrosoftStickyNotes',          'Pense-bêtes',                      $false),
    @('Microsoft.WindowsAlarms',                 'Alarmes et horloge',               $false),
    @('Microsoft.YourPhone',                     'Mobile connecté',                  $false),
    @('Microsoft.Copilot',                       'Copilot',                          $false),
    @('MicrosoftTeams',                          'Teams (version personnelle)',      $false),
    @('*king.com*',                              'Jeux King (Candy Crush...)',       $true),
    @('*Disney*',                                'Disney+',                          $true),
    @('*TikTok*',                                'TikTok',                           $true),
    @('*Facebook*',                              'Facebook',                         $true),
    @('*Instagram*',                             'Instagram',                        $true),
    @('*AmazonVideo*',                           'Prime Video',                      $true),
    @('*SpotifyMusic*',                          'Spotify (version préinstallée)',   $false)
)

function Get-InstalledBloat {
    @(foreach ($b in $BloatApps) {
        $pkgs = @(Get-AppxPackage -Name $b[0] -ErrorAction SilentlyContinue)
        if ($pkgs.Count) { [pscustomobject]@{ Nom = $b[1]; Paquet = $b[0]; Coche = $b[2]; Paquets = $pkgs } }
    })
}

function Remove-Bloat($items) {
    foreach ($b in $items) {
        foreach ($p in $b.Paquets) {
            try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Write-Log "Supprimé : $($b.Nom)" }
            catch { Write-Log "Impossible de supprimer $($b.Nom) : $($_.Exception.Message)" }
        }
    }
}

# --- Programmes lancés au démarrage (même mécanisme que le Gestionnaire des tâches, réversible) ---
$script:StartupSources = @(
    @{ Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approuve = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
    @{ Cle = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Approuve = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
    @{ Cle = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approuve = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' },
    @{ Dossier = [Environment]::GetFolderPath('Startup');       Approuve = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
    @{ Dossier = [Environment]::GetFolderPath('CommonStartup'); Approuve = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
)

function Test-StartupEnabled([string]$approved, [string]$name) {
    $v = (Get-ItemProperty -Path $approved -Name $name -ErrorAction SilentlyContinue).$name
    (-not $v) -or -not ($v[0] -band 1)   # 02 = activé, 03 = désactivé
}

function Get-StartupEntries {
    @(foreach ($s in $StartupSources) {
        if ($s.Cle -and (Test-Path $s.Cle)) {
            $key = Get-Item $s.Cle
            foreach ($n in $key.GetValueNames()) {
                if (-not $n) { continue }
                [pscustomobject]@{ Nom = $n; Commande = "$($key.GetValue($n))"; Approuve = $s.Approuve; Active = (Test-StartupEnabled $s.Approuve $n) }
            }
        }
        if ($s.Dossier -and (Test-Path $s.Dossier)) {
            foreach ($f in Get-ChildItem $s.Dossier -File | Where-Object Name -ne 'desktop.ini') {
                [pscustomobject]@{ Nom = $f.Name; Commande = $f.FullName; Approuve = $s.Approuve; Active = (Test-StartupEnabled $s.Approuve $f.Name) }
            }
        }
    })
}

function Set-StartupEnabled($entry, [bool]$enabled) {
    if (-not (Test-Path $entry.Approuve)) { [void](New-Item -Path $entry.Approuve -Force) }
    $bytes = New-Object byte[] 12
    $bytes[0] = if ($enabled) { 2 } else { 3 }
    if (-not $enabled) { [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($bytes, 4) }
    [void](New-ItemProperty -Path $entry.Approuve -Name $entry.Nom -Value $bytes -PropertyType Binary -Force)
    Write-Log "Démarrage automatique $(if ($enabled) { 'activé' } else { 'désactivé' }) : $($entry.Nom)"
}

# --- Réglages Windows (compte actuel, réversibles en décochant) ---
$script:WindowsTweaks = @(
    @{ Nom = 'Thème sombre pour Windows et les applications'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
       Oui = @{ AppsUseLightTheme = 0; SystemUsesLightTheme = 0 }; Non = @{ AppsUseLightTheme = 1; SystemUsesLightTheme = 1 } },
    @{ Nom = 'Afficher les extensions des fichiers (.exe, .pdf...)'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
       Oui = @{ HideFileExt = 0 }; Non = @{ HideFileExt = 1 } },
    @{ Nom = 'Afficher les fichiers cachés'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
       Oui = @{ Hidden = 1 }; Non = @{ Hidden = 2 } },
    @{ Nom = 'Ouvrir l''Explorateur sur « Ce PC »'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
       Oui = @{ LaunchTo = 1 }; Non = @{ LaunchTo = 2 } },
    @{ Nom = 'Barre des tâches alignée à gauche (Windows 11)'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
       Oui = @{ TaskbarAl = 0 }; Non = @{ TaskbarAl = 1 } },
    @{ Nom = 'Pas de résultats Bing dans la recherche du menu Démarrer'
       Cle = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
       Oui = @{ DisableSearchBoxSuggestions = 1 }; Non = @{ DisableSearchBoxSuggestions = 0 } },
    @{ Nom = 'Pas de suggestions ni de pubs (menu Démarrer, écran de verrouillage)'
       Cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
       Oui = @{ 'SubscribedContent-338388Enabled' = 0; 'SubscribedContent-338389Enabled' = 0; 'SubscribedContent-353694Enabled' = 0; SystemPaneSuggestionsEnabled = 0; SilentInstalledAppsEnabled = 0 }
       Non = @{ 'SubscribedContent-338388Enabled' = 1; 'SubscribedContent-338389Enabled' = 1; 'SubscribedContent-353694Enabled' = 1; SystemPaneSuggestionsEnabled = 1; SilentInstalledAppsEnabled = 1 } },
    @{ Nom = 'Désactiver l''accélération de la souris (pratique en jeu)'
       Cle = 'HKCU:\Control Panel\Mouse'
       Oui = @{ MouseSpeed = '0'; MouseThreshold1 = '0'; MouseThreshold2 = '0' }; Non = @{ MouseSpeed = '1'; MouseThreshold1 = '6'; MouseThreshold2 = '10' } },
    @{ Nom = 'Menu clic droit complet, comme avant (Windows 11)'
       Cle = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; MenuClassique = $true }
)

function Test-Tweak($t) {
    if ($t.MenuClassique) { return (Test-Path $t.Cle) }
    $cur = Get-ItemProperty -Path $t.Cle -ErrorAction SilentlyContinue
    if (-not $cur) { return $false }
    foreach ($k in $t.Oui.Keys) { if ("$($cur.$k)" -ne "$($t.Oui[$k])") { return $false } }
    $true
}

function Set-Tweak($t, [bool]$on) {
    if ($t.MenuClassique) {
        if ($on) { [void](New-Item -Path $t.Cle -Force); Set-ItemProperty -Path $t.Cle -Name '(default)' -Value '' }
        else { Remove-Item -Path (Split-Path $t.Cle) -Recurse -ErrorAction SilentlyContinue }
    } else {
        if (-not (Test-Path $t.Cle)) { [void](New-Item -Path $t.Cle -Force) }
        $vals = if ($on) { $t.Oui } else { $t.Non }
        foreach ($k in $vals.Keys) {
            $type = if ($vals[$k] -is [string]) { 'String' } else { 'DWord' }
            [void](New-ItemProperty -Path $t.Cle -Name $k -Value $vals[$k] -PropertyType $type -Force)
        }
    }
    Write-Log "Réglage Windows $(if ($on) { 'appliqué' } else { 'retiré' }) : $($t.Nom)"
}

# --- Sauvegarde des réglages des logiciels (dans sauvegardes\reglages, voyage avec la clé USB) ---
$script:AppSettings = @(
    @{ Nom = 'Visual Studio Code';            Chemins = @('%APPDATA%\Code\User'); Exclure = @('workspaceStorage', 'globalStorage', 'History') },
    @{ Nom = 'Notepad++';                     Chemins = @('%APPDATA%\Notepad++'); Exclure = @('backup') },
    @{ Nom = 'OBS Studio (scènes, profils)';  Chemins = @('%APPDATA%\obs-studio\basic') },
    @{ Nom = 'Windows Terminal';              Chemins = @('%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState') },
    @{ Nom = 'Git (.gitconfig)';              Chemins = @('%USERPROFILE%\.gitconfig') },
    @{ Nom = 'PowerToys';                     Chemins = @('%LOCALAPPDATA%\Microsoft\PowerToys'); Exclure = @('Logs', 'Updates', 'Telemetry') },
    @{ Nom = 'ShareX';                        Chemins = @('%USERPROFILE%\Documents\ShareX'); Exclure = @('Screenshots', 'Logs', 'Backup') },
    @{ Nom = 'Everything';                    Chemins = @('%APPDATA%\Everything\Everything.ini') },
    @{ Nom = 'qBittorrent';                   Chemins = @('%APPDATA%\qBittorrent') },
    @{ Nom = 'FxSound';                       Chemins = @('%APPDATA%\FxSound') },
    @{ Nom = 'MSI Afterburner (profils)';     Chemins = @('%ProgramFiles(x86)%\MSI Afterburner\Profiles') },
    @{ Nom = 'Minecraft (options, serveurs)'; Chemins = @('%APPDATA%\.minecraft\options.txt', '%APPDATA%\.minecraft\servers.dat') }
)

function Get-AppSettingsFolder($app) { Join-Path (Join-Path $BackupDir 'reglages') ($app.Nom -replace '[^\w\-\+ ]', '').Trim() }

function Test-AppSettingsPresent($app) {
    foreach ($c in $app.Chemins) { if (Test-Path ([Environment]::ExpandEnvironmentVariables($c))) { return $true } }
    $false
}

function Test-AppSettingsSaved($app) { Test-Path (Get-AppSettingsFolder $app) }

function Copy-Tree([string]$from, [string]$to, [string[]]$exclude) {
    $a = @("`"$from`"", "`"$to`"", '/E', '/R:0', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XF', '*.log', '*.tmp', 'LOCK')
    $dirs = @($exclude) + @('Cache', 'GPUCache', 'Code Cache', 'CachedData', 'logs') | Where-Object { $_ }
    $a += '/XD'; $a += @($dirs | ForEach-Object { "`"$_`"" })
    $p = Start-Process robocopy.exe -ArgumentList $a -NoNewWindow -PassThru
    while (-not $p.HasExited) { Wait-Ui }
    $p.ExitCode -lt 8
}

function Backup-AppSettings($app) {
    $dest = Get-AppSettingsFolder $app
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    for ($i = 0; $i -lt $app.Chemins.Count; $i++) {
        $src = [Environment]::ExpandEnvironmentVariables($app.Chemins[$i])
        if (-not (Test-Path $src)) { continue }
        $slot = Join-Path $dest $i
        [void](New-Item -ItemType Directory -Path $slot -Force)
        if (Test-Path $src -PathType Container) { [void](Copy-Tree $src (Join-Path $slot (Split-Path $src -Leaf)) $app.Exclure) }
        else { Copy-Item $src $slot -Force }
    }
    Write-Log "Réglages sauvegardés : $($app.Nom)"
}

function Restore-AppSettings($app) {
    $dir = Get-AppSettingsFolder $app
    for ($i = 0; $i -lt $app.Chemins.Count; $i++) {
        $target = [Environment]::ExpandEnvironmentVariables($app.Chemins[$i])
        $saved = Join-Path (Join-Path $dir $i) (Split-Path $target -Leaf)
        if (-not (Test-Path $saved)) { continue }
        $parent = Split-Path $target
        if (-not (Test-Path $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        if (Test-Path $saved -PathType Container) { [void](Copy-Tree $saved $target @()) }
        else { Copy-Item $saved $target -Force }
    }
    Write-Log "Réglages restaurés : $($app.Nom)"
}

# --- Synchronisation des profils avec un Gist GitHub privé ---
function Get-GistToken([hashtable]$settings) {
    if (-not $settings.GistToken) { return $null }
    try {
        $sec = ConvertTo-SecureString $settings.GistToken
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    } catch { $null }
}

# Le jeton est chiffré avec le compte Windows (illisible sur un autre PC ou par un autre utilisateur)
function Set-GistToken([hashtable]$settings, [string]$token) {
    $settings.GistToken = ConvertTo-SecureString $token -AsPlainText -Force | ConvertFrom-SecureString
}

function Invoke-GitHub([string]$method, [string]$url, [string]$token, $body) {
    $h = @{ Authorization = "token $token"; 'User-Agent' = 'AutoInstall'; Accept = 'application/vnd.github+json' }
    if ($body) {
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $body -Depth 6))
        Invoke-RestMethod -Method $method -Uri $url -Headers $h -Body $bytes -ContentType 'application/json; charset=utf-8'
    } else { Invoke-RestMethod -Method $method -Uri $url -Headers $h }
}

# Envoie tous les profils ; renvoie l'ID du Gist (créé au premier envoi)
function Send-ProfilesToGist([hashtable]$settings, [string]$token) {
    $files = @{}
    foreach ($f in Get-ChildItem $ProfileDir -Filter *.json -File) { $files["AutoInstall-$($f.Name)"] = @{ content = (Get-Content $f.FullName -Raw -Encoding UTF8) } }
    $body = @{ description = 'AutoInstall - mes profils de logiciels'; files = $files }
    if ($settings.GistId) { $r = Invoke-GitHub 'PATCH' "https://api.github.com/gists/$($settings.GistId)" $token $body }
    else { $body.public = $false; $r = Invoke-GitHub 'POST' 'https://api.github.com/gists' $token $body }
    $settings.GistId = $r.id
    Write-Log "$($files.Count) profil(s) envoyé(s) sur GitHub : $($r.html_url)"
}

# Télécharge les profils du Gist dans le dossier profils ; renvoie les noms récupérés
function Receive-ProfilesFromGist([hashtable]$settings, [string]$token) {
    $r = Invoke-GitHub 'GET' "https://api.github.com/gists/$($settings.GistId)" $token $null
    @(foreach ($p in $r.files.PSObject.Properties) {
        if ($p.Name -notmatch '^AutoInstall-(.+)\.json$') { continue }
        $name = $Matches[1]
        $content = if ($p.Value.truncated) { Invoke-RestMethod $p.Value.raw_url -UseBasicParsing | ConvertTo-Json -Depth 6 } else { $p.Value.content }
        Set-Content -Path (Get-ProfilePath $name) -Value $content -Encoding UTF8
        Write-Log "Profil récupéré depuis GitHub : $name"
        $name
    })
}

# --- Clé USB AutoInstall ---
function Get-RemovableDrives {
    @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady })
}

function Copy-ToUsb([string]$root) {
    $dest = Join-Path $root 'AutoInstall'
    Write-Log "Copie d'AutoInstall vers $dest..."
    $ok = Copy-Tree $ScriptDir $dest @('.git', 'journaux', 'cache')
    if ($ok) { Write-Log "Clé prête : branche-la sur le nouveau PC et lance $dest\Lancer.bat" }
    else { Write-Log 'La copie vers la clé a échoué (clé pleine ou protégée en écriture ?).' }
    $ok
}
