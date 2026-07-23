# MyLifeGraph: aktueller Produktleitfaden

Status: Beschreibung des tatsächlich implementierten Repository-Stands vom
22. Juli 2026. Dieses Dokument beschreibt den Ist-Zustand, nicht die Roadmap.
Die verbindlichen technischen Detailverträge bleiben die am Ende verlinkten
Contract-Dokumente.

Die Oberfläche ist in V1 vollständig englisch. Deshalb stehen die sichtbaren
englischen Namen in diesem Dokument in Klammern. Eine deutsche Lokalisierung ist
aktuell nicht implementiert.

## Die Kurzfassung

MyLifeGraph soll explizite Angaben und beobachtbare Handlungen in einen klaren,
ehrlichen Tagesüberblick und vorsichtige regelbasierte Unterstützung übersetzen:

1. **Setup** beschreibt längerfristigen Kontext: Ziele, Präferenzen, Routinen
   und feste Wochenblöcke.
2. **Morning und Evening check-ins** beschreiben den aktuellen Zustand.
3. **Tasks, Habit outcomes und Focus sessions** zeigen, was tatsächlich getan
   wurde.
4. Ein **regelbasierter Daily State** ordnet diese Signale als `push`, `steady`,
   `recover` oder `plan` ein.
5. **Today Overview** zeigt den Both-capture-Streak, exakte Tagesfortschritte,
   Zeitblöcke, Tasks und Habits, ohne eine Entscheidung für den Nutzer zu
   behaupten.
6. Der **Planner** lässt Tasks, Habits, Preparation Plans und feste Termine
   bewusst als Vorschau planen und reserviert Zeit erst nach Bestätigung.
7. Ein persistiertes **Daily Briefing** kann intern weiterhin eine primäre und
   höchstens zwei unterstützende Aktionen ranken. Es dient Scheduler, Reminder,
   Coach-Kontext und Feedback-Historie, ist aber nicht mehr die primäre
   Today-Darstellung.
8. **Feedback, Insights und Weekly Review** machen Reaktionen und Entwicklungen
   sichtbar. Nur das Feedback verändert derzeit automatisch und begrenzt die
   spätere Rangfolge ähnlicher Vorschläge.
9. Der **Coach** kann diesen Zustand erklären und eine unverbindliche Anregung
   formulieren. Er darf keine Produktdaten ändern.

Der Großteil des Produkts ist bewusst regelbasiert und verwendet **kein LLM**.
Der Coach ist die einzige Oberfläche, die in einer explizit aktivierten lokalen
Entwicklungsumgebung ein echtes Sprachmodell aufrufen kann.

## Das beabsichtigte Produktmodell

```text
Längerfristiger Kontext
Profile + Setup + Goals + Habits + feste Commitments
                         │
                         ▼
Aktuelle Signale
Morning/Evening + Tasks + Habit outcomes + Focus sessions
                         │
                         ▼
Regelbasierter Zustand
Snapshot → Daily State → Modus, Qualität, Risiken, Begründungen
                         │
           ┌─────────────┴─────────────┐
           ▼                           ▼
Today Overview                  interne Rangfolge
Streak + Progress +             Recommendations → Daily Briefing
Agenda + Tasks + Habits         → Reminder/Coach-Kontext/Feedback
           │                           │
           ▼                           ▼
explizite Ausführung            spätere Rangfolge
Task/Habit/Focus                bleibt begrenzt beeinflussbar
           └─────────────┬─────────────┘
                         ▼
Review: Insights + Weekly Review

Coach: liest einen begrenzten Ausschnitt dieses Modells, erklärt ihn,
       besitzt aber weder Berechnungs- noch Änderungsrechte.

Calendar import: bleibt ein separater, read-only Datenzweig und darf nur auf
ausdrücklichen Wunsch im Planner beziehungsweise bei Preparation als Busy-Time-
Quelle verwendet werden. Es gibt keinen Live-Sync und keinen Calendar-Write.
```

## Welche Betriebsarten gibt es?

| Modus | Speicherung | Verfügbare Funktionen | Wichtige Grenze |
| --- | --- | --- | --- |
| Local guest/demo | Check-ins und ausgewählte Beispieldaten lokal auf dem Gerät | Grundnavigation, Morning/Evening, ehrliche Demo- oder Leerzustände | Keine synchronisierten Tasks, Habits, Focus sessions, Planner-Pläne, Reviews, Kalenderimporte oder Preparation Plans |
| Synced account | Supabase Auth und die eigenen, per RLS geschützten Supabase-Daten; abgeleitete Workflows über FastAPI | Der vollständige aktuelle Produktumfang | Fehler werden angezeigt und niemals durch personalisiert wirkende Mock-Daten ersetzt |
| Coach mit `fake` provider | Wie ein synced account, aber Coach-Antworten sind feste Testantworten | Coach-Vertrag, History, Memories, Limits und UI lassen sich testen | Das ist kein aktives LLM |
| Coach mit `local_codex_oauth` | Synced account plus explizit aktivierter Codex-CLI-Zugang des lokalen Entwicklers | Ein echter, begrenzter Modellaufruf | Nur lokale Entwicklung; nicht in Release/Produktion verfügbar |

Ein neu registrierter echter Account erhält seine Auth-Identität und sein
kanonisches Profil in Supabase. Danach erzwingt die App das Setup. Erst dessen
explizite Bestätigung materialisiert die gewählten Setup-Daten. Leere optionale
Felder erzeugen keine Goals, Habits oder Schedule Items. Ein echter neuer
Account erhält keine Daten des `student`-Testusers.

## Navigation: Was befindet sich wo?

Die Hauptnavigation hat derzeit genau fünf Ziele.

| Sichtbarer Bereich | Aufgabe | Was dort aktuell zu sehen oder zu tun ist |
| --- | --- | --- |
| **Today** | Den gespeicherten Tag überblicken und Tagesaktionen ausführen | Check-in-Streak, transparenter Fortschritt, vertikale Setup/Task/Habit/Fixed commitment/Preparation/Calendar/Focus-Agenda, heutige Tasks und Habits sowie eingeklappte unterstützende Details |
| **Insights** | Entwicklungen untersuchen | Eine vorsichtige Beobachtung, Datenqualität, 7/14/30/90-Tage-Korrelationen, Trends, Matrix und gespeicherte Insight-Notizen |
| **Quick actions** | Tagesdaten erfassen oder eine Aktivität ausführen | Evening check-in, Morning check-in, Habit completion und Focus |
| **Planner** | Ziele und feste Zeiten bewusst planen | Task, Habit, Exam, Assignment und Fixed commitment anlegen; Vorschauen bestätigen; sieben Tage, Konflikte, Unscheduled und laufende Preparation verwalten |
| **Settings** | Längerfristige Einstellungen, Inbox und Kontoverwaltung | Inbox, Profil/Zeitzone, Setup, Preparation Budget, In-app reminders, Calendar import, optionaler Coach, Export, Löschung, Theme und Sign-out |

