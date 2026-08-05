# MyLifeGraph: aktueller Produktleitfaden

Status: Beschreibung des tatsächlich implementierten Repository-Stands vom
31. Juli 2026. Dieses Dokument beschreibt den Ist-Zustand, nicht die Roadmap.
Die verbindlichen technischen Detailverträge bleiben die am Ende verlinkten
Contract-Dokumente.

Die Oberfläche ist in V1 vollständig englisch. Deshalb stehen die sichtbaren
englischen Namen in diesem Dokument in Klammern. Eine deutsche Lokalisierung ist
aktuell nicht implementiert.

## Die Kurzfassung

MyLifeGraph soll explizite Angaben und beobachtbare Handlungen in einen klaren,
ehrlichen Tagesüberblick und vorsichtige regelbasierte Unterstützung übersetzen:

1. **Setup** erfasst optional den Namen, verpflichtend Typical weekday und Best
   energy window sowie optional Routinen, feste Wochenblöcke, Lernrhythmus und
   Semesterplanung.
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
9. Der **Coach** beantwortet freie Fragen auf Englisch, untersucht bei Bedarf den gesamten
   verfügbaren persönlichen Datenzeitraum read-only und kann Annahmen prüfen
   oder fehlende Daten benennen. Er darf keine Produktdaten ändern.

Der Großteil des Produkts ist bewusst regelbasiert und verwendet **kein LLM**.
Der Coach ist die einzige Oberfläche, die in einer explizit aktivierten lokalen
Entwicklungsumgebung ein echtes Sprachmodell aufrufen kann.

## Das beabsichtigte Produktmodell

```text
Längerfristiger Kontext
Profile + schlankes Setup + Habits + feste Commitments
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

Coach: erhält je Frage einen frischen persönlichen Read-only-Snapshot,
       darf ihn inspizieren, mit SQL abfragen oder isoliert analysieren,
       besitzt aber keinerlei Änderungsrechte.

Calendar import: bleibt ein separater, read-only Datenzweig und darf nur auf
ausdrücklichen Wunsch im Planner beziehungsweise bei Preparation als Busy-Time-
Quelle verwendet werden. Es gibt keinen Live-Sync und keinen Calendar-Write.
```

## Welche Betriebsarten gibt es?

| Modus | Speicherung | Verfügbare Funktionen | Wichtige Grenze |
| --- | --- | --- | --- |
| Local guest/demo | Check-ins und ausgewählte Beispieldaten lokal auf dem Gerät | Grundnavigation, Morning/Evening, ehrliche Demo- oder Leerzustände | Keine synchronisierten Tasks, Habits, Focus sessions, Planner-Pläne, Reviews, Kalenderimporte oder Preparation Plans |
| Synced account | Supabase Auth und die eigenen, per RLS geschützten Supabase-Daten; abgeleitete Workflows über FastAPI | Der vollständige aktuelle Produktumfang | Fehler werden angezeigt und niemals durch personalisiert wirkende Mock-Daten ersetzt |
| Coach mit `fake` provider | Wie ein synced account, aber Coach-Antworten sind feste Testantworten | Freie Frage, Stream, History, Evidence/Trace, Limits und UI lassen sich testen | Das ist kein aktives LLM und führt keine Analyse aus |
| Coach mit `local_codex_oauth` | Synced account plus explizit aktivierter Codex-CLI-Zugang und lokales Analyse-Image | Ein echter `gpt-5.5`-Fast-Turn mit drei Read-only-Werkzeugen | Nur lokale Entwicklung; nicht in Release/Produktion verfügbar |

Ein neu registrierter echter Account erhält seine Auth-Identität und sein
kanonisches Profil in Supabase. Danach erzwingt die App das Setup. Erst dessen
explizite Bestätigung materialisiert die gewählten Setup-Daten. Leere optionale
Felder erzeugen keine Habits oder Schedule Items. Setup verändert niemals die
separat in Settings gespeicherten Reminder-Einstellungen. Ein echter neuer
Account erhält keine Daten des `student`-Testusers.

## Navigation: Was befindet sich wo?

Mit aktiviertem Development-Coach hat die Hauptnavigation genau fünf Ziele.
In Release/Produktion oder bei ausgeschaltetem Coach-Gate entfällt `Coach`
vollständig; `Settings` wird nicht als redundanter Ersatz eingeblendet.

| Sichtbarer Bereich | Aufgabe | Was dort aktuell zu sehen oder zu tun ist |
| --- | --- | --- |
| **Today** | Den gespeicherten Tag überblicken und Tagesaktionen ausführen | Check-in-Streak, transparenter Fortschritt, vertikale Setup/Task/Habit/Fixed commitment/Preparation/Calendar/Focus-Agenda, heutige Tasks und Habits sowie eingeklappte unterstützende Details |
| **Insights** | Entwicklungen untersuchen | Für echte Accounts die unabhängigen Backend-Karten `Personal study pattern` und `Sleep recommendation` mit Stichprobe und erklärbarer Evidenz; zusätzlich 7/14/30/90-Tage-Korrelationen, Trends, Matrix und gespeicherte Insight-Notizen. Nur Demo zeigt die lokale Beispielbeobachtung und keine erfundene Schlafempfehlung. |
| **Quick actions** | Tagesdaten erfassen oder eine Aktivität ausführen | Evening check-in, Morning check-in, Habit completion und Focus |
| **Planner** | Aufgaben, Routinen und feste Zeiten bewusst planen | Task, Habit, Exam, Assignment und Fixed commitment anlegen; Vorschauen bestätigen; sieben Tage, Konflikte, Unscheduled und laufende Preparation verwalten |
| **Coach** | Eine freie Frage zu den eigenen Daten stellen | Development Preview mit frischem persönlichen Snapshot, Read-only-Analyse, sichtbarer Evidence/Provenance und validierter englischer Textantwort |

