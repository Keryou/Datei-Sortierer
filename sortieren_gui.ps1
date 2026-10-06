<#
  sortieren_gui.ps1 - Datei-Sortierer mit grafischer Oberflaeche (Windows)
  Sortiert Bilder, Videos, Musik, Dokumente, Anwendungen (.exe) und ZIP (.zip)
  nach Jahr oder Jahr\Monat. Optional werden Unterordner als Ganzes mitgenommen.
  Start: Doppelklick auf start_sortierer.bat
         oder: powershell -ExecutionPolicy Bypass -File .\sortieren_gui.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
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
# Name des Typ-Ordners fuer mitgenommene Unterordner (nur bei "Alle Typen in eigene Ordner trennen")
$OrdnerKategorie = "Ordner"

$script:abbruch = $false
$script:prozent = 0.0
$script:klinge  = @(50, 150, 255)   # Jedi-Blau

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

# Einfache Signatur eines Ordners (Anzahl Dateien | Gesamtgroesse), um Duplikate zu erkennen
function Get-OrdnerSignatur($pfad) {
    $m = Get-ChildItem -LiteralPath $pfad -Recurse -File -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum
    return ("{0}|{1}" -f $m.Count, [long]$m.Sum)
}

# ---------------------------------------------------------------- Fenster
$form = New-Object System.Windows.Forms.Form
$form.Text = "Datei-Sortierer"
$form.ClientSize = New-Object System.Drawing.Size(640, 730)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Eingabe / Ausgabe
$lblIn  = New-Ctl "System.Windows.Forms.Label"   15 15 300 20 "Eingabeordner (hier wird gesucht):"
$txtIn  = New-Ctl "System.Windows.Forms.TextBox" 15 38 495 24 $null
$btnIn  = New-Ctl "System.Windows.Forms.Button"  520 36 105 27 "Durchsuchen..."
$lblOut = New-Ctl "System.Windows.Forms.Label"   15 75 300 20 "Ausgabeordner (hier landet alles):"
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
$rbKopieren.Checked = $true
$gbAktion.Controls.AddRange(@($rbKopieren, $rbVerschieben))

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
$chkOrdner    = New-Ctl "System.Windows.Forms.CheckBox" 15 405 610 22 "Unterordner als Ganzes mitnehmen  (Inhalt bleibt unveraendert)"
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
    # "Welche Dateien" ist bei "Unterordner mitnehmen" ausgegraut (dann gilt: Hauptordner + Unterordner als Ganzes)
    $gbUmfang.Enabled = (-not $an) -and (-not $chkOrdner.Checked)
    $btnCancel.Enabled = $an
}
function Log([string]$t) { $txtLog.AppendText($t + "`r`n") }

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

