# Windows 功能补充计划

## 📋 优先级排序

### 高优先级（应该立即做）

#### 1. 文件关联 🔴
**影响**：用户无法双击打开文件
**难度**：中等
**预计时间**：2-4 小时

#### 2. 基本安装程序 🔴
**影响**：用户体验不专业
**难度**：中等
**预计时间**：4-6 小时

#### 3. 修复 libs/ 打包问题 🔴
**影响**：阻塞自动发布
**难度**：低
**预计时间**：1-2 小时

---

### 中优先级（应该做）

#### 4. Windows 通知 🟡
**影响**：用户体验
**难度**：低
**预计时间**：2-3 小时

#### 5. 开始菜单快捷方式 🟡
**影响**：易用性
**难度**：低
**预计时间**：1 小时

#### 6. 卸载程序 🟡
**影响**：完整性
**难度**：中等
**预计时间**：2-3 小时

---

### 低优先级（可选）

#### 7. 系统托盘 🟢
**影响**：高级功能
**难度**：中等
**预计时间**：3-4 小时

#### 8. 右键菜单集成 🟢
**影响**：便利性
**难度**：中等
**预计时间**：2-3 小时

#### 9. Direct2D 渲染 🟢
**影响**：性能
**难度**：高
**预计时间**：8-12 小时

---

## 🎯 立即开始：文件关联

### 实现方案

**Windows 文件关联需要**：
1. 注册表项创建
2. 文件类型关联
3. 图标提取/设置
4. "打开方式"菜单项

### 实现位置

**新文件**：`frontend/device/windows/file_associations.lua`

**修改文件**：
- `frontend/device/generic/device.lua` - 设置 `canAssociateFileExtensions = yes`
- `frontend/ui/elements/menu_file_manager.lua` - 添加菜单项

---

## 📝 代码实现框架

### 1. FFI 定义（访问 Windows 注册表）

```lua
-- frontend/ffi/windows_registry.lua
local ffi = require("ffi")

ffi.cdef[[
    typedef void* HKEY;
    typedef unsigned long DWORD;
    typedef const char* LPCSTR;
    
    int RegCreateKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD Reserved,
                        LPSTR lpClass, DWORD dwOptions, DWORD samDesired,
                        void* lpSecurityAttributes, HKEY* phkResult,
                        DWORD* lpdwDisposition);
    int RegSetValueExA(HKEY hKey, LPCSTR lpValueName, DWORD Reserved,
                       DWORD dwType, const void* lpData, DWORD cbData);
    int RegCloseKey(HKEY hKey);
]]

local advapi32 = ffi.load("Advapi32")

local WindowsRegistry = {
    HKEY_CURRENT_USER = ffi.cast("HKEY", 0x80000001),
    KEY_WRITE = 0x20006,
    REG_SZ = 1,
}

function WindowsRegistry:createKey(path)
    local hkey = ffi.new("HKEY[1]")
    local result = advapi32.RegCreateKeyExA(
        self.HKEY_CURRENT_USER,
        path,
        0, nil, 0,
        self.KEY_WRITE,
        nil, hkey, nil
    )
    return result == 0 and hkey[0] or nil
end

function WindowsRegistry:setValue(hkey, name, value)
    local result = advapi32.RegSetValueExA(
        hkey, name, 0, self.REG_SZ,
        value, #value + 1
    )
    return result == 0
end

function WindowsRegistry:closeKey(hkey)
    advapi32.RegCloseKey(hkey)
end

return WindowsRegistry
```

### 2. 文件关联实现

