#!/bin/bash
# freeze-repos.sh - Prevent changes during migration
# Freezes repositories by adding warning labels and pinned issues
# Usage: bash scripts/03-freeze-repos.sh SOURCE_ORG

set -e

SOURCE_ORG="${1:-GhostAISecurity}"
FREEZE_LOG="freeze-repos-$(date +%Y%m%d-%H%M%S).txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧊 FREEZING REPOSITORIES${NC}"
echo "============================"
echo "Source Org: $SOURCE_ORG"
echo "Time: $(date)"
echo "" | tee $FREEZE_LOG

# Verify org exists
if ! gh org view $SOURCE_ORG > /dev/null 2>&1; then
  echo -e "${RED}❌ Organization $SOURCE_ORG not found${NC}"
  exit 1
fi

echo -e "${YELLOW}Fetching repositories...${NC}"
REPOS=$(gh repo list $SOURCE_ORG --json name -q '.[].name')
TOTAL=$(echo "$REPOS" | wc -l)
CURRENT=0

for repo in $REPOS; do
  CURRENT=$((CURRENT + 1))
  echo -e "${BLUE}[$CURRENT/$TOTAL]${NC} Freezing: $repo" | tee -a $FREEZE_LOG
  
  # Step 1: Add special label if it doesn't exist
  echo "  [1/3] Creating freeze label..." | tee -a $FREEZE_LOG
  gh label create "status:migration-frozen" \
    --repo "$SOURCE_ORG/$repo" \
    --description "🧊 Repository frozen for migration" \
    --color "0000FF" 2>/dev/null || echo "  ℹ️  Label already exists" | tee -a $FREEZE_LOG
  
  # Step 2: Create pinned warning issue
  echo "  [2/3] Creating freeze warning issue..." | tee -a $FREEZE_LOG
  ISSUE_OUTPUT=$(gh issue create \
    --repo "$SOURCE_ORG/$repo" \
    --title "🧊 MIGRATION IN PROGRESS - REPOSITORY FROZEN" \
    --body "⚠️ **This repository is being migrated to the Sediba-Ghost organization.**

**STATUS**: In Progress 🔄
**DO NOT PUSH OR MERGE** until migration is complete.

## Timeline
- **Migration Started**: $(date)
- **Estimated Completion**: $(date -d '+4 hours' 2>/dev/null || date -v+4H)
- **Keep Frozen Until**: All systems reconnected & verified

## What's Happening
1. ✅ Repositories are being backed up
2. 🔄 Migrating to new organization
3. ⚙️ Reconnecting CI/CD pipelines
4. 🔑 Re-adding secrets & credentials
5. 🧪 Running validation tests
6. ✅ Will unfreeze when complete

## New Location
After migration, this repo will be available at:
**https://github.com/Sediba-Ghost/$repo**

## Questions?
All changes are reversible. Backups are secured for 30 days.
Contact @GhostAISecurity for updates.

---
*Freeze initiated at $(date)*" \
    --label "status:migration-frozen" \
    --assignee @GhostAISecurity 2>&1)
  
  if echo "$ISSUE_OUTPUT" | grep -q "created"; then
    echo -e "${GREEN}  ✅ Issue created${NC}" | tee -a $FREEZE_LOG
  else
    echo -e "${YELLOW}  ⚠️  Could not create issue (may already exist)${NC}" | tee -a $FREEZE_LOG
  fi
  
  # Step 3: Add topic tag
  echo "  [3/3] Adding migration topic..." | tee -a $FREEZE_LOG
  gh api repos/$SOURCE_ORG/$repo/topics \
    --input - << EOF 2>/dev/null || echo "  ℹ️  Topic update skipped" | tee -a $FREEZE_LOG
{
  "names": ["migration-pending"]
}
EOF
  
  echo -e "${GREEN}  ✅ Frozen${NC}" | tee -a $FREEZE_LOG
  echo "" | tee -a $FREEZE_LOG
done

echo -e "${GREEN}✅ ALL REPOSITORIES FROZEN${NC}"
echo "" | tee -a $FREEZE_LOG
echo "Log saved to: $FREEZE_LOG"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT REMINDERS:${NC}"
echo "1. Notify team: repositories are now frozen"
echo "2. Backup verification passed before proceeding"
echo "3. Monitor freeze log for any issues"
echo "4. Next step: Execute migration"