Weitere Screens sind Unterseiten und keine eigenständigen Hauptbereiche:

- `Weekly review` gehört logisch zu `Today`.
- `Today habits` und `Focus` gehören zur Ausführung unter `Quick actions`.
- `Habit management` und `Preparation plans` gehören logisch zu `Planner`;
  die bisherigen Routen bleiben kompatibel.
- `Inbox` gehört zu `Settings`; `/alerts` bleibt ein kompatibler Link.
- `Calendar import`, `In-app reminders` und der Entwicklungs-`Coach` gehören
  derzeit zu `Settings`.
- Es gibt aktuell **keine** separate Goals-, Tasks-, Schedule- oder Memories-
  Hauptseite.

## Welche Dashboards gibt es tatsächlich?

### 1. Today: Tagesüberblick und Ausführung

`Today` ist das zentrale Dashboard. Es behauptet nicht mehr, eine Entscheidung
für den Nutzer getroffen zu haben. Die sichtbare Reihenfolge ist:

1. **Check-in streak**
   - ein Tag zählt nur mit gültigem Morning und Evening Check-in;
   - beide dürfen jederzeit und in beliebiger Reihenfolge gespeichert werden;
   - ein noch unvollständiger heutiger Tag beendet die bis gestern vollständige
     Serie nicht.
2. **Today's progress**
   - dynamisches `x/y completed` statt einer festen Schrittzahl;
   - zählt die zwei Check-ins, heutige Tasks, heutige Habits und bestätigte
     Preparation Blocks dieses Tages;
   - Calendar, Setup Commitments und tatsächliche Focus Sessions sind Kontext,
     keine automatisch zu erledigenden Schritte;
   - wenn eine gezählte Quelle ausfällt, steht dort ehrlich `Progress
     unavailable`.
3. **Today at a glance**
   - vertikale, chronologische Tagesagenda;
   - verschieden bezeichnete und gefärbte `Setup commitment`, `Preparation`,
     `Calendar` und `Focus`-Einträge;
   - ganztägige Events zuerst, überlappende Einträge separat;
   - Preparation kann den Plan öffnen oder Focus auf dem Managed Task starten.
4. **Today's tasks**
   - überfällige/heute fällige, alle laufenden und heute erledigte manuelle
     Tasks;
   - inline erledigen, wiederherstellen, bearbeiten und Focus starten;
   - `Show all tasks` enthält zusätzlich zukünftige, undatierte, erledigte,
     abgebrochene und planner-managed Tasks.
5. **Today's habits**
   - tägliche, am Wochentag geplante und noch offene Weekly-Target Habits;
   - explizit `Complete`, `Skip` oder `Undo outcome` über Habit V1.
6. **More**, zunächst geschlossen und lazy geladen
   - Preparation workload und Weekly review;
   - gespeicherte Check-in-Signale;
   - regelbasierte Recommendations und Feedback-Historie;
   - vollständige Woche.

`Today` zeigt nur wirklich gespeicherte Werte. Fehlende Schlaf-, Stimmungs-,
Energie-, Stress-, Bewegungs-, Screen-Time- oder Focus-Daten werden weder als
Null noch als erfundener Score dargestellt. Es gibt derzeit bewusst keinen
allgemeinen Readiness-, Wellness- oder Life-Score für echte Accounts.

Ein normaler Aufruf von `Today` ist read-only:
`GET /v1/today/overview-v2` erzeugt
weder Briefing noch Recommendation und verändert keinen Plan. Das persistierte
Daily Briefing bleibt für Scheduler, Reminder, Coach-Kontext und historische
Feedback-Auswertung erhalten, ist aber keine sichtbare angeblich von der App
getroffene Tagesentscheidung mehr. Die exakten Regeln stehen in
`docs/today-overview-v1-contract.md`.

### 2. Insights: Muster- und Korrelationsdashboard

`Insights` beginnt mit genau einer vorsichtigen, lokal berechneten Beobachtung.
Sie zeigt:

- Aussage und kurze Erklärung;
- `Insufficient`, `Emerging` oder `Stronger` confidence;
- Evidenzfenster und Datenqualität;
- optional ein kleines siebentägiges Experiment, das keine Daten oder Pläne
  automatisch verändert.

Der ausklappbare Bereich `Advanced correlation exploration` enthält:

- Zeitfenster von 7, 14, 30 oder 90 Tagen;
- wählbare Signalpaare;
- normalisierte Trendlinien;
- Pearson-Korrelation und gemeinsame Beobachtungszahl;
- stärkste verfügbare Muster;
- eine Korrelationsmatrix;
- unter `Discovered patterns` gespeicherte `ai_insights`-Notizen.

Verwendbare Metriken erscheinen nur, wenn echte Werte vorhanden sind:

| Metrik | Datenquelle |
| --- | --- |
| Sleep, mood, energy, stress | gespeicherte `daily_logs` aus Morning/Evening |
| Screen time, activity, steps | nur vorhandene ältere oder importierte `daily_logs`; die aktuellen Check-ins fragen diese Werte nicht ab |
| Focus minutes | tatsächlich abgeschlossene `focus_sessions` |
| Planned minutes | Task-Schätzungen, Dauer der wöchentlichen Schedule Items und aktive bestätigte Preparation Blocks |
| Habit completion rate | explizite `habit_logs`, also completed/skipped/offen statt angenommener Erfüllung |

Eine Korrelation benötigt mindestens fünf gemeinsame Tage. Die prominente
Beobachtung benötigt mindestens 14 gemeinsame Tage und eine ausreichende
Effektstärke. Das Ergebnis ist eine **Assoziation, keine Ursache** und verändert
weder Briefing noch Plan.

Der technisch benannte Datentyp `ai_insights` ist aktuell kein Beweis für einen
laufenden AI-Insight-Generator. Beim `student`-Testuser sind solche Zeilen
gezielt als Seed-Daten vorhanden. Für einen neuen echten Account kann der
Bereich leer sein. Das `Skillset profile` wird nur in ausdrücklich lokalem
Demo-Modus als Beispiel gezeigt und bei echten Accounts ausgeblendet, weil
aktuell kein belastbarer Produzent dafür existiert.

### Review- und Planungsflächen mit Dashboard-Charakter

Diese Screens visualisieren mehrere Datenarten, sind aber keine Haupt-
Dashboards:

