-- Load every FFI library the way the frontend loads it.
--
-- The duplication work rewrote import archives so each library ships once, under
-- the canonical name. That is invisible to the spec suite: it changes which file
-- a DLL loads, not what the Lua code does, so a spec run passes whether the
-- libraries resolve or not.
--
-- What it affects is whether a library loads and whether its symbols are
-- reachable. Both failure modes are quiet and land far from the cause:
--
--   * a name that no longer exists (`libz.dll`) fails at load;
--   * a wrong export list yields a library that loads but lacks symbols,
--     surfacing as a nil call somewhere in the reader. That is what the first
--     attempt at the rewrite did -- `dlltool --export-all-symbols` read the COFF
--     symbol table, so dependents imported `DllMain` and `_chkstk_ms` and failed
--     at load with error 127.
--
-- So this loads each module the frontend actually uses, by requiring the real
-- `ffi/*.lua` wrappers rather than calling `ffi.loadlib` with guessed arguments.
-- Requiring them exercises the cdefs and the loadlib call together, which is what
-- production does; a hand-written `ffi.loadlib` call tests neither.
--
-- Installed as a user patch, because that is the only way to run Lua inside a
-- running koreader. Results go to $KO_HOME/ffi-check.txt.

local out = {}
local function say(fmt, ...)
    out[#out + 1] = string.format(fmt, ...)
end

local checked, failed = 0, 0
local function check(name, fn)
    checked = checked + 1
    local ok, err = pcall(fn)
    if ok then
        say("ok    %s", name)
    else
        failed = failed + 1
        say("FAIL  %s -- %s", name, tostring(err))
    end
end

-- The modules the frontend requires, which between them load every library the
-- duplication work touched. `require` is the real code path: each of these files
-- declares its cdefs and calls `ffi.loadlib` itself.
--
-- The names are the wrappers that exist under `base/ffi/`, not guesses: there is
-- no `ffi/libpng` or `ffi/webpdemux`, PNG goes through `ffi/png` (lodepng) and
-- WebP through `ffi/webp` (which loads both libwebp and libwebpdemux).
local modules = {
    "ffi/archiver",      -- libarchive-13, and through it libz-1 and libzstd-1
    "ffi/zlib",          -- libz-1
    "ffi/zstd",          -- libzstd-1
    "ffi/png",           -- liblodepng
    "ffi/jpeg",          -- libturbojpeg-0.4.0
    "ffi/pic",           -- libgif-7
    "ffi/utf8proc",      -- libutf8proc-3
    "ffi/koptcontext",   -- libleptonica-6 and libk2pdfopt-2
    "ffi/webp",          -- libwebp-7 and libwebpdemux-2
    "ffi/hashoir",       -- libxxhash-0
    "ffi/freetype",      -- libfreetype-6
    "ffi/harfbuzz",      -- libharfbuzz-0
    "ffi/SDL3",          -- libSDL3-0
    "ffi/mupdf",         -- libwrap-mupdf
    "ffi/crypto",        -- libcrypto-57
}

for _, m in ipairs(modules) do
    check(m, function() require(m) end)
end

-- Also require the whole reader, which pulls in crengine, the document registry
-- and every other native module transitively.
check("apps/reader/readerui", function() require("apps/reader/readerui") end)

-- And call into a few of them, so a module that loads but whose symbols are
-- missing is caught. Each call goes through the interface the module exposes.
--
-- The library handle is private in these wrappers -- `ffi/zlib.lua` keeps `libz`
-- as an upvalue and returns `zlib_compress`/`zlib_decompress` -- so reaching for
-- `module.compressBound` finds nothing, and that says nothing about whether the
-- library loaded. Requiring the module already proves it resolved, since the
-- `ffi.loadlib` call is at its top level; these calls add the other half, that
-- the symbols behind the interface are really there.
check("zlib round-trips data", function()
    local zlib = require("ffi/zlib")
    local data = "the quick brown fox jumps over the lazy dog"
    local packed = zlib.zlib_compress(data)
    assert(packed ~= nil and #packed > 0, "compress produced nothing")
    local back = zlib.zlib_uncompress(packed, #data)
    assert(back == data, "round trip mismatch: " .. tostring(back))
end)

check("zstd round-trips data", function()
    local zstd = require("ffi/zstd")
    local ffi = require("ffi")
    local C = ffi.C
    local data = "the quick brown fox jumps over the lazy dog"

    -- zstd_compress takes a pointer and returns (buffer, length); the buffer is
    -- malloc'd by the module, so the caller frees it.
    local inbuf = ffi.new("char[?]", #data)
    ffi.copy(inbuf, data, #data)
    local packed, plen = zstd.zstd_compress(inbuf, #data, 3)
    assert(packed ~= nil and plen > 0, "compress produced nothing")
    local back, blen = zstd.zstd_uncompress(packed, plen)
    assert(back ~= nil and blen == #data, "decompress length " .. tostring(blen))
    assert(ffi.string(back, blen) == data, "round trip mismatch")
    C.free(packed)
    C.free(back)
end)

-- libarchive reading a real archive. This is the call chain that runs through
-- libz and libzstd, so one check covers three libraries.
--
-- The files come from `test/` in the checkout, whose path is passed in the
-- environment: koreader runs from the package directory, where `test/` does not
-- exist, so a relative path would only work by accident.
check("libarchive reads an epub", function()
    local Archiver = require("ffi/archiver")
    local root = os.getenv("KO_TESTDATA")
    assert(root, "KO_TESTDATA is not set")
    local path = nil
    for _, p in ipairs({
        root .. "/juliet.epub",
        root .. "/leaves.epub",
        root .. "/中文测试书名-论读书.epub",
    }) do
        local f = io.open(p, "rb")
        if f then f:close(); path = p; break end
    end
    assert(path, "no test epub under " .. root)

    local reader = Archiver.Reader:new()
    assert(reader ~= nil, "Reader:new returned nil")
    reader:open(path)
    local n = 0
    for _ in reader:iterate() do n = n + 1 end
    assert(n > 0, "no entries read from " .. path)
end)

-- freetype is loaded by the reader itself, and its library name carries a
-- different version than the project emits, so it is worth calling into.
check("freetype initialises", function()
    local FT = require("ffi/freetype")
    assert(FT ~= nil, "ffi/freetype returned nil")
end)

say("")
say("checked=%d failed=%d", checked, failed)

local path = require("datastorage").getDataDir() .. "/ffi-check.txt"
local f = io.open(path, "w")
f:write(table.concat(out, "\n") .. "\n")
f:close()
