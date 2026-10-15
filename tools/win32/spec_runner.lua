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
-- luassert's signature is `is_equal(expected, actual)`: the *first* argument is
-- what the spec expects, and the second is what it got. Reporting them the other
-- way round produces failure messages that name the values backwards, which is
-- actively misleading — a spec whose two values matched would print
-- "expected X, got X".
function A.is_equal(expected, actual, m)
    if expected ~= actual then
        fail((m and (m .. ": ") or "") .. "expected " .. tostring(expected)
             .. ", got " .. tostring(actual))
    end
end
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
-- luassert's `same` is a *deep* comparison -- it walks nested tables, and
-- compares by value rather than identity. This used to check only the top
-- level (`a[k] ~= v`), so a spec comparing tables of tables failed with
-- "tables differ at 1" even when the contents matched, which is a bug in the
-- test double rather than in what the spec was testing.
local function deep_equal(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    -- Guards against a cycle in either table.
    seen = seen or {}
    if seen[a] and seen[a][b] then return true end
    seen[a] = seen[a] or {}
    seen[a][b] = true
    for k, v in pairs(a) do
        if not deep_equal(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function A.are_same(a,b,m)
    if not deep_equal(a, b) then
        fail((m and (m..": ") or "").."expected the same, got different")
    end
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
-- ---------------------------------------------------------------------------
-- Aliases.
--
-- Deliberately after every function above: these are plain assignments, so
-- naming one before its target is defined stores `nil` and fails the spec later
-- with `attempt to call field 'X' (a nil value)` -- which is exactly what
-- `A.Same = A.are_same` did, silently, until the upstream merge started
-- exercising it.
--
-- luassert gives each assertion several spellings, and the specs use a mix.
local function not_same(a, b, m)
    if a == b then fail(m or "expected different") end
end
local function not_near(a, b, tol, m)
    if math.abs(a - b) <= (tol or 1e-9) then fail(m or "expected different") end
end

A.equals = A.is_equal
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
A.not_truthy = function(v,m) if v then fail(m or "expected falsy") end end
A.is_truthy = A.truthy
A.is_same = A.are_same
A.is_not_true = function(v,m) if v==true then fail(m or "expected not true") end end
A.is_near = function(a,b,tol,m)
    if math.abs(a-b) > (tol or 1e-9) then fail(m or "expected near") end
end
A.are = { same = A.are_same, equal = A.are_equal, not_equal = not_same }
-- luassert spells the negated forms `are_not`/`is_not`, and both are used.
A.are_not = A.are
A.is = { True=A.is_true, False=A.is_false, Nil=A.is_nil, equal=A.is_equal,
         truthy=A.truthy, not_equal=not_same }
A.is_not = { Nil = A.is_not_nil, True = A.is_not_true,
             same = not_same, equals = not_same, Equals = not_same,
             equal = not_same, near = not_near }
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

-- Tidy up after the specs.
--
-- Some of them write to the *working directory* with relative paths — notably
-- `cachesqlite_spec.lua`/`cache_spec.lua`, which use `db_path = "test.db"`.
-- Under the normal harness that lands in a scratch checkout and nobody notices;
-- here the working directory is the application's own directory, so the file
-- ends up shipped next to `koreader.exe`. Remove the known ones so a test run
-- does not leave junk in the install tree.
local leftovers = { "test.db", "test.db-journal", "test.db-wal", "test.db-shm" }
local removed = {}
for _, name in ipairs(leftovers) do
    if os.remove(name) then removed[#removed + 1] = name end
end
if #removed > 0 then
    w("cleaned: " .. table.concat(removed, " "))
end

w("DONE")
out:close()
return true