| Screen | Sichtbare Daten | Wirkung |
| --- | --- | --- |
| **Planner** | Add new, Needs attention, sieben lokale Tage, aktive Preparation, Unscheduled und Historie | Vorschläge reservieren nichts; nur `Confirm plan` aktiviert Task-/Habit-Zeiten, feste Termine bleiben autoritativ und Konflikte verschieben nichts automatisch |
| **Weekly review** | letzte abgeschlossene ISO-Woche, completed/carried/overdue Tasks, completed/skipped/missed/unknown Habit-Möglichkeiten, Focus-Sessions und Minuten, Recovery-Tage, Feedback-Anzahl, Datenqualität und Freshness | erzeugt auf Wunsch höchstens zwei regelbasierte Vorschläge; nur eine bestätigte Änderung an einem manuellen Habit darf direkt angewendet werden |
| **Preparation plans** | aktive, staged, abgeschlossene oder abgebrochene Pläne; Schätzung, Vorleistung, Deadline, Revisionen, datierte Blöcke, bestätigte Reservierungen, gemessener Focus-Fortschritt und 7-Tage-Auslastung | Vorschlag bleibt Preview; erst Bestätigung aktiviert Blöcke und den verwalteten Task |
| **Inbox** | Anzahl unread/read/actionable innerhalb der höchstens 30 geladenen Einträge sowie einzelne Hinweise | Lifecycle-Änderungen und sichere interne Navigation; kein Analyse-Dashboard |

## Featurekatalog: Funktion, Eingaben und Ergebnis

| Feature | Wie es funktioniert | Verwendete Daten | Geschriebene Daten / LLM |
| --- | --- | --- | --- |
| **Auth und Account** | E-Mail/Passwort, Recovery und optional konfiguriertes Google OAuth über Supabase Auth | Auth-Identität und Profil | `profiles`; kein LLM |
| **Setup** | erforderliche Auswahlen plus optionale Details; wöchentliche Termine unterstützen optionale Semestergrenzen und Duplizieren auf weitere Wochentage; atomar, revisioniert und retry-sicher | Fokusbereiche, Tagesstruktur, Energiefenster, Coaching-Stil, Reminder-Präferenz, optionale Ziele/Routinen/Commitments; kein Kalenderzwang | `intake_responses`, `goals`, `habits`, `schedule_items`, `memory_entries`, `notification_preferences`, Onboarding-Snapshot; kein LLM |
| **Morning check-in** | kurze Eingabe für Schlafdauer, separat geschätzte Schlafqualität (1–10), aktuelle Energie und Tagesform | explizite Auswahl des Nutzers; Qualität wird nicht aus der Dauer abgeleitet | Teil des lokalen Tages in `daily_logs`; Qualität bleibt strukturierte Capture-Metadaten und wird auf bestehende Morning-Events gespiegelt, kein fünftes Event und kein LLM |
| **Evening check-in** | zwei kurze Schritte für Mood, Energie, Stress, eine Primary Friction (inklusive `No major friction`), bis zu zwei optionale `Also present`-Frictions und optionale Reflexion | explizite Auswahl/Text; bei Stress 5–10 zusätzlich Quelle und Kontrollierbarkeit; nur die Primary Friction beeinflusst den Daily Mode | anderer Teil desselben `daily_logs`-Tages, dazu `behavioral_events`; strukturierte Frictions können in den begrenzten Coach-Kontext gelangen, freie Reflexions-/Blockertexte nicht |
| **Daily State / Snapshot** | strikte Regeln betrachten einen festen Sieben-Tage-Kontext und klassifizieren Zustand, Risiken und Gründe; sehr schlechte Schlafqualität kann trotz ausreichender Dauer Recovery auslösen, mäßig schlechte Qualität verhindert Push; Action-Facts werden additiv zusammengefasst, verändern aber den Daily-State-Klassifikator nicht | validierte Check-in-Signale für Daily State; zusätzlich Tasks, Goals, Habits, Outcomes, Focus, Schedule und Memories für die übrige Snapshot-Zusammenfassung | `user_state_snapshots`; kein LLM und kein gelernter persönlicher Basiswert |
| **Recommendations** | einzelne regelbasierte Kandidaten werden explizit erzeugt/aktualisiert | Snapshot, Setup, offene Tasks, aktive Goals/Habits und verfügbare Feedback-Signale | `recommendations`; LLM-Wording ist im aktuellen Produktpfad deaktiviert |
| **Daily Briefing** | wählt aus zulässigen Kandidaten eine primäre und bis zu zwei unterstützende Aktionen | aktueller Snapshot, Recommendations, Actions, Dringlichkeit, Recovery-Schutz und passendes Feedback | `daily_briefings`; regelbasiert, nicht AI-geschrieben |
| **Tasks** | endliche Aktionen mit Status und optionaler Deadline/Schätzung | direkte Nutzereingabe oder ein vom bestätigten Preparation Plan verwalteter Task | `tasks`; kein LLM |
| **Habits** | wiederkehrende Ziele mit daily-, weekday- oder weekly-target-Cadence | Definition plus explizites completed/skipped/undo pro lokalem Datum | `habits`, `habit_logs`; kein LLM |
| **Focus** | echter Timer, optional mit genau einem Task oder Habit verknüpft | gewählte Dauer und gemessene verstrichene Zeit | `focus_sessions`; kein LLM |
| **Planner** | deterministische Vorschau aus expliziter Dauer/Deadline/Session beziehungsweise Habit-Dauer/Cadence; freie Zeit berücksichtigt bestätigte Belegung; bei fehlender sichtbarer Verfügbarkeitsquelle warnt die UI vor automatischer Planung | Task/Habit-Eingaben, primär Setup/manual commitments, Planner/Preparation reservations, optional consented aktueller Import | Planner preferences/plans/revisions/blocks/slots/commitments; erst Confirm erstellt/ändert Ziel und Reservierungen; kein LLM, Calendar-Write oder Auto-Replan |
| **Decision feedback** | Reaktion auf eine konkrete Briefing-Aktion | Aktion, Kontext und Feedback-Typ | append-only `decision_feedback`; beeinflusst begrenzt spätere Rankings, führt die Aktion aber nicht aus |
| **Weekly review** | deterministische Fakten für die letzte abgeschlossene lokale ISO-Woche | Tasks, Habit-Möglichkeiten/Outcomes, Focus, Daily State und Feedback | `weekly_reviews`; kein LLM; Änderungen nur nach Bestätigung |
| **Calendar import** | ein bewusst gewähltes UTF-8-`.ics`-File wird begrenzt und read-only importiert | explizite Einwilligung und die gewählte Datei | `calendar_connections`, `calendar_imports`, `calendar_events`; nie an das LLM und nie in `schedule_items` kopiert |
| **Preparation plans** | Nutzer schätzt Gesamtaufwand und Vorleistung; Regeln teilen Restzeit in überprüfbare Datumsblöcke | Deadline, eigene Schätzung, bevorzugte Blockgröße, Tageslimit, Puffer, Setup-Commitments und optional aktuelle importierte Busy Times | `deadline_plans`, Revisionen, Blocks und nach Bestätigung ein verwalteter `task`; kein LLM |
| **Insights** | Flutter berechnet Korrelationen und eine vorsichtige Beobachtung | vorhandene Tages-, Task-, Schedule-, Plan-, Habit- und Focus-Daten | normalerweise nur Anzeige; kein LLM und keine automatische Produktänderung |
| **Inbox lifecycle** | fällige gespeicherte Hinweise lesen, unread/read setzen oder dismissen | owner-scoped `notifications` | Lifecycle-Zeitstempel plus Retry-Ledger; kein LLM |
| **In-app reminders** | nach separater Einwilligung werden höchstens zwei Kandidaten mit fixer Copy regelbasiert erzeugt und bei offener App höchstens einmal als Banner gezeigt | aktueller Recovery-/Briefing-Zustand oder aktuelles Weekly Review, Kategorien, Quiet Hours und Tageslimit | `notification_preferences`, `notifications` und Delivery-Provenance; kein Push, kein Background und kein LLM |
| **Coach** | bewusste Nachricht, begrenzter Context, Safety-Prüfung und validierte Antwort | ausgewählte aktuelle Produktfakten und Memories | `coach_requests`, `coach_messages`, Usage und Selection; nur dieser Pfad kann lokal ein LLM verwenden |
| **Account controls** | Zeitzone, JSON-Export, Passwort-Recovery und permanente Löschung | Profil und owner-scoped Produktdaten | kontrollierte FastAPI/RPC-Operationen; kein LLM |

