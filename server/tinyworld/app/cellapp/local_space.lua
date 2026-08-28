-- tinyworld/app/cellapp/local_space.lua
-- 局部 space: 纯数据边界。
-- 只提供本 cellapp 上的 cell 集合与 space 公共数据。
-- 一切行为(migration / ghost / 广播 / 视野)都在 Cell 或 cellapp 服务中。
-- space 公共配置由 world 创建 space 后下发, cellapp 不读取业务 space 配置。

local class = require "tinyworld.core.class"
local cellMod = require "tinyworld.app.cellapp.cell"

local LocalSpace = class.makeClass("LocalSpace")

function LocalSpace:ctor(app)
    self.app = app
    self.config = app and app.spaceConfig
    self.spaceId = self.config and self.config.id
    self.cells = {}
    self.byKey = {}
end

-- world 下发 space 配置与本 app 负责的 cells
function LocalSpace:bind(config, cells)
    self.config = config
    self.spaceId = config and config.id or nil

    self.cells = {}
    self.byKey = {}
    for _, cellInfo in ipairs(cells or {}) do
        self:addLocalCell(cellInfo)
    end
end

function LocalSpace:addLocalCell(cellInfo)
    local cell = cellMod.new(cellInfo, self.app, self)
    self.cells[#self.cells + 1] = cell
    self.byKey[cellInfo.id] = cell
    return cell
end

function LocalSpace:getCell(key)
    return self.byKey[key]
end

function LocalSpace:isLocal(key)
    return self.byKey[key] ~= nil
end

function LocalSpace:tick(dt)
    for _, cell in ipairs(self.cells) do
        cell:tick(dt)
    end
end

return LocalSpace
