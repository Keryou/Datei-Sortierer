<#
  sortieren_gui.ps1 - Datei-Sortierer mit grafischer Oberflaeche (Windows)
  Version 1.0.0

  Sortiert Bilder, Videos, Musik, Dokumente, Anwendungen (.exe) und ZIP (.zip)
  nach Jahr oder Jahr\Monat. Optional werden Ordner direkt im Hauptordner
  als Ganzes mitsortiert. Duplikate koennen (hash-geprueft) geloescht werden.
  Netzwerkpfade (\\NAS\Freigabe) und Netzlaufwerke werden unterstuetzt.

  Start: Doppelklick auf start_sortierer.bat
         oder: powershell -ExecutionPolicy Bypass -File .\sortieren_gui.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- Daten
$Kategorien = [ordered]@{
    "Bilder"      = @(".jpg",".jpeg",".png",".gif",".bmp",".tif",".tiff",".webp",".heic",".heif",".raw",".cr2",".nef",".arw",".dng")
    "Videos"      = @(".mp4",".mov",".avi",".mkv",".wmv",".flv",".webm",".m4v",".mpg",".mpeg",".3gp",".mts")
    "Musik"       = @(".mp3",".flac",".wav",".aac",".m4a",".ogg",".wma",".opus",".aiff")
    "Dokumente"   = @(".pdf",".doc",".docx",".xls",".xlsx",".ppt",".pptx",".txt",".rtf",".odt",".ods",".odp",".csv",".md")
    "Anwendungen" = @(".exe")
    "ZIP"         = @(".zip")
}
$Labels = @{
    "Bilder" = "Bilder"; "Videos" = "Videos"; "Musik" = "Musik"; "Dokumente" = "Dokumente"
    "Anwendungen" = "Anwendungen (.exe)"; "ZIP" = "ZIP (.zip)"
}
# Diese Typen landen immer in einem eigenen Ordner (Anwendungen\..., ZIP\...)
$ImmerEigenerOrdner = @("Anwendungen", "ZIP")
# Name des Typ-Ordners fuer mitsortierte Ordner (nur bei "Alle Typen in eigene Ordner trennen")
$OrdnerKategorie = "Ordner"

$script:abbruch = $false
$script:prozent = 0.0
$script:klinge  = @(50, 150, 255)   # Jedi-Blau
$script:logZeilen = 0

# ---------------------------------------------------------------- Helfer
function New-Ctl($type, $x, $y, $w, $h, $text) {
    $c = New-Object $type
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    if ($null -ne $text) { $c.Text = $text }
    return $c
}

function Pick-Folder($startPfad) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($startPfad -and (Test-Path -LiteralPath $startPfad)) { $dlg.SelectedPath = $startPfad }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

