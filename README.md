# Smart Pantry

Private Lebensmittelverwaltung als React-/TypeScript-PWA mit Vite, Tailwind CSS, Supabase Auth, PostgreSQL und Realtime. Für Vercel vorbereitet. Die übergebene Projektbeschreibung endet mitten in Abschnitt 15; umgesetzt sind die davor beschriebenen Anforderungen.

## Lokal starten

Voraussetzung: Node.js 22.12 oder neuer (getestet mit Node 24).

```powershell
npm ci
npm run dev
```

Die im Terminal angezeigte Adresse öffnen, normalerweise http://127.0.0.1:5173. Ohne Supabase-Konfiguration startet eine **klar gekennzeichnete lokale Demo**. Änderungen bleiben im Browser gespeichert. Andere Geräte teilen diese Daten nicht. Die Demo enthält Beispielprodukte; die echte Datenbank startet ohne Produkte. Demodaten werden nicht automatisch in Supabase übertragen.

```powershell
npm test
npm run build
npm run preview
```

`dist/` ist der Produktionsbuild. Installation und Service Worker sind im Produktionsbuild aktiv; der Entwicklungsserver verwendet keinen Service Worker. `index.html` nicht per Doppelklick öffnen.

## Supabase einmalig einrichten

1. Ein eigenes Supabase-Projekt anlegen. Die SQL-Datei `supabase/001_schema.sql` **einmal vollständig** im SQL-Editor ausführen. Sie ist eine initiale Migration, kein wiederholt ausführbares Reset-Skript.
   Wenn `001_schema.sql` bereits ausgeführt wurde, für die Sortierung zusätzlich `supabase/002_reorder.sql` einmal ausführen.
2. Öffentliche Registrierung in den Auth-Einstellungen deaktivieren. Einen einzigen Benutzer mit E-Mail und starkem Passwort im Supabase-Dashboard anlegen und die E-Mail bestätigen. Diesen gemeinsamen Haushaltszugang auf allen Geräten verwenden. Keine anonymen Anmeldungen aktivieren.
3. Die Benutzer-UUID aus Auth → Users übernehmen und im SQL-Editor einsetzen:

```sql
insert into public.household_access (singleton, user_id)
values (true, 'HIER-DIE-UUID-DES-HAUSHALTSBENUTZERS');
```

Die Tabelle erlaubt genau einen Haushalt. **Nur dieser konkrete Auth-Benutzer** darf Daten lesen oder Aktionen ausführen. Ein beliebiger anderer angemeldeter Benutzer erhält keinen Zugriff.

4. `.env.example` nach `.env.local` kopieren und beide Werte setzen:

```dotenv
VITE_SUPABASE_URL=https://DEIN-PROJEKT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=DEIN-PUBLISHABLE-KEY
```

Der Publishable Key ist für Browser vorgesehen; alternativ funktioniert der ältere Anon Key. **Niemals** einen Secret Key oder Service-Role-Key eintragen. Passwort und Schlüssel nicht ins Repository committen. Den Entwicklungsserver nach Änderungen an `.env.local` neu starten. Wenn beide Variablen gesetzt sind, erscheint statt der Demo die Anmeldung.

5. In der Realtime-Publication `supabase_realtime` müssen `locations`, `groups`, `products`, `stock` und `shopping` enthalten sein. Die Migration fügt sie hinzu. Die Anwendung lädt Daten nach Reconnect, Browser-Fokus und zusätzlich alle 30 Sekunden neu.

## Auf Vercel bereitstellen

1. Den Projektordner als privates GitHub-Repository hochladen (ohne `node_modules`, `dist`, `.env.local`).
2. In Vercel dieses Repository importieren, Framework „Vite“, Build `npm run build`, Ausgabe `dist`.
3. Beide `VITE_SUPABASE_*`-Variablen in Vercel für die gewünschten Umgebungen setzen. Sie werden beim Build eingesetzt. Nach jeder Änderung neu deployen.
4. Die endgültige HTTPS-Adresse in den Supabase-Auth-URL-Einstellungen als Site URL eintragen. Passwort-Anmeldung benötigt keine Redirect-Seite.
5. Auf zwei Geräten anmelden und die unten genannten Live-Prüfungen durchführen. Danach Android: Browsermenü → App installieren; iPhone: Safari → Teilen → Zum Home-Bildschirm. Die lokale HTTP-Adresse ist keine Installation für andere Geräte.

