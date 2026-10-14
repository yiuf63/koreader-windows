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
--
-- Not fatal: without it `ffi.loadlib` keeps its default behaviour, which still
-- resolves plain names. Say so rather than failing silently, because every
-- `ffi.loadlib` call site would otherwise behave subtly differently with no
-- indication of why.
local ok, err = pcall(require, "ffi/loadlib")
if not ok then
    io.stderr:write("ffi/loadlib not available, using default ffi.load: ",
                    tostring(err), "\n")
end
