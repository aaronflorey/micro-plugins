VERSION = "0.3.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local filepath = import("path/filepath")
local strings = import("strings")
local os = import("os")

local oxfmt_filetypes = {
    javascript = true,
    typescript = true,
    json = true,
    json5 = true,
    yaml = true,
    toml = true,
    html = true,
    css = true,
    scss = true,
    less = true,
    markdown = true,
    mdx = true,
    graphql = true,
    vue = true,
}

local oxfmt_extensions = {
    [".js"] = true,
    [".cjs"] = true,
    [".mjs"] = true,
    [".jsx"] = true,
    [".ts"] = true,
    [".cts"] = true,
    [".mts"] = true,
    [".tsx"] = true,
    [".json"] = true,
    [".jsonc"] = true,
    [".json5"] = true,
    [".yaml"] = true,
    [".yml"] = true,
    [".toml"] = true,
    [".html"] = true,
    [".htm"] = true,
    [".vue"] = true,
    [".css"] = true,
    [".scss"] = true,
    [".less"] = true,
    [".md"] = true,
    [".markdown"] = true,
    [".mdx"] = true,
    [".gql"] = true,
    [".graphql"] = true,
    [".hbs"] = true,
    [".handlebars"] = true,
}

local function path_exists(path)
    local _, err = os.Stat(path)
    return err == nil
end

local function find_in_path(name)
    local path_env = os.Getenv("PATH")
    if path_env == nil or path_env == "" then
        return nil
    end

    for dir in string.gmatch(path_env, "([^:]+)") do
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

local function resolve_tool(start_dir, local_candidates, global_name)
    local local_path, root = find_upwards(start_dir, local_candidates)
    if local_path ~= nil then
        return local_path, root
    end

    local global_path = find_in_path(global_name)
    if global_path ~= nil then
        return global_path, start_dir
    end

    return global_name, start_dir
end

local function has_extension(path, extensions)
    return extensions[strings.ToLower(filepath.Ext(path))] == true
end

local function is_oxfmt_file(filetype, path)
    return oxfmt_filetypes[filetype] == true or has_extension(path, oxfmt_extensions)
end

local function formatter_for(path, filetype)
    local dir = filepath.Dir(path)

    if is_oxfmt_file(filetype, path) then
        local exe, cwd = resolve_tool(dir, {"node_modules/.bin/oxfmt"}, "oxfmt")
        return {
            name = "oxfmt",
            attempts = {
                {exe = exe, cwd = cwd, args = {path}},
            },
        }
    end

    if filetype == "php" or has_extension(path, { [".php"] = true, [".phtml"] = true }) then
        local exe, cwd = resolve_tool(dir, {"vendor/bin/ecs"}, "ecs")
        return {
            name = "ecs",
            attempts = {
                {exe = exe, cwd = cwd, args = {"check", path, "--fix"}},
            },
        }
    end

    if filetype == "go" or has_extension(path, { [".go"] = true }) then
        local exe, cwd = resolve_tool(dir, {}, "gofmt")
        return {
            name = "gofmt",
            attempts = {
                {exe = exe, cwd = cwd, args = {"-w", path}},
            },
        }
    end

    if filetype == "python" or has_extension(path, { [".py"] = true }) then
        local ruff_exe, ruff_cwd = resolve_tool(dir, {".venv/bin/ruff", "venv/bin/ruff"}, "ruff")
        local black_exe, black_cwd = resolve_tool(dir, {".venv/bin/black", "venv/bin/black"}, "black")
        return {
            name = "python formatter",
            attempts = {
                {exe = ruff_exe, cwd = ruff_cwd, args = {"format", path}},
                {exe = black_exe, cwd = black_cwd, args = {path}},
            },
        }
    end

    if filetype == "lua" or has_extension(path, { [".lua"] = true }) then
        local exe, cwd = resolve_tool(dir, {}, "stylua")
        return {
            name = "stylua",
            attempts = {
                {exe = exe, cwd = cwd, args = {path}},
            },
        }
    end

    if filetype == "shell" or filetype == "bash" or filetype == "zsh" or has_extension(path, { [".sh"] = true, [".bash"] = true, [".zsh"] = true }) then
        local exe, cwd = resolve_tool(dir, {}, "shfmt")
        return {
            name = "shfmt",
            attempts = {
                {exe = exe, cwd = cwd, args = {"-w", path}},
            },
        }
    end

    if filetype == "rust" or has_extension(path, { [".rs"] = true }) then
        local exe, cwd = resolve_tool(dir, {}, "rustfmt")
        return {
            name = "rustfmt",
            attempts = {
                {exe = exe, cwd = cwd, args = {path}},
            },
        }
    end

    return nil
end

local function run_attempt(attempt)
    local previous_dir, cwd_err = os.Getwd()
    if cwd_err == nil then
        local chdir_err = os.Chdir(attempt.cwd)
        if chdir_err ~= nil then
            return tostring(chdir_err)
        end
    end

    local _, err = shell.ExecCommand(attempt.exe, unpack(attempt.args))

    if cwd_err == nil then
        os.Chdir(previous_dir)
    end

    if err ~= nil then
        return tostring(err)
    end
    return nil
end

local function format_buffer(bp, options)
    options = options or {}

    local path = bp.Buf.Path
    if path == nil or path == "" then
        if not options.silent then
            micro.InfoBar():Error("Save the buffer before formatting")
        end
        return false
    end

    local filetype = ""
    local detected = bp.Buf:FileType()
    if detected ~= nil then
        filetype = strings.ToLower(detected)
    end

    local formatter = formatter_for(path, filetype)
    if formatter == nil then
        if not options.silent then
            if filetype == "" then
                micro.InfoBar():Error("No formatter configured for this file")
            else
                micro.InfoBar():Error("No formatter configured for filetype '" .. filetype .. "'")
            end
        end
        return false
    end

    bp:Save()

    local last_error = nil
    for _, attempt in ipairs(formatter.attempts) do
        local err = run_attempt(attempt)
        if err == nil then
            bp.Buf:ReOpen()
            if not options.quiet_success then
                micro.InfoBar():Message("Formatted with " .. formatter.name)
            end
            return true
        end

        last_error = err
        if not strings.Contains(err, "not found") and not strings.Contains(err, "executable file not found") then
            if not options.silent then
                micro.InfoBar():Error(err)
            end
            return false
        end
    end

    if not options.silent then
        micro.InfoBar():Error("No installed formatter found for this file (tried " .. formatter.name .. ")")
    end
    if last_error ~= nil then
        micro.Log(last_error)
    end
    return false
end

local function format_command(bp)
    format_buffer(bp, {})
end

function onSave(bp)
    if bp.Buf.Settings["format.onsave"] then
        format_buffer(bp, {silent = true, quiet_success = true})
    end
    return true
end

function init()
    config.RegisterCommonOption("format", "onsave", true)
    config.MakeCommand("format", format_command, config.NoComplete)
    config.AddRuntimeFile("format", config.RTHelp, "help/format.md")
end
