-- Associate document extensions with this executable, on Windows.
--
-- The rest of KOReader already knows how to drive this: `Device` exposes
-- `canAssociateFileExtensions` and `associateFileExtensions`, and
-- `ui/elements/file_ext_assoc.lua` builds the settings menu from them. The
-- PocketBook backend implements the same two; this is the Windows counterpart,
-- writing to `HKCU\Software\Classes` so no elevation is needed.

local ffi = require("ffi")
local logger = require("logger")

ffi.cdef[[
    // Windows Registry API
    typedef void* HKEY;
    typedef unsigned long DWORD;
    typedef const char* LPCSTR;
    typedef char* LPSTR;

    long RegCreateKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD Reserved,
                        LPSTR lpClass, DWORD dwOptions, DWORD samDesired,
                        void* lpSecurityAttributes, HKEY* phkResult,
                        DWORD* lpdwDisposition);
    long RegOpenKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD ulOptions,
                       DWORD samDesired, HKEY* phkResult);
    long RegEnumKeyExA(HKEY hKey, DWORD dwIndex, LPSTR lpName,
                       DWORD* lpcchName, DWORD* lpReserved, LPSTR lpClass,
                       DWORD* lpcchClass, void* lpftLastWriteTime);
    long RegQueryValueExA(HKEY hKey, LPCSTR lpValueName, DWORD* lpReserved,
                          DWORD* lpType, unsigned char* lpData,
                          DWORD* lpcbData);
    long RegSetValueExA(HKEY hKey, LPCSTR lpValueName, DWORD Reserved,
                       DWORD dwType, const void* lpData, DWORD cbData);
    long RegCloseKey(HKEY hKey);
    long RegDeleteKeyA(HKEY hKey, LPCSTR lpSubKey);

    // Shell API for notification
    void SHChangeNotify(long wEventId, unsigned int uFlags, const void* dwItem1, const void* dwItem2);

    // Get executable path
    unsigned long GetModuleFileNameA(void* hModule, char* lpFilename, unsigned long nSize);
]]

local advapi32 = ffi.load("Advapi32")
local shell32 = ffi.load("shell32")
local kernel32 = ffi.load("kernel32")

local FileAssociations = {}

-- Registry constants
local HKEY_CURRENT_USER = ffi.cast("HKEY", 0x80000001)
local KEY_WRITE = 0x20006
local KEY_READ = 0x20019
local REG_SZ = 1
local SHCNE_ASSOCCHANGED = 0x08000000
local SHCNF_IDLIST = 0x0000

-- Every extension points at this one ProgID, which in turn holds the icon and
-- the open command. Sharing it means the command line is written once per
-- associate run rather than once per extension.
local PROGID = "KOReader.Document"

function FileAssociations:getExecutablePath()
    local buf = ffi.new("char[?]", 4096)
    local len = kernel32.GetModuleFileNameA(nil, buf, 4096)
    if len > 0 and len < 4096 then
        return ffi.string(buf, len)
    end
    logger.warn("Failed to get executable path")
    return nil
end

function FileAssociations:createRegistryKey(path)
    local hkey = ffi.new("HKEY[1]")
    local result = advapi32.RegCreateKeyExA(
        HKEY_CURRENT_USER,
        path,
        0, nil, 0,
        KEY_WRITE,
        nil, hkey, nil
    )

    if result == 0 then
        return hkey[0]
    end

    logger.warn("Failed to create registry key:", path, "error:", result)
    return nil
end

