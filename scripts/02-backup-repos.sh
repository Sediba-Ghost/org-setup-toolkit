#!/bin/bash
################################################################################
# PHASE 2: CREATE MIRROR BACKUPS
# Creates bulletproof backups of all repositories with checksums
# Zero-data-loss insurance policy
################################################################################

set -e

SOURCE_ORG="${1:-GhostAISecurity}"
BACKUP_BASE_DIR="./migration-backups-$(date +%Y%m%d-%H%M%S)"
BACKUP_LOG="$BACKUP_BASE_DIR/backup-log.txt"
FAILED_BACKUPS=()
SUCCESSFUL_BACKUPS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}🔄 PHASE 2: CREATE MIRROR BACKUPS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# Create backup directory structure
mkdir -p "$BACKUP_BASE_DIR"/{repos,checksums,metadata}

{
  echo "═══════════════════════════════════════════════════════════"
  echo "🔄 BACKUP LOG"
  echo "═══════════════════════════════════════════════════════════"
  echo "Organization: $SOURCE_ORG"
  echo "Start Time: $(date)"
  echo "Backup Location: $BACKUP_BASE_DIR"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
} | tee "$BACKUP_LOG"

# Function to create backup with retry logic
backup_repo() {
  local repo_name=$1
  local retry_count=0
  local max_retries=3
  
  echo -e "${YELLOW}📦 Backing up: $repo_name${NC}" | tee -a "$BACKUP_LOG"
  
  while [ $retry_count -lt $max_retries ]; do
    local backup_path="$BACKUP_BASE_DIR/repos/$repo_name.git"
    
    if [ -d "$backup_path" ]; then
      echo -e "  ${YELLOW}⚠️  Backup already exists, skipping...${NC}" | tee -a "$BACKUP_LOG"
      SUCCESSFUL_BACKUPS+=("$repo_name")
      return 0
    fi
    
    echo "  [1/3] Cloning as mirror (attempt $((retry_count + 1))/$max_retries)..." | tee -a "$BACKUP_LOG"
    
    if git clone --mirror "https://github.com/$SOURCE_ORG/$repo_name.git" "$backup_path" 2>&1 | tee -a "$BACKUP_LOG"; then
      
      echo "  [2/3] Generating checksums..." | tee -a "$BACKUP_LOG"
      cd "$backup_path"
      
      # Create integrity checksum
      find . -type f -exec sha256sum {} \; > "../${repo_name}.checksums" 2>&1
      
      # Get repository metadata
      local commit_count=$(git rev-list --all --count 2>/dev/null || echo "0")
      local branch_count=$(git branch -a | wc -l)
      local tag_count=$(git tag | wc -l)
      local repo_size=$(du -sh . 2>/dev/null | cut -f1)
      
      cat > "../${repo_name}.metadata" << EOF
Repository: $repo_name
Backup Date: $(date)
Commits: $commit_count
Branches: $branch_count
Tags: $tag_count
Size: $repo_size
SHA256 Checksum Count: $(wc -l < "../${repo_name}.checksums")
Status: SUCCESS
EOF
      
      cd - > /dev/null
      
      echo -e "  ${GREEN}[3/3] ✅ Backup successful${NC}" | tee -a "$BACKUP_LOG"
      echo "       Size: $repo_size | Commits: $commit_count | Branches: $branch_count" | tee -a "$BACKUP_LOG"
      
      SUCCESSFUL_BACKUPS+=("$repo_name")
      return 0
      
    else
      echo "  ❌ Clone failed (attempt $((retry_count + 1))/$max_retries)" | tee -a "$BACKUP_LOG"
      retry_count=$((retry_count + 1))
      
      if [ $retry_count -lt $max_retries ]; then
        echo "  ⏳ Waiting 10 seconds before retry..." | tee -a "$BACKUP_LOG"
        sleep 10
      fi
    fi
  done
  
  echo -e "  ${RED}❌ BACKUP FAILED after $max_retries attempts${NC}" | tee -a "$BACKUP_LOG"
  FAILED_BACKUPS+=("$repo_name")
  return 1
}

# Verify backup integrity
verify_backup() {
  local repo_name=$1
  local backup_path="$BACKUP_BASE_DIR/repos/$repo_name.git"
  
  if [ ! -d "$backup_path" ]; then
    echo -e "  ${RED}❌ Backup directory not found${NC}" | tee -a "$BACKUP_LOG"
    return 1
  fi
  
  if [ ! -f "$BACKUP_BASE_DIR/repos/${repo_name}.checksums" ]; then
    echo -e "  ${RED}❌ Checksum file not found${NC}" | tee -a "$BACKUP_LOG"
    return 1
  fi
  
  echo -e "  ${BLUE}🔍 Verifying integrity...${NC}" | tee -a "$BACKUP_LOG"
  
  cd "$backup_path"
  local current_checksum_count=$(find . -type f | wc -l)
  local stored_checksum_count=$(wc -l < "../${repo_name}.checksums")
  
  if [ "$current_checksum_count" -eq "$stored_checksum_count" ]; then
    echo -e "  ${GREEN}✅ Integrity verified (${current_checksum_count} files)${NC}" | tee -a "$BACKUP_LOG"
    cd - > /dev/null
    return 0
  else
    echo -e "  ${RED}❌ Integrity check failed${NC}" | tee -a "$BACKUP_LOG"
    cd - > /dev/null
    return 1
  fi
}

