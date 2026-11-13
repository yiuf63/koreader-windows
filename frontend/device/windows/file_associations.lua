-- Windows 文件关联实现
-- frontend/device/windows/file_associations.lua

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
local REG_SZ = 1
local SHCNE_ASSOCCHANGED = 0x08000000
local SHCNF_IDLIST = 0x0000

-- Supported file extensions
FileAssociations.SUPPORTED_EXTENSIONS = {
    ".epub", ".pdf", ".mobi", ".azw", ".azw3",
    ".fb2", ".fb2.zip", ".djvu",
    ".cbz", ".cbr", ".cb7", ".cbt",
    ".txt", ".html", ".htm",
    ".zip", ".doc", ".docx", ".rtf"
}

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

    -- Step 1: Associate extension with ProgID
    -- HKCU\Software\Classes\.epub = KOReader.Document
    local hkey = self:createRegistryKey("Software\\Classes\\" .. ext)
    if not hkey then
        return false, "Cannot create registry key for " .. ext
    end

    self:setRegistryValue(hkey, "", "KOReader.Document")
    self:closeRegistryKey(hkey)

    -- Step 2: Create ProgID with friendly name
    -- HKCU\Software\Classes\KOReader.Document
    hkey = self:createRegistryKey("Software\\Classes\\KOReader.Document")
    if hkey then
        self:setRegistryValue(hkey, "", "KOReader Document")
        self:closeRegistryKey(hkey)
    end

    -- Step 3: Set default icon (use exe icon)
    -- HKCU\Software\Classes\KOReader.Document\DefaultIcon
    hkey = self:createRegistryKey("Software\\Classes\\KOReader.Document\\DefaultIcon")
    if hkey then
        self:setRegistryValue(hkey, "", exe_path .. ",0")
        self:closeRegistryKey(hkey)
    end

    -- Step 4: Set open command
    -- HKCU\Software\Classes\KOReader.Document\shell\open\command
    hkey = self:createRegistryKey("Software\\Classes\\KOReader.Document\\shell\\open\\command")
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

function FileAssociations:registerAllExtensions()
    local success_count = 0
    local errors = {}

    for _, ext in ipairs(self.SUPPORTED_EXTENSIONS) do
        local success, err = self:registerExtension(ext)
        if success then
            success_count = success_count + 1
        else
            table.insert(errors, ext .. ": " .. (err or "unknown error"))
        end
    end

    -- Notify shell after all associations are done
    if success_count > 0 then
        self:notifyShell()
    end

    logger.info(string.format("Registered %d/%d file associations", success_count, #self.SUPPORTED_EXTENSIONS))

    return success_count, errors
end

function FileAssociations:unregisterExtension(ext)
    logger.info("Unregistering file association for", ext)

    -- Remove extension association
    local result = advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\" .. ext
    )

    return result == 0
end

function FileAssociations:unregisterAllExtensions()
    local success_count = 0

    for _, ext in ipairs(self.SUPPORTED_EXTENSIONS) do
        if self:unregisterExtension(ext) then
            success_count = success_count + 1
        end
    end

    -- Clean up ProgID (留给最后一次卸载)
    advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\KOReader.Document\\shell\\open\\command"
    )
    advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\KOReader.Document\\shell\\open"
    )
    advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\KOReader.Document\\shell"
    )
    advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\KOReader.Document\\DefaultIcon"
    )
    advapi32.RegDeleteKeyA(
        HKEY_CURRENT_USER,
        "Software\\Classes\\KOReader.Document"
    )

    if success_count > 0 then
        self:notifyShell()
    end

    logger.info(string.format("Unregistered %d file associations", success_count))

    return success_count
end

return FileAssociations
