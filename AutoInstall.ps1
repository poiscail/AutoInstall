# AutoInstall - installe tes logiciels en dernière version via winget
# Lancer avec Lancer.bat (demande les droits admin automatiquement)
# Ligne de commande : AutoInstall.ps1 -Aide

param(
    [string]$Profil,
    [string]$Fichier,
    [switch]$Installer,
    [switch]$MettreAJour,
    [switch]$ToutMettreAJour,
    [switch]$Liste,
    [switch]$Redemarrer,
    [switch]$Silencieux,
    [switch]$Aide,
    [switch]$Relance
)

$ScriptDir = Split-Path -Parent $PSCommandPath
$CliMode = $Installer -or $MettreAJour -or $ToutMettreAJour -or $Liste

$CliHelp = @'
AutoInstall - ligne de commande

  powershell -ExecutionPolicy Bypass -File AutoInstall.ps1 [options]

  -Installer          installe les logiciels du profil
  -MettreAJour        met à jour les logiciels du profil déjà installés
  -ToutMettreAJour    met à jour tous les logiciels du PC
  -Liste              affiche le profil et ce qui est installé
  -Profil <nom>       profil à utiliser (par défaut : le dernier ouvert)
  -Fichier <chemin>   utilise un fichier de sélection (ou un « winget export »)
  -Redemarrer         redémarre le PC à la fin (dans 60 secondes)
  -Silencieux         aucune fenêtre, tout est écrit dans le dossier journaux
  -Aide               affiche cette aide

Sans option, la fenêtre s'ouvre.
Exemple : AutoInstall.ps1 -Profil Jeux -Installer -Silencieux -Redemarrer
'@

if ($Aide) {
    Write-Host $CliHelp
    if ($Relance) { [void](Read-Host 'Appuie sur Entrée pour fermer') }
    exit
}

# --- Relance en administrateur si besoin (en gardant les options) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $CliMode -or $Silencieux) { $argList += '-WindowStyle', 'Hidden' }
    $argList += '-File', "`"$PSCommandPath`"", '-Relance'
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value) { $argList += "-$($kv.Key)" } }
        else { $argList += "-$($kv.Key)", "`"$($kv.Value)`"" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $ScriptDir 'lib\Core.ps1')
. (Join-Path $ScriptDir 'lib\Outils.ps1')
$Settings = Read-Settings

# =====================================================================
# Ligne de commande / mode sans fenêtre
# =====================================================================
if ($CliMode) {
    $script:Quiet = [bool]$Silencieux
    $exitCode = 0
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Log "winget est introuvable. Mets à jour « App Installer » depuis le Microsoft Store."; exit 1 }
    [void](Get-ProfileNames)
    $source = if ($Fichier) { $Fichier } else { Get-ProfilePath $(if ($Profil) { $Profil } else { $Settings.Profil }) }
    if (-not (Test-Path $source)) {
        if ($Fichier) { Write-Log "Fichier introuvable : $source" }
        else { Write-Log "Le profil « $([IO.Path]::GetFileNameWithoutExtension($source)) » n'existe pas encore. Ouvre la fenêtre, coche tes logiciels puis enregistre le profil (profils existants : $((Get-ChildItem $ProfileDir -Filter *.json -File | ForEach-Object BaseName) -join ', '))." }
        if ($Relance -and -not $Silencieux) { [void](Read-Host 'Appuie sur Entrée pour fermer') }
        exit 1
    }
    $entries = @(Read-SelectionFile $source)
    Write-Log "Sélection : $source ($($entries.Count) logiciels)"
    $installed = Get-InstalledPackages
    foreach ($e in $entries) { $e | Add-Member -NotePropertyName Installe -NotePropertyValue $installed.ContainsKey($e.Id) }

    if ($Liste) {
        foreach ($e in $entries) {
            Write-Log ('{0,-32} {1,-40} {2}' -f $e.Nom, $e.Id, $(if ($e.Installe) { "installé $($installed[$e.Id])" } else { 'non installé' }))
        }
    }
    $opts = @{
        SauterInstalles = $Settings.SauterInstalles; RuntimesDabord = $Settings.RuntimesDabord
        PointRestauration = $Settings.PointRestauration; SupprimerRaccourcis = $Settings.SupprimerRaccourcis; Dossier = $Settings.Dossier
    }
    if ($Installer -or $MettreAJour -or $ToutMettreAJour) {
        $err = Test-Prerequisites $Settings.Dossier
        if ($err) { Write-Log $err; exit 1 }
    }
    if ($Installer) {
        $res = Invoke-PackageBatch $entries 'install' $opts
        if (@($res | Where-Object { -not $_.Resultat.Ok }).Count) { $exitCode = 1 }
    }
    if ($MettreAJour) {
        $res = Invoke-PackageBatch @($entries | Where-Object Installe) 'upgrade' $opts
        if (@($res | Where-Object { -not $_.Resultat.Ok }).Count) { $exitCode = 1 }
    }
    if ($ToutMettreAJour) {
        Write-Log 'Mise à jour de tous les logiciels du PC...'
        $r = Get-WingetResult (Invoke-Winget 'upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --include-unknown') 'upgrade'
        Write-Log "Mise à jour générale : $($r.Status)"
    }
    if ($Redemarrer) { Restart-ComputerSoon }
    if ($Relance -and -not $Silencieux) { [void](Read-Host 'Appuie sur Entrée pour fermer') }
    exit $exitCode
}

# =====================================================================
# Fenêtre
# =====================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Gui = $true

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
public class AutoInstallSorter : System.Collections.IComparer {
    public int Column;
    public bool Descending;
    public int Compare(object a, object b) {
        var x = (System.Windows.Forms.ListViewItem)a;
        var y = (System.Windows.Forms.ListViewItem)b;
        string tx = Column < x.SubItems.Count ? x.SubItems[Column].Text : "";
        string ty = Column < y.SubItems.Count ? y.SubItems[Column].Text : "";
        int r = string.Compare(tx, ty, System.StringComparison.CurrentCultureIgnoreCase);
        return Descending ? -r : r;
    }
}
'@

$C_ID = 1; $C_INST = 2; $C_DISPO = 3; $C_STATUT = 4
$ColumnTitles = @('Logiciel', 'ID winget', 'Installée', 'Disponible', 'Statut')

$Themes = @{
    Clair  = @{ Back = [Drawing.SystemColors]::Window; Panel = [Drawing.SystemColors]::Control; Fore = [Drawing.SystemColors]::ControlText
                Muted = [Drawing.Color]::DimGray; ok = [Drawing.Color]::FromArgb(0, 128, 0); err = [Drawing.Color]::FromArgb(190, 30, 30)
                warn = [Drawing.Color]::FromArgb(200, 100, 0); info = [Drawing.Color]::FromArgb(0, 90, 180) }
    Sombre = @{ Back = [Drawing.Color]::FromArgb(32, 32, 32); Panel = [Drawing.Color]::FromArgb(45, 45, 48); Fore = [Drawing.Color]::FromArgb(230, 230, 230)
                Muted = [Drawing.Color]::FromArgb(150, 150, 150); ok = [Drawing.Color]::FromArgb(110, 200, 110); err = [Drawing.Color]::FromArgb(240, 110, 110)
                warn = [Drawing.Color]::FromArgb(240, 170, 60); info = [Drawing.Color]::FromArgb(110, 170, 255) }
}
$script:T = $Themes['Clair']

$script:InstalledMap   = @{}
$script:UpgradeMap     = @{}
$script:LastFailed     = @()
$script:LastAction     = 'install'
$script:Busy           = $false
$script:Loading        = $true
$script:CurrentProfile = 'Principal'

# --- Fenêtre principale ---
$form = New-Object Windows.Forms.Form
$form.Text = 'AutoInstall - réinstalle tes logiciels en un clic'
$icoPath = Join-Path $ScriptDir 'AutoInstall.ico'
if (Test-Path $icoPath) { try { $form.Icon = New-Object Drawing.Icon($icoPath) } catch { } }
$form.Size = New-Object Drawing.Size(1020, 780)
$form.MinimumSize = New-Object Drawing.Size(880, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$BoldFont = New-Object Drawing.Font($form.Font, [Drawing.FontStyle]::Bold)

# Barre du haut : profil, recherche winget, filtre
$top = New-Object Windows.Forms.Panel
$top.Dock = 'Top'
$top.Height = 70

function New-Label([string]$text, [int]$x, [int]$y, $parent) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object Drawing.Point($x, $y)
    $l.AutoSize = $true
    $parent.Controls.Add($l)
    $l
}