`vercel.json` enthält Sicherheitsheader und eine Content Security Policy für Standard-Supabase-Domains. Bei einer eigenen Supabase-Domain `connect-src` entsprechend ergänzen. Es werden keine externen Schriftarten, Analyse-Dienste oder KI-Dienste verwendet.

## Verhalten

- Produkte bleiben bei Bestand 0 in der Bibliothek. Erneutes Hinzufügen setzt ihren Standardlagerort. Vorhandene Bestände behalten ihren Lagerort.
- Bei Bestand 0 erscheint die Einkaufsnachfrage nur, wenn kein aktiver Eintrag für dieselbe Produkt-ID vorliegt.
- Mengen sind ganze Zahlen von 0 bis 1.000.000, auf der Einkaufsliste mindestens 1. Es gibt keine Mindestbestände.
- Gruppenübersichten zählen unterschiedliche vorhandene Produkte im gewählten Lagerort, unabhängig von deren Mengen. Ein Produkt kann mehreren Produktgruppen angehören, zum Beispiel „Gouda“ gleichzeitig „Milchprodukte“ und „Aufschnitt“. Die Zuordnung lässt sich in den Einstellungen über „Produkte bearbeiten“ direkt aus jeder Gruppe heraus ändern.
- Ein Produkt auf der aktiven Einkaufsliste wird beim erneuten Auswählen bearbeitet, nicht dupliziert.
- Die Einkaufsliste hat einen Quick-Add-Modus. Nach dem Aktivieren erscheint direkt unter der Liste ein Eingabefeld; Enter oder „Hinzufügen“ legt bekannte Produkte sofort mit Menge 1 auf die Liste. Neue Namen werden als Produkt gespeichert und ebenfalls mit Menge 1 hinzugefügt; vorher wird der Lagerort ausgewählt. Eine eindeutige Produktgruppe wird vorgeschlagen, bei unklaren Namen erscheint eine kleine optionale Gruppenauswahl.
- Die Produktbibliothek kann nach zuletzt hinzugefügten Produkten, Namen oder Lagerort sortiert werden.
- Neue Produkte lassen sich direkt aus der Einkaufsliste mit Anfangsbestand 0 erstellen.
- Einkaufsabschluss fragt nach der tatsächlichen Menge und bietet „nur erledigt“ oder „zum Bestand“.
- **Rückgängig öffnet einen Einkauf erneut, ohne den Bestand zurückzubuchen.** Das Flag `stock_applied` verhindert eine zweite Einbuchung desselben Einkaufs, auch nach Rückgängig. Für einen späteren neuen Einkauf einen neuen aktiven Eintrag anlegen.
- Lagerorte zeigen in den Einstellungen ebenfalls „Produkte bearbeiten“. Aktive Bestände können dort direkt in den gewählten Lagerort verschoben werden; der Standardlagerort des Produkts bleibt unverändert. Lagerorte mit Standardzuweisungen oder aktivem Bestand lassen sich nicht löschen. Zuerst Produkte verschieben und Standardlagerorte bearbeiten. Löschen einer Gruppe entfernt alle ihre Zuordnungen, die Produkte bleiben gespeichert.
- Lagerorte und Produktgruppen können in den Einstellungen mit Pfeilen nach oben und unten sortiert werden.
- Löschen eines Produktes ist erst ohne Bestand und ohne aktive Einkaufsposition erlaubt; erledigte Einkaufspositionen dieses Produktes werden dabei ebenfalls entfernt.
- Offline erscheint ein Hinweis. Im Haushaltsbetrieb werden keine Offline-Schreibvorgänge gepuffert; die App lädt nach Rückkehr der Verbindung erneut. Die Demo speichert lokal.

## Daten- und Sicherheitsarchitektur

`products`, `stock`, `locations`, `groups`, `shopping` sind getrennte Tabellen. RLS ist auf allen Tabellen aktiviert. Der Browser besitzt nur Leserechte auf Fachtabellen; alle Schreibaktionen laufen über `pantry_command(request_id, command)`.

Die Datenbankfunktion prüft die konkrete Haushalts-UUID, verwendet einen leeren `search_path` und sperrt für jede Änderung die einzige Haushaltszeile. Dadurch werden die wenigen Schreibaktionen eines Haushalts bewusst serialisiert. Mengenänderungen verwenden relative Updates. Checkout und Bestandseinbuchung erfolgen in derselben Transaktion. Ein partieller Unique-Index verhindert zwei aktive Einkaufspositionen für ein Produkt. Fremdschlüssel und CHECK-Constraints schützen Zuordnungen und Mengen.

