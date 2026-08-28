#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

if command -v gh >/dev/null 2>&1; then
  echo "==> Installing gh-dash extension..."
  gh extension install dlvhdr/gh-dash 2>/dev/null || echo "    (already installed)"
fi

echo "==> Stowing dotfiles..."
cd "$DOTFILES_DIR"
stow -v .

echo "==> Bootstrap complete."
