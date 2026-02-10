#!/bin/bash
set -euo pipefail

# Release NDIKitC.xcframework to GitHub Releases.
#
# Xcode's SPM resolver cannot follow the 302 redirect from GitHub's
# browser download URLs. So Package.swift must use the GitHub API
# asset URL format: https://api.github.com/repos/OWNER/REPO/releases/assets/ID.zip
#
# The asset ID is only known after uploading. This script uses a
# draft release to upload first, then updates Package.swift with the
# correct API URL before committing and tagging.
#
# Sequence:
#   1. Create a draft GitHub Release and upload the zip
#   2. Look up the asset ID from the draft release
#   3. Update Package.swift with the API asset URL + checksum
#   4. Commit, tag, push
#   5. Publish the draft release (pointing at the final tag)
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - build-xcframework.sh already run (zip exists in Frameworks/)
#
# Usage:
#   ./Scripts/release.sh <version>
#   Example: ./Scripts/release.sh 6.0.1

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
    echo "  Example: $0 6.0.1"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"

# ============================================================================
# Paths
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$PROJECT_ROOT/Frameworks"
ZIP_PATH="$FRAMEWORKS_DIR/NDIKitC.xcframework.zip"
CHECKSUM_FILE="$FRAMEWORKS_DIR/NDIKitC.xcframework.zip.sha256"
PACKAGE_SWIFT="$PROJECT_ROOT/NDIKit/Package.swift"
NDIKIT_MIT_LICENSE_FILE="$PROJECT_ROOT/NDIKit/LICENSE"
THIRD_PARTY_NOTICES_FILE="$PROJECT_ROOT/THIRD_PARTY_NOTICES.md"
NDI_SDK_LICENSES_FILE="$PROJECT_ROOT/Vendor/NDI-SDK/lib/macOS/libndi_licenses.txt"

# ============================================================================
# Pre-flight checks
# ============================================================================
echo -e "${YELLOW}Pre-flight checks...${NC}"

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

if [ ! -f "$ZIP_PATH" ]; then
    echo -e "${RED}Error: $ZIP_PATH not found.${NC}"
    echo "Run build-xcframework.sh first."
    exit 1
fi

if [ ! -f "$CHECKSUM_FILE" ]; then
    echo -e "${RED}Error: $CHECKSUM_FILE not found.${NC}"
    echo "Run build-xcframework.sh first."
    exit 1
fi

if [ ! -f "$PACKAGE_SWIFT" ]; then
    echo -e "${RED}Error: $PACKAGE_SWIFT not found.${NC}"
    exit 1
fi

if [ ! -f "$NDIKIT_MIT_LICENSE_FILE" ]; then
    echo -e "${RED}Error: $NDIKIT_MIT_LICENSE_FILE not found.${NC}"
    exit 1
fi

if [ ! -f "$THIRD_PARTY_NOTICES_FILE" ]; then
    echo -e "${RED}Error: $THIRD_PARTY_NOTICES_FILE not found.${NC}"
    exit 1
fi

if [ ! -f "$NDI_SDK_LICENSES_FILE" ]; then
    echo -e "${RED}Error: $NDI_SDK_LICENSES_FILE not found.${NC}"
    exit 1
fi

# Verify tag doesn't already exist
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo -e "${RED}Error: Tag $TAG already exists.${NC}"
    echo "Delete it first with: ./Scripts/delete-release.sh $VERSION"
    exit 1
fi

CHECKSUM=$(cat "$CHECKSUM_FILE")
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1 | xargs)
NDIKIT_LICENSE_SIZE=$(du -h "$NDIKIT_MIT_LICENSE_FILE" | cut -f1 | xargs)
NOTICES_SIZE=$(du -h "$THIRD_PARTY_NOTICES_FILE" | cut -f1 | xargs)
NDI_LICENSES_SIZE=$(du -h "$NDI_SDK_LICENSES_FILE" | cut -f1 | xargs)

