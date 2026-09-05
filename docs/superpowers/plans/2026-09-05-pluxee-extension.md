# Pluxee MoneyMoney Extension — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eigenes Repo `Pluxee-MoneyMoney` mit MoneyMoney-Extension für `consumers.pluxee.de`: E-Mail/OTP (Passwort nur wenn Formularfeld), Saldo + Umsätze der DE Benefits Card, Multi-Login-LocalStorage, Host-Allowlist.

**Architecture:** OIDC Authorization Code + PKCE gegen `connect.pluxee.app`; BFF JSON unter `api.pluxee.app/gl/eva/bff`. Invisible hCaptcha auf dem E-Mail-Schritt → expliziter Fehler (kein Cookie-Fallback). Token-Reuse + Refresh über `LocalStorage.connectionsByAccount`. TDD für Parser/Klassifikation offline; Form-POSTs erst nach Live-HTML ohne Captcha-Blocker verdrahten.

**Tech Stack:** LuaJIT (`luajit`), MoneyMoney WebBanking-Host-Globals, Python 3 (Repo-`.venv` wenn vorhanden) für Conformance, GitHub (`gh`) für Remote.

**Spec:** `docs/superpowers/specs/2026-09-05-pluxee-extension-design.md`

## Global Constraints

- Service/BankCode: `Pluxee`; URL `https://consumers.pluxee.de`; Version `0.91`.
- Credentials: `[1]` E-Mail (Pflicht); `[2]` Passwort **nur** wenn Passwortfeld erscheint; OTP via Interactive-Challenge (`title`/`challenge`/`label`).
- Host-Allowlist: `consumers.pluxee.de`, `connect.pluxee.app`, `api.pluxee.app`.
- OIDC DE-Client: `client_id=bf400a61-2659-4269-9363-ebd2029adaa2`, `redirect_uri=https://consumers.pluxee.de/oidc/callback`, PKCE S256, scopes `openid profile email offline_access`.
- BFF: `GET /v2/de/cards`, `GET /v2/de/cards/{cardId}/transactions?limit=N`; Header Bearer + `ocp-apim-subscription-key` (öffentlicher SPA-Key aus Live-Bundle).
- Kontonummer: `pluxee.<benefitId-lower>`; Anzeigename `{benefit.name} (····{last4})`; Typ `AccountTypeCreditCard`; Währung `EUR`.
- Ein MoneyMoney-Konto **pro Benefit** (`card.benefits[]`); Umsätze gefiltert über `splitData.uniqueWalletId`.
- `accountKey`: volle E-Mail lowercased+trimmed (mit `@`).
- Multi-Login: `LocalStorage.connectionsByAccount[accountKey]` (`accessToken`/`refreshToken`/`expiresAt`); keine Connection-Userdata persistieren.
- Captcha → `captchaBlockedMessage()`; kein stiller Fallback; keine Dummy-Salden; keine Secrets in Fixtures.
- Live-DE (2026-09-05): E-Mail-Schritt trägt hCaptcha → `classifyLoginHtml` liefert `"captcha"` vor `"email"`. E-Mail-POST (Task 2) gilt für Fixture/`hcaptchaEnabled=false`-Regression und für den Fall, dass Captcha entfällt — nicht als Captcha-Bypass.
- Commits ohne Cursor-Co-Author-Trailer; Plugin-Arbeit im Repo `Pluxee-MoneyMoney/`, Hub-Index separat.
- Tests aus Repo-Root:
  - `test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py`
  - `luajit tests/test_pluxee.lua`

## File map