[void](New-Label 'Profil :' 12 11 $top)
$profileBox = New-Object Windows.Forms.ComboBox
$profileBox.DropDownStyle = 'DropDownList'
$profileBox.Location = New-Object Drawing.Point(70, 8)
$profileBox.Size = New-Object Drawing.Size(170, 26)

$searchBox = New-Object Windows.Forms.TextBox
$searchBox.Location = New-Object Drawing.Point(260, 8)
$searchBox.Size = New-Object Drawing.Size(300, 26)

$searchBtn = New-Object Windows.Forms.Button
$searchBtn.Text = 'Chercher un autre logiciel'
$searchBtn.Location = New-Object Drawing.Point(568, 6)
$searchBtn.Size = New-Object Drawing.Size(200, 28)

[void](New-Label 'Filtrer :' 12 43 $top)
$filterBox = New-Object Windows.Forms.TextBox
$filterBox.Location = New-Object Drawing.Point(70, 40)
$filterBox.Size = New-Object Drawing.Size(170, 26)

$filterLabel = New-Label 'Coche ce que tu veux, puis « Installer ». Clic droit sur un logiciel pour plus d''options.' 260 43 $top
$top.Controls.AddRange(@($profileBox, $searchBox, $searchBtn, $filterBox))

# Liste des logiciels
$list = New-Object Windows.Forms.ListView
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.ShowGroups = $true
$list.ShowItemToolTips = $true
$list.HideSelection = $false
$list.Dock = 'Fill'
foreach ($w in @(@('Logiciel', 270), @('ID winget', 250), @('Installée', 95), @('Disponible', 95), @('Statut', 220))) { [void]$list.Columns.Add($w[0], $w[1]) }

$Images = New-Object Windows.Forms.ImageList
$Images.ColorDepth = 'Depth32Bit'
$Images.ImageSize = New-Object Drawing.Size(16, 16)
$list.SmallImageList = $Images

$splitter = New-Object Windows.Forms.Splitter
$splitter.Dock = 'Bottom'
$splitter.Height = 5

# Bas : options, journal, progression, boutons
$bottom = New-Object Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 290
$bottom.Padding = New-Object Windows.Forms.Padding(8, 4, 8, 4)

$optFlow = New-Object Windows.Forms.FlowLayoutPanel
$optFlow.Dock = 'Top'
$optFlow.AutoSize = $true
$optFlow.WrapContents = $true

function New-Check([string]$text, [bool]$checked, [string]$tip) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $text
    $c.Checked = $checked
    $c.AutoSize = $true
    $c.Margin = New-Object Windows.Forms.Padding(3, 4, 12, 2)
    $tips.SetToolTip($c, $tip)
    $optFlow.Controls.Add($c)
    $c
}
$tips = New-Object Windows.Forms.ToolTip
$chkSkip      = New-Check 'Sauter les déjà installés'        ([bool]$Settings.SauterInstalles)     'Ne relance pas l''installation des logiciels déjà présents.'
$chkRuntimes  = New-Check 'Runtimes en premier'              ([bool]$Settings.RuntimesDabord)      'Installe Visual C++, .NET, Java, DirectX avant le reste.'
$chkRestore   = New-Check 'Point de restauration avant'      ([bool]$Settings.PointRestauration)   'Crée un point de restauration Windows avant de commencer.'
$chkShortcuts = New-Check 'Supprimer les nouveaux raccourcis du bureau' ([bool]$Settings.SupprimerRaccourcis) 'Met à la corbeille les raccourcis créés sur le bureau pendant l''installation.'
$chkReboot    = New-Check 'Redémarrer à la fin'              ([bool]$Settings.Redemarrer)          'Redémarre le PC 60 secondes après la fin de l''installation.'

$folderLabel = New-Object Windows.Forms.Label
$folderLabel.Text = 'Dossier d''installation :'
$folderLabel.AutoSize = $true
$folderLabel.Margin = New-Object Windows.Forms.Padding(3, 7, 3, 0)
$folderBox = New-Object Windows.Forms.TextBox
$folderBox.ReadOnly = $true
$folderBox.Width = 260
$folderBox.Text = "$($Settings.Dossier)"
$tips.SetToolTip($folderBox, 'Vide = emplacement par défaut. Certains installeurs ignorent ce choix.')
$btnFolder = New-Object Windows.Forms.Button
$btnFolder.Text = 'Choisir...'
$btnFolder.AutoSize = $true
$btnFolderClear = New-Object Windows.Forms.Button
$btnFolderClear.Text = 'Par défaut'
$btnFolderClear.AutoSize = $true
$optFlow.Controls.AddRange(@($folderLabel, $folderBox, $btnFolder, $btnFolderClear))
$optFlow.SetFlowBreak($chkReboot, $true)

$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Font = New-Object Drawing.Font('Consolas', 9)
$log.Dock = 'Fill'

$progress = New-Object Windows.Forms.ProgressBar
$progress.Dock = 'Bottom'
$progress.Height = 16

function New-Row {
    $r = New-Object Windows.Forms.FlowLayoutPanel
    $r.Dock = 'Bottom'
    $r.Height = 42
    $r.Padding = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $r
}
function New-Btn([string]$text, $row, [string]$tip) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.AutoSize = $true
    $b.MinimumSize = New-Object Drawing.Size(0, 32)
    $b.Padding = New-Object Windows.Forms.Padding(4, 0, 4, 0)
    if ($tip) { $tips.SetToolTip($b, $tip) }
    $row.Controls.Add($b)
    $b
}
$row1 = New-Row
$btnAll         = New-Btn 'Tout cocher'            $row1 'Coche tout ce qui est affiché.'
$btnNone        = New-Btn 'Tout décocher'          $row1 'Décoche tout ce qui est affiché.'
$btnInstalled   = New-Btn 'Cocher l''installé'     $row1 'Coche tout ce qui est déjà installé sur ce PC (pour le réinstaller ailleurs).'
$btnRecommended = New-Btn 'Cocher les recommandés' $row1 'Coche les essentiels (en gras dans la liste).'
$btnCheckUpd    = New-Btn 'Vérifier les mises à jour' $row1 'Relit ce qui est installé et les nouvelles versions disponibles.'
$btnUninstall   = New-Btn 'Désinstaller la sélection' $row1 'Désinstalle les logiciels cochés.'

$row2 = New-Row
$row2.Height = 46
$btnUpdSel  = New-Btn 'Mettre à jour la sélection' $row2 'Met à jour les logiciels cochés qui ont une nouvelle version.'
$btnUpgrade = New-Btn 'Tout mettre à jour'         $row2 'Met à jour tous les logiciels du PC (winget upgrade --all).'
$btnRetry   = New-Btn 'Réessayer les échecs'       $row2 'Relance uniquement ce qui a échoué la dernière fois.'
$btnCancel  = New-Btn 'Annuler'                    $row2 'Arrête après le logiciel en cours (deuxième clic : arrêt immédiat).'
$btnRetry.Enabled = $false
$btnCancel.Enabled = $false

$btnInstall = New-Object Windows.Forms.Button
$btnInstall.Text = 'Installer la sélection'
$btnInstall.Dock = 'Right'
$btnInstall.Width = 230
$btnInstall.BackColor = [Drawing.Color]::FromArgb(0, 120, 212)
$btnInstall.ForeColor = [Drawing.Color]::White
$btnInstall.FlatStyle = 'Flat'
$btnInstall.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$installHolder = New-Object Windows.Forms.Panel
$installHolder.Dock = 'Right'
$installHolder.Width = 236
$installHolder.Padding = New-Object Windows.Forms.Padding(6, 6, 0, 2)
$installHolder.Controls.Add($btnInstall)
$row2.Dock = 'Fill'
$row2Holder = New-Object Windows.Forms.Panel
$row2Holder.Dock = 'Bottom'
$row2Holder.Height = 46
$row2Holder.Controls.Add($row2)
$row2Holder.Controls.Add($installHolder)

$bottom.Controls.Add($log)
$bottom.Controls.Add($optFlow)
$bottom.Controls.Add($progress)
$bottom.Controls.Add($row1)
$bottom.Controls.Add($row2Holder)

# Barre d'état
$status = New-Object Windows.Forms.StatusStrip
$lblCount = New-Object Windows.Forms.ToolStripStatusLabel
$lblEta = New-Object Windows.Forms.ToolStripStatusLabel
$lblEta.Spring = $true
$lblEta.TextAlign = 'MiddleLeft'
$lblDisk = New-Object Windows.Forms.ToolStripStatusLabel
[void]$status.Items.AddRange(@($lblCount, $lblEta, $lblDisk))

