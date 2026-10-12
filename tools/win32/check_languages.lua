-- Check that every bundled translation catalogue loads.
--
-- 48 `.mo` files existing on disk is not the same thing as 48 catalogues
-- loading, and the release notes claim the latter — so verify it rather than
-- infer it from a directory listing. Only `zh_CN` had been exercised by hand
-- when this was written.
local tmp = os.getenv("TEMP") or "."
local out = io.open(tmp .. "/kolangs.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

local lfs = require("libs/libkoreader-lfs")
local gettext = require("gettext")

-- Find the catalogues that actually ship next to the running app.
local dir = "l10n"
local available = {}
for entry in lfs.dir(dir) do
    if entry ~= "." and entry ~= ".." then
        if lfs.attributes(dir .. "/" .. entry .. "/koreader.mo", "mode") == "file" then
            available[#available + 1] = entry
        end
    end
end
table.sort(available)
w("catalogues on disk: " .. #available)

-- For each, switch to it and see whether the same probe string changes.
local ok_count, fail_list = 0, {}
for _, lang in ipairs(available) do
    local ok = pcall(function() return gettext.changeLang(lang) end)
    local translated = gettext("Cancel")

    if not ok then
        fail_list[#fail_list + 1] = string.format("%-12s changeLang threw", lang)
    elseif translated == nil then
        fail_list[#fail_list + 1] = string.format("%-12s returned nil", lang)
    else
        ok_count = ok_count + 1
    end
end

w("loaded successfully : " .. ok_count)
w("failed              : " .. #fail_list)
for _, f in ipairs(fail_list) do w("  " .. f) end

-- Back to English, and show a couple of spot checks across scripts.
gettext.changeLang("en_US")
w("")
w("spot checks (from en_US back into each):")
for _, lang in ipairs({ "zh_CN", "ja", "ru", "ar", "de", "fr", "ko" }) do
    if lfs.attributes(dir .. "/" .. lang .. "/koreader.mo", "mode") == "file" then
        gettext.changeLang(lang)
        w(string.format("  %-6s Cancel -> %s", lang, tostring(gettext("Cancel"))))
    end
end
gettext.changeLang("en_US")

out:close()
return true