Weitere Screens sind Unterseiten und keine eigenständigen Hauptbereiche:

- `Settings` ist über den Button oben rechts auf `Today` erreichbar und enthält
  Profil/Zeitzone, Setup, Personal learning, Preparation Budget, Inbox, In-app
  reminders, Calendar import, Export, Löschung, Theme und Sign-out.
- `Weekly review` gehört logisch zu `Today`.
- `Today habits` und `Focus` gehören zur Ausführung unter `Quick actions`.
- `Habit management` und `Preparation plans` gehören logisch zu `Planner`;
  die bisherigen Routen bleiben kompatibel.
- `Inbox` gehört zu `Settings`; `/alerts` bleibt ein kompatibler Link.
- `Calendar import` und `In-app reminders` gehören zu `Settings`. Der
  Entwicklungs-`Coach` hat bei aktiviertem Surface-Gate den rechten
  Hauptnavigationseintrag; der Settings-Eintrag bleibt als sekundärer Zugang
  erhalten.
- Goals sind vollständig entfernt: Es gibt weder Tabelle, Export-Eintrag,
  Setup-Feld, Oberfläche noch aktive Auswertung. Außerdem gibt es keine separate
  Tasks-, Schedule- oder Memories-Hauptseite.

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

Bei echten Accounts beginnt `Insights` mit der read-only Backend-Karte
`Personal study pattern`. Sie zeigt `Collecting`, `Emerging`, `Stable` oder
`Disabled`, die bewertete Stichprobe, Abdeckung, das feste 90-Tage-Fenster und
die Profil-Zeitzone. Ausklappbar folgen höchstens drei rein beobachtende Muster
in fester Reihenfolge: Focus-Zeit, Schlaf und Sessionlänge beziehungsweise
Abstand. Fehlende Reflexionen zählen nicht als Null; die Karte behauptet weder
Ursache noch medizinisches oder akademisches Optimum.

Direkt darunter steht die unabhängige Karte `Sleep recommendation`. Vor 30
geeigneten lokalen Tagen zeigt sie den Fortschritt `N/30`; ohne belastbaren
Vergleich zeigt sie ehrlich `No stable window yet`. Ein geeigneter Tag verbindet
einen gültigen Morning-Check-in ausschließlich mit danach begonnenen,
beendeten und bewerteten Focus-Sessions. Bei `Ready` werden Schlafbeginn,
Aufstehen und Dauer als robuste Zeitfenster gezeigt; `Same local day` und
`Following local day` machen den lokalen Aufsteh-Tag explizit. Die Formulierung
bleibt
`best-supported sleep window` und `associated with`; ein Ergebnis wird weder
übernommen noch automatisch in Schlafziel, Evening-Plan oder Planner geschrieben.
Ein kürzeres beobachtetes Fenster als das bestätigte Schlafziel trägt eine
sichtbare Warnung. Fehler dieser Karte verändern `Personal study pattern` nicht.

Nur der klar beschriftete lokale Demo-Modus behält eine vorsichtige lokal
berechnete Beispielbeobachtung. Diese Demo-Ausgabe verändert keine Daten oder
Pläne.

Der ausklappbare Bereich `Advanced correlation exploration` enthält:

- Zeitfenster von 7, 14, 30 oder 90 Tagen;
- wählbare Signalpaare;
- normalisierte Trendlinien;
- Pearson-Korrelation und gemeinsame Beobachtungszahl;
- stärkste verfügbare Muster;
- eine Korrelationsmatrix;
- unter `Discovered patterns` gespeicherte `ai_insights`-Notizen.

Für echte Accounts stammen die profilzeitbasierten Punkte aus demselben
`personal-patterns-v1`-Backendvertrag. Flutter rekonstruiert keine historische
Planlast oder Habit-Erfüllung aus heutigen Zeilen. Verwendbare Metriken
erscheinen nur, wenn echte Werte vorhanden sind:

| Metrik | Datenquelle |
| --- | --- |
| Previous-night sleep, quality, shortfall | nur eine gültige V4/V5-Schlafepisode mit exakt demselben lokalen Aufwach-/Focus-Tag und `woke_at` vor der Session |
| Morning energy | nur wenn Morning vor Sessionstart erfasst wurde |
| Rated focus time and completion | Tagessumme beziehungsweise Quote ausschließlich bewerteter terminaler `focus_sessions` |
| Planned focus time | Tagessumme der an bewerteten Sessions gespeicherten geplanten Dauer |
| Rated focus quality and useful progress | vorhandene `focus-reflection-v1`-Bewertungen |

Eine Korrelation benötigt mindestens sieben gemeinsame Tage; 7–13 Tage bleiben
`Early evidence`, Rankings beginnen ab 14. Sleep/Shortfall und Activity/Steps
werden als überlappende Signale nicht miteinander verglichen. Das Ergebnis ist
eine **Assoziation, keine Ursache**. Die Exploration besitzt keine
Planner-Autorität. Nur ein separat freigegebenes, Planner-fähiges
Focus-Zeitfenster aus der kompakten Hauptkarte darf einen neu angeforderten
Preview weich bevorzugen.

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
| **Weekly review** | letzte abgeschlossene ISO-Woche, completed/carried/overdue Tasks, completed/skipped/missed/unknown Habit-Möglichkeiten, Focus-Sessions und Minuten, Recovery-Tage, Feedback-Anzahl, Datenqualität und Freshness | rein beobachtend; `Update weekly review` aktualisiert nur Fakten, historische Vorschläge bleiben unsichtbar und sind nicht ausführbar |
| **Preparation plans** | kompakte Open-/History-Accordions; im gezielt geöffneten Plan Schätzung, Vorleistung, Deadline, Revisionen, datierte Blöcke, bestätigte Reservierungen und gemessener Focus-Fortschritt | Vorschlag bleibt Preview; erst Bestätigung aktiviert Blöcke und den verwalteten Task; die 7-Tage-Auslastung bleibt in Today/Planner |
| **Inbox** | Anzahl unread/read/actionable innerhalb der höchstens 30 geladenen Einträge sowie einzelne Hinweise | Lifecycle-Änderungen und sichere interne Navigation; kein Analyse-Dashboard |

