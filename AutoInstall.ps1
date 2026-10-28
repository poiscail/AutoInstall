# AutoInstall - installe tes logiciels en dernière version via winget
# Lancer avec Lancer.bat (demande les droits admin automatiquement)

# --- Relance en administrateur si besoin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir   = Split-Path -Parent $PSCommandPath
$ProfilePath = Join-Path $ScriptDir 'ma-selection.json'

# --- Catalogue par défaut (Catégorie, Nom affiché, ID winget) ---
$Catalog = @(
    @('Navigateurs',   'Google Chrome',            'Google.Chrome'),
    @('Navigateurs',   'Mozilla Firefox',          'Mozilla.Firefox'),
    @('Navigateurs',   'Brave',                    'Brave.Brave'),
    @('Navigateurs',   'Opera GX',                 'Opera.OperaGX'),
    @('IA',            'Claude',                   'Anthropic.Claude'),
    @('Communication', 'Discord',                  'Discord.Discord'),
    @('Communication', 'Telegram',                 'Telegram.TelegramDesktop'),
    @('Communication', 'Zoom',                     'Zoom.Zoom'),
    @('Communication', 'Slack',                    'SlackTechnologies.Slack'),
    @('Jeux',          'Steam',                    'Valve.Steam'),
    @('Jeux',          'Epic Games Launcher',      'EpicGames.EpicGamesLauncher'),
    @('Jeux',          'Ubisoft Connect',          'Ubisoft.Connect'),
    @('Jeux',          'EA App',                   'ElectronicArts.EADesktop'),
    @('Jeux',          'GOG Galaxy',               'GOG.Galaxy'),
    @('Jeux',          'Minecraft Launcher',       'Mojang.MinecraftLauncher'),
    @('Jeux',          'CurseForge',               'Overwolf.CurseForge'),
    @('Jeux',          'Modrinth App',             'Modrinth.ModrinthApp'),
    @('Jeux',          'Lunar Client',             'Moonsworth.LunarClient'),
    @('Jeux',          'Rockstar Games Launcher',  'RockstarGames.Launcher'),
    @('Jeux',          'Roblox',                   'Roblox.Roblox'),
    @('Multimédia',    'VLC',                      'VideoLAN.VLC'),
    @('Multimédia',    'Spotify',                  'Spotify.Spotify'),
    @('Multimédia',    'OBS Studio',               'OBSProject.OBSStudio'),
    @('Multimédia',    'Audacity',                 'Audacity.Audacity'),
    @('Multimédia',    'HandBrake',                'HandBrake.HandBrake'),
    @('Multimédia',    'FxSound',                  'FxSound.FxSound'),
    @('Utilitaires',   '7-Zip',                    '7zip.7zip'),
    @('Utilitaires',   'WinRAR',                   'RARLab.WinRAR'),
    @('Utilitaires',   'Notepad++',                'Notepad++.Notepad++'),
    @('Utilitaires',   'Everything (recherche)',   'voidtools.Everything'),
    @('Utilitaires',   'PowerToys',                'Microsoft.PowerToys'),
    @('Utilitaires',   'ShareX (captures)',        'ShareX.ShareX'),
    @('Utilitaires',   'qBittorrent',              'qBittorrent.qBittorrent'),
    @('Utilitaires',   'Bitwarden',                'Bitwarden.Bitwarden'),
    @('Utilitaires',   'AnyDesk',                  'AnyDesk.AnyDesk'),
    @('Utilitaires',   'TeamViewer',               'TeamViewer.TeamViewer'),
    @('Utilitaires',   'Malwarebytes',             'Malwarebytes.Malwarebytes'),
    @('Utilitaires',   'Google Drive',             'Google.GoogleDrive'),
    @('Utilitaires',   'WizTree (espace disque)',  'AntibodySoftware.WizTree'),
    @('Utilitaires',   'TranslucentTB',            'CharlesMilette.TranslucentTB'),
    @('Matériel',      'CPU-Z',                    'CPUID.CPU-Z'),
    @('Matériel',      'GPU-Z',                    'TechPowerUp.GPU-Z'),
    @('Matériel',      'HWMonitor',                'CPUID.HWMonitor'),
    @('Matériel',      'CrystalDiskInfo',          'CrystalDewWorld.CrystalDiskInfo'),
    @('Matériel',      'MSI Afterburner',          'Guru3D.Afterburner'),
    @('Matériel',      'Rufus',                    'Rufus.Rufus'),
    @('Bureautique',   'LibreOffice',              'TheDocumentFoundation.LibreOffice'),
    @('Bureautique',   'Adobe Acrobat Reader',     'Adobe.Acrobat.Reader.64-bit'),
    @('Bureautique',   'SumatraPDF',               'SumatraPDF.SumatraPDF'),
    @('Bureautique',   'Notion',                   'Notion.Notion'),
    @('Bureautique',   'Obsidian',                 'Obsidian.Obsidian'),
    @('Bureautique',   'Microsoft Teams',          'Microsoft.Teams'),
    @('Bureautique',   'Outlook',                  'Microsoft.Outlook'),
    @('Développement', 'Visual Studio Code',       'Microsoft.VisualStudioCode'),
    @('Développement', 'Git',                      'Git.Git'),
    @('Développement', 'Python 3.13',              'Python.Python.3.13'),
    @('Développement', 'Node.js LTS',              'OpenJS.NodeJS.LTS'),
    @('Développement', 'Windows Terminal',         'Microsoft.WindowsTerminal'),
    @('Développement', 'GitHub CLI',               'GitHub.cli'),
    @('Développement', '.NET SDK 8',               'Microsoft.DotNet.SDK.8'),
    @('Développement', 'Godot Engine',             'GodotEngine.GodotEngine'),
    @('Développement', 'VirtualBox',               'Oracle.VirtualBox'),
    @('Développement', 'Docker Sandboxes',         'Docker.sbx'),
    @('Runtimes',      'Java 21 (Temurin JRE)',    'EclipseAdoptium.Temurin.21.JRE'),
    @('Runtimes',      'Visual C++ 2015+ x64',     'Microsoft.VCRedist.2015+.x64'),
    @('Runtimes',      'Visual C++ 2015+ x86',     'Microsoft.VCRedist.2015+.x86'),
    @('Runtimes',      '.NET Desktop Runtime 8',   'Microsoft.DotNet.DesktopRuntime.8'),
    @('Runtimes',      'DirectX (runtime)',        'Microsoft.DirectX'),
    @('Runtimes',      'Java 8 (Oracle JRE)',      'Oracle.JavaRuntimeEnvironment'),
    @('Runtimes',      'Visual C++ 2013 x64',      'Microsoft.VCRedist.2013.x64'),
    @('Runtimes',      'Visual C++ 2013 x86',      'Microsoft.VCRedist.2013.x86'),
    @('Runtimes',      'Visual C++ 2012 x64',      'Microsoft.VCRedist.2012.x64'),
    @('Runtimes',      'Visual C++ 2012 x86',      'Microsoft.VCRedist.2012.x86'),
    @('Runtimes',      'Visual C++ 2010 x64',      'Microsoft.VCRedist.2010.x64'),
    @('Runtimes',      'Visual C++ 2010 x86',      'Microsoft.VCRedist.2010.x86'),
    @('Runtimes',      'NVIDIA PhysX',             'Nvidia.PhysX')
)

