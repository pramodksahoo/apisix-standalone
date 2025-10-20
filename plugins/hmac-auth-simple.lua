--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core = require("apisix.core")
local hmac = require("resty.hmac")
local str = require("resty.string")
local bit = require("bit")

local plugin_name = "hmac-auth-simple"

local schema = {
    type = "object",
    properties = {
        secret_key = {
            type = "string"
        },
        enable = {
            type = "boolean",
            default = true
        }
    },
    required = { "secret_key" }
}

local _M = {
    version = 0.1,
    priority = 91, -- Run in authentication phase, before built-in hmac-auth
    name = plugin_name,
    schema = schema,
}

local function calculate_signature(secret_key, body)
    local hmac_sha256 = hmac:new(secret_key, hmac.ALGOS.SHA256)
    if not hmac_sha256 then
        return nil, "failed to create hmac object"
    end

    local ok = hmac_sha256:update(body)
    if not ok then
        return nil, "failed to update hmac object with body"
    end

    local digest = hmac_sha256:final()
    return str.to_hex(digest)
end

local function safe_eq(a, b)
    if #a ~= #b then return false end
    local res = 0
    for i = 1, #a do
        res = bit.bor(res, bit.bxor(a:byte(i), b:byte(i)))
    end
    return res == 0
end

local function format_request(ctx, req_body)
    local method = core.request.get_method()
    local path = ctx.var.request_uri
    local headers = core.request.headers(ctx)
    local header_lines = {}
    for k, v in pairs(headers) do
        table.insert(header_lines, k .. ": " .. v)
    end
    local headers_str = table.concat(header_lines, "\n")

    return string.format(
            "%s %s HTTP/1.1\n%s\n\n%s",
            method,
            path,
            headers_str,
            req_body or ""
    )
end

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

function _M.init()
    core.log.warn("hmac-auth-simple plugin initialized!")
end

function _M.destroy()
    core.log.warn("hmac-auth-simple plugin destroyed!")
end

function _M.access(conf, ctx)
    if conf.enable == false then
        core.log.warn("hmac-auth-simple plugin is disabled")
        return
    end

    --core.log.warn("hmac-auth-simple plugin is running with config: ", core.json.encode(conf))

    -- Get request body - handle empty body case
    local req_body, err = core.request.get_body()

    --local log_str = format_request(ctx, req_body)
    --core.log.warn("logging incoming request:\n", log_str)

    if not req_body then
        if err then
            core.log.error("Unable to read body: ", err)
            return 400, { message = "Unable to read request body" }
        else
            req_body = "" -- Empty body is allowed
        end
    end

    local provided_signature = core.request.header(ctx, "X-Hmac-Signature")
    if not provided_signature then
        core.log.warn("Missing X-Hmac-Signature header")
        return 401, { message = "Missing HMAC signature header" }
    end

    -- Strip common HMAC signature prefixes if present
    local prefix_len = 0
    if provided_signature:sub(1, 16) == "hmac-sha256-hex=" then
        prefix_len = 16
    elseif provided_signature:sub(1, 7) == "sha256=" then
        prefix_len = 7
    end

    if prefix_len > 0 then
        provided_signature = provided_signature:sub(prefix_len + 1)
    end

    local expected_signature, sig_err = calculate_signature(conf.secret_key, req_body)
    if not expected_signature then
        core.log.warn("Raw request body for HMAC:", req_body)
        core.log.error("Error generating signature: ", sig_err)
        return 500, { message = "Internal signature error" }
    end

    -- Constant-time comparison
    if not safe_eq(provided_signature, expected_signature) then
        core.log.warn("Raw request body for HMAC:", req_body)
        core.log.warn("Signature mismatch: expected ", expected_signature,
                ", got ", provided_signature)
        return 401, { message = "Invalid HMAC signature" }
    end
    return
end

return _M