## Featurekatalog: Funktion, Eingaben und Ergebnis

| Feature | Wie es funktioniert | Verwendete Daten | Geschriebene Daten / LLM |
| --- | --- | --- | --- |
| **Auth und Account** | E-Mail/Passwort, Recovery und optional konfiguriertes Google OAuth über Supabase Auth | Auth-Identität und Profil | `profiles`; kein LLM |
| **Setup** | nur Typical weekday und Best energy window sind erforderlich; Name, Routinen, Commitments und Study Setup sind optional; Focus setup speichert Rhythmus und Start-Ritual, Semester planning genau ein aktuelles/nächstes Semester; atomar, revisioniert und retry-sicher | explizite Tagesstruktur/Energiefenster sowie optionale Routine-, Commitment-, Focus-/Pausen-, Ritual- und Semesterangaben; keine Focus Areas, Goals, Frictions, Coaching-Style-, Reminder- oder Context-Frage; `responses.goals` wird abgelehnt | `intake_responses`, `study_setup_profiles`, `habits`, `schedule_items`, die Best-Energy-`memory_entries` und Onboarding-Snapshot; `notification_preferences` bleibt vollständig unverändert; kein LLM |
| **Morning check-in** | korrigierbarer geschätzter Schlafbeginn und Aufwachzeit mit automatisch berechneter „Estimated sleep duration“, separat geschätzter Schlafqualität (1–10) und aktueller Energie; keine Tagesform-Auswahl | explizite Selbstauskunft; Qualität wird nicht aus der Dauer abgeleitet, Rohzeiten gelten nicht als objektive Messung | `daily-capture-v5` im lokalen Tag; Rohzeiten bleiben nur in `daily_logs`, Dauer/Qualität werden kompatibel projiziert, kein fünftes Event und kein LLM; historische V2–V4-Werte bleiben lesbar, Day Shape wird nicht mehr gezeigt oder genutzt |
| **Evening check-in** | drei kurze Schritte für Mood, Energie, Stress, geplante Schlafzeit mit Dauerziel sowie optionale Reflection und Specific Blocker; keine Possible Priority oder Friction-Auswahl | explizite Auswahl/Text; bei Stress 5–10 zusätzlich Quelle mit separater Info-Hilfe und Kontrollierbarkeit; zuerst sichtbar sind acht Stunden, persönlich wird der Wert erst beim Speichern | `daily-capture-v5` im selben `daily_logs`-Tag plus abgeleitete `behavioral_events`; während des Rollouts bleiben vollständige V4-Schreibvorgänge zulässig, ein V5-Container wird nie herabgestuft; V2–V4 bleiben lesbar; freie Texte/Rohzeiten gelangen nicht in Daily State, können aber im ausdrücklich ausgelösten persönlichen Coach-Snapshot als nicht vertrauenswürdige Daten enthalten sein |
| **Daily State / Snapshot** | `explainable-daily-state-v3` betrachtet einen festen Sieben-Tage-Kontext und klassifiziert Zustand, Risiken und Gründe ohne Friction oder Day Shape; sehr schlechte Schlafqualität kann trotz ausreichender Dauer Recovery auslösen, mäßig schlechte Qualität verhindert Push, und Push benötigt einen aktiven Task | validierte Stress-, Schlaf- und Energie-Signale plus Workload/Tasks; Habits, Outcomes, Focus, Schedule und Memories ergänzen die übrige Snapshot-Zusammenfassung; keine Goals | `user_state_snapshots`; kein LLM und kein gelernter persönlicher Basiswert; V1/V2 bleiben lesbar, aber `constrained_capacity` und der Day-Shape-Push-Gate sind entfernt |
| **Recommendations** | einzelne regelbasierte Kandidaten werden explizit oder geplant erzeugt/aktualisiert; Setup erzeugt keine Recommendation | Snapshot, echte Check-ins, offene Tasks, Habits und verfügbare Feedback-Signale; keine Goals oder retired Onboarding-Personalisierung | `recommendations`; LLM-Wording ist im aktuellen Produktpfad deaktiviert |
| **Daily Briefing** | wählt aus zulässigen Kandidaten eine primäre und bis zu zwei unterstützende Aktionen | aktueller Snapshot, Recommendations, Actions, Dringlichkeit, Recovery-Schutz und passendes Feedback | `daily_briefings`; regelbasiert, nicht AI-geschrieben |
| **Tasks** | endliche Aktionen mit Status und optionaler Deadline/Schätzung | direkte Nutzereingabe oder ein vom bestätigten Preparation Plan verwalteter Task | `tasks`; kein LLM |
| **Habits** | wiederkehrende Routinen mit daily-, weekday- oder weekly-target-Cadence | Definition plus explizites completed/skipped/undo pro lokalem Datum | `habits`, `habit_logs`; kein LLM |
| **Focus** | echter Timer, optional mit genau einem Task oder Habit verknüpft; gespeicherte Ritualpunkte werden vor Start lokal bestätigt/übersprungen, nach Abschluss kann ein lokaler Recovery-Countdown laufen | geplante Blockdauer oder Study Default, einmalig änderbare Dauer und gemessene verstrichene Zeit; Ritual-Häkchen werden nicht gespeichert | `focus_sessions` inklusive verwendeter Recovery-Minuten; kein eigener Pausendatensatz und kein LLM |
| **Planner** | deterministische Vorschau aus expliziter Dauer/Deadline/Session beziehungsweise Habit-Dauer/Cadence; normale Tasks können explizit den Study Rhythm verwenden, Habits nicht; freie Zeit berücksichtigt bestätigte Belegung einschließlich Recovery; eine aktive Klausur aktiviert zusätzlich den read-only 14-/7-Tage-Outlook mit hypothetisch geschütztem Schlaf | Task/Habit-Eingaben, primär Setup/manual commitments, Study-Revision, Planner/Preparation reservations, optional consented aktueller Import sowie neueste gültige Evening-/Morning-V4/V5-Schlaffakten | Planner preferences/plans/revisions/blocks/slots/commitments; erst Confirm erstellt/ändert Ziel und Reservierungen; Outlook speichert nichts und erzeugt weder Today-Eintrag noch Notification; kein LLM, Calendar-Write oder Auto-Replan |
| **Decision feedback** | Reaktion auf eine konkrete Briefing-Aktion | Aktion, Kontext und Feedback-Typ | append-only `decision_feedback`; beeinflusst begrenzt spätere Rankings, führt die Aktion aber nicht aus |
| **Weekly review** | deterministische Fakten für die letzte abgeschlossene lokale ISO-Woche | Tasks, Habit-Möglichkeiten/Outcomes, Focus, Daily State und Feedback | `weekly-review-v2` in `weekly_reviews`; kein LLM, keine Vorschlagserzeugung und keine Produktänderung |
| **Calendar import** | ein bewusst gewähltes UTF-8-`.ics`-File wird begrenzt und read-only importiert | explizite Einwilligung und die gewählte Datei | `calendar_connections`, `calendar_imports`, `calendar_events`; nie in `schedule_items` kopiert; im Coach nur als nicht vertrauenswürdige Snapshot-Daten, niemals als Anweisung |
| **Preparation plans** | Nutzer schätzt Gesamtaufwand und Vorleistung; kompakte Open-/History-Accordions zeigen genau einen fokussierten Plan, Regeln teilen Restzeit in überprüfbare Datumsblöcke und verwenden einen konfigurierten Study Rhythm verbindlich | Deadline, eigene Schätzung, Study-Revision beziehungsweise sonst bevorzugte Blockgröße, Tageslimit, Puffer, Setup-Commitments und optional aktuelle importierte Busy Times | `deadline_plans`, Revisionen, Focus-/Recovery-Blocks und nach Bestätigung ein verwalteter `task`; fokussiertes Replanning bleibt bis zur Bestätigung staged; Recovery ist Belegung, aber keine Lern-/Budgetminute; kein LLM |
| **Insights** | `personal-patterns-v1` liefert die persönliche Musterkarte und Korrelationen; `sleep-recommendation-v1` liefert unabhängig Fortschritt, Unstable-Grund oder drei robuste Ready-Fenster; nur Demo berechnet lokal eine vorsichtige Beispielbeobachtung und ruft die Schlafroute nicht auf | terminale Focus Sessions mit vorhandenen Reflexionen sowie ausschließlich vor der Session gültige Schlaf-/Morning-Fakten; für Schlafempfehlung mindestens 30 geeignete Tage; gespeicherte `ai_insights` bleiben getrennte Notizen | read-only; kein LLM, keine Kausalaussage, kein Apply und keine automatische Produktänderung; Planner-Nutzung nur nach separater Freigabe für neue Focus-Previews |
| **Inbox lifecycle** | fällige gespeicherte Hinweise lesen, unread/read setzen oder dismissen | owner-scoped `notifications` | Lifecycle-Zeitstempel plus Retry-Ledger; kein LLM |
| **In-app reminders** | nach separater Einwilligung werden höchstens zwei Kandidaten mit fixer Copy regelbasiert erzeugt und bei offener App höchstens einmal als Banner gezeigt | aktueller Recovery-/Briefing-Zustand oder aktuelles Weekly Review, Kategorien, Quiet Hours und Tageslimit | `notification_preferences`, `notifications` und Delivery-Provenance; kein Push, kein Background und kein LLM |
| **Coach** | freie Frage, bei Bedarf Read-only-Inspektion/SQL/isoliertes Python, Safety-Prüfung und validierte englische Textantwort | frischer owner-only SQLite-Snapshot über den verfügbaren relevanten Produktzeitraum, inklusive Detailtexten und Datenkatalog | `coach_requests`, `coach_messages`, Usage sowie backend-erzeugte Evidence/Trace/Fast-Provenance; klar deutsche Provider-Ausgabe wird vor Assistant-Persistenz verworfen; kein Plot und keine Produktmutation; nur dieser Pfad kann lokal ein LLM verwenden |
| **Account controls** | Zeitzone, JSON-Export, Passwort-Recovery und permanente Löschung | Profil und owner-scoped Produktdaten | kontrollierte FastAPI/RPC-Operationen; kein LLM |

