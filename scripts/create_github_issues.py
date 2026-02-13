#!/usr/bin/env python3
"""
GitHub Issues Creator for FixerHook Project
============================================

Creates GitHub issues from a JSON configuration file using the GitHub CLI (gh).

Prerequisites:
    1. GitHub CLI installed: https://cli.github.com/
    2. Authenticated: `gh auth login`
    3. JSON issues file: scripts/github-issues.json

Usage:
    python scripts/create_github_issues.py [options]

Options:
    --dry-run       Preview issues without creating them
    --milestone     Only create issues for a specific milestone
    --labels-only   Only create labels, don't create issues
    --verbose       Show detailed output
"""

import json
import subprocess
import sys
import argparse
import time
from pathlib import Path
from typing import Optional


# Configuration
ISSUES_FILE = Path(__file__).parent / "github-issues.json"
RATE_LIMIT_DELAY = 1.0  # seconds between API calls


# Label definitions with colors
LABEL_DEFINITIONS = {
    "enhancement": {"color": "a2eeef", "description": "New feature or request"},
    "setup": {"color": "c5def5", "description": "Project setup and configuration"},
    "core": {"color": "d73a4a", "description": "Core contract functionality"},
    "testing": {"color": "0e8a16", "description": "Testing related"},
    "documentation": {"color": "0075ca", "description": "Documentation improvements"},
    "security": {"color": "b60205", "description": "Security related"},
    "admin": {"color": "fbca04", "description": "Admin/governance functions"},
    "v1.1": {"color": "1d76db", "description": "Version 1.1 - Dynamic Rewards"},
    "v1.2": {"color": "5319e7", "description": "Version 1.2 - Tiered System"},
    "v2.0": {"color": "006b75", "description": "Version 2.0 - Cross-Pool Registry"},
    "v2.1": {"color": "b4a7d6", "description": "Version 2.1 - NFT Credentials"},
    "high-priority": {"color": "d93f0b", "description": "High priority task"},
    "medium-priority": {"color": "fbca04", "description": "Medium priority task"},
    "low-priority": {"color": "c2e0c6", "description": "Low priority task"},
}


