VERSION = "1.3.0"
 
local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local strings = import("strings")
local os = import("os")

local supported_extensions = {
    [".yml"] = "yaml",
    [".yaml"] = "yaml",
    [".json"] = "json",
}

local function find_in_path(name)
    local path_env = os.Getenv("PATH")
    if path_env == nil or path_env == "" then
        return nil
    end

    for dir in string.gmatch(path_env, "([^:]+)") do
        local candidate = filepath.Join(dir, name)
        local stat, err = os.Stat(candidate)
        if err == nil and stat ~= nil then
            return candidate
        end
    end

    return nil
end

local function resolve_yq()
    local yq_path = find_in_path("yq")
    if yq_path == nil then
        return nil
    end
    return yq_path
end

local function get_file_type(path)
    local ext = strings.ToLower(filepath.Ext(path))
    return supported_extensions[ext]
end

local function split_string(value, separator)
    local parts = {}
    if value == nil or value == "" then
        return parts
    end

    local pattern = string.format("([^%s]+)", separator)
    for part in string.gmatch(value, pattern) do
        table.insert(parts, part)
    end
    return parts
end

local function parse_path(raw)
    local path = {}
    for _, part in ipairs(split_string(raw, string.char(31))) do
        local number = tonumber(part)
        if number ~= nil and tostring(number) == part then
            table.insert(path, number)
        else
            table.insert(path, part)
        end
    end
    return path
end

local function yq_key_candidates(yq_exe, file_path)
    local separator = string.char(31)
    local query = '.. | select(tag == "!!map") | .[] | ((path | map(tostring) | join("' .. separator .. '")) + "\t" + (key | tostring) + "\t" + ((key | line) | tostring) + "\t" + ((key | column) | tostring))'
    local output, err = shell.ExecCommand(yq_exe, "eval", "-r", query, file_path)
    if err ~= nil then
        return nil, tostring(err)
    end

    local candidates = {}
    for line in output:gmatch("[^\n]+") do
        line = strings.TrimSpace(line)
        if line ~= "" then
            local fields = split_string(line, "\t")
            if #fields >= 4 then
                table.insert(candidates, {
                    path = parse_path(fields[1]),
                    key = fields[2],
                    key_line = tonumber(fields[3]) or 0,
                    key_col = tonumber(fields[4]) or 0,
                })
            end
        end
    end

    return candidates, nil
end

local function extract_key_from_line(line)
    local key = nil
    if strings.HasPrefix(strings.TrimSpace(line), "-") then
        return nil
    end
    local yaml_key = line:match('^%s*([%w_]+)%s*:')
    if yaml_key then
        return yaml_key
    end
    local json_key = line:match('%"([^%"]+)%"%s*:')
    if json_key then
        return json_key
    end
    return nil
end

