# Pluxee Benefits — MoneyMoney Extension

Plugin Homepage: https://github.com/rosch100/Pluxee-MoneyMoney

Portal: https://consumers.pluxee.de (OIDC: connect.pluxee.app, API: api.pluxee.app)

Version: **1.00**

Status: E-Mail / hCaptcha / OTP (Passwort nur wenn Formular); Konto pro Benefit; BFF Saldo + Umsätze

Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

## Installation

Unsignierte Datei: [Pluxee Benefits.lua](https://raw.githubusercontent.com/rosch100/Pluxee-MoneyMoney/main/Pluxee%20Benefits.lua)

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
**kopieren** (keine Hardlinks — die Sandbox lädt sie oft nicht), oder im Klon
`./link_ext.sh` ausführen (legt eine echte Kopie an). Danach MoneyMoney neu starten.

Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* **ausschalten**.

In MoneyMoney: **Konto → Konto hinzufügen → Andere** (nicht IBAN/BLZ) →
**Pluxee Benefits** wählen. Service-Name und Dateiname sind absichtlich
*Pluxee Benefits* (Marke + Produkttyp), analog *Givve Prepaid* / *Amazon Bestellungen*.
Benutzername = E-Mail.
Passwort nur setzen, wenn das Portal ein Passwortfeld zeigt; sonst kann das Feld leer bleiben.
Bei OTP den Code aus der E-Mail in die Challenge eingeben.

## Login / hCaptcha / OTP

Der Connect-Login nutzt **invisible hCaptcha**. Das Plugin startet die
MoneyMoney-Captcha-Challenge (Site-Key aus der Login-Seite) und sendet das Token
als `h-captcha-response` mit dem E-Mail-POST. Danach folgen optional Passwort und
E-Mail-OTP. OTP-Resend kann erneut Captcha verlangen.
Gespeicherte Tokens (LocalStorage) werden für Folgesyncs wiederverwendet
(Refresh; sonst erneuter Login). OAuth-`state` und Host-Allowlist schützen den
Callback- und Request-Pfad.

## Konten / Umsätze

Je Benefit ein MoneyMoney-Konto:

- Kontonummer = API-`maskedPan` (z. B. `XXXX 6138`); bei gleicher PAN mehrerer
  Benefits Suffix ` ` + `benefitId` (klein)
- Name bei einem Konto `{Benefit-Name}`, bei mehreren `{Benefit-Name} {last4}`
- Saldo = Benefit-Betrag; Typ Kreditkarte (MoneyMoney-Prepaid-Konvention)
- Umsätze: nur Status `APPROVED`, gefiltert nach `benefitId`; Pagination per
  `toDate` (kein `fromDate` aus MoneyMoney-`since`)

Mehrere Logins: je Bankzugang mit eigener E-Mail.

## Tests

```sh
test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py
lua tests/test_pluxee.lua
```

Aus dem Repo-Root ausführen. Design:
[docs/superpowers/specs/2026-09-05-pluxee-extension-design.md](docs/superpowers/specs/2026-09-05-pluxee-extension-design.md).

## Lizenz

MIT — siehe [LICENSE](LICENSE).