Aktions-UUIDs in `command_receipts` machen eine Wiederholung derselben RPC-Anfrage idempotent. Bei einem Verbindungsfehler verwendet „Erneut versuchen“ dieselbe UUID. Die Belege bleiben gespeichert; für einen privaten Haushalt ist das klein, der Datenbankverbrauch sollte trotzdem beobachtet werden. Keine automatischen Wiederholungen mit neuen IDs verwenden.

Der schlanke Service Worker speichert nur eine öffentliche Offline-Hinweisseite, keine Haushaltsdaten oder Tokens. Ein erneuter App-Start ohne Netz zeigt diese Seite; vollständige Offline-Verwaltung ist nicht vorgesehen.

Supabase verwaltet die Anmeldung mit dauerhaft gespeicherter Sitzung und Token-Erneuerung im Browser. Die Tokens liegen im lokalen Browserspeicher, nicht in einem HttpOnly-Cookie. Geräte daher mit Bildschirmsperre schützen; die CSP reduziert ausführbare Fremdskripte. Die App enthält kein Passwort, keinen Server-Schlüssel und keine öffentliche Registrierung. „Dieses Gerät abmelden“ entfernt die Sitzung. Für einen verlorenen Zugriff die Sitzungen des gemeinsamen Accounts im Auth-System widerrufen.

## Tests und verbleibende Live-Prüfungen

`npm test` führt 12 Tests aus. Die echte SQL-Migration wird in PGlite (PostgreSQL als WASM) ausgeführt; nur die Supabase-Auth-Umgebung wird minimal nachgebildet und die Realtime-Publication-Zeile ausgelassen. Geprüft werden Mengen, Nullbestand, Standardlagerort, Aktionswiederholungen, Unique-Einkäufe, Checkout, Rückgängig, Löschschutz und Autorisierung. Parallel gestartete Testaufrufe werden von PGlite seriell abgearbeitet: Das ersetzt **keinen Test mit mehreren echten PostgreSQL-Verbindungen**.

Im integrierten Browser wurden Desktop- und schmale Smartphone-Ansicht sowie Aufbrauchen → Einkaufsnachfrage → bestätigter Einkauf, Statuswechsel und Lagerortwechsel geprüft. Der Produktionsbuild und Bereitstellung des Service Workers sind erfolgreich. Es bestehen keine beobachteten Browser-Konsolenfehler.

Nach Einrichtung unbedingt noch prüfen:

1. Zwei Geräte ändern denselben Bestand gleichzeitig: beide Änderungen müssen erhalten bleiben.
2. Zwei Geräte schließen denselben Einkauf ab: der Bestand darf nur einmal steigen.
3. Ein zweiter, nicht erlaubter Auth-Account darf weder lesen noch RPCs ausführen; anonyme Zugriffe ebenfalls nicht.
4. Netzwerk trennen und wieder verbinden: verständlicher Hinweis, keine Offline-Buchung, anschließender Abgleich.
5. Android-/iOS-PWA installieren, öffnen, Sitzungserneuerung und Realtime-Reconnect testen.

Echte Supabase-Authentifizierung, gehostetes Realtime, Vercel-Deployment und physische Mobilgeräte wurden mangels eingerichteter Projekte noch nicht getestet.

## Kostenrahmen (geprüft am 10.11.2026)

Supabase Free nennt 500 MB Datenbank, 5 GB Egress, 50.000 monatlich aktive Benutzer und zwei aktive Projekte; inaktive Projekte werden nach einer Woche pausiert. Realtime Free umfasst zwei Millionen Nachrichten pro Monat. Für einen privaten Haushalt erscheint dieser Umfang ausreichend, ohne eine Kostengarantie. Nutzung im Dashboard überwachen und Tarifbedingungen vor Einrichtung erneut prüfen. Quellen: [Supabase Pricing](https://supabase.com/pricing), [Realtime Pricing](https://supabase.com/docs/guides/realtime/pricing), [Realtime Limits](https://supabase.com/docs/guides/realtime/limits).

Vercel Hobby ist für private, nichtkommerzielle Nutzung vorgesehen; die beschriebene Haushaltsnutzung passt dazu. Keine kostenpflichtigen Tarife oder Zusatzdienste wurden eingerichtet. Quelle: [Vercel Hobby](https://vercel.com/docs/plans/hobby).

Technische Referenzen: [Supabase Passwort-Anmeldung](https://supabase.com/docs/reference/javascript/auth-signinwithpassword), [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).
