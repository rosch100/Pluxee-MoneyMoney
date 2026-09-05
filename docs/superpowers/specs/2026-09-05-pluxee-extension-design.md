# Pluxee — MoneyMoney Extension Design

Datum: 2026-09-05
Version: **1.00**

Status: **Release 1.00 (DE Live)** — OIDC E-Mail/hCaptcha/OTP inkl. OAuth-`state`,
Konto pro Benefit (`maskedPan`), BFF Saldo + Umsätze (Pagination `toDate`, ohne
`fromDate`=since, nur `APPROVED`). Offline-Tests grün.

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
| Lieferumfang | Spec + Implementierung + Tests; Release **1.00** |

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
| Version | `1.00` |

### Dateien

```text
Pluxee-MoneyMoney/
  Pluxee Benefits.lua
  README.md
  LICENSE
  link_ext.sh
  tests/
    test_conformance.py
    test_pluxee.lua
    fixtures/          # JSON/HTML-Snippets, keine Credentials/Tokens
  docs/superpowers/
    specs/2026-09-05-pluxee-extension-design.md
```

Hub-Updates: Zeile in Hub-`README.md`-Tabelle und Kurzabschnitt in
`docs/LUA-EXTENSIONS.md`.

## MoneyMoney-Vertragsfläche

- `WebBanking`: `services = {"Pluxee Benefits"}`, `url = "https://consumers.pluxee.de"`,
  `version = 1.00`, Dateiname `Pluxee Benefits.lua` (Title Case, identisch mit
  Service-Name; Marke + Produkttyp wie *Givve Prepaid* / *Amazon Bestellungen*)
  Beschreibung kurz (E-Mail/OTP, optional Passwort wenn Formular)
- `SupportsBank`: `ProtocolWebBanking` und BankCode/Service `Pluxee Benefits`
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
  `connection:getBaseURL()` wird nur übernommen, wenn der Host auf der Allowlist
  liegt.

### Kontomodell

- **v1 Default:** ein MoneyMoney-Konto **pro Benefit** in
  `GET /v2/de/cards` → je Eintrag in `card.benefits[]` (Live-Befund 2026-09-05:
  Portal listet Karten; bei `benefits.length > 1` expandiert die SPA zu
  `MultiBenefitItem`s; Umsätze tragen `splitData[].uniqueWalletId` = `benefitId`).
- Mehrere Karten und/oder mehrere Benefits → mehrere Konten in `ListAccounts`.
- Typ: Prepaid-/Benefit-Karte — `AccountTypeCreditCard` (MoneyMoney hat keinen
  eigenen Prepaid-Typ; analog givve Card)
- Währung: EUR (aus Benefit-`amount.currency`, erwartet `EUR`)
- Kontonummer: API-`card.maskedPan` unverändert (Live z. B. `XXXX 6138`).
  Mehrere Benefits mit gleicher `maskedPan` → Suffix ` ` + `benefitId-lower`
  zur Eindeutigkeit. Legacy-Nummern (`pluxee.<benefitId-lower>`, `····last4`)
  werden beim Lookup weiter erkannt.
- Anzeigename: ein Konto → `{benefit.name}` (Fallback `card.name`);
  mehrere Konten → `{benefit.name} {panLastFour}` (ohne Klammern/Punkte).
- Saldo: genau dieses Benefit-`amount` (nicht Summe aller Benefits der Karte;
  Portal-Zeile zeigt ebenfalls `benefits[0]`, Detailzeilen je Benefit).
- Umsätze: `GET …/cards/{cardId}/transactions?limit=99` (+ optional `benefitId`,
  Folgeseiten per `toDate=YYYY-MM-DD`); **kein** `fromDate` aus MoneyMoney-`since`
  (schneidet Historie ab und löst MM-Warnung „ältere Umsätze…“ aus).
  Nur Buchungen mit `splitData[].uniqueWalletId == benefitId`; Betrag nur aus
  `splitAmount`. Nur Status `APPROVED` importieren (`DECLINED`/`OTHER`/ohne Status
  verwerfen). Fehlt `splitAmount` trotz Match → Buchung verwerfen (explizit, kein Fake).
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
       hCaptcha (Interactive) → E-Mail-POST mit h-captcha-response
       Passwortfeld vorhanden? → credentials[2] setzen
       OTP-Schritt → ggf. Resend (+ Captcha) → Interactive(E-Mail-Code)
       Callback: code + state (state muss session.oauthState matchen)
       code → token (access + refresh) speichern
  → Session-State serialisierbar (Tokens/Strings), keine Connection-Userdata

ListAccounts
  → GET /v2/de/cards (Bearer + APIM-Key)
  → je Benefit (über alle Karten) ein Account (Name, Nummer, Saldo, Typ)
  → Session-Map accountNumber → { cardId, benefitId }

RefreshAccount
  → Lookup cardId/benefitId aus Session-Map (inkl. Legacy-Nummern)
  → GET /v2/de/cards/{cardId}/transactions?limit=99&benefitId=…
  → bei voller Seite weitere Requests mit toDate (ältestes Datum), ohne fromDate
  → Filter: benefitId via splitData; nur APPROVED; Mapping bookingKey/date/amount
  → MoneyMoney-since nicht als API-fromDate (volle Portal-Historie, MM dedupliziert)