# Vollstaendiger Pfad; Netzlaufwerke (z.B. Z:\) werden in den UNC-Pfad (\\Server\Freigabe) umgewandelt,
# damit Eingabe und Ausgabe auch dann sauber verglichen werden, wenn sie ueber verschiedene Namen angegeben wurden.
function Get-Normalisiert($pfad) {
    $voll = [System.IO.Path]::GetFullPath($pfad)
    if ($voll -match '^([A-Za-z]):(\\.*)?$') {
        $lw = $Matches[1].ToUpper() + ':'
        $rest = $Matches[2]
        try {
            $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$lw'" -ErrorAction Stop
            if ($d -and $d.DriveType -eq 4 -and $d.ProviderName) {
                return ($d.ProviderName.TrimEnd('\') + $rest)
            }
        } catch { }
    }
    return $voll
}

# SHA-256 einer Datei (oder $null bei Fehler)
function Get-Hash($pfad) {
    try { return (Get-FileHash -LiteralPath $pfad -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch { return $null }
}

# Signatur eines Ordners: Hash ueber alle relativen Dateipfade + Dateigroessen
function Get-OrdnerSignatur($pfad) {
    $basis = $pfad.TrimEnd('\')
    $zeilen = Get-ChildItem -LiteralPath $pfad -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { "{0}|{1}" -f $_.FullName.Substring($basis.Length), $_.Length } |
        Sort-Object
    $text = ($zeilen -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))
}

# In den Papierkorb (auf Netzlaufwerken gibt es keinen -> dort endgueltig geloescht)
function Remove-InPapierkorb($pfad) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $pfad,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
}

# ---------------------------------------------------------------- Fenster
$form = New-Object System.Windows.Forms.Form
$form.Text = "Datei-Sortierer v1.0.0"
$form.ClientSize = New-Object System.Drawing.Size(640, 730)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Eingabe / Ausgabe
$lblIn  = New-Ctl "System.Windows.Forms.Label"   15 15 610 20 "Eingabeordner (hier wird gesucht)  -  auch Netzwerkpfad, z. B. \\NAS\Freigabe\Ordner"
$txtIn  = New-Ctl "System.Windows.Forms.TextBox" 15 38 495 24 $null
$btnIn  = New-Ctl "System.Windows.Forms.Button"  520 36 105 27 "Durchsuchen..."
$lblOut = New-Ctl "System.Windows.Forms.Label"   15 75 610 20 "Ausgabeordner (hier landet alles)  -  auch Netzwerkpfad"
$txtOut = New-Ctl "System.Windows.Forms.TextBox" 15 98 495 24 $null
$btnOut = New-Ctl "System.Windows.Forms.Button"  520 96 105 27 "Durchsuchen..."

# Ordnerstruktur
$gbStruktur = New-Ctl "System.Windows.Forms.GroupBox" 15 140 300 110 "Ordnerstruktur im Ausgabeordner"
$rbFlach     = New-Ctl "System.Windows.Forms.RadioButton" 15 27 275 22 "Nur Ausgabeordner   (keine Unterordner)"
$rbJahr      = New-Ctl "System.Windows.Forms.RadioButton" 15 53 275 22 "Nur Jahr   (2024\)"
$rbJahrMonat = New-Ctl "System.Windows.Forms.RadioButton" 15 79 275 22 "Jahr und Monat   (2024\03\)"
$rbJahrMonat.Checked = $true
$gbStruktur.Controls.AddRange(@($rbFlach, $rbJahr, $rbJahrMonat))

# Umfang
$gbUmfang = New-Ctl "System.Windows.Forms.GroupBox" 325 140 300 110 "Welche Dateien"
$rbHaupt = New-Ctl "System.Windows.Forms.RadioButton" 15 27 275 22 "Nur Dateien im Hauptordner"
$rbAlles = New-Ctl "System.Windows.Forms.RadioButton" 15 53 275 22 "Alles (inkl. aller Unterordner)"
$rbHaupt.Checked = $true
$gbUmfang.Controls.AddRange(@($rbHaupt, $rbAlles))

# Aktion
$gbAktion = New-Ctl "System.Windows.Forms.GroupBox" 15 260 300 110 "Aktion"
$rbKopieren    = New-Ctl "System.Windows.Forms.RadioButton" 15 27 275 22 "Kopieren (Originale bleiben)"
$rbVerschieben = New-Ctl "System.Windows.Forms.RadioButton" 15 53 275 22 "Verschieben (Originale weg)"
$chkDup        = New-Ctl "System.Windows.Forms.CheckBox"    32 79 258 22 "Duplikate in Quelle loeschen"
$rbKopieren.Checked = $true
$chkDup.Enabled = $false
$gbAktion.Controls.AddRange(@($rbKopieren, $rbVerschieben, $chkDup))

# Dateitypen
$gbTypen = New-Ctl "System.Windows.Forms.GroupBox" 325 260 300 110 "Dateitypen"
$chkTypen = @{}
$pos = @(@(15,27), @(150,27), @(15,53), @(150,53), @(15,79), @(150,79))
$idx = 0
foreach ($name in $Kategorien.Keys) {
    $cb = New-Ctl "System.Windows.Forms.CheckBox" $pos[$idx][0] $pos[$idx][1] 135 22 $Labels[$name]
    $cb.Checked = $true
    $gbTypen.Controls.Add($cb)
    $chkTypen[$name] = $cb
    $idx++
}

# Extras
$chkKategorie = New-Ctl "System.Windows.Forms.CheckBox" 15 380 610 22 "Alle Typen in eigene Ordner trennen  (Bilder\..., Videos\..., Musik\... )"
$chkOrdner    = New-Ctl "System.Windows.Forms.CheckBox" 15 405 610 22 "Ordner mitsortieren  (nur Ordner direkt im Hauptordner, Inhalt bleibt unveraendert)"
$chkProbe     = New-Ctl "System.Windows.Forms.CheckBox" 15 430 610 22 "Probelauf (nur anzeigen, nichts veraendern)"
$chkProbe.Checked = $true
$lblHinweis   = New-Ctl "System.Windows.Forms.Label" 15 455 610 20 "Hinweis: Anwendungen (.exe) und ZIP landen immer in ihren eigenen Ordnern."
$lblHinweis.ForeColor = [System.Drawing.Color]::Gray

# Start / Abbrechen
$btnStart  = New-Ctl "System.Windows.Forms.Button" 15 483 200 36 "Sortieren starten"
$btnCancel = New-Ctl "System.Windows.Forms.Button" 225 483 120 36 "Abbrechen"
$btnCancel.Enabled = $false

# Lichtschwert-Ladebalken (selbst gezeichnet)
$saber = New-Ctl "System.Windows.Forms.Panel" 15 530 610 40 $null
$saber.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic").SetValue($saber, $true, $null)

$pinselSilber = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(175, 180, 190))
$pinselDunkel = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 72, 80))
$pinselNacht  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 25, 30))
$pinselKnopf  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 40, 40))

