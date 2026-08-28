-- tinyworld/app/baseapp/player_store.lua
-- 框架侧玩家数据存储: 负责按配置从关系表读取角色行、读写 bin 存档、
-- 使用模板补齐默认数据, 并按配置从实体 records 构建 cell init data。
-- 表名与字段全部由 gameConfig.playerStore 提供, 本模块不感知具体游戏业务。

local bin = require "tinyworld.core.bin"
local class = require "tinyworld.core.class"

local PlayerStore = class.makeClass("PlayerStore")

function PlayerStore:ctor(db, cfg)
    assert(db and db.query and db.exec, "player store needs db")
    assert(cfg, "player store needs config")

    self.db = db
    self.playerTable = cfg.playerTable or "players"
    self.binTable = cfg.binTable or "player_bin"
    self.accountIdField = cfg.accountIdField or "account_id"
    self.ownerIdField = cfg.ownerIdField or "player_id"
    self.binField = cfg.binField or "bin"
    self.template = cfg.template or {}
    self.rowProps = cfg.rowProps or {}
    self.createDefaults = cfg.createDefaults or {}
    self.cellData = cfg.cellData or {}
end

function PlayerStore:sqlValue(v)
    if type(v) == "number" then
        return tostring(v)
    end
    if self.db.quote then
        return self.db.quote(tostring(v))
    end
    return "'" .. tostring(v) .. "'"
end

-- 用关系行覆盖模板 props
local function applyRowProps(template, playerId, row, rowProps)
    local data = {
        props = {},
        records = {},
        containers = {},
    }

    for key, value in pairs(template.props or {}) do
        data.props[key] = value
    end
    data.props.id = playerId

    for propName, col in pairs(rowProps or {}) do
        if row[col] ~= nil then
            data.props[propName] = row[col]
        end
    end

    for name, rows in pairs(template.records or {}) do
        data.records[name] = rows
    end
    for name, children in pairs(template.containers or {}) do
        data.containers[name] = children
    end
    return data
end

function PlayerStore:characterRow(playerId)
    local rows = self.db.query(string.format(
        "SELECT * FROM %s WHERE id=%d", self.playerTable, playerId))
    return rows and rows[1]
end

function PlayerStore:listCharacters(accountId)
    local rows = self.db.query(string.format(
        "SELECT * FROM %s WHERE %s=%d", self.playerTable,
        self.accountIdField, accountId))
    return rows or {}
end

function PlayerStore:createCharacter(accountId, name)
    local cols = { self.accountIdField, "name" }
    local vals = { self:sqlValue(accountId), self:sqlValue(name) }

    for col, value in pairs(self.createDefaults) do
        cols[#cols + 1] = col
        vals[#vals + 1] = self:sqlValue(value)
    end

    return self.db.exec(string.format("INSERT INTO %s (%s) VALUES (%s)",
        self.playerTable, table.concat(cols, ","), table.concat(vals, ",")))
end

function PlayerStore:load(playerId)
    local row = self:characterRow(playerId)
    if not row then return nil end

    local data = applyRowProps(self.template, playerId, row, self.rowProps)

    local rows = self.db.query(string.format(
        "SELECT %s FROM %s WHERE %s=%d",
        self.binField, self.binTable, self.ownerIdField, playerId))
    local binRow = rows and rows[1]
    if binRow and binRow[self.binField] ~= nil and binRow[self.binField] ~= "" then
        local loaded = bin.unpackEntity(binRow[self.binField])
        if loaded then
            loaded.records = loaded.records or {}
            loaded.containers = loaded.containers or {}
            return loaded
        end
    end
    return data
end

function PlayerStore:save(playerId, dump)
    local body = bin.packEntity(dump)

    local exists = self.db.query(string.format(
        "SELECT %s FROM %s WHERE %s=%d",
        self.ownerIdField, self.binTable, self.ownerIdField, playerId))
    if exists and exists[1] then
        return self.db.exec(string.format(
            "UPDATE %s SET %s=%s WHERE %s=%d",
            self.binTable, self.binField, self:sqlValue(body),
            self.ownerIdField, playerId))
    end

    return self.db.exec(string.format(
        "INSERT INTO %s (%s,%s) VALUES (%d,%s)",
        self.binTable, self.ownerIdField, self.binField, playerId,
        self:sqlValue(body)))
end

-- 从实体 records 按配置提取 cell init data
function PlayerStore:buildCellData(entity)
    local out = {}
    for _, spec in ipairs(self.cellData or {}) do
        local rec = entity:getRecord(spec.record)
        if not rec then goto continue end

        local values = {}
        for _, row in ipairs(rec:rowsList()) do
            values[#values + 1] = row[spec.field]
        end
        out[spec.target] = values
        ::continue::
    end
    return out
end

return PlayerStore
