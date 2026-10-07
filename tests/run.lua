--- Run with `nvim -l tests/run.lua` next to a live Omnigent server and `amh`.
--- Prints only failures; exits non-zero when any check fails.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local unwrap = require("omnigent.unwrap")
local failures = 0

local function check(name, got, want)
    if not vim.deep_equal(got, want) then
        failures = failures + 1
        print(("FAIL %s\n  got  %s\n  want %s"):format(name, vim.inspect(got), vim.inspect(want)))
    end
end

local source = "Intro.\n\nThe **quick** brown fox jumps over the `lazy` dog and keeps running far away.\n- first item\n- second item"
local shown = { "  The quick brown fox jumps over", "  the lazy dog and keeps running", "  far away.", "  - first item" }
check("locate", unwrap.locate(table.concat(shown, "\n"), { "other", source }), "The **quick** brown fox jumps over the `lazy` dog and keeps running far away.\n- first item")
check("locate curly quote", unwrap.locate("● It’s a\n  test", { "It’s a test — done" }), "It’s a test")
check("join bullets", unwrap.join({ "• first item that is quite long here", "• second" }), { "• first item that is quite long here", "• second" })
check("locate miss", unwrap.locate("absent text", { source }), nil)
check("join", unwrap.join(shown), { "The quick brown fox jumps over the lazy dog and keeps running far away.", "- first item" })
check("join keeps short lines", unwrap.join({ "one", "two", "", "a much longer line here" }), { "one", "two", "", "a much longer line here" })
check("quote", unwrap.quote({ "a", "", "b" }), { "> a", ">", "> b", "" })
check("parse_tasks", require("omnigent.api").parse_tasks("ready: a_b.md [long_running] omnigent://0abc session_status=idle\nnoise"), { ["0abc"] = { name = "a_b.md", status = "long_running" } })

require("omnigent").setup()
local sidebar, session = require("omnigent.sidebar"), require("omnigent.session")
vim.cmd("Omnigent toggle")
check("sidebar fills", vim.wait(10000, function()
    return next(sidebar.rows) ~= nil and next(sidebar.tasks) ~= nil
end), true)
check("first line is a section", vim.api.nvim_buf_get_lines(sidebar.buf, 0, 1, false)[1]:match("^.+ %(%d+%)$") ~= nil, true)

local live = vim.iter(sidebar.sessions):find(function(candidate)
    return candidate.status == "running"
end)
if live then
    session.open(live)
    check("terminal opens", vim.wait(10000, function()
        return session.terminals[live.id] ~= nil
    end), true)
    vim.wait(1500)
    local buf = session.terminals[live.id]
    check("terminal shows text", buf and #vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "")) > 0, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    require("omnigent.config").attach = "websocket"
    session.open(live)
    check("websocket terminal opens", vim.wait(10000, function()
        return session.terminals[live.id] ~= nil
    end), true)
    vim.wait(2500)
    buf = session.terminals[live.id]
    check("websocket terminal shows text", buf and #vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "")) > 0, true)
    vim.cmd("normal! ggVG")
    session.reply()
    check("reply quotes into compose", vim.wait(10000, function()
        return vim.bo.buftype == "acwrite" and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:sub(1, 1) == ">"
    end), true)
end
vim.cmd("Omnigent toggle")
check("sidebar hides", vim.fn.bufwinid(sidebar.buf), -1)
os.exit(failures == 0 and 0 or 1)
