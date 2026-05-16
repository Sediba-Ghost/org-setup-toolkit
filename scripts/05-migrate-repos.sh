#!/bin/bash

################################################################################
# 🚀 PHASE 5: CONTROLLED MIRROR MIGRATION
# Zero-Data-Loss Enterprise-Grade Repository Migration
# 
# Purpose: Migrate all repositories from source org to target org using
#          mirror cloning to preserve ALL history, branches, tags, and commits
#
# Usage: bash scripts/05-migrate-repos.sh [SOURCE_ORG] [TARGET_ORG]
################################################################################

set -euo pipefail

# Configuration
SOURCE_ORG="${1:-GhostAISecurity}"
TARGET_ORG="${2:-Sediba-Ghost}"
MIGRATION_LOG="logs/migration-$(date +%Y%m%d-%H%M%S).txt"
MIGRATION_MANIFEST="logs/migration-manifest-$(date +%Y%m%d-%H%M%S).json"
FAILED_REPOS=()
SUCCESSFUL_REPOS=()
SKIPPED_REPOS=()

# Create logs directory
mkdir -p logs

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${timestamp} [${level}] ${message}" | tee -a "$MIGRATION_LOG"
}

# Banner
print_banner() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         🚀 ENTERPRISE MIGRATION PROTOCOL - PHASE 5             ║"
  echo "║              Mirror-Based Repository Migration                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}

# Initialize migration log
init_log() {
  cat > "$MIGRATION_LOG" << EOF
================================================================================
🚀 ENTERPRISE REPOSITORY MIGRATION LOG
================================================================================
Start Time: $(date)
Source Organization: $SOURCE_ORG
Target Organization: $TARGET_ORG
Migration Method: Mirror Clone (Zero-Data-Loss)
================================================================================

EOF
  log "INFO" "Migration log initialized: $MIGRATION_LOG"
}

# Verify source organization
verify_source_org() {
  log "INFO" "Verifying source organization: $SOURCE_ORG"
  
  if gh org view "$SOURCE_ORG" > /dev/null 2>&1; then
    log "INFO" "✅ Source organization verified"
    return 0
  else
    log "ERROR" "❌ Cannot access source organization: $SOURCE_ORG"
    return 1
  fi
}

# Verify target organization
verify_target_org() {
  log "INFO" "Verifying target organization: $TARGET_ORG"
  
  if gh org view "$TARGET_ORG" > /dev/null 2>&1; then
    log "INFO" "✅ Target organization verified"
    return 0
  else
    log "ERROR" "❌ Cannot access target organization: $TARGET_ORG"
    return 1
  fi
}

# Get list of repositories
get_repositories() {
  log "INFO" "Fetching repository list from $SOURCE_ORG..."
  
  local repos=$(gh repo list "$SOURCE_ORG" --json name,description,isPrivate,isArchived -q '.[].name' 2>/dev/null)
  
  if [ -z "$repos" ]; then
    log "WARN" "No repositories found in $SOURCE_ORG"
    return 1
  fi
  
  log "INFO" "Found repositories: $(echo "$repos" | wc -l)"
  echo "$repos"
}

# Create target repository
create_target_repo() {
  local repo_name=$1
  
  log "INFO" "Creating target repository: $TARGET_ORG/$repo_name"
  
  # Check if repo already exists
  if gh repo view "$TARGET_ORG/$repo_name" > /dev/null 2>&1; then
    log "WARN" "Repository already exists: $TARGET_ORG/$repo_name (skipping creation)"
    return 0
  fi
  
  # Create bare repository without initialization
  if gh repo create "$TARGET_ORG/$repo_name" \
    --public \
    --description "Migrated from $SOURCE_ORG/$repo_name" \
    --disable-wiki \
    --disable-issues \
    --disable-projects 2>&1 | tee -a "$MIGRATION_LOG"; then
    log "INFO" "✅ Target repository created: $TARGET_ORG/$repo_name"
    return 0
  else
    log "ERROR" "❌ Failed to create repository: $TARGET_ORG/$repo_name"
    return 1
  fi
}

