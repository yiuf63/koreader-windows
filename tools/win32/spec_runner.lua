-- Run a *single* KOReader frontend spec against the Windows build.
--
-- Installed as a user patch by `tools/win32/run_specs.sh`, which runs one spec
-- per process (a few specs hard-crash the process, and that way a crash costs
-- only that spec). This file supplies the slice of busted's API the specs use,
-- since there is no busted for the win32 target.
--
-- The spec to run is read from a file: a user patch cannot be given arguments.
local tmp = os.getenv("TEMP") or "."

-- Locate the source tree from the running executable's directory, so this works
-- from a build tree as well as from an extracted release.
local root = "D:/Code/koreader"
do
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok then
        -- The launcher runs from `<root>/koreader-win32-<machine>/koreader`, or
        -- from `<root>` in a plain build tree.
        local cwd = lfs.currentdir()
        for _, cand in ipairs({ cwd .. "/../..", cwd .. "/..", cwd }) do
            if lfs.attributes(cand .. "/spec/unit", "mode") == "directory" then
                root = cand
                break
            end
        end
    end
end

local which = ""
do
    local nf = io.open(tmp .. "/kospec_name.txt", "r")
    if nf then which = nf:read("*a") or "" nf:close() end
    which = which:gsub("%s+$", "")
end

local out = io.open(tmp .. "/kotest_one.txt", "w")
local function w(s) out:write(s .. "\n") out:flush() end
w("spec: " .. which)

package.path = root .. "/spec/unit/?.lua;" .. package.path

-- Setup that `commonrequire` would do. It is written for a *fresh* interpreter
-- (it builds the framebuffer, device and canvas from scratch), so it cannot
-- simply be required from inside a running koreader; do the same work inline,
-- as completely as possible, or the specs fail for want of the globals.
local setup_ok, setup_err = pcall(function()
    require("dbg"):turnOff()
    local logger = require("logger")
    logger:setLevel(logger.levels.warn)
    local DS = require("datastorage")
    require("libs/libkoreader-lfs").mkdir(DS:getHistoryDir())
    os.remove(DS:getDataDir() .. "/defaults.tests.lua")
    os.remove(DS:getDataDir() .. "/defaults.tests.lua.old")
    G_defaults = require("luadefaults"):open(DS:getDataDir() .. "/defaults.tests.lua")
    os.remove(DS:getDataDir() .. "/settings.tests.lua")
    os.remove(DS:getDataDir() .. "/settings.tests.lua.old")
    G_reader_settings = require("luasettings"):open(DS:getDataDir() .. "/settings.tests.lua")
    G_reader_settings:saveSetting("document_metadata_folder", "dir")

    -- Do not bring up a real window.
    einkfb = require("ffi/framebuffer")
    einkfb.dummy = true

    local Device = require("device")
    local Screen = Device.screen
    Screen:init()

    local CanvasContext = require("document/canvascontext")
    CanvasContext:init(Device)

    local Input = Device.input
    Input.dummy = true
end)
w("setup: " .. tostring(setup_ok) .. (setup_ok and "" or (" -> " .. tostring(setup_err):sub(1, 160))))
package.loaded["commonrequire"] = true

-- `commonrequire` installs these; several specs rely on them.
package.unload = function(m) if type(m) ~= "string" then return false end
    package.loaded[m] = nil; _G[m] = nil; return true end
package.replace = function(name, module) if type(name) ~= "string" then return false end
    assert(package.unload(name)); package.loaded[name] = module; return true end
package.reload = function(name) if type(name) ~= "string" then return false end
    assert(package.unload(name)); return require(name) end

_G.fastforward_ui_events = function()
    local UIManager = require("ui/uimanager")
    UIManager:shiftScheduledTasksBy(-1e9)
    UIManager:setInputTimeout(0)
    UIManager:handleInput()
end
_G.screenshot = function(screen, filename)
    screen:shot(require("datastorage"):getDataDir() .. "/screenshots/" .. filename)
end
_G.disable_plugins = function()
    local PL = require("pluginloader")
    PL.enabled_plugins, PL.disabled_plugins, PL.loaded_plugins = {}, {}, {}
end
_G.load_plugin = function(name)
    local PL = require("pluginloader")
    local t = PL:_discover()
    local id = name:gsub("%.koplugin$", "")
    for _, v in ipairs(t) do
        if v.name == id then PL:_load{v} return end
    end
    assert(false)
end

