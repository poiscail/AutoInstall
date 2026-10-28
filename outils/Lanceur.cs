// AutoInstall.exe : lance AutoInstall.ps1 (posé à côté de l'exe) avec PowerShell.
// Les droits admin sont demandés par le manifeste. Les options sont transmises au script.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("AutoInstall")]
[assembly: AssemblyProduct("AutoInstall")]
[assembly: AssemblyDescription("Réinstalle tes logiciels en un clic avec winget")]
[assembly: AssemblyVersion("2.0.0.0")]

static class Lanceur
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "AutoInstall.ps1");
        if (!File.Exists(script) || !Directory.Exists(Path.Combine(dir, "lib")))
        {
            MessageBox.Show("AutoInstall.ps1 et le dossier lib doivent être à côté de AutoInstall.exe.\n\n" +
                "Extrais tout le dossier AutoInstall (pas seulement l'exe) puis relance.",
                "AutoInstall", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // Sans option : la fenêtre seule. En ligne de commande : console visible, sauf -Silencieux.
        bool console = args.Length > 0 && !args.Any(a => a.Equals("-Silencieux", StringComparison.OrdinalIgnoreCase));
        string forwarded = string.Join(" ", args.Select(Quote));

        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass " + (console ? "" : "-WindowStyle Hidden ") +
            "-File " + Quote(script) + " " + forwarded + (console ? " -Relance" : ""));
        psi.UseShellExecute = false;
        psi.CreateNoWindow = !console;
        psi.WorkingDirectory = dir;
        try
        {
            using (var p = Process.Start(psi)) { p.WaitForExit(); return p.ExitCode; }
        }
        catch (Exception e)
        {
            MessageBox.Show("Impossible de lancer PowerShell : " + e.Message, "AutoInstall", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '"', '\t' }) < 0) return a;
        return "\"" + a.Replace("\"", "\\\"") + "\"";
    }
}