# Menu
$menu = New-Object Windows.Forms.MenuStrip
function Add-Menu($parent, [string]$text, [scriptblock]$action) {
    if ($text -eq '-') { [void]$parent.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator)); return }
    $mi = New-Object Windows.Forms.ToolStripMenuItem($text)
    if ($action) { $mi.Add_Click($action) }
    if ($parent -is [Windows.Forms.MenuStrip]) { [void]$parent.Items.Add($mi) } else { [void]$parent.DropDownItems.Add($mi) }
    $mi
}
$mFile  = Add-Menu $menu 'Fichier' $null
$mTools = Add-Menu $menu 'Outils' $null
$mView  = Add-Menu $menu 'Affichage' $null
$mHelp  = Add-Menu $menu 'Aide' $null

$form.Controls.Add($list)
$form.Controls.Add($splitter)
$form.Controls.Add($bottom)
$form.Controls.Add($status)
$form.Controls.Add($top)
$form.Controls.Add($menu)
$form.MainMenuStrip = $menu

$BusyControls = @($list, $profileBox, $searchBox, $searchBtn, $filterBox, $optFlow, $menu,
    $btnAll, $btnNone, $btnInstalled, $btnRecommended, $btnCheckUpd, $btnUninstall, $btnUpdSel, $btnUpgrade, $btnInstall)

# =====================================================================
# Journal et état
# =====================================================================
$script:LogSink = {
    param($line)
    $log.AppendText("$line`r`n")
    [Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool]$busy) {
    $script:Busy = $busy
    foreach ($c in $BusyControls) { $c.Enabled = -not $busy }
    $btnCancel.Enabled = $busy
    $btnCancel.Text = 'Annuler'
    $btnRetry.Enabled = (-not $busy) -and $LastFailed.Count -gt 0
    if (-not $busy) { $lblEta.Text = ''; Update-DiskLabel }
}

function Update-DiskLabel {
    $free = Get-FreeSpaceGB $folderBox.Text
    $lblDisk.Text = if ($free -ge 0) { "Espace libre : $free Go" } else { '' }
    $lblDisk.ForeColor = if ($free -ge 0 -and $free -lt 10) { $T.err } else { $T.Fore }
}

function Update-Counter {
    $n = 0
    foreach ($it in $AllItems) { if ($it.Checked) { $n++ } }
    $lblCount.Text = "$n coché(s) sur $($AllItems.Count)"
}
$countTimer = New-Object Windows.Forms.Timer
$countTimer.Interval = 150
$countTimer.Add_Tick({ $countTimer.Stop(); Update-Counter })
$list.Add_ItemChecked({ $countTimer.Stop(); $countTimer.Start() })

# =====================================================================
# Éléments de la liste
# =====================================================================
$groups = @{}
function Get-Group([string]$name) {
    if (-not $groups.ContainsKey($name)) {
        $g = New-Object Windows.Forms.ListViewGroup($name, $name)
        [void]$list.Groups.Add($g)
        $groups[$name] = $g
    }
    $groups[$name]
}

# Tous les logiciels, y compris ceux masqués par le filtre
$AllItems = New-Object Collections.Generic.List[Windows.Forms.ListViewItem]

function Set-Status($it, [string]$text, [string]$kind = '') {
    $it.Tag.Etat = $kind
    $it.SubItems[$C_STATUT].Text = $text
    $it.SubItems[$C_STATUT].ForeColor = if ($kind) { $T[$kind] } else { $T.Fore }
}

# Met à jour les colonnes Installée / Disponible, l'infobulle et (sauf -KeepStatus) le statut
function Update-ItemState($it, [switch]$KeepStatus) {
    $tag = $it.Tag
    $iv = Find-ById $InstalledMap $tag.Id
    $av = Find-ById $UpgradeMap $tag.Id
    $tag.Installe = $null -ne $iv
    $it.SubItems[$C_INST].Text = if ($tag.Installe) { $(if ($iv) { $iv } else { 'oui' }) } else { '' }
    $it.SubItems[$C_DISPO].Text = "$av"
    $tip = @()
    if ($tag.Description) { $tip += $tag.Description }
    if ($tag.Recommande) { $tip += '★ Recommandé' }
    if ($tag.Version) { $tip += "Version choisie : $($tag.Version)" }
    if ($tag.Site) { $tip += "Site : $($tag.Site)" }
    if ($tag.Explication) { $tip += "Dernier problème : $($tag.Explication)" }
    $tip += 'Clic droit : site officiel, version, catégorie...'
    $it.ToolTipText = $tip -join "`n"
    if ($KeepStatus) { return }
    if ($av) { Set-Status $it 'Mise à jour dispo' 'warn' }
    elseif ($tag.Installe) { Set-Status $it 'Déjà installé' 'ok' }
    elseif ($tag.Version) { Set-Status $it "Version $($tag.Version) demandée" 'info' }
    else { Set-Status $it '' }
}

function Test-Filter($it) {
    $f = $filterBox.Text.Trim()
    (-not $f) -or $it.Text -like "*$f*" -or $it.Tag.Id -like "*$f*" -or $it.Tag.Categorie -like "*$f*" -or $it.Tag.Description -like "*$f*"
}

function Update-Filter {
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($it in $AllItems) {
        if (Test-Filter $it) {
            [void]$list.Items.Add($it)
            $it.Group = Get-Group $it.Tag.Categorie
        }
    }
    $list.EndUpdate()
}

function Add-App([string]$cat, [string]$name, [string]$id, [bool]$checked = $false, [hashtable]$meta = @{}) {
    foreach ($it in $AllItems) {
        if ($it.Tag.Id -eq $id) {
            if ($checked) { $it.Checked = $true }
            if ($meta.Version) { $it.Tag.Version = $meta.Version; Update-ItemState $it }
            return $it
        }
    }
    $item = New-Object Windows.Forms.ListViewItem($name)
    $item.UseItemStyleForSubItems = $false
    foreach ($i in 1..4) { [void]$item.SubItems.Add('') }
    $item.SubItems[$C_ID].Text = $id
    $item.Tag = [pscustomobject]@{ Categorie = $cat; Id = $id; Description = ''; Site = ''; Recommande = $false; Version = ''
                                   Installe = $false; Perso = $true; Etat = ''; Explication = '' }
    foreach ($k in $meta.Keys) { $item.Tag.$k = $meta[$k] }
    if ($item.Tag.Recommande) { $item.Font = $BoldFont }
    $item.Checked = $checked
    $AllItems.Add($item)
    Update-ItemState $item
    Set-ItemIcon $item
    if (Test-Filter $item) {
        [void]$list.Items.Add($item)
        $item.Group = Get-Group $cat
    }
    $item
}

function Get-CheckedEntries {
    @(foreach ($it in $AllItems) {
        if (-not $it.Checked) { continue }
        [pscustomobject]@{ Categorie = $it.Tag.Categorie; Nom = $it.Text; Id = $it.Tag.Id; Version = $it.Tag.Version; Installe = $it.Tag.Installe; Item = $it }
    })
}

# =====================================================================
# Icônes : pastille de couleur tout de suite, puis l'icône du site (mise en cache)
# =====================================================================
$IconDir = Join-Path $CachePath 'icones'
$IconQueue = New-Object Collections.Queue
$IconJobs = New-Object Collections.ArrayList
$BadgeColors = @('#0078D4', '#E81123', '#107C10', '#FF8C00', '#5C2D91', '#008575', '#C239B3', '#767676', '#004E8C', '#B4009E', '#498205')

function Get-BadgeKey($it) {
    $letter = "$($it.Text.Trim())".Substring(0, 1).ToUpper()
    $cat = $it.Tag.Categorie
    $key = "pastille|$letter|$cat"
    if (-not $Images.Images.ContainsKey($key)) {
        $sum = 0; foreach ($ch in $cat.ToCharArray()) { $sum += [int]$ch }
        $color = [Drawing.ColorTranslator]::FromHtml($BadgeColors[$sum % $BadgeColors.Count])
        $bmp = New-Object Drawing.Bitmap(16, 16)
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $g.FillEllipse((New-Object Drawing.SolidBrush($color)), 0, 0, 15, 15)
        $sf = New-Object Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $g.DrawString($letter, (New-Object Drawing.Font('Segoe UI', 7, [Drawing.FontStyle]::Bold)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(0, 1, 16, 16)), $sf)
        $g.Dispose()
        $Images.Images.Add($key, $bmp)
    }
    $key
}

