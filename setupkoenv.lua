-- Set search path for `require()`.
package.path =
    "base/?.lua;base/?/init.lua;base/common/?.lua;base/common/?/init.lua;" ..
    "base/frontend/?.lua;base/frontend/?/init.lua;base/plugins/exporter.koplugin/?.lua;" ..
    "common/?.lua;common/?/init.lua;frontend/?.lua;frontend/?/init.lua;plugins/exporter.koplugin/?.lua;" ..
    package.path
package.cpath =
    "common/?.dll;common/?.so;/usr/lib/lua/?.so;" ..
    package.cpath
-- Setup `ffi.load` override and 'loadlib' helper.
local ok = pcall(require, "ffi/loadlib")
if not ok then
    -- loadlib module not available, using default ffi.load behavior
end
