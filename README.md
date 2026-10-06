# Datei-Sortierer 📁⚡

Ein Windows-Tool zum automatischen Sortieren von Bildern, Videos, Musik, Dokumenten, Anwendungen und ZIP-Dateien nach Datum (Jahr/Monat).

## Features

✨ **Grafische Oberfläche** – Keine Kommandozeile nötig  
📅 **Mehrere Sortier-Modi** – Nur Jahr, Jahr/Monat oder flach  
📁 **Unterordner-Verwaltung** – Als Ganzes mitnehmen oder einzelne Dateien sortieren  
🎬 **Dateitypen** – Bilder, Videos, Musik, Dokumente, .exe, .zip  
🔍 **Probelauf** – Vor dem echten Sortieren anschauen, was passiert  
🖼️ **Lichtschwert-Ladebalken** – Weil es cool aussieht  
✅ **Duplikat-Erkennung** – Gleichnamige Dateien mit gleichem Inhalt werden übersprungen

## Requirements

* **Windows 7 oder neuer**
* **PowerShell 5.0+** (ist bereits eingebaut)
* `.NET Framework` (ist bereits eingebaut)

## Installation

1. Beide Dateien in einen Ordner legen:

   * `sortieren\_gui.ps1`
   * `start\_sortierer.bat`
2. **`start\_sortierer.bat` doppelklicken** – Das Fenster öffnet sich.

Wenn Windows eine Sicherheitswarnung zeigt: "Ausführen" klicken.

**Alternativ (manuell):**

```
powershell -ExecutionPolicy Bypass -File .\\sortieren\_gui.ps1
```

## Bedienung

1. **Eingabeordner** wählen (wo die unsortierten Dateien liegen)
2. **Ausgabeordner** wählen (wo die sortierten Dateien landen sollen)
3. **Einstellungen** wählen:

   * Ordnerstruktur (Nur Ausgabeordner / Jahr / Jahr\\Monat)
   * Welche Dateien (Nur Hauptordner / Alle inkl. Unterordner)
   * Aktion (Kopieren / Verschieben)
   * Dateitypen (an- oder abwählbar)
4. **Probelauf** empfohlen: Erst anschauen, was passiert
5. **Sortieren starten**

### Beispiel-Struktur nach dem Sortieren

**Ohne "Alle Typen in eigene Ordner trennen":**

```
Ausgabeordner\\
├── 2024\\
│   ├── 03\\
│   │   ├── urlaub.jpg
│   │   ├── video.mp4
│   │   └── musik.mp3
│   └── 07\\
│       └── doc.pdf
├── Anwendungen\\  (immer separat)
│   └── 2024\\03\\
│       └── installer.exe
└── ZIP\\  (immer separat)
    └── 2024\\08\\
        └── backup.zip
```

**Mit "Alle Typen in eigene Ordner trennen":**

```
Ausgabeordner\\
├── Bilder\\2024\\03\\urlaub.jpg
├── Videos\\2024\\07\\video.mp4
├── Musik\\2024\\03\\musik.mp3
├── Dokumente\\2024\\07\\doc.pdf
├── Anwendungen\\2024\\03\\installer.exe
└── ZIP\\2024\\08\\backup.zip
```

## Wichtige Infos

⚠️ **Probelauf zuerst machen!** – Der ist standardmäßig aktiviert. Da werden keine echten Dateien angefasst.

⚠️ **Verschieben hat keine Undo** – Bei Verschieben sind die Originale weg. Nur für Profis.

✅ **Kopieren ist sicher** – Originale bleiben stehen, dafür brauchst du Festplattenspeicher.

🔄 **Duplikat-Logik** – Dateien mit gleichem Namen und gleicher Größe/Inhalt werden übersprungen.

📁 **Unterordner mit "Unterordner als Ganzes mitnehmen"** – Der Inhalt wird komplett kopiert/verschoben, nicht sortiert. Perfekt für Projekte o. ä.

## Lizenz

[MIT License](LICENSE)

## Author

Felix Wohlers

\---


Erstellt für schnelles und sicheres Sortieren von Datei-Chaos auf Windows.

\---

**Bugs melden oder Features suggerieren?** – [Issues](../../issues) erstellen.