# Migrate repository using mirror clone
migrate_single_repo() {
  local repo_name=$1
  local retry_count=0
  local max_retries=3
  local source_url="https://github.com/$SOURCE_ORG/$repo_name.git"
  local target_url="https://github.com/$TARGET_ORG/$repo_name.git"
  
  log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "INFO" "🔄 Starting migration for: $repo_name"
  log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  while [ $retry_count -lt $max_retries ]; do
    local temp_dir="/tmp/migrate-$repo_name-$$-$retry_count"
    
    log "INFO" "[Attempt $((retry_count + 1))/$max_retries]"
    
    # Step 1: Create target repository
    log "INFO" "  [1/5] Creating target repository..."
    if ! create_target_repo "$repo_name"; then
      log "ERROR" "  Failed to create target repository (attempt $((retry_count + 1)))"
      retry_count=$((retry_count + 1))
      sleep 5
      continue
    fi
    
    # Step 2: Mirror clone source repository
    log "INFO" "  [2/5] Mirror cloning source repository..."
    if ! git clone --mirror "$source_url" "$temp_dir" 2>&1 | tee -a "$MIGRATION_LOG"; then
      log "WARN" "  Clone failed (attempt $((retry_count + 1))/$max_retries)"
      rm -rf "$temp_dir"
      retry_count=$((retry_count + 1))
      sleep 5
      continue
    fi
    
    # Get source repository statistics
    cd "$temp_dir" || exit 1
    local source_commits=$(git rev-list --all --count 2>/dev/null || echo "0")
    local source_branches=$(git branch -r | wc -l)
    local source_tags=$(git tag | wc -l)
    cd - > /dev/null || exit 1
    
    log "INFO" "  📊 Source Repository Statistics:"
    log "INFO" "     • Commits: $source_commits"
    log "INFO" "     • Branches: $source_branches"
    log "INFO" "     • Tags: $source_tags"
    
    # Step 3: Push full mirror to target
    log "INFO" "  [3/5] Pushing full mirror history to target..."
    cd "$temp_dir" || exit 1
    if ! git push --mirror "$target_url" 2>&1 | tee -a "$MIGRATION_LOG"; then
      log "WARN" "  Push failed (attempt $((retry_count + 1))/$max_retries)"
      cd - > /dev/null || exit 1
      rm -rf "$temp_dir"
      retry_count=$((retry_count + 1))
      sleep 5
      continue
    fi
    cd - > /dev/null || exit 1
    
    # Step 4: Verify target repository
    log "INFO" "  [4/5] Verifying target repository integrity..."
    local target_commits=$(git rev-list --all --count "https://github.com/$TARGET_ORG/$repo_name.git" 2>/dev/null || echo "0")
    local target_branches=$(git branch -r -l "https://github.com/$TARGET_ORG/$repo_name.git" 2>/dev/null | wc -l || echo "0")
    local target_tags=$(git ls-remote --tags "https://github.com/$TARGET_ORG/$repo_name.git" 2>/dev/null | wc -l || echo "0")
    
    log "INFO" "  📊 Target Repository Statistics:"
    log "INFO" "     • Commits: $target_commits"
    log "INFO" "     • Branches: $target_branches"
    log "INFO" "     • Tags: $target_tags"
    
    # Step 5: Cleanup
    log "INFO" "  [5/5] Cleaning up temporary files..."
    rm -rf "$temp_dir"
    
    # Verify migration success
    if [ "$target_commits" -gt 0 ]; then
      log "INFO" "✅ Migration successful: $repo_name"
      log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      SUCCESSFUL_REPOS+=("$repo_name")
      return 0
    else
      log "WARN" "Verification failed - no commits found (attempt $((retry_count + 1))/$max_retries)"
      retry_count=$((retry_count + 1))
      sleep 5
      continue
    fi
  done
  
  log "ERROR" "❌ Migration FAILED after $max_retries attempts: $repo_name"
  log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  FAILED_REPOS+=("$repo_name")
  return 1
}

# Execute migration for all repositories
execute_migration() {
  local repos=$(get_repositories)
  
  if [ -z "$repos" ]; then
    log "ERROR" "No repositories to migrate"
    return 1
  fi
  
  local total=$(echo "$repos" | wc -l)
  local current=0
  
  log "INFO" "Starting migration of $total repositories..."
  echo ""
  
  while IFS= read -r repo; do
    current=$((current + 1))
    
    # Progress indicator
    local percent=$((current * 100 / total))
    echo -ne "${BLUE}[$current/$total] ($percent%)${NC} Migrating: $repo\r"
    
    if migrate_single_repo "$repo"; then
      echo -ne "${GREEN}[$current/$total] (100%)${NC} ✅ $repo${NC}\n"
    else
      echo -ne "${RED}[$current/$total] ($percent%)${NC} ❌ $repo${NC}\n"
    fi
    
  done <<< "$repos"
  
  echo ""
}

