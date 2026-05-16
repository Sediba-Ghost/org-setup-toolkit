#!/bin/bash
################################################################################
# PRE-MIGRATION CHECKLIST
# 
# Purpose: Validates that all prerequisites are met before starting the
#          enterprise-grade migration process.
#
# Usage: bash scripts/04-pre-migration-checklist.sh
#
# Exit Codes:
#   0 = All checks passed, safe to proceed
#   1 = One or more checks failed, DO NOT PROCEED
################################################################################

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CHECKLIST_REPORT="pre-migration-checklist-${TIMESTAMP}.txt"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   🔍 PRE-MIGRATION CHECKLIST & VALIDATION SUITE            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Timestamp: $(date)" | tee -a "$CHECKLIST_REPORT"
echo "Hostname: $(hostname)" | tee -a "$CHECKLIST_REPORT"
echo "" | tee -a "$CHECKLIST_REPORT"

# Function to run a check
run_check() {
    local check_name=$1
    local check_command=$2
    local severity=${3:-"error"}  # error, warning, info
    
    echo -n "Checking: $check_name ... " | tee -a "$CHECKLIST_REPORT"
    
    if eval "$check_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}" | tee -a "$CHECKLIST_REPORT"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        if [ "$severity" = "warning" ]; then
            echo -e "${YELLOW}⚠️  WARNING${NC}" | tee -a "$CHECKLIST_REPORT"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
        else
            echo -e "${RED}❌ FAIL${NC}" | tee -a "$CHECKLIST_REPORT"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        fi
    fi
}

################################################################################
# SECTION 1: SYSTEM DEPENDENCIES
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 1: SYSTEM DEPENDENCIES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

run_check "Git installed" "command -v git &> /dev/null"
run_check "GitHub CLI (gh) installed" "command -v gh &> /dev/null"
run_check "Bash version >= 4.0" "[ ${BASH_VERSINFO[0]} -ge 4 ]"
run_check "curl available" "command -v curl &> /dev/null"
run_check "jq (JSON processor) available" "command -v jq &> /dev/null" "warning"

# Version checks
GIT_VERSION=$(git --version | grep -oP '(?<=version )\d+\.\d+' | head -1)
echo "  Git version: $GIT_VERSION" | tee -a "$CHECKLIST_REPORT"

GH_VERSION=$(gh --version | grep -oP '(?<=gh version )\d+\.\d+' | head -1)
echo "  GitHub CLI version: $GH_VERSION" | tee -a "$CHECKLIST_REPORT"

################################################################################
# SECTION 2: GITHUB AUTHENTICATION
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 2: GITHUB AUTHENTICATION & AUTHORIZATION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

run_check "GitHub CLI authenticated" "gh auth status > /dev/null 2>&1"

# Get authenticated user
AUTHENTICATED_USER=$(gh api user --jq '.login' 2>/dev/null)
if [ ! -z "$AUTHENTICATED_USER" ]; then
    echo "  Authenticated as: $AUTHENTICATED_USER" | tee -a "$CHECKLIST_REPORT"
    run_check "User has admin privileges" "gh api user --jq '.site_admin' | grep -q true"
else
    echo -e "${RED}  ❌ Could not determine authenticated user${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

################################################################################
# SECTION 3: SOURCE ORGANIZATION VALIDATION
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 3: SOURCE ORGANIZATION (GhostAISecurity)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

SOURCE_ORG="GhostAISecurity"
run_check "Source org exists and is accessible" "gh org view $SOURCE_ORG > /dev/null 2>&1"

# Get source org details
SOURCE_ORG_TYPE=$(gh api orgs/$SOURCE_ORG --jq '.type' 2>/dev/null || echo "User")
SOURCE_REPO_COUNT=$(gh repo list $SOURCE_ORG --limit 1000 --jq 'length' 2>/dev/null || echo "0")

echo "  Org type: $SOURCE_ORG_TYPE" | tee -a "$CHECKLIST_REPORT"
echo "  Repository count: $SOURCE_REPO_COUNT" | tee -a "$CHECKLIST_REPORT"