local function find_key_at_cursor(candidates, cursor_line, cursor_col, file_type, bp)
    if #candidates == 0 then
        return nil
    end

    local has_line_data = false
    for _, c in ipairs(candidates) do
        if c.key_line > 0 then
            has_line_data = true
            break
        end
    end

    if not has_line_data then
        local buf = bp.Buf
        local max_line = buf:End().Y + 1
        local max_radius = math.max(cursor_line - 1, max_line - cursor_line)

        local function key_on_line(line_number)
            if line_number < 1 or line_number > max_line then
                return nil
            end
            local line_obj = buf:Line(line_number - 1)
            if line_obj == nil then
                return nil
            end
            return extract_key_from_line(line_obj)
        end

        local target_key = key_on_line(cursor_line)
        if target_key == nil then
            for radius = 1, max_radius do
                local before = key_on_line(cursor_line - radius)
                if before ~= nil then
                    target_key = before
                    break
                end

                local after = key_on_line(cursor_line + radius)
                if after ~= nil then
                    target_key = after
                    break
                end
            end
        end

        if target_key ~= nil then
            local matches = {}
            for _, c in ipairs(candidates) do
                if c.key == target_key then
                    table.insert(matches, c)
                end
            end

            if #matches > 0 then
                return matches[#matches]
            end
        end

        if #candidates > 0 then
            return candidates[#candidates]
        end
        return nil
    end

    local same_line = {}
    for _, c in ipairs(candidates) do
        if c.key_line == cursor_line then
            table.insert(same_line, c)
        end
    end

    if #same_line == 0 then
        for _, c in ipairs(candidates) do
            if math.abs(c.key_line - cursor_line) <= 1 then
                table.insert(same_line, c)
            end
        end
    end

    if #same_line == 0 then
        return nil
    end

    if #same_line == 1 then
        return same_line[1]
    end

    local best = same_line[1]
    local best_dist = math.abs(best.key_col - cursor_col)
    for i = 2, #same_line do
        local c = same_line[i]
        local dist = math.abs(c.key_col - cursor_col)
        if dist < best_dist then
            best = c
            best_dist = dist
        end
    end

    return best
end

local function path_to_yq_del_path(path_arr)
    if #path_arr == 0 then
        return ""
    end

    local parts = {}

    local function escape_double_quoted(value)
        value = string.gsub(value, "\\", "\\\\")
        value = string.gsub(value, '"', '\\"')
        return value
    end

    for _, p in ipairs(path_arr) do
        if type(p) == "number" then
            table.insert(parts, "[" .. tostring(p) .. "]")
        else
            if string.match(p, "^[A-Za-z_][A-Za-z0-9_]*$") then
                table.insert(parts, "." .. p)
            else
                table.insert(parts, '["' .. escape_double_quoted(p) .. '"]')
            end
        end
    end

    return table.concat(parts, "")
end

local function delete_key_with_yq(yq_exe, file_path, path_arr)
    local del_path = path_to_yq_del_path(path_arr)
    if del_path == "" then
        return "Cannot delete root"
    end

    local query = "del(" .. del_path .. ")"
    local _, err = shell.ExecCommand(yq_exe, "eval", "-i", query, file_path)
    if err ~= nil then
        return tostring(err)
    end

    return nil
end

local function config_delete_key(bp)
    local path = bp.Buf.Path
    if path == nil or path == "" then
        micro.InfoBar():Error("configdel: Save the buffer before deleting a key")
        return false
    end

    local yq_exe = resolve_yq()
    if yq_exe == nil then
        micro.InfoBar():Error("configdel: yq is required but not installed (https://github.com/mikefarah/yq/)")
        return false
    end

    local file_type = get_file_type(path)
    if file_type == nil then
        micro.InfoBar():Error("configdel: Unsupported filetype (only .yml, .yaml, .json supported)")
        return false
    end

    local cursor = bp.Buf:GetActiveCursor()
    if cursor == nil then
        micro.InfoBar():Error("configdel: No active cursor")
        return false
    end

    local cursor_line = cursor.Y + 1
    local cursor_col = cursor.X + 1

    local candidates, err = yq_key_candidates(yq_exe, path)
    if err ~= nil then
        micro.InfoBar():Error("configdel: Failed to parse file: " .. err)
        return false
    end

    if #candidates == 0 then
        micro.InfoBar():Error("configdel: No keys found in file")
        return false
    end

    local target = find_key_at_cursor(candidates, cursor_line, cursor_col, file_type, bp)
    if target == nil then
        micro.InfoBar():Error("configdel: No key found at cursor position")
        return false
    end

    local del_err = delete_key_with_yq(yq_exe, path, target.path)
    if del_err ~= nil then
        micro.InfoBar():Error("configdel: Delete failed: " .. del_err)
        return false
    end

    bp.Buf:ReOpen()
    micro.InfoBar():Message("Deleted key: " .. target.key)
    return true
end

local function delete_key_command(bp)
    config_delete_key(bp)
end

function init()
    config.MakeCommand("del-key", delete_key_command, config.NoComplete)
    local bound = false
    if config.BindKey ~= nil then
        local ok = pcall(config.BindKey, "Alt-d", "command:del-key", false)
        bound = ok
    end
    if not bound then
        config.TryBindKey("Alt-d", "command:del-key", false)
    end
    config.AddRuntimeFile("configdel", config.RTHelp, "help/configdel.md")
end