function Add-IconImage([string]$key, [string]$path) {
    try {
        $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($path))
        $img = [Drawing.Image]::FromStream($ms)
        $Images.Images.Add($key, (New-Object Drawing.Bitmap($img, 16, 16)))
        $true
    } catch { $false }
}

function Get-IconPath($it) { Join-Path $IconDir (($it.Tag.Id -replace '[\\/:*?"<>|]', '_') + '.png') }

function Set-ItemIcon($it) {
    $key = "icone|$($it.Tag.Id)"
    if ($Images.Images.ContainsKey($key)) { $it.ImageKey = $key; return }
    $png = Get-IconPath $it
    if ((Test-Path $png) -and (Add-IconImage $key $png)) { $it.ImageKey = $key; return }
    $it.ImageKey = Get-BadgeKey $it
    if ($it.Tag.Site -and -not (Test-Path "$png.aucune")) { $IconQueue.Enqueue($it) }
}

$iconTimer = New-Object Windows.Forms.Timer
$iconTimer.Interval = 250
$iconTimer.Add_Tick({
    for ($k = $IconJobs.Count - 1; $k -ge 0; $k--) {
        $job = $IconJobs[$k]
        if (-not $job.Task.IsCompleted) { continue }
        $IconJobs.RemoveAt($k)
        $job.Client.Dispose()
        $key = "icone|$($job.Item.Tag.Id)"
        if (-not $job.Task.IsFaulted -and (Test-Path $job.Path) -and (Add-IconImage $key $job.Path)) { $job.Item.ImageKey = $key }
        else {
            Remove-Item $job.Path -ErrorAction SilentlyContinue
            [void](New-Item -ItemType File -Path "$($job.Path).aucune" -Force)
        }
    }
    while ($IconJobs.Count -lt 6 -and $IconQueue.Count -gt 0) {
        $it = $IconQueue.Dequeue()
        try { $domain = ([Uri]$it.Tag.Site).Host } catch { continue }
        if (-not (Test-Path $IconDir)) { [void](New-Item -ItemType Directory -Path $IconDir) }
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = 'AutoInstall'
        $path = Get-IconPath $it
        $task = $wc.DownloadFileTaskAsync("https://www.google.com/s2/favicons?domain=$domain&sz=32", $path)
        [void]$IconJobs.Add(@{ Task = $task; Client = $wc; Path = $path; Item = $it })
    }
    if ($IconJobs.Count -eq 0 -and $IconQueue.Count -eq 0) { $iconTimer.Stop() }
})

# =====================================================================
# Thème clair / sombre
# =====================================================================
function Set-ThemeColors($c) {
    if ($c -eq $btnInstall) { return }
    switch ($c.GetType().Name) {
        { $_ -in 'TextBox', 'ListView', 'ComboBox', 'ListBox' } { $c.BackColor = $T.Back; $c.ForeColor = $T.Fore }
        'Button' {
            if ($T -eq $Themes.Sombre) { $c.FlatStyle = 'Flat'; $c.BackColor = $T.Back; $c.ForeColor = $T.Fore; $c.FlatAppearance.BorderColor = $T.Muted }
            else { $c.FlatStyle = 'Standard'; $c.BackColor = $T.Panel; $c.ForeColor = $T.Fore; $c.UseVisualStyleBackColor = $true }
        }
        default { $c.BackColor = $T.Panel; $c.ForeColor = $T.Fore }
    }
    foreach ($child in $c.Controls) { Set-ThemeColors $child }
}

function Set-MenuColors($items) {
    foreach ($mi in $items) {
        $mi.BackColor = $T.Panel
        $mi.ForeColor = $T.Fore
        if ($mi -is [Windows.Forms.ToolStripMenuItem]) { Set-MenuColors $mi.DropDownItems }
    }
}

function Set-Theme([string]$name) {
    if (-not $Themes.ContainsKey($name)) { $name = 'Clair' }
    $script:T = $Themes[$name]
    $Settings.Theme = $name
    $form.BackColor = $T.Panel
    $form.ForeColor = $T.Fore
    foreach ($c in $form.Controls) { Set-ThemeColors $c }
    foreach ($s in @($menu, $status, $listMenu)) { $s.BackColor = $T.Panel; $s.ForeColor = $T.Fore; Set-MenuColors $s.Items }
    $filterLabel.ForeColor = $T.Muted
    foreach ($it in $AllItems) {
        foreach ($sub in $it.SubItems) { $sub.BackColor = $T.Back; $sub.ForeColor = $T.Fore }
        Set-Status $it $it.SubItems[$C_STATUT].Text $it.Tag.Etat
    }
    $miDark.Checked = ($name -eq 'Sombre')
    Update-DiskLabel
}

# Applique les mêmes couleurs aux petites fenêtres
function Set-DialogTheme($dlg) {
    $dlg.BackColor = $T.Panel
    $dlg.ForeColor = $T.Fore
    foreach ($c in $dlg.Controls) { Set-ThemeColors $c }
}

# =====================================================================
# Petites fenêtres réutilisables
# =====================================================================
function New-Dialog([string]$title, [int]$w, [int]$h) {
    $d = New-Object Windows.Forms.Form
    $d.Text = $title
    $d.Size = New-Object Drawing.Size($w, $h)
    $d.StartPosition = 'CenterParent'
    $d.Font = $form.Font
    $d.MinimizeBox = $false
    $d.ShowInTaskbar = $false
    $d
}

function New-DialogButtons($dlg, [string]$okText) {
    $p = New-Object Windows.Forms.FlowLayoutPanel
    $p.Dock = 'Bottom'
    $p.FlowDirection = 'RightToLeft'
    $p.Height = 44
    $p.Padding = New-Object Windows.Forms.Padding(6)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Annuler'; $cancel.DialogResult = 'Cancel'; $cancel.AutoSize = $true
    $ok = New-Object Windows.Forms.Button
    $ok.Text = $okText; $ok.DialogResult = 'OK'; $ok.AutoSize = $true
    $p.Controls.AddRange(@($cancel, $ok))
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $p
}

function New-Intro([string]$text) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Dock = 'Top'
    $l.Height = 48
    $l.Padding = New-Object Windows.Forms.Padding(8, 8, 8, 0)
    $l
}

# Liste à cocher. $rows : objets { Text, Detail, Checked }. Renvoie l'état des cases, ou $null si annulé.
function Show-CheckDialog([string]$title, [string]$intro, $rows, [string]$okText = 'Appliquer') {
    $dlg = New-Dialog $title 700 520
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Dock = 'Fill'; $lv.ShowItemToolTips = $true
    [void]$lv.Columns.Add('Élément', 320); [void]$lv.Columns.Add('Détail', 330)
    foreach ($r in $rows) {
        $it = New-Object Windows.Forms.ListViewItem([string]$r.Text)
        [void]$it.SubItems.Add([string]$r.Detail)
        $it.ToolTipText = [string]$r.Detail
        $it.Checked = [bool]$r.Checked
        [void]$lv.Items.Add($it)
    }
    $dlg.Controls.Add($lv)
    $dlg.Controls.Add((New-Intro $intro))
    $dlg.Controls.Add((New-DialogButtons $dlg $okText))
    Set-DialogTheme $dlg
    if ($dlg.ShowDialog($form) -ne 'OK') { return $null }
    , @(foreach ($it in $lv.Items) { $it.Checked })
}

# Choix d'une ligne dans une liste. Renvoie l'index choisi, ou -1.
function Show-ChoiceDialog([string]$title, [string]$intro, [string[]]$choices, [string]$okText = 'Choisir') {
    $dlg = New-Dialog $title 460 420
    $lb = New-Object Windows.Forms.ListBox
    $lb.Dock = 'Fill'
    $lb.IntegralHeight = $false
    $lb.Items.AddRange([object[]]$choices)
    if ($choices.Count) { $lb.SelectedIndex = 0 }
    $lb.Add_DoubleClick({ $dlg.DialogResult = 'OK' })
    $dlg.Controls.Add($lb)
    $dlg.Controls.Add((New-Intro $intro))
    $dlg.Controls.Add((New-DialogButtons $dlg $okText))
    Set-DialogTheme $dlg
    if ($dlg.ShowDialog($form) -ne 'OK') { return -1 }
    $lb.SelectedIndex
}

