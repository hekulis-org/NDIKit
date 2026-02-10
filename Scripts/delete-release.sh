#!/bin/bash
set -euo pipefail

# Delete an NDIKitC release from GitHub.
#
# This script:
#   1. Deletes the GitHub Release for the given version
#   2. Deletes the local and remote git tag
#
# Prerequisites:
#   - gh CLI installed and authenticated
#
# Usage:
#   ./Scripts/delete-release.sh <version>
#   Example: ./Scripts/delete-release.sh 0.1.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# Argument validation
# ============================================================================
if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <version>${NC}"
    echo "  Example: $0 0.1.0"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"

# ============================================================================
# Pre-flight checks
# ============================================================================
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed.${NC}"
    echo "Install with: brew install gh"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub CLI.${NC}"
    echo "Run: gh auth login"
    exit 1
fi

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO" ]; then
    echo -e "${RED}Error: Could not detect GitHub repo from current directory.${NC}"
    exit 1
fi

echo -e "${YELLOW}Delete plan:${NC}"
echo "  Repository: $REPO"
echo "  Tag:        $TAG"
echo ""

# ============================================================================
# Confirmation
# ============================================================================
read -p "Delete release $TAG and its tag? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================================
# Step 1: Delete the GitHub Release
# ============================================================================
if gh release view "$TAG" --repo "$REPO" &> /dev/null; then
    echo -e "${YELLOW}Deleting GitHub Release $TAG...${NC}"
    gh release delete "$TAG" --repo "$REPO" --yes
    echo -e "${GREEN}✓ Release $TAG deleted.${NC}"
else
    echo -e "${YELLOW}No GitHub Release found for $TAG, skipping.${NC}"
fi

# ============================================================================
# Step 2: Delete the remote tag
# ============================================================================
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q "$TAG"; then
    echo -e "${YELLOW}Deleting remote tag $TAG...${NC}"
    git push origin --delete "$TAG"
    echo -e "${GREEN}✓ Remote tag $TAG deleted.${NC}"
else
    echo -e "${YELLOW}No remote tag $TAG found, skipping.${NC}"
fi

# ============================================================================
# Step 3: Delete the local tag
# ============================================================================
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo -e "${YELLOW}Deleting local tag $TAG...${NC}"
    git tag -d "$TAG"
    echo -e "${GREEN}✓ Local tag $TAG deleted.${NC}"
else
    echo -e "${YELLOW}No local tag $TAG found, skipping.${NC}"
fi

echo ""
echo -e "${GREEN}Done! Release $TAG has been removed.${NC}"