| File | Role |
| --- | --- |
| `Pluxee.lua` | Extension: CONSTANTS, PKCE, Auth-Klassifikation, BFF-Parser, Hooks |
| `LICENSE` | MIT (wie Siblings) |
| `README.md` | Install, Auth, hCaptcha-Hinweis, Tests, Hub-Link |
| `link_ext.sh` | Hardlink nach MoneyMoney Extensions |
| `tests/test_conformance.py` | BOM/WebBanking/SupportsBank/Init-Hooks/Captcha-Gate |
| `tests/test_pluxee.lua` | Offline-Unit-Tests (dofile + Stubs) |
| `tests/fixtures/*.html` / `*.json` | Anonymisierte Login-/Wallet-/Tx-Snippets |
| `docs/superpowers/specs/2026-09-05-pluxee-extension-design.md` | Spec |
| `docs/superpowers/plans/2026-09-05-pluxee-extension.md` | Dieser Plan |
| Hub `README.md`, `docs/LUA-EXTENSIONS.md` | Index (Hub-Repo) |

## Baseline (bereits erledigt, 2026-09-05)

Nicht erneut implementieren — bei Re-Run nur Regression prüfen:

- [x] Repo-Gerüst: `LICENSE`, `README.md`, `link_ext.sh`, `.gitignore`, Spec, dieser Plan-Pfad
- [x] `Pluxee.lua`: WebBanking, Allowlist, PKCE, Captcha-Gate, Token-Map, BFF-Parser, **Konto pro Benefit**, Hooks
- [x] Fixtures + `tests/test_conformance.py` + `tests/test_pluxee.lua` grün
- [x] Hub-Index-Zeilen in `MoneyMoney/README.md` und `docs/LUA-EXTENSIONS.md`

**Regression:**

```sh
cd Pluxee-MoneyMoney
test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py
# Expected: CONFORMANCE OK
luajit tests/test_pluxee.lua
# Expected: test_pluxee OK
```

---

### Task 1: Konto pro Benefit (ListAccounts + Tx-Filter)

**Status:** erledigt im Code (2026-09-05) — Regression unten.

**Files:**
- Modify: `Pluxee.lua` (`accountNumberForBenefit`, `iterWalletBenefits`, `parseTransactionsPayload(..., benefitId)`, `ListAccounts`, `RefreshAccount`)
- Modify: `tests/test_pluxee.lua`, Spec/README
- Create: `tests/fixtures/wallet_two_benefits.json`; Update: `tests/fixtures/transactions.json` (`splitData`)

**Interfaces:**
- Consumes: `parseWalletCards`, `moneyAmountFromPluxee`
- Produces:
  - `accountNumberForBenefit(benefit)` → `pluxee.<benefitId-lower>`
  - `iterWalletBenefits(cards)` → `{ {card, benefit}, ... }`
  - `parseTransactionsPayload(payload, since, benefitId)` → nur Splits mit `uniqueWalletId == benefitId`
  - Session: `benefitsByAccountNumber[number] = { cardId, benefitId }`

- [x] **Steps 1–4:** Fixtures + Parser + Hooks + Tests
- [ ] **Step 5: Commit** (nur auf User-Wunsch; vorher `/codereview`)

**Regression:**

```sh
luajit tests/test_pluxee.lua
# Expected: multi.benefitRows=2, tx.count.benefit1=2, tx.count.benefit2=1
```

---

### Task 2: Login-Form-POST E-Mail (ohne Captcha-Bypass)

**Status:** erledigt im Code (2026-09-05).

**Files:**
- Modify: `Pluxee.lua` (`startOidcLogin`, `submitLoginEmail`, `extractFormAction`, `buildLoginSubmissionBody`)
- Modify: `tests/test_pluxee.lua`
- Create: `tests/fixtures/login_email_no_captcha.html`

**Interfaces:**
- Consumes: `classifyLoginHtml(html)` → `"email"|"password"|"otp"|"captcha"|"unknown"`
- Produces:
  - `buildLoginSubmissionBody(email)` → `string` (`application/x-www-form-urlencoded`)
  - `extractFormAction(html, currentUrl)` → absolute `https://…`-URL (Allowlist) oder `nil`
  - `submitLoginEmail(html, currentUrl, email)` → response-body `string` oder Fehlerstring
