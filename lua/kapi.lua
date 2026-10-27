-- kapi.lua: look up Linux kernel APIs (kcalloc, kmalloc, ...) from a kernel tree.
-- Shows the kernel-doc comment + signature in a float; <CR> jumps to the source.
local M = {}

M.opts = {
  tree = vim.env.KERNEL_TREE or vim.fn.expand("~/repo/linux-stable"),
  -- directories searched, in priority order
  dirs = { "include", "lib", "mm", "kernel", "fs", "drivers", "net", "arch" },
}

function M.setup(o)
  M.opts = vim.tbl_extend("force", M.opts, o or {})
end

-- Walk up from a definition line to find a preceding /** ... */ block.
local function read_def(path, lnum)
  local lines = vim.fn.readfile(path)
  local first = lnum
  -- if the line above is a continuation of the prototype / attribute, ignore; keep simple
  local i = lnum - 1
  local doc_start
  if lines[i] and lines[i]:match("^%s*%*/") then
    while i >= 1 do
      if lines[i]:match("^/%*%*") then doc_start = i break end
      if lines[i]:match("^/%*") then break end
      i = i - 1
    end
  end
  local out = {}
  local s = doc_start or first
  local e = first
  -- take through the end of the signature / macro
  local depth_done = false
  while e <= #lines and e < first + 40 do
    local l = lines[e]
    if l:match("{%s*$") or l:match(";%s*$") or (l:match("^#define") and not l:match("\\%s*$")) then
      depth_done = true
    end
    if depth_done then break end
    e = e + 1
  end
  for n = s, math.min(e, #lines) do out[#out + 1] = lines[n] end
  return out, doc_start ~= nil
end

local function find(name)
  local t = M.opts.tree
  local dirs = {}
  for _, d in ipairs(M.opts.dirs) do
    if vim.uv.fs_stat(t .. "/" .. d) then dirs[#dirs + 1] = d end
  end
  -- column-0 function definition/prototype, or #define
  local pat = "^(#\\s*define\\s+" .. name .. "\\b|[A-Za-z_][^;=#]*[ \\t*]" .. name .. "\\()"
  local cmd = vim.list_extend({
    "rg", "--no-heading", "--line-number", "--with-filename", "--glob", "*.[ch]", "-e", pat,
  }, dirs)
  local res = vim.system(cmd, { cwd = t, text = true }):wait()
  local hits = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local f, n = line:match("^(.-):(%d+):")
    if f then
      local path = t .. "/" .. f
      local body, documented = read_def(path, tonumber(n))
      hits[#hits + 1] = { path = path, rel = f, lnum = tonumber(n), body = body, doc = documented }
    end
  end
  table.sort(hits, function(a, b)
    if a.doc ~= b.doc then return a.doc end
    local ah, bh = a.rel:match("%.h$") ~= nil, b.rel:match("%.h$") ~= nil
    if ah ~= bh then return ah end
    return a.rel < b.rel
  end)
  return hits
end

local function show(hit)
  local lines = vim.list_extend({ "// " .. hit.rel .. ":" .. hit.lnum, "" }, hit.body)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "c"
  vim.bo[buf].modifiable = false
  local w = 20
  for _, l in ipairs(lines) do w = math.max(w, #l) end
  w = math.min(w + 2, vim.o.columns - 6)
  local h = math.min(#lines, vim.o.lines - 8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    title = " kapi ", title_pos = "center",
  })
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  vim.keymap.set("n", "q", close, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf })
  vim.keymap.set("n", "<CR>", function()
    close()
    vim.cmd("edit " .. vim.fn.fnameescape(hit.path))
    vim.api.nvim_win_set_cursor(0, { hit.lnum, 0 })
    vim.cmd("normal! zz")
  end, { buffer = buf })
end

function M.lookup(name)
  name = name or vim.fn.expand("<cword>")
  if not name or name == "" then return end
  if vim.fn.executable("rg") == 0 then
    return vim.notify("kapi: ripgrep (rg) required", vim.log.levels.ERROR)
  end
  local hits = find(name)
  if #hits == 0 then
    return vim.notify("kapi: no definition of '" .. name .. "' in " .. M.opts.tree, vim.log.levels.WARN)
  end
  if #hits == 1 or hits[1].doc and not hits[2].doc then return show(hits[1]) end
  vim.ui.select(hits, {
    prompt = "kapi: " .. name,
    format_item = function(h) return (h.doc and "[doc] " or "      ") .. h.rel .. ":" .. h.lnum end,
  }, function(h) if h then show(h) end end)
end

function M.prompt()
  vim.ui.input({ prompt = "Kernel API: " }, function(s) if s and s ~= "" then M.lookup(s) end end)
end

return M
