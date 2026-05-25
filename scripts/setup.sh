#!/bin/bash

# Lumina - One-Step Setup Script
# This script prepares your environment to build and test the Lumina prototype.
#
# Usage:
#   ./scripts/setup.sh
#
# What it does:
#   - Builds the Swift project
#   - Creates ~/Movies/Lumina Samples folder
#   - Opens recommended royalty-free demo videos
#   - Opens the hardware testing guide
#   - Prints clear next steps

set -e

# Colors for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Lumina Prototype - Setup Script    ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get the directory where this script lives, then go to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}→ Moving to project directory...${NC}"
cd "$PROJECT_ROOT"
echo "   Current directory: $(pwd)"
echo ""

# Step 1: Build the project
echo -e "${YELLOW}→ Building the project with Swift...${NC}"
if swift build; then
    echo -e "${GREEN}   ✅ Build successful!${NC}"
else
    echo -e "${RED}   ❌ Build failed. Please check the errors above.${NC}"
    exit 1
fi
echo ""

# Step 2: Create samples folder
echo -e "${YELLOW}→ Creating samples folder...${NC}"
mkdir -p ~/Movies/Lumina\ Samples
echo -e "${GREEN}   ✅ Folder ready: ~/Movies/Lumina Samples${NC}"
echo ""

# Step 3: Open helpful resources
echo -e "${YELLOW}→ Opening recommended demo videos and documentation...${NC}"

# Best demo video (subtle clouds - excellent for wallpaper testing)
open "https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/" 2>/dev/null || true

# Second good option
open "https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/" 2>/dev/null || true

# Open the testing guide
open "docs/PROTOTYPE_TESTING.md" 2>/dev/null || true

echo -e "${GREEN}   ✅ Resources opened in your browser/editor${NC}"
echo ""

# Final instructions
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Download one of the opened videos (start with the Clouds video)"
echo "     and save it into:"
echo "     ~/Movies/Lumina Samples/"
echo ""
echo "  2. Run the prototype:"
echo "     .build/debug/Lumina"
echo ""
echo "  3. Click the menu bar icon (🌊) → \"Load Video…\" (⌘O)"
echo ""
echo "  4. For full testing instructions (Instruments, scenarios, checklist):"
echo "     See the file that just opened: docs/PROTOTYPE_TESTING.md"
echo ""
echo -e "${YELLOW}Tip:${NC} You can re-run this script anytime with:"
echo "     ./scripts/setup.sh"
echo ""
echo -e "${BLUE}========================================${NC}"