-- Minimal busted surface.
local passed, failed = 0, 0
local errors = {}
local stack = {}
local function fail(m) error(m, 3) end
local A = {}
function A.is_true(v,m) if v~=true then fail((m or "expected true")..", got "..tostring(v)) end end
function A.is_false(v,m) if v~=false then fail((m or "expected false")..", got "..tostring(v)) end end
function A.is_nil(v,m) if v~=nil then fail((m or "expected nil")..", got "..tostring(v)) end end
function A.is_not_nil(v,m) if v==nil then fail(m or "expected not nil") end end
function A.is_equal(a,b,m) if a~=b then fail((m and (m..": ") or "").."expected "..tostring(b)..", got "..tostring(a)) end end
A.are_equal = A.is_equal
-- luassert's other spellings, which several specs use.
A.Equals = A.is_equal
A.equal = A.is_equal
A.same = A.is_equal
A.truthy = function(v,m) if not v then fail(m or "expected truthy") end end
A.falsy = function(v,m) if v then fail(m or "expected falsy") end end
A.Nil = A.is_nil
-- `nil` is a reserved word, so this key needs the bracket form.
A.Not = { Nil = A.is_not_nil, ["nil"] = A.is_not_nil,
          equal = function(a,b,m) if a==b then fail(m or "expected different") end end }
A.not_equal = A.Not.equal
-- luassert exposes both `assert.is.True(...)` and bare `assert.True(...)`.
A.True = A.is_true
A.False = A.is_false
A.Equal = A.is_equal
A.Same = A.are_same
A.Table = A.is_table
A.String = A.is_string
A.Number = A.is_number
A.Function = A.is_function
A.Boolean = A.is_boolean
A.Error = function(fn, m) if pcall(fn) then fail(m or "expected an error") end end
A.Near = function(a, b, tol, m)
    if math.abs(a - b) > (tol or 1e-9) then fail((m and (m..": ") or "").."expected ~"..tostring(b)..", got "..tostring(a)) end
end
function A.are_same(a,b,m)
    if type(a)=="table" and type(b)=="table" then
        for k,v in pairs(a) do if b[k]~=v then fail("tables differ at "..tostring(k)) end end
        for k in pairs(b) do if a[k]==nil then fail("tables differ at "..tostring(k)) end end
        return
    end
    A.is_equal(a,b,m)
end
function A.is_table(v,m) if type(v)~="table" then fail((m or "expected table")..", got "..type(v)) end end
function A.is_string(v,m) if type(v)~="string" then fail((m or "expected string")..", got "..type(v)) end end
function A.is_number(v,m) if type(v)~="number" then fail((m or "expected number")..", got "..type(v)) end end
function A.is_function(v,m) if type(v)~="function" then fail((m or "expected function")..", got "..type(v)) end end
function A.is_boolean(v,m) if type(v)~="boolean" then fail((m or "expected boolean")..", got "..type(v)) end end
function A.has_error(fn,m) if pcall(fn) then fail(m or "expected an error") end end
A.has_no = { errors = function(fn,m) local ok,e=pcall(fn) if not ok then fail((m and (m..": ") or "")..tostring(e)) end end }
A.has = { errors = function(fn,m) if not pcall(fn) then fail(m or "expected no errors") end end,
          error = function(fn,m) if pcall(fn) then fail(m or "expected an error") end end }
A.are = { same = A.are_same, equal = A.are_equal }
A.is = { True=A.is_true, False=A.is_false, Nil=A.is_nil, equal=A.is_equal,
         truthy=function(v,m) if not v then fail(m or "expected truthy") end end,
         not_equal=function(a,b,m) if a==b then fail(m or "expected different") end end }
A.is_not = { Nil = A.is_not_nil }
_G.assert = setmetatable(A, { __call = function(_,v,m) if not v then error(m or "assertion failed",2) end end })
_G.describe = function(n,f) stack[#stack+1]=n; pcall(f); stack[#stack]=nil end
_G.context = _G.describe
_G.it = function(n,f)
    local full = table.concat(stack," / ").." / "..n
    local ok,err = pcall(f)
    if ok then passed=passed+1
    else failed=failed+1; errors[#errors+1]=full.." :: "..tostring(err):gsub("\n"," "):sub(1,160) end
end
_G.spec, _G.test = _G.it, _G.it
_G.setup = function(f) local ok,e=pcall(f) if not ok then errors[#errors+1]="[setup] "..tostring(e):sub(1,120) end end
_G.teardown = function() end
_G.before_each = function() end
_G.after_each = function() end
_G.pending = function() end
_G.insulate = function(a,b) local f=type(a)=="function" and a or b; if f then pcall(f) end end
_G.randomize = function() end

local chunk, lerr = loadfile(root .. "/spec/unit/" .. which)
if not chunk then
    w("load-failed: " .. tostring(lerr):sub(1, 150))
else
    local ok, err = pcall(chunk)
    if not ok then w("run-error: " .. tostring(err):gsub("\n", " "):sub(1, 200)) end
end

w(string.format("passed: %d", passed))
w(string.format("failed: %d", failed))
for _, e in ipairs(errors) do w("  FAIL " .. e) end
w("DONE")
out:close()
return true