## Die zentralen Begriffe

### Vergleich auf einen Blick

| Objekt | Kernfrage | Zeitmodell | Wird „erledigt“? | Aktueller Verwaltungsort |
| --- | --- | --- | --- | --- |
| **Goal** | Wohin will ich? | längerfristig, optional mit Zieltag | nicht als heutige Aktion | Setup; keine allgemeine Goals-Seite |
| **Task** | Was kann ich einmalig abschließen? | optionaler Deadline-Zeitpunkt | ja | Today |
| **Habit** | Was will ich regelmäßig wiederholen? | täglich, gewählte Wochentage oder Wochenziel | Outcome pro lokalem Tag | Quick actions / Setup bei Setup-owned Habits |
| **Schedule Item** | Wann bin ich jede Woche fest gebunden? | wiederkehrender Wochentag mit Start/Ende | nein | Setup; Ansicht in Today |
| **Calendar Event** | Was stand in der importierten Datei? | konkreter importierter Zeitraum | nein, read-only | Settings → Calendar import |
| **Preparation Block** | Wann reserviere ich einen Teil meiner Prüfungsvorbereitung? | konkretes lokales Datum im bestätigten Plan | nicht einzeln; Fortschritt kommt aus Focus | Preparation plans; Ansicht auch in Today |
| **Focus Session** | Woran arbeite ich jetzt tatsächlich? | gemessener Timerblock | completed oder abandoned | Quick actions → Focus |

### Goal

Ein **Goal** beschreibt eine Richtung oder ein gewünschtes Ergebnis, nicht die
nächste ausführbare Handlung.

Beispiel: `Plan exams earlier`.

- typische Frage: **Wohin will ich mich entwickeln?**
- Felder: Titel, optionale Beschreibung, Status, optional Fortschritt und
  Zieltermin;
- Setup-Status: `active`, `paused` oder `archived`; die kanonische Tabelle
  erlaubt zusätzlich `completed` für andere Quellen, hat dafür aber noch keine
  allgemeine UI;
- Verwendung: Kontext für Snapshots, Recommendations, Briefings und Coach;
- aktuelle UI: Setup verwaltet bis zu drei Setup-Ziele. Es gibt keine allgemeine
  Goals-Seite für frei angelegte Goals.

Ein Goal wird nicht direkt „heute erledigt“. Ein Task oder Habit kann intern auf
ein Goal verweisen, aber diese Beziehung wird in der Oberfläche noch nicht als
klares Goal-Plan-System dargestellt.

### Task

Ein **Task** ist eine einmalige, konkret abschließbare Aktion.

Beispiel: `Finish math problem set` mit 60 Minuten Schätzung und Deadline.

- typische Frage: **Was kann ich abschließen?**
- Felder: Titel, Beschreibung, Priorität (`low` bis `critical`), optionale
  Deadline und Schätzung von 5–480 Minuten;
- Status: `todo`, `in_progress`, `done`, `cancelled` oder historisch
  `archived`;
- Aktionen: erstellen, bearbeiten, erledigen, verschieben, abbrechen,
  wiederherstellen und als Focus-Ziel öffnen;
- aktuelle UI: Task-Verwaltung befindet sich direkt auf `Today`.

Ein von einem Preparation Plan erzeugter Task ist **planner-owned**. Er bleibt
als Focus-Ziel sichtbar, darf aber nicht über die normalen Task-Aktionen
bearbeitet oder beendet werden. Dafür muss der zugehörige Plan geöffnet werden.

### Routine candidate und Habit

Eine im Setup nur benannte **Routine candidate** ist zunächst eine Idee. Solange
Cadence und Aktivierung nicht ausdrücklich bestätigt sind, wird sie nicht
getrackt und erzeugt keine tägliche Pflicht.

Ein **Habit** ist dagegen ein ausführbares, wiederkehrendes Verhalten:

- `daily`: jeden lokalen Tag;
- `weekdays`: nur an explizit ausgewählten Wochentagen;
- `weekly_target`: ein Ziel von 1–7 Erfüllungen pro ISO-Woche.

Für einen fälligen Tag existiert genau einer dieser Zustände:

- `completed`: explizit erledigt;
- `skipped`: bewusst ausgelassen;
- offen: noch keine Zeile;
- `missed`: ein vergangener fälliger Tag blieb offen.

`skipped`, offen und `missed` werden nicht als Erfolg umgedeutet. Ein Outcome
kann für denselben Tag rückgängig gemacht werden. Setup-owned Habits lassen sich
im Tagesflow ausführen, ihre Definition wird aber nur unter `Settings → Setup
and commitments` geändert. Manuelle Habits werden unter `Habit management`
verwaltet.

### Schedule Item / Fixed Commitment

Ein **Schedule Item** ist ein wiederkehrender fester Wochenblock aus dem Setup.

Beispiel: `Math`, Montag 08:15–09:45, `Room 204`.

