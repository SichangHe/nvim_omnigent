--- Calls to the Omnigent server and to `amh`. Every call is asynchronous;
--- `on_done(err, result)` runs on the main loop with `err` a string or `nil`.
local M = {}

local function run(cmd, opts, on_done)
    vim.system(cmd, opts, vim.schedule_wrap(function(result)
        if result.code ~= 0 then
            return on_done(vim.trim(result.stderr .. result.stdout))
        end
        on_done(nil, result.stdout)
    end))
end

--- Send an HTTP request to the Omnigent `server`; the result is the decoded JSON reply.
function M.request(server, method, path, body, on_done)
    local cmd = { "curl", "-sS", "--fail-with-body", "-X", method, server .. path }
    if body then
        vim.list_extend(cmd, { "-H", "Content-Type: application/json", "-d", vim.json.encode(body) })
    end
    run(cmd, { text = true }, function(err, stdout)
        if err then
            return on_done(err)
        end
        if stdout == "" then
            return on_done(nil, nil)
        end
        local ok, decoded = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
        on_done(not ok and decoded or nil, ok and decoded or nil)
    end)
end

--- Run `amh` with `args`; the result is its output.
--- Standard input is closed so that a question from `amh` fails instead of waiting.
function M.amh(amh, args, env, on_done)
    run(vim.list_extend({ amh }, args), { text = true, env = env, stdin = false }, on_done)
end

--- Map each session id to its `amh` task, parsed from `amh agent list` lines
--- `STATE: NAME.md [status] omnigent://ID ...`.
function M.parse_tasks(agent_list)
    local tasks = {}
    for line in agent_list:gmatch("[^\n]+") do
        local name, status, id = line:match("^%w+: (%S+%.md) %[(.-)%] omnigent://(%x+)")
        if name then
            tasks[id] = { name = name, status = status }
        end
    end
    return tasks
end

return M
