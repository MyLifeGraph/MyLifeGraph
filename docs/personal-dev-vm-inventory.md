# Persönliche Entwicklungs-VM: MyLifeGraph-Inventar

## Nachtrag: Stilllegung am 26. September 2026

Nach ausdrücklicher Freigabe des Eigentümers wurden die unten dokumentierten
elf laufenden Projektcontainer gestoppt und ihre Restart-Policy von
`unless-stopped` auf `no` gesetzt. Die Edge Runtime blieb gestoppt. Die
User-Unit war bereits deaktiviert/inaktiv und wurde nicht aktiviert.
Andere laufende Docker-Container waren vor/nach der Aktion identisch.
Alle drei Projektvolumes, Images, Checkout-Dateien und Testquellen bleiben erhalten.
**Kein Plattenplatz wurde gezielt freigeräumt; eine neue geprüfte Sicherung
wurde noch nicht erstellt.** Die folgenden Inventartabellen beschreiben den
Zustand vor dem Stoppen, nicht weiterhin laufende Dienste.

Beim ersten Stop überschritten Kong, Vector, Analytics und PostgreSQL das
30-Sekunden-Limit (Exit 137). Die Datenbank wurde deshalb allein nochmals gestartet:
`pg_isready` und ein lesendes `SELECT 1` waren erfolgreich. Nach gezieltem
PostgreSQL-Fast-Shutdown bestätigte Docker `running=false`, `exit=0`, `restart=no`.
Der dabei laufende `docker exec pg_ctl` lieferte selbst keinen erfolgreichen
Returncode; maßgeblich beobachtet wurde der beendete Container mit Exit 0.
Das ist keine vollständige Datenintegritätsprüfung oder Restore-Verifikation.

Anschließend scheiterten zusätzliche SSH-Kontrollen sowohl zur VM als auch zum
Proxmox-Host mit Timeout. Keine Ursache belegt, kein Host-Neustart ausgeführt.
Weitere Sicherung/Löschung bleibt ausstehend. Vor Fortsetzung Status erneut lesen.

### Letzte gemessene Gesamtkapazitäten

| Ebene | RAM | Festplatte / Storage |
| --- | --- | --- |
| Entwicklungs-VM | Proxmox-Zuweisung 11 GiB; Gast meldet 10,70 GiB nutzbar | Virtuelle Disk 100 GiB / 107,37 GB; Root-Dateisystem 102,89 GB |
| VM nach erstem Stop | 3,71 GiB verwendet, 6,99 GiB verfügbar | Root 63,35 GB belegt, 39,53 GB verfügbar |
| Proxmox-Host | Betriebssystem meldet 15,34 GiB nutzbar; zuletzt 12,39 GiB verwendet, 2,95 GiB verfügbar; Swap 8 GiB | Interne NVMe 512,11 GB; zusätzlich zwei USB-Datenträger mit jeweils 62,91 GB |
| Proxmox-System-Dateisystem | — | 100,86 GB gesamt, 68,51 GB belegt, 27,18 GB verfügbar |
| Proxmox-VM-Thinpool `local-lvm` | — | 374,54 GB gesamt, ca. 131,43 GB belegt, 243,11 GB verfügbar |
| USB-Backup-Dateisystem | — | 61,60 GB gesamt, 23,47 GB belegt, 37,48 GB verfügbar |
| Zusätzliches USB-Dateisystem | — | 62,90 GB gesamt, ca. 0,02 GB belegt, 62,88 GB verfügbar |

GB sind dezimal, GiB binär. Insgesamt physisch sichtbar: ca. **637,94 GB**
(512,11 GB intern plus 125,83 GB USB). Die VM-Disk liegt im Proxmox-Thinpool:
**VM und Host dürfen nicht addiert werden**. System- und Thinpool-Freiplatz sind
verschiedene Speicherbereiche; nicht jeder freie Block ist für jeden Zweck
direkt verfügbar. Reservierte Dateisystemblöcke erklären Abweichungen zwischen
Gesamt, belegt und verfügbar. Thin-Provisioning/Discard kann Gast- und
Hostbelegung zusätzlich unterscheiden.

Vor dem Stop: Gast-RAM 5,19 GiB verwendet, 5,51 GiB verfügbar; danach rund
**1,48 GiB zusätzlich verfügbar**. Momentaufnahme mit anderen aktiven Workloads,
kein isoliertes Benchmark. Die VM behält ihre 11-GiB-Zuweisung; freier RAM im Gast
muss nicht sofort als freier RAM auf dem Proxmox-Host erscheinen.