function Show-InputDialog([string]$title, [string]$intro, [string]$default = '', [switch]$Password) {
    $dlg = New-Dialog $title 480 190
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $tb = New-Object Windows.Forms.TextBox
    $tb.Text = $default
    $tb.UseSystemPasswordChar = [bool]$Password
    $tb.Location = New-Object Drawing.Point(12, 60)
    $tb.Width = 440
    $dlg.Controls.Add($tb)
    $dlg.Controls.Add((New-Intro $intro))
    $dlg.Controls.Add((New-DialogButtons $dlg 'OK'))
    Set-DialogTheme $dlg
    if ($dlg.ShowDialog($form) -ne 'OK') { return $null }
    $tb.Text.Trim()
}

function Show-Message([string]$text, [string]$icon = 'Information', [string]$buttons = 'OK') {
    [Windows.Forms.MessageBox]::Show($form, $text, 'AutoInstall', $buttons, $icon)
}

# =====================================================================
# Profils
# =====================================================================
function Save-CurrentProfile {
    if ($Loading) { return }
    Write-SelectionFile (Get-ProfilePath $CurrentProfile) (Get-CheckedEntries)
}

function Import-Entries($entries) {
    foreach ($e in $entries) { [void](Add-App $e.Categorie $e.Nom $e.Id $true @{ Version = $e.Version }) }
}

function Open-Profile([string]$name) {
    $script:Loading = $true
    $list.BeginUpdate()
    foreach ($it in @($AllItems)) {
        if ($it.Tag.Perso) { [void]$AllItems.Remove($it); $list.Items.Remove($it) }
        else { $it.Checked = $false; if ($it.Tag.Version) { $it.Tag.Version = ''; Update-ItemState $it } }
    }
    $list.EndUpdate()
    $script:CurrentProfile = $name
    $Settings.Profil = $name
    $path = Get-ProfilePath $name
    if (Test-Path $path) {
        try {
            $entries = Read-SelectionFile $path
            Import-Entries $entries
            Write-Log "Profil « $name » chargé ($($entries.Count) logiciels)."
        } catch { Write-Log "Impossible de lire le profil $name : $_" }
    } else { Write-Log "Nouveau profil « $name »." }
    $script:Loading = $false
    Update-Counter
}

function Update-ProfileBox([string]$select) {
    $script:Loading = $true
    $profileBox.Items.Clear()
    foreach ($n in Get-ProfileNames) { [void]$profileBox.Items.Add($n) }
    if (-not $profileBox.Items.Contains($select)) { [void]$profileBox.Items.Add($select) }
    $profileBox.SelectedItem = $select
    $script:Loading = $false
}

$profileBox.Add_SelectedIndexChanged({
    if ($Loading -or $profileBox.SelectedItem -eq $CurrentProfile) { return }
    Save-CurrentProfile
    Open-Profile ([string]$profileBox.SelectedItem)
})

function Test-ProfileName([string]$name) { $name -and $name -notmatch '[\\/:*?"<>|]' }

# =====================================================================
# winget : statut, installation, mises à jour
# =====================================================================
function Update-InstalledStatus([switch]$KeepStatus) {
    Set-Busy $true
    $progress.Style = 'Marquee'
    Write-Log 'Recherche des logiciels installés...'
    $script:InstalledMap = Get-InstalledPackages
    Write-Log 'Recherche des mises à jour disponibles...'
    $script:UpgradeMap = Get-AvailableUpgrades
    $nInst = 0; $nUpd = 0
    foreach ($it in $AllItems) {
        Update-ItemState $it -KeepStatus:$KeepStatus
        if ($it.Tag.Installe) { $nInst++ }
        if ($it.SubItems[$C_DISPO].Text) { $nUpd++ }
    }
    Write-Log "$nInst logiciel(s) de la liste installé(s), $nUpd mise(s) à jour disponible(s) dans la liste ($($UpgradeMap.Count) sur tout le PC)."
    $progress.Style = 'Blocks'
    Set-Busy $false
}

function Get-Options {
    @{ SauterInstalles = $chkSkip.Checked; RuntimesDabord = $chkRuntimes.Checked; PointRestauration = $chkRestore.Checked
       SupprimerRaccourcis = $chkShortcuts.Checked; Dossier = $folderBox.Text }
}

# Installe / met à jour / désinstalle des éléments de la liste en suivant la progression
function Start-Batch($items, [string]$action, [switch]$NoSkip) {
    $items = @($items)
    if ($items.Count -eq 0) { Write-Log 'Rien à faire.'; return }
    if ($action -ne 'uninstall') {
        $err = Test-Prerequisites $folderBox.Text
        if ($err) { Write-Log $err; [void](Show-Message $err 'Warning'); return }
    }
    $filterBox.Text = ''
    Save-CurrentProfile
    Set-Busy $true
    $opts = Get-Options
    if ($NoSkip) { $opts.SauterInstalles = $false }
    $entries = @(foreach ($it in $items) {
        [pscustomobject]@{ Categorie = $it.Tag.Categorie; Nom = $it.Text; Id = $it.Tag.Id; Version = $it.Tag.Version; Installe = $it.Tag.Installe; Item = $it }
    })
    $progress.Style = 'Blocks'
    $progress.Maximum = $entries.Count
    $progress.Value = 0
    $guiVerb = @{ install = 'Installation...'; upgrade = 'Mise à jour...'; uninstall = 'Désinstallation...' }[$action]
    $onItem = {
        param($entry, $phase, $res, $info)
        $li = $entry.Item
        switch ($phase) {
            'skip'  { Set-Status $li 'Déjà installé (ignoré)' 'ok'; $progress.Value = [Math]::Min($progress.Maximum, $progress.Value + 1) }
            'start' {
                Set-Status $li $guiVerb 'info'
                $li.EnsureVisible()
                $txt = "$($info.Index + 1) / $($info.Total) : $($entry.Nom)"
                if ($info.Restant) { $txt += " - environ $([Math]::Max(1, [Math]::Ceiling($info.Restant.TotalMinutes))) min restante(s)" }
                $lblEta.Text = $txt
            }
            'done'  {
                Set-Status $li ($res.Status + $(if ($res.Ok) { ' ✔' } else { ' ✖' })) $(if ($res.Ok) { 'ok' } else { 'err' })
                $li.Tag.Explication = if ($res.Ok) { '' } else { $res.Explication }
                $progress.Value = [Math]::Min($progress.Maximum, $progress.Value + 1)
            }
        }
    }
    $results = @(Invoke-PackageBatch $entries $action $opts $onItem)
    $script:LastFailed = @($results | Where-Object { -not $_.Resultat.Ok } | ForEach-Object { $_.Entree.Item })
    $script:LastAction = $action
    Update-InstalledStatus -KeepStatus

    $ok = $results.Count - $LastFailed.Count
    $msg = "Terminé : $ok réussi(s), $($LastFailed.Count) échec(s)."
    if ($LastFailed.Count) {
        $msg += "`n`n" + (($results | Where-Object { -not $_.Resultat.Ok } | ForEach-Object { "• $($_.Entree.Nom) : $($_.Resultat.Explication)" }) -join "`n")
        $msg += "`n`nTu peux cliquer sur « Réessayer les échecs »."
    }
    if ($action -eq 'install' -and $chkReboot.Checked -and -not $CancelRequested) {
        Restart-ComputerSoon
        if ((Show-Message "$msg`n`nLe PC va redémarrer dans 60 secondes." 'Information' 'OKCancel') -eq 'Cancel') {
            & shutdown.exe /a | Out-Null
            Write-Log 'Redémarrage annulé.'
        }
    } else { [void](Show-Message $msg $(if ($LastFailed.Count) { 'Warning' } else { 'Information' })) }
}

# =====================================================================
# Recherche winget
# =====================================================================
$searchAction = {
    $q = $searchBox.Text.Trim()
    if (-not $q) { return }
    Set-Busy $true
    Write-Log "Recherche de « $q »..."
    $res = @(Search-Winget $q)
    Set-Busy $false
    if ($res.Count -eq 0) { Write-Log 'Aucun résultat.'; return }

    $rows = @(foreach ($r in $res) { [pscustomobject]@{ Text = $r.Nom; Detail = "$($r.Id)   $($r.Version)"; Checked = $false } })
    $checked = Show-CheckDialog "Résultats pour « $q »" 'Coche les logiciels à ajouter à ta liste.' $rows 'Ajouter à ma liste'
    if ($null -eq $checked) { return }
    for ($i = 0; $i -lt $res.Count; $i++) {
        if (-not $checked[$i]) { continue }
        [void](Add-App 'Ajoutés par moi' $res[$i].Nom $res[$i].Id $true)
        Write-Log "Ajouté : $($res[$i].Nom) ($($res[$i].Id))"
    }
    Save-CurrentProfile
}
$searchBtn.Add_Click($searchAction)
$searchBox.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $searchAction } })
$filterBox.Add_TextChanged({ Update-Filter })

