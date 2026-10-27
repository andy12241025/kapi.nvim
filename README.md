# kapi.nvim

Look up Linux kernel APIs (`kcalloc`, `kmalloc`, ...) from inside Neovim. Searches a kernel tree with ripgrep and shows the kernel-doc comment and signature in a float.

Requires `rg`.

```lua
{
  "andy12241025/kapi.nvim",
  config = function()
    local kapi = require("kapi")
    kapi.setup({ tree = vim.fn.expand("~/repo/linux-stable") }) -- or $KERNEL_TREE
    vim.api.nvim_create_user_command("Kapi", function(a) kapi.lookup(a.args ~= "" and a.args or nil) end, { nargs = "?" })
    vim.keymap.set("n", "<leader>kk", kapi.lookup, { desc = "Kernel API under cursor" })
    vim.keymap.set("n", "<leader>ks", kapi.prompt, { desc = "Kernel API search" })
  end,
}
```

In the float: `<CR>` opens the source, `q`/`<Esc>` closes.
