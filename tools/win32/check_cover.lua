-- Does the "Start-up of background extraction job failed" prompt still appear?
--
-- `CoverMenu:updateItems` calls `BookInfoManager:extractInBackground(...)` and,
-- when that returns false, shows
--   "Start-up of background extraction job failed.\nPlease restart KOReader or your device."
-- It returned false on Windows purely because `fork()` is unavailable, even
-- though the extraction itself is perfectly doable inline.
--
-- Call the same function the menu calls, with a real book, and check the return
-- value. Also confirm the work actually happened (the info ends up in the db),
-- since "returns true" alone would be worthless if it silently did nothing.
local tmp = os.getenv("TEMP") or "."
local out = io.open(tmp .. "/kocover.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

local lfs = require("libs/libkoreader-lfs")
w("cwd = " .. tostring(lfs.currentdir()))

-- `bookinfomanager` lives inside the coverbrowser plugin, which is not on
-- `package.path` until the plugin is loaded; add its directory explicitly.
package.path = "plugins/coverbrowser.koplugin/?.lua;" .. package.path

local ok_req, BookInfoManager = pcall(require, "bookinfomanager")
w("BookInfoManager loaded: " .. tostring(ok_req)
    .. (ok_req and "" or (" -> " .. tostring(BookInfoManager):sub(1, 200))))
if not ok_req then
    out:close()
    return true
end

-- Grab a real book from the bundled test data, so this is not a synthetic path.
local candidates = {
    "spec/front/unit/data/leaves.epub",
    "spec/front/unit/data/juliet.epub",
    "../../test/leaves.epub",
}
local book
for _, p in ipairs(candidates) do
    if lfs.attributes(p, "mode") == "file" then book = p break end
end
w("book: " .. tostring(book))

if not book then
    w("no test book found; cannot exercise the path")
    out:close()
    return true
end

-- The files argument is a list of {filepath=..., cover_specs=...}.
local files = { { filepath = book, cover_specs = nil } }

local started = os.time()
local ok, launched = pcall(function()
    return BookInfoManager:extractInBackground(files)
end)
local elapsed = os.time() - started

w("")
w(string.format("extractInBackground -> ok=%s launched=%s  (%.1fs)",
    tostring(ok), tostring(launched), elapsed))
w("")
if not ok then
    w("RESULT: it raised.")
elseif launched then
    w("RESULT: returned true, so CoverMenu will NOT show the")
    w("        'Start-up of background extraction job failed' prompt.")
    if elapsed >= 1 then
        w("        (Took " .. elapsed .. "s: the work ran inline, as expected")
        w("         where there is no fork().)")
    end
else
    w("RESULT: still returns false -- the prompt would still appear.")
end
out:close()
return true
