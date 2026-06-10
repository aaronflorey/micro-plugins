VERSION = "0.3.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local strings = import("strings")
local os = import("os")
local buffer = import("micro/buffer")

local diagnostic_owner = "jsonschema"

local function path_exists(path)
    local _, err = os.Stat(path)
    return err == nil
end

local function find_in_path(name)
    local path_env = os.Getenv("PATH")
    if path_env == nil or path_env == "" then
        return nil
    end

    local separator = ":"
    if os.PathListSeparator ~= nil then
        if type(os.PathListSeparator) == "number" then
            separator = string.char(os.PathListSeparator)
        else
            separator = tostring(os.PathListSeparator)
        end
    end

    local pattern = string.format("([^%s]+)", separator:gsub("([%%%-%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
    for dir in string.gmatch(path_env, pattern) do
        local candidate = filepath.Join(dir, name)
        if path_exists(candidate) then
            return candidate
        end
    end

    return nil
end

local function find_upwards(start_dir, candidates)
    local dir = start_dir

    while dir ~= "" do
        for _, candidate in ipairs(candidates) do
            local full_path = filepath.Join(dir, candidate)
            if path_exists(full_path) then
                return full_path, dir
            end
        end

        local parent = filepath.Dir(dir)
        if parent == dir then
            break
        end
        dir = parent
    end

    return nil, nil
end

local function resolve_tool(start_dir)
    local local_path, root = find_upwards(start_dir, {
        "node_modules/.bin/jsonschema",
        "node_modules/.bin/jsonschema.cmd",
    })
    if local_path ~= nil then
        return local_path, root
    end

    local global_path = find_in_path("jsonschema")
    if global_path ~= nil then
        return global_path, start_dir
    end

    return nil, nil
end

local function read_file(path)
    local file = io.open(path, "r")
    if file == nil then
        return nil, "Could not open file"
    end

    local content = file:read("*a")
    file:close()

    if content == nil then
        return nil, "Could not read file"
    end

    return content, nil
end

local function is_json_file(path)
    return strings.ToLower(filepath.Ext(path)) == ".json"
end

local function extract_schema_from_text(text)
    local schema = text:match('"%$schema"%s*:%s*"([^"]+)"')
    if schema ~= nil and schema ~= "" then
        return schema
    end
    return nil
end

local function has_uri_scheme(value)
    return value:match("^[A-Za-z][A-Za-z0-9+.-]*:") ~= nil
end

local function resolve_schema_path(path, schema)
    if schema == nil or schema == "" then
        return schema
    end

    if strings.HasPrefix(schema, "#") then
        return schema
    end

    if has_uri_scheme(schema) then
        return schema
    end

    if filepath.IsAbs(schema) then
        return schema
    end

    return filepath.Join(filepath.Dir(path), schema)
end

local function clear_messages(buf)
    buf:ClearMessages(diagnostic_owner)
end

local function setting_enabled(settings, key, default)
    local value = settings[key]
    if value == nil then
        return default
    end
    return value
end

local function is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    local count = 0
    for key, _ in pairs(tbl) do
        if type(key) ~= "number" then
            return false
        end
        if key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
    end

    return #tbl == count
end

local function new_state(text)
    return {
        text = text,
        pos = 1,
        len = #text,
        line = 1,
        col = 1,
        locations = {},
    }
end

local function current_char(state)
    if state.pos > state.len then
        return nil
    end
    return string.sub(state.text, state.pos, state.pos)
end

local function advance(state)
    local ch = current_char(state)
    if ch == nil then
        return nil
    end

    state.pos = state.pos + 1
    if ch == "\n" then
        state.line = state.line + 1
        state.col = 1
    else
        state.col = state.col + 1
    end
    return ch
end

local function skip_whitespace(state)
    while true do
        local ch = current_char(state)
        if ch == nil or not string.find(" \t\r\n", ch, 1, true) then
            return
        end
        advance(state)
    end
end

local function copy_loc(state)
    return { line = state.line, col = state.col }
end

local function set_location(state, pointer, loc)
    if state.locations[pointer] == nil then
        state.locations[pointer] = loc
    end
end

local function parse_string(state)
    if current_char(state) ~= '"' then
        return nil, "Expected string"
    end

    advance(state)
    local parts = {}

    while true do
        local ch = current_char(state)
        if ch == nil then
            return nil, "Unterminated string"
        end

        if ch == '"' then
            advance(state)
            return table.concat(parts), nil
        end

        if ch == "\\" then
            advance(state)
            local esc = current_char(state)
            if esc == nil then
                return nil, "Unterminated escape"
            end

            if esc == '"' or esc == "\\" or esc == "/" then
                table.insert(parts, esc)
                advance(state)
            elseif esc == "b" then
                table.insert(parts, "\b")
                advance(state)
            elseif esc == "f" then
                table.insert(parts, "\f")
                advance(state)
            elseif esc == "n" then
                table.insert(parts, "\n")
                advance(state)
            elseif esc == "r" then
                table.insert(parts, "\r")
                advance(state)
            elseif esc == "t" then
                table.insert(parts, "\t")
                advance(state)
            elseif esc == "u" then
                local code = string.sub(state.text, state.pos + 1, state.pos + 4)
                if #code ~= 4 or not code:match("^[0-9a-fA-F]+$") then
                    return nil, "Invalid unicode escape"
                end
                table.insert(parts, "?")
                advance(state)
                advance(state)
                advance(state)
                advance(state)
                advance(state)
            else
                return nil, "Invalid escape"
            end
        else
            table.insert(parts, ch)
            advance(state)
        end
    end
end

local parse_value

local function parse_literal(state, literal)
    for i = 1, #literal do
        if current_char(state) ~= string.sub(literal, i, i) then
            return false
        end
        advance(state)
    end
    return true
end

local function parse_number(state)
    local ch = current_char(state)
    if ch == "-" then
        advance(state)
    end

    ch = current_char(state)
    if ch == nil then
        return "Unexpected end of number"
    end

    if ch == "0" then
        advance(state)
    elseif ch:match("%d") then
        while true do
            ch = current_char(state)
            if ch == nil or not ch:match("%d") then
                break
            end
            advance(state)
        end
    else
        return "Invalid number"
    end

    ch = current_char(state)
    if ch == "." then
        advance(state)
        ch = current_char(state)
        if ch == nil or not ch:match("%d") then
            return "Invalid number"
        end
        while true do
            ch = current_char(state)
            if ch == nil or not ch:match("%d") then
                break
            end
            advance(state)
        end
    end

    ch = current_char(state)
    if ch == "e" or ch == "E" then
        advance(state)
        ch = current_char(state)
        if ch == "+" or ch == "-" then
            advance(state)
        end
        ch = current_char(state)
        if ch == nil or not ch:match("%d") then
            return "Invalid number"
        end
        while true do
            ch = current_char(state)
            if ch == nil or not ch:match("%d") then
                break
            end
            advance(state)
        end
    end

    return nil
end

local function parse_array(state, pointer)
    advance(state)
    skip_whitespace(state)

    if current_char(state) == "]" then
        advance(state)
        return nil
    end

    local index = 0
    while true do
        local err = parse_value(state, pointer .. "/" .. tostring(index))
        if err ~= nil then
            return err
        end

        skip_whitespace(state)
        local ch = current_char(state)
        if ch == "]" then
            advance(state)
            return nil
        end
        if ch ~= "," then
            return "Expected ',' or ']'"
        end
        advance(state)
        skip_whitespace(state)
        index = index + 1
    end
end

local function parse_object(state, pointer)
    advance(state)
    skip_whitespace(state)

    if current_char(state) == "}" then
        advance(state)
        return nil
    end

    while true do
        local key, key_err = parse_string(state)
        if key_err ~= nil then
            return key_err
        end

        skip_whitespace(state)
        if current_char(state) ~= ":" then
            return "Expected ':'"
        end
        advance(state)
        skip_whitespace(state)

        local child_pointer = pointer .. "/" .. key:gsub("~", "~0"):gsub("/", "~1")
        local err = parse_value(state, child_pointer)
        if err ~= nil then
            return err
        end

        skip_whitespace(state)
        local ch = current_char(state)
        if ch == "}" then
            advance(state)
            return nil
        end
        if ch ~= "," then
            return "Expected ',' or '}'"
        end
        advance(state)
        skip_whitespace(state)
    end
end

parse_value = function(state, pointer)
    skip_whitespace(state)
    set_location(state, pointer, copy_loc(state))

    local ch = current_char(state)
    if ch == nil then
        return "Unexpected end of input"
    end

    if ch == "{" then
        return parse_object(state, pointer)
    end
    if ch == "[" then
        return parse_array(state, pointer)
    end
    if ch == '"' then
        local _, err = parse_string(state)
        return err
    end
    if ch == "t" then
        if parse_literal(state, "true") then
            return nil
        end
        return "Invalid literal"
    end
    if ch == "f" then
        if parse_literal(state, "false") then
            return nil
        end
        return "Invalid literal"
    end
    if ch == "n" then
        if parse_literal(state, "null") then
            return nil
        end
        return "Invalid literal"
    end
    if ch == "-" or ch:match("%d") then
        return parse_number(state)
    end

    return "Unexpected character"
end

local function build_location_map(text)
    local state = new_state(text)
    local err = parse_value(state, "")
    if err ~= nil then
        return {}
    end
    return state.locations
end

local function decode_json_string(value)
    value = value:gsub('\\u001f', string.char(31))
    value = value:gsub('\\n', '\n')
    value = value:gsub('\\r', '\r')
    value = value:gsub('\\t', '\t')
    value = value:gsub('\\"', '"')
    value = value:gsub('\\\\', '\\')
    return value
end

local function parse_instance_position(value)
    local numbers = {}
    for number in value:gmatch('%d+') do
        table.insert(numbers, tonumber(number))
    end
    if #numbers >= 2 then
        return {
            line = numbers[1],
            col = numbers[2],
        }
    end
    return nil
end

local function extract_json_string_field(fragment, key)
    local start_pos, end_pos = fragment:find('"' .. key .. '"%s*:%s*"')
    if start_pos == nil then
        return nil
    end

    local i = end_pos + 1
    local parts = {}
    local escaped = false

    while i <= #fragment do
        local ch = fragment:sub(i, i)
        if escaped then
            table.insert(parts, "\\" .. ch)
            escaped = false
        elseif ch == "\\" then
            escaped = true
        elseif ch == '"' then
            return decode_json_string(table.concat(parts))
        else
            table.insert(parts, ch)
        end
        i = i + 1
    end

    return nil
end

local function parse_json_error_object(fragment)
    local pointer = extract_json_string_field(fragment, "instanceLocation")
    local message = extract_json_string_field(fragment, "error")
    if message == nil then
        return nil
    end

    local position = fragment:match('"instancePosition"%s*:%s*%[(.-)%]')
    return {
        pointer = pointer or "",
        message = message,
        loc = parse_instance_position(position or ""),
    }
end

local function decode_validation_output(output)
    if output == nil then
        return nil
    end

    local trimmed = strings.TrimSpace(output)
    if trimmed == "" then
        return { valid = true, messages = {} }
    end

    local valid = trimmed:match('"valid"%s*:%s*(%a+)')
    if valid == "true" then
        return { valid = true, messages = {} }
    end

    local messages = {}
    local errors_blob = trimmed:match('"errors"%s*:%s*(%b[])')
    if errors_blob ~= nil then
        for fragment in errors_blob:gmatch('%b{}') do
            local item = parse_json_error_object(fragment)
            if item ~= nil then
                table.insert(messages, item)
            end
        end
    end

    if #messages == 0 then
        for fragment in trimmed:gmatch('%b{}') do
            local item = parse_json_error_object(fragment)
            if item ~= nil then
                table.insert(messages, item)
            end
        end
    end

    if #messages == 0 then
        local generic = extract_json_string_field(trimmed, "error")
        if generic ~= nil then
            table.insert(messages, {
                pointer = "",
                message = generic,
            })
        else
            local current = nil
            for line in output:gmatch("[^\n]+") do
                line = strings.TrimSpace(line)
                if strings.HasPrefix(line, "error: ") then
                    if current ~= nil then
                        table.insert(messages, current)
                    end
                    current = {
                        pointer = "",
                        message = string.sub(line, 8),
                    }
                elseif current ~= nil and strings.HasPrefix(line, "at instance location ") then
                    local pointer = line:match('at instance location "([^"]*)"')
                    if pointer ~= nil then
                        current.pointer = pointer
                    end
                end
            end

            if current ~= nil then
                table.insert(messages, current)
            end
        end
    end

    if #messages == 0 then
        return nil
    end

    return { valid = false, messages = messages }
end

local function summarize_message(item)
    local message = item.message or "Schema validation failed"
    local pointer = item.pointer or ""
    if pointer == "" then
        return message
    end
    return message .. " at " .. pointer
end

local function dedupe_messages(messages)
    local seen = {}
    local deduped = {}

    for _, item in ipairs(messages) do
        local loc = item.loc
        local loc_key = ""
        if loc ~= nil then
            loc_key = tostring(loc.line or "") .. ":" .. tostring(loc.col or "")
        end
        local key = (item.pointer or "") .. "\n" .. (item.message or "") .. "\n" .. loc_key
        if not seen[key] then
            seen[key] = true
            table.insert(deduped, item)
        end
    end

    return deduped
end

local function is_aggregate_properties_error(item)
    local pointer = item.pointer or ""
    local message = item.message or ""
    if pointer ~= "" then
        return false
    end

    local lower = strings.ToLower(message)
    return strings.Contains(lower, "defined properties subschemas")
        or strings.Contains(lower, "properties subschemas")
end

local function prune_aggregate_messages(messages)
    local has_specific_pointer = false
    for _, item in ipairs(messages) do
        if (item.pointer or "") ~= "" then
            has_specific_pointer = true
            break
        end
    end

    if not has_specific_pointer then
        return messages
    end

    local pruned = {}
    for _, item in ipairs(messages) do
        if not is_aggregate_properties_error(item) then
            table.insert(pruned, item)
        end
    end

    if #pruned == 0 then
        return messages
    end

    return pruned
end

local function add_message(buf, loc, message)
    if loc ~= nil and loc.line ~= nil and loc.col ~= nil then
        local start = buffer.Loc(math.max(loc.col - 1, 0), math.max(loc.line - 1, 0))
        local ending = buffer.Loc(math.max(loc.col, 1), math.max(loc.line - 1, 0))
        buf:AddMessage(buffer.NewMessage(diagnostic_owner, message, start, ending, buffer.MTError))
        return
    end

    buf:AddMessage(buffer.NewMessageAtLine(diagnostic_owner, message, 1, buffer.MTError))
end

local function apply_diagnostics(buf, messages, locations)
    clear_messages(buf)
    for _, item in ipairs(messages) do
        add_message(buf, item.loc or locations[item.pointer or ""], item.message)
    end
end

local function run_validation(path, schema, http_enabled)
    local dir = filepath.Dir(path)
    local exe, cwd = resolve_tool(dir)
    if exe == nil then
        return nil, "missing_tool"
    end

    local args = {"validate", schema, path, "--json"}
    if http_enabled then
        table.insert(args, "--http")
    end

    local previous_dir, cwd_err = os.Getwd()
    if cwd_err == nil then
        local chdir_err = os.Chdir(cwd)
        if chdir_err ~= nil then
            return nil, tostring(chdir_err)
        end
    end

    local output, err = shell.ExecCommand(exe, unpack(args))

    if cwd_err == nil then
        os.Chdir(previous_dir)
    end

    local parsed = decode_validation_output(output or "")
    if parsed ~= nil then
        return parsed, nil
    end

    if err ~= nil then
        return nil, tostring(err)
    end

    return nil, strings.TrimSpace(output or "")
end

local function validate_buffer(bp, options)
    options = options or {}
    local path = bp.Buf.Path
    if path == nil or path == "" then
        if not options.silent or options.notify_errors then
            micro.InfoBar():Error("jsonschema: Save the buffer before validating")
        end
        return false
    end

    if not is_json_file(path) then
        clear_messages(bp.Buf)
        if not options.silent then
            micro.InfoBar():Error("jsonschema: Only .json files are supported")
        end
        return false
    end

    local text, read_err = read_file(path)
    if text == nil then
        clear_messages(bp.Buf)
        if not options.silent or options.notify_errors then
            micro.InfoBar():Error("jsonschema: " .. read_err)
        end
        return false
    end

    local schema = extract_schema_from_text(text)

    if schema == nil then
        clear_messages(bp.Buf)
        if not options.silent then
            micro.InfoBar():Message("jsonschema: No root $schema found")
        end
        return true
    end

    schema = resolve_schema_path(path, schema)

    local result, err = run_validation(path, schema, setting_enabled(bp.Buf.Settings, "jsonschema.http", true))
    if err == "missing_tool" then
        clear_messages(bp.Buf)
        if not options.silent_missing then
            micro.InfoBar():Error("jsonschema: Install the 'jsonschema' CLI to validate schemas")
        end
        return false
    end

    if err ~= nil then
        clear_messages(bp.Buf)
        if not options.silent or options.notify_errors then
            micro.InfoBar():Error("jsonschema: " .. err)
        end
        return false
    end

    if result.valid then
        clear_messages(bp.Buf)
        if not options.quiet_success then
            micro.InfoBar():Message("jsonschema: Schema validation passed")
        end
        return true
    end

    local messages = dedupe_messages(prune_aggregate_messages(result.messages))
    if #messages == 0 then
        messages = {
            {
                pointer = "",
                message = "Schema validation failed",
            },
        }
    end

    local locations = build_location_map(text)
    apply_diagnostics(bp.Buf, messages, locations)
    if not options.silent or options.notify_errors then
        local summary = summarize_message(messages[1])
        if #messages > 1 then
            summary = summary .. " (and " .. tostring(#messages - 1) .. " more)"
        end
        micro.InfoBar():Error("jsonschema: " .. summary)
    end
    return false
end

local function validate_schema_command(bp)
    validate_buffer(bp, { silent = false, quiet_success = false, silent_missing = false })
end

function onSave(bp)
    if setting_enabled(bp.Buf.Settings, "jsonschema.onsave", true) then
        validate_buffer(bp, { silent = true, quiet_success = true, silent_missing = true, notify_errors = true })
    end
    return true
end

function init()
    config.RegisterCommonOption("jsonschema", "onsave", true)
    config.RegisterCommonOption("jsonschema", "http", true)
    config.MakeCommand("validate-schema", validate_schema_command, config.NoComplete)
    config.AddRuntimeFile("jsonschema", config.RTHelp, "help/jsonschema.md")
end