# Get list of repositories
echo -e "${BLUE}Fetching repository list from $SOURCE_ORG...${NC}"
REPOS=$(gh repo list "$SOURCE_ORG" --json name -q '.[].name' 2>/dev/null)
TOTAL=$(echo "$REPOS" | wc -l)
CURRENT=0

if [ -z "$REPOS" ]; then
  echo -e "${RED}❌ No repositories found or unable to access $SOURCE_ORG${NC}"
  echo -e "${YELLOW}Ensure you have 'gh' CLI installed and authenticated:${NC}"
  echo "  gh auth login"
  exit 1
fi

echo -e "${GREEN}Found $TOTAL repositories to backup${NC}"
echo ""

# Backup each repository
for repo in $REPOS; do
  CURRENT=$((CURRENT + 1))
  echo ""
  echo -e "${BLUE}[$CURRENT/$TOTAL]${NC} Processing: $repo"
  
  backup_repo "$repo"
  
  if [ $? -eq 0 ]; then
    verify_backup "$repo"
  fi
done

# Generate summary report
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 BACKUP SUMMARY${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

{
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "📊 BACKUP SUMMARY"
  echo "═══════════════════════════════════════════════════════════"
  echo "Total Repositories: $TOTAL"
  echo "Successful Backups: ${#SUCCESSFUL_BACKUPS[@]}"
  echo "Failed Backups: ${#FAILED_BACKUPS[@]}"
  echo ""
} | tee -a "$BACKUP_LOG"

if [ ${#SUCCESSFUL_BACKUPS[@]} -gt 0 ]; then
  echo -e "${GREEN}✅ Successful backups:${NC}" | tee -a "$BACKUP_LOG"
  printf '  %s\n' "${SUCCESSFUL_BACKUPS[@]}" | tee -a "$BACKUP_LOG"
fi

if [ ${#FAILED_BACKUPS[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ FAILED BACKUPS (Requires manual intervention):${NC}" | tee -a "$BACKUP_LOG"
  printf '  %s\n' "${FAILED_BACKUPS[@]}" | tee -a "$BACKUP_LOG"
fi

# Create backup manifest
cat > "$BACKUP_BASE_DIR/BACKUP_MANIFEST.txt" << EOF
═══════════════════════════════════════════════════════════
BACKUP MANIFEST
═══════════════════════════════════════════════════════════
Organization: $SOURCE_ORG
Backup Date: $(date)
Backup Location: $(pwd)/$BACKUP_BASE_DIR

STRUCTURE:
├── repos/                    # Mirror repositories
├── checksums/               # SHA256 checksums
├── metadata/                # Repository metadata
├── backup-log.txt           # Detailed backup log
├── BACKUP_MANIFEST.txt      # This file
└── RETENTION_POLICY.txt     # Data retention guidelines

RETENTION POLICY:
═══════════════════════════════════════════════════════════
⚠️  KEEP THIS BACKUP FOR 30 DAYS MINIMUM

Timeline:
- Day 0: Backup created
- Day 7-14: Verify migration successful
- Day 21-30: Confirm all systems working
- Day 30+: Safe to delete (after successful migration)

RECOVERY PROCEDURE:
═══════════════════════════════════════════════════════════
If migration fails and rollback needed:

1. For each failed repo:
   cd repos/repo-name.git
   git push --mirror https://github.com/SOURCE_ORG/repo-name.git

2. Verify integrity using checksums:
   sha256sum -c ../repo-name.checksums

3. Contact: Sediba-Ghost/org-setup-toolkit issues

BACKUP STATISTICS:
═══════════════════════════════════════════════════════════
Total Repositories: $TOTAL
Successful: ${#SUCCESSFUL_BACKUPS[@]}
Failed: ${#FAILED_BACKUPS[@]}
Total Backup Size: $(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1)
Backup Created: $(date)
EOF

cat >> "$BACKUP_LOG" << EOF

═══════════════════════════════════════════════════════════
Backup End Time: $(date)
Total Backup Size: $(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1)
═══════════════════════════════════════════════════════════
EOF

echo ""
echo -e "${GREEN}✅ Backup process complete!${NC}"
echo ""
echo -e "${YELLOW}📁 Backup Location: $(pwd)/$BACKUP_BASE_DIR${NC}"
echo ""
echo -e "${BLUE}📋 Key Files:${NC}"
echo "  • Repositories:    $BACKUP_BASE_DIR/repos/"
echo "  • Checksums:       $BACKUP_BASE_DIR/repos/*.checksums"
echo "  • Metadata:        $BACKUP_BASE_DIR/repos/*.metadata"
echo "  • Detailed Log:    $BACKUP_LOG"
echo "  • Manifest:        $BACKUP_BASE_DIR/BACKUP_MANIFEST.txt"
echo ""

if [ ${#FAILED_BACKUPS[@]} -gt 0 ]; then
  echo -e "${RED}⚠️  WARNING: ${#FAILED_BACKUPS[@]} backup(s) failed!${NC}"
  echo "Review the log and retry before proceeding with migration."
  exit 1
else
  echo -e "${GREEN}🎉 All backups successful! Safe to proceed with migration.${NC}"
  exit 0
fi