# --- Fenêtre principale ---
$form = New-Object Windows.Forms.Form
$form.Text = 'AutoInstall - réinstalle tes logiciels en un clic'
$form.Size = New-Object Drawing.Size(900, 700)
$form.MinimumSize = New-Object Drawing.Size(760, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)

# Barre de recherche winget
$searchBox = New-Object Windows.Forms.TextBox
$searchBox.Location = New-Object Drawing.Point(12, 14)
$searchBox.Size = New-Object Drawing.Size(420, 26)
$searchBox.Anchor = 'Top,Left'

$searchBtn = New-Object Windows.Forms.Button
$searchBtn.Text = 'Chercher un autre logiciel'
$searchBtn.Location = New-Object Drawing.Point(440, 12)
$searchBtn.Size = New-Object Drawing.Size(200, 28)

# Filtre de la liste
$filterTitle = New-Object Windows.Forms.Label
$filterTitle.Text = 'Filtrer :'
$filterTitle.Location = New-Object Drawing.Point(12, 48)
$filterTitle.AutoSize = $true

$filterBox = New-Object Windows.Forms.TextBox
$filterBox.Location = New-Object Drawing.Point(70, 45)
$filterBox.Size = New-Object Drawing.Size(220, 26)

$filterLabel = New-Object Windows.Forms.Label
$filterLabel.Text = 'Coche ce que tu veux, puis « Installer ». Ta sélection est sauvegardée automatiquement.'
$filterLabel.Location = New-Object Drawing.Point(300, 48)
$filterLabel.AutoSize = $true
$filterLabel.ForeColor = [Drawing.Color]::DimGray

