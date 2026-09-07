# VPS-Abschluss für Matthias und Gregor

Diese Übergabe setzt die bereits geprüfte VPS-Einrichtung fort. Ziel:
`openclaw-01`, `178.104.87.50`. Sie beschreibt den vorbereiteten Abschluss für
API, Coach, HTTPS und Dienststart nach Neustart. Den zuletzt beobachteten Stand
und die Release-Identität dokumentiert der
[RC4-Prüfnachweis](verification.md#rc4-administrator-handoff-2026-09-07).
Vor Änderungen den tatsächlichen Serverzustand prüfen; ein späterer `git pull`
beweist weder Dienststatus noch unveränderte Staging-Dateien.

## Einstieg für Matthias und seinen Agenten

Zuerst `AGENTS.md` lesen. Bei VPS-Arbeit diese Anleitung und die
[VPS-Betriebsregeln](../deploy/vps/README.md) verwenden. Für einen lokalen
Projektstart gilt stattdessen die
[lokale Entwicklungsanleitung](local-dev.md#complete-local-stack).
Die bisherigen Benutzer-, Runtime-, Codex- und Journal-Bootstraps auf diesem
Server nicht erneut ausführen. Bestehendes Journal und Codex-Anmeldung erhalten.

Das geprüfte, geheimnisfreie Paket liegt bereits auf dem VPS:

- `/srv/mylifegraph-work/rc4-staging/setup.tar`
- `/srv/mylifegraph-work/rc4-staging/README-MATTHIAS.md` (ursprüngliche Übergabekopie)

Der Abschluss braucht keine Dateien von Gregors lokalem Rechner oder aus `/tmp`.
Das Archiv enthält Release, Quellmanifest, Installer, Konfiguration ohne Key
und Prüfskripte. Es wird als Deployment-Artefakt auf dem VPS gehalten, nicht als
Binärdatei in Git. Fehlt es oder stimmt die Prüfsumme unten nicht, abbrechen und
ein neues geprüftes Paket vorbereiten; keine andere Datei unter gleichem Namen
ungeprüft ausführen. Dieser Handoff-Commit ersetzt nicht die im Paket festgelegte
RC4-Anwendungsrevision.

Für die vollständige Serverbetreuung ist das
[Projektbetreuer-Paket](../deploy/vps/PROJECT_ADMIN.md) vorbereitet. Ein
`ops`-Administrator muss diese Rechte einmal installieren; bis dahin bleibt
Matthias' Zugang auf die bisherige SSH-Rolle beschränkt. Danach kann Matthias
selbst am Server entwickeln, konfigurieren und deployen. Die externen Zugriffe
auf GitHub, Supabase und Vercel sind laut Gregor bereits vorhanden.

Matthias bereitet Domain und Key vor. Nach Installation der Betreuerrolle führt
er den Abschluss selbst mit `sudo /usr/local/sbin/mylifegraph-project setup` aus. Danach folgen
Vercel-Konfiguration und Browser-Abnahme. Aktuell sind weder AWS noch
Backup-Einrichtung Teil dieses Auftrags. Für Supabase-Agentenarbeit ausschließlich
den direkten Supabase-MCP verwenden, nicht das Supabase-Plugin. Zugangsdaten und
Codex-OAuth-Dateien niemals auslesen oder in Chat/Repository übernehmen.

## Matthias’ SSH-Zugang testen

Der Administrator hat beide Geräteschlüssel für `mylifegraph-matthias`
freigeschaltet. Der [Zugangs-Prüfnachweis](verification.md#matthias-ssh-enrollment-installed-2026-09-07)
enthält die unabhängig gelesenen Schlüssel- und Server-Fingerprints. Den
Zugangsinstaller für diese Schlüssel nicht erneut ausführen. Private
Geräteschlüssel bleiben bei Matthias; er erhält keine Sudo- oder Deployment-Rechte.

Auf Laptop und VM jeweils mit dem dortigen privaten Schlüssel testen. Den
Platzhalter durch den tatsächlichen Dateipfad ersetzen (ohne `.pub`):

```bash
ssh -i /pfad/zum/privaten_schluessel \
  -o IdentitiesOnly=yes -o HostKeyAlgorithms=ssh-ed25519 \
  mylifegraph-matthias@178.104.87.50
```

Beim ersten Login den angezeigten Server-Fingerprint mit dem Prüfnachweis
abgleichen. Danach `whoami`, `id` und den Zugriff auf `/srv/mylifegraph-work`
prüfen. Eine mögliche Passphrase-Abfrage betrifft Matthias' Geräteschlüssel.
Die tatsächlichen Logins von beiden Geräten sind noch nicht bestätigt.
Gregor hat inzwischen einen erfolgreichen Login gemeldet; die getrennte
Abnahme beider Geräte steht noch aus. Die weitergehenden Betreuerrechte sind
noch nicht installiert.

## 1. Matthias: Domain und Supabase-Key vorbereiten

- Eine API-Subdomain wählen, beispielsweise `api.eure-domain.de`.
- DNS: **A → 178.104.87.50**, ohne DNS-Proxy und vorerst ohne AAAA-Eintrag. Auf die DNS-Verteilung warten. TCP 80 und 443 müssen zum VPS durchkommen, auch durch eine eventuell aktive Hetzner-Firewall.
- Im **Pilotprojekt `oscrunlndfrecjilojja`** einen Supabase **Secret API Key (`sb_secret_…`)** bereithalten. Kein Publishable/Anon-Key. Der Key wird später verdeckt direkt am Server eingegeben; nicht in Chat, Git oder Vercel-Frontendvariablen ablegen.

Die Browseradresse bleibt zunächst `https://my-life-graph-mu.vercel.app`. Eine neue eigene App-Domain erfordert zusätzlich eine passende CORS-Konfiguration.

## 2. Anwendung aktivieren

Nach Installation der [Betreuerrolle](../deploy/vps/PROJECT_ADMIN.md) nutzt
Matthias im interaktiven SSH-Terminal:

```bash
sudo /usr/local/sbin/mylifegraph-project setup
```

Er braucht dafür Gregors Passwort nicht. Währenddessen keine zweite Installation
oder manuelle Dienstkonfiguration starten. Der folgende bisherige `ops`-Befehl
bleibt nur für Hosts ohne diese Delegation; nach Installation der Betreuerrolle
ist das RC4-Paket bereits versiegelt und wird über `setup` aufgerufen.

Erst ausführen, wenn Domain und Key bereitstehen. Das Skript fragt beides ab, prüft den Datenbankzugriff und schaltet danach HTTPS, API und Coach ein:

```bash
sudo /bin/bash -c '
  set -euo pipefail
  target=/root/mylifegraph-rc4
  staging=/srv/mylifegraph-work/rc4-staging
  test ! -e "$target"
  test ! -L "$target"
  install -d -o root -g root -m 0700 "$target"
  install -o root -g root -m 0400 "$staging/setup.tar" "$target/"
  cd "$target"
  printf "%s  %s\n" \
    "4dbb604dc2798ec545bc083517ce713304f464af46f79225e899415a6b8336ce" \
    setup.tar | /usr/bin/sha256sum --check
  /usr/bin/tar --extract --file setup.tar \
    --no-same-owner --no-same-permissions
  /bin/bash install.sh
'
```

Erfolg: Die letzte JSON-Zeile meldet `state: passed`, `https_verified: true`, `api_and_coach_active: true` und `boot_enabled: true`. Geprüft werden der exakte Release, Datenbankvertrag, optionale Teilnahmebestätigung, lokales Löschjournal und Coach-Bereitschaft. Der Installer selbst sendet keine Modellanfrage.

Falls eine Eingabe oder Prüfung fehlschlägt: nur die ausgegebene Phase/Fehlermeldung weitergeben, niemals den Key. Nach einem sauberen Abbruch kann Matthias `setup` erneut aufrufen, sofern die Betreuerrolle installiert ist. Ohne diese Rolle kann der Administrator denselben bereits versiegelten Installer erneut starten:

```bash
sudo /bin/bash -c 'set -euo pipefail; cd /root/mylifegraph-rc4; /bin/bash install.sh'
```

Nur wiederholen, wenn keine Rücknahmefehler (`failed_steps`) gemeldet wurden. Nach erfolgreicher Aktivierung nicht erneut ausführen. Das Skript stoppt bei vorhandener aktiver Konfiguration.

Bei einem Fehler während des Starts versucht der Installer, die Dienste zu stoppen und die von ihm erstellte Konfiguration zurückzunehmen. Das macht keine Datenbankänderungen oder bereits bearbeitete Anfragen rückgängig: Der normale API-Start kann bestehende Vorgänge abgleichen. Journal, bestehende Releases und Codex-Anmeldung bleiben erhalten. Backups werden wie vereinbart nicht eingerichtet.

## 3. Frontend verbinden

Nach erfolgreichem VPS-Abschluss im Vercel-Projekt `my-life-graph` für den Pilot-/Produktionsbuild `AI_SERVICE_BASE_URL=https://<API-Subdomain>` setzen und den Build erneut ausführen. Der Supabase-Secret-Key gehört ausschließlich auf den VPS. Bereits vorhandene Vercel-Buildfehler sind ein separater offener Punkt; dieses Paket behebt sie nicht automatisch.

Danach mit einem vorhandenen Testkonto anmelden und einen Coach-Dialog im Browser testen. Erst dieser Test bestätigt den vollständigen Weg vom Frontend über die API bis zum Coach.

## Nach dem Abschluss

Die letzte Installer-Ausgabe und die Browser-Abnahme ohne Geheimnisse in
[Verification](verification.md#current-verified-baseline) dokumentieren. Dabei
Vorbereitung, tatsächlichen Dienststart und erfolgreichen Browserdialog getrennt
benennen. Wenn noch etwas fehlschlägt, die konkrete Phase und den nächsten Schritt
festhalten, damit der nächste Agent direkt dort fortsetzen kann.