$btnStart.Add_Click({
    $txtLog.Clear()
    Set-Saber 0
    $script:abbruch = $false

    $in  = $txtIn.Text.Trim()
    $out = $txtOut.Text.Trim()

    if (-not $in -or -not (Test-Path -LiteralPath $in -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Bitte einen gueltigen Eingabeordner waehlen.", "Hinweis") | Out-Null
        return
    }
    if (-not $out) {
        [System.Windows.Forms.MessageBox]::Show("Bitte einen Ausgabeordner waehlen.", "Hinweis") | Out-Null
        return
    }
    try {
        $inVoll  = [System.IO.Path]::GetFullPath($in)
        $outVoll = [System.IO.Path]::GetFullPath($out)
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
    $mitKategorie = $chkKategorie.Checked
    $alles = $rbAlles.Checked -and (-not $ordnerMit)   # Unterordner-Modus: Unterordner bleiben ganz, nichts wird einzeln herausgeholt
    $struktur = 2                       # 0 = nur Ausgabeordner, 1 = Jahr, 2 = Jahr\Monat
    if ($rbFlach.Checked) { $struktur = 0 } elseif ($rbJahr.Checked) { $struktur = 1 }

    if ($verschieben -and -not $probe) {
        $antwort = [System.Windows.Forms.MessageBox]::Show(
            "Die Dateien werden VERSCHOBEN (Originale sind danach weg). Wirklich starten?",
            "Sicher?", "YesNo", "Warning")
        if ($antwort -ne "Yes") { return }
    }

    # Klingenfarbe: Probelauf gruen, Kopieren blau, Verschieben rot
    if ($probe)            { $script:klinge = @(50, 230, 90) }
    elseif ($verschieben)  { $script:klinge = @(255, 35, 35) }
    else                   { $script:klinge = @(50, 150, 255) }

    Set-Sperre $true
    $counts = @{ Sortiert = 0; Ordner = 0; Doppelt = 0; Fehler = 0 }
    $logZeilen = 0

    try {
        # ---- Suchen
        $lblStatus.Text = "Suche Dateien ..."
        [System.Windows.Forms.Application]::DoEvents()

        $suchArgs = @{ LiteralPath = $in; File = $true; Force = $true; ErrorAction = "SilentlyContinue" }
        if ($alles) { $suchArgs.Recurse = $true }

        $dateien = @()
        if ($map.Count -gt 0) {
            $dateien = @(Get-ChildItem @suchArgs | Where-Object {
                $map.ContainsKey($_.Extension.ToLower()) -and
                -not $_.FullName.StartsWith($outPrefix, [System.StringComparison]::OrdinalIgnoreCase)
            })
        }

        # Unterordner (direkt im Hauptordner), die als Ganzes mitgenommen werden
        $ordnerListe = @()
        if ($ordnerMit) {
            $ordnerListe = @(Get-ChildItem -LiteralPath $in -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
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
        Log "$($dateien.Count) Dateien und $($ordnerListe.Count) Unterordner gefunden."
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

            # Namenskonflikt: gleicher Inhalt = Duplikat (ueberspringen), sonst _1, _2 ...
            $i = 1
            $istDoppelt = $false
            while (Test-Path -LiteralPath $zielDatei) {
                if ($istOrdner) {
                    if ((Get-OrdnerSignatur $zielDatei) -eq (Get-OrdnerSignatur $f.FullName)) { $istDoppelt = $true; break }
                    $zielDatei = Join-Path $zielOrdner ("{0}_{1}" -f $f.Name, $i)
                } else {
                    if ((Get-Item -LiteralPath $zielDatei).Length -eq $f.Length) { $istDoppelt = $true; break }
                    $zielDatei = Join-Path $zielOrdner ("{0}_{1}{2}" -f $f.BaseName, $i, $f.Extension)
                }
                $i++
            }

            $zaehlerName = "Sortiert"
            if ($istOrdner) { $zaehlerName = "Ordner" }

            if ($istDoppelt) {
                $counts.Doppelt++
            } elseif ($probe) {
                $counts[$zaehlerName]++
                if ($logZeilen -lt 500) {
                    $tag = "[Probe]"
                    if ($istOrdner) { $tag = "[Probe][Ordner]" }
                    Log "$tag $($f.FullName)  ->  $zielDatei"
                    $logZeilen++
                }
            } else {
                try {
                    if (-not (Test-Path -LiteralPath $zielOrdner)) {
                        New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null
                    }
                    if ($istOrdner) {
                        if ($verschieben) { Move-Item -LiteralPath $f.FullName -Destination $zielDatei -ErrorAction Stop }
                        else              { Copy-Item -LiteralPath $f.FullName -Destination $zielDatei -Recurse -ErrorAction Stop }
                    } else {
                        if ($verschieben) { Move-Item -LiteralPath $f.FullName -Destination $zielDatei -ErrorAction Stop }
                        else              { Copy-Item -LiteralPath $f.FullName -Destination $zielDatei -ErrorAction Stop }
                    }
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

        if ($probe -and ($counts.Sortiert + $counts.Ordner) -gt 500) { Log "... (Anzeige auf 500 Zeilen begrenzt)" }

        $ende = if ($probe) { "Probelauf fertig" } else { "Fertig" }
        $msg = "$ende. Dateien: $($counts.Sortiert) | Ordner: $($counts.Ordner) | Duplikate uebersprungen: $($counts.Doppelt) | Fehler: $($counts.Fehler)"
        Log ""
        Log $msg
        $lblStatus.Text = $msg
    }
    catch {
        Log "Unerwarteter Fehler: $($_.Exception.Message)"
        $lblStatus.Text = "Fehler - siehe Protokoll."
    }
    finally {
        Set-Sperre $false
    }
})

[void]$form.ShowDialog()