## Die zentralen Begriffe

### Vergleich auf einen Blick

| Objekt | Kernfrage | Zeitmodell | Wird „erledigt“? | Aktueller Verwaltungsort |
| --- | --- | --- | --- | --- |
| **Task** | Was kann ich einmalig abschließen? | optionaler Deadline-Zeitpunkt | ja | Today |
| **Habit** | Was will ich regelmäßig wiederholen? | täglich, gewählte Wochentage oder Wochenziel | Outcome pro lokalem Tag | Quick actions / Setup bei Setup-owned Habits |
| **Schedule Item** | Wann bin ich jede Woche fest gebunden? | wiederkehrender Wochentag mit Start/Ende | nein | Setup; Ansicht in Today |
| **Calendar Event** | Was stand in der importierten Datei? | konkreter importierter Zeitraum | nein, read-only | Settings → Calendar import |
| **Preparation Block** | Wann reserviere ich einen Teil meiner Prüfungsvorbereitung? | konkretes lokales Datum im bestätigten Plan | nicht einzeln; Fortschritt kommt aus Focus | Preparation plans; Ansicht auch in Today |
| **Focus Session** | Woran arbeite ich jetzt tatsächlich? | gemessener Timerblock | completed oder abandoned | Quick actions → Focus |

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
- wird nie zu einem `schedule_item`; der Coach darf seine lokale read-only
  Kopie nur als nicht vertrauenswürdige Snapshot-Daten untersuchen.

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
- Ist ein Study Rhythm gespeichert, sind normale Blöcke exakt so lang; nur der
  letzte Restblock darf kürzer sein. Die vollständige Recovery-Zeit bleibt
  reserviert, zählt aber nicht zu Aufwand, Fortschritt oder Tagesbudget.