# Liste des logiciels
$list = New-Object Windows.Forms.ListView
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.ShowGroups = $true
$list.Location = New-Object Drawing.Point(12, 72)
$list.Size = New-Object Drawing.Size(860, 380)
$list.Anchor = 'Top,Bottom,Left,Right'
[void]$list.Columns.Add('Logiciel', 300)
[void]$list.Columns.Add('ID winget', 330)
[void]$list.Columns.Add('Statut', 200)

$groups = @{}
function Get-Group([string]$name) {
    if (-not $groups.ContainsKey($name)) {
        $g = New-Object Windows.Forms.ListViewGroup($name, $name)
        [void]$list.Groups.Add($g)
        $groups[$name] = $g
    }
    $groups[$name]
}

# Tous les logiciels, y compris ceux masqués par le filtre (la catégorie est dans .Tag)
$AllItems = New-Object Collections.Generic.List[Windows.Forms.ListViewItem]
# IDs winget déjà installés sur ce PC (remplis au démarrage)
$InstalledIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Test-Filter([Windows.Forms.ListViewItem]$item) {
    $f = $filterBox.Text.Trim()
    (-not $f) -or $item.Text -like "*$f*" -or $item.SubItems[1].Text -like "*$f*" -or $item.Tag -like "*$f*"
}

function Update-Filter {
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($it in $AllItems) {
        if (Test-Filter $it) {
            [void]$list.Items.Add($it)
            $it.Group = Get-Group $it.Tag
        }
    }
    $list.EndUpdate()
}

function Add-App([string]$cat, [string]$name, [string]$id, [bool]$checked = $false) {
    foreach ($it in $AllItems) { if ($it.SubItems[1].Text -eq $id) { $it.Checked = $it.Checked -or $checked; return } }
    $item = New-Object Windows.Forms.ListViewItem($name)
    [void]$item.SubItems.Add($id)
    [void]$item.SubItems.Add($(if ($InstalledIds.Contains($id)) { 'Déjà installé' } else { '' }))
    $item.Tag = $cat
    $item.Checked = $checked
    $AllItems.Add($item)
    if (Test-Filter $item) {
        [void]$list.Items.Add($item)
        $item.Group = Get-Group $cat
    }
}

foreach ($c in $Catalog) { Add-App $c[0] $c[1] $c[2] }

# Journal
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Font = New-Object Drawing.Font('Consolas', 9)
$log.Location = New-Object Drawing.Point(12, 460)
$log.Size = New-Object Drawing.Size(860, 110)
$log.Anchor = 'Bottom,Left,Right'

$progress = New-Object Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(12, 578)
$progress.Size = New-Object Drawing.Size(860, 18)
$progress.Anchor = 'Bottom,Left,Right'

# Boutons du bas
function New-Btn([string]$text, [int]$x, [int]$w) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, 606)
    $b.Size = New-Object Drawing.Size($w, 36)
    $b.Anchor = 'Bottom,Left'
    $form.Controls.Add($b)
    $b
}
$btnAll     = New-Btn 'Tout cocher'      12  110
$btnNone    = New-Btn 'Tout décocher'    128 110
$btnSave    = New-Btn 'Sauvegarder'      244 110
$btnUpgrade = New-Btn 'Mettre à jour tout le PC' 360 190
$btnInstall = New-Btn 'Installer la sélection'  0 230
$btnInstall.Anchor = 'Bottom,Right'
$btnInstall.Location = New-Object Drawing.Point(642, 606)
$btnInstall.BackColor = [Drawing.Color]::FromArgb(0, 120, 212)
$btnInstall.ForeColor = [Drawing.Color]::White
$btnInstall.FlatStyle = 'Flat'
$btnInstall.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)

$form.Controls.AddRange(@($searchBox, $searchBtn, $filterTitle, $filterBox, $filterLabel, $list, $log, $progress))