- Bei `classifyLoginHtml == "captcha"`: sofort `captchaBlockedMessage()`, **kein** POST

- [x] **Step 1: Failing tests für Form-Extraktion**

Fixture `tests/fixtures/login_email_no_captcha.html` (ohne den Substring `hcaptcha`/`h-captcha`):

```html
<!DOCTYPE html><html><body>
<form method="post" action="/op/interaction/abc/login">
  <input type="hidden" name="action" value="login-submission" />
  <input id="input-login" name="login" type="email" />
  <button type="submit">Weiter</button>
</form>
</body></html>
```

```lua
assertEq(classifyLoginHtml(readFixture("login_email_no_captcha.html")), "email", "classify.email.nocaptcha")
assertEq(classifyLoginHtml(readFixture("login_email_hcaptcha.html")), "captcha", "classify.captcha.priority")
local body = buildLoginSubmissionBody("user@example.com")
assertEq(body, "action=login-submission&login=user%40example.com", "loginBody")
local action = extractFormAction(
  readFixture("login_email_no_captcha.html"),
  "https://connect.pluxee.app/op/interaction/abc/login"
)
assertEq(action, "https://connect.pluxee.app/op/interaction/abc/login", "formAction")
```

- [x] **Step 2: Test FAIL ohne Funktionen**

```sh
luajit tests/test_pluxee.lua
```

Expected: FAIL (`buildLoginSubmissionBody` / `extractFormAction` undefined)

- [x] **Step 3: Implementierung**

```lua
function buildLoginSubmissionBody(email)
  return "action=login-submission&login=" .. urlEncode(normalizeEmail(email))
end

function extractFormAction(html, currentUrl)
  if type(html) ~= "string" then
    return nil
  end
  local action = html:match('<form[^>]*action="([^"]+)"')
    or html:match("<form[^>]*action='([^']+)'")
  if not action or action == "" then
    if type(currentUrl) == "string" and currentUrl:match("^https://") then
      assertAllowedUrl(currentUrl)
      return currentUrl
    end
    return nil
  end
  if action:match("^https://") then
    assertAllowedUrl(action)
    return action
  end
  if action:sub(1, 1) == "/" then
    local origin = (currentUrl or ""):match("^(https://[^/]+)")
    if not origin then
      return nil
    end
    local abs = origin .. action
    assertAllowedUrl(abs)
    return abs
  end
  return nil
end

function submitLoginEmail(html, currentUrl, email)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return nil, captchaBlockedMessage()
  end
  if kind ~= "email" then
    return nil, "Pluxee: E-Mail-Login-Seite erwartet, erhalten: " .. tostring(kind)
  end
  local action = extractFormAction(html, currentUrl)
  if not action then
    return nil, "Pluxee: Form-action für E-Mail-Login fehlt."
  end
  local body = buildLoginSubmissionBody(email)
  local response = apiRequest("POST", action, body, nil, "application/x-www-form-urlencoded")
  return response, nil
end
```

In `startOidcLogin` nach dem ersten GET:

```lua
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return captchaBlockedMessage()
  end
  if kind == "email" then
    local response, err = submitLoginEmail(html, url, session.accountKey)
    if err then
      return err
    end
    kind = classifyLoginHtml(response)
    -- weiter: password / otp / captcha wie bestehende Verzweigung
  end
```

- [x] **Step 4: Tests grün**

```sh
luajit tests/test_pluxee.lua
```

Expected: `test_pluxee OK`

- [ ] **Step 5: Commit** (nur auf User-Wunsch; vorher `/codereview`)

```sh
git add Pluxee.lua tests/test_pluxee.lua tests/fixtures/login_email_no_captcha.html
git commit -m "$(cat <<'EOF'
feat: Pluxee email login form body and action extract

EOF
)"
```

---

### Task 3: Passwort- und OTP-Schritte

