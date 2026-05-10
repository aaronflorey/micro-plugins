VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local strings = import("strings")
local os = import("os")
local json = import("encoding/json")

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

local function parse_json_array(json_str)
    local success, result = pcall(json.Unmarshal, json_str)
    if not success then
        return nil
    end
    return result
end

local function yq_key_candidates(yq_exe, file_path)
    local query = '.. | select(tag == "!!map") | .[] | {"path": path, "key": key, "key_line": (key | line), "key_col": (key | column)}'
    local output, err = shell.ExecCommand(yq_exe, "eval", "-o=json", "-I=0", query, file_path)
    if err ~= nil then
        return nil, tostring(err)
    end

    local candidates = {}
    for line in output:gmatch("[^\n]+") do
        line = strings.TrimSpace(line)
        if line ~= "" then
            local candidate = parse_json_array(line)
            if candidate ~= nil then
                table.insert(candidates, candidate)
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
        local start_line = math.max(1, cursor_line - 5)
        local end_line = math.min(cursor_line + 5, buf:End().Y + 1)
        local line_keys = {}
        for ln = start_line, end_line do
            local loc = {X = 0, Y = ln - 1}
            local line_text = ""
            local line_obj = buf:Line(ln - 1)
            if line_obj ~= nil then
                line_text = line_obj
            end
            local key = extract_key_from_line(line_text)
            if key then
                line_keys[key] = ln
            end
        end
        for _, c in ipairs(candidates) do
            if line_keys[c.key] ~= nil then
                return c
            end
        end
        if #candidates > 0 then
            return candidates[1]
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
    for _, p in ipairs(path_arr) do
        if type(p) == "number" then
            table.insert(parts, "[" .. tostring(p) .. "]")
        else
            if #parts == 0 then
                table.insert(parts, "." .. p)
            else
                table.insert(parts, "." .. p)
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
    config.BindKey("Alt-d", "command:del-key")
    config.AddRuntimeFile("configdel", config.RTHelp, "help/configdel.md")
end
