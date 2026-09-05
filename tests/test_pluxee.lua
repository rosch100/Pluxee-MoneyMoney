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

dofile("Pluxee.lua")

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
assertEq(SupportsBank(ProtocolWebBanking, "Pluxee"), true, "SupportsBank.ok")
assertEq(SupportsBank(ProtocolWebBanking, "Other"), false, "SupportsBank.no")
assertEq(hostAllowed("https://api.pluxee.app/gl/eva/bff/v2/de/cards"), true, "host.api")
assertEq(hostAllowed("https://connect.pluxee.app/op/oidc/auth"), true, "host.connect")
assertEq(hostAllowed("https://evil.example/x"), false, "host.evil")

assertEq(classifyLoginHtml(readFixture("login_email_hcaptcha.html")), "captcha", "classify.captcha")
assertEq(classifyLoginHtml(readFixture("login_email_no_captcha.html")), "email", "classify.email.nocaptcha")
assertEq(classifyLoginHtml(readFixture("login_password.html")), "password", "classify.password")
assertEq(classifyLoginHtml(readFixture("login_otp.html")), "otp", "classify.otp")
assertEq(type(captchaBlockedMessage()) == "string", true, "captcha.msg")
assertEq(captchaBlockedMessage():find("hCaptcha", 1, true) ~= nil, true, "captcha.msg.hcaptcha")

local loginBody = buildLoginSubmissionBody("User@Example.com")
assertEq(loginBody:find("action=login%-submission", 1) ~= nil, true, "login.body.action")
assertEq(loginBody:find("login=user%%40example%.com", 1) ~= nil or loginBody:find("login=user@example.com", 1, true) ~= nil, true, "login.body.email")
assertEq(buildPasswordSubmissionBody("secret"), "password=secret", "password.body")
assertEq(buildOtpSubmissionBody("123456"), "otp=123456", "otp.body")

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

local ch = emailOtpChallenge(nil)
assertEq(ch.label, "E-Mail-Code", "otp.label")

local wallet = parseJson(readFixture("wallet_cards.json"))
local cards = parseWalletCards(wallet)
local rows = iterWalletBenefits(cards)
assertEq(#rows, 1, "wallet.benefitRows")
assertNear(benefitBalance(rows[1].benefit), 3.37, "wallet.balance")
assertEq(accountNumberForBenefit(rows[1].benefit), "pluxee.deufixturebenefit001", "wallet.accountNumber")
assertEq(accountNameForBenefit(rows[1].card, rows[1].benefit), "Benefits Card (····6138)", "wallet.accountName")

local multi = parseJson(readFixture("wallet_two_benefits.json"))
local multiRows = iterWalletBenefits(parseWalletCards(multi))
assertEq(#multiRows, 2, "multi.benefitRows")
assertEq(accountNumberForBenefit(multiRows[1].benefit), "pluxee.deufixturebenefit001", "multi.n1")
assertEq(accountNumberForBenefit(multiRows[2].benefit), "pluxee.deufixturebenefit002", "multi.n2")
assertNear(benefitBalance(multiRows[2].benefit), 12.00, "multi.balance2")
assertEq(accountNameForBenefit(multiRows[2].card, multiRows[2].benefit), "Meal Pass (····6138)", "multi.name2")

local txs = parseTransactionsPayload(parseJson(readFixture("transactions.json")), nil, "DEUFIXTUREBENEFIT001")
assertEq(#txs, 2, "tx.count.benefit1")
assertEq(txs[1].name, "REWE Filialen Voll", "tx1.name")
assertNear(txs[1].amount, -0.40, "tx1.amount")
assertEq(txs[1].bookingKey, "DEUfixture-tx-1:DEUFIXTUREBENEFIT001", "tx1.key")
assertEq(txs[2].name, "Load", "tx2.name")
assertNear(txs[2].amount, 50.00, "tx2.amount")
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
