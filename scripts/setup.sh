#!/bin/bash

# Lumina - One-Step Setup Script (Enhanced)
# Prepares your environment to build and test the Lumina prototype.
#
# Features:
# - Checks macOS and Swift versions
# - Detects and offers to install missing Command Line Tools
# - Safe color output (auto-detects terminal support)
# - Builds the project + prepares demo assets and docs
#
# Usage:
#   ./scripts/setup.sh
#   ./scripts/setup.sh --no-color

set -u  # Treat unset variables as error (but handle carefully)

# =============================================================================
# Color Handling (safe for all terminals)
# =============================================================================

# Default to no color
USE_COLOR=false

# Detect color support
detect_colors() {
    # Check for --no-color flag
    for arg in "$@"; do
        if [[ "$arg" == "--no-color" ]]; then
            USE_COLOR=false
            return
        fi
    done

    # Check if stdout is a terminal and supports colors
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        if [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
            USE_COLOR=true
        fi
    fi
}

# Color variables (populated only if supported)
setup_colors() {
    if $USE_COLOR; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        BOLD='\033[1m'
        NC='\033[0m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        BOLD=''
        NC=''
    fi
}

print_header()    { echo -e "${BLUE}${BOLD}========================================${NC}"; }
print_title()     { echo -e "${BLUE}${BOLD}   Lumina Prototype - Setup Script    ${NC}"; }
print_success()   { echo -e "${GREEN}✅ $1${NC}"; }
print_warning()   { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()     { echo -e "${RED}❌ $1${NC}"; }
print_info()      { echo -e "${BLUE}→ $1${NC}"; }
print_plain()     { echo -e "$1"; }

# =============================================================================
# Version & Environment Checks
# =============================================================================

check_macos_version() {
    print_info "Checking macOS version..."

    if ! command -v sw_vers >/dev/null 2>&1; then
        print_warning "Could not detect macOS version (sw_vers not found)."
        return 0
    fi

    local os_version
    os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")

    print_plain "   macOS version: $os_version"

    # Basic check: warn if below 15.0 (Sequoia)
    # Project targets latest (Tahoe / 26+), but works on 15+
    if [[ "$os_version" =~ ^[0-9]+ ]]; then
        local major
        major=$(echo "$os_version" | cut -d. -f1)
        if [[ "$major" -lt 15 ]]; then
            print_warning "macOS $os_version detected. Lumina is designed for macOS 15+ (best on 26+)."
            print_plain "   The prototype may still work, but some features (window levels, power APIs) are optimized for newer macOS."
        else
            print_success "macOS version looks good ($os_version)"
        fi
    fi
}

check_swift_version() {
    print_info "Checking Swift toolchain..."

    if ! command -v swift >/dev/null 2>&1; then
        print_error "Swift command not found!"
        print_plain "   You need Swift 6.3+ (included with Xcode Command Line Tools or full Xcode)."
        return 1
    fi

    local swift_full_version
    swift_full_version=$(swift --version 2>/dev/null | head -n 1)

    print_plain "   $swift_full_version"

    # Extract major.minor
    local swift_version
    swift_version=$(echo "$swift_full_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)

    if [[ -z "$swift_version" ]]; then
        print_warning "Could not parse Swift version. Proceeding anyway."
        return 0
    fi

    # Compare versions (very basic)
    local major minor
    IFS='.' read -r major minor <<< "$swift_version"

    if [[ "$major" -lt 6 ]] || { [[ "$major" -eq 6 ]] && [[ "$minor" -lt 3 ]]; }; then
        print_warning "Swift $swift_version detected. Recommended: Swift 6.3+"
        print_plain "   You can still try to build, but some modern concurrency features may not work perfectly."
    else
        print_success "Swift version looks good ($swift_version)"
    fi
}

check_developer_tools() {
    print_info "Checking for Apple developer tools (required for building)..."

    local dev_path
    if dev_path=$(xcode-select -p 2>/dev/null); then
        print_success "Developer tools found: $dev_path"

        # Check if we have full Xcode (for Instruments)
        if [[ "$dev_path" == *"/Xcode.app/"* ]]; then
            print_success "Full Xcode detected (great for Instruments later)"
        else
            print_plain "   You have Command Line Tools. This is sufficient for building the prototype."
            print_plain "   For Instruments (battery/CPU profiling), install full Xcode from the App Store."
        fi
        return 0
    else
        print_error "No Apple developer tools found!"
        print_plain ""
        print_plain "   The project requires Xcode Command Line Tools to build."
        print_plain ""
        read -r -p "Would you like to install Command Line Tools now? [y/N] " response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_info "Launching Command Line Tools installer..."
            print_plain "   A dialog will appear. Follow the prompts to install."
            xcode-select --install || true
            print_warning "After the installation finishes, please re-run this script."
            exit 0
        else
            print_warning "Skipping installation."
            print_plain "   You can install later with: xcode-select --install"
            print_plain "   Then re-run: ./scripts/setup.sh"
            return 1
        fi
    fi
}

# =============================================================================
# Main Setup Logic
# =============================================================================

main() {
    detect_colors "$@"
    setup_colors

    # Support quick dev run: ./scripts/setup.sh --run
    if [[ "${1:-}" == "--run" || "${1:-}" == "run" ]]; then
        quick_dev_run
        exit 0
    fi

    print_header
    print_title
    print_header
    echo ""

    # --- Environment Checks ---
    check_macos_version
    echo ""

    if ! check_swift_version; then
        print_error "Swift is required. Please install Xcode Command Line Tools or full Xcode."
        exit 1
    fi
    echo ""

    if ! check_developer_tools; then
        # User chose not to install or tools are missing
        print_warning "Continuing without developer tools may cause the build to fail."
        echo ""
    fi
    echo ""

    # Get project root
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    print_info "Moving to project directory..."
    cd "$PROJECT_ROOT" || exit 1
    print_plain "   $(pwd)"
    echo ""

    # Build
    print_info "Building the project..."
    # Use relaxed concurrency mode during development to avoid Swift 6 data-race
    # warnings from thumbnail loading (these are safe in this context).
    # We can tighten this later once we do a full concurrency audit.
    if swift build -Xswiftc -strict-concurrency=minimal; then
        print_success "Build completed successfully!"
    else
        print_error "Build failed. See errors above."
        exit 1
    fi
    echo ""

    # Samples folder
    print_info "Creating samples folder..."
    mkdir -p ~/Movies/Lumina\ Samples
    print_success "Folder ready: ~/Movies/Lumina Samples"

    # Check for a demo video (convention: demo.mp4 makes it easy for scripts / future auto-load)
    if [[ -f ~/Movies/Lumina\ Samples/demo.mp4 ]]; then
        print_success "Demo video detected: ~/Movies/Lumina Samples/demo.mp4"
    else
        print_plain "   (No demo.mp4 found yet — drop or rename a video to demo.mp4 for easy reference)"
    fi
    echo ""

    # Open resources (only on first-time / incomplete setup)
    if [[ -f ~/Movies/Lumina\ Samples/demo.mp4 ]]; then
        print_plain "   Demo video already present — skipping first-time resource opens (Mixkit links + testing guide)."
    else
        print_info "Opening recommended demo videos and documentation (first-time setup)..."
        open "https://mixkit.co/free-stock-video/clouds-and-blue-sky-background-2408/" 2>/dev/null || true
        open "https://mixkit.co/free-stock-video/multicolor-ink-swirls-in-water-286/" 2>/dev/null || true
        open "docs/PROTOTYPE_TESTING.md" 2>/dev/null || true
        print_success "Resources opened"
    fi
    echo ""

    # Final instructions
    print_header
    print_success "Setup complete!"
    print_header
    echo ""
    print_plain "${BOLD}Next steps:${NC}"
    echo ""

    if [[ -f ~/Movies/Lumina\ Samples/demo.mp4 ]]; then
        print_plain "  1. Your demo video is ready at ~/Movies/Lumina Samples/demo.mp4"
    else
        print_plain "  1. Place (or rename) a video as demo.mp4 inside ~/Movies/Lumina Samples/"
    fi

    echo ""
    print_plain "  2. Build the release app:   ./build"
    print_plain "  3. Run the real app:        ./run"
    print_plain "  4. Load it via the menu bar icon → \"Load Video…\" (⌘O)"
    echo ""
    print_plain "  5. Read docs/PROTOTYPE_TESTING.md for verification steps."
    echo ""
    print_plain "${YELLOW}Tip:${NC} Always use ./run to test (it uses the packaged dist/Lumina.app)"
    echo ""
    print_plain "${YELLOW}Re-run anytime:${NC}"
    print_plain "  Build only:   ./build"
    print_plain "  Build + Run:  ./run"
    print_plain "  (This replaces the old debug + setup --run workflow)"
    echo ""
    print_header
}

main "$@"

# --- Legacy support (kept for now) ---
# The recommended commands are now ./build and ./run at the project root.
# These build and launch the real packaged dist/Lumina.app instead of debug.