**Status:** erledigt im Code (2026-09-05).

**Files:**
- Modify: `Pluxee.lua` (`buildPasswordSubmissionBody`, `buildOtpSubmissionBody`, `submitLoginPassword`, `submitLoginOtp`, `InitializeSession2`)
- Modify: `tests/test_pluxee.lua`
- Fixtures (v1-Vertrag bis Live-Capture sie ersetzt): `tests/fixtures/login_password.html` (`name="password"`), `tests/fixtures/login_otp.html` (`name="otp"`)

**Interfaces:**
- Consumes: `session.pendingPassword`, `emailOtpChallenge(message)`, `classifyLoginHtml`, `extractFormAction`
- Produces:
  - `buildPasswordSubmissionBody(password)` → `string` mit Key `password`
  - `buildOtpSubmissionBody(code)` → `string` mit Key `otp`
  - `submitLoginPassword(html, currentUrl, password)` → `response, err`
  - `submitLoginOtp(html, currentUrl, code)` → `response, err`
- Spec: Passwort nur bei `kind == "password"`; leeres Passwort → Fehlerstring (kein stilles Überspringen)

- [x] **Step 1: Failing tests**

```lua
assertEq(buildPasswordSubmissionBody("s3cret"), "password=s3cret", "pwBody")
assertEq(buildOtpSubmissionBody("123456"), "otp=123456", "otpBody")
local ch = emailOtpChallenge("Bitte Code")
assertEq(ch.title, "Pluxee Authentifizierung", "otp.title")
assertEq(ch.label, "E-Mail-Code", "otp.label")
assertEq(classifyLoginHtml(readFixture("login_password.html")), "password", "classify.password")
assertEq(classifyLoginHtml(readFixture("login_otp.html")), "otp", "classify.otp")
```

- [x] **Step 2: Run — FAIL**

```sh
luajit tests/test_pluxee.lua
```

Expected: FAIL (`buildPasswordSubmissionBody` / `buildOtpSubmissionBody` undefined)

- [x] **Step 3: Implementierung**

```lua
function buildPasswordSubmissionBody(password)
  return "password=" .. urlEncode(tostring(password or ""))
end

function buildOtpSubmissionBody(code)
  return "otp=" .. urlEncode(trim(tostring(code or "")))
end

function submitLoginPassword(html, currentUrl, password)
  if classifyLoginHtml(html) ~= "password" then
    return nil, "Pluxee: Passwort-Seite erwartet."
  end
  if trim(tostring(password or "")) == "" then
    return nil, "Pluxee: Passwort erforderlich (Portal zeigt Passwortfeld)."
  end
  local action = extractFormAction(html, currentUrl)
  if not action then
    return nil, "Pluxee: Form-action für Passwort fehlt."
  end
  local response = apiRequest(
    "POST",
    action,
    buildPasswordSubmissionBody(password),
    nil,
    "application/x-www-form-urlencoded"
  )
  return response, nil
end

function submitLoginOtp(html, currentUrl, code)
  if classifyLoginHtml(html) ~= "otp" then
    return nil, "Pluxee: OTP-Seite erwartet."
  end
  if trim(tostring(code or "")) == "" then
    return nil, emailOtpChallenge("Bitte den E-Mail-Code eingeben.")
  end
  local action = extractFormAction(html, currentUrl)
  if not action then
    return nil, "Pluxee: Form-action für OTP fehlt."
  end
  local response = apiRequest(
    "POST",
    action,
    buildOtpSubmissionBody(code),
    nil,
    "application/x-www-form-urlencoded"
  )
  return response, nil
end
```

In `InitializeSession2` bei `session.awaitingMfa`:

