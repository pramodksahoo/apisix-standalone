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

-- PCI Tokenization Plugin
-- Intercepts API requests, extracts PCI objects, calls tokenization service,
-- and handles responses with configurable error behavior.

local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local http = require("resty.http")
local json = require("cjson")
local jwt = require("resty.jwt")

-- Constants
local PLUGIN_NAME = "pci-tokenization-plugin"
local DEFAULT_TIMEOUT = 5000
local ROOT_OBJECT_KEYS = { "", "root", "body" }

-- Error codes
local ERROR_CODES = {
    TENANT_EXTRACTION_FAILED = 'TOK_ERROR_1001',
    TOKENIZATION_ERROR = 'TOK_ERROR_1002',
    SERVICE_UNAVAILABLE = 'TOK_ERROR_1003',
    AUTH_TOKEN_ERROR = 'TOK_ERROR_1004'
}

-- OAuth2 token cache
local access_token_cache = {
    token = nil,
    expires_at = 0,
    realm = nil
}

-- Schema definition
local schema = {
    type = "object",
    properties = {
        intercept_path_pattern_list = {
            type = "array",
            items = { type = "string" },
            minItems = 1
        },
        intercept_object_key = { type = "string" },
        is_graphql_request = { type = "boolean", default = false },
        graphql_operation_names = { 
            type = "array", 
            items = { type = "string" },
            default = {}
        },
        token_service_endpoint = { type = "string" },
        token_service_timeout = { type = "number", default = DEFAULT_TIMEOUT },
        is_token_gateway_url = { type = "boolean", default = false },
        iam_service_url = { type = "string" },
        token_service_auth_client_id = { type = "string" },
        token_service_auth_secret = { type = "string" },
        token_service_auth_realm = { type = "string", default = "core-apps" },
        token_service_scope = { type = "string", default = "openid" },
        has_tenant_guid = { type = "boolean" },
        has_tenant = { type = "boolean" },
        tenant_guid_resolver_url = { type = "string" },
        tenant_guid_resolver_method = { type = "string", enum = { "GET", "POST" }, default = "GET" },
        tenant_guid_resolver_reference = { type = "string" },
        tenant_information_location = { type = "string", enum = { "headers", "body", "jwt" } },
        tenant_information_reference = { type = "string" },
        reject_on_error = { type = "boolean", default = true }
    },
    required = { "intercept_path_pattern_list", "intercept_object_key", "token_service_endpoint" }
}

-- Plugin module definition
local _M = {
    version = 0.1,
    priority = 85,
    name = PLUGIN_NAME,
    schema = schema,
}

-- Plugin lifecycle functions
function _M.check_schema(conf, schema_type)
    -- Validate that either has_tenant_guid or has_tenant is true, but not both
    if conf.has_tenant_guid and conf.has_tenant then
        return false, "Cannot have both has_tenant_guid and has_tenant set to true"
    end
    
    if not conf.has_tenant_guid and not conf.has_tenant then
        return false, "Either has_tenant_guid or has_tenant must be set to true"
    end
    
    -- Validate OAuth2 configuration if token gateway is enabled
    if conf.is_token_gateway_url then
        if not conf.iam_service_url then
            return false, "iam_service_url is required when is_token_gateway_url is true"
        end
        if not conf.token_service_auth_client_id then
            return false, "token_service_auth_client_id is required when is_token_gateway_url is true"
        end
        if not conf.token_service_auth_secret then
            return false, "token_service_auth_secret is required when is_token_gateway_url is true"
        end
    end
    
    return core.schema.check(schema, conf)
end

function _M.init()
    core.log.info("PCI Tokenization Plugin initialized")
    local attr = plugin.plugin_attr(PLUGIN_NAME)
    if attr then
        core.log.info(PLUGIN_NAME, " plugin attributes loaded")
    end
end

function _M.destroy()
    -- Call this function when plugin is unloaded
end

-- Utility functions
local function is_root_object_key(key)
    for _, root_key in ipairs(ROOT_OBJECT_KEYS) do
        if key == root_key then
            return true
        end
    end
    return false
end

local function parse_nested_path(path)
    local keys = {}
    for key in path:gmatch("[^.]+") do
        table.insert(keys, key)
    end
    return keys
end