if [ "$SOURCE_REPO_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}  ⚠️  No repositories found in source org${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
fi

# Check for backup directory
run_check "Backup directory exists" "[ -d 'migration-backups-'* ] || [ -f 'backup-manifest.json' ]"

################################################################################
# SECTION 4: TARGET ORGANIZATION VALIDATION
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 4: TARGET ORGANIZATION (Sediba-Ghost)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

TARGET_ORG="Sediba-Ghost"
run_check "Target org exists and is accessible" "gh org view $TARGET_ORG > /dev/null 2>&1"

# Get target org details
TARGET_ORG_TYPE=$(gh api orgs/$TARGET_ORG --jq '.type' 2>/dev/null || echo "User")
TARGET_REPO_COUNT=$(gh repo list $TARGET_ORG --limit 1000 --jq 'length' 2>/dev/null || echo "0")

echo "  Org type: $TARGET_ORG_TYPE" | tee -a "$CHECKLIST_REPORT"
echo "  Current repository count: $TARGET_REPO_COUNT" | tee -a "$CHECKLIST_REPORT"

# Check write permissions
run_check "Can create repos in target org" "gh api /orgs/$TARGET_ORG/repos -X POST -f name='migration-test-$(date +%s)' > /dev/null 2>&1 && gh repo delete $TARGET_ORG/migration-test-* --yes > /dev/null 2>&1"

################################################################################
# SECTION 5: BACKUP VALIDATION
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 5: BACKUP INTEGRITY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

# Find latest backup
LATEST_BACKUP=$(find . -maxdepth 1 -type d -name "migration-backups-*" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

if [ ! -z "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
    echo "  Latest backup: $LATEST_BACKUP" | tee -a "$CHECKLIST_REPORT"
    
    BACKUP_SIZE=$(du -sh "$LATEST_BACKUP" | cut -f1)
    echo "  Backup size: $BACKUP_SIZE" | tee -a "$CHECKLIST_REPORT"
    
    BACKUP_REPO_COUNT=$(find "$LATEST_BACKUP" -maxdepth 1 -name "*.git" -type d | wc -l)
    echo "  Backed up repositories: $BACKUP_REPO_COUNT" | tee -a "$CHECKLIST_REPORT"
    
    if [ "$BACKUP_REPO_COUNT" -eq "$SOURCE_REPO_COUNT" ]; then
        echo -e "  ${GREEN}✅ Backup count matches source${NC}" | tee -a "$CHECKLIST_REPORT"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "  ${YELLOW}⚠️  Backup count ($BACKUP_REPO_COUNT) differs from source ($SOURCE_REPO_COUNT)${NC}" | tee -a "$CHECKLIST_REPORT"
        CHECKS_WARNING=$((CHECKS_WARNING + 1))
    fi
    
    # Check for checksums
    CHECKSUM_COUNT=$(find "$LATEST_BACKUP" -name "*checksums*.txt" | wc -l)
    if [ $CHECKSUM_COUNT -gt 0 ]; then
        echo -e "  ${GREEN}✅ Checksum files found ($CHECKSUM_COUNT)${NC}" | tee -a "$CHECKLIST_REPORT"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo -e "  ${YELLOW}⚠️  No checksum files found${NC}" | tee -a "$CHECKLIST_REPORT"
        CHECKS_WARNING=$((CHECKS_WARNING + 1))
    fi
else
    echo -e "  ${YELLOW}⚠️  No backups found${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
fi

################################################################################
# SECTION 6: NETWORK & API CONNECTIVITY
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 6: NETWORK & API CONNECTIVITY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

run_check "GitHub API is reachable (api.github.com)" "curl -s -o /dev/null -w '%{http_code}' https://api.github.com | grep -q 200"
run_check "GitHub.com is reachable" "curl -s -o /dev/null -w '%{http_code}' https://github.com | grep -q 200"
run_check "SSH key configured (optional)" "[ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]" "warning"

# Rate limit check
RATE_LIMIT=$(gh api rate_limit --jq '.rate.remaining' 2>/dev/null || echo "0")
echo "  GitHub API rate limit remaining: $RATE_LIMIT" | tee -a "$CHECKLIST_REPORT"

if [ "$RATE_LIMIT" -lt 100 ]; then
    echo -e "  ${YELLOW}⚠️  Low rate limit - consider waiting before migration${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
fi

################################################################################
# SECTION 7: REPOSITORY FREEZE STATUS
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 7: REPOSITORY FREEZE STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

FROZEN_REPOS=0
UNFROZEN_REPOS=0

for repo in $(gh repo list $SOURCE_ORG --json name -q '.[].name' 2>/dev/null | head -5); do
    # Check for freeze label
    LABELS=$(gh api repos/$SOURCE_ORG/$repo/labels --jq '.[].name' 2>/dev/null)
    
    if echo "$LABELS" | grep -q "migration-frozen"; then
        FROZEN_REPOS=$((FROZEN_REPOS + 1))
    else
        UNFROZEN_REPOS=$((UNFROZEN_REPOS + 1))
    fi
done

echo "  Checked repositories: $((FROZEN_REPOS + UNFROZEN_REPOS))" | tee -a "$CHECKLIST_REPORT"
echo "  Frozen: $FROZEN_REPOS" | tee -a "$CHECKLIST_REPORT"
echo "  Unfrozen: $UNFROZEN_REPOS" | tee -a "$CHECKLIST_REPORT"

if [ $UNFROZEN_REPOS -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  Some repositories are not marked as frozen${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
fi

################################################################################
# SECTION 8: DISK SPACE & RESOURCES
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 8: DISK SPACE & SYSTEM RESOURCES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')" GB"
echo "  Available disk space: $AVAILABLE_SPACE" | tee -a "$CHECKLIST_REPORT"

AVAILABLE_GB=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
if [ "$AVAILABLE_GB" -lt 50 ]; then
    echo -e "  ${RED}❌ Insufficient disk space (< 50 GB)${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
elif [ "$AVAILABLE_GB" -lt 100 ]; then
    echo -e "  ${YELLOW}⚠️  Low disk space (< 100 GB)${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
else
    echo -e "  ${GREEN}✅ Sufficient disk space${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

AVAILABLE_MEMORY=$(free -g | awk 'NR==2 {print $7}')
echo "  Available memory: ${AVAILABLE_MEMORY} GB" | tee -a "$CHECKLIST_REPORT"

if [ "$AVAILABLE_MEMORY" -lt 4 ]; then
    echo -e "  ${YELLOW}⚠️  Low available memory (< 4 GB)${NC}" | tee -a "$CHECKLIST_REPORT"
    CHECKS_WARNING=$((CHECKS_WARNING + 1))
fi

################################################################################
# SECTION 9: CONFIGURATION FILES
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 9: MIGRATION CONFIGURATION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

run_check "Migration config file exists" "[ -f 'migration-config.json' ] || [ -f '.migration-config' ]" "warning"
run_check "Scripts directory exists" "[ -d 'scripts' ]"
run_check "Documentation exists" "[ -f 'README.md' ] || [ -f 'MIGRATION.md' ]" "warning"

################################################################################
# SECTION 10: FINAL RECOMMENDATIONS
################################################################################
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}SECTION 10: FINAL CHECKLIST SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n" | tee -a "$CHECKLIST_REPORT"

TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))

echo "" | tee -a "$CHECKLIST_REPORT"
echo "╔════════════════════════════════════════════════════════════╗" | tee -a "$CHECKLIST_REPORT"
echo "║               CHECKLIST SUMMARY REPORT                      ║" | tee -a "$CHECKLIST_REPORT"
echo "╠════════════════════════════════════════════════════════════╣" | tee -a "$CHECKLIST_REPORT"
echo "║ Total Checks Performed:        $TOTAL_CHECKS                              ║" | tee -a "$CHECKLIST_REPORT"
echo "║ ✅ Passed:                     $CHECKS_PASSED                              ║" | tee -a "$CHECKLIST_REPORT"
echo "║ ⚠️  Warnings:                  $CHECKS_WARNING                              ║" | tee -a "$CHECKLIST_REPORT"
echo "║ ❌ Failed:                     $CHECKS_FAILED                              ║" | tee -a "$CHECKLIST_REPORT"
echo "╚════════════════════════════════════════════════════════════╝" | tee -a "$CHECKLIST_REPORT"
echo "" | tee -a "$CHECKLIST_REPORT"

# Recommendations
if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "${RED}🚫 MIGRATION NOT READY TO PROCEED${NC}" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
    echo "⚠️  CRITICAL ISSUES FOUND:" | tee -a "$CHECKLIST_REPORT"
    echo "   - $CHECKS_FAILED check(s) failed" | tee -a "$CHECKLIST_REPORT"
    echo "   - Review the failed items above" | tee -a "$CHECKLIST_REPORT"
    echo "   - Resolve issues and run checklist again" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
elif [ $CHECKS_WARNING -gt 0 ]; then
    echo -e "${YELLOW}⚠️  MIGRATION READY WITH CAUTIONS${NC}" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
    echo "ℹ️  WARNINGS TO ADDRESS:" | tee -a "$CHECKLIST_REPORT"
    echo "   - $CHECKS_WARNING warning(s) found" | tee -a "$CHECKLIST_REPORT"
    echo "   - Review warnings above" | tee -a "$CHECKLIST_REPORT"
    echo "   - Proceed with caution or resolve first" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
else
    echo -e "${GREEN}✅ ALL CHECKS PASSED - READY TO MIGRATE!${NC}" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
    echo "🚀 You are clear to proceed with:" | tee -a "$CHECKLIST_REPORT"
    echo "   - bash scripts/05-migrate-repos.sh" | tee -a "$CHECKLIST_REPORT"
    echo "" | tee -a "$CHECKLIST_REPORT"
fi

echo "Report saved to: $CHECKLIST_REPORT" | tee -a "$CHECKLIST_REPORT"
echo ""

# Exit with appropriate code
if [ $CHECKS_FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