```lua
  if session.awaitingMfa then
    local code = credentials and credentials[1]
    local html = session.pendingLoginHtml
    local currentUrl = session.pendingLoginUrl
    local response, err = submitLoginOtp(html, currentUrl, code)
    if type(err) == "table" then
      return err
    end
    if err then
      return err
    end
    local haystack = tostring(response or "")
    local cbCode = parseCallbackCode(haystack)
    if cbCode then
      local payload, tokenErr = exchangeAuthorizationCode(cbCode)
      if tokenErr then
        return tokenErr
      end
      applyTokenPayload(payload, rawget(_G, "LocalStorage"), session.accountKey)
      session.awaitingMfa = false
      return nil
    end
    if classifyLoginHtml(response) == "otp" then
      session.awaitingMfa = true
      return emailOtpChallenge("Code ungültig oder abgelaufen. Bitte neuen Code prüfen.")
    end
    if classifyLoginHtml(response) == "captcha" then
      return captchaBlockedMessage()
    end
    return "Pluxee: Unerwartete Antwort nach OTP (kein callback code)."
  end
```

`parseCallbackCode` / `exchangeAuthorizationCode` / `applyTokenPayload`: Task 4 zuerst oder parallel verdrahten; OTP-Erfolgspfad ist ohne Task 4 nicht lauffähig.
Nach Live-Capture (Browser DevTools → Network, Request nach Captcha): wenn Feldnamen abweichen, Fixtures + `build*SubmissionBody` **gleichzeitig** anpassen (kein stilles Weitermachen mit alten Keys).

- [x] **Step 4: Tests grün**

```sh
luajit tests/test_pluxee.lua
```

Expected: `test_pluxee OK` (OTP→Token-Pfad darf bis Task 4 stubben, solange Body-Builder-Tests grün sind)

- [ ] **Step 5: Commit** (nur auf User-Wunsch; vorher `/codereview`)

```sh
git add Pluxee.lua tests/test_pluxee.lua tests/fixtures/login_password.html tests/fixtures/login_otp.html
git commit -m "$(cat <<'EOF'
feat: Pluxee password and OTP form submission helpers

EOF
)"
```

---

### Task 4: Authorization-Code → Token + Refresh

**Status:** erledigt im Code (2026-09-05; Refresh war Baseline).

**Files:**
- Modify: `Pluxee.lua` (`parseCallbackCode`, `exchangeAuthorizationCode`, `applyTokenPayload` bereits vorhanden erweitern)
- Modify: `tests/test_pluxee.lua`
- Create: `tests/fixtures/token_response.json` (synthetisch, keine echten Tokens)

**Interfaces:**
- Consumes: `session.codeVerifier`, `CONSTANTS.tokenUrl` / `clientId` / `redirectUri`, `persistTokens`
- Produces:
  - `parseCallbackCode(urlOrBody)` → `string|nil` (Authorization-Code)
  - `exchangeAuthorizationCode(code)` → `payload, err` (`payload` Tabelle mit `access_token`, oder `nil, string`)
  - Refresh bleibt `exchangeRefreshToken(refreshToken)` → payload-Tabelle oder `nil` (bestehend)

- [x] **Step 1: Failing tests**

`tests/fixtures/token_response.json`:

```json
{
  "access_token": "fixture-access",
  "refresh_token": "fixture-refresh",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

```lua
assertEq(parseCallbackCode("https://consumers.pluxee.de/oidc/callback?code=abc&state=x"), "abc", "callback.code")
assertEq(parseCallbackCode("https://consumers.pluxee.de/"), nil, "callback.nil")
local tok = parseJson(readFixture("token_response.json"))
assertEq(tok.access_token, "fixture-access", "token.access")
assertEq(tok.refresh_token, "fixture-refresh", "token.refresh")
```

- [x] **Step 2: Run FAIL**

```sh
luajit tests/test_pluxee.lua
```

Expected: FAIL (`parseCallbackCode` undefined)

- [x] **Step 3: Implementierung**

```lua
function parseCallbackCode(url)
  if type(url) ~= "string" then
    return nil
  end
  return url:match("[?&]code=([^&]+)")
