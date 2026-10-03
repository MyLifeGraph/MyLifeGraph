# MyLifeGraph – ausführliche Projekt- und Chat-Übergabe

**Für Gregor und einen neu einsteigenden Entwicklungsagenten**

**Stand dieser Zusammenfassung: 3. Oktober 2026**

**Repository:** [MyLifeGraph/MyLifeGraph](https://github.com/MyLifeGraph/MyLifeGraph)

## 0. Zweck, Verlässlichkeit und Lesereihenfolge

Diese Übergabe führt die umfangreiche Weiterentwicklung aus dem Chat zu einer zusammenhängenden Beschreibung zusammen: Produkt, Oberfläche, zusätzliche Funktionen, Fehlerkorrekturen, Architektur, Entwicklungsablauf, Tests und Veröffentlichung. Sie soll verständlich sein, ohne den gesamten Chat zu lesen.

Sie ist ein **datierter Übergabeschnappschuss**, kein Ersatz für die technischen Feature-Verträge im Repository und kein Auftrag, etwas erneut zu installieren oder zu veröffentlichen. Es wurde für diese Übergabe kein neuer Produktionsdurchlauf durchgeführt. Der unten genannte Live-Stand stammt aus der zuletzt dokumentierten Veröffentlichung vom 3. Oktober.

Bitte diese drei Ebenen unterscheiden:

1. **Implementiert:** Verhalten ist im Quellcode und in den zugehörigen Verträgen beschrieben.
2. **Veröffentlicht und geprüft:** Ein bestimmter Commit beziehungsweise ein konkretes Artefakt wurde tatsächlich geprüft und ausgerollt.
3. **Geräteabhängig:** Android-Berechtigungen, Google-OAuth-Kaltstart, NFC, Herstellerverhalten und echte Zustellung benötigen zusätzlich physische Gerätetests. Automatisierte Tests ersetzen diese nicht.

Frühere Wünsche wurden mehrfach präzisiert. Diese Datei beschreibt den **zuletzt vereinbarten Zustand**, nicht jede verworfene Designvariante. Beispielsweise ist die Fokusvorbereitung keine bewertete Abhakliste mehr; die Webseite enthält keinen automatisch abgespielten Video-Walkthrough; die allgemeine App-Oberfläche wurde nicht vollständig auf Deutsch übersetzt.

**Schneller Einstieg:** Abschnitte 1–3 für Status und Architektur; 4–17 für das Produkt; 18–22 für Fehler, Sicherheit und Arbeitsweise; 23–26 für Betrieb, Tests und Weiterarbeit.

Es stehen bewusst **keine Passwörter, API-Schlüssel, Tokens, privaten IP-Adressen oder Keystore-Inhalte** in dieser Datei. Zugangsdaten müssen separat und geschützt übergeben werden.

---

## 1. Zuletzt belegter Auslieferungsstand

### 1.1 Zusammengehöriger Release

| Bestandteil | Zuletzt dokumentierter Stand |
| --- | --- |
| Zusammenführung | [Pull Request #33](https://github.com/MyLifeGraph/MyLifeGraph/pull/33), gemergt |
| Geprüfter Kandidat | `e6ef1378597a5ab95cec44db39cdde512ee0fca0` |
| Main-Merge | `f7259435857ceb22d567f0831481833d14604259`, gleicher Quellbaum wie der Kandidat |
| Release | [`v0.1.0-pilot.1-rc.18`](https://github.com/MyLifeGraph/MyLifeGraph/releases/tag/v0.1.0-pilot.1-rc.18) |
| Art der Veröffentlichung | Signierter **Pilot-/Prerelease**, keine Behauptung eines stabilen Store-Releases |
| Android | `MyLifeGraph-v0.1.0-pilot.1-rc.18.apk`, Version Code `10000096` |
| Web-App | Vercel-Produktion auf dem genannten Main-Commit als READY geprüft |
| VPS | Release vorbereitet und aktiviert; öffentliche Health-/Readiness-Prüfung und Projekt-Helfer bestätigten den passenden Stand |
| Datenbank | 79 Migrationen; Head `20260925164043_reversible_notification_and_focus_correction.sql` |
| SQL für diesen Release | Keine zusätzliche Migration erforderlich; bestehende Cloud-Kompatibilität wurde geprüft |

Das APK-Artefakt hatte 151.044.364 Bytes. APK- und SBOM-Prüfsummen wurden gegen `SHA256SUMS` geprüft. Das Signaturzertifikat entsprach dem Vorgänger; der Version Code ist höher. Das ist wichtig für ein Update über eine bereits installierte APK hinweg.

**Direkte Einstiege:**

- [Signierte APK herunterladen](https://github.com/MyLifeGraph/MyLifeGraph/releases/download/v0.1.0-pilot.1-rc.18/MyLifeGraph-v0.1.0-pilot.1-rc.18.apk)
- [Produktive Web-App](https://my-life-graph-my-life-graph-s-projects.vercel.app/)
- [Separate Produktwebseite](https://mylifegraph-website.vercel.app/)
- [VPS Health](https://mylifegraph.duckdns.org/v1/health)
- [VPS Readiness](https://mylifegraph.duckdns.org/v1/ready)

### 1.2 Prüfnachweise

- [Vollständiger manueller CI-Lauf](https://github.com/MyLifeGraph/MyLifeGraph/actions/runs/37135362362): alle sieben Prüflanes erfolgreich, einschließlich frischer Migrations-/pgTAP-Prüfung und vollständiger Browser-Journeys.
- [PR-Prüfung](https://github.com/MyLifeGraph/MyLifeGraph/actions/runs/37135306936): erfolgreich. Die Änderungsklassifizierung übersprang dort eine redundante DB-Lane; der vollständige manuelle Lauf hatte sie ausgeführt.
- [Signierter Tag-Build](https://github.com/MyLifeGraph/MyLifeGraph/actions/runs/37136204669): erfolgreich.
- [Automatischer signierter Main-Build](https://github.com/MyLifeGraph/MyLifeGraph/actions/runs/37136174066): erfolgreich.
- Lokal ergänzten 97 gezielte Flutter-Regressionstests und native JVM-/Lint-Prüfungen die Prüfung. Unabhängige Reviews untersuchten Navigation, Flutter-Flows sowie natives Blocking/Auth.

**Grenze:** Beim abschließenden Audit war kein Android-Gerät über ADB verbunden. Deshalb wurde nicht behauptet, dass jeder OEM-Sonderfall, NFC-Tag und reale OAuth-Kaltstart physisch abgenommen sei.

**Dokumentationshinweis:** `docs/verification.md` ist der kanonische Eigentümer der laufenden Verifikation. Einige dortige Einträge dokumentieren bewusst frühere lokale Zwischenstände vor der Veröffentlichung. Die obigen CI-/PR-/Release-Links belegen den späteren Abschluss. Die genaue Veröffentlichungsprüfung wurde zusätzlich in einer lokalen, ignorierten Release-Evidenznotiz festgehalten; deren Anwesenheit darf auf einem anderen Rechner nicht vorausgesetzt werden.

---

## 2. Entwicklung des Produkts und Zusammenarbeit

Die ursprüngliche, stärker auf Planung konzentrierte Idee wurde zu einem persönlichen Studien- und Alltagsbegleiter erweitert. Nutzerinterviews zeigten, dass ein weiterer Planer allein nicht genügend Mehrwert vermittelt. Wichtig wurden verständliche Unterstützung, geringer Aufwand bei der Dateneingabe und sinnvolle Erinnerungen.

Die Idee eines persönlichen Chat-Coachs, der vorhandene Daten und Muster untersuchen kann, war **unsere Lösung für die erkannten Bedürfnisse** – nicht die wortwörtliche Feature-Bestellung der Befragten. Aktive Erinnerungen, beispielsweise an Bettzeit oder Deadlines, wurden dagegen ausdrücklich als hilfreich gewünscht. Sprach-Check-ins und optionale Uhrdaten verringern die Eingabehürde.

Die Arbeitsteilung laut unserer gemeinsamen Beschreibung:

- **Matthias:** erster KI-gestützter Prototyp und Frontend-Grundstruktur; Verbindung externer Dienste, Authentifizierung, Datenzugriff und Auslieferungsworkflow; später umfangreiche UX-Überarbeitung und zusätzliche Funktionen wie Spracheingabe, Watch-Anbindung und Android-App-Blocking.
- **Gregor:** wesentliche Backend-, Planungs-, Analyse- und serverseitige Logik sowie VPS-Grundstruktur und Backend-Automatisierung.
- **Gemeinsam:** regelmäßige Abstimmungen, Produktentscheidungen und Nutzerfeedback.

Das ist eine inhaltliche Rollenbeschreibung aus dem Gespräch, keine zeilenweise Git-Autorenzuordnung. Viele Änderungen entstanden mit Codex-Unterstützung. Die menschliche Verantwortung lag weiterhin bei Produktentscheidungen, Zugriffsfreigaben, Review und Abnahme.

Ein wichtiges Learning: Agenten waren besonders hilfreich bei klar beschriebenen Aufgaben mit anschließender gezielter Nachbesserung. Ein Experiment mit weitgehend autonomem Erfinden und Implementieren neuer Features erzeugte auch überladene, textlastige Ergebnisse. Daraus entstand unser heutiger Ansatz: klare Richtung vorgeben, kleine überprüfbare Änderungen machen, echte Fehler reproduzieren und UX bewusst gestalten.

---

## 3. Architektur: Was läuft wo?

```text
Flutter Web auf Vercel / Flutter Android APK
  ├─ Supabase Auth → Sitzung, optional Google-Anmeldung
  ├─ freigegebene owner-begrenzte Datenzugriffe → Supabase Postgres/RLS
  └─ Bearer-authentifizierte Produktbefehle → FastAPI auf dem VPS
       ├─ kanonische Daten / RPCs / Projektionen → Supabase
       ├─ Coach → gewählter Provider bzw. getrennter Projekt-Executor
       ├─ Server-Spracheingabe → begrenzter Speech-Sidecar
       └─ Push-Worker → Firebase Cloud Messaging → Android

Zusätzlich nur auf Android:
  Health Connect → freiwilliger Import → Supabase / Check-in-Angebot
  On-device Speech → lokale Transkription → überprüfbarer Text
  App Blocking → native Regeln / Accessibility / lokale Timer / Preview

Separate Produktwebseite auf eigenem Vercel-Projekt:
  statische Darstellung + synthetische Demo; keine Produktdatenbank
```

### 3.1 Grundprinzipien

- Die Android-App ist eine **Flutter-App mit nativer Engine und Android-Bridges**, kein bloßer WebView-Container der Vercel-App. Eine gezielte Offline-WebView für die Website-Blockseite ist eine separate Ausnahme.
- FastAPI leitet den Nutzer aus dem verifizierten Bearer-Token ab. Eine vom Client mitgeschickte Nutzer-ID darf keine Schreibberechtigung verleihen.
- Flutter erhält nur den vorgesehenen publishable/anon Supabase-Schlüssel, niemals Service-Role- oder Scheduler-Secrets.
- Viele Produktfunktionen sind deterministisch: Planung, Capture, Tagesprojektionen, Korrelationen und Reminder sind nicht pauschal „KI“.
- Coach-Fragen und ausdrücklich angeforderte Ultra-Quick-Entwürfe können ein Sprachmodell aufrufen. Das ist ein eigener, begrenzter Ablauf.
- Guest/Mock bleibt lokal. Ein Fehler bei einem echten Konto darf nie unbemerkt durch Beispieldaten ersetzt werden.
- Lesen, Vorschlagen, Bestätigen und Speichern sind unterschiedliche Handlungen. Eine Vorschau reserviert noch keine Lernzeit.

### 3.2 Externe Dienste

| Dienst | Aufgabe und Abgrenzung |
| --- | --- |
| GitHub + Actions | Quellcode, PRs, Prüfungen, Builds, signierte Release-Artefakte |
| Vercel | Flutter-Web-App; zusätzlich ein getrenntes Projekt für die Produktwebseite |
| Supabase | Auth, Postgres, RLS, Migrationen und kontrollierte Daten-/RPC-Grenzen |
| Google Cloud / Google OAuth | Google-Anmeldung über den Supabase-Auth-Fluss |
| Firebase / FCM | Android-Push-Transport, **kein Ersatz für Supabase** |
| Cloudflare Turnstile | Vorgesehene Auth-/Registrierungs-Challenge; kein allgemeiner Beleg, dass sämtlicher Verkehr über Cloudflare läuft |
| Produktions-VPS | FastAPI, isolierter Coach-Executor, Speech-Dienst und passende Betriebshelfer |
| Caddy / DuckDNS | HTTPS-Reverse-Proxy beziehungsweise öffentlicher API-Domainname |
| OpenAI / Gemini | Explizit gewählte Coach-Provider; unterschiedliche Berechtigungen, Schlüssel und Budgets |
| Android Health Connect | Optionale Schnittstelle für freigegebene Schlaf-/Schrittdaten |
| Modell-Downloadquelle | Fest gepinnte, überprüfte Dateien für lokale Speech-Modelle; keine beliebige Modell-URL |

Firebase wurde unter der Vorgabe **Spark/kostenlos** eingerichtet. Keine eigenmächtige Umstellung auf einen bezahlten Tarif. Eigene API-Keys können unabhängig davon beim jeweiligen Modellanbieter Kosten verursachen. Der VPS ist ebenfalls keine von Firebase bereitgestellte Gratis-Rechenleistung.

---

## 4. Today: schneller Überblick statt Erklärungssammlung

Today wurde deutlich kompakter und handlungsorientierter:

- Der Check-in-Streak zeigt die Anzahl weiterhin in **Tagen**, nicht irgendwann in Monaten. Zahl und Überschrift sind kompakt angeordnet; die Zahl ist rechts ausgerichtet, aber mit Abstand zur Info-Aktion.
- Die Werte des **letzten vorhandenen Check-ins** sind direkt sichtbar. Ein kurzes Datum in Klammern macht deutlich, wenn es ältere Daten sind. Kein zusätzliches Aufklappen einer neuen Check-in-Historie.
- Die Reihenfolge ist wieder **Werte zuerst, Morning-/Evening-Aktionen darunter**.
- Es werden nur tatsächlich vorhandene Werte gezeigt. Fehlende Werte werden nicht zu null oder einem erfundenen Score.
- `Today's schedule` trennt aktive Einträge von bereits erledigten Einträgen; abgeschlossene Inhalte sind kompakt beziehungsweise eingeklappt zugänglich.
- Redundante Untertitel und doppelte Setup-Commitment-Beschriftungen wurden reduziert. Ladefehler und wichtige Zustände bleiben sichtbar.
- `All tasks` lässt datierte und undatierte Tasks filtern; beide Gruppen sind anfangs sichtbar. **Dated/Undated bezieht sich auf Deadlines**, nicht auf die Existenz einer Kalenderreservierung.
- Task-/Habit-Aktionen reagieren unmittelbar. Ein kleiner Saving-Zustand zeigt die noch ausstehende Bestätigung.

Die schnelle Rückmeldung ist keine vorgetäuschte Speicherung: Bei einer unbestätigten fehlgeschlagenen Änderung wird die Darstellung zurückgesetzt. Ist die Änderung bereits gespeichert und nur das Nachladen scheitert, bleibt sie gespeichert; sie darf nicht erneut ausgeführt werden. Konkurrierende Aktionen bleiben während der Klärung gesperrt.

Der Streak bleibt an den vorhandenen vollständigen Morning-/Evening-Capture-Regeln orientiert. Quick Notes oder importierte Watch-Beobachtungen dürfen nicht automatisch einen vollständigen Check-in vortäuschen.

## 5. Morning und Evening: vollständige Daten, weniger Reibung

### 5.1 Kompaktere Formulare

Die bestehenden Felder und fachlichen Bedeutungen wurden erhalten. Überschriften und Fragen bleiben, redundante Erklärungssätze wurden gekürzt. Die Speicheraktion heißt kurz **Save**. Ähnliche Auswahlgruppen haben konsistente Größen und Zustände.

Ein konkretes Beispiel ist `Where did today's stress come from?`:

1. Erstes Antippen wählt eine Ursache und markiert sie grün.
2. Bei der gewählten Ursache erscheint eine klare Aufklappmöglichkeit.
3. Erneutes Öffnen zeigt das verbundene Feld **Specific blocker** direkt unter dieser Ursache, mit passender Breite und zusammengehöriger Oberfläche.
4. Ohne ausgewählte Ursache wird es nicht als loses zusätzliches Feld gezeigt.

Das ist weiterhin **ein optionales Kontextfeld**, keine unabhängig gespeicherte Textsammlung pro Ursache. Bereits eingegebener Kontext darf durch bloßes Ein-/Ausklappen oder Wechseln der Auswahl nicht überraschend verschwinden. Die getrennten optionalen Notes bleiben erhalten.

Leicht grüne Hover-/Fokusflächen hatten zuvor wie eine zweite Auswahl ausgesehen. Die Zustände wurden optisch getrennt: Eine 8 darf nicht ausgewählt sein, während eine neutral berührte 9 ebenfalls wie ausgewählt aussieht. Dabei wurden nicht die gespeicherten Werte geändert.

### 5.2 Vergangene Tage nachtragen

Manuelle Morning-/Evening-Check-ins unterstützen **heute und die sieben vorherigen Profil-Kalendertage**. Die ausgewählte Tageszuordnung bleibt sichtbar. Datum wechseln oder mit ungespeicherten Änderungen zurückgehen verlangt eine Verwerfen-Bestätigung.

Wichtig für Datenintegrität:

- Das Profil mit IANA-Zeitzone bestimmt den Tag, nicht zufällig die Browserzeitzone.
- Ein nachgetragener Morning-Check-in bekommt nicht stillschweigend die jetzige Uhrzeit als damalige Aufwachzeit.
- Änderungen aktualisieren die Projektion des tatsächlich bearbeiteten Tages.
- Bestehende Revisions-/Konfliktprüfungen bleiben bestehen.
- Das ist keine allgemeine Cloud-Autosave- oder Crash-Recovery-Garantie für ungespeicherte Formulare.
- Der Ultra-Quick-Sprachentwurf bleibt an seinen vorgesehenen heutigen Capture-Kontext gebunden; der manuelle Rückdatierungsdialog ist nicht automatisch auch eine Voice-Rückdatierung.

## 6. Ultra Quick Check-in und Quick Note

Es gibt Morning, Evening und Quick Note. Die mobile Auswahl wurde kompakter angeordnet. Für Morning/Evening ist der wichtigste Grundsatz:

> Spracheingabe liefert einen überprüfbaren Entwurf – keinen unvollständigen oder ungeprüft gespeicherten Check-in.

Der Ablauf:

1. Sprache und Modus auswählen.
2. Kurze Vorlage direkt beim Öffnen sehen, ohne zuerst das Textfeld fokussieren zu müssen.
3. Sprechen oder tippen.
4. Strukturierte Werte aus dem Text extrahieren lassen.
5. Im normalen Review/Formular prüfen, korrigieren und fehlende Pflichtfelder ergänzen.
6. Erst die explizite Bestätigung speichert über den normalen Capture-Weg.

Die Sprechvorlagen folgen der normalen Feldreihenfolge. Während einer Aufnahme bleiben sie als Orientierung nutzbar. Die UK-/Deutschland-Flagge schaltet direkt um; Englisch ist Standard. Die gespeicherte Auswahl übersteht Seitenwechsel und Neustarts.

Deutsche Angaben werden auf dieselben kanonischen Felder abgebildet. Es gibt keine zweite deutsche Datenstruktur, die Korrelationen oder Insights auseinanderlaufen lässt. Schlafdauer allein darf keine Einschlaf-/Aufwachzeit erfinden. Explizite Korrekturen benötigen eigenen Textbeleg. Auch Uhrzeitformen wie `7 am`, `11 pm` oder `23 Uhr 30` werden berücksichtigt.

Ein korrigierter Fehler betraf bestehende Schlafzeiten: Eine ausdrücklich neu vorgeschlagene Zeit muss die alte Zeit im Review ersetzen; nicht erwähnte gespeicherte Antworten dürfen erhalten bleiben. Entwurf, bestehende Werte und Speicherung dürfen nicht unkontrolliert vermischt werden.

**Quick Note** ergänzt freiwilligen Kontext. Sie zählt nicht als vollständiger Morning-/Evening-Check-in. Der Coach darf aus einer Notiz keinen nicht angegebenen Messwert oder erledigten Check-in ableiten.

## 7. Speech-to-Text: Server oder On-device

Speech-to-Text ist von der Auswahl des Chat-Coach-Providers getrennt. Ein lokales Sprachmodell bedeutet nicht automatisch einen lokalen oder offline verfügbaren Coach.

### Server

- Vorgegebener Speech-Dienst auf dem VPS, getrennt vom eigentlichen Coach-Executor.
- Explizite Audioinformation und Mikrofonberechtigung; kein dauerhaftes Mithören.
- Begrenzte Aufnahme, normalerweise bis 30 Sekunden.
- Abbrechen, Verlassen, Hintergrundwechsel und Kontowechsel behandeln späte Antworten so, dass sie keinen neuen Entwurf überschreiben.

### On-device

- In der unterstützten 64-Bit-Android-App, nicht als lokale Inferenz in Flutter Web.
- **Whisper Tiny**, **Whisper Base**, beide multilingual, sowie **Parakeet TDT 0.6B V3 INT8**. Frühere Erwähnungen von „Wispr“ beziehungsweise „V4“ waren keine zusätzliche tatsächlich unterstützte Modellreihe.
- Expliziter Download; festgelegte Revisionen, Dateigrößengrenzen und SHA256-Prüfung vor Aktivierung.
- Gewichte liegen privat in der App, nicht vollständig in der APK. Parakeet benötigt ungefähr 670 MB Download und entsprechend mehr Gerätespeicher.
- Installiert und ausgewählt sind unterschiedliche Zustände. Auswahl bleibt gespeichert; ungenutzte Modelle können entfernt werden.
- Keine stille Ausweichroute auf den Server, falls ein lokales Modell fehlt oder fehlschlägt.
- Lokale Transkription verschickt kein Audio. Später bewusst abgesendeter Text kann selbstverständlich an den gewählten Coach gehen.

Das Auswahlmenü sitzt über der App-/Systemnavigation und berücksichtigt Safe Areas, kleine Höhen und vergrößerte Schrift. Beim erneuten Öffnen bleiben die Modelle sichtbar; die Liste darf nicht bei „Server/On-device“ abgeschnitten enden. Die zugehörigen Coach-/Speech-Einstellungen wurden aus den allgemeinen Settings entfernt, wo sie nur doppelt waren; sie bleiben im Coach erreichbar.

## 8. Coach: Chat, Datenanalyse und kontrollierte Provider

### 8.1 Oberfläche und Nutzung

- Eigenständiger Chat mit getrennt scrollender Timeline und erreichbarem Composer.
- Verlauf beginnt beim neuesten Eintrag. Beim Hochscrollen erscheint ein dezenter runder Pfeil nach unten.
- Eigene Nachrichten und Antworten sind optisch klar getrennt.
- Mikrofon, Provider-/Key-Auswahl und Speech-Quelle sind kompakt am Composer erreichbar.
- Verbleibende Nachrichten stehen beim Provider, nicht platzraubend neben der Seitenüberschrift.
- Pull-to-refresh funktioniert am Anfang des Chat-Scrollbereichs, auch bei leerem Verlauf. Es lädt Verlauf/Capabilities neu, sendet keine Frage und erhält den Entwurf.
- Deutsch/Englisch ist über die gespeicherte Flagge auswählbar. Die Coach-Sprache ist von der Ultra-Quick-Vorlagensprache getrennt.
- Sprachwechsel übersetzt nicht nachträglich alte Nachrichten. Laufende beziehungsweise exakt zu wiederholende Anfragen behalten ihre Identität und Sprache.
- Unsicherheit wird kompakt mit Text, Farbe und Icon gezeigt: **High uncertainty bedeutet weniger sicher**, nicht besonders sicher. Farbe ist kein Wahrheitsnachweis.

### 8.2 Provider und Schlüssel

Der Nutzer kann Standard/Project Coach, eigenen OpenAI-Key oder eigenen Gemini-Key wählen. Provider- und Gemini-Modellauswahl werden geräte- und profilbezogen gespeichert. Ein neuer Nutzer übernimmt nicht versehentlich die Auswahl beziehungsweise Schlüssel eines anderen Profils.

Die Repository-Konfiguration enthält einen Gemini-Selector für 3.6/3.7/3.8 Flash und die passenden expliziten Adapter-IDs. Das ist **keine Aussage, dass jedes Google-Konto dauerhaft Zugriff auf jedes Modell hat**. Live-Verfügbarkeit ist gesondert zu testen; keine erfundenen Modellnamen ergänzen. Auch die OpenAI-Modellzuordnung ist im Provider-Vertrag festgelegt, nicht beliebig aus dem UI-Text abzuleiten.

Schlüssel:

- Web: nur im Speicher des jeweiligen Tabs, nicht dauerhaft in Supabase oder Browser-LocalStorage.
- Android: verschlüsselte gerätelokale Speicherung; keine Cloud-Synchronisierung des Keys.
- Übermittlung nur für den explizit gewählten Provider im jeweiligen HTTPS-Aufruf; serverseitig nicht persistieren oder loggen.
- Logout, Kontolöschung und Profilwechsel bereinigen den vorgesehenen Key-Zustand.
- Kein automatischer Provider-Wechsel bei Fehlern. Gemini darf nicht plötzlich über den Standard-Codex-Provider laufen.

**Budgetkorrektur gegenüber einer früheren Vereinfachung im Chat:** Die allgemeine 20-Turn-Tagesgrenze ist accountweit im lokalen Tag. Standard hat zusätzlich eigene Dispatch-Grenzen, unter anderem fünf pro Nutzer und 15 global pro UTC-Tag. Die UI muss das tatsächlich zurückgelieferte Budget des ausgewählten Providers darstellen; „Gemini hat immer komplett unabhängige 20“ wäre zu ungenau.

### 8.3 Was der Coach mit Daten darf

Der Coach untersucht einen begrenzten, nur lesbaren persönlichen Datenkontext. Für BYOK stehen begrenzte Inspect-/Query-Werkzeuge bereit, nicht beliebige Datenbankrechte. Der getrennte Projekt-Executor kann innerhalb seiner Isolation zusätzlich Auswertungscode ausführen; das ist keine freie Shell auf dem Produktivserver.

- Kein Erstellen, Löschen oder Umplanen von Produktdaten durch freie Chatantworten.
- Kein Zugriff auf Daten anderer Nutzer.
- Keine Service-Role-/Firebase-Secrets im Executor.
- Begrenzte Tool-Aufrufe, Antwortgrößen und Laufzeiten.
- Keine automatische Gleichsetzung von Korrelation mit Ursache.
- Health-Connect-Beobachtungen tragen ihre Herkunft; überlappende manuelle Daten dürfen nicht addiert werden.
- Busy-/Retry-Zustände behalten passende Anfrageidentitäten. Wiederholen darf keine zweite versteckte Ausführung erzeugen.

## 9. Insights und Personal Learning

Die Oberfläche ist in **Overview** und **Advanced** gegliedert. Advanced enthält Compare, Top patterns, Trend overlay, Skillset, Past, Matrix und Discovered.

### Compare und Navigation

- Die horizontale Tab-Leiste zeigt dezente Randpfeile nur bei tatsächlichem Überlauf; auch am PC erreichbar.
- Ein nicht benötigter Pfeil reserviert keinen leeren Platz. Am rechten Ende ist nicht mehr ein zweiter Klick nötig, um den letzten Tab hinter dem Pfeil hervorzuholen.
- Metriken heißen beispielsweise `Previous-night sleep (Recovery)` statt mit einem Punkt zwischen Name und Kategorie.
- Die Überschrift bleibt vollbreit. Erklärung und Korrelationswert beziehungsweise No-data-Zustand sind darunter kompakter angeordnet.
- `Longer period` erweitert das bestehende Zeitfenster; es verspricht keine Daten, die nicht vorhanden sind.
- Darstellung für 7/14/30/90 Tage ist konsistent; große Schrift darf zugunsten der Bedienbarkeit umbrechen.

### Skillset

- Radar/Spinnennetz bleibt erhalten; alternativ Balkendiagramm mit denselben Daten und derselben Skala.
- Anfangs sind alle unterstützten Dimensionen ausgewählt. Bereits gespeicherte Auswahlen – auch eine leere – werden nicht überschrieben.
- Auswahl und Darstellung persistieren gerätebezogen pro Konto, Guest separat. Keine Cloud-Synchronisierung dieser Ansichtspräferenz.
- Der Filter ändert nur die Anzeige, niemals verfügbare Check-in-Fragen oder gespeicherte Werte.
- Fehlende Daten sind fehlende Daten, nicht null. Das Radar braucht mindestens drei gemessene ausgewählte Dimensionen; Balken können einzelne Messwerte zeigen.
- Learning und Discipline sind beschriebene abgeleitete Kennzahlen, keine objektive Bewertung von Intelligenz oder Charakter. Stress wird nicht stillschweigend invertiert.

### Past: zwei echte Vergleichsmodi

**Rolling:** Die letzten 7/14/30 Kalendertage einschließlich heute werden mit dem unmittelbar vorhergehenden gleich langen Zeitraum verglichen. Keine doppelt verwendete Grenzdatum-Zeile.

**Weekdays:** Montag bis zum heutigen Wochentag dieser Woche wird über Montag bis Sonntag der Vorwoche gelegt. Die aktuelle Kurve läuft nicht künstlich bis Sonntag weiter.

Vorherige Werte sind blasser und gestrichelt, aktuelle kräftiger. Datum, Einheit, Profilzeitzone und Lücken bleiben nachvollziehbar. Es handelt sich um eine lesende Darstellung bestehender Daten, keine neue versteckte Score-Berechnung oder neue Capture-Tabelle.

### Grenzen der Analyse

Schlafempfehlungen brauchen ausreichende geeignete Daten und ihre bestehenden Qualitätsregeln. Mehr Daten erzeugen nicht zwangsläufig sofort ein schönes Sleep Window. Für eine Demo wurden Testdaten bewusst angepasst; das ist kein Beleg, dass dieselbe Empfehlung bei jedem echten Nutzer entstehen muss.

Freitext wie Specific blocker ist Kontext, nicht automatisch eine numerische Korrelationsdimension. Die Präsenz eines Feldes in der Datenbank bedeutet nicht, dass jede Statistik es auswertet. Die fachliche Verwendung ist im jeweiligen Analyse-/Snapshot-Vertrag zu prüfen.

## 10. Planner, Tasks und Vorbereitung

### 10.1 Responsive Struktur

**Handy/Tablet:** `This week` zeigt Kalender beziehungsweise Listenansicht. `Planning` bündelt Needs Attention, Vorbereitung, Vorschauen, Habits, unscheduled Tasks und Verlauf. Beide Ansichten verwenden dieselben Daten und Befehle.

**Desktop:** Die frühere zweispaltige Anordnung wurde gezielt wiederhergestellt: Kalender und Anlegen links, kompakte Planungsinformationen rechts. Kein erzwungener Handy-Umschalter am großen Desktop. Bei größerer Schrift kann die kompaktere responsive Struktur sinnvoll wieder greifen.

- `+ Add` ist kompakt, pillenförmig und mit Abstand zur Kalender-/Listenwahl angeordnet.
- Auf schmalen Planning-Ansichten kann Add die ganze Inhaltsbreite nutzen.
- Kalenderimport ist über die Header-Aktion erreichbar.
- Leere Tage in der Listenansicht behalten dieselbe Breite wie gefüllte Tage.
- Das Add-Menü erhält alle fünf vorhandenen Erstellungswege; auf kleinen Höhen bleibt es scrollbar statt Einträge abzuschneiden.
- Eine bewusste Aufwärtsgeste **ab der unteren Navigation** öffnet beim Planner das Anlegen. Normales Scrollen im Kalender darf das nicht auslösen.

### 10.2 Tasks und reversible Aktionen

Unscheduled Tasks lassen sich direkt abhaken und über Menü beziehungsweise Long Press entfernen. Entfernen nutzt die bestehende Stornierung, keinen unkontrollierten Hard Delete. Wiederherstellung ist über Today/All tasks vorgesehen. Änderungen werden zwischen Today und Planner nachgeladen.

Reservierungen und zugrunde liegende Aufgaben sind verschiedene Dinge:

- `Cancel reservations` entfernt reservierte Zeit, behält aber das Ziel.
- `Remove task` entfernt das aktive Task-Ziel über dessen Lifecycle und löst künftige Slots.
- Habits haben Management-/Archivierungswege; Setup-eigene Definitionen werden im zuständigen Setup verwaltet.
- Focus- und Ausführungshistorie bleiben nachvollziehbar.

### 10.3 Exams, Assignments und Preparation Plans

Die vorhandene Planungslogik wurde nicht durch Designarbeit ersetzt. Neu beziehungsweise überarbeitet sind kompaktere Schritte und Gruppen wie Study time, Study rhythm, Daily limit, Busy times und Check capacity. Optionale Details sind aufklappbar; notwendige Eingaben und Warnungen bleiben sichtbar.

Vorschau und Bestätigung bleiben getrennt. Erst die Bestätigung reserviert Zeit. Needs-Attention-/Replan-Flows zeigen den bestehenden Plan mit seinen tatsächlichen Konflikten, nicht einen zweiten unabhängigen Planungsalgorithmus.

`Remove plan from calendar` ist von bloßem Freigeben der Reservierungen zu unterscheiden. Ein abgeschlossener oder entfernter Plan darf nicht durch historische Revisionen wieder als aktiver Block erscheinen. `Plan again` erzeugt eine neue bewusste Vorschau, keine automatische Reaktivierung des alten Zustands. Bereits geleistete Focus-Zeit bleibt erhalten.

## 11. Kalenderimport: Verbindung ist nicht Synchronisation

Der aktuelle Import ist ein **bewusster `.ics`-Dateiimport**, keine laufende Google-Calendar-Synchronisierung.

- Quelle anlegen und Zustimmung geben importiert noch keine Datei. Deshalb kann „Connected / No file imported“ ein korrekter Zustand sein.
- Leere, nie importierte Quellen können jetzt über `Remove source` entfernt werden. Intern bleiben die vorgesehenen Disconnect-/Delete-Prüfungen und ein minimaler Audit-Tombstone erhalten.
- Bei Quellen mit Daten bleiben **Disconnect** und **Delete imported data** getrennte Aktionen.
- Disconnect stoppt weitere Importe, behält die bisherige lokale Kopie als veraltet/getrennt.
- Löschen entfernt importierte lokale Daten, nicht den ursprünglichen externen Kalender.
- Manuelle Termine, Setup-Termine und bereits angelegte Vorbereitungspläne werden nicht nebenbei gelöscht.
- Eingelesene Ereignisse bleiben read-only. Keine vorgetäuschten Edit-/Provider-Delete-Funktionen.

„Imported calendar as busy“ bedeutet: geeignete aktuelle Importtermine können bei der Kapazitätsplanung als bereits belegte Zeit gelten. Es bedeutet nicht, dass MyLifeGraph in den Quellkalender schreibt. Diese Präferenz liegt auf Mobile unter Planning statt doppelt auf beiden Planner-Seiten.

Ein Dateiumfang, eine erteilte Zustimmung, ein erfolgreicher Import und ein für die aktuelle Profilzeitzone gültiger Planungsstand sind unterschiedliche Zustände. Veraltete oder fehlgeschlagene Daten dürfen nicht als leere freie Zeit interpretiert werden.

## 12. Fokus-Sessions und Vorbereitung

Die frühere kleinteilige Vorbereitung wurde zu einer schnellen Erinnerung reduziert:

- kurze passive Liste der konfigurierten Dinge, etwa Wasser, Snack oder Badezimmer;
- kompakte Aktionen **Cancel / Ready & start**;
- keine einzeln gespeicherten Ready-/Skip-Wertungen;
- kein Einfluss dieser Häkchen auf Korrelationen, Produktivität oder Lernfortschritt.

Die Liste ist Vorbereitungshilfe, keine neue Messquelle. Die zugrunde liegenden Setup-Einstellungen bleiben der Ort zum Anpassen der Vorbereitung.

Focus selbst behält klare Regeln: höchstens eine aktive Session je Nutzer, echte Start-/Endzeiten, keine Gleichsetzung von geplantem und tatsächlich geleistetem Aufwand. Planbezogene Sessions behalten ihre Herkunft, damit Lernzeit korrekt zugeordnet wird.

Im Verlauf gibt es für abgeschlossene Sessions **Correct time**. Die Zeit darf innerhalb des ursprünglich aufgezeichneten Intervalls korrigiert beziehungsweise wiederhergestellt werden, nicht darüber hinaus verlängert. Start, Tag, Ziel und ursprüngliche Herkunft werden nicht frei umgeschrieben; Audit und Konfliktkontrolle bleiben bestehen. Abgebrochene Sessions werden dadurch nicht nachträglich zu abgeschlossenen.

Erholung nach einer Session ist ein überspringbarer lokaler Countdown, kein zusätzlicher erledigter Focus-Block und keine künstliche Lernzeit.

---

## 13. Android App Blocking: eigenständiger Funktionsbereich

Dies ist eine der größten Erweiterungen gegenüber dem alten Stand. Einstieg über das Shield-Symbol im Header beziehungsweise **App blocking** in Settings. Der Bereich hat seine eigene Navigation:

**Plans · Strict · Insights · Customize**

Die normale untere Hauptnavigation wird hier nicht als zweite konkurrierende Navigation eingeblendet. Regeln und Nutzungsdaten bleiben gerätelokal; es wurde dafür keine neue Cloud-Blocking-Datenbank eingeführt.

### 13.1 Benannte Pläne und kombinierbare Regeln

Ein Plan hat unter anderem Name, Icon, Ziele und Aktivzustand. Ziele sind installierte Apps und – mit separater Zustimmung – Website-Domains.

Kombinierbare Auslöser:

- während einer echten Focus Session;
- bestimmte Wochentage und Uhrzeitfenster, auch über Mitternacht;
- sofortiger Timer für eine Dauer;
- dauerhaft;
- gemeinsames tägliches Nutzungsbudget der ausgewählten Ziele.

**Regeln und Pläne werden als ODER kombiniert:** Ein Ziel bleibt blockiert, solange irgendeine wirksame Regel es blockiert. Das Löschen oder Pausieren eines Plans darf einen anderen noch aktiven Plan nicht umgehen.

Ein Focus-Plan ist an die tatsächliche Focus-Lifecycle-Freigabe gekoppelt. Das Öffnen einer Vorschau oder eines Editors erzeugt keine Focus Session. DND behält seine getrennte, focusbezogene Berechtigung.

Zeitpläne verwenden die **Android-Gerätezeitzone**. Das ist bewusst nicht dieselbe Zuständigkeit wie die Profilzeitzone für Cloud-Check-ins und Planner. Übernachtfenster gehören zum Startwochentag; Endgrenzen sind exklusiv.

Vorhandene Aktionen umfassen Bearbeiten, Duplizieren, Pausieren/Fortsetzen und bestätigtes Löschen. Quick Block erzeugt einen normalen zeitlich begrenzten Plan statt einer versteckten zweiten Regelwelt. Timer und Budgets unterstützen die dokumentierten Grenzen bis 1.440 Minuten.

### 13.2 App-Auswahl und kompakte Bedienung

- Echte native App-Icons, Suche und gut erkennbare Auswahlhaken.
- Social-media- und Games-Vorauswahl; markiert, wenn die entsprechende installierte Gruppe vollständig ausgewählt ist.
- Vorauswahlen ergänzen Ziele, statt manuell gewählte Ziele still zu entfernen.
- Games hängt an verfügbaren Android-Kategorien; fehlende Klassifizierung wird nicht frei erfunden.
- Auswahl löschen, kontrolliertes Ein-/Ausklappen und eine begrenzt hohe, unabhängig scrollende Liste.
- **Save und Anzahl ausgewählter Ziele bleiben erreichbar**, auch bei langen Listen und unter Berücksichtigung von Tastatur/Systemnavigation.
- Suche oder Einklappen speichert nicht automatisch und löscht keine Auswahl.

Aktive Pläne unterscheiden sich durch sichtbaren Zustand, Akzent und kurze Statuszeile von geplanten, pausierten oder abgelaufenen Plänen. Farbe allein ist nicht die Zustandsinformation. Nutzungsbudgets können beispielsweise „Counting“ sein, ohne bereits jedes Öffnen zu blockieren.

### 13.3 Strict-Modus

Strict erschwert Änderungen an den Blocking-Einstellungen. Mögliche Freigabebedingungen sind Wartezeit, Ladegerät, ausgewähltes WLAN und NFC. **Mehrere ausgewählte Bedingungen werden gemeinsam verlangt**, anders als die ODER-Verknüpfung der Blocking-Auslöser.

- Wartefristen nutzen monotone Zeit statt manipulierbarer Wandzeit.
- Nach einem Neustart gilt eine alte Entsperranfrage nicht mehr. Erst erneutes bewusstes Unblock startet die volle Wartephase; sie startet nicht automatisch im Hintergrund.
- WLAN ist eine Geräte-/Berechtigungsprüfung, keine starke kryptografische Authentifizierung.
- NFC-Einrichtung verlangt die vorgesehenen übereinstimmenden Scans; gespeichert wird die dafür vorgesehene Hash-Identität, kein frei zugänglicher Rohschlüssel.
- Freigabe öffnet ein begrenztes Bearbeitungsfenster; `Lock now` beendet es.
- Emergency Release ist nur verfügbar, wenn Strict wirklich **deaktiviert** ist – nicht bereits während eines zeitweilig entsperrten Bearbeitungsfensters.
- Ein dezenter animierter Ring läuft um ein festes Schloss, solange Strict tatsächlich verriegelt ist. Reduced Motion und Hintergrundzustand stoppen unnötige Bewegung.

**Nachtrag des anschließenden Bugfix-Auftrags:** Aktivieren verriegelt Strict ohne laufenden Countdown. Erst **Unblock** fordert die Entsperrung an und startet die Wartefrist; danach erscheint die bewachte Abschlussaktion. NFC-Scan ist erst nach dieser Anfrage erreichbar. Die zuvor schon sichtbare Sekundenanzeige war irreführend: Im geprüften nativen Code startete Aktivieren selbst keinen Timer. Zusätzlich wird eine unbekannte Boot-ID nicht mehr als gültige Zeitbasis akzeptiert. Veröffentlichungsnachweise dieses Nachtrags werden getrennt vom obigen RC18-Schnappschuss geführt.

### 13.4 Customize und echter Block-Screen

Anpassbar sind kurzer Titel/Text, Icon, Hintergrund und Wartezeit vor Return. Alle vier Hintergründe werden unterstützt: Liquid Glass, Dark, Light und Space. Die gespeicherte Blocking-Auswahl kann unabhängig vom allgemeinen App-Theme bestehen.

Sechs feste Icon-Varianten – Shield, Work, Games, Social, Sleep und Study – werden konsistent gerendert. Ein ausgewähltes Schild wird nicht durch ein zufälliges Schriftzeichen ersetzt.

Auf Android zeigt Customize eine verkleinerte **echte native `BlockingScreenView`**, also dieselbe View-Komponente wie das App-Overlay. Das ist keine bloße beliebige HTML-Skizze. Die Preview hat jedoch keinerlei Regelautorität: Ihr Timer ist nur Vorschau, sie zählt keine echten Blocking-Versuche und verändert keine laufenden Pläne. Nicht unterstützte Plattformen kennzeichnen ihre Näherung ehrlich.

**Scroll-Korrektur im anschließenden Auftrag:** Die eingebettete Android-Vorschau darf vertikale Wischgesten nicht mehr vollständig für sich beanspruchen. Wischen über ihr bewegt die umgebende Seite, während Taps für die Vorschau erhalten bleiben. Customize steht oberhalb der hohen Vorschau. Die echte Blocking-Overlay-Ansicht behält ihre eigene Scrollfunktion. Strict- und aktive-Focus-Bearbeitungssperren bleiben absichtlich bestehen. Die Tastaturabstände gehören den Bearbeitungsdialogen; die verdeckte Blocking-Seite darf bei geöffneter Tastatur nicht zusätzlich zusammenschrumpfen und überlaufen.

### 13.5 Return-Verzögerung und Anti-Loop-Verhalten

Für die Rückkehr gibt es Sekunden- und Minuten-Presets, einschließlich 1/3/5/10/15 Sekunden sowie längeren Werten bis 15 Minuten; vorhandene Immediate-/20-Sekunden-Optionen bleiben erhalten.

Der ovale Return-Button füllt sich von links nach rechts und wird erst nach Ablauf aktiv. Die native Seite prüft die Deadline, nicht nur die Flutter-Animation.

- Home beziehungsweise Wechsel zur eigenen App setzt die Wartezeit nicht zurück und entfernt das wartende Overlay nicht einfach vorzeitig.
- Erneute Accessibility-Ereignisse, Neuzeichnen und Wechsel zwischen blockierten Zielen verlängern denselben Versuch nicht endlos.
- Nach gültigem Return wird das Overlay zuerst entfernt und anschließend MyLifeGraph beziehungsweise eine sichere Home-Rückkehr geöffnet.
- Return beendet den aktuellen Block-Screen, **nicht** den Blocking-Plan oder Strict.
- Ablauf der Regel und vorgesehene Sicherheitsausgänge verhindern eine beabsichtigte Endlossperre.

**Bewusste Sicherheitsgrenze:** Das ist keine kioskfeste, deinstallationssichere Geräteverwaltung. Telefon, Alarm, Systemeinstellungen und weitere notwendige Android-Auswege bleiben berücksichtigt. Hersteller/SystemUI können Overlay-Verhalten beeinflussen. Eine absolute Zusage „man kommt unter keinen Umständen irgendwo heraus“ wäre falsch und gefährlich.

### 13.6 Website-Blocking

Website-Beobachtung ist separat zustimmungspflichtig. Die Umsetzung erkennt Domains an bekannten Adressleisten-IDs ausgewählter Browser, darunter Chrome-Varianten, Edge, Brave, Firefox und Samsung Internet.

- Keine universelle DNS-/VPN-Filterung.
- Keine Garantie für jeden Browser, versteckte Adressleisten oder jede Suchoberfläche.
- Kein Mitschreiben beliebiger Seiteninhalte, URL-Queries oder kompletter Surfverläufe.
- Eine private Offline-Blockseite hat JavaScript, Netzwerk- und Dateizugriff abgeschaltet.
- Rückkehr/Back führt sicher heraus, statt sofort denselben blockierten Tab erneut sichtbar zu machen.
- Der fremde Browser-Tab wird **nicht tatsächlich auf eine neue URL umgeschrieben**. Das war eine ursprüngliche Lösungsüberlegung, nicht die implementierte Garantie.

### 13.7 Lokale Statistiken und Timer-Benachrichtigungen

Blocking Insights zeigt gemessene Vordergrundnutzungsdauer, nicht Aufmerksamkeit oder „echte Produktivität“. Screen-off-Zeiten werden berücksichtigt. Website-Budgetbeobachtung beginnt erst mit Zustimmung; es wird kein rückwirkender vollständiger Browser-Verlauf behauptet.

Zeitlich begrenzte aktive Blocking-Pläne haben eine stille Android-Benachrichtigung mit Name und vom System aktualisiertem Countdown. Pause, Deaktivierung, Löschen und Ablauf entfernen sie entsprechend dem nativen Lifecycle. Fehlende Notification-Berechtigung deaktiviert nicht das Blocking selbst.

Das ist **kein FCM-Push** und kein allgemeiner Live-Timer für jeden Planner-Termin. Android/OEM/DND können die Darstellung beeinflussen.

### 13.8 Schutz vor konkurrierenden Änderungen

Editoren behalten ihre Ausgangsrevision. Ein alter Detaildialog darf keine zwischenzeitlich veränderten Regeln überschreiben oder einen gelöschten Plan neu erzeugen. Während Save laufen Back-/Swipe-/Doppeltap- und Tastaturänderungen nicht unkontrolliert weiter. Fehler erhalten den Entwurf, statt Erfolg vorzutäuschen.

Verspätete Status-/Nutzungsantworten sind gegen den aktuellen Auswahlstand abgegrenzt. Auch nach entzogener Beobachtungsberechtigung bleibt es möglich, gespeicherte Ziele zu entfernen oder Budgets zu reduzieren; neue oder weitergehende Beobachtung erfordert wieder die passenden Rechte.

## 14. Watch-Daten / Health Connect

Der gewählte Weg ist **Garmin beziehungsweise kompatible Quelle → Android Health Connect → MyLifeGraph**, nicht eine direkte Garmin-Developer-API. Ein eigenes Garmin-Developer-Konto ist für diesen Weg nicht erforderlich; die Quelle muss ihre Daten aber tatsächlich nach Health Connect schreiben und der Nutzer muss den Zugriff erlauben.

Aktueller Umfang:

- unterstütztes Android/Health-Connect-Setup, im Vertrag Android 14+;
- optionale Schlaf- und Schrittdaten;
- getrennte Cloud-Zustimmung und Android-Leseberechtigung;
- ein gebundenes Gerät pro Konto für diese Importbeziehung;
- begrenzter Vordergrund-Sync der letzten sieben Profil-Kalendertage;
- automatischer Versuch bei Initialisierung/Rückkehr für bereits korrekt verbundene Geräte, zeitlich gedrosselt;
- manuelles `Sync now`, `Stop sharing` und `Delete imported data`.

**Connected** bedeutet, dass die erforderliche App-/Freigabeverbindung bestätigt ist. Es bedeutet nicht „die Garmin-Uhr ist gerade per Bluetooth erreichbar“ oder „die letzten Daten sind garantiert aktuell“. Das neue große Watch-Symbol visualisiert diesen Status, ohne ihn aufzublähen. Fehler, anderes gebundenes Gerät und „hier nicht verfügbar“ bleiben unterscheidbar.

Stop sharing löscht nicht automatisch vorhandene Daten. Delete imported data entfernt die vorgesehenen Importdaten und deaktiviert die Freigabe, nicht manuelle Check-ins oder bereits formulierte alte Coach-Antworten.

### Schlaf im Morning-Check-in übernehmen

Wenn passende Berechtigungen und Daten vorhanden sind, kann ein noch ungespeicherter Morning-Check-in **Watch sleep / Use times** anbieten. Eine geeignete Schlafsession wird dem ausgewählten Profil-Tag zugeordnet. Übernahme ist ausdrücklich; danach bleiben die Zeiten editierbar und müssen normal gespeichert werden.

Manuelle Änderungen, ein bereits gespeicherter Capture oder ein überprüfter Voice-Entwurf werden nicht durch einen verspäteten Import überschrieben. Annehmen, Verwerfen oder eigenes Editieren verhindert erneutes unerwünschtes Anbieten im selben Entwurf.

Importierte Tagesaggregate sind zusätzliche herkunftsmarkierte Beobachtungen für den Datenkontext. Sie sind kein zweiter autoritativer Schreiber von Morning/Evening und dürfen nicht mit überlappenden manuellen Angaben doppelt gezählt werden.

## 15. Benachrichtigungen: drei unterschiedliche Mechanismen

| Mechanismus | Zweck | Nicht damit verwechseln |
| --- | --- | --- |
| Inbox / In-app reminders | Gespeicherte Hinweise, Read/Unread, Dismiss/Restore und zulässige Navigation | Existenz eines Inbox-Eintrags beweist keine Systemzustellung |
| Android Push über FCM | Bewusst aktivierte wichtige Erinnerungen auch bei geschlossener App | Kein Garant bei Force-stop, Offline-Zustand oder OEM-Einschränkungen |
| Lokale Blocking-Timer | Aktiver Geräte-Countdown eines Blocking-Plans | Kein Cloud-Push und kein neuer Planner-Datensatz |

### 15.1 Inbox

Inbox wurde aus den allgemeinen Settings in die gemeinsamen Header-Aktionen verschoben. Karten sind kompakter; Read/Unread, Dismiss und Open sind Icon-Aktionen. Das Antippen einer Karte öffnet dasselbe erlaubte Ziel. Verschachtelte Buttons lösen nicht zusätzlich die Karte aus.

Öffnen ist nicht automatisch Gelesen-Markieren. Gelöschte beziehungsweise ausgeblendete Einträge besitzen den vorgesehenen Dismiss-Lifecycle und können über `Dismissed / Restore` zurückgeholt werden. `Load more` erweitert die geladene Historie; Zähler beziehen sich auf geladene Einträge, nicht unbegrenzt auf alle Daten.

### 15.2 Unterstützte Push-Kategorien

- Morning Check-in, sofern für den Profil-Tag noch nicht gespeichert;
- Evening Check-in, entsprechend;
- wichtige heute fällige Tasks/Deadlines;
- kurz vor einer belastbaren empfohlenen Bettzeit;
- seltene, hinreichend belegte wichtige Muster aus der definierten Regelklasse.

Die Musterregel bedeutet nicht, dass jede neu gefundene Korrelation oder ein beliebiges „Instagram macht dich müde“-Beispiel automatisch Push auslöst. Die konkreten Zulässigkeitsregeln sind enger.

Morning und Evening sind getrennt aktivierbar und haben editierbare Profil-Uhrzeiten, standardmäßig 08:00 und 20:00. Master-Schalter, Kategorien und Quiet Hours bleiben unter Nutzerkontrolle. Die zusätzlichen Check-in-Opt-ins werden Bestandsnutzern nicht einfach eingeschaltet.

Anti-Spam und Zustellung:

- eigener begrenzter Worker im API-Betrieb, kein Firebase-Cloud-Functions-Umbau;
- höchstens zwei Check-in-Versuche und zwei Versuche der anderen Kategorien pro rollenden 24 Stunden;
- Muster-Cooldown von 30 Tagen;
- enge Zustellfenster und keine späte Welle veralteter Nachhol-Pushes;
- erneute Prüfung, ob der Check-in inzwischen gespeichert wurde;
- Geräte-/Sitzungsbindung, Duplikatkontrolle und generische sensible Daten vermeidende Texte;
- kein automatisches Wiederholen unklarer Sendefälle mit Spam-Risiko.

FCM-Annahme ist nicht gleich physisch sichtbare Benachrichtigung. Android-Berechtigung ist nicht gleich Cloud-Zustimmung. Web-/iOS-Push und E-Mail-Erinnerungen sind damit nicht automatisch unterstützt.

## 16. Visuelles System, Navigation und Bediengefühl

### Vier Appearance-Modi

Dark bleibt der App-Standard; Light, Space und Liquid Glass sind gerätelokale Optionen. **Die Produktwebseite startet dagegen mit Liquid Glass.**

Liquid Glass wurde mehrfach verfeinert: dunkler Graphit-/Silbercharakter, dezente Stahlblau-Akzente, durchscheinende Flächen und Lichtkanten statt großer weißgrauer Kästen. Der geschätzte violette Hintergrundverlauf blieb erhalten. Planner-Kategorien färben eher schmale Akzente als ganze unlesbare graublaue Karten.

Die bestehenden Layoutpositionen und fachlichen Farben sollten nicht beliebig neu erfunden werden. Gemeinsame Tokens steuern Oberflächen, Radien, Kontraste und Interaktionen. Menüs und Dialoge dürfen für Lesbarkeit deutlich deckender sein als dekorative Glasschichten. Kein Blur-Filter auf jeder einzelnen Karte; High Contrast und Reduced Motion bleiben berücksichtigt.

### Einklappbare Floating Island

Die Header-Aktionen sind in allen Themes als gemeinsame Form organisiert, mit deren eigenen Farben:

- geschlossen ein runder, etwa 48px großer Menübutton;
- Öffnen nach links **in derselben Zeile**, ohne Titel/Seiteninhalt umzuschieben;
- weicher Reveal mit Clipping/Fade, keine verzerrten oder skalierten Icon-Glyphen;
- möglichst viele Icons nutzen den tatsächlich verfügbaren Platz; keine starre „immer vier“-Regel;
- erst bei echtem Überlauf kommt eine Scrollhilfe, bei extrem schmalem Platz bleibt horizontales Scrollen;
- Antippen außerhalb, Scrollen/Swipen, Back, Escape, Aktion und Seitenwechsel schließen;
- außerhalb begonnene Gesten werden dabei nicht vom Menü verschluckt;
- keine zusätzlichen ruhenden Kästen um jedes Icon; Interaktionsfeedback und Tastaturfokus bleiben;
- ein kleiner Unread-Punkt erhält die Auffindbarkeit eines Coach-Hinweises.

### Informationen und Haptik

Lange Texte wurden durch kurze Titel, knappe Zustände und optionale Hilfen ersetzt. Wichtige Zustimmung, Fehler, Kosten-/Datenhinweise und Warnungen werden **nicht** aus dekorativen Gründen versteckt.

Info-Aktionen bleiben zugänglich; Long Press auf geeignete Überschriften ergänzt eine kleine örtlich verankerte Erklärung. Kein großer Dialog mit unnötigem Close-Button. Außen-Tap/Back/Escape schließt. Es gibt keinen Lesetimer, der mitten im Lesen verschwindet. Lange Erklärungen können innerhalb der begrenzten Hilfe scrollen.

`Haptic feedback` ist standardmäßig an und gerätelokal abschaltbar. Es ist dezent und respektiert unterstützte Plattformen; Web/Desktop bekommen keine erfundene Vibration. Gerätegefühl bleibt physisch zu prüfen.

### Swipes und Aktualisieren

- Hauptseiten folgen einer eindeutigen horizontalen Bewegung; vertikales Scrollen und verschachtelte Scroller behalten Priorität.
- Seiteninhalt folgt nach der Plattform-Bewegungsschwelle dem Finger; erst ein ausreichender Weg oder klarer Flick schließt den Wechsel ab.
- Dokumentierte Entscheidung: ungefähr 22% Breite, begrenzt auf 48–120px, beziehungsweise gerichteter Flick ab 32px und 650px/s.
- Routing wechselt erst nach dem Einrasten. Abbrechen führt zurück, ohne Datenmutation.
- Spätere Tabs kommen von rechts, frühere von links – bei Buttons und Gesten konsistent.
- Bewegte Seiten haben eine deckende Übergangsfläche, damit nicht zwei Texte gleichzeitig durchscheinen.
- Pull-to-refresh für Today, Insights, Planner und Coach ersetzt auf kleinen Screens den überfüllenden Header-Refresh. Größere Layouts und ausdrückliche Retry-Aktionen bleiben erhalten.

## 17. Produktwebseite und interaktive Vorschau

Die eigene Webseite liegt unter `apps/website` und wird unabhängig von der Flutter-Web-App gehostet. Englisch ist Standard, Deutsch vollständig auswählbar; Sprache und Appearance werden lokal gespeichert.

Sie enthält Produktbeschreibung, Funktionsübersicht, Einstieg zur App/Android-Releases und eine vereinfachte interaktive Vorschau. Diese verwendet **ausschließlich erfundene In-memory-Daten und vorgefertigte Coach-Antworten**. Kein Account, keine echte KI-Anfrage, keine Supabase-Verbindung.

Die Demo startet über eine attraktive, screenshotartige Vorschau mit Glass-Play-Aktion. Erst danach öffnet sich ein Modal, auf Mobile fullscreen. So fängt eine bereits aktive eingebettete Demo nicht jeden Scrollversuch auf der normalen Seite ab. Schließen stellt Scrollposition und Fokus wieder her; die Demo behält ihren Zustand bis Reset/Reload.

Ein dezenter Hinweis ist sowohl außen als auch im geöffneten Demo-Header sichtbar: vereinfachte Vorschau, nicht die vollständige App. Desktop-/Mobile-Aufbau orientiert sich an der App, bleibt aber ausdrücklich eine synthetische Tour.

Der dekorative Hero zeigt ein CSS-3D-Handy mit synthetischem Today-Inhalt. Die anfängliche Scroll-Drehung wurde entfernt. Stattdessen: sehr geringe Schwebebewegung und leichte Mausneigung; offscreen, im Hintergrund und bei Reduced Motion pausiert beziehungsweise deaktiviert. Kein Videodownload, WebGL-Paket oder heimlicher Account-Screenshot.

Die harten Ränder der Hintergrund-Akzentflächen wurden durch weich auslaufende Masken entschärft, auch für breite Screens. Das wirkt auf Dekoration, nicht auf Lesbarkeit oder Klickflächen.

Settings der echten App enthält einen kurzen **Website**-Link. Die Webseite ist nicht unter einem beliebig angehängten Pfad der produktiven Flutter-App eingebaut; sie hat ihr eigenes Vercel-Projekt und ihre eigene CSP.

---

## 18. Wesentliche Fehler: Symptom, Ursache und Korrektur

Die folgende Auswahl enthält belegte Korrekturen beziehungsweise ausdrücklich begrenzte Diagnosen. Sie soll verhindern, dass ein neuer Agent die Probleme versehentlich wieder einbaut.

| Symptom | Ursache / Grenze | Korrektur oder verbindliche Schutzregel |
| --- | --- | --- |
| Watch-Schlafzeiten in Berlin exakt zwei Stunden zu früh | Bereits profilzonenbezogene Zeit wurde erneut gerätelokal umgerechnet | IANA-Konvertierung einmal; keine zweite `.toLocal()`-Umdeutung einer bereits zonierten Uhrzeit; UTC nur an den definierten Grenzen |
| Kurzes „Authentication failed“, danach trotzdem angemeldet | Abgelaufene gespeicherte Supabase-Session wurde vor asynchroner Token-Erneuerung für einen geschützten Read benutzt | Vor solchen Reads gültige Session/SDK-Refresh abwarten; parallele Erneuerungen zusammenführen; echte Fehler nicht verstecken |
| Auth-Fehler bleibt beim echten Retry sichtbar oder Streamfehler wird unkontrolliert | Fehler-/Ladezustände und Auth-Stream-Ereignisse waren nicht sauber getrennt | Tatsächlicher Retry wechselt in Loading; Auth-Streamfehler explizit behandeln; normale gültige Refreshes nicht unnötig als Logout behandeln |
| Deutscher Coach scheitert, danach „another request in progress“ | Completion akzeptierte den sprachgebundenen Fingerprint nicht passend zur Claim-Identität | Additive German-Completion-Migration und passende API-/Client-Verträge; keine pauschale Löschung laufender Claims |
| Gemini meldet lokalen Provider-/Codex-Fehler | Sammeltexte, Capability-Zuordnung beziehungsweise alte Providerantworten konnten irreführen | Explizite Provideridentität, keine Basisprovider-Abfrage für abgewiesenes BYOK, verspätete falsche Antworten verwerfen, bessere Fehlertexte |
| Modellwechsel allein löst nicht jeden Gemini-Fehler | Modellzugang, Adapter, Allowlist und Live-Anbieter sind getrennte Fehlerquellen | Zulässige Modellauswahl und Adapter-/DB-Kompatibilität; keine Zusage, jeder Providerfehler sei damit erledigt |
| Voice-Review behält alte Schlafuhrzeit trotz klarer neuer Angabe | Entwurf und vorhandene Antworten wurden nicht korrekt selektiv zusammengeführt | Explizit vorgeschlagene Zeiten ersetzen; nicht erwähnte Antworten erhalten; vollständiges Review vor Save |
| Seiten gleiten beim Zurückwechseln in falsche Richtung | Transition-Richtung nicht konsistent zum Zielindex | Einheitliche richtungsabhängige Navigation für Swipe und Tab-Buttons |
| Zwei Seiten überlappen transparent | Glass-/Übergangshintergründe ließen vorherige Texte durch | Deckende Fläche während des Slides; danach normaler gemeinsamer Hintergrund |
| Settings/Back verschiebt Planner/Coach oder kehrt auf falschen Tab zurück | Route-lokaler Headerzustand beziehungsweise noch auslaufender Root-Swipe wirkte unter der gepushten Route weiter | Back-Zustand route-lokal; verdeckten Pager auf geroutete Seite zurücksetzen und späte Settlement-Ereignisse abgrenzen |
| Coach-Hinweis gilt als gelesen, obwohl nur kurz angeswipt | Sichtbarkeit mit bloßem Mount/Teilansicht verwechselt | Tatsächliche Tab-/Viewport-/Route-Sichtbarkeit prüfen, nicht verdeckte Nachbarseite quittieren |
| Speech-Auswahl unten abgeschnitten, nach erneutem Öffnen Modelle unsichtbar | Sheet-Höhe, Root-Overlay und Insets nicht zuverlässig berücksichtigt | Root-Sheet, Safe Area, vollständige Liste und Scrollfähigkeit |
| Planner wirkt nach fehlgeschlagenem Refresh gültig und erlaubt alte Aktionen | Erhaltene alte Daten wurden nicht von bestätigter Aktualität getrennt | Sichtbarer Retry; abgeleitete Mutationen bis erfolgreichem Read sperren; Reads zusammenführen |
| Insights-Refreshfehler bei vorhandenen Daten unsichtbar | Retained-data-Zustand überdeckte Fehleranzeige | Daten erhalten, Fehler/Retry trotzdem anzeigen |
| Blocking-Einrichtung startet WLAN-/NFC-Flows mehrfach | Schnelle wiederholte Aktivierung vor dem nächsten Frame | Synchrone Busy-/Saving-Sperren; keine zweite native Anfrage |
| Alte Blocking-Dialoge überschreiben neuere Regeln | Fehlende Bindung an die Öffnungsrevision beziehungsweise entfernte Identität | Revision prüfen, Konflikt zeigen; keine Wiederbelebung gelöschter Pläne |
| Return-Countdown könnte durch wiederholte Ereignisse endlos starten | Timer an Darstellung statt endlichen Versuch gebunden | Monotone Deadline pro Versuch; Repaint/Home verlängern sie nicht; Overlay vor Navigation entfernen |
| Header-Titel/Icon-Aktionen bei schmaler Breite unzugänglich | Feste Breiten, unnötige Reserveflächen, Semantics-Lücken | Gemessene titelbegrenzte Island, Überlauf erst bei Bedarf, echte 44px-Ziele, Screenreader-/Fokus-Prüfungen |

Nicht jeder ursprüngliche Verdacht war ein echter Serverausfall. „Dashboard unavailable“ oder Providerfehler allein beweisen weder einen ausgefallenen VPS noch ein leeres Tokenkonto. Zuerst konkreten Request, Zustand und Reproduktion prüfen; keine pauschalen Fehlerunterdrückungen.

## 19. Zeitzonen, Persistenz und Datenintegrität

Diese Regeln sind besonders wichtig, weil viele Funktionen dieselben Daten verwenden:

1. **Zeitpunkt und lokale Uhrzeit sind verschieden.** Absolute Ereignisse werden als bewusste Zeitpunkte übertragen; für Anzeige und Tageszuordnung gilt die jeweilige zuständige IANA-Zone.
2. **Cloud-Capture/Planner/Focus-Projektionen verwenden Profilzeit**, soweit der Vertrag dies festlegt. Gerätebezogene Blocking-Wochenpläne verwenden Gerätezeit. Diese Unterschiede nicht blind „vereinheitlichen“.
3. **Keine festen +1/+2-Stunden-Hacks.** DST/Sommerzeit und andere IANA-Zonen müssen korrekt bleiben.
4. **Manuelle DST-Lücken/-Mehrdeutigkeiten nicht raten.** Nicht existente beziehungsweise mehrdeutige lokale Eingaben müssen korrigiert werden; importierte absolute Instants behalten ihre Identität.
5. **Kalendertage nicht als pauschale 24-Stunden-Abstände behandeln.** Das betrifft rückwirkende Check-ins, Past-Vergleiche, Wochenprojektionen und Reminder.
6. **Versionen und Revisionsprüfungen nicht umgehen.** Derselbe Request mit geändertem Inhalt ist kein gültiger Retry.
7. **Speicherung und Projektion unterscheiden.** Ein nachgelagerter Refreshfehler macht eine bestätigte Datenänderung nicht ungeschehen.
8. **Lücken nicht füllen, nur damit Charts schön aussehen.** Demo-Accounts dürfen bewusst synthetisch gepflegt werden; echte Nutzerhistorie nicht ohne separaten Auftrag verändern.

Die Tests decken mehrere Zonen einschließlich Berlin, UTC und weiteren IANA-Fällen sowie DST-Grenzen ab. Das ist keine Behauptung, jede mögliche Eingabe jeder IANA-Zone auf jedem Gerät manuell durchgespielt zu haben.

## 20. Auth, Konto und Sicherheitsgrenzen

Google- und E-Mail-Anmeldung bleiben erhalten. Die Login-Seite wurde kompakter, aber wieder mit sichtbaren E-Mail-Feldern und gut lesbarer Überschrift gestaltet. Bei Tastatur, großen Schriften, Fehlern oder nötigen Datenschutzhinweisen darf sie weiterhin scrollen; „alles auf jeden Bildschirm zwingen“ ist kein sinnvolles Ziel.

Account-Funktionen umfassen die vorgesehenen Zeitzoneneinstellungen, JSON-Export, Recovery und bestätigte Kontolöschung. Gerätebezogene Preferences sind nicht automatisch exportierbare Cloud-Produktdaten. Pilot-/Datenschutzhinweise und ihre konfigurierbaren Gates dürfen nicht aus UX-Gründen umgangen werden.

Unverändert verbindlich:

- owner-begrenzte RLS und explizite Grants;
- eingeschränkte Service-RPCs und private Audit-/Usage-Ledger;
- keine Backend-Secrets im Client, in Coach-Tools oder in Build-Caches;
- keine angepassten historischen Migrationen;
- keine Logausgabe von `.env`, Keys, Bearern oder Datenbankpasswörtern;
- insbesondere kein Lesen/Kopieren lokaler Codex-OAuth-Dateien durch den Agenten;
- keine stillen Provider-Fallbacks, Datenweitergaben oder automatischen Paid-Upgrades;
- keine Sicherheits-/Datenschutzgarantie allein aus einem grünen Testlauf.

Für die kostenlose Supabase-Vorgabe wurde kein kostenpflichtiger Tarifwechsel zur Passwort-Leak-Prüfung autorisiert. Nicht behaupten, ein nicht aktivierter Premium-Schutz sei aktiv. Den aktuellen Dashboard-/Tarifstatus bei einer späteren Änderung separat prüfen.

---

## 21. Agenten-Workflow: ausdrückliche Freigabe gilt für den Auftrag

**Die zentrale Workflow-Änderung steht in `AGENTS.md`, Abschnitt „Authorization Before Updating Main“.** Ein Agent soll nicht an jedem Zwischenschritt erneut nachfragen, wenn die Veröffentlichung für genau diesen Auftrag bereits ausdrücklich erlaubt wurde.

| Nutzerauftrag | Erlaubnis |
| --- | --- |
| „Prüfe / analysiere / empfehle“ | Lesen und berichten; keine ungefragte Implementierung |
| „Implementiere / fixe das“ | In-Scope-Code, Tests und nötige Dokumentation lokal ändern; noch keine automatische Remote-Veröffentlichung |
| „Implementiere, teste und setze es live; PR und Merge sind erlaubt“ | Arbeitsbranch erstellen/verwenden, pushen, PR, Checks abwarten, In-Scope-Fehler beheben, Main mergen, Release signieren/veröffentlichen und betroffene bestehende Produktionsdienste aktualisieren |
| „Merge auf Main“ ohne Produktionsauftrag | Nötige Branch-/PR-/Check-/Merge-Schritte; nicht automatisch zusätzlicher VPS-/Cloud-Rollout |
| „Nicht deployen“ | Deployment bleibt gesperrt, auch wenn andere Veröffentlichungsschritte erlaubt sind |
| Keine explizite Remote-Freigabe | Vor Push/PR/Deployment/sonstiger Remote-Mutation nachfragen |

### 21.1 Beispiel für einen vollständigen Auftrag

> Implementiere die beschriebenen Änderungen auf einem passenden Arbeitsbranch. Prüfe sie mit den erforderlichen Tests, behebe reproduzierbare Fehler, pushe den Branch und erstelle beziehungsweise aktualisiere den passenden Pull Request. Wenn alle erforderlichen Checks erfolgreich sind, darfst du ohne erneute Rückfrage auf Main mergen, die signierte APK als Release bereitstellen und die betroffenen bestehenden Produktionsdienste einschließlich erforderlicher geprüfter additiver Migrationen aktualisieren. Keine destruktiven Datenoperationen, neuen kostenpflichtigen Dienste oder sachfremden Änderungen.

Diese Freigabe ist **auf die Aufgabe begrenzt**, kein Freibrief für jedes zukünftige Projekt. Ein bestehender passender PR soll weiterverwendet werden; nicht für jeden kleinen Nachtrag eine unnötige neue Parallelentwicklung starten. Wenn der alte PR schon gemergt ist, auf einem neuen `codex/…`-Arbeitsbranch weitermachen.

### 21.2 Was trotz Freigabe nicht wegfällt

- Erforderliche GitHub-Checks und Administrator-/Branchschutz bleiben verpflichtend.
- Kein Force-Push oder Überschreiben fremder neuer Arbeit.
- Vor Main-Aktualisierung Kandidat, Commit-Differenz und Checks prüfen; Ziel-Drift erneut lesen.
- Geplanten konkreten Veröffentlichungsschritt kurz mitteilen; bei vorhandener Freigabe ist das **keine erneute Erlaubnisfrage**.
- Unverwandte Änderungen, neue bezahlte Abhängigkeiten, abgeschwächte Sicherheit oder destruktive Datenoperationen brauchen neue Autorität.
- Ein früheres „mach alles live“ für Feature A erlaubt nicht automatisch die Veröffentlichung einer später nur zur Analyse angefragten Änderung B.

### 21.3 Kontext vor Änderungen

`AGENTS.md` vollständig lesen. Danach zielgerichtet die zuständigen Feature-Eigentümer und ihre übergreifenden Invarianten lesen – nicht jedes Markdown des Repositories pauschal laden.

Vor der ersten Änderung:

1. Branch, HEAD, staged/unstaged/untracked Zustand prüfen.
2. Aufgabenbasis mit `git rev-parse HEAD` erfassen.
3. Betroffene Pfade, Tests und öffentliche Schnittstellen lesen.
4. Passende Owner-Dokumente bestimmen und im Arbeitsvermerk benennen.
5. Bestehende Nutzeränderungen erhalten und nicht still in den eigenen Commit aufnehmen.

Dokumentation ist Teil der Fertigstellung. Verhaltensänderungen brauchen passende Owner-Updates; bei rein verhaltenserhaltender Änderung darf bereits korrekte Dokumentation unverändert bleiben, mit kurzer Begründung.

## 22. Teststrategie: echte Reproduktion statt spekulativer „Fixes“

Der Wunsch war wiederholt: funktionale und deutliche visuelle Bugs finden, aber **nur bestätigte reproduzierbare Bugs beheben**. UX-Ideen ohne klaren Fehler zunächst empfehlen, nicht als Bugbehebung verstecken.

Typischer Ablauf:

- Symptom und erwartetes Verhalten festhalten.
- Gezielt reproduzieren, möglichst zunächst roter Regressionstest.
- Engen Fix implementieren.
- Dasselbe Szenario grün nachprüfen; angrenzende Flows testen.
- Unterschiedliche Fehlerpfade prüfen: Back, Escape, Swipe, schnelles Doppeltippen, abgebrochener Request, Resize, große Schrift, Hintergrundwechsel, altes Ergebnis nach neuer Auswahl.
- Review nicht allein auf happy-path Screenshots begrenzen.

Es gab mehrere unabhängige Review-Runden zu Navigation, Flutter-Flows und nativen Regeln. Besonders intensive synthetische Tests prüften wiederholte Tabwechsel, wartende Saves sowie tausende Overlay-/Home-Ereignisse ohne Verlängerung der Return-Deadline. Das beweist konkrete Invarianten, nicht absolute Fehlerfreiheit sämtlicher Geräte.

**Wichtig auf Windows:** Ein vollständiger lokaler POSIX-Prüfharness konnte an fehlendem `setsid` scheitern; einige Golden-Differenzen waren plattformabhängig. Die Lösung war ein vollständiger Linux-/GitHub-Lauf, nicht das Entfernen der Sicherheitsprüfungen oder blindes Neugenerieren aller Referenzbilder.

Aktuelle Testzahlen und aktuelle Commit-Evidenz gehören in `docs/verification.md`, ältere Läufe in die Historie. Ein Testfile im Repository ist kein Beleg, dass der aktuelle Stand gerade erfolgreich getestet wurde.

## 23. CI, Caches und reproduzierbare Builds

Die Optimierung war bewusst konservativ:

- sichere Dependency-Caches statt ganzer Arbeitsverzeichnisse;
- Gradle nur freigegebene Download-/Wrapper-Bereiche, keine Keystores, Signierkonfiguration, generierten Firebase-Dateien oder gesamten Projekt-Buildzustände;
- weiterhin Lock-/Hash-Prüfung, `npm ci` und die vorgesehenen Installationsregeln;
- Wiederverwendung nur für ein exakt identifiziertes, überprüftes **Debug-Web-Verifikationsbundle**;
- Cache-Key berücksichtigt Commit, relevante Quellen und Buildskripte, Lockfiles, tatsächliche Toolchain-Versionen, OS/Architektur, Runner und Buildargumente;
- Manifest-/Prüfsummenfehler, fehlende Outputs oder geänderte Eingaben führen zum Neubau;
- keine großzügige Präfix-Wiederherstellung für Build-Ergebnisse;
- Tests, Sicherheitsprüfungen und Signierung bleiben auch bei Cache-Hit erhalten.

Release-APK, Vercel-Produktion und E2E haben eigene Buildidentitäten. Sie dürfen das Debug-Verifikationsbundle nicht als auslieferbares Produkt übernehmen. Signierte Kandidaten werden frisch gebaut und an SHA/Tag/Zertifikat gebunden.

### Gemessene Einsparung – historische Messung vom 26. September

| Versuch | Neubau | Cache-Hit | Einordnung |
| --- | ---: | ---: | --- |
| Lokaler Web-Verifikationsbuild | 40,39 s | 1,20 s | 39,19 s beziehungsweise rund 97% weniger Zeit in diesem Versuch |
| Weiterer lokaler Build | 39,55 s | 2,22 s | 37,33 s beziehungsweise rund 94,4% weniger |
| Wiederholter GitHub-Web-Job, Build-Helfer | 68,44 s | 0,27 s | Runner-Setup und Cache-Transfer nicht in diesen Helferzeiten enthalten |

Zusätzlich wurden Quelländerung, unerwarteter Cache-Inhalt und No-cache-Pfad geprüft. Die Zeitwerte sind keine pauschale Beschleunigungszusage für jede Pipeline oder den heutigen Rechner.

### Vollständiger Build ohne diese Caches

- Lokaler Web-Gate: `npm run verify:web -- --no-cache`.
- Passender direkter Windows-Helfer: `node scripts/web_build_cache.mjs --no-cache`, mit konfiguriertem bestehendem Flutter-Launcher.
- Manuelle GitHub-Workflows: `no_cache=true`.
- Repository-weites Build-Opt-out: `CI_NO_CACHE=true` für die dokumentierten Workflows, einschließlich Tag-Builds.

Dadurch werden Restore und Save umgangen; bereits installierte Toolchains werden nicht unnötig neu installiert. Vercel hat eine getrennte Cache-Politik und kompiliert weiterhin selbst.

## 24. Lokale Entwicklung, alte VM und Produktion

### 24.1 Drei Umgebungen sauber auseinanderhalten

| Umgebung | Zweck | Produktionswirkung |
| --- | --- | --- |
| Vollständig lokal | Eigene Supabase-/Backend-/Frontend-Prüfung nach den Repo-Skripten | Keine automatische Cloud-Wirkung |
| Laptop mit Cloud-Frontend | Lokales Flutter, aber echte Supabase-/VPS-Endpunkte | **Produktaktionen können echte Kontodaten verändern** |
| Produktions-Web/APK | Veröffentlichter Client und bestehender VPS/Supabase | Echter Live-Betrieb |

Guest/Mock und die synthetische Website-Demo sind zusätzliche, strikt lokale Datenwelten. Ein gleich benanntes lokales Testkonto ist nicht automatisch dasselbe Konto in Supabase Cloud.

Der unterstützte normale lokale Einstieg ist `npm run start:local`. Für die dokumentierte Laptop-Cloudentwicklung existiert `node scripts/start_cloud_frontend.mjs`. Loopback-Ports und benötigte Konfiguration stehen in `docs/local-dev.md`; nicht aus alten Chat-Portnummern neue parallele Prozessstapel bauen.

### 24.2 Persönliche Entwicklungs-VM wurde stillgelegt, nicht gelöscht

Auf Matthias' eigener VM lag früher ein separater MyLifeGraph-Devstack. Er ist **nicht** der produktive VPS. Am 26. September wurden nach Freigabe die elf Projektcontainer gestoppt und ihre Restart-Policy auf `no` gesetzt. Die lokale App-User-Unit war bereits deaktiviert/inaktiv. Andere Projekte wurden nicht angefasst.

Vor dem Stop liefen Supabase Studio, Meta, Storage, REST, Realtime, Test-Mail, Kong, Vector, Analytics, Auth und PostgreSQL. Die Edge Runtime war bereits gestoppt.

Historische Messung, nicht heutiger Live-Wert:

- ungefähr **1,61 GiB RAM** für die elf Container;
- **64 Prozesse**, 176 Tasks einschließlich Threads;
- CPU-Stichproben etwa **18,63–22,73% eines Kerns**, nicht der gesamten Mehrkernmaschine;
- dem Projekt zugeordnete Plattenbelegung ungefähr **11,86 GB**, einschließlich Images, Volumes und Checkouts, mit Shared-Layer-Einschränkungen;
- nach dem Stop ungefähr 1,48 GiB zusätzlicher verfügbarer Gast-RAM als Momentaufnahme.

**Es wurde kein entsprechender Plattenplatz freigeräumt.** Images, Volumes und Projektdateien blieben erhalten. Ein gesondert restore-verifiziertes Backup und eine eventuelle Plattenbereinigung standen noch aus; spätere SSH-Kontrollen waren durch Timeouts begrenzt. Keinen heutigen Erreichbarkeits- oder Löschstatus daraus ableiten.

Die VM hatte 11 GiB zugewiesenen RAM und eine virtuelle 100-GiB-Disk. Der Proxmox-Host meldete etwa 15,34 GiB nutzbaren RAM, intern 512,11 GB und zwei zusätzliche USB-Datenträger. VM-Disk und Host-Storage **nicht addieren**: Die virtuelle Disk liegt bereits auf dem Host.

Die genaue Bestandsaufnahme und Wiederaufbauarchitektur liegen in `docs/personal-dev-vm-inventory.md` und `docs/personal-dev-vm-rebuild.md`. Vor weiterem Aufräumen neu inventarisieren, geschützt sichern und Restore prüfen. Kein globales Docker-Prune; keine fremden Dienste oder gemeinsam genutzten SDKs löschen.

### 24.3 Datenbank-Sicherheitsworkflow

- Normale Verifikation prüft Migrationsgeschichte und stoppt bei Abweichungen.
- Pending SQL erst lesen; `APPLY_MIGRATIONS=true` ist eine ausdrückliche lokale Opt-in-Handlung, kein Default.
- `RESET_DB=true` ist in normalen Prüf-/Startskripten verboten.
- Ein lokaler Reset ist ein eigener destruktiver Auftrag mit Preview, frischem zielgebundenem Token, Backup und Restore-Verifikation.
- Restore-Verifikation erfolgt in einem **physisch getrennten RAM-only-Postgres-Container**, nicht in der normalen Datenbank.
- Historische Migrationen bleiben unverändert; neue Änderungen additiv über neue Migrationen.
- Vor CLI-Aufrufen installierte Hilfe prüfen statt Flags zu erraten.

## 25. Release, Signierung und Betrieb

### 25.1 Sicherer Standardablauf

1. Arbeitsstand und Aufgabenbasis feststellen; passende Freigabe vorhanden?
2. Implementierung und Owner-Dokumente fertigstellen.
3. Kandidaten gezielt und entsprechend seiner Grenzen vollständig prüfen.
4. Passenden Branch/PR pushen; erforderliche Checks abwarten und echte Fehler beheben.
5. Main-Drift erneut prüfen, geprüften Kandidaten zusammenführen.
6. Bei Schemaänderung: Live-Historie prüfen, reviewed additive Migrationen in richtiger Reihenfolge ausrollen; nicht blind jede lokale Datei erneut anwenden.
7. API-/Executor-/Speech-Release passend vorbereiten und die betroffenen bestehenden Dienste aktivieren.
8. Vercel-Projekt, Commit und READY-Status prüfen.
9. Signierte APK bauen, SHA/Tag/Zertifikat/Version Code/Checksummen prüfen und Release veröffentlichen.
10. Öffentliche Health-/Readiness-Antworten und tatsächliche Artefakte kontrollieren; Geräteprüfung separat ausweisen.

Das bedeutet nicht, dass jeder UI-Fix zwingend Datenbank, Speech und Produktwebseite neu deployen muss. **Nur betroffene Komponenten**, aber deren Kette vollständig.

### 25.2 Wo die Signierungs-Secrets liegen

Die CI nutzt das geschützte GitHub-Environment **`pilot-release`** mit:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Werte gehören nicht in Git, Markdown oder Cache. Ein lokales `key.properties` und der dazugehörige Keystore sind ebenfalls private, ignorierte Dateien. Release-Builds dürfen bei fehlender Signierung nicht still auf den Debug-Key ausweichen.

`FIREBASE_ANDROID_CONFIG_BASE64` liefert die vorgesehene Android-Clientkonfiguration. Das ist nicht der private FCM-Senderschlüssel. **`FCM_CREDENTIALS_JSON` bleibt auf der API-Seite** und darf nicht im APK, Coach-Executor oder Build-Cache landen.

CI entfernt temporäres Signiermaterial auch bei Fehlern. Neue APKs müssen dasselbe passende Signaturzertifikat und einen höheren numerischen Version Code haben. Dateiname allein beweist keine Update-Kompatibilität.

### 25.3 Vercel-Falle aus der letzten Veröffentlichung

Die lokale `.vercel`-Zuordnung zeigte noch auf ein altes Projekt/Team. Deshalb gab es irreführende Statusmeldungen der alten Integration, während das tatsächlich verwendete Projekt später erfolgreich deployte.

Vor einer künftigen Veröffentlichung das **wirklich aktive Projekt und Team** auflösen. Nicht ungeprüft die lokale Zuordnung als Wahrheit verwenden, Zugriffsregeln ändern oder ein weiteres Produktionsprojekt erzeugen. Die Produktwebseite ist ohnehin ein getrenntes Projekt.

### 25.4 In-App-Updates

Android Settings enthält Updates mit installierter Version, Check und Download. Beim geeigneten App-Start wird im Hintergrund begrenzt geprüft, ohne laufende Formulare oder Tastatur zu unterbrechen.

- GitHub-Releases einschließlich Pilot-Prereleases werden anhand der kontrollierten Metadaten geprüft, nicht nur über `/releases/latest`.
- Numerischer Buildvergleich, kein lexikalischer Fehler zwischen `rc.9` und `rc.10`.
- Genau eine automatische Information pro neuer Buildnummer: Dismiss/Back/Outside/Download führen nicht zur ständigen Wiederholung.
- Die bereits angekündigte Version wird vor Anzeige gespeichert; bei fehlgeschlagener Speicherung keine Popup-Schleife.
- Manuelles Prüfen bleibt möglich. Automatische Fehler bleiben unaufdringlich; manuelle Fehler sagen nicht fälschlich „aktuell“.
- Download öffnet den vorgesehenen externen Weg zur APK; Android übernimmt die Installationsbestätigung. Kein stilles Selbstinstallieren.

### 25.5 Skalierung realistisch einordnen

Zehn Nutzer mit normalen Reads sind nicht dasselbe wie zehn gleichzeitige Coach-Analysen. Die Repo-Konfiguration begrenzt öffentliche Reads, Mutationen, Coach-Zulassung, Ausführungen und Speech bewusst. Der Standard-Executor ist besonders eng begrenzt; pro Nutzer bleibt nur eine ausstehende Coach-Anfrage zulässig.

Cloud-Modelle benötigen keine VPS-GPU. Für mehr echte Gleichzeitigkeit zuerst Zulassungs-/Providerbudgets, Snapshot-/DB-Zugriffe und gemessene CPU-/RAM-Last prüfen. Mehr API-Worker oder eine GPU entfernen nicht automatisch durable Quoten und können prozesslokale Annahmen verletzen. Die vorhandene Architektureinschätzung ist **kein zehnparalleler-Nutzer-Lasttest**.

---

## 26. Einstiegspunkte für den nächsten Agenten

Die folgenden Links sind absichtlich auf den übergebenen Release-Tag gepinnt, damit sie auch außerhalb dieses lokalen Ordners funktionieren. Für neue Arbeit anschließend zusätzlich den tatsächlich ausgecheckten aktuellen Stand lesen.

| Thema | Eigentümer / Einstieg |
| --- | --- |
| Verbindlicher Arbeitsablauf und Autorisierung | [AGENTS.md](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/AGENTS.md) |
| Produktüberblick | [Current Product Guide](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/current-product-guide.md) |
| Bestehende technische Übergabe | [Development Handoff](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/development-handoff.md) |
| System- und Datengrenzen | [Architecture](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/architecture.md) |
| Flutter-Verhalten und Plattformgrenzen | [Mobile README](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/apps/mobile/README.md) |
| Today | [Today Overview](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/today-overview-v1-contract.md) |
| Capture und Briefing | [Daily Briefing / Capture](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/daily-briefing-implementation-plan.md) |
| Schreibautorität, Revisionen und Zeit | [Stabilization Contract](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/stabilization-consistency-contract.md) |
| Coach, Sprachen und Speech-Auswahl | [Controlled Coach](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/phase-10-controlled-coach-plan.md) |
| Speech-Server | [Speech Service](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/services/speech_service/README.md) |
| Insights, Past und Skillset | [Personal Learning](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/personal-learning-v1-contract.md) |
| Planner | [Planner Contract](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/planner-v1-contract.md) |
| Exams / Assignments | [Deadline Planner](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/deadline-planner-v1-contract.md) |
| Study Setup | [Study Setup](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/study-setup-v1-contract.md) |
| Tasks, Habits und Focus | [Executable Actions](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/phase-3-executable-actions-contract.md) |
| Kalender | [Calendar Import](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/phase-9-calendar-import-contract.md) |
| Android Blocking – vollständige Grenzen | [Focus Protection](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/android-focus-protection-v1-contract.md) |
| Watch / Health Connect | [Health Connect](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/health-connect-v1-contract.md) |
| Inbox-Lifecycle | [Notification Lifecycle](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/notification-lifecycle-v1-contract.md) |
| Foreground und Android Push | [Notification Delivery](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/notification-delivery-v1-contract.md) |
| Account und Datenkontrolle | [Account Controls](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/v1-account-controls-contract.md) |
| Datenbank / Auth / vollständiges Migrationsinventar | [Supabase Current State](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/supabase-current-state.md) |
| Design | [Visual System](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/frontend-visual-system-v2.md) |
| Kurze, wahrheitsgemäße UI-Texte | [Copy Contract](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/ui-language-and-copy-contract.md) |
| Website | [Website README](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/apps/website/README.md) |
| Android Updates | [App Updates](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/android-app-updates.md) |
| Lokale Befehle / Cache-Steuerung | [Local Dev](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/local-dev.md) |
| Backup / Reset / Restore | [Local Database Safety](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/local-database-safety.md) |
| Stillgelegte VM | [Inventar](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/personal-dev-vm-inventory.md), [Wiederaufbau](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/personal-dev-vm-rebuild.md) |
| VPS-Handoff und Betrieb | [VPS Handoff](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/vps-matthias-handoff.md), [Deployment README](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/deploy/vps/README.md), [Project Admin](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/deploy/vps/PROJECT_ADMIN.md) |
| Release-Abfolge | [Pilot Release Plan](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/vps-pilot-release-plan.md) |
| Signierung | [Release Signing](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/apps/mobile/android/RELEASE_SIGNING.md) |
| Prüfungen / Evidenz | [Verification](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/verification.md) |
| Cross-runtime-Versionsregister | [Current Contracts](https://github.com/MyLifeGraph/MyLifeGraph/blob/v0.1.0-pilot.1-rc.18/docs/current-contracts.json) |

### Empfohlener erster Arbeitsdurchlauf

1. Checkout synchronisieren, vorhandene Änderungen und Branchzuordnung prüfen; nicht blind resetten.
2. `AGENTS.md` lesen und für die neue Aufgabe den Base-Commit festhalten.
3. Release-/Cloud-Stand bei Bedarf frisch lesen; diese Datei ist kein dauerhaftes Monitoring.
4. Nur die betroffenen Eigentümer laden. Bei mehrdeutiger Zuständigkeit erst Architektur/Registry klären.
5. Lokales Szenario reproduzieren; bei Android-spezifischem Verhalten echte APK und Berechtigungen verwenden.
6. Änderung, Regressionstest und nötige Dokumentation zusammen reviewen.
7. `npm run verify:docs`, `git diff --check` und die passenden Produktprüfungen ausführen.
8. Affected-Auswahl ausschließlich mit der **vor Arbeitsbeginn erfassten** Basis: `npm run verify:affected -- --base-ref <task-base-ref>`. Nach eigenen Commits nicht einfach `HEAD` als alte Aufgabenbasis benutzen.
9. Vor Handoff staged, unstaged und untracked Dateien prüfen. Generierte Fehlerscreenshots sind nicht automatisch Release-Inhalt.
10. Nur bei entsprechender Aufgabenfreigabe veröffentlichen; dann den gesamten autorisierten Ablauf ohne überflüssige erneute Erlaubnisfragen abschließen.

## 27. Was ausdrücklich nicht als „schon vollständig gelöst“ gelten darf

- Keine vollständige deutsche Übersetzung sämtlicher App-Seiten; Deutsch gilt gezielt für Coach/Ultra Quick, die Webseite ist separat zweisprachig.
- Kein direkter Garmin-Login und keine universelle Watch-Unterstützung unabhängig von Health Connect und Quelle.
- Kein unbeaufsichtigtes Watch-to-Capture-Speichern ohne Review.
- Kein Browser-unabhängiges DNS-/VPN-Blocking und kein manipulationssicherer Android-Kioskmodus.
- Keine Cloud-Synchronisierung aller gerätelokalen Blocking-/Theme-/Speech-Präferenzen.
- Kein autonom schreibender Coach, kein automatisches Planen aus einer freien Chatantwort.
- Keine garantierte Push-Zustellung nach Force-stop oder bei fehlender Verbindung.
- Kein heimlicher kontinuierlicher Kalender-Sync; `.ics` bleibt bewusster Import.
- Keine automatische Installation einer neuen APK ohne Android-Nutzerentscheidung.
- Kein neuer gemessener Lasttest für zehn gleichzeitig analysierende Coaches.
- Kein vollständiges Backup der alten VM allein durch ihre Markdown-Wiederaufbauanleitung.
- Keine Behauptung, dass synthetische Screenshots echte Handyfotos oder vollständig bestandene Geräteabnahmen seien.

### Verbleibende Geräteabnahme nach dem letzten Release

Besonders sinnvoll sind: Google-OAuth-Kaltstart bei abgelaufenem Token; verschiedene Android-/OEM-Versionen; Blocking mit Home, SystemUI, Telefon/Alarm/Settings; Return nach Timerablauf; Rechteentzug; Neustart; NFC und WLAN; echte Health-Connect-Quelle; lokale Speech-Downloads und Speicherdruck; Push bei erlaubten/abgelehnten Notifications; Update über vorhandene signierte Installation.

Das sind **Abnahmen auf echter Hardware**, keine versteckt als erledigt markierten Implementierungsaufträge. Neue reproduzierbare Fehler daraus gezielt fixen, nicht vorsorglich unrelated Funktionen umbauen.

---

## 28. Die wichtigsten Leitplanken in zehn Sätzen

1. Weniger Erklärungstext, mehr klare Handlung – aber niemals Zustimmung, Fehler oder wichtige Grenzen verstecken.
2. Bestehende Funktionen und kanonische Datenmodelle erhalten; eine UI-Verbesserung ist kein Anlass für einen Backend-Neubau.
3. Änderungen aus Voice und Watch bleiben überprüfbar und nutzen den normalen Speicherweg.
4. Preview, gespeicherte Planung und tatsächliche Ausführung strikt trennen.
5. Gute Reaktionszeit durch kontrollierte optimistische Darstellung, nicht durch vorgetäuschten Erfolg.
6. Zeitzonen mit IANA und klaren Zuständigkeiten behandeln, niemals mit pauschalen Stundenkorrekturen.
7. App Blocking ist wirksame freiwillige Unterstützung mit Sicherheitsauswegen, keine absolute Gerätesperre.
8. Tests müssen den aktuellen Kandidaten belegen; „war früher grün“ genügt nicht.
9. Eine ausdrücklich erlaubte Veröffentlichung vollständig durchführen, ohne dieselbe Erlaubnis wiederholt einzufordern.
10. Am Ende präzise sagen, was lokal geändert, geprüft, veröffentlicht und noch nicht physisch abgenommen wurde.

**Ende der Übergabe.** Diese Datei darf direkt weitergegeben werden; sie enthält keine Zugangsdaten und setzt zum Verständnis keine privaten lokalen Evidenzdateien voraus.
