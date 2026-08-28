-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Colemak-DH: window navigation on Ctrl+Shift+Arrow (plain Ctrl+Arrow is claimed by macOS Mission
-- Control, and Option+Arrow is unreliable since terminals send Option+Left/Right as legacy
-- Meta-b/Meta-f word-nav codes instead of modified arrows)
vim.keymap.set("n", "<C-S-Up>", "<C-w>k", { desc = "Upper Window" })
vim.keymap.set("n", "<C-S-Down>", "<C-w>j", { desc = "Lower Window" })
vim.keymap.set("n", "<C-S-Left>", "<C-w>h", { desc = "Left Window" })
vim.keymap.set("n", "<C-S-Right>", "<C-w>l", { desc = "Right Window" })

-- Buffer switching on Shift+Arrow (default <S-h>/<S-l> use inconvenient letters)
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })

vim.keymap.set("t", "<C-q>", [[<C-\><C-n>]], { desc = "Terminal to Normal mode" })

vim.keymap.set("v", "(", "c()<Esc>P", { desc = "Wrap text in parentheses" })
vim.keymap.set("v", "[", "c[]<Esc>P", { desc = "Wrap text in square brackets" })
vim.keymap.set("v", "{", "c{}<Esc>P", { desc = "Warp text in curly brackets" })
