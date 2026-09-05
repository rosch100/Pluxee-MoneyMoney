# Pluxee — MoneyMoney Extension Design

Datum: 2026-09-05

Status: **Teil-Implementiert** — Parser/Hooks/Konto-pro-Benefit/Captcha-Gate;
OIDC-Form-POSTs (E-Mail/Passwort/OTP/Token) verdrahtet; Erstlogin durch
invisible hCaptcha auf Connect weiterhin blockiert (Live 2026-09-05; spezifiziert,
kein Cookie-Fallback). Offline-Tests grün; Live-Smoke in MoneyMoney empfohlen.

## Ziel

Eigenes Repository und MoneyMoney-Web-Banking-Extension für das
**Pluxee Consumer-Portal Deutschland** (`https://consumers.pluxee.de/`):
Login mit E-Mail und E-Mail-OTP (Passwort nur wenn das Portal ein Passwortfeld
zeigt), Saldo und Umsätze der Benefits Card in MoneyMoney.

## Kontext

- Hub: [moneymoney-extensions](https://github.com/rosch100/moneymoney-extensions)
- Sibling-Muster: `*-MoneyMoney` als Nested-Git-Repos unter dem Hub,
  Remote unter `rosch100` auf GitHub
- Portal: `https://consumers.pluxee.de/` (Wallet SPA)
- Identity: `https://connect.pluxee.app/op/` (OIDC Authorization Code + PKCE)
- API: `https://api.pluxee.app/gl/eva/bff/` (Bearer + APIM-Subscription-Key)
- Live-Befund Browser 2026-09-05 (eingeloggte DE-Session): Wallet, Karte,
  Transaktionen über BFF bestätigt
- Kein Business-/Employer-Portal in v1; nur Consumer DE

## Entscheidungen (bestätigt)

| Thema | Entscheidung |
| --- | --- |
| Ansatz | Sibling-Repo + OIDC/PKCE + BFF-JSON (nicht HTML-Scraping der SPA) |
| Auth | A: E-Mail + E-Mail-OTP via MoneyMoney-Interactive; **wenn** das Portal ein Passwortfeld zeigt, mit `credentials[2]` befüllen |
| Cookie-Import | Nicht Hauptweg in v1 (kein Fallback als stiller Ersatz für OTP) |
| Scope | DE Consumer: Saldo + Umsätze, **Konto pro Benefit** |
| Lieferumfang Session | Scaffold + Spec/Plan + Implementierung in derselben Lieferkette |

## Nicht-Ziele (v1)

- Andere Länder als DE (`consumers.pluxee.at` etc.)
- Kartenaktivierung, PIN, Sperren, Benefit hinzufügen
- Cookie-/Callback-URL-Import als primärer Login
- App-Push / Biometrie / WebAuthn
- Employer-/Client-Portal
- Gemeinsames Lua-Modul im Hub

## Repository

| Feld | Wert |
| --- | --- |
| Lokaler Pfad | `MoneyMoney/Pluxee-MoneyMoney/` |
| GitHub | `https://github.com/rosch100/Pluxee-MoneyMoney` |
| Lizenz | MIT |
| Startversion | `0.91` (Beta), später `1.0x` wenn Login+Sync stabil |

### Dateien

```text
Pluxee-MoneyMoney/
  Pluxee.lua
  README.md
  LICENSE
  link_ext.sh
  tests/
    test_conformance.py
    test_pluxee.lua
    fixtures/          # JSON-Snippets, keine Credentials/Tokens
  docs/superpowers/
    specs/2026-09-05-pluxee-extension-design.md
    plans/             # nach writing-plans
```

Hub-Updates nach Repo-Create: Zeile in Hub-`README.md`-Tabelle und Kurzabschnitt
in `docs/LUA-EXTENSIONS.md`.

## MoneyMoney-Vertragsfläche

- `WebBanking`: `services = {"Pluxee"}`, `url = "https://consumers.pluxee.de"`,
  `version = 0.91`, Beschreibung kurz (E-Mail/OTP, optional Passwort wenn Formular)
- `SupportsBank`: `ProtocolWebBanking` und BankCode/Service `Pluxee`
- Hooks: `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`
- Credentials:
  - `[1]` = E-Mail (Pflicht)
  - `[2]` = Passwort — **nur** an das Portal senden, wenn ein Passwortfeld
    erscheint; sonst nicht als Login-Faktor erzwingen. MoneyMoney kann das Feld
    UI-seitig trotzdem verlangen; leerer String ist erlaubt, solange der
    OTP-Pfad greift.
- Host-Allowlist (Live 2026-09-05):
  - `consumers.pluxee.de`
  - `connect.pluxee.app`
  - `api.pluxee.app`
  Weitere Hosts nur nach neuem Live-Befund + Tests.

### Kontomodell

- **v1 Default:** ein MoneyMoney-Konto **pro Benefit** in
  `GET /v2/de/cards` → je Eintrag in `card.benefits[]` (Live-Befund 2026-09-05:
  Portal listet Karten; bei `benefits.length > 1` expandiert die SPA zu
  `MultiBenefitItem`s; Umsätze tragen `splitData[].uniqueWalletId` = `benefitId`).
- Mehrere Karten und/oder mehrere Benefits → mehrere Konten in `ListAccounts`.
- Typ: Prepaid-/Benefit-Karte — `AccountTypeCreditCard` (MoneyMoney hat keinen
  eigenen Prepaid-Typ; analog givve Card)
- Währung: EUR (aus Benefit-`amount.currency`, erwartet `EUR`)
- Kontonummer: `pluxee.<benefitId-lower>` (stabil, eindeutig, ohne PAN-Secret).
  Beispiel: `benefitId` `DEUGF2UW0P9TQ7UCYTEURH0` →
  `pluxee.deugf2uw0p9tq7ucyteurh0`.
- Anzeigename: `{benefit.name} (····{card.panLastFour})` — Fallback
  `benefit.name` bzw. `card.name`, wenn Last4 fehlt.
- Saldo: genau dieses Benefit-`amount` (nicht Summe aller Benefits der Karte;
  Portal-Zeile zeigt ebenfalls `benefits[0]`, Detailzeilen je Benefit).
- Umsätze: `GET …/cards/{cardId}/transactions`, dann nur Buchungen mit
  `splitData[].uniqueWalletId == benefitId`; Betrag ausschließlich aus dem
  passenden `splitAmount` (kein stiller Fallback auf Tx-Gesamtbetrag).
  Fehlt `splitAmount` trotz Match → Buchung verwerfen (explizit, kein Fake).
- Keine Dummy-Umsätze; leere Transaktionsliste ist gültig

Verworfen: ein Konto pro Karte (vermischt Benefits); ein Konto nur nach E-Mail.

## Architektur

```text
InitializeSession2
  → Connection + LocalStorage.connectionsByAccount[accountKey]
  → accountKey = normalizeEmail(credentials[1])
  → gültigen Refresh-/Access-Token aus Map wiederverwenden (ohne Re-Login)
  → sonst OIDC Authorization Code + PKCE:
       authorize → Login-UI Connect
       E-Mail setzen → weiter
       Passwortfeld vorhanden? → credentials[2] setzen
       OTP-Schritt → Interactive(E-Mail-Code) → absenden
       Captcha/Blocker → klarer Fehler (kein stiller Fallback, kein Fake-Login)
       code → token (access + refresh) speichern
  → Session-State serialisierbar (Tokens/Strings), keine Connection-Userdata

ListAccounts
  → GET /v2/de/cards (Bearer + APIM-Key)
  → je Benefit (über alle Karten) ein Account (Name, Nummer, Saldo, Typ)
  → Session-Map accountNumber → { cardId, benefitId }

RefreshAccount
  → Lookup cardId/benefitId aus Session-Map
  → GET /v2/de/cards/{cardId}/transactions?limit=…
  → Filter auf benefitId via splitData.uniqueWalletId
  → Mapping: date, splitAmount/amount, merchantName/description, bookingKey
  → since-Filter clientseitig bzw. Limit; Pagination nur nach Live-Befund

EndSession
  → bei persistierter Map keinen Remote-Logout; Bucket behalten
```

### Auth-Details (Live nachziehen, Spec-Rahmen)

OIDC (Discovery `https://connect.pluxee.app/op/.well-known/openid-configuration`):

| Parameter | Wert (DE SPA, Live) |
| --- | --- |
| `client_id` | `bf400a61-2659-4269-9363-ebd2029adaa2` |
| `redirect_uri` | `https://consumers.pluxee.de/oidc/callback` |
| `response_type` | `code` |
| `scope` | `openid profile email` (+ `offline_access` wenn Token-Endpoint liefert) |
| PKCE | `S256` |
| authorize | `https://connect.pluxee.app/op/oidc/auth` |
| token | `https://connect.pluxee.app/op/oidc/token` |

Login-UI-Schritte (Reihenfolge verbindlich für Implementierung; exakte
Feldnamen/CSRF beim ersten Live-Login festnageln — nicht raten):

1. E-Mail eingeben und absenden (passwordless-Pfad bevorzugen).
2. Erscheint ein **Passwortfeld** → mit `credentials[2]` befüllen und absenden.
3. Erscheint **OTP/E-Mail-Code** → `MM.interactive` / Challenge; Code absenden.
4. **Captcha** oder nicht automatisierbarer Schritt → Session abbrechen mit
   expliziter Fehlermeldung an MoneyMoney (z. B. dass Login im Plugin blockiert
   ist). Kein Cookie-Import als stiller Ersatz in v1; kein leerer Erfolg.

Credential rejection: falsche E-Mail / OTP / Passwort über Marker in
Antworttext/`error` → `LoginFailed` (analog givve Card); Netzwerk/Parse:
explizite Fehlermeldung; kein stiller Fallback, keine Dummy-Salden.

### API (Live 2026-09-05)

Basis: `https://api.pluxee.app/gl/eva/bff`

Header:

- `Authorization: Bearer <access_token>`
- `ocp-apim-subscription-key: <key aus SPA-Config>` — Key ist im öffentlichen
  SPA-Bundle enthalten; im Plugin als Konstante aus demselben Live-Befund,
  kein Secret aus User-Daten. Wechsel nur nach neuem Live-Befund.
- `Accept: application/json`

| Zweck | Request |
| --- | --- |
| Wallet / Karten + Saldo | `GET /v2/de/cards` → `getWallet1` |
| Umsätze | `GET /v2/de/cards/{cardId}/transactions?limit=N` |
| optional Meta | `GET /v2/de/consumer/cards/{cardId}/consumerInfo` |

Betragsmodell: `{ "value": <int>, "exponent": 2, "currency": "EUR" }` —
Anzeigebetrag = `value / 10^exponent`. Transaktions-`value` ist bereits
vorzeichenbehaftet (DEBIT negativ).

### Session / Multi-Login

Folgt der Hub-/Sibling-Konvention **Multi-Login LocalStorage** wie givve Card
(`connectionsByAccount[accountKey]`). Die ausführliche Hub-Spec lag zum
Zeitpunkt dieser Spec nicht im lokalen Hub-Checkout; verbindlich ist das
givve-/Sibling-Muster im Code, nicht eine zweite parallele Spec hier.

- `accountKey` = volle E-Mail aus `credentials[1]`, lowercased und getrimmt
- Map-Eintrag: `accessToken`, `refreshToken`, `expiresAt` — nur serialisierbare
  Strings/Zahlen
- Reuse nur bei Key-Match; Token abgelaufen → Refresh; Refresh fehlgeschlagen
  → vollständiger Re-Login (+ OTP)
- Refresh-Token-Rotation: neueste Tokens zurück in LocalStorage schreiben
- Keine echten Tokens in Repo, Fixtures, Logs oder Spec-Beispielen

## Fehlerbehandlung

| Situation | Verhalten |
| --- | --- |
| Unbekannte E-Mail / falsches Passwort | Credential rejection |
| Falscher OTP | Challenge erneut oder klarer Fehler |
| Captcha / nicht automatisierbar | Expliziter Fehler; kein stiller Fallback |
| Session / Token abgelaufen mid-sync | Refresh oder Re-Login; kein Fake-Erfolg |
| Parse / Netzwerk / unerwartetes JSON | Fehlerstring an MoneyMoney; kein 0-Saldo als Erfolg |
| Leere Kartenliste | Klarer Fehler oder leere Account-Liste laut Engine-Konvention — kein Dummy-Konto |

## Tests

- `test_conformance.py`: Pflicht-Hooks / WebBanking-Metadaten (`Pluxee`, version, url)
- `test_pluxee.lua`: OTP-Pfad-Erkennung, Passwortfeld-Zweig, Captcha-Fail,
  Wallet-/Transaktions-Parser gegen Fixtures (anonymisierte JSON-Ausschnitte)
- Keine echten Secrets, Tokens, vollständigen PANs oder Personen-PII in Fixtures

## Lieferreihenfolge

1. Spec (dieses Dokument) + Implementation Plan (`writing-plans`)
2. Scaffold GitHub-Repo + Stub-`Pluxee.lua` + Tests grün
3. OIDC-Login: E-Mail → optional Passwort → OTP verdrahten (Live-Festnagelung)
4. Saldo + Umsätze über BFF + Hub-Doku

## Live-Befund Login (2026-09-05)

- Login-UI: `…/op/interaction/{id}/login` → Form `action=login-submission`,
  Feld `name="login"` (E-Mail), Button Weiter
- **Invisible hCaptcha** ist aktiv (`hcaptchaEnabled`, Site-Hinweis auf der Seite).
  Der SPA-Submit führt vor dem POST `hcaptcha.execute` aus. Ohne gelöstes
  Captcha ist der E-Mail-Schritt aus MoneyMoney-Lua **nicht** automatisierbar.
- Plugin-Verhalten: Captcha erkennen → **expliziter Fehler** (kein Cookie-
  Fallback, kein Fake-Login). Token-Reuse bleibt für bereits gespeicherte
  Sessions.

## Offene Punkte (nur Live, kein Spec-Blocker)

- Exakte CSRF-/Hidden-Felder und OTP-/Passwort-Seiten-HTML nach Captcha
- Pagination / `since`-Semantik der Transactions-API
- Ob `offline_access` / Refresh für den DE-Client zuverlässig geliefert wird
- Ob eine künftige Engine-API Captcha/JS-Login erlaubt (dann Auth-Pfad nachziehen)

## Conformity-Abgleich (Remediation 2026-09-05)

| Früheres Finding | Adressiert in |
| --- | --- |
| Keine Spec-Datei | dieses Dokument |
| Captcha/OIDC-Risiko unklar | Auth-Details + Fehlerbehandlung |
| Passwort-Semantik unklar | Credentials + Login-Schritte 1–3 |
| Hosts/API nicht fix | Host-Allowlist + API-Tabelle |
| Kontomodell offen | Kontomodell (pro Benefit, Live 2026-09-05) |
| Multi-Benefit-UI/API | Kontomodell + Architektur RefreshAccount |
| Session/Multi-Login offen | Session / Multi-Login |
| Hub-Registry | Lieferreihenfolge Schritt 4 |
| Secrets | Tests + Session (Verbot) |
