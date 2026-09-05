--
-- Plugin Homepage: https://github.com/rosch100/Pluxee-MoneyMoney
-- Pluxee — MoneyMoney Web Banking Extension
-- Portal: https://consumers.pluxee.de  OIDC: https://connect.pluxee.app
-- API: https://api.pluxee.app/gl/eva/bff
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 0.91,
  url         = "https://consumers.pluxee.de",
  services    = {"Pluxee"},
  description = "Pluxee Benefits Card — E-Mail/OTP (Passwort nur wenn Formular)"
}

local CONSTANTS = {
  portalUrl = "https://consumers.pluxee.de",
  oidcAuthority = "https://connect.pluxee.app/op",
  authorizeUrl = "https://connect.pluxee.app/op/oidc/auth",
  tokenUrl = "https://connect.pluxee.app/op/oidc/token",
  redirectUri = "https://consumers.pluxee.de/oidc/callback",
  clientId = "bf400a61-2659-4269-9363-ebd2029adaa2",
  scope = "openid profile email offline_access",
  bffBase = "https://api.pluxee.app/gl/eva/bff",
  country = "de",
  -- Öffentlicher SPA-Key (Live-Bundle consumers.pluxee.de, 2026-09-05)
  apimSubscriptionKey = "f2b9fb99716f43a38b01867a0aeaf687",
  allowedHosts = {
    "consumers.pluxee.de",
    "connect.pluxee.app",
    "api.pluxee.app",
  },
  serviceName = "Pluxee",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
  transactionLimit = 100,
}

-- Connect-/Token-Antworten (OIDC + UI-HTML); analog givve Card.
local CREDENTIAL_REJECTION_MARKERS = {
  "invalid_grant",
  "invalid_client",
  "access_denied",
  "invalid credentials",
  "invalid email",
  "invalid password",
  "unauthorized",
  "login failed",
  "falsche",
  "ungültig",
  "ungueltig",
  "incorrect",
  "wrong password",
  "wrong code",
  "otp invalid",
  "code invalid",
}

local connection
local session = {}

function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function normalizeEmail(raw)
  return trim(tostring(raw or "")):lower()
end

function normalizeAccountKey(raw)
  return normalizeEmail(raw)
end

function hostAllowed(urlOrHost)
  if type(urlOrHost) ~= "string" or urlOrHost == "" then
    return false
  end
  local host = urlOrHost
  if host:match("^https?://") then
    host = host:match("^https?://([^/?#]+)") or ""
  end
  host = host:lower():gsub(":443$", ""):gsub(":80$", "")
  for _, allowed in ipairs(CONSTANTS.allowedHosts) do
    if host == allowed then
      return true
    end
  end
  return false
end

function assertAllowedUrl(url)
  if type(url) ~= "string" or url == "" then
    error("Pluxee: URL fehlt")
  end
  if not url:match("^https://") then
    error("Pluxee: nur https:// erlaubt")
  end
  if not hostAllowed(url) then
    error("Pluxee: Host nicht erlaubt: " .. tostring(url))
  end
  return url
end