Nächster sicherer Schritt nach wiederhergestellter Verbindung: Projektstatus
erneut prüfen, PG15-kompatible Backup-/Restore-Voraussetzungen klären,
Datenbank/Storage und unversionierte Dateien geschützt sichern. Erst danach
über gezielte Plattenbereinigung entscheiden. Keine globale Docker-Bereinigung.

## Geltungsbereich

Die zugehörige [Architektur und Wiederaufbau-Anleitung](personal-dev-vm-rebuild.md)
beschreibt Verbindungen, Ports, Datenablagen und die sichere Rekonstruktion.

Lesende Bestandsaufnahme vom **26. September 2026** auf Matthias' eigener
Entwicklungs-VM (bestehender SSH-Alias `codex-devbox`). Nicht der produktive VPS,
nicht Supabase Cloud und nicht andere Projekte. Keine Dienste wurden gestoppt,
keine Daten gelöscht und keine Konfiguration verändert. Private IP-Adressen und
Zugangsdaten gehören nicht in diese Notiz.

Die Werte sind Momentaufnahmen, keine dauerhafte Zustandszusage. Vor einer
späteren Bereinigung Namen, Nutzung und Größen erneut prüfen. Der Laptop-
Cloudworkflow benötigt diesen Stack nicht; siehe [Local Development](local-dev.md).
Produktionsdienste bleiben separat; siehe [Entwicklungsübergabe](development-handoff.md).

## Dienste und Arbeitsspeicher

Alle folgenden laufenden Container tragen exakt das Präfix `supabase_` und den
Suffix `_mylifegraph`. Beispiel: `supabase_db_mylifegraph`.

| Name zwischen Präfix und Suffix | Aufgabe | RAM (MiB) | CPU, zweite Stichprobe | Prozesse |
| --- | --- | ---: | ---: | ---: |
| studio | Verwaltungsoberfläche | 200,60 | 0,01 % | 1 |
| pg_meta | Datenbank-Metadaten-API | 100,00 | 14,70 % | 1 |
| storage | Dateispeicher-API | 151,40 | 0,01 % | 1 |
| rest | REST-Datenzugriff | 18,77 | 0,10 % | 1 |
| realtime | Echtzeitdienst | 200,60 | 0,52 % | 9 |
| inbucket | Test-Mailserver (Mailpit-Image) | 13,24 | 0,00 % | 1 |
| auth | Authentifizierung | 11,70 | 0,00 % | 1 |
| kong | API-Gateway | 115,80 | 0,01 % | 3 |
| vector | Log-Sammlung | 27,82 | 0,01 % | 2 |
| analytics | Log-Auswertung | 573,70 | 6,80 % | 10 |
| db | PostgreSQL | 234,60 | 0,57 % | 34 |
| **Summe** | **11 laufende Container** | **1.648,23** | **22,73 %** | **64** |

- RAM: **ca. 1,61 GiB** (1,73 GB dezimal). Die vorherige Stichprobe lag bei
  1.684,62 MiB; grob also 1,6 GiB. Docker-Statistik, ohne pauschale Zurechnung
  des gemeinsamen Docker-Daemons oder des gesamten Host-Caches.
- CPU: zusammen **18,63 % bzw. 22,73 % eines CPU-Kerns** in zwei Stichproben,
  nicht 23 % der gesamten Mehrkern-VM und kein Langzeitmittel. Vor allem
  `pg_meta` und zeitweise `analytics` waren aktiv.
- **64 Prozesse**, beziehungsweise **176 Tasks inklusive Threads** laut Docker.
  Prozesszählung über `docker top`, Threadzählung über `docker stats`.
- Alle elf laufenden Container hatten `unless-stopped` als Restart-Policy und
  liefen seit vier Tagen. Ein deaktivierter App-Service verhindert diesen
  separaten Docker-Wiederanlauf nicht.
- `supabase_edge_runtime_mylifegraph`: vorhanden, aber gestoppt, Restart-Policy
  `no`; deshalb kein laufender RAM-/CPU-Anteil in der Tabelle.
- User-Unit `mylifegraph-local.service`: installiert, **disabled / inactive / dead**,
  `MainPID=0`. Die frühere App-Neustartschleife war nicht aktiv.