EndSession
  → bei persistierter Map keinen Remote-Logout; Bucket behalten
```

### Auth-Details

OIDC (Discovery `https://connect.pluxee.app/op/.well-known/openid-configuration`):

| Parameter | Wert (DE SPA, Live) |
| --- | --- |
| `client_id` | `bf400a61-2659-4269-9363-ebd2029adaa2` |
| `redirect_uri` | `https://consumers.pluxee.de/oidc/callback` |
| `response_type` | `code` |
| `scope` | `openid profile email` (+ `offline_access` wenn Token-Endpoint liefert) |
| PKCE | `S256` |
| `state` | Session-Wert; Pflicht-Match vor Token-Tausch |
| authorize | `https://connect.pluxee.app/op/oidc/auth` |
| token | `https://connect.pluxee.app/op/oidc/token` |

Login-UI-Schritte:

1. E-Mail eingeben und absenden (passwordless-Pfad bevorzugen).
2. **Captcha** → MoneyMoney-Interactive mit offizieller hCaptcha-Script-URL
   (`sitekey` + `referer` aus der Login-Seite); Token in `credentials[1]`, dann
   Form-POST mit `h-captcha-response`. Fehlt der Site-Key → expliziter Fehler.
3. Erscheint ein **Passwortfeld** → mit `credentials[2]` befüllen und absenden.
4. Erscheint **OTP/E-Mail-Code** → ggf. Resend (JSON, ggf. Captcha);
   `MM.interactive` / Challenge; Code absenden.
5. Callback-URL: Authorization-`code` aus `connection:getBaseURL()` (nicht SPA-HTML);
   `state` gegen `session.oauthState` prüfen.

Credential rejection: falsche E-Mail / OTP / Passwort über Marker in
Antworttext/`error` → `LoginFailed` (analog givve Card); Netzwerk/Parse:
explizite Fehlermeldung; kein stiller Fallback, keine Dummy-Salden.

OTP-`interactionId` nur `[%w%-]+` (≤128); `opUrl` nur Allowlist-Hosts,
sonst Default `CONSTANTS.oidcAuthority`.

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
| Umsätze | `GET /v2/de/cards/{cardId}/transactions?limit=1..99` (+ `benefitId`, Folgeseiten `toDate`; **kein** `fromDate`=since) |
| optional Meta | `GET /v2/de/consumer/cards/{cardId}/consumerInfo` |

Betragsmodell: `{ "value": <int>, "exponent": 2, "currency": "EUR" }` —
Anzeigebetrag = `value / 10^exponent`. Transaktions-`value` ist bereits
vorzeichenbehaftet (DEBIT negativ).

### Session / Multi-Login

Folgt der Hub-/Sibling-Konvention **Multi-Login LocalStorage** wie givve Card
(`connectionsByAccount[accountKey]`).

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
| Captcha / nicht automatisierbar | MM-hCaptcha-Challenge; bei Fehlschlag expliziter Fehler |
| OAuth state mismatch / fehlt | Expliziter Fehler; kein Token-Tausch |
| Session / Token abgelaufen mid-sync | Refresh oder Re-Login; kein Fake-Erfolg |
| Parse / Netzwerk / unerwartetes JSON | Fehlerstring an MoneyMoney; kein 0-Saldo als Erfolg |
| Leere Kartenliste | Klarer Fehler oder leere Account-Liste laut Engine-Konvention — kein Dummy-Konto |

## Tests

- `test_conformance.py`: Pflicht-Hooks / WebBanking-Metadaten (`Pluxee Benefits`, version `1.00`, url)
- `test_pluxee.lua`: OTP-Pfad-Erkennung, Passwortfeld-Zweig, Captcha, OAuth-state,
  `interactionId`/`opUrl`-Validierung, Wallet-/Transaktions-Parser gegen Fixtures
- Keine echten Secrets, Tokens, vollständigen PANs oder Personen-PII in Fixtures

## Live-Befund Login (2026-09-05)

- Login-UI: `…/op/interaction/{id}/login` → Form `action=login-submission`,
  Feld `name="login"` (E-Mail), Button Weiter
- **Invisible hCaptcha** ist aktiv (`hcaptchaEnabled`, Site-Hinweis auf der Seite).
  Der SPA-Submit führt vor dem POST `hcaptcha.execute` aus und hängt
  `h-captcha-response` an das Formular.
- Plugin-Verhalten: Site-Key aus der Seite lesen → MoneyMoney-Captcha-Challenge
  (`https://js.hcaptcha.com/1/api.js?sitekey=…&referer=…`) → Token → E-Mail-POST.
- Nach OTP/Consent: Authorization-`code` in der finalen Callback-URL
  (`getBaseURL`), nicht im SPA-HTML-Body.
- Token-Reuse bleibt für bereits gespeicherte Sessions.

## Offene Punkte (kein Release-Blocker)

- Ob `offline_access` / Refresh für den DE-Client zuverlässig geliefert wird
- Ob eine künftige Engine-API Captcha/JS-Login erlaubt (dann Auth-Pfad nachziehen)
