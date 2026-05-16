#!/bin/bash

################################################################################
# PHASE 6: GITHUB ACTIONS WORKFLOW RESTORATION
# 
# Purpose: Re-enable and verify all GitHub Actions workflows in target repos
# This ensures CI/CD pipelines continue functioning post-migration
#
# Author: Sediba-Ghost Organization
# Date: 2026-05-16
################################################################################

set -euo pipefail

# Configuration
TARGET_ORG="${1:-Sediba-Ghost}"
WORKFLOWS_BACKUP="workflows-backup-$(date +%Y%m%d-%H%M%S)"
WORKFLOWS_LOG="workflow-restoration-$(date +%Y%m%d-%H%M%S).txt"
WORKFLOW_STATUS_REPORT="workflow-status-$(date +%Y%m%d-%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_REPOS=0
REPOS_WITH_WORKFLOWS=0
WORKFLOWS_RESTORED=0
WORKFLOWS_FAILED=0
TOTAL_WORKFLOWS=0

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
  local msg="$1"
  echo -e "${BLUE}[INFO]${NC} $msg" | tee -a "$WORKFLOWS_LOG"
}

log_success() {
  local msg="$1"
  echo -e "${GREEN}[✓]${NC} $msg" | tee -a "$WORKFLOWS_LOG"
}

log_error() {
  local msg="$1"
  echo -e "${RED}[✗]${NC} $msg" | tee -a "$WORKFLOWS_LOG"
}

log_warning() {
  local msg="$1"
  echo -e "${YELLOW}[!]${NC} $msg" | tee -a "$WORKFLOWS_LOG"
}

################################################################################
# INITIALIZATION
################################################################################

initialize_session() {
  echo "⚙️  GITHUB ACTIONS WORKFLOW RESTORATION" | tee "$WORKFLOWS_LOG"
  echo "=======================================" | tee -a "$WORKFLOWS_LOG"
  echo "Target Organization: $TARGET_ORG" | tee -a "$WORKFLOWS_LOG"
  echo "Start Time: $(date)" | tee -a "$WORKFLOWS_LOG"
  echo "Log File: $WORKFLOWS_LOG" | tee -a "$WORKFLOWS_LOG"
  echo "" | tee -a "$WORKFLOWS_LOG"
  
  # Create workflow status JSON
  echo "{" > "$WORKFLOW_STATUS_REPORT"
  echo "  \"migration_timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$WORKFLOW_STATUS_REPORT"
  echo "  \"target_organization\": \"$TARGET_ORG\"," >> "$WORKFLOW_STATUS_REPORT"
  echo "  \"repositories\": [" >> "$WORKFLOW_STATUS_REPORT"
}

################################################################################
# WORKFLOW RESTORATION LOGIC
################################################################################

