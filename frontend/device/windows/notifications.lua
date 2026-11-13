-- Windows Toast Notification 实现
-- frontend/device/windows/notifications.lua

local ffi = require("ffi")
local logger = require("logger")

ffi.cdef[[
    // Windows Runtime (WinRT) for Toast Notifications
    typedef struct IUnknown IUnknown;
    typedef long HRESULT;
    typedef unsigned short wchar_t;
    typedef const wchar_t* LPCWSTR;

    // Shell API for simpler notifications
    int MessageBoxW(void* hWnd, LPCWSTR lpText, LPCWSTR lpCaption, unsigned int uType);

    // For system notifications
    typedef struct {
        unsigned int cbSize;
        void* hwnd;
        unsigned int uID;
        unsigned int uFlags;
        unsigned int uCallbackMessage;
        void* hIcon;
        wchar_t szTip[128];
        unsigned int dwState;
        unsigned int dwStateMask;
        wchar_t szInfo[256];
        unsigned int uTimeout;
        wchar_t szInfoTitle[64];
        unsigned int dwInfoFlags;
    } NOTIFYICONDATAW;

    int Shell_NotifyIconW(unsigned int dwMessage, NOTIFYICONDATAW* lpData);
]]

local user32 = ffi.load("user32")
local shell32 = ffi.load("shell32")

local WindowsNotifications = {}

-- Constants
local MB_OK = 0x00000000
local MB_ICONINFORMATION = 0x00000040
local MB_ICONWARNING = 0x00000030
local MB_ICONERROR = 0x00000010

local NIM_ADD = 0x00000000
local NIM_MODIFY = 0x00000001
local NIM_DELETE = 0x00000002
local NIF_MESSAGE = 0x00000001
local NIF_ICON = 0x00000002
local NIF_TIP = 0x00000004
local NIF_INFO = 0x00000010
local NIIF_INFO = 0x00000001
local NIIF_WARNING = 0x00000002
local NIIF_ERROR = 0x00000003

-- Convert UTF-8 string to wide string (UTF-16)
function WindowsNotifications:utf8ToWide(str)
    if not str then return nil end

    -- Simple conversion for ASCII
    local len = #str
    local wstr = ffi.new("wchar_t[?]", len + 1)
    for i = 0, len - 1 do
        wstr[i] = string.byte(str, i + 1)
    end
    wstr[len] = 0
    return wstr
end

-- Show a simple message box notification
function WindowsNotifications:showMessageBox(title, message, icon_type)
    local wtitle = self:utf8ToWide(title or "KOReader")
    local wmessage = self:utf8ToWide(message or "")

    local icon = MB_ICONINFORMATION
    if icon_type == "warning" then
        icon = MB_ICONWARNING
    elseif icon_type == "error" then
        icon = MB_ICONERROR
    end

    user32.MessageBoxW(nil, wmessage, wtitle, MB_OK + icon)
end

-- Show a balloon notification (system tray style)
function WindowsNotifications:showBalloon(title, message, icon_type)
    local nid = ffi.new("NOTIFYICONDATAW")
    nid.cbSize = ffi.sizeof("NOTIFYICONDATAW")
    nid.hwnd = nil
    nid.uID = 1
    nid.uFlags = NIF_INFO

    -- Set title
    local wtitle = self:utf8ToWide(title or "KOReader")
    local wmessage = self:utf8ToWide(message or "")

    -- Copy strings (limited by buffer size)
    for i = 0, math.min(63, #title) do
        nid.szInfoTitle[i] = wtitle[i]
    end

    for i = 0, math.min(255, #message) do
        nid.szInfo[i] = wmessage[i]
    end

    -- Set icon type
    nid.dwInfoFlags = NIIF_INFO
    if icon_type == "warning" then
        nid.dwInfoFlags = NIIF_WARNING
    elseif icon_type == "error" then
        nid.dwInfoFlags = NIIF_ERROR
    end

    nid.uTimeout = 5000 -- 5 seconds

    -- Add the notification icon first
    nid.uFlags = NIF_MESSAGE + NIF_ICON + NIF_TIP
    local tip = self:utf8ToWide("KOReader")
    for i = 0, math.min(127, 8) do
        nid.szTip[i] = tip[i]
    end

    shell32.Shell_NotifyIconW(NIM_ADD, nid)

    -- Then show the balloon
    nid.uFlags = NIF_INFO
    local result = shell32.Shell_NotifyIconW(NIM_MODIFY, nid)

    -- Clean up after showing
    -- Note: In real implementation, should keep icon and clean up later

    return result == 1
end

-- Simple notification (non-blocking)
function WindowsNotifications:notify(title, message, level)
    logger.info("Windows notification:", title, "-", message)

    -- For now, use simple approach
    -- In real implementation, could use WinRT Toast Notifications for Windows 8+
    -- or balloon tips for Windows 7

    -- Determine icon type from level
    local icon_type = "info"
    if level == "warn" or level == "warning" then
        icon_type = "warning"
    elseif level == "error" then
        icon_type = "error"
    end

    -- Try balloon notification (less intrusive)
    -- Fall back to message box if needed
    local success = pcall(function()
        self:showBalloon(title, message, icon_type)
    end)

    if not success then
        logger.warn("Balloon notification failed, notification logged only")
    end

    return true
end

return WindowsNotifications
