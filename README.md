# AutoInstall

Réinstalle tous mes logiciels en un clic après une réinstallation de Windows, toujours en dernière version (via winget).

## Utilisation

1. Télécharger le dépôt (Code → Download ZIP) et l'extraire.
2. Double-cliquer sur `Lancer.bat` (accepter la demande admin).
3. Cocher ce que tu veux (ou choisir un profil) → **Installer la sélection**.

Si winget n'est pas encore dispo sur un Windows neuf : mettre à jour « App Installer » dans le Microsoft Store.

## Ce que ça sait faire

**Installation**
- Les essentiels sont en gras (**Cocher les recommandés**), la description et le site s'affichent au survol.
- Options à cocher : sauter les déjà installés, runtimes (Visual C++, .NET…) en premier, point de restauration avant, supprimer les raccourcis ajoutés sur le bureau, redémarrer à la fin, dossier d'installation.
- Temps restant estimé, bouton **Annuler** (1er clic : arrêt après le logiciel en cours, 2e clic : arrêt immédiat), **Réessayer les échecs**.
- Les erreurs winget sont expliquées en français.
- Vérifie la connexion Internet et l'espace disque avant de commencer.

**Mises à jour et nettoyage**
- Colonnes *Installée* / *Disponible*, **Mettre à jour la sélection**, **Tout mettre à jour**, **Désinstaller la sélection**.
- Outils → nettoyage d'un PC neuf (applis préinstallées), programmes au démarrage, réglages Windows (thème sombre, extensions de fichiers, menu clic droit complet…).
- Outils → sauvegarder / restaurer les réglages de certains logiciels (VS Code, Notepad++, OBS, Windows Terminal…).

**Profils**
- Plusieurs profils (Jeux, Travail…), import/export, import d'un fichier `winget export`.
- **Cocher l'installé** : coche tout ce qui est déjà sur ce PC pour le réinstaller ailleurs.
- Fichier → envoyer / récupérer les profils sur un Gist GitHub privé (jeton avec la seule permission « gist », chiffré avec ton compte Windows).
- Fichier → préparer une clé USB AutoInstall.

**Affichage** : clic droit sur un logiciel (site officiel, choisir une version, cocher toute la catégorie), tri par colonne, filtre, thème sombre, taille de fenêtre mémorisée.

## Ligne de commande

```
powershell -ExecutionPolicy Bypass -File AutoInstall.ps1 -Profil Jeux -Installer -Silencieux -Redemarrer
```

Options : `-Installer`, `-MettreAJour`, `-ToutMettreAJour`, `-Liste`, `-Profil <nom>`, `-Fichier <chemin>`, `-Redemarrer`, `-Silencieux`, `-Aide`.

## Fichiers

| Fichier / dossier | Rôle |
|---|---|
| `AutoInstall.ps1` | fenêtre et ligne de commande |
| `lib\Core.ps1` | winget, profils, journal, vérifications |
| `lib\Outils.ps1` | nettoyage, démarrage, réglages, Gist, clé USB |
| `catalogue.json` | liste des logiciels proposés (modifiable) |
| `profils\` | tes sélections |
| `sauvegardes\` | réglages des logiciels sauvegardés |
| `journaux\` | un journal par jour |
| `reglages.json`, `cache\` | préférences et icônes (locaux) |
