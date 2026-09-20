-- In-process MoneyMoney crypto stubs for offline Pluxee tests (no openssl/tmp).
-- Mirrors MM.sha256 (uppercase hex), MM.hexToBin, MM.base64urlencode, MM.random.

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

local function sha256Binary(msg)
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

local function sha256Hex(msg)
  local binary = sha256Binary(msg)
  local parts = {}
  for i = 1, #binary do
    parts[i] = string.format("%02X", string.byte(binary, i))
  end
  return table.concat(parts)
end

local function hexToBin(hex)
  hex = tostring(hex):gsub("[^0-9A-Fa-f]", "")
  if (#hex % 2) ~= 0 then
    return nil
  end
  local parts = {}
  for i = 1, #hex, 2 do
    parts[#parts + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return table.concat(parts)
end

local function base64urlencode(raw)
  local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local t = {}
  for i = 1, #raw, 3 do
    local a, b, c = string.byte(raw, i, i + 2)
    b = b or 0
    c = c or 0
    local n = a * 65536 + b * 256 + c
    t[#t + 1] = b64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    t[#t + 1] = b64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    if i + 1 <= #raw then
      t[#t + 1] = b64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
    end
    if i + 2 <= #raw then
      t[#t + 1] = b64:sub(n % 64 + 1, n % 64 + 1)
    end
  end
  return table.concat(t):gsub("+", "-"):gsub("/", "_")
end

local function randomBytes(n)
  local parts = {}
  for i = 1, n do
    parts[i] = string.char(math.random(0, 255))
  end
  return table.concat(parts)
end

return {
  sha256 = sha256Hex,
  hexToBin = hexToBin,
  base64urlencode = base64urlencode,
  random = randomBytes,
}