- Eine Änderung des Study Rhythm macht eine offene Preview veraltet und zeigt
  den aktiven Plan unter `Needs attention`; sie verschiebt nie automatisch
  einen Block.
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
- Ein geplanter Block bestimmt zuerst die Dauer, sonst gelten Study Default,
  letzte Session und schließlich 25 Minuten; eine manuelle Session kann die
  Dauer einmalig abweichend wählen.
- Aktive Setup-Ritualpunkte werden als `Ready`/`Not needed today` oder über
  `Skip remaining and start` erledigt. Diese Auswahl wird nicht gespeichert.
- Nur eine abgeschlossene Session startet den überspringbaren lokalen
  Recovery-Countdown. Die Pausenlänge steht in der Session-Metadatenstruktur,
  erzeugt aber weder Historie noch Fortschritt.

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

Eine **Memory Entry** ist eine dauerhafte, überprüfbare Notiz, etwa zu Habit,
Pattern oder wiederkehrendem Problem. Setup materialisiert nur noch `Best
energy window`; manuelle oder anderweitig erzeugte Memories bleiben erhalten.
Der aktuelle freie Coach kann sanitisierten owner-scoped Memory-Inhalt in
seinem temporären Snapshot untersuchen. Die frühere Auswahl von höchstens acht
Memories bleibt nur für lesbare V1/V2-Historie kompatibel und erscheint nicht
mehr im aktuellen Coach-Screen.

Aktuell gilt:

- keine automatische Extraktion aus Gesprächen;
- keine automatische Änderung von Stärke oder Evidenz;
- Memory-Text ist im Coach immer nicht vertrauenswürdige Daten, nie Anweisung;
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

### 1. Expliziter Setup-Kontext

Die App kennt Typical weekday, bestes Energiefenster, bestätigte Habits, feste
Commitments und optional Study Setup, weil der Nutzer sie angegeben hat. Das ist
gespeicherter Kontext, kein maschinelles Lernen. Reminder-Einstellungen bleiben
ein separater Settings-Vertrag.

### 2. Regelbasierte Zustandsableitung

Daily State, Briefings, Preparation Plans, Weekly Reviews und Reminders werden
mit transparenten, versionierten Regeln berechnet. Gleiche Eingaben erzeugen
dieselben Ergebnisse. Ein LLM entscheidet diese Ergebnisse nicht.

### 3. Verhaltensfakten

Completed/cancelled Tasks, completed/skipped Habits und completed/abandoned
Focus-Sessions liefern belastbarere Fakten als eine weitere Selbsteinschätzung.
Sie fließen in Snapshots, Wochenfakten und Insights ein, ändern aber nicht
heimlich Definitionen.

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

### 6. Rein beobachtende Wochenfakten

Weekly Review fasst ausschließlich Fakten der abgeschlossenen Woche zusammen:
Tasks, Habit-Möglichkeiten und -Outcomes, Focus, Recovery-Tage und Feedback.
Neue oder aktualisierte Reviews erzeugen keine Vorschläge und ändern weder
Habits noch Tasks, Schedule oder Pläne. Historische Proposal-Arrays bleiben nur
für alte gespeicherte Zeilen transportlesbar; Flutter zeigt sie nicht an und
kann sie nicht ausführen.

### Was die App ausdrücklich noch nicht tut

- kein Online-Training oder Fine-tuning eines persönlichen Modells;
- kein persönlicher gelernter Baseline- oder Readiness-Score;
- keine Embeddings und keine Vector Search;
- keine automatische Memory-Extraktion aus Check-ins oder Coach-Chats;
- kein autonomer Hintergrund-Agent; der Coach besitzt genau drei begrenzte
  Read-only-Analysewerkzeuge und keine Shell-, Web- oder Schreibwerkzeuge;
- keine versteckten Änderungen an Tasks, Habits, Schedule oder Plänen;
- keine automatische Kalender-Synchronisation;
- keine kausalen Gesundheits- oder Leistungsbehauptungen.

## Was kann der LLM Coach aktuell?

### Sichtbarkeit und Provider

Der Screen heißt `Coach` und beginnt mit `Ask anything`.

- Er ist in Release-Builds und bei `APP_ENV=production` immer verborgen.
- Mit `provider=fake` zeigt er feste Testantworten. Die UI sagt dann ausdrücklich
  dass es Testdaten und kein Live-Assistant sind.
- Mit explizit aktiviertem `local_codex_oauth` kann FastAPI lokal die bereits
  angemeldete Codex CLI desselben Linux/WSL-Nutzers aufrufen. Jeder Turn
  verlangt exakt `gpt-5.5`, `service_tier="fast"` und aktivierten Fast Mode.
- Fehlen Modell, Fast-Unterstützung, Login, Docker oder Analyse-Image, ist der
  Provider ehrlich nicht verfügbar. Es gibt keinen Modell-/Tier-Fallback und
  keinen deploybaren Produktionsprovider.

### Was er lesen darf