def run_gh_command(args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a GitHub CLI command."""
    cmd = ["gh"] + args
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def check_gh_installed() -> bool:
    """Check if GitHub CLI is installed and authenticated."""
    try:
        result = run_gh_command(["auth", "status"], check=False)
        return result.returncode == 0
    except FileNotFoundError:
        return False


def get_repo_info() -> tuple[str, str]:
    """Get the current repository owner and name."""
    result = run_gh_command(["repo", "view", "--json", "owner,name"])
    data = json.loads(result.stdout)
    return data["owner"]["login"], data["name"]


def create_label(name: str, color: str, description: str, dry_run: bool = False) -> bool:
    """Create a GitHub label."""
    if dry_run:
        print(f"  [DRY RUN] Would create label: {name} (#{color})")
        return True
    
    try:
        run_gh_command([
            "label", "create", name,
            "--color", color,
            "--description", description,
            "--force"  # Update if exists
        ])
        print(f"  ✓ Created label: {name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  ✗ Failed to create label {name}: {e.stderr}")
        return False


def create_milestone(title: str, description: str = "", dry_run: bool = False) -> bool:
    """Create a GitHub milestone."""
    if dry_run:
        print(f"  [DRY RUN] Would create milestone: {title}")
        return True
    
    try:
        # Check if milestone exists
        result = run_gh_command(["api", "repos/{owner}/{repo}/milestones", "--jq", ".[].title"], check=False)
        existing = result.stdout.strip().split("\n") if result.stdout else []
        
        if title in existing:
            print(f"  ○ Milestone already exists: {title}")
            return True
        
        run_gh_command([
            "api", "repos/{owner}/{repo}/milestones",
            "-X", "POST",
            "-f", f"title={title}",
            "-f", f"description={description}"
        ])
        print(f"  ✓ Created milestone: {title}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  ✗ Failed to create milestone {title}: {e.stderr}")
        return False


def create_issue(issue: dict, dry_run: bool = False, verbose: bool = False) -> bool:
    """Create a single GitHub issue."""
    title = issue["title"]
    body = issue["body"]
    labels = issue.get("labels", [])
    milestone = issue.get("milestone", "")
    
    # Add priority label
    priority = issue.get("priority", "medium")
    labels.append(f"{priority}-priority")
    
    # Format body with metadata
    full_body = f"""## {issue.get('phase', 'Task')}

**Task ID:** {issue['id']}
**Estimate:** {issue.get('estimate', 'TBD')}
**Priority:** {priority.upper()}

---

{body}
"""
    
    if dry_run:
        print(f"\n  [DRY RUN] Would create issue:")
        print(f"    Title: {title}")
        print(f"    Labels: {', '.join(labels)}")
        print(f"    Milestone: {milestone}")
        if verbose:
            print(f"    Body:\n{full_body[:200]}...")
        return True
    
    try:
        cmd = [
            "issue", "create",
            "--title", title,
            "--body", full_body
        ]
        
        # Add labels
        for label in labels:
            cmd.extend(["--label", label])
        
        # Add milestone if specified
        if milestone:
            cmd.extend(["--milestone", milestone])
        
        result = run_gh_command(cmd)
        issue_url = result.stdout.strip()
        print(f"  ✓ Created: {title}")
        if verbose:
            print(f"    URL: {issue_url}")
        
        time.sleep(RATE_LIMIT_DELAY)  # Rate limiting
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"  ✗ Failed to create issue: {title}")
        print(f"    Error: {e.stderr}")
        return False


def load_issues(filepath: Path) -> dict:
    """Load issues from JSON file."""
    with open(filepath) as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser(
        description="Create GitHub issues from JSON configuration"
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Preview issues without creating them"
    )
    parser.add_argument(
        "--milestone", "-m",
        type=str,
        help="Only create issues for specific milestone"
    )
    parser.add_argument(
        "--labels-only",
        action="store_true",
        help="Only create labels, don't create issues"
    )
    parser.add_argument(
        "--milestones-only",
        action="store_true",
        help="Only create milestones, don't create issues"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed output"
    )
    parser.add_argument(
        "--file", "-f",
        type=Path,
        default=ISSUES_FILE,
        help="Path to issues JSON file"
    )
    
    args = parser.parse_args()
    
    # Check prerequisites
    print("🔍 Checking prerequisites...")
    
    if not check_gh_installed():
        print("❌ GitHub CLI not installed or not authenticated.")
        print("   Install: https://cli.github.com/")
        print("   Then run: gh auth login")
        sys.exit(1)
    print("  ✓ GitHub CLI authenticated")
    
    if not args.file.exists():
        print(f"❌ Issues file not found: {args.file}")
        sys.exit(1)
    print(f"  ✓ Issues file found: {args.file}")
    
    # Get repo info
    try:
        owner, repo = get_repo_info()
        print(f"  ✓ Repository: {owner}/{repo}")
    except Exception as e:
        print(f"❌ Could not get repository info: {e}")
        sys.exit(1)
    
    # Load issues
    print("\n📖 Loading issues...")
    data = load_issues(args.file)
    issues = data.get("issues", [])
    milestones = data.get("metadata", {}).get("milestones", [])
    
    print(f"  Found {len(issues)} issues")
    print(f"  Found {len(milestones)} milestones")
    
    if args.dry_run:
        print("\n⚠️  DRY RUN MODE - No changes will be made\n")
    
    # Create labels
    print("\n🏷️  Creating labels...")
    for label_name, label_config in LABEL_DEFINITIONS.items():
        create_label(
            label_name,
            label_config["color"],
            label_config["description"],
            dry_run=args.dry_run
        )
    
    if args.labels_only:
        print("\n✅ Labels created. Exiting (--labels-only mode).")
        return
    
    # Create milestones
    print("\n🎯 Creating milestones...")
    for milestone in milestones:
        create_milestone(
            milestone["title"],
            f"Target: {milestone.get('due', 'TBD')}",
            dry_run=args.dry_run
        )
    
    if args.milestones_only:
        print("\n✅ Milestones created. Exiting (--milestones-only mode).")
        return
    
    # Filter issues by milestone if specified
    if args.milestone:
        issues = [i for i in issues if i.get("milestone") == args.milestone]
        print(f"\n📝 Creating {len(issues)} issues for milestone: {args.milestone}")
    else:
        print(f"\n📝 Creating {len(issues)} issues...")
    
    # Create issues
    success_count = 0
    fail_count = 0
    
    for issue in issues:
        if create_issue(issue, dry_run=args.dry_run, verbose=args.verbose):
            success_count += 1
        else:
            fail_count += 1
    
    # Summary
    print("\n" + "="*50)
    print("📊 Summary:")
    print(f"   ✓ Created: {success_count} issues")
    if fail_count:
        print(f"   ✗ Failed: {fail_count} issues")
    
    if args.dry_run:
        print("\n💡 Run without --dry-run to create issues.")


if __name__ == "__main__":
    main()
