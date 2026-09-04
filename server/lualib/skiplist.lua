-- lualib/skiplist.lua
-- 纯 Lua 跳表(skiplist, 参考 redis zsl 实现), 作为 cslib/skiplist C 模块的降级实现。
-- 接口与 C 版保持一致:
--   s = Skiplist.new()
--   s:insert(score, id)
--   s:remove(score, id) -> boolean
--   s:count() -> number
--   ids = s:range(lo, hi) -> 有序 id 数组(按 score, (score,id) 字典序)
--   ok, err = s:verify()

local MAXLEVEL = 24
local P = 0.25
local rnd = math.random

local Skiplist = {}
Skiplist.__index = Skiplist

local function lt(s1, id1, s2, id2)
    if s1 ~= s2 then return s1 < s2 end
    return id1 < id2
end

local function eq(s1, id1, s2, id2)
    return s1 == s2 and id1 == id2
end

function Skiplist.new()
    return setmetatable({
        header = { forward = {} },
        level = 1,
        n = 0,
        idSet = {},
    }, Skiplist)
end

local function randomLevel()
    local lvl = 1
    while lvl < MAXLEVEL and rnd() < P do lvl = lvl + 1 end
    return lvl
end

function Skiplist:insert(score, id)
    if self.idSet[id] then
        -- 同 id 重新插入: 先按旧 score 删除, 与新坐标保持一致
        self:remove(self.idSet[id].score, id)
    end

    local update = {}
    local x = self.header
    for i = self.level, 1, -1 do
        while x.forward[i] and lt(x.forward[i].score, x.forward[i].id, score, id) do
            x = x.forward[i]
        end
        update[i] = x
    end

    local lvl = randomLevel()
    if lvl > self.level then
        for i = self.level + 1, lvl do update[i] = self.header end
        self.level = lvl
    end

    local node = { score = score, id = id, forward = {} }
    for i = 1, lvl do
        node.forward[i] = update[i].forward[i]
        update[i].forward[i] = node
    end
    node.backward = update[1] ~= self.header and update[1] or nil
    if node.forward[1] then node.forward[1].backward = node end

    self.idSet[id] = node
    self.n = self.n + 1
    return node
end

function Skiplist:remove(score, id)
    local node = self.idSet[id]
    if not node then return false end

    -- score 由调用方保证与当前链表中的一致(与 C 版语义一致)
    local update = {}
    local x = self.header
    for i = self.level, 1, -1 do
        while x.forward[i] and lt(x.forward[i].score, x.forward[i].id, node.score, node.id) do
            x = x.forward[i]
        end
        update[i] = x
    end

    local l1 = update[1] and update[1].forward[1]
    if not (l1 and eq(l1.score, l1.id, node.score, node.id)) then
        error("skiplist: node unreachable id=" .. tostring(id))
    end

    for i = 1, self.level do
        local f = update[i].forward[i]
        if f and eq(f.score, f.id, node.score, node.id) then
            update[i].forward[i] = f.forward[i]
        end
    end

    if l1.forward[1] then l1.forward[1].backward = l1.backward end
    while self.level > 1 and not self.header.forward[self.level] do
        self.level = self.level - 1
    end

    self.idSet[id] = nil
    self.n = self.n - 1
    return true
end

function Skiplist:count()
    return self.n
end

function Skiplist:range(lo, hi)
    local x = self.header
    for i = self.level, 1, -1 do
        while x.forward[i] and x.forward[i].score < lo do x = x.forward[i] end
    end

    local out = {}
    local node = x.forward[1]
    while node and node.score <= hi do
        out[#out + 1] = node.id
        node = node.forward[1]
    end
    return out
end

function Skiplist:verify()
    local i = 0
    local prev
    local node = self.header.forward[1]
    while node do
        i = i + 1
        if prev and not lt(prev.score, prev.id, node.score, node.id) then
            return false, "ordering broken"
        end
        if node.backward ~= prev then return false, "backward broken" end
        prev = node
        node = node.forward[1]
    end
    if i ~= self.n then return false, "count mismatch" end
    return true
end

return Skiplist
