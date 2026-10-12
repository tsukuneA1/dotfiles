-- Load VS Code-style Python snippets and expand them with <Tab>.
local snippet_file = vim.fn.stdpath("config") .. "/snippets/python.json"
local snippet_lines = vim.fn.readfile(snippet_file)
local vscode_snippets = vim.json.decode(table.concat(snippet_lines, "\n"))
local snippets_by_prefix = {}
for _, snippet in pairs(vscode_snippets) do
  snippets_by_prefix[snippet.prefix] = snippet
end

local function render_body(body)
  if type(body) == "table" then
    body = table.concat(body, "\n")
  end

  local rendered = ""
  local cursor_offset
  local i = 1
  while i <= #body do
    local rest = body:sub(i)
    if rest:sub(1, 2) == "$0" then
      cursor_offset = #rendered
      i = i + 2
    else
      local token = rest:match("^%${%d+:[^}]*}")
      if token then
        rendered = rendered .. token:match("^%${%d+:(.*)}$")
        i = i + #token
      else
        token = rest:match("^%${%d+}") or rest:match("^%$%d+")
        if token then
          i = i + #token
        else
          rendered = rendered .. body:sub(i, i)
          i = i + 1
        end
      end
    end
  end
  return rendered, cursor_offset or #rendered
end

local function expand_or_insert_tab()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  local prefix = line:sub(1, col):match("([%w_]+)$")
  local snippet = prefix and snippets_by_prefix[prefix]
  if not snippet then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
    return
  end

  local expanded, offset = render_body(snippet.body)
  local start_col = col - #prefix
  vim.api.nvim_buf_set_text(0, row, start_col, row, col, vim.split(expanded, "\n", { plain = true }))

  local before_cursor = expanded:sub(1, offset)
  local newline_count = select(2, before_cursor:gsub("\n", ""))
  local last_newline = before_cursor:match(".*()\n")
  local target_col = last_newline and (#before_cursor - last_newline) or #before_cursor
  if newline_count == 0 then
    target_col = start_col + target_col
  end
  vim.api.nvim_win_set_cursor(0, { row + newline_count + 1, target_col })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(args)
    vim.keymap.set("i", "<Tab>", expand_or_insert_tab, {
      buffer = args.buf,
      silent = true,
      desc = "Expand Python snippet",
    })
  end,
})

-- Show keyword matches automatically while typing.  Ctrl-N completion also
-- searches other loaded buffers, so names from open files appear here too.
vim.opt.completeopt = { "menuone", "noinsert" }
vim.api.nvim_create_autocmd("TextChangedI", {
  callback = function()
    if vim.fn.pumvisible() == 1 then
      return
    end

    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local prefix = line:sub(1, cursor[2]):match("([%a_][%w_]*)$")
    if not prefix or #prefix < 2 then
      return
    end

    vim.schedule(function()
      if vim.fn.mode() ~= "i" or vim.api.nvim_get_current_buf() ~= buf then
        return
      end
      local current_cursor = vim.api.nvim_win_get_cursor(0)
      if current_cursor[1] ~= cursor[1] or current_cursor[2] ~= cursor[2] then
        return
      end
      if vim.bo[buf].filetype == "python" then
        local matches = {}
        local seen = {}
        for name, snippet in pairs(snippets_by_prefix) do
          if name:sub(1, #prefix) == prefix then
            matches[#matches + 1] = {
              word = name,
              kind = "S",
              menu = snippet.description or "snippet",
              user_data = "python_snippet",
            }
            seen[name] = true
          end
        end
        if #matches > 0 then
          table.sort(matches, function(a, b) return a.word < b.word end)
          -- Keep ordinary names available when a snippet has the same prefix.
          local line_count = math.min(vim.api.nvim_buf_line_count(buf), 2000)
          for _, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, line_count, false)) do
            for word in text:gmatch("[%a_][%w_]*") do
              if word ~= prefix and word:sub(1, #prefix) == prefix and not seen[word] then
                matches[#matches + 1] = { word = word, kind = "W" }
                seen[word] = true
                if #matches >= 100 then break end
              end
            end
            if #matches >= 100 then break end
          end
          vim.fn.complete(cursor[2] - #prefix + 1, matches)
          return
        end
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "n", false)
    end)
  end,
})

-- Expand a snippet after its completion item is accepted.
vim.api.nvim_create_autocmd("CompleteDone", {
  callback = function()
    local item = vim.v.completed_item
    if item.user_data ~= "python_snippet" then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.schedule(function()
      if vim.fn.mode() == "i" and vim.api.nvim_get_current_buf() == buf
          and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor) then
        expand_or_insert_tab()
      end
    end)
  end,
})

-- Accept the selected completion with Enter; otherwise insert a newline.
vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true, desc = "Accept completion or insert newline" })

-- Pick a directory from :cd with fzf.  :cd hoge/<Tab> searches below hoge.
local function fzf_cd(argument)
  if vim.fn.executable("fzf") ~= 1 then
    vim.notify("fzf is required for :cd completion", vim.log.levels.WARN)
    return
  end

  local parent, query = argument:match("^(.*)/([^/]*)$")
  local root = parent or "."
  query = query or argument
  if root == "" then root = "/" end
  root = vim.fn.expand(root)
  if vim.fn.isdirectory(root) ~= 1 then
    vim.notify("Not a directory: " .. root, vim.log.levels.WARN)
    return
  end

  local output = vim.fn.tempname()
  local width = math.max(1, math.floor(vim.o.columns * 0.8))
  local height = math.max(1, math.floor(vim.o.lines * 0.6))
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  local script = [[
find "$1" -mindepth 1 -maxdepth 6 \( -name .git -o -name node_modules -o -name .venv -o -name dist -o -name build \) -prune -o -type d -print |
  fzf --scheme=path --query "$3" --prompt='cd> ' > "$2"
]]
  vim.fn.termopen({ "sh", "-c", script, "sh", root, output, query }, {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
        local selected = vim.fn.filereadable(output) == 1 and vim.fn.readfile(output)[1] or nil
        vim.fn.delete(output)
        if selected and selected ~= "" then vim.api.nvim_set_current_dir(selected) end
      end)
    end,
  })
  vim.cmd.startinsert()
end

vim.keymap.set("c", "<Tab>", function()
  if vim.fn.getcmdtype() ~= ":" then return "<Tab>" end
  local line = vim.fn.getcmdline()
  local command, argument = line:match("^%s*(%a+)%s*(.*)$")
  if command ~= "cd" or vim.fn.getcmdpos() ~= #line + 1 then return "<Tab>" end
  vim.schedule(function() fzf_cd(argument) end)
  return "<C-c>"
end, { expr = true, desc = "Select a directory for :cd with fzf" })