$saber.Add_Paint({
    param($sender, $e)
    $gr = $e.Graphics
    $gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w = $sender.ClientSize.Width
    $h = $sender.ClientSize.Height
    $cy = [int]($h / 2)
    $gr.Clear([System.Drawing.Color]::FromArgb(14, 14, 20))

    $x0 = 66
    $xEnde = $w - 14
    $laenge = ($xEnde - $x0) * $script:prozent
    $cr = $script:klinge[0]; $cg = $script:klinge[1]; $cb2 = $script:klinge[2]

    # ausgeschaltete Klinge (Schiene)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 45, 58), [single]6)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $gr.DrawLine($pen, $x0, $cy, $xEnde, $cy)
    $pen.Dispose()

    # leuchtende Klinge
    if ($laenge -gt 1) {
        $xSpitze = $x0 + $laenge
        $flackern = Get-Random -Minimum 0 -Maximum 16
        $schichten = @(
            @(30, (22 + $flackern)),
            @(22, (40 + $flackern)),
            @(15, (75 + $flackern))
        )
        foreach ($s in $schichten) {
            $a = [Math]::Min(255, $s[1])
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, $cr, $cg, $cb2), [single]$s[0])
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
            $gr.DrawLine($pen, $x0, $cy, $xSpitze, $cy)
            $pen.Dispose()
        }
        # farbiger Kern
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, $cr, $cg, $cb2), [single]10)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $gr.DrawLine($pen, $x0, $cy, $xSpitze, $cy)
        $pen.Dispose()
        # weisser Kern
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(240, 255, 255, 255), [single]4)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $gr.DrawLine($pen, $x0, $cy, $xSpitze, $cy)
        $pen.Dispose()
    }

    # Griff (ueber die Klinge gezeichnet, damit der Anfang sauber verschwindet)
    $gr.FillRectangle($pinselDunkel, 2, $cy - 8, 8, 16)            # Knauf
    $gr.FillRectangle($pinselSilber, 10, $cy - 7, 46, 14)          # Koerper
    $gr.FillRectangle($pinselNacht, 18, $cy - 7, 3, 14)            # Rillen
    $gr.FillRectangle($pinselNacht, 28, $cy - 7, 3, 14)
    $gr.FillRectangle($pinselNacht, 38, $cy - 7, 3, 14)
    $gr.FillEllipse($pinselKnopf, 45, $cy - 3, 6, 6)               # Knopf
    $gr.FillRectangle($pinselDunkel, 56, $cy - 11, 12, 22)         # Emitter
    $gr.FillRectangle($pinselSilber, 56, $cy - 11, 3, 22)
})

function Set-Saber([double]$p) {
    $script:prozent = $p
    $saber.Invalidate()
    $saber.Update()
}

$lblStatus = New-Ctl "System.Windows.Forms.Label" 15 577 610 20 "Bereit."
$txtLog = New-Ctl "System.Windows.Forms.TextBox" 15 602 610 115 $null
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)

$form.Controls.AddRange(@($lblIn,$txtIn,$btnIn,$lblOut,$txtOut,$btnOut,
    $gbStruktur,$gbUmfang,$gbAktion,$gbTypen,$chkKategorie,$chkOrdner,$chkProbe,$lblHinweis,
    $btnStart,$btnCancel,$saber,$lblStatus,$txtLog))

