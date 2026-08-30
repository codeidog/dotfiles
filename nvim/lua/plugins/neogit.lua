return {
  "NeogitOrg/neogit",
  lazy = true,
  dependencies = {
    -- "sindrets/diffview.nvim", -- optional
    { "esmuellert/codediff.nvim", version = "v2.67.1" }, -- optional; pinned: newer builds broke neogit's integration (SessionConfig schema refactor)

    -- Only one of these is needed.
    -- "nvim-telescope/telescope.nvim", -- optional
    -- "ibhagwan/fzf-lua",              -- optional
    -- "nvim-mini/mini.pick",           -- optional
    "folke/snacks.nvim", -- optional
  },
  cmd = "Neogit",
  keys = {
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
  },
}