# =====================================================================
# Clic droit sur un logiciel
# =====================================================================
$listMenu = New-Object Windows.Forms.ContextMenuStrip
$miSite      = $listMenu.Items.Add('Ouvrir le site officiel')
$miVersion   = $listMenu.Items.Add('Choisir la version...')
$miLatest    = $listMenu.Items.Add('Revenir à la dernière version')
[void]$listMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miCatCheck  = $listMenu.Items.Add('Cocher toute la catégorie')
$miCatClear  = $listMenu.Items.Add('Décocher toute la catégorie')
[void]$listMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miRemove    = $listMenu.Items.Add('Retirer de ma liste')
$list.ContextMenuStrip = $listMenu

function Get-FocusedItem { if ($list.SelectedItems.Count) { $list.SelectedItems[0] } else { $null } }

$listMenu.Add_Opening({
    $it = Get-FocusedItem
    if (-not $it) { $_.Cancel = $true; return }
    $miSite.Text = if ($it.Tag.Site) { 'Ouvrir le site officiel' } else { 'Voir la fiche winget' }
    $miLatest.Visible = [bool]$it.Tag.Version
    $miCatCheck.Text = "Cocher toute la catégorie « $($it.Tag.Categorie) »"
    $miCatClear.Text = "Décocher toute la catégorie « $($it.Tag.Categorie) »"
    $miRemove.Visible = $it.Tag.Perso
})

$miSite.Add_Click({
    $it = Get-FocusedItem
    $url = if ($it.Tag.Site) { $it.Tag.Site } else { "https://winstall.app/apps/$($it.Tag.Id)" }
    Start-Process $url
})

$miVersion.Add_Click({
    $it = Get-FocusedItem
    Set-Busy $true
    Write-Log "Recherche des versions de $($it.Text)..."
    $versions = @(Get-PackageVersions $it.Tag.Id)
    Set-Busy $false
    if ($versions.Count -eq 0) { [void](Show-Message "Aucune version trouvée pour $($it.Text)." 'Warning'); return }
    $choices = @('Toujours la dernière version (conseillé)') + $versions
    $idx = Show-ChoiceDialog "Version de $($it.Text)" 'Choisis la version à installer. Elle sera retenue dans ton profil.' $choices
    if ($idx -lt 0) { return }
    $it.Tag.Version = if ($idx -eq 0) { '' } else { $versions[$idx - 1] }
    $it.Checked = $true
    Update-ItemState $it
    Write-Log "$($it.Text) : $(if ($it.Tag.Version) { "version $($it.Tag.Version) choisie" } else { 'dernière version' })."
    Save-CurrentProfile
})

$miLatest.Add_Click({
    $it = Get-FocusedItem
    $it.Tag.Version = ''
    Update-ItemState $it
    Save-CurrentProfile
})

function Set-CategoryChecked([string]$cat, [bool]$value) {
    foreach ($it in $AllItems) { if ($it.Tag.Categorie -eq $cat) { $it.Checked = $value } }
}
$miCatCheck.Add_Click({ Set-CategoryChecked (Get-FocusedItem).Tag.Categorie $true })
$miCatClear.Add_Click({ Set-CategoryChecked (Get-FocusedItem).Tag.Categorie $false })

$miRemove.Add_Click({
    $it = Get-FocusedItem
    [void]$AllItems.Remove($it)
    $list.Items.Remove($it)
    Save-CurrentProfile
    Update-Counter
})

# Tri par colonne (clic sur un titre, deuxième clic = ordre inverse)
$sorter = New-Object AutoInstallSorter
$list.Add_ColumnClick({
    if ($list.ListViewItemSorter -and $sorter.Column -eq $_.Column) { $sorter.Descending = -not $sorter.Descending }
    else { $sorter.Column = $_.Column; $sorter.Descending = $false }
    $list.ListViewItemSorter = $sorter
    $list.Sort()
    for ($i = 0; $i -lt $list.Columns.Count; $i++) {
        $list.Columns[$i].Text = $ColumnTitles[$i] + $(if ($i -eq $sorter.Column) { if ($sorter.Descending) { ' ▼' } else { ' ▲' } } else { '' })
    }
})

# =====================================================================
# Boutons
# =====================================================================
$btnAll.Add_Click({ foreach ($it in $list.Items) { $it.Checked = $true } })
$btnNone.Add_Click({ foreach ($it in $list.Items) { $it.Checked = $false } })
$btnRecommended.Add_Click({ foreach ($it in $AllItems) { if ($it.Tag.Recommande) { $it.Checked = $true } } })

$btnInstalled.Add_Click({
    $n = 0
    foreach ($it in $AllItems) { if ($it.Tag.Installe) { $it.Checked = $true; $n++ } }
    $known = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($it in $AllItems) { [void]$known.Add($it.Tag.Id) }
    $others = @($InstalledMap.Keys | Where-Object { -not $known.Contains($_) } | Sort-Object)
    Write-Log "$n logiciel(s) de la liste coché(s)."
    if ($others.Count -and (Show-Message "$($others.Count) autre(s) logiciel(s) installé(s) avec winget ne sont pas dans la liste.`nLes ajouter et les cocher aussi ?" 'Question' 'YesNo') -eq 'Yes') {
        foreach ($id in $others) { [void](Add-App 'Installés sur ce PC' ($id -replace '^[^.]+\.', '') $id $true) }
        Write-Log "$($others.Count) logiciel(s) ajouté(s) dans « Installés sur ce PC »."
    }
    Save-CurrentProfile
})

$btnCheckUpd.Add_Click({ Update-InstalledStatus })

$btnInstall.Add_Click({
    $items = @($AllItems | Where-Object { $_.Checked })
    if ($items.Count -eq 0) { Write-Log 'Rien de coché.'; return }
    Start-Batch $items 'install'
})

$btnUpdSel.Add_Click({
    $items = @($AllItems | Where-Object { $_.Checked -and $_.Tag.Installe })
    if ($items.Count -eq 0) { [void](Show-Message 'Aucun logiciel coché n''est installé.'); return }
    $withUpd = @($items | Where-Object { $_.SubItems[$C_DISPO].Text })
    if ($withUpd.Count) { $items = $withUpd } else { Write-Log 'Aucune mise à jour connue, winget va vérifier chaque logiciel.' }
    Start-Batch $items 'upgrade'
})

$btnUninstall.Add_Click({
    $items = @($AllItems | Where-Object { $_.Checked -and $_.Tag.Installe })
    if ($items.Count -eq 0) { [void](Show-Message 'Aucun logiciel coché n''est installé.'); return }
    $names = ($items | ForEach-Object { "• $($_.Text)" }) -join "`n"
    if ((Show-Message "Désinstaller ces $($items.Count) logiciel(s) ?`n`n$names" 'Warning' 'YesNo') -ne 'Yes') { return }
    Start-Batch $items 'uninstall'
})

$btnRetry.Add_Click({ Start-Batch $LastFailed $LastAction -NoSkip })

$btnCancel.Add_Click({
    if (-not $CancelRequested) {
        $script:CancelRequested = $true
        $btnCancel.Text = 'Arrêter tout de suite'
        Write-Log 'Annulation demandée : arrêt après le logiciel en cours.'
    } else {
        Write-Log 'Arrêt immédiat du logiciel en cours.'
        Stop-CurrentWinget
    }
})

$btnUpgrade.Add_Click({
    $err = Test-Prerequisites $folderBox.Text
    if ($err) { [void](Show-Message $err 'Warning'); return }
    Set-Busy $true
    $script:CancelRequested = $false
    Write-Log 'Mise à jour de tous les logiciels installés (winget upgrade --all)...'
    $progress.Style = 'Marquee'
    $r = Get-WingetResult (Invoke-Winget 'upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --include-unknown') 'upgrade'
    $progress.Style = 'Blocks'
    Write-Log "Mise à jour générale terminée : $($r.Status). $($r.Explication)"
    Update-InstalledStatus
})