end

function exchangeAuthorizationCode(code)
  if type(code) ~= "string" or code == "" then
    return nil, "Pluxee: Authorization-Code fehlt."
  end
  if type(session.codeVerifier) ~= "string" or session.codeVerifier == "" then
    return nil, "Pluxee: PKCE code_verifier fehlt."
  end
  local body = "grant_type=authorization_code"
    .. "&code=" .. urlEncode(code)
    .. "&redirect_uri=" .. urlEncode(CONSTANTS.redirectUri)
    .. "&client_id=" .. urlEncode(CONSTANTS.clientId)
    .. "&code_verifier=" .. urlEncode(session.codeVerifier)
  local raw = apiRequest("POST", CONSTANTS.tokenUrl, body, nil, "application/x-www-form-urlencoded")
  local payload = parseJson(raw)
  if not payload or type(payload.access_token) ~= "string" or payload.access_token == "" then
    return nil, "Pluxee: Token-Tausch fehlgeschlagen."
  end
  return payload, nil
end
```

Nach erfolgreichem Exchange: `applyTokenPayload(payload, storage, accountKey)` + `probeWallet`; bei Parse-/Netzwerkfehler Fehlerstring, kein leerer Erfolg mit Fake-Saldo. Tests nutzen unencoded `code=abc`.
- [x] **Step 4: Tests grün**

```sh
luajit tests/test_pluxee.lua
test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py
```

Expected: beide OK

- [ ] **Step 5: Commit** (nur auf User-Wunsch; vorher `/codereview`)

```sh
git add Pluxee.lua tests/test_pluxee.lua tests/fixtures/token_response.json
git commit -m "$(cat <<'EOF'
feat: Pluxee OIDC code exchange and callback parse

EOF
)"
```

---

### Task 5: Live-Smoke in MoneyMoney + Spec-Status

**Files:**
- Modify: `docs/superpowers/specs/2026-09-05-pluxee-extension-design.md` (Status-Zeile)
- Modify: `README.md` nur wenn Live-Befund Captcha/OTP ändert
- Test: manuell MoneyMoney Beta

**Interfaces:**
- Consumes: installiertes `Pluxee.lua` via `./link_ext.sh`
- Produces: dokumentierter Live-Status in Spec (Captcha weiterhin blockierend **oder** OTP-Pfad grün)

- [ ] **Step 1: Extension linken**

```sh
./link_ext.sh
```

Expected: Hardlink `…/MoneyMoney/Extensions/Pluxee.lua` → Repo-Datei

- [ ] **Step 2: MoneyMoney Beta**

1. Signaturprüfung aus; Bankzugang **Pluxee**, E-Mail = Portal-Login.
2. Aktualisieren: erwartet Captcha-Fehlermeldung **oder** (falls Engine Captcha umgeht) OTP-Challenge.
3. Mit gültigem Token in LocalStorage (nur Debug): `ListAccounts` zeigt je Benefit `pluxee.<benefitId-lower>`, Saldo; `RefreshAccount` nur Umsätze dieses Benefits.

- [ ] **Step 3: Spec-Status setzen**

Status-Zeile ersetzen durch genau eine der beiden Varianten (Datum = Smoke-Tag, z. B. `2026-09-05`):

- `Status: **Teil-Implementiert** — Parser/Hooks/Captcha-Gate; Erstlogin durch hCaptcha blockiert (Live 2026-09-05)`
- `Status: **Implementiert** — Login+Sync Live grün (2026-09-05)`

Offene Punkte in Spec nur streichen, wenn derselbe Live-Lauf sie belegt.

- [ ] **Step 4: Commit** (nur auf User-Wunsch; vorher `/codereview`)

```sh
git add docs/superpowers/specs/2026-09-05-pluxee-extension-design.md README.md
git commit -m "$(cat <<'EOF'
docs: Pluxee live smoke status