Für jede bewusst gesendete V3-Frage baut FastAPI eine neue, private
`personal-snapshot-v2`-SQLite-Datei ausschließlich aus Daten des angemeldeten
Owners. Sie darf den gesamten verfügbaren Zeitraum der relevanten Quellen
enthalten:

- Setup/Intake, Preferences und Study Setup;
- Morning/Evening, Behavioral und Lifestyle Entries;
- Tasks, Habits/Outcomes, Focus Sessions und Reflections;
- Planner, Preparation Plans, Commitments und Reservierungen;
- Calendar Connection/Import/Event-Inhalte;
- Snapshots, Briefings, Feedback und Weekly Reviews;
- Insights, Recommendations, Skillsets und Memories; sowie
- frühere Coach-Nachrichten.

Ein verständlicher Katalog beschreibt Tabellen, Spalten, Beziehungen,
Datensatzanzahlen, verfügbare Zeiträume und Hilfs-Views. Maximal gelten 10.000
Zeilen je Quelle, 50.000 insgesamt und 8 MiB. Überschreitung bricht ehrlich ab;
es gibt keine stille Kürzung.

Der Agent erhält ausschließlich:

- `inspect_data` für Katalog und Abdeckung;
- `query_data` für begrenzte read-only `SELECT`-/`WITH`-Abfragen; und
- `run_python` in einem separaten Docker-Container ohne Netzwerk oder Secrets,
  als Non-root mit read-only Root und ausschließlich read-only gemountetem
  Snapshot.

Pandas, NumPy, SciPy, Statsmodels und Matplotlib sind vorhanden. Ein interner
Plot kann dem Modell bei der Analyse helfen, wird aber weder gespeichert noch
in Flutter dargestellt.

### Was er nicht lesen darf

- Supabase Auth-Daten, E-Mail, Tokens, Rollen, Provider-Interna oder Service
  Keys;
- andere Nutzerzeilen;
- Anti-Replay-, Usage-, Memory-Selection- oder rein operative Backend-Ledger;
- allgemeine Hostdateien, OAuth-Dateien oder Backend-Environment;
- Web, Apps, Plugins, Unteragenten, Host-Shell oder Produkt-APIs.

Notes, Setup- und Calendar-Text, Memories und frühere Nachrichten können als
persönliche Daten im Snapshot stehen, gelten aber immer als nicht
vertrauenswürdige Inhalte und niemals als Anweisung.

### Was er ausgeben darf

- eine Antwort von höchstens 4.000 Zeichen;
- explizite Unsicherheit `low`, `medium` oder `high` samt Grund;
- Safety-Klassifikation;
- mehrere begründete Vorschläge im normalen Text, aber keine strukturierte
  Action/Suggestion;
- einen aufklappbaren Bereich mit tatsächlich verwendeten Datenquellen,
  Zeiträumen, Counts, Inspect-/SQL-/Python-Schritten, Einschränkungen und
  `gpt-5.5 · Fast configured`-Provenance.

Die sichtbare Antwort trennt beobachtete Daten, unsichere Interpretation,
fehlende Information und allgemeines Modellwissen. Sie darf einer falschen
Prämisse widersprechen oder eine kurze Rückfrage stellen. Chain-of-thought,
Plots, Scripts oder erfundene Evidence werden nicht angezeigt.

### Was er nicht tun darf

Der Coach kann keine Tasks, Habits, Schedule Items, Calendar Events,
Briefings, Reviews, Memories oder Preparation Plans anlegen, ändern, erledigen
oder löschen. Er kann keine Notifications auslösen und nicht im Hintergrund
laufen. Er darf aus beobachtbaren Produktdaten keine Kausalität, Diagnose oder
medizinische Gewissheit behaupten.

Deterministische Safety-Prüfungen laufen vor und nach dem Provider. Ein akuter
Risikofall kann Snapshot und Provider komplett umgehen.

### Limits und Speicherung

- Nachricht: höchstens 2.000 Unicode-Codepoints;
- Antwort: höchstens 4.000 Codepoints;
- Standardbudget: 20 gestartete Fragen pro lokalem Tag und Nutzer;
- höchstens ein gleichzeitig aktiver Turn pro Nutzer plus globales
  Parallelitätslimit;
- höchstens zwölf Tool-Aufrufe und 180 Sekunden pro Turn;
- SQL höchstens fünf Sekunden, Python höchstens 30 Sekunden;
- erfolgreiche validierte User-/Assistant-Paare werden gespeichert;
- Evidence, kompakter Tool-Trace und Fast-Provenance stammen aus Backend-
  Ausführung, nicht aus dem Modell;
- `Delete conversation` entfernt Gespräch, Evidence und Trace, aber nicht
  Request-Tombstones oder Usage. Löschen setzt das Tagesbudget nicht zurück;
- Prompt, SQLite-Snapshot, Python-Scripts, Plots, Temp-Dateien und roher
  CLI-Eventstream werden nach dem Turn gelöscht und nicht persistiert.

## Welche Daten liegen wo?

