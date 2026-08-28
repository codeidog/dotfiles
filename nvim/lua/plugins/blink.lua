-- <C-Space> collides with macOS's "Select next input source" shortcut,
-- so it never reaches Neovim. Bind blink.cmp's manual completion trigger
-- to <C-j> instead, without disturbing the default "enter" preset's
-- other bindings (<CR> accept, <C-y> select_and_accept, etc).
return {
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.keymap = opts.keymap or {}
      opts.keymap["<C-j>"] = { "show" }
    end,
  },
}
