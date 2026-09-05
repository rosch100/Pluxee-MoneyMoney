# Pluxee — MoneyMoney Extension
Plugin Homepage: https://github.com/rosch100/Pluxee-MoneyMoney
Portal: https://consumers.pluxee.de (OIDC: connect.pluxee.app, API: api.pluxee.app)
Version: **0.91** Beta
Status: E-Mail/OTP (Passwort nur wenn Formular); **Konto pro Benefit**; BFF Saldo + Umsätze
Hub (gemeinsame Tools/Doku): https://github.com/rosch100/moneymoney-extensions

## Installation
Unsignierte Datei: [Pluxee.lua](https://raw.githubusercontent.com/rosch100/Pluxee-MoneyMoney/main/Pluxee.lua)
Datei nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions` kopieren, oder im Klon `./link_ext.sh` ausführen.
Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung in den Erweiterungseinstellungen aus.

In MoneyMoney Bankzugang anlegen: Bank **Pluxee**, Benutzername = E-Mail.
Passwort nur setzen, wenn das Portal ein Passwortfeld zeigt; sonst kann das Feld leer bleiben.
Bei OTP den Code aus der E-Mail in die Challenge eingeben.

## Hinweis Login / hCaptcha
Der Connect-Login (E-Mail-Schritt) nutzt **invisible hCaptcha**. MoneyMoney-Lua kann
dieses Captcha nicht lösen — der Erstlogin schlägt dann mit einer klaren
Fehlermeldung fehl. Gespeicherte Tokens (LocalStorage nach erfolgreicher Session)
werden für Folgesyncs wiederverwendet, inkl. Refresh soweit der Client
`offline_access` liefert.

## Konten / Multi-Login
Je Benefit ein MoneyMoney-Konto: Nummer `pluxee.<benefitId-lower>`, Name
`{Benefit-Name} (····last4)`. Mehrere Karten oder mehrere Benefits auf einer
Karte → mehrere Konten. Mehrere Logins: je Bankzugang mit eigener E-Mail.

## Tests
```sh
test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py
luajit tests/test_pluxee.lua
```
Aus dem Repo-Root ausführen.

## Lizenz
MIT — siehe [LICENSE](LICENSE).