| Datenbereich | Zentrale Tabellen bzw. Speicherung | Hauptnutzer |
| --- | --- | --- |
| Identität und Profil | Supabase Auth, `profiles` | Routing, lokale Datumslogik, Account controls |
| Setup | `intake_responses`, `study_setup_profiles`, `habits`, `schedule_items`, Best-Energy-`memory_entries`, Onboarding-`user_state_snapshots` | Setup, Focus Defaults/Ritual und Planner/Preparation; keine Reminder-Mutation |
| Tägliche Erfassung | `daily_logs`, `behavioral_events` | Today, Daily State, Insights |
| Ausführung | `tasks`, `habit_logs`, `focus_sessions` | Today, Focus/Habits, Snapshot, Weekly Review, Insights |
| Persönliches Lernen | `focus_session_reflections`, `learning_preferences`; gelernte Planner-Provenienz additiv in Planner-/Deadline-Revisionen | Focus, Evening, Insights und nach separater Freigabe nur neue Planner-Previews |
| Tagesüberblick | `daily_logs`, `tasks`, `habits`, `habit_logs`, `schedule_items`, aktive Planner-/Preparation-Blöcke, feste Planner-Commitments, aktueller Calendar Import und `focus_sessions` | `today-overview-v2` und Today; V1 bleibt kompatibel |
| Interne Tagesrangfolge | `user_state_snapshots`, `recommendations`, `daily_briefings`, `decision_feedback` | Reminder, Historie, regelbasierte Rangfolge und bei expliziter Frage der temporäre Coach-Snapshot |
| Wochenreview | `weekly_reviews` | Weekly Review, Reminder und bei expliziter Frage Coach-Snapshot |
| Kalenderimport | `calendar_connections`, `calendar_imports`, `calendar_events`, technische Request-Identitäten | Calendar, optional Preparation Planner und read-only Coach-Snapshot; nie als Instruktion |
| Vorbereitung | `deadline_plans`, `deadline_plan_revisions`, `deadline_plan_blocks`, technische Request-Identitäten | Preparation Plans, Today workload/week, Focus-Fortschritt |
| Zentrale Planung | `planner_preferences`, Action Plans/Revisionen, Task Blocks, Habit Slots, Planner Commitments und technische Request-Identitäten | Planner, Today V2 und gemeinsame Availability |
| Hinweise | `notifications`, `notification_preferences`, Action-Request-Ledger | Inbox und foreground banners |
| Coach | `coach_requests`, `coach_usage_events`, `coach_messages`; `coach_memory_selections` nur Legacy-Kompatibilität | Availability, V3 Evidence/Trace/Fast-Provenance, gemischte History und Budget |
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
   verwaltet manuelle Tasks, Habits, Preparation und Commitments. Setup-owned
   Habit-/Commitment-Definitionen bleiben unter `Settings → Setup`;
   Planner darf sie nur ausführen beziehungsweise als Busy-Time verwenden.
3. **Drei Zeitmodelle sehen ähnlich aus.** Wiederkehrende `Schedule Items`,
   importierte `Calendar Events` und datierte `Preparation Blocks` heißen im
   Alltag alle schnell „Kalender“, haben aber völlig andere Rechte und
   Bedeutungen.
4. **Mehrere Ratschlagsquellen existieren weiter.** Recommendations liegen
   bewusst unter `More`, das Daily Briefing ist ein interner regelbasierter
   Backend-Fakt für Reminder/Coach/Feedback, und Vorschläge im Coach-Text
   bleiben unverbindliche, nicht ausführbare sprachliche Reflexionen.
5. **Setup ist gleichzeitig Onboarding und spätere Verwaltung.** Nutzer erwarten
   dort meist nur den ersten Start; tatsächlich werden dort dauerhaft
   Setup-Habits, Commitments und Study Setup gepflegt.
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
| Was passierte letzte Woche? | `Today → Weekly review` |
| Welche Zusammenhänge sehe ich über mehrere Tage? | `Insights` |
| Welche Hinweise warten auf mich? | `Settings → Inbox` |
| Kann mir ein Modell den Zustand erklären? | `Coach` in der Hauptnavigation, nur Development Preview |

Setup-owned Habit-/Commitment-Definitionen bleiben bewusst unter Settings
Setup; Planner darf aktive Setup-Habits zeitlich einplanen und zeigt
Setup-Commitments als belegte Zeit, übernimmt aber nicht deren Definition.

## Konkreter Testweg mit dem Student-Account

Der lokale, synchronisierte Testuser ist als breite Produkt-Fixture gedacht:

```text
E-Mail:   student@example.test
Passwort: DemoPass123!
```

Er läuft mit `USE_MOCK_DATA=false` gegen die lokale Supabase- und FastAPI-
Umgebung. Der Seed deckt unter anderem 43 profilzeitbasierte Daily-Capture-V5-
Tage, drei Habit-Cadences, mehrere Task-Status, 36 bewertete Focus-Tage, eine
fortsetzbare aktive Focus Session, Briefing-Historie, Decision Feedback, Weekly
Review, Calendar Import, drei Preparation Plans, In-app consent, Inbox-Zustände,
Memories und Coach-History ab. Schlaf bleibt bei ungefähr
`7:15–8:30 h`, Schlafqualität bei `6–9`, Energie bei `5–8` und Stress bei
`3–8`. Die heutige Morning Capture ist vorhanden; Evening bleibt absichtlich
offen.

Ein sinnvoller manueller Rundgang ist:

```bash
# Echte lokale Antworten über den bereits angemeldeten Codex-CLI-Nutzer
npm run start:local:coach

# Alternativ feste Testantworten ohne Modellaufruf
npm run start:local:coach:fake

# Personal-Learning-Planner zusätzlich freischalten
LEARNED_FOCUS_PLANNING_PILOT_ENABLED=true npm run start:local:coach:fake
```

Ein normales `npm run start:local` lässt neue Coach-Antworten bewusst
deaktiviert; die bereits gespeicherte Coach-History des Student-Accounts bleibt
dabei lediglich lesbar.

1. Auf `Today` den bis gestern reichenden Both-capture-Streak, die genaue
   `x/y`-Arithmetik, alle vier Agenda-Kategorien sowie Today/All Tasks und Today
   Habits prüfen. Danach den bewusst offenen heutigen Evening-Check-in
   ausfüllen und kontrollieren, dass Morning erhalten bleibt.
2. `More` öffnen und Preparation Workload, Weekly Review, gespeicherte Signale,
   Recommendations, vorhandene Feedback-History und Full Week prüfen.
