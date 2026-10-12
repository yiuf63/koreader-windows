-- Is any *user-visible* time wrong on Windows?
--
-- Raw `os.date("%_H:%M", t)` returns a number because the MS CRT lacks the GNU
-- padding flags (and LuaJIT's os_date pushes nothing when strftime keeps
-- failing). But `frontend/datetime.lua` has a `jit.os == "Windows"` branch that
-- avoids those flags, so the question is whether anything a user sees is
-- actually affected.
--
-- Check the real call paths rather than the raw primitive.
local tmp = os.getenv("TEMP") or "."
local out = io.open(tmp .. "/koclock.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

local datetime = require("datetime")

w("=== the reader footer clock (readerfooter.lua uses secondsToHour) ===")
for _, h in ipairs({ 0, 9, 12, 13, 23 }) do
    local t = os.time({ year = 2026, month = 10, day = 13, hour = h, min = 5, sec = 0 })
    w(string.format("  %02d:05  ->  24h='%s'   12h='%s'",
        h,
        tostring(datetime.secondsToHour(t, false)),
        tostring(datetime.secondsToHour(t, true))))
end

w("")
w("=== full date+time (book list, book info, menus) ===")
local t = os.time({ year = 2026, month = 10, day = 13, hour = 9, min = 57, sec = 39 })
for _, use_locale in ipairs({ false, true }) do
    w(string.format("  secondsToDateTime(t, nil, %-5s) -> '%s'",
        tostring(use_locale), tostring(datetime.secondsToDateTime(t, nil, use_locale))))
end

w("")
w("=== anything that still returns a non-string? ===")
local bad = 0
local probes = {
    { "secondsToHour 24h",  function() return datetime.secondsToHour(t, false) end },
    { "secondsToHour 12h",  function() return datetime.secondsToHour(t, true) end },
    { "secondsToDateTime",  function() return datetime.secondsToDateTime(t) end },
    { "secondsToDate",      function() return datetime.secondsToDate(t) end },
    { "secondsToHour(wall)",function() return datetime.secondsToHour(os.time(), false) end },
}
for _, p in ipairs(probes) do
    local ok, v = pcall(p[2])
    local is_str = ok and type(v) == "string"
    if not is_str then bad = bad + 1 end
    w(string.format("  %-20s %-8s %s", p[1],
        is_str and "string" or type(v), tostring(v)))
end

w("")
if bad == 0 then
    w("RESULT: every user-facing time renders as a string. The raw")
    w("        os.date('%_H') failure is not reachable through datetime.lua,")
    w("        because its Windows branch avoids the GNU flags.")
else
    w("RESULT: " .. bad .. " user-facing call(s) do NOT return a string.")
end

out:close()
return true
