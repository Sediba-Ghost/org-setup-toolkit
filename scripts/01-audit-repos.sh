#!/bin/bash
################################################################################
# PHASE 1A: PRE-MIGRATION AUDIT & ASSESSMENT
# Purpose: Scan all repos for critical data, dependencies, and configurations
# Safe: Read-only operations only
################################################################################

set -e

ORG="${1:-GhostAISecurity}"
AUDIT_REPORT="migration-audit-$(date +%Y%m%d-%H%M%S).txt"
FAILED_AUDITS=0

echo "🔍 STARTING PRE-MIGRATION AUDIT"
echo "================================" | tee $AUDIT_REPORT
echo "Organization: $ORG" >> $AUDIT_REPORT
echo "Timestamp: $(date)" >> $AUDIT_REPORT
echo "================================" >> $AUDIT_REPORT

# Verify org exists
if ! gh org view $ORG > /dev/null 2>&1; then
  echo "❌ ERROR: Cannot access organization: $ORG"
  exit 1
fi

echo "✅ Organization verified"
echo ""

# Get all repos
REPOS=$(gh repo list $ORG --json name -q '.[].name' 2>/dev/null)
TOTAL_REPOS=$(echo "$REPOS" | wc -l)

echo "📦 Found $TOTAL_REPOS repositories"
echo "" | tee -a $AUDIT_REPORT

