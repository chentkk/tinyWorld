-- tinyworld/app/cellapp/local_space.lua
-- 局部 space: 某个 space 在本 cellapp 上的运行态。
-- 只管理该 space 在本 app 上的 cell 集合与 space 公共数据(几何/AOI/bounds)。
-- 一切行为(migration / ghost / 广播 / 视野)都在 Cell 或 cellapp 服务中。

local class = require "tinyworld.core.class"
local cellMod = require "tinyworld.app.cellapp.cell"

local LocalSpace = class.makeClass("LocalSpace")

function LocalSpace:ctor(host, config, cells)
    self.host = host
    config = config or (host and host.spaceConfig)
    self.config = config
    self.id = config and config.id
    self.bounds = (config and config.bounds)
        or { x1 = 0, y1 = 0, x2 = (config and config.width) or 0, y2 = (config and config.height) or 0 }
    self.cells = {}
    self.byKey = {}

    for _, cellInfo in ipairs(cells or {}) do
        self:addLocalCell(cellInfo)
    end
end

function LocalSpace:addLocalCell(cellInfo)
    local cell = cellMod.new(cellInfo, self.host, self)
    self.cells[#self.cells + 1] = cell
    self.byKey[cellInfo.id] = cell
    return cell
end

function LocalSpace:getSpaceId()
    return self.id
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