local function get_nested_value(obj, keys)
    local value = obj
    for _, key in ipairs(keys) do
        if type(value) == "table" and value[key] then
            value = value[key]
        else
            return nil
        end
    end
    return value
end

local function set_nested_value(obj, keys, new_value)
    local parent = obj
    for i = 1, #keys - 1 do
        parent = parent[keys[i]]
    end
    parent[keys[#keys]] = new_value
end

local function get_reject_on_error_config(conf)
    return conf.reject_on_error == nil and true or conf.reject_on_error
end

-- Request interception logic
local function should_intercept_request(conf, ctx)
    local request_uri = ctx.var.request_uri
    local patterns = conf.intercept_path_pattern_list
    
    for _, pattern in ipairs(patterns) do
        if ngx.re.match(request_uri, pattern, "jo") then
            core.log.info("Request intercepted, pattern matched: ", pattern)
            return true
        end
    end
    
    return false
end

-- Tenant information extraction
local function extract_tenant_from_headers(ctx, reference)
    return core.request.header(ctx, reference)
end

local function extract_tenant_from_body(reference)
    local body_data = core.request.get_body()
    if not body_data then
        return nil
    end
    
    local body_table = json.decode(body_data)
    if not body_table then
        return nil
    end
    
    local keys = parse_nested_path(reference)
    return get_nested_value(body_table, keys)
end

local function extract_tenant_from_jwt(ctx, reference)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        core.log.warn("No Authorization header found for JWT extraction")
        return nil
    end
    
    -- Remove "Bearer " prefix if present
    local token = auth_header:match("Bearer%s+(.+)") or auth_header
    
    -- Decode JWT without verification (since we just need to extract claims)
    local jwt_obj = jwt:load_jwt(token)
    if not jwt_obj or not jwt_obj.payload then
        core.log.error("Failed to decode JWT token")
        return nil
    end
    
    local keys = parse_nested_path(reference)
    local value = get_nested_value(jwt_obj.payload, keys)
    
    if not value then
        core.log.warn("JWT claim not found with path: ", reference)
    end
    
    return value
end

local function extract_tenant_info(conf, ctx)
    local location = conf.tenant_information_location
    local reference = conf.tenant_information_reference
    
    if location == "headers" then
        return extract_tenant_from_headers(ctx, reference)
    elseif location == "body" then
        return extract_tenant_from_body(reference)
    elseif location == "jwt" then
        return extract_tenant_from_jwt(ctx, reference)
    end
    
    return nil
end

-- GraphQL operation filtering
local function should_intercept_graphql_operation(conf, body_table)
    if not conf.is_graphql_request then
        return true -- Not a GraphQL request, proceed normally
    end
    
    -- Check if specific operations are configured
    if #conf.graphql_operation_names == 0 then
        return true -- No specific operations configured, intercept all
    end
    
    -- Extract operation name from GraphQL query
    local query = body_table.query
    if not query then
        return false
    end
    
    -- Simple regex to extract operation name (mutation/query name)
    local operation_match = ngx.re.match(query, "(?:mutation|query)\\s+(\\w+)", "jo")
    if not operation_match then
        return false
    end
    
    local operation_name = operation_match[1]
    
    -- Check if this operation should be intercepted
    for _, configured_op in ipairs(conf.graphql_operation_names) do
        if operation_name == configured_op then
            return true
        end
    end
    
    return false
end

-- PCI object extraction from request body
local function extract_pci_object(conf, ctx)
    local body_data = core.request.get_body()
    if not body_data then
        core.log.warn("No request body found")
        return nil
    end
    
    local body_table = json.decode(body_data)
    if not body_table then
        core.log.error("Failed to parse request body as JSON")
        return nil
    end
    
    -- Check if GraphQL operation should be intercepted
    if not should_intercept_graphql_operation(conf, body_table) then
        core.log.info("GraphQL operation not configured for interception")
        return nil
    end
    
    local pci_object
    if is_root_object_key(conf.intercept_object_key) then
        -- Use entire request body as pci object
        pci_object = body_table
    else
        -- Extract specific property from request body (supports nested paths)
        local keys = parse_nested_path(conf.intercept_object_key)
        pci_object = get_nested_value(body_table, keys)
        
        if not pci_object then
            core.log.warn("PCI object not found with path: ", conf.intercept_object_key)
            return nil
        end
    end
    
    return pci_object, body_table
end

-- Tokenization response processing
local function handle_successful_tokenization(conf, tokenization_response, body_table)
    -- Success case: replace pci object and add trace ID
    if is_root_object_key(conf.intercept_object_key) then
        -- Replace entire body with tokenized pci object
        body_table = tokenization_response.pciObject
    else
        -- Replace specific property using nested path support
        local keys = parse_nested_path(conf.intercept_object_key)
        set_nested_value(body_table, keys, tokenization_response.pciObject)
    end
    
    -- Add trace ID to response headers
    ngx.header["x-trace-id"] = tokenization_response.traceId
    
    core.log.info("Tokenization successful, trace ID: ", tokenization_response.traceId)
    return body_table, true
end

local function handle_tokenization_error_reject(tokenization_response)
    local error_code = tokenization_response.errorObject.errorCode or ERROR_CODES.TOKENIZATION_ERROR
    core.log.error("Rejecting request due to tokenization error, errorCode: ", error_code)
    
    -- Add trace ID to response headers before returning error
    ngx.header["x-trace-id"] = tokenization_response.traceId
    
    -- Return error with just the errorCode from errorObject
    return nil, false, 400, {
        errorCode = error_code
    }
end

local function handle_tokenization_error_passthrough(conf, tokenization_response, body_table)
    core.log.info("Sending tokenization error downstream, reject_on_error=false")
    
    -- Error case: handle error object and trace ID
    if is_root_object_key(conf.intercept_object_key) then
        -- Replace entire body with error object
        body_table = {
            errorObject = tokenization_response.errorObject
        }
    else
        -- Remove pci object using nested path support
        local keys = parse_nested_path(conf.intercept_object_key)
        local parent = body_table
        for i = 1, #keys - 1 do
            parent = parent[keys[i]]
        end
        
        -- Remove the pci object and add error info
        parent[keys[#keys]] = nil
        body_table.errorObject = tokenization_response.errorObject
    end
    
    -- Add trace ID to response headers
    ngx.header["x-trace-id"] = tokenization_response.traceId
    
    core.log.info("Tokenization failed, trace ID: ", tokenization_response.traceId)
    return body_table, true
end

local function process_tokenization_response(conf, tokenization_response, body_table)
    if tokenization_response.pciObject and tokenization_response.traceId then
        return handle_successful_tokenization(conf, tokenization_response, body_table)
        
    elseif tokenization_response.errorObject and tokenization_response.traceId then
        local reject_on_error = get_reject_on_error_config(conf)
        
        if reject_on_error then
            return handle_tokenization_error_reject(tokenization_response)
        else
            return handle_tokenization_error_passthrough(conf, tokenization_response, body_table)
        end
        
    else
        core.log.error("UNEXPECTED response format from tokenization service")
        core.log.error("Expected: {pciObject: {...}, traceId: '...'} OR {errorObject: {...}, traceId: '...'}")
        core.log.error("Actual response structure:")
        for key, value in pairs(tokenization_response or {}) do
            core.log.error("  Key: ", key, " Type: ", type(value))
        end
        return nil, false
    end
end

-- OAuth2 Token Management
local function is_token_expired()
    return ngx.now() >= access_token_cache.expires_at
end

local function get_oauth2_token(conf)
    -- Check if we have a valid cached token for this realm
    if access_token_cache.token and 
       access_token_cache.realm == conf.token_service_auth_realm and 
       not is_token_expired() then
        core.log.info("Using cached OAuth2 token")
        return access_token_cache.token, nil, nil
    end
    
    core.log.info("Requesting new OAuth2 token")
    
    local httpc = http.new()
    httpc:set_timeout(conf.token_service_timeout or DEFAULT_TIMEOUT)
    
    -- Construct the IAM service URL
    local iam_url = conf.iam_service_url .. "/realms/" .. conf.token_service_auth_realm .. "/protocol/openid-connect/token"
    
    -- Prepare form data
    local form_data = "client_id=" .. ngx.escape_uri(conf.token_service_auth_client_id) ..
                     "&client_secret=" .. ngx.escape_uri(conf.token_service_auth_secret) ..
                     "&grant_type=client_credentials" ..
                     "&scope=" .. ngx.escape_uri(conf.token_service_scope or "openid")
    
    local res, err = httpc:request_uri(iam_url, {
        method = "POST",
        body = form_data,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        }
    })
    
    if not res then
        core.log.error("Failed to call IAM service: ", err)
        return nil, "Network error calling IAM service", 503
    end
    
    if res.status ~= 200 then
        core.log.error("IAM authentication failed with status: ", res.status)
        return nil, "IAM service authentication failed with status: " .. res.status, res.status
    end
    
    -- Parse the JSON response
    local response_body, decode_err = json.decode(res.body)
    if not response_body then
        core.log.error("Failed to decode IAM response: ", decode_err or "decode error")
        return nil, "Invalid JSON response from IAM service", 401
    end
    
    if not response_body.access_token then
        core.log.error("No access token in IAM response")
        return nil, "IAM service did not return access token", 401
    end
    
    -- Cache the token (assuming 15 minutes expiry, subtract 60 seconds for safety)
    local expires_in = response_body.expires_in or 900 -- Default to 15 minutes
    access_token_cache.token = response_body.access_token
    access_token_cache.expires_at = ngx.now() + expires_in - 60  -- 1 minute safety margin
    access_token_cache.realm = conf.token_service_auth_realm
    
    core.log.info("Successfully obtained and cached OAuth2 token")
    return response_body.access_token, nil, nil
end

-- Tokenization service communication
local function call_tokenization_service(conf, pci_object, tenant_object)
    local httpc = http.new()
    httpc:set_timeout(conf.token_service_timeout or DEFAULT_TIMEOUT)
    
    local request_body = {
        pciObject = pci_object,
        tenantObject = tenant_object
    }

    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    -- Add OAuth2 authentication if token gateway is enabled
    if conf.is_token_gateway_url then
        local access_token, auth_err, auth_status = get_oauth2_token(conf)
        if not access_token then
            core.log.error("OAuth2 authentication failed: ", auth_err)
            return nil, "Authentication failed: " .. (auth_err or "unknown error"), auth_status
        end
        headers["Authorization"] = "Bearer " .. access_token
    end

    local res, err = httpc:request_uri(conf.token_service_endpoint, {
        method = "POST",
        body = json.encode(request_body),
        headers = headers
    })

    if not res then
        core.log.error("Failed to call tokenization service: ", err)
        return nil, "Network error calling tokenization service"
    end
    
    -- Check for HTTP error status codes
    if res.status ~= 200 then
        core.log.error("Tokenization service HTTP error: ", res.status)
        
        local error_message = "Tokenization service returned HTTP " .. res.status
        if res.body and res.body ~= "" then
            -- Try to parse error response if available
            local error_body, parse_err = json.decode(res.body)
            if error_body then
                if error_body.error_msg then
                    error_message = error_message .. ": " .. error_body.error_msg
                elseif error_body.error then
                    error_message = error_message .. ": " .. error_body.error
                elseif error_body.message then
                    error_message = error_message .. ": " .. error_body.message
                end
            end
        end
        
        return nil, error_message, res.status
    end
    
    -- Check if response body exists
    if not res.body or res.body == "" then
        core.log.error("Tokenization service returned empty response")
        return nil, "Empty response from tokenization service"
    end
    
    -- Parse the JSON response
    local response_body, decode_err = json.decode(res.body)
    if not response_body then
        core.log.error("Failed to decode tokenization response: ", decode_err or "decode error")
        return nil, "Invalid JSON response from tokenization service"
    end
    
    return response_body, nil
end

-- Error handling helpers
local function create_error_response(error_code, description, details)
    return {
        errorObject = {
            errorCode = error_code,
            description = description,
            details = details
        }
    }
end

local function handle_tenant_extraction_error(conf, reject_on_error)
    if reject_on_error then
        -- Return 400 error code when reject_on_error is true
        return 400, {
            errorCode = ERROR_CODES.TENANT_EXTRACTION_FAILED,
        }
    else
        -- Create error object for downstream service when reject_on_error is false
        local error_body = create_error_response(
            ERROR_CODES.TENANT_EXTRACTION_FAILED,
            "Failed to extract tenant information",
            "Tenant information not found in " .. (conf.tenant_information_location or "unknown location")
        )
        
        -- Send error information downstream as request body
        local error_body_json = json.encode(error_body)
        ngx.req.set_body_data(error_body_json)
        core.log.info("Sending tenant extraction error downstream")
        return nil
    end
end

local function handle_service_unavailable_error(reject_on_error, err, http_status)
    -- Check if this is an authentication error based on HTTP status code
    if http_status and (http_status == 401) then
        if reject_on_error then
            -- Return 401 error code for authentication failures
            return 401, {
                errorCode = ERROR_CODES.AUTH_TOKEN_ERROR,
            }
        else
            -- Create error object for downstream service when reject_on_error is false
            local error_body = create_error_response(
                ERROR_CODES.AUTH_TOKEN_ERROR,
                "Authentication with tokenization service failed",
                err
            )
            
            -- Send error information downstream as request body
            local error_body_json = json.encode(error_body)
            ngx.req.set_body_data(error_body_json)
            core.log.info("Sending authentication error downstream")
            return nil
        end
    else
        -- Handle regular service unavailable errors
        if reject_on_error then
            -- Return 503 error code when reject_on_error is true
            return 503, {
                errorCode = ERROR_CODES.SERVICE_UNAVAILABLE,
            }
        else
            -- Create error object for downstream service when reject_on_error is false
            local error_body = create_error_response(
                ERROR_CODES.SERVICE_UNAVAILABLE,
                "Tokenization service is currently unavailable",
                err
            )
            
            -- Send error information downstream as request body
            local error_body_json = json.encode(error_body)
            ngx.req.set_body_data(error_body_json)
            core.log.info("Sending tokenization service error downstream")
            return nil
        end
    end
end

local function build_tenant_object(conf, tenant_value)
    local tenant_object = {
        type = conf.has_tenant_guid and "guid" or "string",
        value = tenant_value
    }

    -- Add resolver information if has_tenant_guid is true
    if conf.has_tenant_guid then
        tenant_object.tenantResolverUrl = conf.tenant_guid_resolver_url
        tenant_object.tenantResolverMethod = conf.tenant_guid_resolver_method or "GET"
        tenant_object.tenantResolverReference = conf.tenant_guid_resolver_reference or "tenantId"
    end
    
    return tenant_object
end

-- Main plugin rewrite function
function _M.rewrite(conf, ctx)
    -- Check if request should be intercepted
    if not should_intercept_request(conf, ctx) then
        return
    end
    
    -- Extract pci object from request body
    local pci_object, body_table = extract_pci_object(conf, ctx)
    if not pci_object then
        return
    end

    local reject_on_error = get_reject_on_error_config(conf)

    -- Extract tenant information
    local tenant_value = extract_tenant_info(conf, ctx)
    if not tenant_value then
        core.log.error("Failed to extract tenant information")
        return handle_tenant_extraction_error(conf, reject_on_error)
    end
    
    -- Prepare tenant detail object
    local tenant_object = build_tenant_object(conf, tenant_value)
    
    -- Call tokenization service
    local tokenization_response, err, http_status = call_tokenization_service(conf, pci_object, tenant_object)
    if not tokenization_response then
        core.log.error("Tokenization service call failed: ", err)
        return handle_service_unavailable_error(reject_on_error, err, http_status)
    end
    
    -- Process response and update request body
    local updated_body, success, error_status, error_response = process_tokenization_response(conf, tokenization_response, body_table)
    if not success then
        if error_status and error_response then
            -- Return error response when reject_on_error is true for tokenization errors
            core.log.error("Returning tokenization error response, status: ", error_status)
            return error_status, error_response
        else
            -- Fallback behavior for other failures
            core.log.warn("Failed to process tokenization response, passing through original body")
            local original_body = json.encode(body_table)
            ngx.req.set_body_data(original_body)
            return
        end
    end
    
    -- Update request body
    local new_body = json.encode(updated_body)
    ngx.req.set_body_data(new_body)
    
    -- Set trace ID headers for upstream server
    if tokenization_response.traceId then
        ngx.req.set_header("x-trace-id", tokenization_response.traceId)
    end
    
    core.log.info("PCI tokenization completed successfully")
end

return _M