```lua
-- frontend/device/windows/file_associations.lua
local ffi = require("ffi")
local WindowsRegistry = require("ffi/windows_registry")

local FileAssociations = {}

-- 支持的文件扩展名
FileAssociations.SUPPORTED_EXTENSIONS = {
    ".epub", ".pdf", ".mobi", ".azw", ".azw3",
    ".fb2", ".djvu", ".cbz", ".cbr", ".txt",
    ".html", ".htm", ".zip", ".doc", ".docx"
}

function FileAssociations:getExecutablePath()
    local buf = ffi.new("char[?]", 4096)
    local kernel32 = ffi.load("kernel32")
    ffi.cdef[[
        unsigned long GetModuleFileNameA(void* hModule, char* lpFilename, unsigned long nSize);
    ]]
    local len = kernel32.GetModuleFileNameA(nil, buf, 4096)
    if len > 0 then
        return ffi.string(buf, len)
    end
    return nil
end

function FileAssociations:registerExtension(ext)
    local exe_path = self:getExecutablePath()
    if not exe_path then
        return false, "Cannot get executable path"
    end
    
    -- 创建文件类型关联
    -- HKCU\Software\Classes\.epub = KOReader.Document
    local hkey = WindowsRegistry:createKey("Software\\Classes\\" .. ext)
    if not hkey then
        return false, "Cannot create registry key for " .. ext
    end
    
    WindowsRegistry:setValue(hkey, "", "KOReader.Document")
    WindowsRegistry:closeKey(hkey)
    
    -- 创建命令关联
    -- HKCU\Software\Classes\KOReader.Document\shell\open\command
    hkey = WindowsRegistry:createKey("Software\\Classes\\KOReader.Document\\shell\\open\\command")
    if not hkey then
        return false, "Cannot create command key"
    end
    
    local command = string.format('"%s" "%%1"', exe_path)
    WindowsRegistry:setValue(hkey, "", command)
    WindowsRegistry:closeKey(hkey)
    
    -- 通知 Windows 更新文件关联
    local shell32 = ffi.load("shell32")
    ffi.cdef[[
        void SHChangeNotify(long wEventId, unsigned int uFlags, const void* dwItem1, const void* dwItem2);
    ]]
    shell32.SHChangeNotify(0x08000000, 0x0000, nil, nil) -- SHCNE_ASSOCCHANGED
    
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
            table.insert(errors, ext .. ": " .. err)
        end
    end
    
    return success_count, errors
end

function FileAssociations:isAssociated(ext)
    -- 检查扩展名是否已关联到 KOReader
    -- TODO: 实现读取注册表检查
    return false
end

return FileAssociations
```

### 3. UI 菜单集成

```lua
-- 在 frontend/apps/filemanager/filemanagermenu.lua 中添加

function FileManagerMenu:setWindowsFileAssociations()
    local FileAssociations = require("device/windows/file_associations")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")
    
    UIManager:show(ConfirmBox:new{
        text = _("Associate supported file formats with KOReader?\n\nThis will allow you to double-click files to open them in KOReader."),
        ok_text = _("Associate"),
        ok_callback = function()
            local success_count, errors = FileAssociations:registerAllExtensions()
            
            local message
            if #errors == 0 then
                message = string.format(_("Successfully associated %d file types with KOReader."), success_count)
            else
                message = string.format(_("Associated %d file types.\n\nErrors:\n%s"), 
                                      success_count, table.concat(errors, "\n"))
            end
            
            UIManager:show(InfoMessage:new{
                text = message,
                timeout = 5,
            })
        end,
    })
end
```

### 4. 修改 Device 定义

```lua
-- 在 frontend/device/generic/device.lua 中

-- 找到这一行并修改：
canAssociateFileExtensions = no,  -- 改为 yes

-- 添加方法：
function Device:associateFileExtensions()
    if not self.canAssociateFileExtensions then
        return false
    end
    
    if self:isWin32() then
        local FileAssociations = require("device/windows/file_associations")
        return FileAssociations:registerAllExtensions()
    end
    
    return false
end
```

---

## 🔧 测试方案

```lua
-- tests/file_associations_spec.lua
describe("Windows File Associations", function()
    local FileAssociations
    
    setup(function()
        FileAssociations = require("device/windows/file_associations")
    end)
    
    it("should get executable path", function()
        local path = FileAssociations:getExecutablePath()
        assert.is_not_nil(path)
        assert.is_true(path:match("koreader%.exe$") ~= nil)
    end)
    
    it("should register extension", function()
        local success = FileAssociations:registerExtension(".epub")
        assert.is_true(success)
    end)
    
    it("should register all extensions", function()
        local count, errors = FileAssociations:registerAllExtensions()
        assert.is_true(count > 0)
        assert.is_true(#errors == 0)
    end)
end)
```

---

## 📋 实现步骤

### 第1步：创建基础文件（30分钟）
- [ ] `frontend/ffi/windows_registry.lua`
- [ ] `frontend/device/windows/file_associations.lua`

### 第2步：集成到 UI（30分钟）
- [ ] 修改 `device.lua`
- [ ] 在文件管理器菜单添加选项

### 第3步：测试（1小时）
- [ ] 单元测试
- [ ] 手动测试注册表更改
- [ ] 测试双击打开文件

### 第4步：文档（30分钟）
- [ ] 用户指南
- [ ] 开发者文档

---

## 💡 注意事项

### 权限问题
- 修改 HKEY_CURRENT_USER 不需要管理员权限
- 如果用户想要全局关联（所有用户），需要提升权限

### 兼容性
- Windows 10 1903+ （已经是最低要求）
- 支持 UTF-8 路径

### 回退方案
- 提供取消关联功能
- 记录原有关联

---

要开始实现文件关联功能吗？我可以创建这些文件并进行初步测试。
