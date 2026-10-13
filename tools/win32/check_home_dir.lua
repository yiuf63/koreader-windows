-- Check what `Device.home_dir` resolves to, and that font_settings loads.
--
-- The Windows build had a nil `home_dir` when started from Explorer, because it
-- derived from `HOME`, which only a POSIX shell sets. Anything concatenating it
-- then failed — `font_settings.lua` did, aborting startup. This records the
-- resolved value so the fallback can be confirmed rather than assumed.
local out = io.open("D:/ko-launch-test/home_dir.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end

w("HOME          = " .. tostring(os.getenv("HOME")))
w("USERPROFILE   = " .. tostring(os.getenv("USERPROFILE")))
w("XDG_DOCUMENTS_DIR = " .. tostring(os.getenv("XDG_DOCUMENTS_DIR")))
w("jit.os        = " .. tostring(jit.os))
w("")

local ok, Device = pcall(require, "device")
w("require device: " .. tostring(ok))
if ok then
    w("Device.home_dir = " .. tostring(Device.home_dir))
    w("is nil?         = " .. tostring(Device.home_dir == nil))
end

w("")
local ok2, fs = pcall(require, "ui/elements/font_settings")
w("require font_settings: " .. tostring(ok2)
    .. (ok2 and "" or (" -> " .. tostring(fs))))
out:close()
return true
