-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Record nvim's cwd to ~/.nvim-cwd so the `cdnv` shell helper can jump to it
vim.api.nvim_create_autocmd({ "DirChanged", "VimEnter" }, {
  callback = function()
    vim.fn.writefile({ vim.fn.getcwd() }, vim.fn.expand("~/.nvim-cwd"))
  end,
})