- typische Frage: **Welche Zeit ist jede Woche bereits gebunden?**
- Felder: Titel, ISO-Wochentag, Start, Ende, optional Ort/Farbe/Notiz;
- kein `completed`-Status und kein Timer;
- sichtbar in der vollständigen Woche auf `Today`;
- fließt in geplante Minuten und die regelbasierte Kapazitätsbetrachtung ein;
- wird derzeit im Setup und nicht auf einer eigenen Schedule-Seite verwaltet.

Ein Schedule Item ist weder ein importiertes Calendar Event noch ein datierter
Preparation Block.

### Calendar Event

Ein **Calendar Event** ist eine read-only Kopie eines Events aus genau einer
bewusst importierten `.ics`-Datei.

Beispiel: ein importierter Abgabetermin `Research methods essay due`.

- keine Live-Verbindung, kein OAuth-Token und kein Hintergrund-Sync;
- ein erneuter manueller Import gleicht stabile Event-Identitäten ab;
- Disconnect stoppt weitere Imports, lässt die lokale Kopie aber bestehen;
- `Delete local imported data` entfernt nur die lokale Kopie und Historie;
- kann nach ausdrücklicher Auswahl eine Deadline oder Busy-Time-Quelle für
  einen Preparation Plan sein;
- wird nie zu einem `schedule_item` und nie an den Coach gesendet.

### Preparation Plan, Revision und Block

Ein **Preparation Plan** verteilt einen vom Nutzer selbst geschätzten Lern- oder
Arbeitsaufwand bis zu einer Prüfung oder Abgabe.

Beispiel: `Calculus final exam`, 12 Stunden Gesamtaufwand, 2 Stunden bereits
erledigt, bevorzugte 50-Minuten-Blöcke.

- Der Nutzer liefert Schätzung, Vorleistung, Deadline, Blockgröße,
  planbezogenes Tagesmaximum und Puffer.
- Optional kann eine bewusst ausgewählte Calendar-Deadline und/oder aktuelle
  importierte Busy Time verwendet werden.
- Die Regelengine erzeugt eine **Revision**: einen unveränderlichen,
  überprüfbaren Vorschlag.
- Vor der Bestätigung ist die Revision nur eine **Preview**.
- Erst `Confirm reservations` aktiviert die Revision, ihre datierten
  **Preparation Blocks** und genau einen stabilen verwalteten Task.
- Replanning erzeugt wieder nur eine staged Revision. Die bisherigen Blöcke
  bleiben aktiv, bis die neue Revision bestätigt wird.
- Nur nach Aktivierung abgeschlossene Focus-Sessions am verwalteten Task zählen
  als gemessener Fortschritt. Sie erledigen Plan, Block oder Task nie
  automatisch.

Ein **Preparation Block** ist also eine datierte Reservierung eines Plans. Ein
**Schedule Item** ist dagegen eine wiederkehrende wöchentliche Verpflichtung.

### Focus Session

Eine **Focus Session** misst einen tatsächlichen Ausführungsblock:

- geplante Dauer 5–240 Minuten;
- optional genau ein offener Task oder ein aktives Habit als Ziel;
- höchstens eine aktive Session pro Account;
- Abschluss als `completed` oder `abandoned`;
- `actual_minutes` entstehen aus verstrichener Zeit, nicht aus der Planung;
- Abschluss verändert den verknüpften Task oder das Habit nicht automatisch.

### Check-in, Daily Log und Behavioral Event

Morning und Evening werden pro lokalem Datum in **einem** `daily_logs`-Datensatz
zusammengeführt. Das erneute Speichern eines Teils ersetzt nicht den anderen.

- Morning: Schlafdauer, aktuelle Energie, `normal`/`constrained`/`flexible` day
  shape.
- Evening: Mood, Energie, Stress, Hauptfriktion; bei höherem Stress zusätzlich
  Quelle und Kontrollierbarkeit; optionale Reflexion und Morgenpriorität.

Aus den strukturierten numerischen Angaben werden bis zu vier stabile
**Behavioral Events** für Mood, Energie, Stress und Schlaf abgeleitet. Sie sind
keine eigene Nutzerfunktion, sondern eine normalisierte Quelle für den
Snapshot-Aggregator. Freitext bleibt Check-in-Kontext, wird weder zu Memory,
Task oder Notification befördert noch in Daily-State-Snapshots kopiert.

### Snapshot und Daily State

Ein **User State Snapshot** ist eine kompakte, deterministisch abgeleitete Sicht
auf vorhandene Fakten. Der tägliche Snapshot enthält den **Daily State**:

- Qualität: `missing`, `partial`, `current`, `stale`;
- Modus: `push`, `steady`, `recover`, `plan`;
- maschinenlesbare Risiken und verständliche Gründe;
- konkrete Feldevidenz und Herkunft.

Die Regeln verwenden einen festen Sieben-Tage-Zustandskontext. Sie behaupten
keinen persönlich gelernten Basiswert und stellen keine medizinische Diagnose.

### Recommendation und Daily Briefing

Eine **Recommendation** ist ein einzelner Vorschlagskandidat mit Grund,
Kategorie, Priorität, Confidence und optionaler ausführbarer Zielbeschreibung.
Mehrere Recommendations können gleichzeitig existieren.

Ein **Daily Briefing** ist ein persistiertes internes Rangfolge-Artefakt über
diese und weitere zulässige Actions:

- genau eine primäre Aktion;
- höchstens zwei unterstützende Aktionen;
- Daily Mode, Kapazität, Freshness und Evidenz;
- striktes ausführbares Ziel, falls die Aktion wirklich ausgeführt werden kann.

Die Recommendation sagt also „das könnte relevant sein“, das Briefing speichert
„dies wurde unter den damaligen Regeln am höchsten gerankt“. Today selbst
behauptet daraus keine Entscheidung für den Nutzer; Recommendations sind dort
nur unterstützend unter `More` sichtbar.

### Decision Feedback

**Decision Feedback** ist eine historische Reaktion auf eine konkrete
Briefing-Aktion. Es führt die Aktion nicht aus und ändert weder Task noch Habit.

- `done`: laut Nutzer erledigt;
- `later`: später passend;
- `not_helpful`: nicht hilfreich;
- `too_much`: zu viel für den Kontext;
- `does_not_fit`: passt grundsätzlich nicht.

Passendes Feedback der letzten 28 Tage wird zeitlich abgewertet, gedeckelt und
additiv in die spätere Rangfolge ähnlicher Kontexte einbezogen. Recovery- und
Dringlichkeitsschutz können nicht dadurch ausgehebelt werden.

### Memory

