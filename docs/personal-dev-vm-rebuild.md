# Persönliche Entwicklungs-VM: Architektur und Wiederaufbau

## Zweck und Grenzen

**Statusnachtrag:** Der alte VM-Stack wurde inzwischen autorisiert gestoppt;
die elf zuvor laufenden Container haben jetzt Restart-Policy `no`. Alle Daten
bleiben erhalten. Backup und Plattenbereinigung stehen noch aus. Details und
die Unterbrechung der abschließenden SSH-Kontrollen stehen im
[Inventar-Nachtrag](personal-dev-vm-inventory.md#nachtrag-stilllegung-am-26-september-2026).
Die Installationsbeschreibung unten hält den ursprünglichen Zustand fest.

Stand: **26. September 2026**, lesend auf Matthias' eigener Ubuntu-VM geprüft.
SSH-Ziel ist der bereits konfigurierte Alias `codex-devbox`, Benutzer `codex`.
Private IP-Adressen, Passwörter, Schlüssel und OAuth-Dateien werden bewusst nicht
in Git dokumentiert. Der SSH-Alias muss auf einem neuen Rechner separat durch
den Eigentümer eingerichtet werden.

Diese Anleitung beschreibt den **alten persönlichen Entwicklungsstack**, nicht
den produktiven VPS und nicht Supabase Cloud. Sie verbindet die beobachtete
Installation mit den versionierten Wiederaufbauquellen. Sie ist **kein Backup**:
gelöschte Testdaten, unversionierte Dateien und Zugangsdaten lassen sich aus
Markdown allein nicht zurückholen. Kein Wiederaufbau wurde jetzt ausgeführt.

Einstiege für einen späteren Agenten:

- [Ressourcen und vollständige Containerliste](personal-dev-vm-inventory.md)
- [Unterstützte lokale Entwicklung](local-dev.md#complete-local-stack)
- [Produktarchitektur und Sicherheitsgrenzen](architecture.md#high-level-shape)
- [Schema und Migrationsinventar](supabase-current-state.md)
- [Backup-/Restore-Regeln](local-database-safety.md)
- [Verifikation](verification.md#verification-levels)

## Die drei getrennten Umgebungen

| Umgebung | Client | Daten und Backend | Braucht die persönliche VM? |
| --- | --- | --- | --- |
| Alter vollständiger VM-Devstack | Flutter Web auf der VM, Zugriff per sicherer Weiterleitung | VM-Supabase und VM-FastAPI | Ja |
| Laptop-Cloudentwicklung | Lokales Flutter Web, optional lokaler API-Proxy | Supabase Cloud und Produktions-VPS; echte Kontodaten | Nein |
| Veröffentlichte App | Vercel-Webapp oder signierte Android-APK | Supabase Cloud und Produktions-VPS | Nein |

Guest-/Mock-Modus bleibt eine vierte, rein lokale Datenquelle ohne authentifizierte
Produktaufrufe. Die separate Produktwebseite unter `apps/website` verwendet eine
synthetische Demo und braucht ebenfalls diesen VM-Stack nicht.

## Verbindungsschema des vollständigen VM-Stacks

```text
Laptop-Browser -- sichere SSH-Portweiterleitung --> VM-Flutter Web
  |                                                  |
  +-- Supabase-Sitzung / publishable key --> Kong -----+--> Auth
  |                                         |        +--> REST --> PostgreSQL
  |                                         |        +--> Storage --> Volume + PostgreSQL
  |                                         |        +--> Realtime --> PostgreSQL
  +-- Bearer-Token --> FastAPI --> owner-geprüfte DB-/RPC-Zugriffe
                         ^
                   lokaler Scheduler

Studio --> Meta / Supabase-APIs --> PostgreSQL
Auth --> Test-Mailserver
Container-Logs --> Vector --> Analytics

Start-Supervisor: Supabase prüfen/starten, Migrationen prüfen,
                 FastAPI + Scheduler + Flutter starten
```

Das ist die logische Dienststruktur, keine Behauptung, dass alle Pfeile beim
Audit aktiv genutzt wurden. **Aktiv waren nur die elf Supabase-Container**;
Flutter, FastAPI und Scheduler wurden nicht als laufende Projektprozesse gefunden.
Die gestoppte Edge Runtime ist ein optionaler Supabase-Baustein.

FastAPI erhält Backend-Zugangsdaten ausschließlich serverseitig. Flutter bekommt
niemals Service-Role-Keys oder Scheduler-Tokens. Supabase-RLS und owner-geprüfte
API-Kommandos bleiben bestehen. Das lokale Testkonto ist nicht automatisch das
gleichnamige Cloud-Konto; die Datenbanken sind getrennt.

## Beobachtete Installation

| Bestandteil | Beobachtung |
| --- | --- |
| Betriebssystem / Architektur | Ubuntu 24.04.4 LTS / x86_64 |
| Docker Engine | 29.1.3 |
| Supabase CLI | 2.107.0 |
| Node / npm | 22.23.2 / 10.9.8 |
| Python | 3.12.3 |
| Hauptcheckout | `/home/codex/code/MyLifeGraph` |
| Alter Checkout-Branch | `preview/morning-evening-check-in` |
| Nicht versionierter Bestand | `.codex-ui-grok-attachments/`; Inhalt nicht untersucht |
| Docker-Netzwerk | `supabase_network_mylifegraph`, Bridge, nicht `internal` |
| Projektkennung | `mylifegraph` in `supabase/config.toml` |

Flutter-/Android-SDK-Versionen wurden in diesem Audit nicht neu bestimmt. Vor
Wiederaufbau anhand des gewählten Repository-Stands und seiner Lockfiles prüfen;
die [Voraussetzungen](local-dev.md#prerequisites) sind die aktuelle Anleitung.
Keine SDKs pauschal löschen: Sie können von anderen Projekten genutzt werden.

### Ports

| Zweck | VM-Hostport | Containerport / Herkunft |
| --- | ---: | --- |
| Supabase Gateway | 54321 | Kong 8000 |
| PostgreSQL | 54322 | DB 5432 |
| Studio | 54323 | Studio 3000 |
| Test-Mail-Weboberfläche | 54324 | Mailpit 8025 |
| Analytics | 54327 | Logflare 4000 |
| FastAPI, alte User-Unit | 8001 | `LOCAL_STACK_AI_PORT`, aktuell nicht gestartet |
| Flutter, alte User-Unit | 7358 | `LOCAL_STACK_FRONTEND_PORT`, aktuell nicht gestartet |

Die fünf Docker-Hostports waren auf **allen IPv4-/IPv6-Schnittstellen** gebunden.
Das beweist ohne Firewall-/Routerprüfung keine Internet-Erreichbarkeit, ist aber
**keine sichere Loopback-Vorlage**. Beim späteren Wiederaufbau projektbezogen auf
Loopback begrenzen und SSH-Tunnel nutzen; nicht ungeprüft die alten Bindings
kopieren oder globale Docker-/Firewall-Regeln anderer Projekte verändern.
Die normalen Repository-Defaults sind FastAPI 8000 und Flutter 7357; die alte
User-Unit überschreibt sie. Bei SSH-Weiterleitung müssen die im Browser verwendeten
Client-Endpunkte und Auth-Redirects zusammenpassen. Nicht private Docker-IP-Adressen
im Client verwenden.

### Images des Altbestands

Alle Referenzen beginnen mit `public.ecr.aws/supabase/`. Sie dokumentieren die
alten Container, **nicht** eine freigegebene neue Versionskombination:

| Container-Kurzname | Image und Tag |
| --- | --- |
| studio | `studio:2026.08.10-sha-5b68af1` |
| pg_meta | `postgres-meta:v0.97.0` |
| storage | `storage-api:v1.69.0` |
| rest | `postgrest:v16.1` |
| realtime | `realtime:v2.124.4` |
| inbucket | `mailpit:v1.30.2` |
| auth | `gotrue:v2.195.0` |
| kong | `kong:2.8.1` |
| vector | `vector:0.53.0-alpine` |
| analytics | `logflare:1.50.2` |
| db | `postgres:15.8.1.085` |
| edge_runtime, gestoppt | `edge-runtime:v1.74.3` |

**Bekannte Inkompatibilität:** Der vorhandene DB-Container ist PostgreSQL 15,
während `supabase/config.toml` im alten VM-Checkout und im aktuellen Laptop-Checkout
`major_version = 17` verlangt. Migrationshistorie wurde hier nicht abgefragt;
die genaue frühere Fehlermeldung wurde nicht erneut untersucht. Keinesfalls das
PG15-Datenvolume einfach an ein PG17-Image hängen, historische Migrationen ändern
oder mit Reset einen Start erzwingen. Altbestand sichern und einen getrennten,
kontrollierten logischen Restore/Upgrade planen, falls seine Daten benötigt werden.

## Dateien, persistente Daten und Secrets

| Ablage | Rolle / Wiederherstellung |
| --- | --- |
| Hauptcheckout, `apps/mobile` | Flutter-Client; Quelle ist Git, lokaler Diff separat sichern |
| Hauptcheckout, `services/ai_service` | FastAPI; Abhängigkeiten gemäß versionierten Python-Dateien wiederherstellen |
| Hauptcheckout, `supabase/config.toml`, `supabase/migrations`, `supabase/tests` | Stack-Konfiguration, Schemahistorie, DB-Tests; aus passendem Git-Stand |
| Hauptcheckout, `scripts` | Start-Supervisor, Migration-Preflight, Tests, Backup-/Reset-Schutz |
| `supabase_db_mylifegraph` | Persistentes PostgreSQL-Volume, gemountet unter `/var/lib/postgresql/data` |
| `supabase_storage_mylifegraph` | Persistente Storage-Dateien, gemountet unter `/mnt` |
| `supabase_edge_runtime_mylifegraph` | Unreferenziertes Volume, beim Inventar ohne Nutzdaten |
| `supabase/snippets` im Hauptcheckout | Beschreibbarer Studio-Bind-Mount |
| `supabase/.temp/start-secrets/.../main/index.ts` | Generierter Edge-Runtime-Bind-Mount nach `/root/index.ts`; temporär/privat, nicht veröffentlichen |
| `/var/run/docker.sock` | Vector bindet den Docker-Socket read-only ein; privilegierte Docker-Verbindung, kein Projektdatenbackup |
| `.env` im Hauptcheckout | Vorhandene lokale Konfiguration; Inhalte nicht gelesen. Werte privat neu provisionieren, `.env.example` ist nur das Schema |
| `.tools/local-stack` | Private Supervisor-Laufzeitdateien und Logs; keine Git-Quelle |
| `.tools/supabase-backups` | Vorgesehener Backup-Ausgabeordner; Vorhandensein gültiger Backups hier nicht behauptet |
| `~/.config/systemd/user/mylifegraph-local.service` | Alte lokale User-Unit, siehe unten |
| `~/.local/bin/build-mylifegraph-lan` | Maschinenlokaler Build-Helfer; vorhanden, nicht vollständig auditiert/versioniert |
| `~/.local/share/mylifegraph-lan-build` | Generierter LAN-Webbuild |
| `~/.local/state/mylifegraph` | Lokaler Zustand des VM-Workflows |
| `~/mylifegraph-validation-20260916.12bski` | Alter Validierungsbestand; vor Löschung auf einmalige Artefakte prüfen |
| `~/code/MyLifeGraph-debug-apk` | Kleiner zusätzlicher Projektpfad; vor Löschung Inhalt/Zweck nochmals prüfen |

Git stellt Code und Konfigurationstemplates wieder her, **nicht** Auth-Nutzer,
Check-ins, hochgeladene Dateien oder unversionierte Helfer. Der DB-Backup-Wrapper
sichert Datenbankinhalte, nicht automatisch das Storage-Dateivolume, alle lokalen
Helfer oder private Konfiguration. Diese benötigen bei Bedarf separate geschützte
Sicherung außerhalb der später zu löschenden VM-Pfade. OAuth-Zustand nicht kopieren
oder auslesen; für optionale Provider später nativ neu anmelden.

## Alter Startmechanismus und sichere Alternative

Die User-Unit hat `WorkingDirectory=/home/codex/code/MyLifeGraph`, startet
`npm run start:local`, setzt die beiden Ports 8001/7358 und verwendet
`Type=simple`, `After=network-online.target`, `WantedBy=default.target`,
`Restart=on-failure`, `RestartSec=15`. Sie ist **deaktiviert und inaktiv**.
Die elf Docker-Container sind dagegen separat mit `unless-stopped` konfiguriert.

Den automatischen 15-Sekunden-Retry **nicht** als empfohlenes Setup wiederherstellen.
Der Repository-Supervisor beendet sich absichtlich bei Migrationskonflikten; ein
blind neu startender Service macht daraus eine Ressourcen verschwendende Schleife.
Zuerst einen manuellen, nachvollziehbaren Start herstellen. Autostart nur nach
erfolgreicher Prüfung und einem separat gewünschten Betriebsplan einrichten.

## Wiederaufbau in sinnvoller Reihenfolge

Diese Schritte gelten erst bei einem zukünftigen ausdrücklichen Wiederaufbauauftrag:

1. **Ziel auswählen:** Laptop-Cloudmodus, frischer isolierter VM-Teststack oder
   Wiederherstellung der alten VM-Daten. Nicht mit Produktionszugängen vermischen.
2. **Bestand sichern:** Git-Status und unversionierte Anhänge/Helfer prüfen;
   geschützte Konfiguration separat sichern. Datenbank mit dem dokumentierten
   `npm run db:backup:local`-Workflow sichern und dessen isolierten Restore prüfen.
   Vorher dessen Kompatibilität zum alten Checkout/PG15 prüfen; bei Ablehnung
   Schutz nicht umgehen. Storage-Dateien zusätzlich sichern. Backup nicht im
   einzigen später zu löschenden Verzeichnis belassen.
3. **Code bereitstellen:** Den bewusst gewählten Git-Stand aus dem Projekt-Repository
   beziehen, `AGENTS.md` und dessen Besitzer-Dokumente lesen. Nicht blind den alten
   VM-Branch zur aktuellen Quelle erklären; lokale Änderungen/Anhänge erhalten.
4. **Werkzeuge bereitstellen:** Unterstützte Flutter/Dart-, Python-, Node/npm-,
   Docker- und Supabase-Versionen prüfen. Vor Supabase-Befehlen installierte Hilfe
   lesen. Lockfiles verwenden und die Installationsanweisungen in
   [Local Development](local-dev.md#prerequisites) beachten; keine privaten
   Werkzeugkopien ins Repository installieren.
5. **Datenbank bewusst aufbauen:** Für neue Testdaten einen frischen isolierten
   Entwicklungsstack mit passender PG-Version verwenden. Für alte Daten einen
   geprüften logischen Restore in einen separaten Zielcluster durchführen.
   Das PG15-Original bleibt bis erfolgreicher Abnahme unangetastet. Die
   Migrationshistorie muss zum gewählten Code passen; Apply nur nach SQL-/Datenprüfung
   und explizitem Opt-in, niemals impliziter Reset.
6. **Private Konfiguration:** `.env.example` als Vorlage verwenden, bestehende
   `.env` nicht überschreiben. Lokale Supabase-URL und öffentliche Client-Key-Werte
   korrekt setzen; Backend-Credentials ausschließlich im Backend. Auth-Redirects
   an die tatsächlich verwendete lokale Browseradresse anpassen. Mock-Modus
   deaktivieren, wenn echte lokale Testkonten verwendet werden sollen.
7. **Manuell starten:** `npm run start:local` aus dem Projekt. Falls die alten
   VM-Ports nötig sind, vorher `LOCAL_STACK_AI_PORT=8001` und
   `LOCAL_STACK_FRONTEND_PORT=7358` setzen. Der sichere Standard aktiviert keine
   Modellantworten; deterministische Coach-Tests nutzen
   `npm run start:local:coach:fake`. Echte Provider sind ein eigener Opt-in.
8. **Abnehmen:** Migration-Preflight, Dienststatus, Loopback-Bindings, Login und
   einen lokalen Schreib-/Lesetest prüfen. Gates nach
   [Verification](verification.md) auswählen; echte Cloud-Daten nicht als
   Testfixtures verwenden. Auch nach Beenden des Supervisors kann Supabase
   weiterlaufen – Containerstatus separat kontrollieren.

Für den gewünschten künftigen **Laptop-Cloudworkflow** genügt stattdessen der
in [Local Development](local-dev.md#personal-windows-browser-with-existing-cloud-accounts)
beschriebene `node scripts/start_cloud_frontend.mjs`: Flutter auf Loopback 7357,
API-Proxy auf Loopback 8003, echte bestehende Cloud-Dienste. Kein VM-Docker nötig.

## Vor einer späteren Bereinigung

Für zukünftige veröffentlichte Build-Kopien gilt zusätzlich die
[begrenzte Release-Bereinigung](local-release-retention.md): nur der markierte
Artefaktordner, erst nach Upload-/SHA-256-Prüfung, mit Dry-Run und Wiederholschutz.
Das gibt keine Löschfreigabe für alte Datenbanken, Container, Backups, Anhänge,
Server-Rückfallversionen oder unregistrierte Altbestände. Installation und
Prüfnachweise stehen im aktuellen Verification-Baseline-Abschnitt.

- Testcode und CI im Repository **behalten**. Wegfallen kann die alte laufende
  VM-Testumgebung, nicht die Fähigkeit, weiterhin Regressionstests auszuführen.
- Zuerst genau diese elf Container stoppen und Wiederanlauf prüfen; das spart
  etwa 1,6 GiB RAM und den im Inventar gemessenen CPU-Anteil, aber keinen Plattenplatz.
- Danach nur auf separaten Löschauftrag gesicherte Projektcontainer, Images,
  Artefakte und gegebenenfalls Volumes entfernen. Image-Sharing vorher prüfen.
- Kein globales Docker-Prune, keine fremden Projekte, SDKs, Produktionsdienste
  oder Supabase-Cloud-Daten anfassen.
- Offene Punkte vor Datenlöschung: geprüfter DB-/Storage-Backup-Nachweis,
  Sicherung unversionierter Anhänge/Helfer, gewählter Wiederherstellungs-Git-Stand.

Ressourcenwerte und Messgrenzen stehen im [Inventar](personal-dev-vm-inventory.md).
Eine neue VM mit diesen Anweisungen wurde noch nicht testweise aufgebaut; die
Dokumentation ersetzt daher keine Wiederherstellungsprobe und keine Datensicherung.