function Write-Log([string]$msg) {
    $log.AppendText("[$(Get-Date -Format HH:mm:ss)] $msg`r`n")
    [Windows.Forms.Application]::DoEvents()
}

# --- Sauvegarde / chargement de la sélection ---
function Save-Selection {
    $sel = foreach ($it in $AllItems) {
        if (-not $it.Checked) { continue }
        [pscustomobject]@{ Categorie = $it.Tag; Nom = $it.Text; Id = $it.SubItems[1].Text }
    }
    ConvertTo-Json @($sel) | Set-Content -Path $ProfilePath -Encoding UTF8
}

function Load-Selection {
    if (-not (Test-Path $ProfilePath)) { return }
    try {
        $sel = Get-Content $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($s in $sel) { Add-App $s.Categorie $s.Nom $s.Id $true }
        Write-Log "Sélection chargée depuis ma-selection.json ($(@($sel).Count) logiciels)."
    } catch { Write-Log "Impossible de lire ma-selection.json : $_" }
}

# --- Exécute winget sans figer la fenêtre, renvoie le code de sortie ---
function Invoke-Winget([string]$arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'winget'
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    while (-not $p.HasExited) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.ExitCode
}

function Set-Busy([bool]$busy) {
    foreach ($b in @($btnInstall, $btnUpgrade, $btnAll, $btnNone, $btnSave, $searchBtn, $filterBox)) { $b.Enabled = -not $busy }
    $list.Enabled = -not $busy
}

