# GitHub Issues Management Scripts

This directory contains scripts and data for managing FixerHook project tasks as GitHub Issues.

## Files

| File | Description |
|------|-------------|
| `github-issues.json` | JSON data containing all 85 tasks as issue definitions |
| `create_github_issues.py` | Python script to create issues using GitHub CLI |

## Prerequisites

### 1. Install GitHub CLI

```bash
# macOS
brew install gh

# Or download from https://cli.github.com/
```

### 2. Authenticate

```bash
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

### 3. Navigate to Repository

```bash
cd /path/to/the-fixer-hook
```

## Usage

### Preview Issues (Dry Run)

See what would be created without making changes:

```bash
python scripts/create_github_issues.py --dry-run
```

### Create Labels Only

Create project labels without creating issues:

```bash
python scripts/create_github_issues.py --labels-only
```

### Create Milestones Only

```bash
python scripts/create_github_issues.py --milestones-only
```

### Create All Issues

**⚠️ Warning:** This creates 85 issues!

```bash
python scripts/create_github_issues.py
```

### Create Issues for Specific Milestone

```bash
# v1.1 only (20 issues)
python scripts/create_github_issues.py --milestone "v1.1 - Dynamic Rewards"

# v1.2 only (18 issues)
python scripts/create_github_issues.py --milestone "v1.2 - Tiered System"

# v2.0 only (20 issues)
python scripts/create_github_issues.py --milestone "v2.0 - Cross-Pool Registry"

# v2.1 only (17 issues)
python scripts/create_github_issues.py --milestone "v2.1 - NFT Credentials"
```

### Verbose Output

```bash
python scripts/create_github_issues.py --verbose
```

## Milestones

| Milestone | Issues | Target |
|-----------|--------|--------|
| v1.1 - Dynamic Rewards | 20 | Q1 2026 |
| v1.2 - Tiered System | 18 | Q2 2026 |
| v2.0 - Cross-Pool Registry | 20 | Q3 2026 |
| v2.1 - NFT Credentials | 17 | Q4 2026 |
| **Total** | **75** | |

## Labels Created

| Label | Color | Description |
|-------|-------|-------------|
| `enhancement` | 🔵 Blue | New feature or request |
| `setup` | 🔷 Light Blue | Project setup |
| `core` | 🔴 Red | Core functionality |
| `testing` | 🟢 Green | Testing related |
| `documentation` | 🔵 Blue | Documentation |
| `security` | 🔴 Dark Red | Security related |
| `admin` | 🟡 Yellow | Admin functions |
| `v1.1` | 🔵 Blue | Version 1.1 |
| `v1.2` | 🟣 Purple | Version 1.2 |
| `v2.0` | 🟢 Teal | Version 2.0 |
| `v2.1` | 🟣 Lavender | Version 2.1 |
| `high-priority` | 🔴 Orange | High priority |
| `medium-priority` | 🟡 Yellow | Medium priority |
| `low-priority` | 🟢 Light Green | Low priority |

## Issue Format

Each issue is created with:

- **Title**: `[vX.X] Task description`
- **Body**: Structured with phase, task ID, estimate, and acceptance criteria
- **Labels**: Version + category + priority
- **Milestone**: Linked to appropriate version milestone

Example:

```markdown
## Phase 2: Core Implementation

**Task ID:** 1.2.3
**Estimate:** 2h
**Priority:** HIGH

---

Implement dynamic reward calculation using Solady FixedPointMathLib.

```solidity
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
...
```
```

## Recommended Workflow

1. **First Time Setup**:
   ```bash
   # Create labels and milestones
   python scripts/create_github_issues.py --labels-only
   python scripts/create_github_issues.py --milestones-only
   ```

2. **Sprint Planning**:
   ```bash
   # Create issues for current milestone
   python scripts/create_github_issues.py --milestone "v1.1 - Dynamic Rewards"
   ```

3. **Set Up Project Board**:
   ```bash
   # Create a project board via GitHub UI or CLI
   gh project create --title "FixerHook Development"
   ```

4. **Add Issues to Project**:
   ```bash
   # Link issues to project (via GitHub UI recommended)
   ```

## Troubleshooting

### "Not authenticated"

```bash
gh auth login
```

### "Repository not found"

Make sure you're in the repository directory:

```bash
cd /path/to/the-fixer-hook
gh repo view
```

### Rate Limiting

The script includes a 1-second delay between issue creations. If you hit rate limits:

```bash
# Wait a few minutes and retry specific milestone
python scripts/create_github_issues.py --milestone "v1.1 - Dynamic Rewards"
```

## Modifying Issues

Edit `github-issues.json` to:

- Add new issues
- Modify descriptions
- Change priorities
- Adjust estimates

Then re-run with `--dry-run` to preview changes.