restore_workflows_for_repo() {
  local repo_name="$1"
  local repo_workflows_count=0
  local repo_enabled_count=0
  
  log_info "Processing repository: $repo_name"
  
  # Get list of all workflows in the repository
  local workflows=$(gh api repos/"$TARGET_ORG"/"$repo_name"/actions/workflows \
    --paginate -q '.[].id' 2>/dev/null || true)
  
  if [ -z "$workflows" ]; then
    log_warning "No workflows found in $repo_name"
    echo "    {" >> "$WORKFLOW_STATUS_REPORT"
    echo "      \"repository\": \"$repo_name\"," >> "$WORKFLOW_STATUS_REPORT"
    echo "      \"workflows_found\": 0," >> "$WORKFLOW_STATUS_REPORT"
    echo "      \"workflows_enabled\": 0," >> "$WORKFLOW_STATUS_REPORT"
    echo "      \"status\": \"no_workflows\"" >> "$WORKFLOW_STATUS_REPORT"
    echo "    }," >> "$WORKFLOW_STATUS_REPORT"
    return 0
  fi
  
  REPOS_WITH_WORKFLOWS=$((REPOS_WITH_WORKFLOWS + 1))
  
  # Process each workflow
  while IFS= read -r workflow_id; do
    if [ -z "$workflow_id" ]; then
      continue
    fi
    
    TOTAL_WORKFLOWS=$((TOTAL_WORKFLOWS + 1))
    repo_workflows_count=$((repo_workflows_count + 1))
    
    # Get workflow details
    local workflow_name=$(gh api repos/"$TARGET_ORG"/"$repo_name"/actions/workflows/"$workflow_id" \
      -q '.name' 2>/dev/null || echo "unknown")
    
    local workflow_state=$(gh api repos/"$TARGET_ORG"/"$repo_name"/actions/workflows/"$workflow_id" \
      -q '.state' 2>/dev/null || echo "unknown")
    
    log_info "  Workflow: $workflow_name (ID: $workflow_id, State: $workflow_state)"
    
    # Enable the workflow if disabled
    if [ "$workflow_state" = "disabled_inactivity" ] || [ "$workflow_state" = "disabled_manually" ]; then
      if gh api -X PUT repos/"$TARGET_ORG"/"$repo_name"/actions/workflows/"$workflow_id"/enable \
        2>/dev/null; then
        log_success "    Re-enabled: $workflow_name"
        repo_enabled_count=$((repo_enabled_count + 1))
        WORKFLOWS_RESTORED=$((WORKFLOWS_RESTORED + 1))
      else
        log_error "    Failed to enable: $workflow_name"
        WORKFLOWS_FAILED=$((WORKFLOWS_FAILED + 1))
      fi
    else
      log_success "    Already enabled: $workflow_name"
      repo_enabled_count=$((repo_enabled_count + 1))
      WORKFLOWS_RESTORED=$((WORKFLOWS_RESTORED + 1))
    fi
  done <<< "$workflows"
  
  # Add to JSON report
  echo "    {" >> "$WORKFLOW_STATUS_REPORT"
  echo "      \"repository\": \"$repo_name\"," >> "$WORKFLOW_STATUS_REPORT"
  echo "      \"workflows_found\": $repo_workflows_count," >> "$WORKFLOW_STATUS_REPORT"
  echo "      \"workflows_enabled\": $repo_enabled_count," >> "$WORKFLOW_STATUS_REPORT"
  echo "      \"status\": \"success\"" >> "$WORKFLOW_STATUS_REPORT"
  echo "    }," >> "$WORKFLOW_STATUS_REPORT"
}

################################################################################
# VERIFY WORKFLOWS
################################################################################

verify_workflows() {
  log_info ""
  log_info "Verifying workflow configurations..."
  
  local repos=$(gh repo list "$TARGET_ORG" --json name -q '.[].name' 2>/dev/null || true)
  
  while IFS= read -r repo_name; do
    if [ -z "$repo_name" ]; then
      continue
    fi
    
    # Check for workflow files in .github/workflows
    local workflow_files=$(gh api repos/"$TARGET_ORG"/"$repo_name"/contents/.github/workflows \
      -q '.[].name' 2>/dev/null || true)
    
    if [ -n "$workflow_files" ]; then
      log_success "Workflow files detected in $repo_name:"
      while IFS= read -r workflow_file; do
        [ -z "$workflow_file" ] && continue
        log_info "  - $workflow_file"
      done <<< "$workflow_files"
    fi
  done <<< "$repos"
}

################################################################################
# WORKFLOW DIAGNOSTICS
################################################################################

check_workflow_secrets() {
  log_info ""
  log_info "Checking workflow secrets configuration..."
  
  local repos=$(gh repo list "$TARGET_ORG" --json name -q '.[].name' 2>/dev/null || true)
  
  while IFS= read -r repo_name; do
    if [ -z "$repo_name" ]; then
      continue
    fi
    
    local secret_count=$(gh api repos/"$TARGET_ORG"/"$repo_name"/actions/secrets \
      --paginate -q 'length' 2>/dev/null || echo "0")
    
    if [ "$secret_count" -gt 0 ]; then
      log_info "$repo_name: $secret_count secret(s) configured"
    else
      log_warning "$repo_name: No secrets configured (may be needed for CI/CD)"
    fi
  done <<< "$repos"
}

