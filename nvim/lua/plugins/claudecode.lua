return {
  {
    "coder/claudecode.nvim",
    dependencies = {
      -- Local dev plugin: https://github.jfrog.info/idoga/nvim-herdr-provider
      -- Tracked/versioned there, not here — see that repo for design notes.
      { dir = vim.fn.expand("~/Documents/Projects/nvim-herdr-provider"), name = "nvim-herdr-provider" },
    },
    opts = function(_, opts)
      -- `opts` as a function (not a table) so this `require` runs after lazy.nvim
      -- has added the dependency above to the runtime path, not at spec-load time.
      opts.terminal = opts.terminal or {}
      opts.terminal.provider = require("herdr_provider")

      opts.diff_opts = opts.diff_opts or {}
      opts.diff_opts.open_in_new_tab = true
      return opts
    end,
  },
}