-- Compact SHA-256 + base64url for PKCE (MoneyMoney has no built-in digest).
local function bit_band(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 and bb == 1 then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bor(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 or bb == 1 then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bxor(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa ~= bb then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bnot(a)
  return 4294967295 - a
end

local function bit_rshift(a, n)
  return math.floor(a / (2 ^ n)) % 4294967296
end

local function bit_lshift(a, n)
  return (a * (2 ^ n)) % 4294967296
end

local function bit_ror(x, n)
  return bit_bor(bit_rshift(x, n), bit_lshift(x, 32 - n))
end

function sha256(msg)
  local k = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local bytes = { string.byte(msg, 1, #msg) }
  local bitLen = #bytes * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end
  for i = 7, 0, -1 do
    bytes[#bytes + 1] = math.floor(bitLen / (2 ^ (8 * i))) % 256
  end
  for i = 1, #bytes, 64 do
    local w = {}
    for j = 0, 15 do
      local b = i + j * 4
      w[j] = bytes[b] * 16777216 + bytes[b + 1] * 65536 + bytes[b + 2] * 256 + bytes[b + 3]
    end
    for j = 16, 63 do
      local s0 = bit_bxor(bit_bxor(bit_ror(w[j - 15], 7), bit_ror(w[j - 15], 18)), bit_rshift(w[j - 15], 3))
      local s1 = bit_bxor(bit_bxor(bit_ror(w[j - 2], 17), bit_ror(w[j - 2], 19)), bit_rshift(w[j - 2], 10))
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % 4294967296
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for j = 0, 63 do
      local S1 = bit_bxor(bit_bxor(bit_ror(e, 6), bit_ror(e, 11)), bit_ror(e, 25))
      local ch = bit_bxor(bit_band(e, f), bit_band(bit_bnot(e), g))
      local temp1 = (h + S1 + ch + k[j + 1] + w[j]) % 4294967296
      local S0 = bit_bxor(bit_bxor(bit_ror(a, 2), bit_ror(a, 13)), bit_ror(a, 22))
      local maj = bit_bxor(bit_bxor(bit_band(a, b), bit_band(a, c)), bit_band(b, c))
      local temp2 = (S0 + maj) % 4294967296
      h = g
      g = f
      f = e
      e = (d + temp1) % 4294967296
      d = c
      c = b
      b = a
      a = (temp1 + temp2) % 4294967296
    end
    h0 = (h0 + a) % 4294967296
    h1 = (h1 + b) % 4294967296
    h2 = (h2 + c) % 4294967296
    h3 = (h3 + d) % 4294967296
    h4 = (h4 + e) % 4294967296
    h5 = (h5 + f) % 4294967296
    h6 = (h6 + g) % 4294967296
    h7 = (h7 + h) % 4294967296
  end
  local out = {}
  for _, v in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
    for i = 3, 0, -1 do
      out[#out + 1] = string.char(math.floor(v / (256 ^ i)) % 256)
    end
  end
  return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64urlEncode(raw)
  local t = {}
  for i = 1, #raw, 3 do
    local a, b, c = string.byte(raw, i, i + 2)
    b = b or 0
    c = c or 0
    local n = a * 65536 + b * 256 + c
    local n1 = math.floor(n / 262144) % 64
    local n2 = math.floor(n / 4096) % 64
    local n3 = math.floor(n / 64) % 64
    local n4 = n % 64
    t[#t + 1] = B64:sub(n1 + 1, n1 + 1)
    t[#t + 1] = B64:sub(n2 + 1, n2 + 1)
    if i + 1 <= #raw then
      t[#t + 1] = B64:sub(n3 + 1, n3 + 1)
    end
    if i + 2 <= #raw then
      t[#t + 1] = B64:sub(n4 + 1, n4 + 1)
    end
  end
  return table.concat(t):gsub("+", "-"):gsub("/", "_")
end

function pkcePair()
  local raw = {}
  for i = 1, 32 do
    raw[i] = string.char(math.random(0, 255))
  end
  local verifier = base64urlEncode(table.concat(raw))
  local challenge = base64urlEncode(sha256(verifier))
  return verifier, challenge
end

function urlEncode(s)
  if MM and MM.urlencode then
    return MM.urlencode(tostring(s))
  end
  return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function buildAuthorizeUrl(codeChallenge, state)
  return CONSTANTS.authorizeUrl
    .. "?client_id="
    .. urlEncode(CONSTANTS.clientId)
    .. "&redirect_uri="
    .. urlEncode(CONSTANTS.redirectUri)
    .. "&response_type=code"
    .. "&scope="
    .. urlEncode(CONSTANTS.scope)
    .. "&code_challenge="
    .. urlEncode(codeChallenge)
    .. "&code_challenge_method=S256"
    .. "&state="
    .. urlEncode(state or "mm")
    .. "&prompt=login"
    .. "&ui_locales=de"
end

function parseJson(str)
  if type(str) ~= "string" or str == "" then
    return nil
  end
  local ok, result = pcall(function()
    return JSON(str):dictionary()
  end)
  if ok then
    return result
  end
  return nil
end

function classifyLoginHtml(html)
  if type(html) ~= "string" or html == "" then
    return "unknown"
  end
  local lower = html:lower()
  if lower:find("hcaptcha", 1, true) or lower:find("h-captcha", 1, true) then
    return "captcha"
  end
  if lower:find('name="password"', 1, true) or lower:find("type=\"password\"", 1, true)
      or lower:find("type='password'", 1, true) then
    return "password"
  end
  if lower:find("otp", 1, true) or lower:find("einmalcode", 1, true)
      or lower:find("one-time", 1, true) or lower:find("bestätigungscode", 1, true)
      or lower:find("verifizierungscode", 1, true) then
    return "otp"
  end
  if lower:find('name="login"', 1, true) or lower:find("input-login", 1, true)
      or lower:find("e-mail-adresse", 1, true) or lower:find("login-submission", 1, true) then
    return "email"
  end
  return "unknown"
end

function captchaBlockedMessage()
  return "Pluxee: Login blockiert durch hCaptcha auf connect.pluxee.app — "
    .. "automatischer E-Mail/OTP-Login aus dem Plugin ist derzeit nicht möglich."
end

function isCredentialRejection(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  local lower = text:lower()
  for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
    if lower:find(marker, 1, true) then
      return true
    end
  end
  return false
end

function credentialRejectionOr(message)
  if isCredentialRejection(message) then
    return LoginFailed
  end
  return message
end

function emailOtpChallenge(message)
  return {
    title = "Pluxee Authentifizierung",
    challenge = message or "Bitte den Code aus der Pluxee-E-Mail eingeben.",
    label = "E-Mail-Code",
  }
end

function moneyAmountFromPluxee(amountTable)
  if type(amountTable) ~= "table" or type(amountTable.value) ~= "number" then
    return nil
  end
  local exp = amountTable.exponent
  if type(exp) ~= "number" then
    exp = 2
  end
  return amountTable.value / (10 ^ exp)
end

function benefitBalance(benefit)
  if type(benefit) ~= "table" then
    return nil
  end
  return moneyAmountFromPluxee(benefit.amount)
end

function cardLast4(card)
  if type(card) ~= "table" then
    return ""
  end
  if type(card.panLastFourDigits) == "string" and card.panLastFourDigits ~= "" then
    return card.panLastFourDigits
  end
  local masked = card.maskedPan
  if type(masked) == "string" then
    local dig = masked:match("(%d%d%d%d)%s*$")
    if dig then
      return dig
    end
  end
  if type(card.cardId) == "string" and #card.cardId >= 4 then
    return card.cardId:sub(-4)
  end
  return ""
end

function accountNumberForBenefit(benefit)
  if type(benefit) ~= "table" or type(benefit.benefitId) ~= "string" or trim(benefit.benefitId) == "" then
    error("Pluxee: benefitId für Kontonummer fehlt")
  end
  return "pluxee." .. trim(benefit.benefitId):lower()
end

function accountNameForBenefit(card, benefit)
  local name = "Pluxee"
  if type(benefit) == "table" and type(benefit.name) == "string" and trim(benefit.name) ~= "" then
    name = trim(benefit.name)
  elseif type(card) == "table" and type(card.name) == "string" and trim(card.name) ~= "" then
    name = trim(card.name)
  end
  local last4 = cardLast4(card)
  if last4 ~= "" then
    return name .. " (····" .. last4 .. ")"
  end
  return name
end

function iterWalletBenefits(cards)
  local rows = {}
  if type(cards) ~= "table" then
    return rows
  end
  for i = 1, #cards do
    local card = cards[i]
    if type(card) == "table" and type(card.cardId) == "string" and type(card.benefits) == "table" then
      for j = 1, #card.benefits do
        local benefit = card.benefits[j]
        if type(benefit) == "table" and type(benefit.benefitId) == "string" and benefit.benefitId ~= "" then
          rows[#rows + 1] = { card = card, benefit = benefit }
        end
      end
    end
  end
  return rows
end

function parseIsoDateTimeToTimestamp(iso)
  if type(iso) ~= "string" or iso == "" then
    return nil
  end
  local y, m, d, hh, mm, ss = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then
    y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    hh, mm, ss = 12, 0, 0
  end
  if not y then
    return nil
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(hh) or 12,
    min = tonumber(mm) or 0,
    sec = tonumber(ss) or 0,
  })
end

function amountForBenefitTransaction(tx, benefitId)
  if type(tx) ~= "table" then
    return nil
  end
  if type(benefitId) == "string" and benefitId ~= "" and type(tx.splitData) == "table" then
    local sum = 0
    local found = false
    local currency = nil
    for i = 1, #tx.splitData do
      local split = tx.splitData[i]
      if type(split) == "table" and split.uniqueWalletId == benefitId then
        local amt = moneyAmountFromPluxee(split.splitAmount)
        if amt ~= nil then
          sum = sum + amt
          found = true
          if type(split.splitAmount) == "table" and type(split.splitAmount.currency) == "string" then
            currency = split.splitAmount.currency
          end
        end
      end
    end
    if found then
      return sum, currency
    end
    return nil, nil
  end
  return moneyAmountFromPluxee(tx.amount), nil
end

function mapPluxeeTransaction(tx, benefitId)
  if type(tx) ~= "table" then
    return nil
  end
  if type(benefitId) == "string" and benefitId ~= "" then
    local matched = false
    if type(tx.splitData) == "table" then
      for i = 1, #tx.splitData do
        local split = tx.splitData[i]
        if type(split) == "table" and split.uniqueWalletId == benefitId then
          matched = true
          break
        end
      end
    end
    if not matched then
      return nil
    end
  end
  local amount, splitCurrency = amountForBenefitTransaction(tx, benefitId)
  local ts = parseIsoDateTimeToTimestamp(tx.date)
  local name = nil
  if type(tx.merchantName) == "string" and trim(tx.merchantName) ~= "" then
    name = trim(tx.merchantName)
  elseif type(tx.description) == "string" and trim(tx.description) ~= "" then
    name = trim(tx.description)
  end
  if not name or amount == nil or not ts then
    return nil
  end
  local currency = "EUR"
  if type(splitCurrency) == "string" and splitCurrency ~= "" then
    currency = splitCurrency
  elseif type(tx.amount) == "table" and type(tx.amount.currency) == "string" and tx.amount.currency ~= "" then
    currency = tx.amount.currency
  end
  local bookingKey = tx.id
  if type(benefitId) == "string" and benefitId ~= "" and type(bookingKey) == "string" then
    bookingKey = bookingKey .. ":" .. benefitId
  end
  return {
    bookingDate = ts,
    name = name,
    amount = amount,
    bookingKey = bookingKey,
    currency = currency,
  }
end

function parseTransactionsPayload(payload, sinceTimestamp, benefitId)
  local out = {}
  if type(payload) ~= "table" or type(payload.transactions) ~= "table" then
    return out
  end
  for i = 1, #payload.transactions do
    local mapped = mapPluxeeTransaction(payload.transactions[i], benefitId)
    if mapped then
      if sinceTimestamp == nil or mapped.bookingDate >= sinceTimestamp then
        out[#out + 1] = mapped
      end
    end
  end
  return out
end

function parseWalletCards(payload)
  if type(payload) ~= "table" or type(payload.cards) ~= "table" then
    return {}
  end
  return payload.cards
end

function stripNonSerializableConnections(storage)
  if type(storage) ~= "table" then
    return
  end
  storage.connection = nil
  if type(storage.connectionsByAccount) == "table" then
    for _, entry in pairs(storage.connectionsByAccount) do
      if type(entry) == "table" then
        entry.connection = nil
      end
    end
  end
end

function getConnectionEntry(storage, accountKey)
  if not storage then
    return nil
  end
  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey]
  if not entry then
    entry = {}
    storage.connectionsByAccount[accountKey] = entry
  end
  return entry
end

function persistTokens(storage, accountKey, accessToken, refreshToken, expiresAt)
  local entry = getConnectionEntry(storage, accountKey)
  if not entry then
    return
  end
  entry.accessToken = accessToken
  entry.refreshToken = refreshToken
  entry.expiresAt = expiresAt
  storage.connectionAccountKey = accountKey
  storage.accessToken = accessToken
  storage.refreshToken = refreshToken
  storage.expiresAt = expiresAt
end

function restoreTokens(storage, accountKey)
  if not storage or accountKey == "" then
    return nil, nil, nil
  end
  local entry = storage.connectionsByAccount and storage.connectionsByAccount[accountKey]
  local access = entry and entry.accessToken
  local refresh = entry and entry.refreshToken
  local expiresAt = entry and entry.expiresAt
  if (not access or access == "") and storage.connectionAccountKey == accountKey then
    access = storage.accessToken
    refresh = storage.refreshToken
    expiresAt = storage.expiresAt
  end
  if type(access) == "string" and access ~= "" then
    session.accessToken = access
    session.refreshToken = refresh
    session.expiresAt = expiresAt
    return access, refresh, expiresAt
  end
  return nil, nil, nil
end

function apiHeaders(accessToken)
  local headers = {
    ["Accept"] = "application/json",
    ["Accept-Language"] = "de-DE,de;q=0.9",
    ["User-Agent"] = CONSTANTS.userAgent,
    ["ocp-apim-subscription-key"] = CONSTANTS.apimSubscriptionKey,
    ["Origin"] = CONSTANTS.portalUrl,
    ["Referer"] = CONSTANTS.portalUrl .. "/",
  }
  if type(accessToken) == "string" and accessToken ~= "" then
    headers["Authorization"] = "Bearer " .. accessToken
  end
  return headers
end

function apiRequest(method, url, body, accessToken, contentType)
  assertAllowedUrl(url)
  return connection:request(method, url, body, contentType, apiHeaders(accessToken))
end

function walletUrl()
  return CONSTANTS.bffBase .. "/v2/" .. CONSTANTS.country .. "/cards"
end

function transactionsUrl(cardId, limit)
  local lim = limit or CONSTANTS.transactionLimit
  return CONSTANTS.bffBase
    .. "/v2/"
    .. CONSTANTS.country
    .. "/cards/"
    .. urlEncode(cardId)
    .. "/transactions?limit="
    .. tostring(lim)
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == CONSTANTS.serviceName
end

function ensureConnection()
  if not connection then
    connection = Connection()
  end
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent
end

function probeWallet(accessToken)
  local raw = apiRequest("GET", walletUrl(), nil, accessToken)
  local payload = parseJson(raw)
  if payload and type(payload.cards) == "table" then
    return payload
  end
  return nil
end

function exchangeRefreshToken(refreshToken)
  if type(refreshToken) ~= "string" or refreshToken == "" then
    return nil
  end
  local body = "grant_type=refresh_token"
    .. "&refresh_token="
    .. urlEncode(refreshToken)
    .. "&client_id="
    .. urlEncode(CONSTANTS.clientId)
  local raw = apiRequest("POST", CONSTANTS.tokenUrl, body, nil, "application/x-www-form-urlencoded")
  local payload = parseJson(raw)
  if not payload or type(payload.access_token) ~= "string" or payload.access_token == "" then
    return nil
  end
  return payload
end

function applyTokenPayload(payload, storage, accountKey)
  local access = payload.access_token
  local refresh = payload.refresh_token
  local expiresIn = payload.expires_in
  local expiresAt = nil
  if type(expiresIn) == "number" then
    expiresAt = os.time() + expiresIn
  end
  session.accessToken = access
  session.refreshToken = refresh
  session.expiresAt = expiresAt
  if storage then
    persistTokens(storage, accountKey, access, refresh, expiresAt)
  end
end

function buildLoginSubmissionBody(email)
  return "action=login-submission&login=" .. urlEncode(normalizeEmail(email))
end

function buildPasswordSubmissionBody(password)
  return "password=" .. urlEncode(tostring(password or ""))
end

function buildOtpSubmissionBody(code)
  return "otp=" .. urlEncode(trim(tostring(code or "")))
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
  local response = apiRequest(
    "POST",
    action,
    buildLoginSubmissionBody(email),
    nil,
    "application/x-www-form-urlencoded"
  )
  return response, nil
end

function submitLoginPassword(html, currentUrl, password)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return nil, captchaBlockedMessage()
  end
  if kind ~= "password" then
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
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return nil, captchaBlockedMessage()
  end
  if kind ~= "otp" then
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
    .. "&code="
    .. urlEncode(code)
    .. "&redirect_uri="
    .. urlEncode(CONSTANTS.redirectUri)
    .. "&client_id="
    .. urlEncode(CONSTANTS.clientId)
    .. "&code_verifier="
    .. urlEncode(session.codeVerifier)
  local raw = apiRequest("POST", CONSTANTS.tokenUrl, body, nil, "application/x-www-form-urlencoded")
  local payload = parseJson(raw)
  if not payload or type(payload.access_token) ~= "string" or payload.access_token == "" then
    if isCredentialRejection(raw) then
      return nil, LoginFailed
    end
    return nil, "Pluxee: Token-Tausch fehlgeschlagen."
  end
  return payload, nil
end

function continueLoginAfterResponse(response, currentUrl)
  local haystack = tostring(response or "")
  local cbCode = parseCallbackCode(haystack)
  if cbCode then
    local payload, tokenErr = exchangeAuthorizationCode(cbCode)
    if tokenErr then
      return tokenErr
    end
    local storage = rawget(_G, "LocalStorage")
    applyTokenPayload(payload, storage, session.accountKey)
    local wallet = probeWallet(session.accessToken)
    if not wallet then
      return "Pluxee: Login ok, aber Wallet nicht lesbar."
    end
    session.walletPayload = wallet
    session.awaitingMfa = false
    session.pendingLoginHtml = nil
    session.pendingLoginUrl = nil
    return nil
  end
  local kind = classifyLoginHtml(haystack)
  if kind == "captcha" then
    return captchaBlockedMessage()
  end
  if kind == "password" then
    if session.passwordSubmitted then
      return LoginFailed
    end
    local pw = session.pendingPassword or ""
    local nextHtml, err = submitLoginPassword(haystack, currentUrl, pw)
    if err then
      return err
    end
    session.passwordSubmitted = true
    session.pendingLoginHtml = nextHtml
    session.pendingLoginUrl = currentUrl
    return continueLoginAfterResponse(nextHtml, currentUrl)
  end
  if kind == "otp" then
    if session.otpSubmitted and isCredentialRejection(haystack) then
      session.awaitingMfa = false
      return LoginFailed
    end
    session.awaitingMfa = true
    session.pendingLoginHtml = haystack
    session.pendingLoginUrl = currentUrl
    return emailOtpChallenge(nil)
  end
  if isCredentialRejection(haystack) then
    session.awaitingMfa = false
    return LoginFailed
  end
  if kind == "email" then
    return captchaBlockedMessage() .. " (E-Mail-Schritt erneut — Captcha erwartet.)"
  end
  return "Pluxee: Unerwartete Login-Antwort von connect.pluxee.app."
end

function startOidcLogin()
  local verifier, challenge = pkcePair()
  session.codeVerifier = verifier
  session.oauthState = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
  local url = buildAuthorizeUrl(challenge, session.oauthState)
  local html = apiRequest("GET", url, nil, nil)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return captchaBlockedMessage()
  end
  if kind == "email" then
    local response, err = submitLoginEmail(html, url, session.accountKey)
    if err then
      return err
    end
    session.pendingLoginHtml = response
    session.pendingLoginUrl = url
    return continueLoginAfterResponse(response, url)
  end
  if kind == "password" then
    session.pendingLoginHtml = html
    session.pendingLoginUrl = url
    return continueLoginAfterResponse(html, url)
  end
  if kind == "otp" then
    session.awaitingMfa = true
    session.pendingLoginHtml = html
    session.pendingLoginUrl = url
    return emailOtpChallenge(nil)
  end
  return "Pluxee: Unerwartete Login-Seite von connect.pluxee.app."
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  local password = credentials and credentials[2] or ""
  local storage = rawget(_G, "LocalStorage")

  if step == 1 then
    if email == "" then
      return "Bitte die Pluxee-E-Mail-Adresse eingeben."
    end
    session = { accountKey = email, pendingPassword = password }
    if storage then
      stripNonSerializableConnections(storage)
      getConnectionEntry(storage, email)
      storage.connectionAccountKey = email
    end
    ensureConnection()

    local access, refresh = restoreTokens(storage, email)
    if access then
      local wallet = probeWallet(access)
      if wallet then
        session.walletPayload = wallet
        return nil
      end
      if refresh then
        local refreshed = exchangeRefreshToken(refresh)
        if refreshed then
          applyTokenPayload(refreshed, storage, email)
          wallet = probeWallet(session.accessToken)
          if wallet then
            session.walletPayload = wallet
            return nil
          end
        end
      end
      session.accessToken = nil
    end

    if interactive == false then
      return "Pluxee: Interaktive Anmeldung (E-Mail-OTP) erforderlich."
    end
    return startOidcLogin()
  end

  ensureConnection()
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
    session.otpSubmitted = true
    session.pendingLoginHtml = response
    return continueLoginAfterResponse(response, currentUrl)
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function ListAccounts(knownAccounts)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "Pluxee: Session fehlt — bitte anmelden."
  end
  ensureConnection()
  local wallet = session.walletPayload
  if not wallet then
    wallet = probeWallet(session.accessToken)
    if not wallet then
      return "Pluxee: Kontenliste konnte nicht gelesen werden."
    end
    session.walletPayload = wallet
  end
  local cards = parseWalletCards(wallet)
  local rows = iterWalletBenefits(cards)
  if #rows == 0 then
    return "Pluxee: Kein Benefit im Wallet gefunden."
  end
  local accounts = {}
  session.benefitsByAccountNumber = {}
  for i = 1, #rows do
    local card = rows[i].card
    local benefit = rows[i].benefit
    local balance = benefitBalance(benefit)
    if balance == nil then
      return "Pluxee: Saldo für Benefit fehlt."
    end
    local number = accountNumberForBenefit(benefit)
    session.benefitsByAccountNumber[number] = {
      cardId = card.cardId,
      benefitId = benefit.benefitId,
    }
    accounts[#accounts + 1] = {
      name = accountNameForBenefit(card, benefit),
      accountNumber = number,
      currency = "EUR",
      balance = balance,
      type = AccountTypeCreditCard,
    }
  end
  return accounts
end

function RefreshAccount(account, since)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "Pluxee: Session fehlt — bitte anmelden."
  end
  ensureConnection()
  local cardId = nil
  local benefitId = nil
  if type(account) == "table" and type(account.accountNumber) == "string" then
    local ref = session.benefitsByAccountNumber and session.benefitsByAccountNumber[account.accountNumber]
    if type(ref) == "table" then
      cardId = ref.cardId
      benefitId = ref.benefitId
    end
  end
  if not cardId or not benefitId then
    local wallet = session.walletPayload or probeWallet(session.accessToken)
    if not wallet then
      return "Pluxee: Wallet für Umsätze nicht lesbar."
    end
    session.walletPayload = wallet
    local rows = iterWalletBenefits(parseWalletCards(wallet))
    if #rows < 1 then
      return "Pluxee: Benefit für Umsätze nicht gefunden."
    end
    if type(account) == "table" and type(account.accountNumber) == "string" then
      for i = 1, #rows do
        if accountNumberForBenefit(rows[i].benefit) == account.accountNumber then
          cardId = rows[i].card.cardId
          benefitId = rows[i].benefit.benefitId
          break
        end
      end
    end
    if not cardId or not benefitId then
      return "Pluxee: Benefit passt nicht zur Kontonummer."
    end
  end

  local wallet = session.walletPayload or probeWallet(session.accessToken)
  local balance = nil
  if wallet then
    for _, row in ipairs(iterWalletBenefits(parseWalletCards(wallet))) do
      if row.benefit.benefitId == benefitId then
        balance = benefitBalance(row.benefit)
        break
      end
    end
  end
  if balance == nil then
    return "Pluxee: Saldo konnte nicht gelesen werden."
  end

  local txRaw = apiRequest("GET", transactionsUrl(cardId), nil, session.accessToken)
  local txPayload = parseJson(txRaw)
  if not txPayload then
    return "Pluxee: Umsätze konnten nicht gelesen werden."
  end
  return {
    balance = balance,
    transactions = parseTransactionsPayload(txPayload, since, benefitId),
  }
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  session.pendingPassword = nil
  session.awaitingMfa = false
  session.codeVerifier = nil
  session.passwordSubmitted = nil
  session.otpSubmitted = nil
  session.pendingLoginHtml = nil
  session.pendingLoginUrl = nil
  connection = nil
end
