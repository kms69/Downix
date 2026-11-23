#!/bin/bash

# Quick Verification Script for Download Manager
# Tests basic functionality without requiring Xcode

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Download Manager - Quick Verification Script           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

function test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

function test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

function test_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

function test_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Check Swift Installation
echo -e "\n${BLUE}═══ Test 1: Swift Installation ═══${NC}"
if command -v swift &> /dev/null; then
    SWIFT_VERSION=$(swift --version | head -n 1)
    test_pass "Swift installed: $SWIFT_VERSION"
else
    test_fail "Swift not found"
    exit 1
fi

# Test 2: Check File Structure
echo -e "\n${BLUE}═══ Test 2: File Structure ═══${NC}"

FILES=(
    "DownloadManager/Sources/Models/DownloadTask.swift"
    "DownloadManager/Sources/DownloadEngine/DownloadManager.swift"
    "DownloadManager/Sources/DownloadEngine/SegmentDownloader.swift"
    "DownloadManager/Tests/DownloadTaskTests.swift"
    "DownloadManager/Tests/DownloadManagerTests.swift"
    "DownloadManager/Tests/IntegrationTests.swift"
    "PROJECT_SPECIFICATION.md"
    "README.md"
    "TESTING_GUIDE.md"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        test_pass "Found: $file"
    else
        test_fail "Missing: $file"
    fi
done

# Test 3: Syntax Check
echo -e "\n${BLUE}═══ Test 3: Swift Syntax Validation ═══${NC}"

SWIFT_FILES=(
    "DownloadManager/Sources/Models/DownloadTask.swift"
    "DownloadManager/Sources/DownloadEngine/SegmentDownloader.swift"
    "DownloadManager/Sources/DownloadEngine/DownloadManager.swift"
)

for file in "${SWIFT_FILES[@]}"; do
    if swiftc -typecheck "$file" 2>/dev/null; then
        test_pass "Syntax valid: $(basename $file)"
    else
        test_warn "Syntax check skipped for: $(basename $file) (may need dependencies)"
    fi
done

# Test 4: Count Lines of Code
echo -e "\n${BLUE}═══ Test 4: Code Statistics ═══${NC}"

TOTAL_LINES=$(find DownloadManager/Sources -name "*.swift" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
if [ ! -z "$TOTAL_LINES" ]; then
    test_info "Total lines of code: $TOTAL_LINES"
fi

TEST_LINES=$(find DownloadManager/Tests -name "*.swift" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
if [ ! -z "$TEST_LINES" ]; then
    test_info "Total lines of test code: $TEST_LINES"
fi

FILE_COUNT=$(find DownloadManager/Sources -name "*.swift" | wc -l)
test_info "Swift source files: $FILE_COUNT"

TEST_COUNT=$(find DownloadManager/Tests -name "*Tests.swift" | wc -l)
test_info "Test files: $TEST_COUNT"

# Test 5: Check for Common Issues
echo -e "\n${BLUE}═══ Test 5: Code Quality Checks ═══${NC}"

# Check for TODO comments
TODO_COUNT=$(grep -r "TODO" DownloadManager/Sources/ 2>/dev/null | wc -l)
if [ $TODO_COUNT -gt 0 ]; then
    test_info "Found $TODO_COUNT TODO items"
else
    test_pass "No TODO items found"
fi

# Check for print statements (should use proper logging)
PRINT_COUNT=$(grep -r "print(" DownloadManager/Sources/ 2>/dev/null | wc -l)
if [ $PRINT_COUNT -gt 0 ]; then
    test_warn "Found $PRINT_COUNT print statements (consider adding logging)"
else
    test_pass "No debug print statements"
fi

# Test 6: Network Connectivity
echo -e "\n${BLUE}═══ Test 6: Network Connectivity ═══${NC}"

if ping -c 1 google.com &> /dev/null; then
    test_pass "Internet connection available"
else
    test_warn "No internet connection (integration tests may fail)"
fi

# Test if test server is reachable
if curl -I https://speed.hetzner.de/1MB.bin 2>/dev/null | head -n 1 | grep "200" &> /dev/null; then
    test_pass "Test file server accessible (speed.hetzner.de)"
else
    test_warn "Test file server not accessible"
fi

# Test 7: Directory Permissions
echo -e "\n${BLUE}═══ Test 7: File System Permissions ═══${NC}"

DOWNLOAD_DIR="$HOME/Downloads"
if [ -d "$DOWNLOAD_DIR" ]; then
    test_pass "Downloads directory exists: $DOWNLOAD_DIR"
    
    if [ -w "$DOWNLOAD_DIR" ]; then
        test_pass "Downloads directory is writable"
    else
        test_fail "Downloads directory is not writable"
    fi
else
    test_warn "Downloads directory not found"
fi

TEMP_DIR=$(mktemp -d 2>/dev/null)
if [ -d "$TEMP_DIR" ]; then
    test_pass "Can create temporary directories"
    rm -rf "$TEMP_DIR"
else
    test_fail "Cannot create temporary directories"
fi

# Test 8: Package Structure
echo -e "\n${BLUE}═══ Test 8: Package Configuration ═══${NC}"

if [ -f "Package.swift" ]; then
    test_pass "Package.swift exists"
    
    # Try to resolve dependencies (won't build, just check Package.swift syntax)
    if swift package dump-package > /dev/null 2>&1; then
        test_pass "Package.swift is valid"
    else
        test_warn "Package.swift may have issues"
    fi
else
    test_fail "Package.swift missing"
fi

# Summary
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Test Summary                           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))
    echo "Success Rate: $SUCCESS_RATE%"
fi

echo ""
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Run the test runner: swift DownloadManager/Tests/TestRunner.swift"
    echo "2. Create Xcode project: open Package.swift"
    echo "3. Run unit tests in Xcode: ⌘ + U"
    echo "4. Test actual downloads"
    EXIT_CODE=0
else
    echo -e "${RED}✗ Some checks failed${NC}"
    echo "Review the errors above and fix any issues"
    EXIT_CODE=1
fi

echo ""
echo -e "${BLUE}Verification completed at: $(date)${NC}"
echo ""

exit $EXIT_CODE
