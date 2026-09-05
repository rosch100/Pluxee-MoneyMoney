# Pluxee Benefits — MoneyMoney-Erweiterung

Pluxee-Benefits (Saldo und Umsätze) in MoneyMoney.

Version: **1.00**
Repository: https://github.com/rosch100/Pluxee-MoneyMoney
Gemeinsame Infos: https://github.com/rosch100/moneymoney-extensions

## Installation

Unsignierte Datei:
[Pluxee Benefits.lua](https://raw.githubusercontent.com/rosch100/Pluxee-MoneyMoney/main/Pluxee%20Benefits.lua)

Datei nach
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
**kopieren** (keine Hardlinks — die Sandbox lädt sie oft nicht), oder im Klon
`./link_ext.sh` ausführen. Danach MoneyMoney neu starten.

Unsignierte Plugins: MoneyMoney-**Beta**, Signaturprüfung unter
*MoneyMoney → Einstellungen → Erweiterungen* ausschalten.

## Einrichten

*Konto hinzufügen* → *Andere* (nicht IBAN/BLZ) → **Pluxee Benefits**.

Benutzername = E-Mail. Passwort nur setzen, wenn das Portal danach fragt;
sonst kann das Feld leer bleiben. Captcha und E-Mail-Code erscheinen bei Bedarf
in MoneyMoney — den Code aus der E-Mail eingeben.

Mehrere Logins: je einen Bankzugang mit eigener E-Mail anlegen.

## Nutzung

Jeder Benefit erscheint als eigenes Konto. Bei mehreren Benefits mit gleicher
Kartennummer unterscheidet MoneyMoney sie anhand des Namens bzw. der letzten
Ziffern.

Nur bestätigte Umsätze werden übernommen. Spätere Abrufe nutzen die gespeicherte
Anmeldung, bis erneut Captcha oder Code nötig sind.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
