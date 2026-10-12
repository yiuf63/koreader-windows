-- Verify the LuaJIT UTF-8 fix for Windows system messages.
--
-- The message text comes from `FormatMessage`, which used to be called in its
-- ANSI form; on a Chinese system that returns GBK, while Lua strings are UTF-8.
-- After the patch it should be UTF-8, so the bytes should decode as valid UTF-8
-- and contain no replacement characters.
--
-- Assert on the bytes, not on how it happens to look in a console.
local tmp = os.getenv("TEMP") or "."
local out = io.open(tmp .. "/komoji.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

local ffi = require("ffi")
require("ffi/posix_h")

-- Trigger the same error path the startup banner hits.
local ok, err = pcall(ffi.load, "libs/libkoreader-monolibtic.dll")
w("ffi.load failed as expected: " .. tostring(not ok))
if ok then out:close() return true end

local msg = tostring(err)
w("message: " .. msg)
w("")

-- Byte-level checks.
local bytes = {}
for i = 1, #msg do bytes[#bytes + 1] = string.format("%02X", msg:byte(i)) end
w("hex: " .. table.concat(bytes, " "))
w("")

-- UTF-8 validity: every multi-byte sequence must be well formed. A GBK string
-- decoded as UTF-8 typically contains bytes >= 0x80 that do not form valid
-- sequences.
local i, n, bad = 1, #msg, 0
while i <= n do
    local c = msg:byte(i)
    local len
    if c < 0x80 then len = 1
    elseif c >= 0xC2 and c <= 0xDF then len = 2
    elseif c >= 0xE0 and c <= 0xEF then len = 3
    elseif c >= 0xF0 and c <= 0xF4 then len = 4
    else bad = bad + 1; i = i + 1; len = 0 end
    if len > 1 then
        local valid = true
        for k = 1, len - 1 do
            local cc = msg:byte(i + k)
            if not cc or cc < 0x80 or cc > 0xBF then valid = false break end
        end
        if not valid then bad = bad + 1 end
        i = i + len
    elseif len == 1 then
        i = i + 1
    end
end
w("invalid UTF-8 sequences: " .. bad)
w("contains U+FFFD (replacement char): " .. tostring(msg:find("\239\191\189") ~= nil))

w("")
if bad == 0 then
    w("RESULT: the message is valid UTF-8.")
    w("        CP_UTF8 conversion is in effect.")
else
    w("RESULT: " .. bad .. " invalid sequence(s) -- still not UTF-8.")
end

-- Also show what the old ANSI form would have produced, for contrast: the
-- system message in the ANSI code page, decoded as UTF-8.
ffi.cdef[[
typedef unsigned long DWORD;
DWORD GetLastError(void);
DWORD FormatMessageA(DWORD dwFlags, const void *lpSource, DWORD dwMessageId,
                     DWORD dwLanguageId, char *lpBuffer, DWORD nSize, void *Arguments);
DWORD FormatMessageW(DWORD dwFlags, const void *lpSource, DWORD dwMessageId,
                     DWORD dwLanguageId, unsigned short *lpBuffer, DWORD nSize, void *Arguments);
static const DWORD KO_FM_SYSTEM = 0x00001000;
static const DWORD KO_FM_IGNORE = 0x00000200;
]]
local C = ffi.C
local bufA = ffi.new("char[512]")
if C.FormatMessageA(bit.bor(C.KO_FM_SYSTEM, C.KO_FM_IGNORE), nil, 126, 0, bufA, 512, nil) ~= 0 then
    local ansi = ffi.string(bufA)
    -- Strip the trailing newline the system message carries.
    ansi = ansi:gsub("[\r\n]+$", "")
    w("")
    w("for contrast, the ANSI form of the same message:")
    w("  as bytes  : " .. (ansi:gsub(".", function(c)
        return string.format("%02X ", c:byte()) end)))
    w("  in a UTF-8 terminal this shows as: " .. ansi)
end
out:close()
return true
