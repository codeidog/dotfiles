-- Terraform/Ansible/Docker/YAML/Helm/Git/JSON support is enabled via
-- `:LazyExtras` instead of imported here (see lazyvim.json) — keeps the
-- ordering that LazyVim's own extras system already handles correctly.
return {
  -- Bash/shell has no first-party LazyVim extra (yet), so it's wired by hand
  -- below, the same way the disabled example.lua shows for pyright.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "shellcheck", "shfmt" },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        sh = { "shfmt" },
        bash = { "shfmt" },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
      },
    },
  },
}