-- Extensions this program currently owns, discovered from the registry rather
-- than from a list in the source: `HKCU\Software\Classes\<ext>` whose default
-- value is our ProgID.
--
-- Reading the registry is what makes removal correct. A list kept in the source
-- can only name extensions some version of the code knew about, so anything
-- registered by an older build and since dropped would never be cleaned up.
function FileAssociations:listRegisteredExtensions()
    local result = {}
    local classes = ffi.new("HKEY[1]")
    local rc = advapi32.RegOpenKeyExA(
        HKEY_CURRENT_USER,
        "Software\\Classes",
        0,
        KEY_READ,
        classes
    )
    if rc ~= 0 then
        logger.warn("Cannot open Software\\Classes, error:", rc)
        return result
    end

    local index = 0
    while true do
        local name = ffi.new("char[256]")
        local name_len = ffi.new("DWORD[1]", 256)
        rc = advapi32.RegEnumKeyExA(classes[0], index, name, name_len,
                                    nil, nil, nil, nil)
        -- ERROR_NO_MORE_ITEMS (259) ends the enumeration; anything else is a real
        -- failure and also ends it, since continuing would not make progress.
        if rc ~= 0 then
            break
        end
        index = index + 1

        local ext = ffi.string(name, name_len[0])
        -- Only dotted names are candidate extensions; the default value of one of
        -- ours is the ProgID, which is what `getProgId` checks below.
        if ext:sub(1, 1) == "." and self:getProgId(ext) == PROGID then
            result[#result + 1] = ext
        end
    end

    advapi32.RegCloseKey(classes[0])
    return result
end

function FileAssociations:getProgId(ext)
    local hkey = ffi.new("HKEY[1]")
    local rc = advapi32.RegOpenKeyExA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\" .. ext,
        0,
        KEY_READ,
        hkey
    )
    if rc ~= 0 then
        return nil
    end

    local buf = ffi.new("char[256]")
    local buf_len = ffi.new("DWORD[1]", 256)
    rc = advapi32.RegQueryValueExA(hkey[0], nil, nil, nil, buf, buf_len)
    advapi32.RegCloseKey(hkey[0])
    if rc ~= 0 then
        return nil
    end
    -- REG_SZ values are stored with the terminator counted in `buf_len`.
    return ffi.string(buf, math.max(0, buf_len[0] - 1))
end

function FileAssociations:setRegistryValue(hkey, name, value)
    local result = advapi32.RegSetValueExA(
        hkey,
        name,
        0,
        REG_SZ,
        value,
        #value + 1
    )

    if result ~= 0 then
        logger.warn("Failed to set registry value:", name, "error:", result)
    end

    return result == 0
end

function FileAssociations:closeRegistryKey(hkey)
    advapi32.RegCloseKey(hkey)
end

function FileAssociations:notifyShell()
    -- Notify Windows that file associations have changed
    shell32.SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil)
end

function FileAssociations:registerExtension(ext)
    local exe_path = self:getExecutablePath()
    if not exe_path then
        return false, "Cannot get executable path"
    end

    logger.info("Registering file association for", ext)

    -- Step 1: point the extension at the ProgID.
    --   HKCU\Software\Classes\.epub  (default) = "KOReader.Document"
    local hkey = self:createRegistryKey("Software\\Classes\\" .. ext)
    if not hkey then
        return false, "Cannot create registry key for " .. ext
    end
    self:setRegistryValue(hkey, "", PROGID)
    self:closeRegistryKey(hkey)

    -- Steps 2-4 maintain the ProgID. They are idempotent, and rerunning them on
    -- every extension is what keeps the stored `exe_path` current: the program
    -- may have been moved since the associations were first written.
    local progid_key = "Software\\Classes\\" .. PROGID

    -- Step 2: the friendly name the shell displays.
    hkey = self:createRegistryKey(progid_key)
    if hkey then
        self:setRegistryValue(hkey, "", "KOReader Document")
        self:closeRegistryKey(hkey)
    end

    -- Step 3: icon, taken from the executable.
    hkey = self:createRegistryKey(progid_key .. "\\DefaultIcon")
    if hkey then
        self:setRegistryValue(hkey, "", exe_path .. ",0")
        self:closeRegistryKey(hkey)
    end

    -- Step 4: the command. `%1` is the file the shell was asked to open; the
    -- surrounding quotes matter because the path can contain spaces.
    hkey = self:createRegistryKey(progid_key .. "\\shell\\open\\command")
    if not hkey then
        return false, "Cannot create command key"
    end

    local command = string.format('"%s" "%%1"', exe_path)
    local success = self:setRegistryValue(hkey, "", command)
    self:closeRegistryKey(hkey)

    if not success then
        return false, "Cannot set command value"
    end

    return true
end

function FileAssociations:unregisterExtension(ext)
    logger.info("Unregistering file association for", ext)

    local result = advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\" .. ext
    )
    if result ~= 0 then
        return false
    end

    -- The ProgID is shared, so it has to stay while any extension still points at
    -- it. Only the last removal drops it, and the depth-first order matters:
    -- `RegDeleteKeyA` refuses to delete a key that still has subkeys.
    local remaining = false
    for _, other in ipairs(self:listRegisteredExtensions()) do
        if other ~= ext then
            remaining = true
            break
        end
    end

    if not remaining then
        local progid_key = "Software\\Classes\\" .. PROGID
        for _, sub in ipairs({
            "\\shell\\open\\command",
            "\\shell\\open",
            "\\shell",
            "\\DefaultIcon",
            "",
        }) do
            advapi32.RegDeleteKeyA(HKEY_CURRENT_USER, progid_key .. sub)
        end
    end

    return true
end


return FileAssociations
