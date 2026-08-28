-- Colorscheme playground (Ghostty opacity / shaders need transparent = true).
-- Active theme: Rose Pine below.
-- To try another: comment out active block, uncomment Cyberdream, restart nvim.

return {
  ---------------------------------------------------------------------------
  -- Cyberdream (tuned for transparent + busy Ghostty shaders)
  -- Default neon is too loud over nebula; muted + lower saturation reads better.
  ---------------------------------------------------------------------------
  -- {
  --   "scottmckendry/cyberdream.nvim",
  --   opts = {
  --     transparent = true,
  --     variant = "muted", -- "default" | "light" | "muted"
  --     saturation = 0.7, -- 0 greyscale … 1 full neon (default)
  --     italic_comments = true,
  --     hide_fillchars = true,
  --     highlights = {
  --       -- Keep gutters see-through; bump contrast for opacity
  --       LineNr = { fg = "#7b8496", bg = "NONE" },
  --       CursorLineNr = { fg = "#ffbd5e", bg = "NONE", bold = true },
  --       SignColumn = { bg = "NONE" },
  --       FoldColumn = { bg = "NONE" },
  --       Comment = { fg = "#7b8496", bg = "NONE", italic = true },
  --     },
  --   },
  -- },
  -- {
  --   "LazyVim/LazyVim",
  --   opts = { colorscheme = "cyberdream" },
  -- },

  ---------------------------------------------------------------------------
  -- ACTIVE: Rose Pine Main (pairs well with space / opacity)
  ---------------------------------------------------------------------------
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      variant = "main", -- "main" | "moon" | "dawn"
      styles = {
        transparency = true,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "rose-pine" },
  },
}