Eine **Memory Entry** ist eine dauerhafte, überprüfbare Notiz, etwa zu Goal,
Habit, Pattern oder wiederkehrendem Problem. Setup kann solche Notizen aus
expliziten Angaben materialisieren. Der Coach darf höchstens acht geeignete
Memories verwenden, und auch nur nach separater Auswahl im Coach-Screen.

Aktuell gilt:

- keine automatische Extraktion aus Gesprächen;
- keine automatische Änderung von Stärke oder Evidenz;
- preference-Memories sind für Coach V1 ausgeschlossen;
- Setup-owned Inhalt wird in Setup geändert;
- es gibt noch keine eigenständige allgemeine Memory-Verwaltung.

### Notification

Eine **Notification** ist zunächst nur ein gespeicherter Inbox-Eintrag. Das ist
kein Beweis, dass eine System- oder Push-Benachrichtigung zugestellt wurde.

- `unread` und `read` sind reversible Zustände;
- `dismiss` behält einen Tombstone, entfernt den Eintrag aber aus normalen
  Inbox-Reads;
- nur erlaubte interne Routen erhalten einen `Open`-Button;
- in-app delivery benötigt eine separate, ausdrückliche Einwilligung;
- ein Banner kann nur erscheinen, während MyLifeGraph geöffnet ist.

## Wie „lernt“ die App derzeit wirklich?

Das Wort „lernen“ bezeichnet aktuell mehrere unterschiedliche Mechanismen. Nur
einer davon passt zukünftige Entscheidungen automatisch an.

### 1. Explizite Personalisierung aus Setup

Die App kennt Fokusbereiche, Day Shape, bestes Energiefenster, Coaching-Stil,
Goals, bestätigte Habits und feste Commitments, weil der Nutzer sie angegeben
hat. Das ist gespeicherter Kontext, kein maschinelles Lernen.

### 2. Regelbasierte Zustandsableitung

Daily State, Briefings, Preparation Plans, Weekly Reviews und Reminders werden
mit transparenten, versionierten Regeln berechnet. Gleiche Eingaben erzeugen
dieselben Ergebnisse. Ein LLM entscheidet diese Ergebnisse nicht.

### 3. Verhaltensfakten

Completed/cancelled Tasks, completed/skipped Habits und completed/abandoned
Focus-Sessions liefern belastbarere Fakten als eine weitere Selbsteinschätzung.
Sie fließen in Snapshots, Wochenfakten und Insights ein, ändern aber nicht
heimlich Definitionen oder Ziele.

### 4. Begrenztes adaptives Ranking durch Feedback

Das ist der aktuell echte automatische Anpassungsmechanismus:

- Ein Nutzer bewertet eine Briefing-Aktion.
- Das Event bleibt als getrennte Evidenz erhalten.
- Beim nächsten passenden Kontext berücksichtigt das Ranking maximal 28 Tage
  alte, zeitlich abgewertete und gedeckelte Effekte.
- Sicherheits-, Recovery- und Dringlichkeitsregeln behalten Vorrang.

Die App „merkt“ sich damit beispielsweise, dass eine bestimmte Art Vorschlag in
einem `recover`-Kontext wiederholt `too_much` war. Sie trainiert dafür kein
Modell.

### 5. Deskriptive Insights

Insights berechnet Korrelationen neu aus dem gewählten Zeitfenster. Das kann ein
Muster sichtbar machen, verändert aber kein Ranking und beweist keine Ursache.

### 6. Wöchentliche, bestätigungspflichtige Anpassung

Weekly Review kann aus der abgeschlossenen Woche höchstens zwei Änderungen
vorschlagen. Nur eine genau geprüfte Änderung an einem manuellen Habit darf nach
Bestätigung direkt angewendet werden. Alles andere bleibt Information, Preview
oder öffnet Setup.

### Was die App ausdrücklich noch nicht tut

- kein Online-Training oder Fine-tuning eines persönlichen Modells;
- kein persönlicher gelernter Baseline- oder Readiness-Score;
- keine Embeddings und keine Vector Search;
- keine automatische Memory-Extraktion aus Check-ins oder Coach-Chats;
- keine autonomen Agents oder model-gesteuerten Tools;
- keine versteckten Änderungen an Goals, Tasks, Habits, Schedule oder Plänen;
- keine automatische Kalender-Synchronisation;
- keine kausalen Gesundheits- oder Leistungsbehauptungen.

## Was kann der LLM Coach aktuell?

### Sichtbarkeit und Provider

Der Screen heißt bewusst `Coach preview`.

- Er ist in Release-Builds und bei `APP_ENV=production` immer verborgen.
- Mit `provider=fake` zeigt er feste Testantworten. Die UI sagt dann ausdrücklich
  `Uses fixed test responses. This is not a live assistant.`
- Mit explizit aktiviertem `local_codex_oauth` kann FastAPI lokal die bereits
  angemeldete Codex CLI desselben Linux/WSL-Nutzers aufrufen. Das bevorzugte
  konfigurierte Modell ist `gpt-5.5`, sofern CLI und Account diese ID anbieten.
- Es gibt keinen stillen Fallback und derzeit keinen deploybaren
  Produktionsprovider.

### Was er lesen darf

Für eine bewusst gesendete Nachricht baut FastAPI ein deterministisches Paket
von höchstens 32 KiB. Es kann enthalten:

- lokales Datum, Profil-Zeitzone und strukturierten Coaching-Stil;
- aktuellen Daily-State-Snapshot;
- aktuelles persistiertes Daily Briefing inklusive Freshness;
- begrenzte aktive Goals, Tasks, Habits und aktuelle/letzte Focus-Sessions;
- das letzte abgeschlossene Weekly Review mit sichtbarer Freshness;
- höchstens acht ausdrücklich ausgewählte Memories;
- höchstens sechs abgeschlossene frühere Coach-Turns, nochmals nach Zeichen
  begrenzt.

Die Antwort zeigt unter `Data used`, wie viele Einträge pro Quelle verfügbar,
einbezogen oder ausgelassen wurden und wie frisch die Quelle war.

### Was er nicht lesen darf

- E-Mail, Tokens, Rollen, Service Keys oder fremde Nutzerzeilen;
- arbitrary SQL, Datenbankzugang, Dateien, Web, Apps, Plugins oder Tools;
- importierte Calendar-Titel, Beschreibungen, Orte, Teilnehmer oder `.ics`-
  Rohinhalt;
- Check-in-Notizen, Intake-Freitext, Notification-Texte oder andere versteckte
  Freitexte;
- nicht ausgewählte Memories oder unbegrenzte Historie.

### Was er ausgeben darf

- eine Antwort von höchstens 4.000 Zeichen;
- explizite Unsicherheit `low`, `medium` oder `high` samt Grund;
- Safety-Klassifikation;
- Herkunft, Provider- und Modellangabe;
- höchstens eine **review-only staged suggestion**.