# Audit each repo
REPO_NUM=0
for repo in $REPOS; do
  REPO_NUM=$((REPO_NUM + 1))
  echo "[$REPO_NUM/$TOTAL_REPOS] Auditing: $repo" | tee -a $AUDIT_REPORT
  
  # Clone to temp directory
  TEMP_DIR="/tmp/audit-$repo-$$"
  
  if ! git clone --quiet --depth=1 https://github.com/$ORG/$repo.git $TEMP_DIR 2>/dev/null; then
    echo "  ❌ FAILED to clone" | tee -a $AUDIT_REPORT
    FAILED_AUDITS=$((FAILED_AUDITS + 1))
    continue
  fi
  
  cd $TEMP_DIR
  
  # --- SECRETS CHECK ---
  echo "" >> ../$AUDIT_REPORT
  echo "📦 Repository: $repo" >> ../$AUDIT_REPORT
  echo "---" >> ../$AUDIT_REPORT
  echo "🔐 Secrets Check:" >> ../$AUDIT_REPORT
  
  SECRETS_FOUND=0
  
  # Check for .env files
  if [ -f ".env" ] || [ -f ".env.local" ] || [ -f ".env.example" ]; then
    echo "  ⚠️  .env files found (check for hardcoded secrets)" >> ../$AUDIT_REPORT
    SECRETS_FOUND=$((SECRETS_FOUND + 1))
  fi
  
  # Check for .key, .pem files
  if find . -maxdepth 2 -name "*.key" -o -name "*.pem" 2>/dev/null | grep -v node_modules | head -n 5; then
    echo "  ⚠️  Key files found (MUST BE REMOVED)" >> ../$AUDIT_REPORT
    SECRETS_FOUND=$((SECRETS_FOUND + 1))
  fi
  
  # Check for hardcoded secrets in code
  if grep -r "password\|secret\|api.key\|token" --include="*.js" --include="*.py" --include="*.go" --include="*.ts" . 2>/dev/null | grep -i "=\|:\|:" | head -n 3; then
    echo "  ⚠️  Potential hardcoded secrets in code (REVIEW)" >> ../$AUDIT_REPORT
    SECRETS_FOUND=$((SECRETS_FOUND + 1))
  fi
  
  if [ $SECRETS_FOUND -eq 0 ]; then
    echo "  ✅ No obvious secrets detected" >> ../$AUDIT_REPORT
  fi
  
  # --- GITHUB ACTIONS ---
  echo "⚙️  GitHub Actions:" >> ../$AUDIT_REPORT
  
  if [ -d ".github/workflows" ]; then
    WORKFLOW_COUNT=$(ls .github/workflows 2>/dev/null | wc -l)
    echo "  ✅ Found $WORKFLOW_COUNT workflows:" >> ../$AUDIT_REPORT
    ls .github/workflows 2>/dev/null | sed 's/^/    - /' >> ../$AUDIT_REPORT
  else
    echo "  ℹ️  No workflows found" >> ../$AUDIT_REPORT
  fi
  
  # --- DEPLOYMENT CONFIG ---
  echo "🚀 Deployment Platforms:" >> ../$AUDIT_REPORT
  
  DEPLOYMENT_COUNT=0
  
  if [ -f "vercel.json" ]; then
    echo "  ✅ Vercel config found" >> ../$AUDIT_REPORT
    DEPLOYMENT_COUNT=$((DEPLOYMENT_COUNT + 1))
  fi
  
  if [ -f "render.yaml" ]; then
    echo "  ✅ Render config found" >> ../$AUDIT_REPORT
    DEPLOYMENT_COUNT=$((DEPLOYMENT_COUNT + 1))
  fi
  
  if [ -f "netlify.toml" ] || [ -f ".netlify/state.json" ]; then
    echo "  ✅ Netlify config found" >> ../$AUDIT_REPORT
    DEPLOYMENT_COUNT=$((DEPLOYMENT_COUNT + 1))
  fi
  
  if [ -f "Dockerfile" ]; then
    echo "  ✅ Docker config found" >> ../$AUDIT_REPORT
    DEPLOYMENT_COUNT=$((DEPLOYMENT_COUNT + 1))
  fi
  
  if [ $DEPLOYMENT_COUNT -eq 0 ]; then
    echo "  ℹ️  No deployment configs found" >> ../$AUDIT_REPORT
  fi
  
  # --- REPOSITORY STATS ---
  echo "📊 Repository Stats:" >> ../$AUDIT_REPORT
  
  REPO_SIZE=$(du -sh . 2>/dev/null | cut -f1)
  echo "  Size: $REPO_SIZE" >> ../$AUDIT_REPORT
  
  BRANCH_COUNT=$(git branch -a 2>/dev/null | wc -l)
  echo "  Branches: $BRANCH_COUNT" >> ../$AUDIT_REPORT
  
  TAG_COUNT=$(git tag 2>/dev/null | wc -l)
  echo "  Tags: $TAG_COUNT" >> ../$AUDIT_REPORT
  
  COMMIT_COUNT=$(git rev-list --all --count 2>/dev/null)
  echo "  Commits: $COMMIT_COUNT" >> ../$AUDIT_REPORT
  
  # --- DEPENDENCIES ---
  echo "📦 Dependencies:" >> ../$AUDIT_REPORT
  
  if [ -f "package.json" ]; then
    echo "  ✅ Node.js (package.json)" >> ../$AUDIT_REPORT
  fi
  
  if [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
    echo "  ✅ Python detected" >> ../$AUDIT_REPORT
  fi
  
  if [ -f "go.mod" ]; then
    echo "  ✅ Go detected" >> ../$AUDIT_REPORT
  fi
  
  if [ -f "Gemfile" ]; then
    echo "  ✅ Ruby detected" >> ../$AUDIT_REPORT
  fi
  
  # --- WEBHOOKS (via API) ---
  cd - > /dev/null
  
  echo "🔔 Webhooks & Integrations:" >> $AUDIT_REPORT
  
  WEBHOOK_COUNT=$(gh api repos/$ORG/$repo/hooks --paginate -q 'length' 2>/dev/null || echo "0")
  
  if [ "$WEBHOOK_COUNT" -gt 0 ]; then
    echo "  ✅ Found $WEBHOOK_COUNT webhooks:" >> $AUDIT_REPORT
    gh api repos/$ORG/$repo/hooks --paginate -q '.[] | "    - \(.name): \(.url)"' >> $AUDIT_REPORT 2>/dev/null
  else
    echo "  ℹ️  No webhooks found" >> $AUDIT_REPORT
  fi
  
  # Cleanup
  rm -rf $TEMP_DIR
  
  echo "  ✅ Audit complete"
done

# Summary
echo "" | tee -a $AUDIT_REPORT
echo "================================" | tee -a $AUDIT_REPORT
echo "✅ AUDIT SUMMARY" | tee -a $AUDIT_REPORT
echo "================================" | tee -a $AUDIT_REPORT
echo "Total Repos Scanned: $TOTAL_REPOS" | tee -a $AUDIT_REPORT
echo "Failed Audits: $FAILED_AUDITS" | tee -a $AUDIT_REPORT
echo "Success Rate: $(( ((TOTAL_REPOS - FAILED_AUDITS) * 100) / TOTAL_REPOS ))%" | tee -a $AUDIT_REPORT
echo "" | tee -a $AUDIT_REPORT
echo "Report saved: $AUDIT_REPORT" | tee -a $AUDIT_REPORT

exit $FAILED_AUDITS