$btnFolder.Add_Click({
    $fb = New-Object Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Dossier où installer les logiciels (un sous-dossier par logiciel)'
    if ($folderBox.Text) { $fb.SelectedPath = $folderBox.Text }
    if ($fb.ShowDialog($form) -eq 'OK') { $folderBox.Text = $fb.SelectedPath; Update-DiskLabel }
})
$btnFolderClear.Add_Click({ $folderBox.Text = ''; Update-DiskLabel })

# =====================================================================
# Menu Fichier
# =====================================================================
[void](Add-Menu $mFile 'Nouveau profil...' {
    $name = Show-InputDialog 'Nouveau profil' 'Nom du profil (ex. Jeux, Travail, PC de maman) :'
    if (-not (Test-ProfileName $name)) { return }
    Save-CurrentProfile
    Open-Profile $name
    Save-CurrentProfile
    Update-ProfileBox $name
})
[void](Add-Menu $mFile 'Renommer le profil...' {
    $name = Show-InputDialog 'Renommer le profil' "Nouveau nom pour « $CurrentProfile » :" $CurrentProfile
    if (-not (Test-ProfileName $name) -or $name -eq $CurrentProfile) { return }
    Save-CurrentProfile
    Move-Item (Get-ProfilePath $CurrentProfile) (Get-ProfilePath $name) -Force
    $script:CurrentProfile = $name
    $Settings.Profil = $name
    Update-ProfileBox $name
    Write-Log "Profil renommé en « $name »."
})
[void](Add-Menu $mFile 'Supprimer le profil' {
    if ((Show-Message "Supprimer le profil « $CurrentProfile » ?" 'Warning' 'YesNo') -ne 'Yes') { return }
    Remove-Item (Get-ProfilePath $CurrentProfile) -ErrorAction SilentlyContinue
    Write-Log "Profil « $CurrentProfile » supprimé."
    $script:CurrentProfile = ''
    $next = @(Get-ProfileNames)[0]
    Open-Profile $next
    Update-ProfileBox $next
})
Add-Menu $mFile '-' $null
[void](Add-Menu $mFile 'Importer une sélection...' {
    $od = New-Object Windows.Forms.OpenFileDialog
    $od.Filter = 'Sélection AutoInstall ou winget export (*.json)|*.json|Tous les fichiers|*.*'
    if ($od.ShowDialog($form) -ne 'OK') { return }
    try {
        $entries = Read-SelectionFile $od.FileName
        Import-Entries $entries
        Save-CurrentProfile
        Write-Log "$($entries.Count) logiciel(s) importé(s) depuis $($od.FileName)."
    } catch { [void](Show-Message "Fichier illisible : $_" 'Error') }
})
[void](Add-Menu $mFile 'Exporter la sélection...' {
    $sd = New-Object Windows.Forms.SaveFileDialog
    $sd.Filter = 'Sélection AutoInstall (*.json)|*.json'
    $sd.FileName = "AutoInstall-$CurrentProfile.json"
    if ($sd.ShowDialog($form) -ne 'OK') { return }
    Write-SelectionFile $sd.FileName (Get-CheckedEntries)
    Write-Log "Sélection exportée dans $($sd.FileName)."
})
Add-Menu $mFile '-' $null

function Get-GistTokenOrAsk([switch]$Change) {
    $token = if ($Change) { $null } else { Get-GistToken $Settings }
    if ($token) { return $token }
    if ((Show-Message "Pour synchroniser avec GitHub, il faut un jeton (token) ayant uniquement la permission « gist ».`nOuvrir la page GitHub pour en créer un ?" 'Question' 'YesNo') -eq 'Yes') {
        Start-Process 'https://github.com/settings/tokens/new?scopes=gist&description=AutoInstall'
    }
    $token = Show-InputDialog 'Jeton GitHub' 'Colle ton jeton GitHub (il sera chiffré avec ton compte Windows) :' '' -Password
    if (-not $token) { return $null }
    Set-GistToken $Settings $token
    Save-Settings $Settings
    $token
}

[void](Add-Menu $mFile 'Envoyer mes profils sur GitHub (Gist privé)' {
    $token = Get-GistTokenOrAsk
    if (-not $token) { return }
    Save-CurrentProfile
    try { Send-ProfilesToGist $Settings $token; Save-Settings $Settings; [void](Show-Message "Profils envoyés.`nID du Gist (à garder pour un autre PC) : $($Settings.GistId)") }
    catch { Write-Log "Échec de l'envoi sur GitHub : $($_.Exception.Message)"; [void](Show-Message "Échec de l'envoi : $($_.Exception.Message)`nLe jeton est peut-être expiré (Fichier > Changer le jeton GitHub)." 'Error') }
})
[void](Add-Menu $mFile 'Récupérer mes profils depuis GitHub' {
    $token = Get-GistTokenOrAsk
    if (-not $token) { return }
    if (-not $Settings.GistId) {
        $id = Show-InputDialog 'Gist GitHub' 'Adresse ou ID du Gist où tes profils ont été envoyés :'
        if (-not $id) { return }
        $Settings.GistId = ($id.TrimEnd('/') -split '/')[-1]
    }
    if ((Show-Message 'Les profils du même nom sur ce PC seront remplacés. Continuer ?' 'Question' 'YesNo') -ne 'Yes') { return }
    try {
        $names = @(Receive-ProfilesFromGist $Settings $token)
        Save-Settings $Settings
        if ($names.Count) { Open-Profile $(if ($names -contains $CurrentProfile) { $CurrentProfile } else { $names[0] }); Update-ProfileBox $CurrentProfile }
        [void](Show-Message "$($names.Count) profil(s) récupéré(s).")
    } catch { Write-Log "Échec de la récupération : $($_.Exception.Message)"; [void](Show-Message "Échec : $($_.Exception.Message)" 'Error') }
})
[void](Add-Menu $mFile 'Changer le jeton GitHub...' { [void](Get-GistTokenOrAsk -Change) })
Add-Menu $mFile '-' $null
[void](Add-Menu $mFile 'Préparer une clé USB AutoInstall...' {
    $drives = @(Get-RemovableDrives)
    if ($drives.Count -eq 0) { [void](Show-Message 'Aucune clé USB détectée. Branche-la puis réessaie.' 'Warning'); return }
    $labels = @($drives | ForEach-Object { "$($_.Name)  $($_.VolumeLabel)  ($([Math]::Round($_.AvailableFreeSpace / 1GB, 1)) Go libres)" })
    $idx = Show-ChoiceDialog 'Clé USB AutoInstall' 'AutoInstall, tes profils et tes sauvegardes seront copiés sur la clé (dossier AutoInstall).' $labels 'Copier'
    if ($idx -lt 0) { return }
    Save-CurrentProfile
    Save-Settings $Settings
    Set-Busy $true
    if ((Show-Message 'Sauvegarder aussi les réglages de tes logiciels sur la clé ?' 'Question' 'YesNo') -eq 'Yes') {
        foreach ($app in $AppSettings) { if (Test-AppSettingsPresent $app) { Backup-AppSettings $app } }
    }
    $ok = Copy-ToUsb $drives[$idx].RootDirectory.FullName
    Set-Busy $false
    [void](Show-Message $(if ($ok) { "Clé prête ! Sur le nouveau PC, ouvre AutoInstall sur la clé et lance Lancer.bat." } else { 'La copie a échoué, regarde le journal.' }))
})
Add-Menu $mFile '-' $null
[void](Add-Menu $mFile 'Ouvrir le dossier des journaux' { if (-not (Test-Path $LogDir)) { [void](New-Item -ItemType Directory $LogDir) }; Start-Process explorer.exe $LogDir })
[void](Add-Menu $mFile 'Quitter' { $form.Close() })

