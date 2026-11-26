# Uhr-Akku (iPhone)

iPhone-App mit Widget, die den Akkustand einer Wear-OS-Uhr per Bluetooth liest
(Standard-Akkudienst 0x180F / 0x2A19) und im Home- und Sperrbildschirm anzeigt.

Die Uhr stellt den Dienst per BLE bereit, siehe `BatteryGattServer.kt` im Projekt
WearBridge (Wear-OS-Seite).

## Gesundheitsdaten

Die App holt Puls, Schritte, Strecke, Kalorien und Etagen von der Uhr ab und schreibt sie in
Apple Health (`App/HealthSync.swift`). Die Uhr sammelt die Daten im Hintergrund und haelt sie in
einem Zwischenspeicher, aus dem die App ab der letzten bekannten Nummer abholt und quittiert.
Das Protokoll steht im Projekt der Watch-App unter `docs/health-protokoll.md`.
Beim ersten Start auf **Health erlauben** tippen.

## Aufbau

- `App/`: SwiftUI-App, `BleMonitor` verbindet sich dauerhaft mit der Uhr
  (CoreBluetooth, Hintergrundmodus `bluetooth-central`, State Restoration)
- `Widget/`: WidgetKit-Widget (klein, Sperrbildschirm rund und rechteckig)
- `Shared/BatteryStore.swift`: gemeinsamer Speicher ueber die App Group `group.de.wearbattery`
- `project.yml`: XcodeGen-Beschreibung, die Xcode-Projektdatei wird nicht eingecheckt

## Bauen (ohne Mac)

Der Workflow `.github/workflows/build.yml` baut auf einem macOS-Runner eine unsignierte
`WearBattery.ipa` und legt sie als Artefakt ab. Starten ueber Actions, Build IPA, Run workflow.

## Installieren

1. IPA aus dem Artefakt herunterladen (ZIP entpacken).
2. Mit SideStore oder AltStore und der eigenen Apple-ID signieren und installieren.
   Mit einer kostenlosen Apple-ID laeuft die Signatur nach 7 Tagen ab und wird
   von SideStore/AltStore erneuert.
3. App oeffnen, Bluetooth erlauben, auf **Suchen** tippen, die Uhr waehlen.
4. Widget hinzufuegen: Home-Bildschirm gedrueckt halten, Plus, Uhr-Akku.

## Bekannte Grenzen

- Die App-Group-Berechtigung (gemeinsamer Speicher fuer das Widget) muss der
  Signierdienst mitsignieren, sonst bleibt das Widget leer.
- iOS beschraenkt Bluetooth im Hintergrund, der Wert kann verzoegert ankommen.
