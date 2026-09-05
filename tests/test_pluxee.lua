---@diagnostic disable: duplicate-set-field
-- Offline-Tests für Pluxee (kein MoneyMoney-Host nötig).

function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
AccountTypeCreditCard = 3
LoginFailed = "LoginFailed"

MM = {
  printStatus = function(msg)
    io.stderr:write("[STATUS] " .. msg .. "\n")
  end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end,
}

function Connection()
  return {
    request = function()
      return nil
    end,
    get = function()
      return nil
    end,
    getCookies = function()
      return ""
    end,
    setCookie = function() end,
  }
end

function JSON(str)
  local i = 1
  local function peek()
    return str:sub(i, i)
  end
  local function skip()
    while str:sub(i, i):match("%s") do
      i = i + 1
    end
  end
  local parseValue
  local function parseString()
    i = i + 1
    local start = i
    while true do
      local c = str:sub(i, i)
      if c == "" then
        error("unterminated string")
      end
      if c == "\\" then
        i = i + 2
      elseif c == '"' then
        local raw = str:sub(start, i - 1)
        i = i + 1
        return raw:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub('\\"', '"'):gsub("\\\\", "\\")
      else
        i = i + 1
      end
    end
  end
  local function parseNumber()
    local start = i
    if peek() == "-" then
      i = i + 1
    end
    while peek():match("%d") do
      i = i + 1
    end
    if peek() == "." then
      i = i + 1
      while peek():match("%d") do
        i = i + 1
      end
    end
    return tonumber(str:sub(start, i - 1))
  end
  local function parseArray()
    i = i + 1
    local arr = {}
    skip()
    if peek() == "]" then
      i = i + 1
      return arr
    end
    while true do
      arr[#arr + 1] = parseValue()
      skip()
      if peek() == "]" then
        i = i + 1
        return arr
      end
      if peek() ~= "," then
        error("expected comma in array")
      end
      i = i + 1
      skip()
    end
  end
  local function parseObject()
    i = i + 1
    local obj = {}
    skip()
    if peek() == "}" then
      i = i + 1
      return obj
    end
    while true do
      skip()
      if peek() ~= '"' then
        error("expected string key")
      end
      local key = parseString()
      skip()
      if peek() ~= ":" then
        error("expected colon")
      end
      i = i + 1
      obj[key] = parseValue()
      skip()
      if peek() == "}" then
        i = i + 1
        return obj
      end
      if peek() ~= "," then
        error("expected comma in object")
      end
      i = i + 1
    end
  end
  parseValue = function()
    skip()
    local c = peek()
    if c == '"' then
      return parseString()
    end
    if c == "{" then
      return parseObject()
    end
    if c == "[" then
      return parseArray()
    end
    if c == "t" and str:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    end
    if c == "f" and str:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    end
    if c == "n" and str:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    end
    if c == "-" or c:match("%d") then
      return parseNumber()
    end
    error("unexpected at " .. i)
  end
  local decoded = parseValue()
  return {
    dictionary = function()
      return decoded
    end,
  }
end

dofile("Pluxee Benefits.lua")

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print(
      "FAIL  "
        .. label
        .. ": expected="
        .. tostring(expected)
        .. ", actual="
        .. tostring(actual)
    )
    os.exit(1)
  end
end

local function assertNear(actual, expected, label)
  if type(actual) == "number" and math.abs(actual - expected) < 0.001 then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print(
      "FAIL  "
        .. label
        .. ": expected~"
        .. tostring(expected)
        .. ", actual="
        .. tostring(actual)
    )
    os.exit(1)
  end
end

local function readFixture(name)
  local f = assert(io.open("tests/fixtures/" .. name, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

assertEq(normalizeEmail("  User@Firma.DE "), "user@firma.de", "normalizeEmail")
assertEq(SupportsBank(ProtocolWebBanking, "Pluxee Benefits"), true, "SupportsBank.ok")
assertEq(SupportsBank(ProtocolWebBanking, "Pluxee"), false, "SupportsBank.bareBrand")
assertEq(SupportsBank(ProtocolWebBanking, "Other"), false, "SupportsBank.no")
assertEq(hostAllowed("https://api.pluxee.app/gl/eva/bff/v2/de/cards"), true, "host.api")
assertEq(hostAllowed("https://connect.pluxee.app/op/oidc/auth"), true, "host.connect")
assertEq(hostAllowed("https://evil.example/x"), false, "host.evil")

assertEq(classifyLoginHtml(readFixture("login_email_hcaptcha.html")), "captcha", "classify.captcha")
assertEq(classifyLoginHtml(readFixture("login_email_no_captcha.html")), "email", "classify.email.nocaptcha")
assertEq(classifyLoginHtml(readFixture("login_password.html")), "password", "classify.password")
assertEq(classifyLoginHtml(readFixture("login_otp.html")), "otp", "classify.otp")
assertEq(
  classifyLoginHtml(readFixture("login_otp.html")),
  "otp",
  "classify.otp.beforeCaptchaInNextData"
)
assertEq(loginHtmlHasEmailField(readFixture("login_email_hcaptcha.html")), true, "login.hasEmail.captchaPage")
assertEq(
  extractHcaptchaSiteKey(readFixture("login_email_hcaptcha.html")),
  "b0fdbea0-b123-42f6-b521-d532697a5512",
  "hcaptcha.siteKey"
)
local hc = hCaptchaInteractiveChallenge("b0fdbea0-b123-42f6-b521-d532697a5512", "https://connect.pluxee.app/op/interaction/x/login")
assertEq(type(hc) == "table", true, "hcaptcha.challenge.table")
assertEq(hc.challenge:find("js%.hcaptcha%.com/1/api%.js", 1) ~= nil, true, "hcaptcha.challenge.url")
assertEq(hc.challenge:find("sitekey=b0fdbea0%-b123%-42f6%-b521%-d532697a5512", 1) ~= nil, true, "hcaptcha.challenge.sitekey")
assertEq(type(captchaBlockedMessage()) == "string", true, "captcha.msg")
assertEq(captchaBlockedMessage():find("hCaptcha", 1, true) ~= nil, true, "captcha.msg.hcaptcha")
assertEq(isCredentialRejection("invalid_grant"), true, "cred.reject.invalid_grant")
assertEq(isCredentialRejection("otp invalid"), true, "cred.reject.otp")
assertEq(isCredentialRejection("welcome to pluxee"), false, "cred.reject.clean")
assertEq(credentialRejectionOr("invalid credentials"), LoginFailed, "cred.reject.LoginFailed")

local loginBody = buildLoginSubmissionBody("User@Example.com")
assertEq(loginBody:find("action=login%-submission", 1) ~= nil, true, "login.body.action")
assertEq(loginBody:find("login=user%%40example%.com", 1) ~= nil or loginBody:find("login=user@example.com", 1, true) ~= nil, true, "login.body.email")
local loginBodyHc = buildLoginSubmissionBody("user@example.com", "tok-abc")
assertEq(loginBodyHc:find("h%-captcha%-response=tok%-abc", 1) ~= nil, true, "login.body.hcaptcha")
assertEq(buildPasswordSubmissionBody("secret"), "password=secret", "password.body")
assertEq(buildOtpSubmissionBody("123456"), "action=address-validation&isWebAuthnAvailable=false&code=123456", "otp.body")
assertEq(buildResendOtpJson(nil), '{"action":"resend-address-validation"}', "otp.resend.json")
assertEq(
  buildResendOtpJson("tok"),
  '{"action":"resend-address-validation","h-captcha-response":"tok"}',
  "otp.resend.json.captcha"
)
local otpMeta = extractOtpPageMeta(readFixture("login_otp.html"))
assertEq(otpMeta.interactionId, "fixture-interaction-otp", "otp.meta.interactionId")
assertEq(otpMeta.nbCodesSent, 0, "otp.meta.nbCodesSent")
assertEq(otpMeta.hcaptchaCredits, 3, "otp.meta.credits")
assertEq(
  otpResendUrl(otpMeta),
  "https://connect.pluxee.app/op/interaction/fixture-interaction-otp/email_address_ownership_validation",
  "otp.resend.url"
)
local otpMetaUrlPreferred = extractOtpPageMeta(
  readFixture("login_otp.html"),
  "https://connect.pluxee.app/op/interaction/62e25790-url-id/login"
)
assertEq(otpMetaUrlPreferred.interactionId, "62e25790-url-id", "otp.meta.interactionId.urlWins")
assertEq(
  otpResendUrl(otpMetaUrlPreferred),
  "https://connect.pluxee.app/op/interaction/62e25790-url-id/email_address_ownership_validation",
  "otp.resend.url.fromPath"
)
assertEq(otpResendNeedsCaptcha(otpMeta), false, "otp.resend.needsCaptcha.false")
assertEq(otpResendNeedsCaptcha({ hcaptchaCredits = 0 }), true, "otp.resend.needsCaptcha.true")

local formAction = extractFormAction(
  readFixture("login_email_no_captcha.html"),
  "https://connect.pluxee.app/op/auth"
)
assertEq(formAction, "https://connect.pluxee.app/op/interaction/abc/login", "form.action.relative")
assertEq(
  parseCallbackCode("https://consumers.pluxee.de/oidc/callback?code=abc123&state=mm"),
  "abc123",
  "callback.code"
)
assertEq(
  parseCallbackCode("<!DOCTYPE html><html><body>spa</body></html>"),
  nil,
  "callback.code.spaHtmlNil"
)
assertEq(
  parseCallbackCode("https://consumers.pluxee.de/oidc/callback?code=a%2Bb&state=mm"),
  "a+b",
  "callback.code.urldecoded"
)

local function pluxeeSession()
  local i = 1
  while true do
    local name, value = debug.getupvalue(oauthCallbackStateError, i)
    if not name then
      error("session upvalue missing")
    end
    if name == "session" then
      return value
    end
    i = i + 1
  end
end

local sess = pluxeeSession()
sess.oauthState = "mm-state-ok"
local trustedCode, trustedErr = authorizationCodeFromTrustedCallback(
  "https://consumers.pluxee.de/oidc/callback?code=abc123&state=mm-state-ok"
)
assertEq(trustedCode, "abc123", "callback.trusted.code")
assertEq(trustedErr, nil, "callback.trusted.err")
local badStateCode, badStateErr = authorizationCodeFromTrustedCallback(
  "https://consumers.pluxee.de/oidc/callback?code=abc123&state=wrong"
)
assertEq(badStateCode, nil, "callback.state.mismatch.code")
assertEq(badStateErr ~= nil, true, "callback.state.mismatch.err")
local noStateCode, noStateErr = authorizationCodeFromTrustedCallback(
  "https://consumers.pluxee.de/oidc/callback?code=abc123"
)
assertEq(noStateCode, nil, "callback.state.missing.code")
assertEq(noStateErr ~= nil, true, "callback.state.missing.err")
sess.oauthState = nil
local noSessionCode, noSessionErr = authorizationCodeFromTrustedCallback(
  "https://consumers.pluxee.de/oidc/callback?code=abc123&state=mm-state-ok"
)
assertEq(noSessionCode, nil, "callback.state.sessionMissing.code")
assertEq(noSessionErr ~= nil, true, "callback.state.sessionMissing.err")

assertEq(isSafeOidcInteractionId("62e25790-url-id"), true, "interactionId.safe")
assertEq(isSafeOidcInteractionId("../evil"), false, "interactionId.path")
assertEq(isSafeOidcInteractionId("id with space"), false, "interactionId.space")
assertEq(allowedOidcOpUrl("https://connect.pluxee.app/op"), "https://connect.pluxee.app/op", "opUrl.allowed")
assertEq(allowedOidcOpUrl("https://evil.example/op"), nil, "opUrl.evil")
local evilOpMeta = extractOtpPageMeta(
  '{"interactionId":"fixture-interaction-otp","opUrl":"https://evil.example/op"}',
  nil
)
assertEq(evilOpMeta.opUrl, "https://connect.pluxee.app/op", "opUrl.evil.fallback")
assertEq(
  extractInteractionIdFromUrl("https://connect.pluxee.app/op/interaction/../evil/email"),
  nil,
  "interactionId.url.path"
)

local ch = emailOtpChallenge(nil)
assertEq(ch.label, "E-Mail-Code", "otp.label")

local wallet = parseJson(readFixture("wallet_cards.json"))
local cards = parseWalletCards(wallet)
local rows = iterWalletBenefits(cards)
assertEq(#rows, 1, "wallet.benefitRows")
assertNear(benefitBalance(rows[1].benefit), 3.37, "wallet.balance")
assertEq(accountNumberForBenefit(rows[1].card, rows[1].benefit, 1), "XXXX 6138", "wallet.accountNumber")
assertEq(legacyAccountNumberForBenefit(rows[1].benefit), "pluxee.deufixturebenefit001", "wallet.accountNumber.legacy")
assertEq(accountNameForBenefit(rows[1].card, rows[1].benefit, false), "Benefits Card", "wallet.accountName.single")
assertEq(accountNameForBenefit(rows[1].card, rows[1].benefit, true), "Benefits Card 6138", "wallet.accountName.multi")
assertEq(cardLast4(rows[1].card), "6138", "wallet.cardLast4")

local multi = parseJson(readFixture("wallet_two_benefits.json"))
local multiRows = iterWalletBenefits(parseWalletCards(multi))
assertEq(#multiRows, 2, "multi.benefitRows")
local multiCounts = panUsageCounts(multiRows)
assertEq(multiCounts["XXXX 6138"], 2, "multi.pan.count")
assertEq(
  accountNumberForBenefit(multiRows[1].card, multiRows[1].benefit, multiCounts["XXXX 6138"]),
  "XXXX 6138 deufixturebenefit001",
  "multi.n1"
)
assertEq(
  accountNumberForBenefit(multiRows[2].card, multiRows[2].benefit, multiCounts["XXXX 6138"]),
  "XXXX 6138 deufixturebenefit002",
  "multi.n2"
)
assertNear(benefitBalance(multiRows[2].benefit), 12.00, "multi.balance2")
assertEq(accountNameForBenefit(multiRows[2].card, multiRows[2].benefit, true), "Meal Pass 6138", "multi.name2")
assertEq(
  rowMatchesAccountNumber(multiRows[1], "pluxee.deufixturebenefit001", multiCounts),
  true,
  "multi.legacyMatch"
)
assertEq(
  rowMatchesAccountNumber(rows[1], "····6138", panUsageCounts(rows)),
  true,
  "wallet.legacyDotsMatch"
)
assertEq(
  transactionsUrl("DEU00000000000001130923"),
  "https://api.pluxee.app/gl/eva/bff/v2/de/cards/DEU00000000000001130923/transactions?limit=99",
  "tx.url.limit99"
)
assertEq(
  transactionsUrl("DEU00000000000001130923", {
    benefitId = "DEUGF2",
    toDate = "2023-05-10",
  }),
  "https://api.pluxee.app/gl/eva/bff/v2/de/cards/DEU00000000000001130923/transactions?limit=99&benefitId=DEUGF2&toDate=2023-05-10",
  "tx.url.pageWithoutFromDate"
)
assertEq(dayBeforeYmd("2025-11-01"), "2025-10-31", "tx.dayBefore")
assertEq(nextPaginationToDate(nil, "2025-11-22T13:42:28.000"), "2025-11-22", "tx.nextTo.first")
assertEq(nextPaginationToDate("2025-11-22", "2025-11-22T01:00:00.000"), "2025-11-21", "tx.nextTo.sameDay")
assertEq(
  oldestTransactionIsoDate(parseJson(readFixture("transactions.json")).transactions),
  "2025-07-19T07:09:08.000",
  "tx.oldest"
)
local seenKeys = {}
local merged = {}
appendUniqueMappedTransactions(merged, seenKeys, {
  { bookingKey = "a", amount = 1 },
  { bookingKey = "a", amount = 1 },
  { bookingKey = "b", amount = 2 },
})
assertEq(#merged, 2, "tx.dedupe")
local apiErr = pluxeeApiErrorMessage({
  code = 600,
  message = "Validation failed",
  validationErrors = {
    { member = "TransactionCount", message = "The field TransactionCount must be between 1 and 99." },
  },
})
assertEq(apiErr:find("between 1 and 99", 1, true) ~= nil, true, "tx.apiError.limit")

local txs = parseTransactionsPayload(parseJson(readFixture("transactions.json")), nil, "DEUFIXTUREBENEFIT001")
assertEq(#txs, 2, "tx.count.benefit1")
assertEq(txs[1].name, "REWE Filialen Voll", "tx1.name")
assertNear(txs[1].amount, -0.40, "tx1.amount")
assertEq(txs[1].bookingKey, "DEUfixture-tx-1:DEUFIXTUREBENEFIT001", "tx1.key")
assertEq(txs[2].name, "Load", "tx2.name")
assertNear(txs[2].amount, 50.00, "tx2.amount")
assertEq(isApprovedPluxeeTransaction({ status = "DECLINED" }), false, "tx.declined")
assertEq(isApprovedPluxeeTransaction({ status = "APPROVED" }), true, "tx.approved")
assertEq(isApprovedPluxeeTransaction({ status = "OTHER" }), false, "tx.other")
assertEq(isApprovedPluxeeTransaction({}), false, "tx.nostatus")
assertEq(mapPluxeeTransaction({
  id = "x",
  status = "DECLINED",
  merchantName = "Shop",
  date = "2025-07-19T07:09:08.000",
  amount = { value = -100, exponent = 2, currency = "EUR" },
  splitData = {
    { uniqueWalletId = "DEUFIXTUREBENEFIT001", splitAmount = { value = -100, exponent = 2, currency = "EUR" } },
  },
}, "DEUFIXTUREBENEFIT001"), nil, "tx.declined.skipped")
local txsOther = parseTransactionsPayload(parseJson(readFixture("transactions.json")), nil, "DEUFIXTUREBENEFIT002")
assertEq(#txsOther, 1, "tx.count.benefit2")
assertEq(txsOther[1].name, "Other Shop", "tx.other.name")
assertNear(txsOther[1].amount, -1.00, "tx.other.amount")

local verifier, challenge = pkcePair()
assertEq(type(verifier) == "string" and #verifier > 20, true, "pkce.verifier")
assertEq(type(challenge) == "string" and #challenge > 20, true, "pkce.challenge")
-- RFC 7636 appendix vector: verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
-- challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
local rfcChallenge = base64urlEncode(sha256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
assertEq(rfcChallenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "pkce.rfc7636")

print("test_pluxee OK")
