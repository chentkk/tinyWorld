-- server/test/test_proto.lua
-- JSON 编解码与网络帧切分测试。

package.path = "./?.lua;./?/init.lua;" .. package.path

local json = require "tinyworld.core.json"
local msg = require "tinyworld.net.msg"

local t = { t = "AUTH", n = "auth", d = { token = "abc", code = 0 } }
local body = msg.encodeBody(t)
local frame = require("tinyworld.core.proto").packBody(body)

local back = json.decode(body)
assert(back.t == "AUTH" and back.d.token == "abc")

-- frame 解析
local len, fbody = require("tinyworld.core.proto").popFrame(frame)
assert(len == #body and fbody == body)

-- 粘包场景
local twoFrames = frame .. frame
local l1, b1 = require("tinyworld.core.proto").popFrame(twoFrames)
local rest = twoFrames:sub(l1 + 3)
local l2, b2 = require("tinyworld.core.proto").popFrame(rest)
assert(b1 == body and b2 == body)

print("PASS test_proto")