# Generate migration manifest
generate_manifest() {
  log "INFO" "Generating migration manifest..."
  
  cat > "$MIGRATION_MANIFEST" << EOF
{
  "migrationMetadata": {
    "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "sourceOrganization": "$SOURCE_ORG",
    "targetOrganization": "$TARGET_ORG",
    "migrationMethod": "mirror-clone",
    "totalRepositories": $((${#SUCCESSFUL_REPOS[@]} + ${#FAILED_REPOS[@]} + ${#SKIPPED_REPOS[@]})),
    "successfulMigrations": ${#SUCCESSFUL_REPOS[@]},
    "failedMigrations": ${#FAILED_REPOS[@]},
    "skippedMigrations": ${#SKIPPED_REPOS[@]}
  },
  "successfulRepositories": [
EOF
  
  for repo in "${SUCCESSFUL_REPOS[@]}"; do
    echo "    \"$repo\"," >> "$MIGRATION_MANIFEST"
  done
  
  # Remove trailing comma from last entry
  sed -i '$ s/,$//' "$MIGRATION_MANIFEST"
  
  cat >> "$MIGRATION_MANIFEST" << EOF
  ],
  "failedRepositories": [
EOF
  
  for repo in "${FAILED_REPOS[@]}"; do
    echo "    \"$repo\"," >> "$MIGRATION_MANIFEST"
  done
  
  sed -i '$ s/,$//' "$MIGRATION_MANIFEST"
  
  cat >> "$MIGRATION_MANIFEST" << EOF
  ],
  "skippedRepositories": [
EOF
  
  for repo in "${SKIPPED_REPOS[@]}"; do
    echo "    \"$repo\"," >> "$MIGRATION_MANIFEST"
  done
  
  sed -i '$ s/,$//' "$MIGRATION_MANIFEST"
  
  cat >> "$MIGRATION_MANIFEST" << EOF
  ],
  "nextSteps": [
    "Review failed repositories and retry migration",
    "Verify all workflows are present in target repositories",
    "Add secrets to target repositories (see Phase 6)",
    "Test CI/CD pipelines",
    "Update deployment configurations",
    "Run validation suite (Phase 8)"
  ]
}
EOF
  
  log "INFO" "Manifest saved: $MIGRATION_MANIFEST"
}

# Print migration summary
print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                   📊 MIGRATION SUMMARY                         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  local total=$((${#SUCCESSFUL_REPOS[@]} + ${#FAILED_REPOS[@]}))
  local success_rate=$((${#SUCCESSFUL_REPOS[@]} * 100 / total))
  
  log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "INFO" "✅ MIGRATION COMPLETE"
  log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "INFO" ""
  log "INFO" "📊 Statistics:"
  log "INFO" "   • Total Repositories: $total"
  log "INFO" "   • Successful: ${#SUCCESSFUL_REPOS[@]}"
  log "INFO" "   • Failed: ${#FAILED_REPOS[@]}"
  log "INFO" "   • Success Rate: $success_rate%"
  log "INFO" ""
  
  if [ ${#SUCCESSFUL_REPOS[@]} -gt 0 ]; then
    log "INFO" "✅ Successfully Migrated:"
    printf '   %s\n' "${SUCCESSFUL_REPOS[@]}" | while read line; do
      log "INFO" "   • $line"
    done
    log "INFO" ""
  fi
  
  if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    log "ERROR" "❌ Failed Migrations (RETRY REQUIRED):"
    printf '   %s\n' "${FAILED_REPOS[@]}" | while read line; do
      log "ERROR" "   • $line"
    done
    log "INFO" ""
    log "INFO" "Retry command:"
    log "INFO" "   bash scripts/05-migrate-repos.sh $SOURCE_ORG $TARGET_ORG"
    log "INFO" ""
  fi
  
  log "INFO" "📁 Artifacts:"
  log "INFO" "   • Migration Log: $MIGRATION_LOG"
  log "INFO" "   • Migration Manifest: $MIGRATION_MANIFEST"
  log "INFO" ""
  log "INFO" "🚀 Next Steps:"
  log "INFO" "   1. Review failed repositories (if any)"
  log "INFO" "   2. Run Phase 6: Restore GitHub Actions Workflows"
  log "INFO" "   3. Run Phase 7: Migrate Secrets"
  log "INFO" "   4. Run Phase 8: Post-Migration Validation"
  log "INFO" "   5. Run Phase 9: Archive Old Repositories"
  log "INFO" ""
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# Main execution
main() {
  print_banner
  
  # Initialize
  init_log
  
  # Pre-flight checks
  log "INFO" "Running pre-flight checks..."
  verify_source_org || exit 1
  verify_target_org || exit 1
  
  log "INFO" "✅ All pre-flight checks passed"
  log "INFO" ""
  
  # Execute migration
  execute_migration
  
  # Generate manifest
  generate_manifest
  
  # Print summary
  print_summary
  
  # Exit with appropriate code
  if [ ${#FAILED_REPOS[@]} -eq 0 ]; then
    log "INFO" "🎉 ALL REPOSITORIES MIGRATED SUCCESSFULLY"
    exit 0
  else
    log "ERROR" "⚠️  SOME REPOSITORIES FAILED - REVIEW AND RETRY"
    exit 1
  fi
}

# Execute main
main "$@"