### Was er nicht tun darf

Der Coach kann keine Goals, Tasks, Habits, Schedule Items, Calendar Events,
Briefings, Reviews, Memories oder Preparation Plans anlegen, ändern, erledigen
oder löschen. Er kann auch nicht selbständig im Hintergrund laufen. Daily State
und Daily Briefing bleiben begrenzte Berechnungs- und Rangfolgequellen; der
Coach erklärt und reflektiert sie nur und entscheidet nichts für den Nutzer.

Deterministische Safety-Prüfungen laufen vor und nach dem Provider. Ein akuter
Risikofall kann den Provider komplett umgehen. Fehlende oder veraltete Daten
erzwingen sichtbar höhere Unsicherheit.

### Limits und Speicherung

- Nachricht: höchstens 2.000 Unicode-Codepoints;
- Antwort: höchstens 4.000 Codepoints;
- Standardbudget: 20 Requests pro lokalem Tag und Nutzer;
- höchstens ein gleichzeitig aktiver Request pro Nutzer plus globales
  Parallelitätslimit;
- erfolgreiche validierte User-/Assistant-Paare werden gespeichert;
- `Delete conversation` entfernt den Gesprächsinhalt, aber nicht die
  inhaltsfreien Request-Tombstones oder das Usage-Ledger. Löschen setzt das
  Tagesbudget deshalb nicht zurück;
- Prompt, Snapshot-Kopie und roher CLI-Eventstream werden nicht persistiert.

## Welche Daten liegen wo?

| Datenbereich | Zentrale Tabellen bzw. Speicherung | Hauptnutzer |
| --- | --- | --- |
| Identität und Profil | Supabase Auth, `profiles` | Routing, lokale Datumslogik, Account controls |
| Setup | `intake_responses`, `goals`, `habits`, `schedule_items`, `notification_preferences`, `memory_entries`, Onboarding-`user_state_snapshots` | Setup, Snapshots, Briefings, Coach |
| Tägliche Erfassung | `daily_logs`, `behavioral_events` | Today, Daily State, Insights |
| Ausführung | `tasks`, `habit_logs`, `focus_sessions` | Today, Focus/Habits, Snapshot, Weekly Review, Insights |
| Tagesüberblick | `daily_logs`, `tasks`, `habits`, `habit_logs`, `schedule_items`, aktive Planner-/Preparation-Blöcke, feste Planner-Commitments, aktueller Calendar Import und `focus_sessions` | `today-overview-v2` und Today; V1 bleibt kompatibel |
| Interne Tagesrangfolge | `user_state_snapshots`, `recommendations`, `daily_briefings`, `decision_feedback` | Reminder, Coach-Kontext, Historie und zukünftige regelbasierte Rangfolge |
| Wochenreview | `weekly_reviews` | Weekly Review, Reminder, begrenzter Coach-Kontext |
| Kalenderimport | `calendar_connections`, `calendar_imports`, `calendar_events`, technische Request-Identitäten | Calendar und optional Preparation Planner; nicht Coach |
| Vorbereitung | `deadline_plans`, `deadline_plan_revisions`, `deadline_plan_blocks`, technische Request-Identitäten | Preparation Plans, Today workload/week, Focus-Fortschritt |
| Zentrale Planung | `planner_preferences`, Action Plans/Revisionen, Task Blocks, Habit Slots, Planner Commitments und technische Request-Identitäten | Planner, Today V2 und gemeinsame Availability |
| Hinweise | `notifications`, `notification_preferences`, Action-Request-Ledger | Inbox und foreground banners |
| Coach | `coach_requests`, `coach_usage_events`, `coach_memory_selections`, `coach_messages` | Coach-Availability, Context, History und Budget |
| Weitere Projektionen | `ai_insights`, `skillset_profiles` | gespeicherte Notes bzw. ausschließlich gekennzeichnete lokale Demo-Skillset-Anzeige |
| Gerätelokal | Guest-Check-ins und Theme-Präferenz | Gastmodus bzw. Appearance |

Technische Request- und Usage-Ledger sind keine sichtbaren Features. Sie sorgen
dafür, dass ein Retry dieselbe Operation nicht doppelt ausführt und dass
gelöschte Coach-History kein Budget zurücksetzt. Supabase RLS begrenzt Reads auf
den Eigentümer; besonders sensible oder abgeleitete Writes laufen nur über
FastAPI und service-role-only RPCs.

## Wo bleiben bewusste Produktgrenzen sichtbar?

Planner ordnet die frühere Verteilung der Planung neu. Einige Trennlinien sind
absichtlich weiterhin sichtbar:

1. **`Today` bündelt weiterhin viele Rollen.** Der primäre Bereich ist jetzt
   klarer als Streak, Fortschritt, Agenda, Tasks und Habits geordnet; unter
   `More` bleiben aber Preparation-Auslastung, Weekly Review, Recommendations,
   Feedback-Historie und die volle Woche gebündelt.
2. **Definition und Zeitplanung sind nicht immer dieselbe Autorität.** Planner
   verwaltet manuelle Tasks, Habits, Preparation und Commitments. Goals sowie
   Setup-owned Habit-/Commitment-Definitionen bleiben unter `Settings → Setup`;
   Planner darf sie nur ausführen beziehungsweise als Busy-Time verwenden.
3. **Drei Zeitmodelle sehen ähnlich aus.** Wiederkehrende `Schedule Items`,
   importierte `Calendar Events` und datierte `Preparation Blocks` heißen im
   Alltag alle schnell „Kalender“, haben aber völlig andere Rechte und
   Bedeutungen.
4. **Mehrere Ratschlagsquellen existieren weiter.** Recommendations liegen
   bewusst unter `More`, das Daily Briefing ist ein interner regelbasierter
   Backend-Fakt für Reminder/Coach/Feedback, und eine Coach-Suggestion bleibt
   nur eine unverbindliche sprachliche Reflexion.
5. **Setup ist gleichzeitig Onboarding und spätere Verwaltung.** Nutzer erwarten
   dort meist nur den ersten Start, tatsächlich werden dort dauerhaft Goals,
   Setup-Habits und Commitments gepflegt.
6. **Quick actions bleibt reine Tagesausführung.** Check-ins, Habit Completion
   und Focus liegen dort; Neuanlage und Verwaltung sind in Planner gebündelt.
7. **`Insights` mischt aktuelle Berechnung und gespeicherte Notes.** Die
   Korrelationen sind live und regelbasiert; `ai_insights` kann dagegen nur
   Seed- oder anderweitig gespeicherte Zeilen enthalten. Der technische Name
   suggeriert mehr aktive AI-Erzeugung, als heute existiert.