# =====================================================================
# Menu Outils
# =====================================================================
[void](Add-Menu $mTools 'Nettoyage d''un PC neuf...' {
    Set-Busy $true
    $found = @(Get-InstalledBloat)
    Set-Busy $false
    if ($found.Count -eq 0) { [void](Show-Message 'Aucune application préinstallée inutile trouvée.'); return }
    $rows = @($found | ForEach-Object { [pscustomobject]@{ Text = $_.Nom; Detail = $_.Paquets[0].Name; Checked = $_.Coche } })
    $checked = Show-CheckDialog 'Nettoyage d''un PC neuf' 'Applications préinstallées trouvées. Coche celles à supprimer (elles restent réinstallables depuis le Microsoft Store).' $rows 'Supprimer'
    if ($null -eq $checked) { return }
    $sel = @(for ($i = 0; $i -lt $found.Count; $i++) { if ($checked[$i]) { $found[$i] } })
    if ($sel.Count -eq 0) { return }
    Set-Busy $true
    Remove-Bloat $sel
    Set-Busy $false
    [void](Show-Message "$($sel.Count) application(s) traitée(s). Détails dans le journal.")
})
[void](Add-Menu $mTools 'Programmes au démarrage de Windows...' {
    $entries = @(Get-StartupEntries)
    if ($entries.Count -eq 0) { [void](Show-Message 'Aucun programme ne se lance au démarrage.'); return }
    $rows = @($entries | ForEach-Object { [pscustomobject]@{ Text = $_.Nom; Detail = $_.Commande; Checked = $_.Active } })
    $checked = Show-CheckDialog 'Programmes au démarrage' 'Coché = se lance au démarrage de Windows. Décoche pour désactiver (réversible, comme dans le Gestionnaire des tâches).' $rows
    if ($null -eq $checked) { return }
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($checked[$i] -ne $entries[$i].Active) {
            try { Set-StartupEnabled $entries[$i] $checked[$i] } catch { Write-Log "Impossible de modifier $($entries[$i].Nom) : $_" }
        }
    }
})
[void](Add-Menu $mTools 'Réglages Windows...' {
    $states = @($WindowsTweaks | ForEach-Object { Test-Tweak $_ })
    $rows = @(for ($i = 0; $i -lt $WindowsTweaks.Count; $i++) { [pscustomobject]@{ Text = $WindowsTweaks[$i].Nom; Detail = $(if ($states[$i]) { 'déjà actif' } else { '' }); Checked = $states[$i] } })
    $checked = Show-CheckDialog 'Réglages Windows' 'Coche les réglages à appliquer à ton compte. Décocher remet le réglage Windows par défaut.' $rows
    if ($null -eq $checked) { return }
    $changed = 0
    for ($i = 0; $i -lt $WindowsTweaks.Count; $i++) {
        if ($checked[$i] -ne $states[$i]) {
            try { Set-Tweak $WindowsTweaks[$i] $checked[$i]; $changed++ } catch { Write-Log "Impossible d'appliquer « $($WindowsTweaks[$i].Nom) » : $_" }
        }
    }
    if ($changed -and (Show-Message "$changed réglage(s) modifié(s).`nRedémarrer l'Explorateur Windows maintenant pour les voir ? (certains demandent de se reconnecter)" 'Question' 'YesNo') -eq 'Yes') {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
})
Add-Menu $mTools '-' $null
[void](Add-Menu $mTools 'Sauvegarder les réglages des logiciels...' {
    $apps = @($AppSettings | Where-Object { Test-AppSettingsPresent $_ })
    if ($apps.Count -eq 0) { [void](Show-Message 'Aucun logiciel connu dont on peut sauvegarder les réglages.'); return }
    $rows = @($apps | ForEach-Object { [pscustomobject]@{ Text = $_.Nom; Detail = $(if (Test-AppSettingsSaved $_) { 'déjà sauvegardé (sera remplacé)' } else { '' }); Checked = $true } })
    $checked = Show-CheckDialog 'Sauvegarder les réglages' "Les réglages seront copiés dans le dossier « sauvegardes » d'AutoInstall (emporte-le, ou prépare une clé USB)." $rows 'Sauvegarder'
    if ($null -eq $checked) { return }
    Set-Busy $true
    for ($i = 0; $i -lt $apps.Count; $i++) { if ($checked[$i]) { Backup-AppSettings $apps[$i] } }
    Set-Busy $false
    [void](Show-Message 'Sauvegarde terminée.')
})
[void](Add-Menu $mTools 'Restaurer les réglages des logiciels...' {
    $apps = @($AppSettings | Where-Object { Test-AppSettingsSaved $_ })
    if ($apps.Count -eq 0) { [void](Show-Message 'Aucune sauvegarde de réglages trouvée.'); return }
    $rows = @($apps | ForEach-Object { [pscustomobject]@{ Text = $_.Nom; Detail = ''; Checked = $true } })
    $checked = Show-CheckDialog 'Restaurer les réglages' 'Ferme ces logiciels avant de continuer. Leurs réglages actuels seront remplacés par la sauvegarde.' $rows 'Restaurer'
    if ($null -eq $checked) { return }
    Set-Busy $true
    for ($i = 0; $i -lt $apps.Count; $i++) { if ($checked[$i]) { Restore-AppSettings $apps[$i] } }
    Set-Busy $false
    [void](Show-Message 'Restauration terminée.')
})
Add-Menu $mTools '-' $null
[void](Add-Menu $mTools 'Créer un point de restauration maintenant' { Set-Busy $true; New-RestorePoint; Set-Busy $false })

# =====================================================================
# Menus Affichage et Aide
# =====================================================================
$miDark = Add-Menu $mView 'Thème sombre' { Set-Theme $(if ($miDark.Checked) { 'Clair' } else { 'Sombre' }) }
[void](Add-Menu $mView 'Actualiser (installés et mises à jour)' { Update-InstalledStatus })
[void](Add-Menu $mHelp 'Ligne de commande...' { [void](Show-Message $CliHelp) })
[void](Add-Menu $mHelp 'Page du projet sur GitHub' { Start-Process 'https://github.com/poiscail/AutoInstall' })

# =====================================================================
# Fenêtre : mémoire de la position, fermeture, démarrage
# =====================================================================
function Restore-WindowLayout {
    $w = $Settings.Fenetre
    if ($w -and $w.W -gt 0) {
        $rect = New-Object Drawing.Rectangle([int]$w.X, [int]$w.Y, [int]$w.W, [int]$w.H)
        if ([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith($rect) }) {
            $form.StartPosition = 'Manual'
            $form.Bounds = $rect
        }
        if ($w.Max) { $form.WindowState = 'Maximized' }
        if ($w.Bas -gt 100) { $bottom.Height = [int]$w.Bas }
    }
    $cols = @($Settings.Colonnes)
    if ($cols.Count -eq $list.Columns.Count) { for ($i = 0; $i -lt $cols.Count; $i++) { if ($cols[$i] -gt 20) { $list.Columns[$i].Width = [int]$cols[$i] } } }
}

function Save-AppSettings {
    $b = if ($form.WindowState -eq 'Normal') { $form.Bounds } else { $form.RestoreBounds }
    $Settings.Fenetre = @{ X = $b.X; Y = $b.Y; W = $b.Width; H = $b.Height; Max = ($form.WindowState -eq 'Maximized'); Bas = $bottom.Height }
    $Settings.Colonnes = @(foreach ($c in $list.Columns) { $c.Width })
    $o = Get-Options
    $Settings.SauterInstalles = $o.SauterInstalles
    $Settings.RuntimesDabord = $o.RuntimesDabord
    $Settings.PointRestauration = $o.PointRestauration
    $Settings.SupprimerRaccourcis = $o.SupprimerRaccourcis
    $Settings.Dossier = $o.Dossier
    $Settings.Redemarrer = $chkReboot.Checked
    $Settings.Profil = $CurrentProfile
    Save-Settings $Settings
}

$form.Add_FormClosing({
    if ($Busy) {
        if ((Show-Message 'Une opération est en cours. Quitter quand même ?' 'Warning' 'YesNo') -ne 'Yes') { $_.Cancel = $true; return }
        $script:CancelRequested = $true
        Stop-CurrentWinget
    }
    Save-CurrentProfile
    Save-AppSettings
})

$form.Add_Shown({
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [void](Show-Message "winget n'est pas encore disponible.`nOuvre le Microsoft Store, mets à jour « App Installer », puis relance AutoInstall." 'Warning')
        Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        $form.Close()
        return
    }
    Write-Log "Journal enregistré dans $LogFile"
    Update-InstalledStatus
    $iconTimer.Start()
    Write-Log 'Prêt. winget installe toujours la dernière version, sauf si tu en choisis une autre (clic droit).'
})

# Catalogue, profil, thème, puis affichage
$list.BeginUpdate()
foreach ($c in Read-Catalog) {
    [void](Add-App $c.categorie $c.nom $c.id $false @{ Description = "$($c.description)"; Site = "$($c.site)"; Recommande = [bool]$c.recommande; Perso = $false })
}
$list.EndUpdate()
$startProfile = if ($Profil) { $Profil } elseif ($Settings.Profil) { $Settings.Profil } else { 'Principal' }
Open-Profile $startProfile
Update-ProfileBox $startProfile
Restore-WindowLayout
Set-Theme $Settings.Theme
Update-Counter
Update-DiskLabel

[void]$form.ShowDialog()