################################################################################
# GENERATE DETAILED REPORT
################################################################################

generate_detailed_report() {
  log_info ""
  log_info "Generating detailed workflow restoration report..."
  
  # Close JSON array
  sed -i '$ s/,$//' "$WORKFLOW_STATUS_REPORT"
  echo "" >> "$WORKFLOW_STATUS_REPORT"
  echo "  ]," >> "$WORKFLOW_STATUS_REPORT"
  echo "  \"summary\": {" >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"total_repositories\": $TOTAL_REPOS," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"repositories_with_workflows\": $REPOS_WITH_WORKFLOWS," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"total_workflows\": $TOTAL_WORKFLOWS," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"workflows_restored\": $WORKFLOWS_RESTORED," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"workflows_failed\": $WORKFLOWS_FAILED," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"success_rate\": \"$(( (WORKFLOWS_RESTORED * 100) / (TOTAL_WORKFLOWS + 1) ))%\"," >> "$WORKFLOW_STATUS_REPORT"
  echo "    \"end_time\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >> "$WORKFLOW_STATUS_REPORT"
  echo "  }" >> "$WORKFLOW_STATUS_REPORT"
  echo "}" >> "$WORKFLOW_STATUS_REPORT"
  
  log_success "Report generated: $WORKFLOW_STATUS_REPORT"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  initialize_session
  
  log_info "Fetching repository list from $TARGET_ORG..."
  local repos=$(gh repo list "$TARGET_ORG" --json name -q '.[].name' 2>/dev/null || true)
  
  if [ -z "$repos" ]; then
    log_error "Failed to fetch repositories from $TARGET_ORG"
    exit 1
  fi
  
  # Count and process repositories
  while IFS= read -r repo_name; do
    if [ -z "$repo_name" ]; then
      continue
    fi
    
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    restore_workflows_for_repo "$repo_name"
  done <<< "$repos"
  
  # Verify and check additional configurations
  verify_workflows
  check_workflow_secrets
  
  # Generate report
  generate_detailed_report
  
  # Print summary
  echo ""
  echo "=======================================" | tee -a "$WORKFLOWS_LOG"
  echo "✅ WORKFLOW RESTORATION SUMMARY" | tee -a "$WORKFLOWS_LOG"
  echo "=======================================" | tee -a "$WORKFLOWS_LOG"
  echo "Total Repositories: $TOTAL_REPOS" | tee -a "$WORKFLOWS_LOG"
  echo "Repositories with Workflows: $REPOS_WITH_WORKFLOWS" | tee -a "$WORKFLOWS_LOG"
  echo "Total Workflows Found: $TOTAL_WORKFLOWS" | tee -a "$WORKFLOWS_LOG"
  echo "Workflows Restored: $WORKFLOWS_RESTORED" | tee -a "$WORKFLOWS_LOG"
  echo "Workflows Failed: $WORKFLOWS_FAILED" | tee -a "$WORKFLOWS_LOG"
  
  if [ $TOTAL_WORKFLOWS -gt 0 ]; then
    local success_rate=$(( (WORKFLOWS_RESTORED * 100) / TOTAL_WORKFLOWS ))
    echo "Success Rate: ${success_rate}%" | tee -a "$WORKFLOWS_LOG"
  fi
  
  echo ""
  echo "📊 Detailed Report: $WORKFLOW_STATUS_REPORT" | tee -a "$WORKFLOWS_LOG"
  echo "📝 Full Log: $WORKFLOWS_LOG" | tee -a "$WORKFLOWS_LOG"
  echo "End Time: $(date)" | tee -a "$WORKFLOWS_LOG"
  echo ""
  
  # Exit with appropriate code
  if [ $WORKFLOWS_FAILED -gt 0 ]; then
    log_warning "⚠️  Some workflows failed. Review the logs above."
    exit 1
  else
    log_success "✅ All workflows restored successfully!"
    exit 0
  fi
}

# Run main function
main "$@"