8. **Die Oberfläche ist nur englisch.** Für eine deutschsprachige Nutzung
   erhöht das zusätzlich die begriffliche Reibung.

## Empfohlenes einfaches Denkmodell für die jetzige UI

Bis zu einer späteren Informationsarchitektur kann man die App so lesen:

| Frage | Richtiger Ort |
| --- | --- |
| Was ist heute gespeichert und noch offen? | `Today`: Streak, Progress, Agenda, Tasks und Habits |
| Wie fühle ich mich gerade bzw. wie war der Tag? | `Quick actions → Morning/Evening` |
| Was will ich einmalig erledigen oder terminieren? | `Planner → Task` |
| Was will ich regelmäßig tun oder terminieren? | `Planner → Habit`; Ausführung über `Quick actions → Habit completion` |
| Woran arbeite ich jetzt messbar? | `Quick actions → Focus` |
| Welche Prüfung/Abgabe braucht reservierte Lernzeit? | `Planner → Exam/Assignment` |
| Was ist einmalig oder jede Woche fest belegt? | `Planner → Fixed commitment`; Setup-owned Commitments bleiben unter `Settings → Setup` |
| Was ist meine längerfristige Richtung? | `Settings → Setup and commitments → Goals` |
| Was passierte letzte Woche? | `Today → Weekly review` |
| Welche Zusammenhänge sehe ich über mehrere Tage? | `Insights` |
| Welche Hinweise warten auf mich? | `Settings → Inbox` |
| Kann mir ein Modell den Zustand erklären? | `Settings → Coach`, nur Development Preview |

Goals und Setup-owned Habit-/Commitment-Definitionen bleiben bewusst unter
Settings Setup; Planner darf aktive Setup-Habits zeitlich einplanen und zeigt
Setup-Commitments als belegte Zeit, übernimmt aber nicht deren Definition.

## Konkreter Testweg mit dem Student-Account

Der lokale, synchronisierte Testuser ist als breite Produkt-Fixture gedacht:

```text
E-Mail:   student@example.test
Passwort: DemoPass123!
```

Er läuft mit `USE_MOCK_DATA=false` gegen die lokale Supabase- und FastAPI-
Umgebung. Der Seed deckt unter anderem 21+ Daily Logs, drei Habit-Cadences,
mehrere Task-Status, eine fortsetzbare aktive Focus Session, Briefing-Historie,
Decision Feedback, Weekly Review, Calendar Import, drei Preparation Plans,
In-app consent, Inbox-Zustände, ausgewählte Memories und Coach-History ab.

Ein sinnvoller manueller Rundgang ist:

1. Auf `Today` den Both-capture-Streak, die genaue `x/y`-Arithmetik, alle vier
   Agenda-Kategorien sowie Today/All Tasks und Today Habits prüfen.
2. `More` öffnen und Preparation Workload, Weekly Review, gespeicherte Signale,
   Recommendations, vorhandene Feedback-History und Full Week prüfen.
3. Unter `Quick actions` die aktive Focus Session fortsetzen oder beenden und
   Habit outcomes ausführen.
4. `Weekly review` öffnen, Fakten und die Änderungsautorität eines Vorschlags
   unterscheiden.
5. `Planner` öffnen: alle fünf Create-Flows, Needs attention, sieben Tage,
   Unscheduled und aktive Preparation prüfen; einen Task/Habit-Preview erst
   nach bewusster Bestätigung reservieren.
6. Unter `Settings → Calendar import` read-only Events und den Einstieg `Plan
   preparation` ansehen.
7. In `Insights` Observation, Datenfenster, Signalquellen und Advanced-
   Korrelationen prüfen.
8. Unter `Settings → Inbox` unread/read/dismiss und erlaubte `Open`-Ziele
   testen.
9. Unter `Settings` Preparation Budget, Reminder-Consent und Coach öffnen. Bei
   `fake` provider sind Antworten absichtlich feste Testdaten und kein LLM-
   Beweis.

`npm run seed:demo` stellt diese lokale Fixture wieder her, löscht und erzeugt
dabei aber die drei ausdrücklich benannten **lokalen** Demo-Auth-Accounts neu.
Es ist kein Befehl für eine Remote-Datenbank.

## Bewusst nicht implementiert

- deutsche Lokalisierung;
- allgemeine Goals- oder Memory-Verwaltungsseite sowie Bearbeitung
  Setup-owned Definitionen außerhalb von Settings Setup;
- produktionsfähiger LLM-Provider;
- ein persönliches trainiertes Modell oder Vector Memory;
- autonomer Coach oder model-gesteuerte Schreibaktionen;
- Live-Calendar-OAuth, URL-Fetch, Zwei-Wege-Sync oder Provider-Write;
- Browser-, System-, Push-, E-Mail- oder Background-Notifications;
- deployter Cron/Scheduler;
- automatische Prüfungsaufwandsschätzung oder Calendar-Titel-Inferenz;
- automatische Plan-, Goal-, Task- oder Habit-Änderungen;
- belastbarer Skillset-Score für echte Accounts.

## Vertiefende technische Dokumente

- `docs/architecture.md`: Systemgrenzen und Datenflüsse.
- `docs/daily-briefing-implementation-plan.md`: Daily State, Briefing, Ranking
  und Feedback.
- `docs/today-overview-v1-contract.md`: Streak, Progress, Agenda-Quellen,
  Today-Task/Habit-Auswahl, Teilfehler und Guest-Grenze.
- `docs/planner-v1-contract.md`: zentrale Planner-Navigation, Availability,
  Task-/Habit-Previews, Commitments und Today V2.
- `docs/phase-3-executable-actions-contract.md`: Tasks, Habits, Focus und
  ausführbare Actions.
- `docs/phase-8-weekly-review-contract.md`: Wochenfakten und bestätigte
  Habit-Anpassung.
- `docs/phase-9-calendar-import-contract.md`: Calendar Consent und read-only
  `.ics`-Import.
- `docs/deadline-planner-v1-contract.md`: Preparation Plans, Revisionen,
  Blocks, Kapazität und Fortschritt.
- `docs/phase-10-controlled-coach-plan.md`: Coach-Context, Provider, Safety,
  Memory und Usage.
- `docs/notification-lifecycle-v1-contract.md`: Inbox read/unread/dismiss.
- `docs/notification-delivery-v1-contract.md`: Consent, fixe Reminder-Copy und
  foreground delivery.
- `docs/v1-account-controls-contract.md`: Zeitzone, Export und Account-Löschung.
- `docs/ui-language-and-copy-contract.md`: aktuelle englische Produktbegriffe
  und Capability-Truth.