# --- Repère les logiciels déjà installés (winget export donne des IDs exacts) ---
function Update-InstalledStatus {
    Set-Busy $true
    $progress.Style = 'Marquee'
    Write-Log 'Recherche des logiciels déjà installés...'
    $tmp = Join-Path $env:TEMP "autoinstall-export-$PID.json"
    [void](Invoke-Winget "export -o `"$tmp`" --source winget --accept-source-agreements")
    $InstalledIds.Clear()
    if (Test-Path $tmp) {
        try {
            $data = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($src in $data.Sources) { foreach ($p in $src.Packages) { [void]$InstalledIds.Add($p.PackageIdentifier) } }
        } catch { Write-Log "Impossible de lire la liste des logiciels installés : $_" }
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $n = 0
    foreach ($it in $AllItems) {
        if ($InstalledIds.Contains($it.SubItems[1].Text)) { $it.SubItems[2].Text = 'Déjà installé'; $n++ }
    }
    Write-Log "$n logiciel(s) de la liste déjà installé(s) sur ce PC."
    $progress.Style = 'Blocks'
    Set-Busy $false
}

# --- Recherche dans tout le catalogue winget ---
function Search-Winget([string]$query) {
    $out = & winget search $query --source winget --accept-source-agreements 2>$null
    $lines = @($out | ForEach-Object { "$_" -replace '^.*\r', '' })
    $sep = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{10,}') { $sep = $i; break } }
    if ($sep -lt 1) { return @() }
    $header = $lines[$sep - 1]
    $starts = @([regex]::Matches($header, '\S+') | ForEach-Object { $_.Index })
    if ($starts.Count -lt 3) { return @() }
    $results = for ($i = $sep + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Length -lt $starts[2]) { continue }
        $name = $l.Substring(0, $starts[1]).Trim()
        $id   = $l.Substring($starts[1], $starts[2] - $starts[1]).Trim()
        $ver  = $l.Substring($starts[2], [Math]::Min($l.Length, $(if ($starts.Count -gt 3) { $starts[3] } else { $l.Length })) - $starts[2]).Trim()
        if ($id) { [pscustomobject]@{ Nom = $name; Id = $id; Version = $ver } }
    }
    @($results)
}

$searchAction = {
    $q = $searchBox.Text.Trim()
    if (-not $q) { return }
    $form.Cursor = 'WaitCursor'
    Write-Log "Recherche de « $q »..."
    $res = Search-Winget $q
    $form.Cursor = 'Default'
    if ($res.Count -eq 0) { Write-Log 'Aucun résultat.'; return }

    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = "Résultats pour « $q » - coche et valide"
    $dlg.Size = New-Object Drawing.Size(700, 450)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = $form.Font
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true
    $lv.Dock = 'Fill'
    [void]$lv.Columns.Add('Nom', 260); [void]$lv.Columns.Add('ID winget', 280); [void]$lv.Columns.Add('Version', 110)
    foreach ($r in $res) {
        $it = New-Object Windows.Forms.ListViewItem($r.Nom)
        [void]$it.SubItems.Add($r.Id); [void]$it.SubItems.Add($r.Version)
        [void]$lv.Items.Add($it)
    }
    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'Ajouter à ma liste'; $ok.Dock = 'Bottom'; $ok.Height = 36
    $ok.DialogResult = 'OK'
    $dlg.Controls.Add($lv); $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok
    if ($dlg.ShowDialog($form) -eq 'OK') {
        foreach ($it in $lv.CheckedItems) {
            Add-App 'Ajoutés par moi' $it.Text $it.SubItems[1].Text $true
            Write-Log "Ajouté : $($it.Text) ($($it.SubItems[1].Text))"
        }
        Save-Selection
    }
}
$searchBtn.Add_Click($searchAction)
$searchBox.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $searchAction } })
$filterBox.Add_TextChanged({ Update-Filter })

# --- Boutons ---
$btnAll.Add_Click({ foreach ($it in $list.Items) { $it.Checked = $true } })
$btnNone.Add_Click({ foreach ($it in $list.Items) { $it.Checked = $false } })
$btnSave.Add_Click({ Save-Selection; Write-Log "Sélection sauvegardée dans $ProfilePath" })

$btnUpgrade.Add_Click({
    Set-Busy $true
    Write-Log 'Mise à jour de tous les logiciels installés (winget upgrade --all)...'
    $progress.Style = 'Marquee'
    $code = Invoke-Winget 'upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown'
    $progress.Style = 'Blocks'
    Write-Log "Mise à jour terminée (code $code)."
    Set-Busy $false
})

$btnInstall.Add_Click({
    $items = @($AllItems | Where-Object { $_.Checked })
    if ($items.Count -eq 0) { Write-Log 'Rien de coché.'; return }
    $filterBox.Text = ''   # tout réafficher pour suivre la progression
    Save-Selection
    Set-Busy $true
    $progress.Style = 'Blocks'
    $progress.Maximum = $items.Count
    $progress.Value = 0
    $ok = 0; $fail = @()
    foreach ($it in $items) {
        $id = $it.SubItems[1].Text
        $it.SubItems[2].Text = 'Installation...'
        $it.EnsureVisible()
        Write-Log "Installation de $($it.Text)..."
        $code = Invoke-Winget "install --id `"$id`" --exact --source winget --silent --accept-package-agreements --accept-source-agreements"
        switch ($code) {
            0           { $it.SubItems[2].Text = 'Installé ✔'; $ok++ }
            -1978335189 { $it.SubItems[2].Text = 'Déjà à jour ✔'; $ok++ }   # 0x8A15002B
            -1978335135 { $it.SubItems[2].Text = 'Déjà installé ✔'; $ok++ } # 0x8A150061
            -1978335212 { $it.SubItems[2].Text = 'Introuvable ✖'; $fail += $it.Text } # 0x8A150014
            default     { $it.SubItems[2].Text = "Erreur ($code) ✖"; $fail += $it.Text }
        }
        Write-Log "  -> $($it.SubItems[2].Text)"
        $progress.Value++
    }
    Write-Log "Terminé : $ok réussi(s), $($fail.Count) échec(s)."
    if ($fail.Count) { Write-Log ("Échecs : " + ($fail -join ', ')) }
    Set-Busy $false
    [void][Windows.Forms.MessageBox]::Show("Terminé !`n$ok réussi(s), $($fail.Count) échec(s).", 'AutoInstall')
})

$form.Add_FormClosing({ Save-Selection })

# --- Démarrage ---
$form.Add_Shown({
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [void][Windows.Forms.MessageBox]::Show("winget n'est pas encore disponible.`nOuvre le Microsoft Store, mets à jour « App Installer », puis relance AutoInstall.", 'AutoInstall', 'OK', 'Warning')
        Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        $form.Close()
        return
    }
    Load-Selection
    Update-InstalledStatus
    Write-Log 'Prêt. winget installera toujours la dernière version disponible.'
})

[void]$form.ShowDialog()
