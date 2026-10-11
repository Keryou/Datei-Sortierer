# Datei-Sortierer

Ein Windows-Tool mit grafischer Oberfläche, das Bilder, Videos, Musik, Dokumente, Programme und ZIP-Dateien einsammelt und automatisch nach **Jahr** oder **Jahr\Monat** in Ordner sortiert.

![Plattform](https://img.shields.io/badge/Plattform-Windows-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)
![Lizenz](https://img.shields.io/badge/Lizenz-MIT-green)

![Screenshot des Datei-Sortierers](docs/screenshot.png)

## ✨ Features

- Grafische Oberfläche mit Ein- und Ausgabeordner, keine Kommandozeile nötig
- Ordnerstruktur wählbar: nur Ausgabeordner (flach), nur Jahr oder Jahr\Monat
- Umfang wählbar: nur Dateien im Hauptordner oder alles inklusive Unterordner
- Ordner mitsortieren: Ordner direkt im Hauptordner wandern als Ganzes mit, ihr Inhalt bleibt unverändert
- Dateitypen einzeln wählbar: Bilder, Videos, Musik, Dokumente, Anwendungen (`.exe`), ZIP (`.zip`)
- Kopieren oder Verschieben
- Duplikat-Erkennung per SHA-256, optional mit Löschen der Duplikate (Papierkorb)
- Netzwerkpfade (`\\NAS\Freigabe\Ordner`) und Netzlaufwerke als Ein- und Ausgabe
- Probelauf (standardmäßig aktiv), der nur anzeigt, was passieren würde
- Laserschwert-Ladebalken: grün im Probelauf, blau beim Kopieren, rot beim Verschieben

## 🧰 Voraussetzungen

- Windows 10 oder 11
- Windows PowerShell 5.1 (ist bereits enthalten, es muss nichts installiert werden)

## 🚀 Start

1. Dieses Repository herunterladen (**Code → Download ZIP**) oder unter **Releases** die aktuelle Version holen
2. ZIP entpacken. `sortieren_gui.ps1` und `start_sortierer.bat` müssen im selben Ordner liegen
3. `start_sortierer.bat` doppelklicken

Alternativ in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\sortieren_gui.ps1
```

## 🕹️ Bedienung

1. **Eingabeordner** und **Ausgabeordner** wählen oder einen Netzwerkpfad eintippen
2. Ordnerstruktur, Umfang, Aktion und Dateitypen einstellen
3. **Zuerst den Probelauf machen** und das Protokoll prüfen
4. Probelauf-Haken entfernen und **Sortieren starten**

### Beispiel (Jahr\Monat, ohne Typ-Trennung)

```
Ausgabeordner\
├── 2024\
│   ├── 03\
│   │   ├── urlaub.jpg
│   │   └── song.mp3
│   └── 07\
│       └── rechnung.pdf
├── Anwendungen\
│   └── 2024\03\setup.exe
└── ZIP\
    └── 2024\08\backup.zip
```

Mit **„Alle Typen in eigene Ordner trennen“** entsteht stattdessen `Bilder\2024\03\`, `Videos\...`, `Musik\...` usw. `.exe` und `.zip` landen immer in `Anwendungen\` bzw. `ZIP\`.

## 🔍 Duplikat-Logik

Liegt am Ziel schon eine Datei mit gleichem Namen und gleicher Größe, werden beide per **SHA-256** verglichen:

- **Gleicher Inhalt:** Duplikat. Die Datei wird nicht noch einmal kopiert oder verschoben. Mehrfaches Ausführen erzeugt keine Kopien-Flut, und zusammengeführte Backups enthalten jede Datei nur einmal.
- **Anderer Inhalt:** Die Datei bekommt einen Zähler (`name_1.jpg`, `name_2.jpg`, ...) und geht nicht verloren.

Bei Ordnern wird eine Signatur aus allen relativen Dateipfaden und Dateigrößen verglichen. Ordner werden nie automatisch gelöscht.

## ⚠️ Duplikate löschen

- Die Option gibt es nur bei **Verschieben**. Beim Kopieren sollen die Originale ja bleiben.
- Gelöscht wird nur, wenn der Inhalt per SHA-256 als identisch bestätigt wurde.
- Gelöscht wird in den **Papierkorb**. Auf **Netzlaufwerken gibt es keinen Papierkorb**, dort wird endgültig gelöscht.
- Eingabe- und Ausgabeordner dürfen nicht auf denselben Ort zeigen, auch nicht über verschiedene Namen (z. B. IP-Adresse und Hostname desselben NAS).
- Der Probelauf zeigt, welche Dateien als Duplikat gelöscht würden.

## 🌐 Netzwerkordner

- UNC-Pfade (`\\Server\Freigabe\Ordner`) einfach in das Feld eintippen
- Netzlaufwerke (z. B. `Z:\`) werden intern in den UNC-Pfad umgewandelt
- Braucht die Freigabe eine Anmeldung, einmal im Explorer öffnen und anmelden
- Große Netzwerkordner und das Prüfen von Duplikaten können dauern, vor allem bei großen Dateien

## 📝 Hinweise

- Als Datum wird das **ältere von Erstell- und Änderungsdatum** verwendet, nicht das Aufnahmedatum aus den Foto-Metadaten
- Systemordner, Junctions und der Ausgabeordner selbst werden nicht angefasst
- **Nutzung auf eigene Gefahr.** Erst mit Testdaten und im Probelauf ausprobieren, besonders bei *Verschieben* und *Duplikate löschen*

## 📜 Lizenz

MIT, siehe [LICENSE](LICENSE).

## 🤝 Mitmachen

Bugs und Wünsche gern über den **Issues**-Tab melden.