- Keine weiteren laufenden MyLifeGraph-App-Prozesse in der lesbaren Prozessliste
  gefunden (Zuordnung über Projektpfade, ohne Ausgabe von Argumenten/Secrets).

## Festplattenbelegung

Erhoben gegen 00:44 UTC (02:44 Europe/Berlin). **GB hier dezimal**, GiB binär.
Volumes, Projektverzeichnisse und aktuelle Container-Logs wurden mit `du -B1`
gemessen; Image-/Writable-Layer-Werte stammen aus Dockers Speicherbilanz.

| Bestandteil | Belegung ca. |
| --- | ---: |
| Zwölf referenzierte Docker-Images einschließlich gestoppter Edge Runtime, interne gemeinsame Schichten einmal gezählt | 9,500 GB |
| Datenbank-Volume `supabase_db_mylifegraph` | 0,932 GB |
| Storage-Volume `supabase_storage_mylifegraph` | 8 KiB |
| Checkout `~/code/MyLifeGraph` einschließlich darin enthaltener Artefakte | 0,727 GB |
| Validierungsverzeichnis `~/mylifegraph-validation-20260916.12bski` | 0,501 GB |
| LAN-Build `~/.local/share/mylifegraph-lan-build` | 0,065 GB |
| Aktuelle Container-Logs zusammen | 0,126 GB |
| Beschreibbare Container-Schichten zusammen | 0,005 GB |
| `~/code/MyLifeGraph-debug-apk`, `~/.local/state/mylifegraph`, User-Service-Datei zusammen | 24 KiB |
| **Bilanzierte Summe** | **ca. 11,86 GB / 11,04 GiB** |

Das unreferenzierte Volume `supabase_edge_runtime_mylifegraph` meldete 0 Byte
Nutzdaten in Docker. Die Service-Datei liegt unter
`~/.config/systemd/user/mylifegraph-local.service`.

Die Image-Summe vor Bereinigung interner Doppelzählung betrug 9.755.373.946 Byte.
Studio/Meta teilen 246.652.928 Byte und Auth/Mailpit 9.072.640 Byte; jeweils einmal
abgezogen ergibt dies 9.499.648.378 Byte. Auch mit anderen Images besteht ein
Layer-Overlap. Daher ist die Gesamtsumme **eine gerundete zugeordnete Belegung,
keine garantierte Löschersparnis oder exakte physische Datenträgerbilanz**.
Docker-Metadaten, mögliche rotierte Logs, gemeinsame SDK-/Paket-Caches und nicht
eindeutig diesem Projekt zuordenbare Build-Caches sind nicht mitgerechnet.
Die kumulierten Block-I/O-Werte aus `docker stats` sind keine Festplattengröße.

## Spätere Stilllegung: Entscheidungshilfe, kein ausgeführter Auftrag

1. Für reine Laptop-Entwicklung kann der alte VM-Stack stillgelegt bleiben.
   Zuerst nur die exakt benannten Projektcontainer stoppen und Wiederanlauf
   kontrollieren; Datenbank- und Storage-Volumes zunächst behalten.
2. Stoppen spart Laufzeit-RAM/CPU, **nicht** die oben belegte Festplatte.
3. Vor Löschen von Volumes oder Projektverzeichnissen vorhandene Daten,
   uncommittete Arbeit und Backups prüfen. Lokale Daten erst nach einer
   wiederherstellungsgeprüften Sicherung und ausdrücklichem Löschauftrag entfernen.
   Den [Datenbank-Sicherheitsworkflow](local-database-safety.md) beachten.
4. Images nur nach erneuter Abhängigkeitsprüfung gezielt entfernen. Kein globales
   Docker-Prune, kein Entfernen gemeinsamer SDKs oder anderer Projekte.
5. Produktions-VPS und Supabase Cloud sind keine Ziele dieser Stilllegung.

## Erhebungsmethode

Nur lesend: systemd-Unit-Status, gefiltertes `docker ps`, `docker stats`,
`docker top`, gezielte Container-/Image-/Volume-Metadaten, Dockers `system/df`
und `du` auf den oben benannten Pfaden. Für geschützte Docker-Verzeichnisse wurde
`sudo -n du` verwendet. Keine Datenbankabfragen, keine Supabase-Migrationen,
keine Einsicht in `.env` oder OAuth-Dateien. Nicht als neuen Startauftrag verwenden.