$sperrListe = @($txtIn,$btnIn,$txtOut,$btnOut,$gbStruktur,$gbUmfang,$gbAktion,$gbTypen,$chkKategorie,$chkOrdner,$chkProbe,$btnStart)

function Set-Sperre([bool]$an) {
    foreach ($c in $sperrListe) { $c.Enabled = -not $an }
    # "Welche Dateien" ist bei "Ordner mitsortieren" ausgegraut (dann gilt: Hauptordner + Ordner als Ganzes)
    $gbUmfang.Enabled = (-not $an) -and (-not $chkOrdner.Checked)
    $btnCancel.Enabled = $an
}
function Log([string]$t) { $txtLog.AppendText($t + "`r`n") }
# Protokollzeile mit Begrenzung (sonst wird die Anzeige bei tausenden Dateien traege)
function Log-Limit([string]$t) {
    if ($script:logZeilen -lt 500) { Log $t; $script:logZeilen++ }
}

# ---------------------------------------------------------------- Events
$btnIn.Add_Click({
    $p = Pick-Folder $txtIn.Text
    if ($p) { $txtIn.Text = $p }
})
$btnOut.Add_Click({
    $p = Pick-Folder $txtOut.Text
    if ($p) { $txtOut.Text = $p }
})
$btnCancel.Add_Click({ $script:abbruch = $true })
$chkOrdner.Add_CheckedChanged({ $gbUmfang.Enabled = -not $chkOrdner.Checked })
# Duplikate loeschen ist nur bei "Verschieben" sinnvoll (beim Kopieren sollen die Originale ja bleiben)
$rbVerschieben.Add_CheckedChanged({
    if ($rbVerschieben.Checked) { $chkDup.Enabled = $true }
    else { $chkDup.Checked = $false; $chkDup.Enabled = $false }
})

