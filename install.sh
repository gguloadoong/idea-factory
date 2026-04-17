#!/bin/bash
# idea-factory installer
# Usage: curl -fsSL https://raw.githubusercontent.com/USER/idea-factory/main/install.sh | bash

set -e

REPO_URL="https://github.com/gguloadoong/idea-factory"
INSTALL_DIR="$HOME/.claude"
SKILL_DIR="$INSTALL_DIR/skills/start-company"
TEMPLATE_DIR="$INSTALL_DIR/templates/company"

echo "🏭 Installing idea-factory..."

# Detect install method
if [ -d ".git" ] && [ -f "install.sh" ]; then
  SOURCE_DIR="$(pwd)"
  echo "   Installing from local repo: $SOURCE_DIR"
else
  SOURCE_DIR=$(mktemp -d)
  echo "   Cloning from GitHub..."
  git clone --depth 1 "$REPO_URL" "$SOURCE_DIR" 2>/dev/null || {
    echo "❌ Failed to clone. Install from local: cd idea-factory && bash install.sh"
    exit 1
  }
fi

# Create directories
mkdir -p "$SKILL_DIR"
mkdir -p "$TEMPLATE_DIR"/{agents,hooks,documents}

# Install skill
cp "$SOURCE_DIR/skills/start-company/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "   ✓ Skill installed: /start-company"

# Install templates
cp "$SOURCE_DIR/templates/CLAUDE.md.tmpl" "$TEMPLATE_DIR/"
cp "$SOURCE_DIR/templates/settings.json" "$TEMPLATE_DIR/"
cp "$SOURCE_DIR/templates/agents/"*.md "$TEMPLATE_DIR/agents/"
cp "$SOURCE_DIR/templates/hooks/"*.sh "$TEMPLATE_DIR/hooks/"
cp "$SOURCE_DIR/templates/documents/"*.tmpl "$TEMPLATE_DIR/documents/"
chmod +x "$TEMPLATE_DIR/hooks/"*.sh
echo "   ✓ Templates installed: ~/.claude/templates/company/"

# Cleanup temp dir if cloned
if [ "$SOURCE_DIR" != "$(pwd)" ] && [ -d "$SOURCE_DIR/.git" ]; then
  rm -rf "$SOURCE_DIR"
fi

echo ""
echo "✅ idea-factory installed!"
echo ""
echo "Usage:"
echo "  Open Claude Code and type:"
echo "  /start-company a portfolio tracking app for busy investors"
echo ""
echo "Prerequisites:"
echo "  - Claude Code CLI (claude-sonnet-4-6 or claude-opus-4-7)"
echo "  - Node.js 18+"
echo "  - Git"
echo "  - (Optional) oh-my-claudecode for ralph autonomous loop"
echo ""