EOF
)"
```

---

### Task 6: GitHub-Remote veröffentlichen

**Files:**
- Remote only; Arbeitsverzeichnis `Pluxee-MoneyMoney/`

**Interfaces:**
- Produces: `https://github.com/rosch100/Pluxee-MoneyMoney` mit Branch `main`

- [ ] **Step 1: Initial commit falls noch keiner**

```sh
cd Pluxee-MoneyMoney
git status -sb
git add LICENSE README.md Pluxee.lua link_ext.sh .gitignore tests docs
git commit -m "$(cat <<'EOF'
feat: Pluxee MoneyMoney extension scaffold

OIDC/PKCE + BFF parsers, captcha gate, offline tests.
EOF
)"
```

Kein Cursor-Co-Author-Trailer. Vor Commit: `/codereview` auf dem zu commitenden Diff (`codereview-before-commit`).

- [ ] **Step 2: Repo anlegen und pushen**

Wenn Remote noch fehlt:

```sh
gh repo create rosch100/Pluxee-MoneyMoney --public --source=. --remote=origin --push
```

Wenn `origin` schon existiert:

```sh
git push -u origin HEAD
```

Expected: `origin` zeigt auf `rosch100/Pluxee-MoneyMoney`, `main` aktuell.

- [ ] **Step 3: README-Raw-URL prüfen**

```sh
curl -sI "https://raw.githubusercontent.com/rosch100/Pluxee-MoneyMoney/main/Pluxee.lua" | head -n 5
```

Expected: HTTP 200

---

### Task 7: Hub-Index verifizieren (Regression)

**Files:**
- Verify: Hub `../README.md`, `../docs/LUA-EXTENSIONS.md` (relativ zu `Pluxee-MoneyMoney/`)

- [ ] **Step 1: Zeilen prüfen**

```sh
cd Pluxee-MoneyMoney
rg -n "Pluxee" ../README.md ../docs/LUA-EXTENSIONS.md
```

Expected: Tabellenzeile in Hub-README + Abschnitt „Pluxee — 0.91 Beta“ in `LUA-EXTENSIONS.md`.

- [ ] **Step 2: Hub-Commit nur wenn Zeilen fehlen oder User commit anfordert**

Fehlende Zeilen analog Baseline ergänzen; kein Scope-Creep auf andere Hub-Docs.

---

## Spec-Coverage-Check (Plan-Self-Review)

| Spec-Anforderung | Task |
| --- | --- |
| Sibling-Repo + MIT + link_ext | Baseline, Task 6 |
| WebBanking `Pluxee` 0.91 + Hooks | Baseline |
| OIDC PKCE + client_id DE | Baseline, Task 4 |
| E-Mail → optional Passwort → OTP | Task 2–3 |
| Captcha → expliziter Fehler | Baseline, Task 2 (Global Constraint Live-DE) |
| BFF cards + transactions | Baseline |
| Konto pro Benefit, `pluxee.<benefitId>`, Tx-Filter | Task 1 (erledigt) |
| Multi-Login Token-Map + Refresh | Baseline, Task 4 |
| Tests conformance + lua fixtures | Baseline + Tasks 1–4 |
| Hub-Index | Baseline, Task 7 |
| Live-Smoke / Spec-Status | Task 5 |
| GitHub Remote | Task 6 |
| Nicht-Ziele (Cookie-Import, andere Länder) | bewusst keine Tasks |

**Placeholder-Scan:** keine offenen Platzhalter-Schritte; OTP/Password-Feldnamen = Fixture-Vertrag (`password` / `otp`) bis Live-Capture.

**Typ-Konsistenz:** `classifyLoginHtml` → string kinds; `accountNumberForBenefit(benefit)`; `exchangeAuthorizationCode` → `payload, err`; Tokens `accessToken`/`refreshToken`/`expiresAt` in Map; `submitLogin*` → `response, err`; `benefitsByAccountNumber`.
