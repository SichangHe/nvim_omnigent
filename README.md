# nvim_omnigent

(authored by agents unless marked 🧑)

Use [Omnigent](https://github.com/omnigent-ai/omnigent) agents from Neovim: a sidebar of sessions in the web GUI's sections (Pinned, projects, Sessions), the agent's own terminal in the main window, and a normal buffer for writing messages.

Needs Neovim 0.11+, `curl`, `python3`, and an Omnigent server reachable at the configured URL. On the machine that runs the agents, the terminal attaches through `tmux`; elsewhere, for example on a laptop with the server's port forwarded, it attaches through the server's websocket. `amh`, the agent manager helper, is used when installed.

To use it from a laptop, forward the server port and set `server` to the forwarded address:

```sh
ssh -L 6767:localhost:6767 the-server
```

Starting, closing and messaging agents through `amh` only work where `amh` runs.

## Install

With lazy.nvim:

```lua
{ "SichangHe/nvim_omnigent", opts = {} }
```

Options and their defaults are in [`lua/omnigent/config.lua`](lua/omnigent/config.lua).

## Keys

Anywhere:

- `<leader>oo` show or hide the sidebar
- `<leader>on` start a new agent
- `<leader>om` write a message to the agent of the current buffer
- `<leader>or` (visual) quote the selection into a message

`<CR>` moves one step toward the agent:

- sidebar: open the agent's terminal
- agent terminal, normal mode: open the compose buffer
- agent terminal, visual mode: quote the selection into the compose buffer
- compose buffer, normal mode: send. `:w` also sends

Sidebar only: `m` message, `n` new agent, `D` close agent, `r` refresh, `q` hide.

The agent terminal is a normal Neovim terminal: `i` types into the agent, `<C-\><C-n>` returns to normal mode.

## Quoting agent output

Select text in the agent terminal and press `<CR>`. The plugin looks the selection up in the session transcript and quotes the passage as the agent wrote it, so the quote has no line breaks from terminal wrapping and keeps its Markdown. When no passage matches, it joins wrapped lines by a word wrap rule instead.

## Messages and amh

An agent that has an `amh` task gets messages through `amh task edit`, which appends them to its task file. Other sessions get them from the Omnigent server. Starting and closing agents use `amh task start`, `amh task close` and `amh agent stop`.

## Develop

`nvim -l tests/run.lua` runs the checks against the live server. Design notes are in [`docs/design.md`](docs/design.md).