3. Unter `Quick actions` die aktive Focus Session fortsetzen oder beenden und
   Habit outcomes ausführen; bei konfiguriertem Study Setup auch Checkliste und
   lokalen Recovery-Countdown prüfen.
4. `Weekly review` öffnen und die nachvollziehbaren Wochenfakten, Datenqualität
   und Freshness prüfen; es gibt dort keine Anpassungs- oder Bestätigungsaktion.
5. `Planner` öffnen: alle fünf Create-Flows, Needs attention, sieben Tage,
   Unscheduled und aktive Preparation prüfen; einen Task/Habit-Preview erst
   nach bewusster Bestätigung reservieren; `Use study rhythm` nur beim Task und
   offene/überfällige Kurswahl als Link zurück zu Settings prüfen. Bei einer
   aktiven Klausur zusätzlich den read-only Watch-/Exam-week-/Overdue-Status,
   Schlafkapazität und explizite Review-/Replan-Navigation prüfen.
6. Unter `Settings → Calendar import` read-only Events und den Einstieg `Plan
   preparation` ansehen.
7. In `Insights` `Personal study pattern` öffnen. Erwartet werden `Stable`, 36
   Bewertungen auf 36 lokalen Tagen, ungefähr 97% Abdeckung und das beobachtete
   Fenster `09:00–13:00`. Direkt darunter zeigt `Sleep recommendation` den
   Status `Ready` sowie Sleep start, Wake time, Duration und die Warnung zum
   kürzeren Rohfenster gegenüber dem bestätigten Ziel. Unter `Quick actions → Focus` eine historische
   Bewertung bearbeiten sowie die aktive Session beenden und neu bewerten.
8. Für Planner-Nutzung die App mit dem obigen Pilot-Flag starten, unter
   `Settings → Personal learning` den standardmäßig ausgeschalteten Schalter
   `Prefer learned Focus times in new plans` aktivieren und einen neuen
   Task-Preview anfordern. Ein freies passendes Ergebnis zeigt
   `Learned timing applied · 36 rated sessions`; belegte Zeit darf weiterhin
   einen sichtbaren Setup-Fallback auslösen.
9. Unter `Settings → Inbox` unread/read/dismiss und erlaubte `Open`-Ziele
   testen.
10. Unter `Settings` Preparation Budget und Reminder-Consent prüfen. `Coach`
   über die Hauptnavigation öffnen, eine freie Frage stellen und `Data and
   analysis details` prüfen. Es darf keine Modus-/Horizon-/Focus-/Memory-
   Auswahl oder Plot geben. Beim `fake` provider sind Antworten absichtlich
   feste Testdaten und kein LLM-Beweis.

`npm run seed:demo` stellt diese lokale Fixture wieder her, löscht und erzeugt
dabei aber die drei ausdrücklich benannten **lokalen** Demo-Auth-Accounts neu.
Es ist kein Befehl für eine Remote-Datenbank.

## Bewusst nicht implementiert

- deutsche Lokalisierung;
- Goals in Schema, Export, Setup, Oberfläche oder Auswertung sowie eine
  allgemeine Memory-Verwaltungsseite;
- produktionsfähiger LLM-Provider;
- ein persönliches trainiertes Modell oder Vector Memory;
- autonomer Hintergrund-Coach, zusätzliche Tools oder model-gesteuerte
  Schreibaktionen;
- Live-Calendar-OAuth, URL-Fetch, Zwei-Wege-Sync oder Provider-Write;
- Browser-, System-, Push-, E-Mail- oder Background-Notifications;
- deployter Cron/Scheduler;
- automatische Prüfungsaufwandsschätzung oder Calendar-Titel-Inferenz;
- automatische Plan-, Task- oder Habit-Änderungen;
- belastbarer Skillset-Score für echte Accounts.

## Vertiefende technische Dokumente

- `docs/setup-personalization-retirement-contract.md`: schlankes Setup,
  Goal-/Friction-Stilllegung, Kompatibilität und Datenbereinigung.
- `docs/architecture.md`: Systemgrenzen und Datenflüsse.
- `docs/daily-briefing-implementation-plan.md`: Daily State, Briefing, Ranking
  und Feedback.
- `docs/today-overview-v1-contract.md`: Streak, Progress, Agenda-Quellen,
  Today-Task/Habit-Auswahl, Teilfehler und Guest-Grenze.
- `docs/planner-v1-contract.md`: zentrale Planner-Navigation, Availability,
  Task-/Habit-Previews, Commitments und Today V2.
- `docs/study-setup-v1-contract.md`: Focus Rhythm, Start-Ritual, Recovery-
  Reservierungen, Semester und Kurswahlfenster.
- `docs/phase-3-executable-actions-contract.md`: Tasks, Habits, Focus und
  ausführbare Actions.
- `docs/phase-8-weekly-review-contract.md`: rein beobachtende Wochenfakten,
  Freshness und historische Transportkompatibilität.
- `docs/phase-9-calendar-import-contract.md`: Calendar Consent und read-only
  `.ics`-Import.
- `docs/deadline-planner-v1-contract.md`: Preparation Plans, Revisionen,
  Blocks, Kapazität und Fortschritt.
- `docs/phase-10-controlled-coach-plan.md`: freier Coach-Agent, persönlicher
  SQLite-Snapshot, MCP/Python-Sandbox, Provider/Fast, Safety, Evidence und Usage.
- `docs/notification-lifecycle-v1-contract.md`: Inbox read/unread/dismiss.
- `docs/notification-delivery-v1-contract.md`: Consent, fixe Reminder-Copy und
  foreground delivery.
- `docs/v1-account-controls-contract.md`: Zeitzone, Export und Account-Löschung.
- `docs/ui-language-and-copy-contract.md`: aktuelle englische Produktbegriffe
  und Capability-Truth.