$btnStart.Add_Click({
    $txtLog.Clear()
    Set-Saber 0
    $script:abbruch = $false
    $script:logZeilen = 0

    $in  = $txtIn.Text.Trim()
    $out = $txtOut.Text.Trim()

    if (-not $in -or -not (Test-Path -LiteralPath $in -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Bitte einen gueltigen Eingabeordner waehlen.`r`n`r`nBei Netzwerkpfaden: Ist die Freigabe erreichbar? Ggf. vorher im Explorer oeffnen und anmelden.",
            "Hinweis") | Out-Null
        return
    }
    if (-not $out) {
        [System.Windows.Forms.MessageBox]::Show("Bitte einen Ausgabeordner waehlen.", "Hinweis") | Out-Null
        return
    }
    try {
        $inVoll  = Get-Normalisiert $in
        $outVoll = Get-Normalisiert $out
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ein Pfad ist ungueltig.", "Hinweis") | Out-Null
        return
    }
    $outPrefix = $outVoll.TrimEnd('\') + '\'

    # Erweiterungen der angehakten Typen
    $map = @{}
    foreach ($name in $Kategorien.Keys) {
        if ($chkTypen[$name].Checked) { foreach ($e in $Kategorien[$name]) { $map[$e] = $name } }
    }
    $ordnerMit = $chkOrdner.Checked
    if ($map.Count -eq 0 -and -not $ordnerMit) {
        [System.Windows.Forms.MessageBox]::Show("Bitte mindestens einen Dateityp anhaken.", "Hinweis") | Out-Null
        return
    }

    $probe = $chkProbe.Checked
    $verschieben = $rbVerschieben.Checked
    $dupLoeschen = $chkDup.Checked -and $verschieben
    $mitKategorie = $chkKategorie.Checked
    $alles = $rbAlles.Checked -and (-not $ordnerMit)   # Ordner-Modus: Ordner bleiben ganz, nichts wird einzeln herausgeholt
    $struktur = 2                       # 0 = nur Ausgabeordner, 1 = Jahr, 2 = Jahr\Monat
    if ($rbFlach.Checked) { $struktur = 0 } elseif ($rbJahr.Checked) { $struktur = 1 }

    if ($verschieben -and -not $probe) {
        $text = "Die Dateien werden VERSCHOBEN (Originale sind danach weg)."
        if ($dupLoeschen) {
            $text += "`r`n`r`nDuplikate (identischer Inhalt, per SHA-256 geprueft) werden aus dem Eingabeordner in den Papierkorb verschoben. Auf Netzlaufwerken gibt es keinen Papierkorb - dort werden sie ENDGUELTIG geloescht."
        }
        $text += "`r`n`r`nWirklich starten?"
        $antwort = [System.Windows.Forms.MessageBox]::Show($text, "Sicher?", "YesNo", "Warning")
        if ($antwort -ne "Yes") { return }
    }

    # Klingenfarbe: Probelauf gruen, Kopieren blau, Verschieben rot
    if ($probe)            { $script:klinge = @(50, 230, 90) }
    elseif ($verschieben)  { $script:klinge = @(255, 35, 35) }
    else                   { $script:klinge = @(50, 150, 255) }

    Set-Sperre $true
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $counts = @{ Sortiert = 0; Ordner = 0; Doppelt = 0; Geloescht = 0; Fehler = 0 }

    try {
        # ---- Suchen
        $lblStatus.Text = "Suche Dateien ... (bei Netzwerkordnern kann das etwas dauern)"
        [System.Windows.Forms.Application]::DoEvents()

        $suchArgs = @{ LiteralPath = $inVoll; File = $true; Force = $true; ErrorAction = "SilentlyContinue" }
        if ($alles) { $suchArgs.Recurse = $true }

        $dateien = @()
        if ($map.Count -gt 0) {
            $dateien = @(Get-ChildItem @suchArgs | Where-Object {
                $map.ContainsKey($_.Extension.ToLower()) -and
                -not $_.FullName.StartsWith($outPrefix, [System.StringComparison]::OrdinalIgnoreCase)
            })
        }

        # Ordner direkt im Hauptordner, die als Ganzes mitsortiert werden
        $ordnerListe = @()
        if ($ordnerMit) {
            $ordnerListe = @(Get-ChildItem -LiteralPath $inVoll -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
                $p = $_.FullName.TrimEnd('\') + '\'
                -not ($_.Attributes -band [System.IO.FileAttributes]::System) -and
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
                -not $outPrefix.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not $p.StartsWith($outPrefix, [System.StringComparison]::OrdinalIgnoreCase)
            })
        }

        $items = New-Object System.Collections.ArrayList
        foreach ($d in $dateien)     { [void]$items.Add([pscustomobject]@{ Info = $d; IstOrdner = $false }) }
        foreach ($o in $ordnerListe) { [void]$items.Add([pscustomobject]@{ Info = $o; IstOrdner = $true }) }

        $gesamt = $items.Count
        if ($gesamt -eq 0) {
            $lblStatus.Text = "Nichts Passendes gefunden."
            Log "Nichts Passendes gefunden."
            return
        }
        Log "$($dateien.Count) Dateien und $($ordnerListe.Count) Ordner gefunden."
        $schritt = [Math]::Max(1, [int]($gesamt / 100))

        if (-not $probe -and -not (Test-Path -LiteralPath $outVoll)) {
            New-Item -ItemType Directory -Path $outVoll -Force | Out-Null
        }

        # ---- Sortieren
        $n = 0
        foreach ($it in $items) {
            if ($script:abbruch) { Log "Abgebrochen."; break }
            $n++
            $f = $it.Info
            $istOrdner = $it.IstOrdner

            $datum = $f.CreationTime
            if ($f.LastWriteTime -lt $datum) { $datum = $f.LastWriteTime }

            if ($istOrdner) { $kat = $OrdnerKategorie } else { $kat = $map[$f.Extension.ToLower()] }

            $zielOrdner = $outVoll
            if ($istOrdner) {
                if ($mitKategorie) { $zielOrdner = Join-Path $zielOrdner $kat }
            } elseif ($mitKategorie -or ($ImmerEigenerOrdner -contains $kat)) {
                $zielOrdner = Join-Path $zielOrdner $kat
            }
            if ($struktur -ge 1) { $zielOrdner = Join-Path $zielOrdner $datum.ToString("yyyy") }
            if ($struktur -ge 2) { $zielOrdner = Join-Path $zielOrdner $datum.ToString("MM") }

            $zielDatei = Join-Path $zielOrdner $f.Name

            # Sicherheitsnetz: Datei liegt schon exakt am Ziel -> nichts tun (und nie loeschen!)
            $selbst = ($zielDatei -ieq $f.FullName)

            # Namenskonflikt: identischer Inhalt = Duplikat, sonst _1, _2 ...
            $i = 1
            $istDoppelt = $false
            $quellHash = $null
            if (-not $selbst) {
                while (Test-Path -LiteralPath $zielDatei) {
                    if ($istOrdner) {
                        if ((Get-OrdnerSignatur $zielDatei) -eq (Get-OrdnerSignatur $f.FullName)) { $istDoppelt = $true; break }
                        $zielDatei = Join-Path $zielOrdner ("{0}_{1}" -f $f.Name, $i)
                    } else {
                        if ((Get-Item -LiteralPath $zielDatei).Length -eq $f.Length) {
                            # gleicher Name + gleiche Groesse -> Inhalt per SHA-256 vergleichen
                            $lblStatus.Text = "Pruefe Duplikat: $($f.Name)"
                            [System.Windows.Forms.Application]::DoEvents()
                            if ($null -eq $quellHash) { $quellHash = Get-Hash $f.FullName }
                            $zielHash = Get-Hash $zielDatei
                            if ($quellHash -and ($quellHash -eq $zielHash)) { $istDoppelt = $true; break }
                        }
                        $zielDatei = Join-Path $zielOrdner ("{0}_{1}{2}" -f $f.BaseName, $i, $f.Extension)
                    }
                    $i++
                }
            }

            $zaehlerName = "Sortiert"
            if ($istOrdner) { $zaehlerName = "Ordner" }

            if ($selbst) {
                $counts.Doppelt++
                Log-Limit "[Uebersprungen] liegt schon am Ziel: $($f.FullName)"
            } elseif ($istDoppelt) {
                $counts.Doppelt++
                if ($dupLoeschen -and -not $istOrdner) {
                    # Duplikat (Inhalt per Hash bestaetigt) aus der Quelle entfernen
                    if ($probe) {
                        $counts.Geloescht++
                        Log-Limit "[Probe][Duplikat -> Papierkorb] $($f.FullName)   (identisch mit $zielDatei)"
                    } else {
                        try {
                            Remove-InPapierkorb $f.FullName
                            $counts.Geloescht++
                        } catch {
                            $counts.Fehler++
                            Log "FEHLER beim Loeschen: $($f.FullName) - $($_.Exception.Message)"
                        }
                    }
                } elseif ($probe) {
                    Log-Limit "[Probe][Duplikat -> uebersprungen] $($f.FullName)   (identisch mit $zielDatei)"
                }
            } elseif ($probe) {
                $counts[$zaehlerName]++
                $tag = "[Probe]"
                if ($istOrdner) { $tag = "[Probe][Ordner]" }
                Log-Limit "$tag $($f.FullName)  ->  $zielDatei"
            } else {
                try {
                    if (-not (Test-Path -LiteralPath $zielOrdner)) {
                        New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null
                    }
                    if ($verschieben) { Move-Item -LiteralPath $f.FullName -Destination $zielDatei -ErrorAction Stop }
                    elseif ($istOrdner) { Copy-Item -LiteralPath $f.FullName -Destination $zielDatei -Recurse -ErrorAction Stop }
                    else { Copy-Item -LiteralPath $f.FullName -Destination $zielDatei -ErrorAction Stop }
                    $counts[$zaehlerName]++
                } catch {
                    $counts.Fehler++
                    Log "FEHLER: $($f.FullName) - $($_.Exception.Message)"
                }
            }

            if (($n % $schritt) -eq 0 -or $n -eq $gesamt) {
                Set-Saber ($n / $gesamt)
                $lblStatus.Text = "$n / $gesamt"
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($script:logZeilen -ge 500) { Log "... (Anzeige auf 500 Zeilen begrenzt)" }

        $ende = if ($probe) { "Probelauf fertig" } else { "Fertig" }
        $loeschWort = if ($probe) { "wuerden geloescht" } else { "geloescht" }
        $msg = "$ende. Dateien: $($counts.Sortiert) | Ordner: $($counts.Ordner) | Duplikate: $($counts.Doppelt) (${loeschWort}: $($counts.Geloescht)) | Fehler: $($counts.Fehler)"
        Log ""
        Log $msg
        $lblStatus.Text = $msg
    }
    catch {
        Log "Unerwarteter Fehler: $($_.Exception.Message)"
        $lblStatus.Text = "Fehler - siehe Protokoll."
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Set-Sperre $false
    }
})

[void]$form.ShowDialog()