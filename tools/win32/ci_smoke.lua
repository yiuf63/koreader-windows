-- Runtime smoke test for the Windows build.
--
-- Installed as a user patch by `tools/win32/ci_smoke.sh` and executed at
-- koreader startup, because that is the only way to run Lua inside the real
-- process — and the real process is the thing under test here.
--
-- It covers the failures that only appear at runtime, which a successful
-- compile says nothing about:
--
--   * the POSIX shim (`base/win32_posix.c`): MSVCRT exports `_open`, not
--     `open`, so `ffi.C.open` and friends only resolve if the shim is linked
--     into koreader.exe and exported;
--   * the DLL search path: `libs/` and `common/` have to be registered, or
--     libraries whose own imports are not on the default path fail to load;
--   * gettext: `.mo` files are binary, and loading them needs `open` to be in
--     *binary* mode.
--
-- Writes its result to a file (a GUI process has nowhere to print) and exits
-- non-zero via the caller when it does not end in `SMOKE OK`.
local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
local out = io.open(tmp .. "/ci_smoke.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

local failures = 0
local function check(name, ok, detail)
    if ok then
        w(string.format("  ok    %s", name))
    else
        failures = failures + 1
        w(string.format("  FAIL  %s%s", name, detail and (" -- " .. tostring(detail)) or ""))
    end
end

w("Windows build smoke test")
w("")

-- ---------------------------------------------------------------- POSIX shim
w("POSIX shim")
do
    local ffi = require("ffi")
    require("ffi/posix_h")
    local C = ffi.C

    for _, n in ipairs({ "open", "read", "write", "close", "lseek" }) do
        check("ffi.C." .. n, pcall(function() return C[n] end))
    end

    -- The shim must open in binary mode: a text-mode read would shorten the
    -- result on CRLF, which is how the translation catalogue failed to load.
    local path = (os.getenv("TEMP") or ".") .. "/ci_smoke_bin.txt"
    local f = io.open(path, "wb")
    f:write("a\r\nb\r\nc\r\n")   -- 9 bytes: the CRs must survive the round trip
    f:close()

    local fd = C.open(path, C.O_RDONLY)
    check("open() returns a valid fd", tonumber(fd) >= 0, fd)
    if tonumber(fd) >= 0 then
        local buf = ffi.new("char[64]")
        local n = tonumber(C.read(fd, buf, 64))
        check("read() returns all 9 bytes (binary mode)", n == 9, n)
        C.close(fd)
    end
    os.remove(path)
end

-- ------------------------------------------------------------- DLL search path
w("")
w("DLL loading")
do
    -- Loaded by name through the registered search path, the way the frontend
    -- does; these are the libraries whose own imports live beside them.
    for _, lib in ipairs({ "blitbuffer", "koreader-cre", "koreader-djvu" }) do
        local ffi = require("ffi")
        local ok, err = pcall(ffi.loadlib, lib)
        check("load " .. lib, ok, ok and nil or tostring(err):sub(1, 80))
    end
end

-- ------------------------------------------------------------------- gettext
w("")
w("gettext")
do
    local gettext = require("gettext")
    local ok, err = pcall(function() gettext.changeLang("zh_CN") end)
    check("load zh_CN catalogue", ok, ok and nil or tostring(err):sub(1, 100))
    if ok then
        -- A catalogue that loaded but is empty would pass the check above.
        local translated = gettext("Cancel")
        check("translate a known string", translated ~= "Cancel" and translated ~= nil,
            "got " .. tostring(translated))
        w("        Cancel -> " .. tostring(translated))
    end
end

-- ------------------------------------------------------------------ frontend
w("")
w("frontend")
do
    -- Covers SDL loading, the framebuffer, the device abstraction and the
    -- reader UI: the parts that touch win32-specific code.
    for _, mod in ipairs({ "device", "ui/uimanager", "ffi/blitbuffer",
                           "document/documentregistry", "apps/reader/readerui" }) do
        local ok, err = pcall(require, mod)
        check("require " .. mod, ok, ok and nil or tostring(err):sub(1, 100))
    end
end

w("")
if failures == 0 then
    w("SMOKE OK")
else
    w(string.format("SMOKE FAILED (%d)", failures))
end
out:close()
return true