echo -e "${GREEN}✓ gh CLI authenticated${NC}"
echo -e "${GREEN}✓ Zip found: $ZIP_PATH ($ZIP_SIZE)${NC}"
echo -e "${GREEN}✓ Checksum: $CHECKSUM${NC}"
echo -e "${GREEN}✓ NDIKit MIT license: $NDIKIT_MIT_LICENSE_FILE ($NDIKIT_LICENSE_SIZE)${NC}"
echo -e "${GREEN}✓ Third-party notices: $THIRD_PARTY_NOTICES_FILE ($NOTICES_SIZE)${NC}"
echo -e "${GREEN}✓ NDI SDK licenses: $NDI_SDK_LICENSES_FILE ($NDI_LICENSES_SIZE)${NC}"
echo ""

# Detect repo from git remote
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO" ]; then
    echo -e "${RED}Error: Could not detect GitHub repo from current directory.${NC}"
    exit 1
fi

# Show git status
echo -e "${YELLOW}Git status:${NC}"
git -C "$PROJECT_ROOT" status --short
echo ""

RELEASE_NOTES="NDIKitC.xcframework binary for NDIKit $VERSION.

**Checksum (SHA-256):**
\`\`\`
$CHECKSUM
\`\`\`

**Supported platforms:**
- macOS (arm64) — Apple Silicon
- iOS (arm64) — iPhone / iPad devices

**Licensing assets included in this release:**
- \`NDIKIT_LICENSE.txt\` (MIT for NDIKit-authored code)
- \`THIRD_PARTY_NOTICES.md\` (NDI SDK licensing and attribution requirements)
- \`NDI_SDK_LICENSES.txt\` (upstream NDI SDK license text)

**Required attribution for products using NDI technology:**
\`This product includes NDI(R) technology licensed from Vizrt NDI AB.\`
\`NDI(R) is a registered trademark of Vizrt NDI AB.\`"

echo -e "${YELLOW}Release plan:${NC}"
echo "  Repository:  $REPO"
echo "  Tag:         $TAG"
echo "  Asset:       NDIKitC.xcframework.zip ($ZIP_SIZE)"
echo "  Asset:       NDIKIT_LICENSE.txt ($NDIKIT_LICENSE_SIZE)"
echo "  Asset:       THIRD_PARTY_NOTICES.md ($NOTICES_SIZE)"
echo "  Asset:       NDI_SDK_LICENSES.txt ($NDI_LICENSES_SIZE)"
echo "  Checksum:    $CHECKSUM"
echo ""
echo "  Steps:"
echo "    1. Create draft GitHub Release + upload zip"
echo "    2. Look up asset ID from draft"
echo "    3. Update Package.swift with API asset URL + checksum"
echo "    4. Commit: \"Release $TAG\""
echo "    5. Tag: $TAG"
echo "    6. Push commit + tag to origin"
echo "    7. Publish draft release"
echo ""

# ============================================================================
# Confirmation
# ============================================================================
read -p "Proceed with release? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Upload an asset to a GitHub release and print its asset ID.
upload_release_asset() {
    local FILE_PATH="$1"
    local ASSET_NAME="$2"
    local CONTENT_TYPE="$3"
    local UPLOAD_URL="https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME"
    local RESPONSE

    RESPONSE=$(curl -sSf \
        -H "Authorization: token $(gh auth token)" \
        -H "Content-Type: $CONTENT_TYPE" \
        --data-binary "@$FILE_PATH" \
        "$UPLOAD_URL")

    python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" <<< "$RESPONSE"
}

# ============================================================================
# Step 1: Create draft GitHub Release and upload assets
# ============================================================================
echo -e "${YELLOW}Step 1: Creating draft release and uploading assets...${NC}"

# Create a draft release via the GitHub API (draft=true means no tag is created yet)
RELEASE_ID=$(gh api "repos/$REPO/releases" \
    --method POST \
    -f tag_name="$TAG" \
    -f name="NDIKitC $VERSION" \
    -f body="$RELEASE_NOTES" \
    -F draft=true \
    --jq '.id')

echo -e "${GREEN}✓ Draft release created (ID: $RELEASE_ID)${NC}"

# Upload assets to the draft release.
ASSET_ID=$(upload_release_asset "$ZIP_PATH" "NDIKitC.xcframework.zip" "application/zip")
NDIKIT_LICENSE_ASSET_ID=$(upload_release_asset "$NDIKIT_MIT_LICENSE_FILE" "NDIKIT_LICENSE.txt" "text/plain")
NOTICES_ASSET_ID=$(upload_release_asset "$THIRD_PARTY_NOTICES_FILE" "THIRD_PARTY_NOTICES.md" "text/markdown")
NDI_LICENSES_ASSET_ID=$(upload_release_asset "$NDI_SDK_LICENSES_FILE" "NDI_SDK_LICENSES.txt" "text/plain")

echo -e "${GREEN}✓ Zip uploaded (Asset ID: $ASSET_ID)${NC}"
echo -e "${GREEN}✓ NDIKit MIT license uploaded (Asset ID: $NDIKIT_LICENSE_ASSET_ID)${NC}"
echo -e "${GREEN}✓ Third-party notices uploaded (Asset ID: $NOTICES_ASSET_ID)${NC}"
echo -e "${GREEN}✓ NDI SDK licenses uploaded (Asset ID: $NDI_LICENSES_ASSET_ID)${NC}"

# ============================================================================
# Step 2: Construct the API asset URL
# ============================================================================
# Xcode's SPM needs the API URL format with .zip suffix.
API_URL="https://api.github.com/repos/$REPO/releases/assets/$ASSET_ID.zip"

echo -e "${GREEN}✓ API URL: $API_URL${NC}"

# ============================================================================
# Step 3: Update Package.swift with API URL and checksum
# ============================================================================
echo -e "${YELLOW}Step 3: Updating Package.swift...${NC}"

# Replace the URL line (matches both old browser URLs and API URLs)
sed -i '' "s|url: \"https://[^\"]*\"|url: \"$API_URL\"|" "$PACKAGE_SWIFT"

# Replace the checksum line
sed -i '' "s|checksum: \"[a-f0-9]*\"|checksum: \"$CHECKSUM\"|" "$PACKAGE_SWIFT"

echo -e "${GREEN}✓ Package.swift updated${NC}"
echo "    url: \"$API_URL\""
echo "    checksum: \"$CHECKSUM\""

# ============================================================================
# Step 4: Commit
# ============================================================================
echo -e "${YELLOW}Step 4: Committing changes...${NC}"

git -C "$PROJECT_ROOT" add "$PACKAGE_SWIFT"
git -C "$PROJECT_ROOT" commit -m "Release $TAG"

echo -e "${GREEN}✓ Committed: Release $TAG${NC}"

# ============================================================================
# Step 5: Create git tag
# ============================================================================
echo -e "${YELLOW}Step 5: Creating tag $TAG...${NC}"

git -C "$PROJECT_ROOT" tag "$TAG"

echo -e "${GREEN}✓ Tag $TAG created${NC}"

# ============================================================================
# Step 6: Push commit + tag to origin
# ============================================================================
echo -e "${YELLOW}Step 6: Pushing to origin...${NC}"

git -C "$PROJECT_ROOT" push origin
git -C "$PROJECT_ROOT" push origin "$TAG"

echo -e "${GREEN}✓ Pushed commit and tag to origin${NC}"

# ============================================================================
# Step 7: Publish the draft release, pointing at the final tag
# ============================================================================
echo -e "${YELLOW}Step 7: Publishing release...${NC}"

gh api "repos/$REPO/releases/$RELEASE_ID" \
    --method PATCH \
    -F draft=false \
    -f tag_name="$TAG" \
    --silent

echo -e "${GREEN}✓ Release $TAG published${NC}"

# ============================================================================
# Done
# ============================================================================
echo ""
echo -e "${GREEN}Done! Release $TAG is live.${NC}"
echo ""
echo "  Release: https://github.com/$REPO/releases/tag/$TAG"
echo "  API URL: $API_URL"
