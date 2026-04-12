#!/usr/bin/env python3
"""sync-lib.py — idea-factory template-to-downstream sync engine.

Compares template files against downstream GitHub repos and optionally
creates PRs to fix drift. Uses `gh api` for all GitHub operations (no cloning).

Usage (called by sync-downstream.sh):
    python3 scripts/sync-lib.py --mode check --registry downstream-registry.json \
        --manifest sync-manifest.json --templates /path/to/idea-factory
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from difflib import unified_diff
from pathlib import Path


def gh_api(endpoint: str, method: str = "GET", data: dict | None = None) -> dict | None:
    """Call GitHub API via gh CLI."""
    cmd = ["gh", "api", endpoint]
    if method != "GET":
        cmd.extend(["--method", method])
    if data:
        for k, v in data.items():
            cmd.extend(["-f", f"{k}={v}"])
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout) if result.stdout.strip() else {}
    except Exception:
        return None


def fetch_file(org: str, repo: str, path: str) -> tuple[str | None, str | None]:
    """Fetch file content and SHA from GitHub. Returns (content, sha) or (None, None)."""
    data = gh_api(f"repos/{org}/{repo}/contents/{path}?ref=main")
    if not data or "content" not in data:
        return None, None
    try:
        content = base64.b64decode(data["content"]).decode("utf-8")
        return content, data.get("sha")
    except Exception:
        return None, None


def read_local(templates_dir: str, src_path: str) -> str | None:
    """Read a local template file."""
    full_path = Path(templates_dir) / src_path
    if not full_path.exists():
        return None
    return full_path.read_text()


def compute_settings(templates_dir: str, project_type: str) -> str | None:
    """Run merge-settings.sh to generate expected settings.json."""
    script = Path(templates_dir) / "scripts" / "merge-settings.sh"
    if not script.exists():
        return None
    try:
        result = subprocess.run(
            ["bash", str(script), project_type],
            capture_output=True, text=True, timeout=10,
            cwd=templates_dir
        )
        return result.stdout if result.returncode == 0 else None
    except Exception:
        return None


def make_diff(local: str, remote: str, label: str) -> list[str]:
    """Generate unified diff lines."""
    local_lines = local.splitlines(keepends=True)
    remote_lines = remote.splitlines(keepends=True)
    return list(unified_diff(remote_lines, local_lines,
                             fromfile=f"downstream/{label}",
                             tofile=f"template/{label}", lineterm=""))


def normalize(content: str) -> str:
    """Normalize content for comparison (strip trailing whitespace/newlines)."""
    return content.rstrip()


def create_sync_pr(org: str, repo: str, files: list[dict], templates_dir: str):
    """Create a PR in downstream repo with updated files."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    branch_name = f"idea-factory/sync-{today}"

    # Get main branch SHA
    ref_data = gh_api(f"repos/{org}/{repo}/git/refs/heads/main")
    if not ref_data or "object" not in ref_data:
        print(f"  ✗ Cannot get main ref for {repo}", file=sys.stderr)
        return False

    main_sha = ref_data["object"]["sha"]

    # Check if branch exists, delete if so
    existing = gh_api(f"repos/{org}/{repo}/git/refs/heads/{branch_name}")
    if existing and "ref" in existing:
        gh_api(f"repos/{org}/{repo}/git/refs/heads/{branch_name}", method="DELETE")

    # Create branch
    create_result = subprocess.run(
        ["gh", "api", f"repos/{org}/{repo}/git/refs",
         "--method", "POST",
         "-f", f"ref=refs/heads/{branch_name}",
         "-f", f"sha={main_sha}"],
        capture_output=True, text=True, timeout=30
    )
    if create_result.returncode != 0:
        print(f"  ✗ Cannot create branch in {repo}: {create_result.stderr}", file=sys.stderr)
        return False

    # Update each file
    for f in files:
        content_b64 = base64.b64encode(f["content"].encode()).decode()
        update_fields = [
            "-f", f"message=chore: sync {f['path']} from idea-factory template",
            "-f", f"content={content_b64}",
            "-f", f"branch={branch_name}",
        ]
        if f.get("sha"):
            update_fields.extend(["-f", f"sha={f['sha']}"])

        update_result = subprocess.run(
            ["gh", "api", f"repos/{org}/{repo}/contents/{f['path']}",
             "--method", "PUT"] + update_fields,
            capture_output=True, text=True, timeout=30
        )
        if update_result.returncode != 0:
            print(f"  ✗ Cannot update {f['path']} in {repo}: {update_result.stderr}", file=sys.stderr)

    # Update .idea-factory-version
    version_content = json.dumps({
        "version": "v8",
        "synced_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "synced_from": subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, text=True,
            cwd=templates_dir
        ).stdout.strip()[:12]
    }, indent=2, ensure_ascii=False) + "\n"

    ver_b64 = base64.b64encode(version_content.encode()).decode()
    # Check if .idea-factory-version exists
    _, ver_sha = fetch_file(org, repo, ".idea-factory-version")
    ver_fields = [
        "-f", "message=chore: update .idea-factory-version",
        "-f", f"content={ver_b64}",
        "-f", f"branch={branch_name}",
    ]
    if ver_sha:
        ver_fields.extend(["-f", f"sha={ver_sha}"])
    subprocess.run(
        ["gh", "api", f"repos/{org}/{repo}/contents/.idea-factory-version",
         "--method", "PUT"] + ver_fields,
        capture_output=True, text=True, timeout=30
    )

    # Create PR
    file_list = "\n".join(f"- `{f['path']}`" for f in files)
    pr_body = f"""## idea-factory 템플릿 동기화

다음 파일이 idea-factory 최신 템플릿과 다릅니다:

{file_list}

### 변경 이유
idea-factory 템플릿이 업데이트되었으나 이 프로젝트에 반영되지 않았습니다.
자세한 내용: https://github.com/{org}/idea-factory/commits/main

---
🤖 Generated by idea-factory sync-downstream
"""
    pr_result = subprocess.run(
        ["gh", "pr", "create",
         "--repo", f"{org}/{repo}",
         "--head", branch_name,
         "--base", "main",
         "--title", f"chore: idea-factory 템플릿 동기화 ({today})",
         "--body", pr_body,
        ],
        capture_output=True, text=True, timeout=30
    )
    if pr_result.returncode == 0:
        pr_url = pr_result.stdout.strip()
        print(f"  ✓ PR created: {pr_url}")
        return True
    else:
        print(f"  ✗ PR creation failed: {pr_result.stderr}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["check", "apply"], default="check")
    parser.add_argument("--registry", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--templates", required=True)
    parser.add_argument("--repo", default="")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    with open(args.registry) as f:
        registry = json.load(f)
    with open(args.manifest) as f:
        manifest = json.load(f)

    org = registry["org"]
    repos = [r for r in registry["repos"] if r.get("enabled", True)]
    if args.repo:
        repos = [r for r in repos if r["name"] == args.repo]
        if not repos:
            print(f"Repo '{args.repo}' not found in registry")
            return

    managed = manifest.get("managed", [])
    computed = manifest.get("computed", [])

    total_drift = 0
    total_missing = 0
    total_ok = 0
    repo_drifts: dict[str, list[dict]] = {}

    print(f"\n{'='*60}")
    print(f"  idea-factory downstream sync — {args.mode} mode")
    print(f"  {len(repos)} repos × {len(managed) + len(computed)} files")
    print(f"{'='*60}\n")

    for repo_info in repos:
        repo_name = repo_info["name"]
        repo_type = repo_info.get("type", "web-app")
        overrides = repo_info.get("overrides", {})
        drifted_files = []

        print(f"▶ {repo_name} ({repo_type})")

        # Check managed files
        for entry in managed:
            dst = entry["dst"]

            # Skip if repo has override for this file
            if overrides.get(dst) == "customized":
                if args.verbose:
                    print(f"    ⊘ {dst} (customized override)")
                continue

            local_content = read_local(args.templates, entry["src"])
            if local_content is None:
                if args.verbose:
                    print(f"    ? {dst} (template missing: {entry['src']})")
                continue

            remote_content, remote_sha = fetch_file(org, repo_name, dst)

            if remote_content is None:
                print(f"    ✗ {dst} — MISSING in downstream")
                total_missing += 1
                drifted_files.append({
                    "path": dst,
                    "content": local_content,
                    "sha": None,
                    "status": "missing"
                })
            elif normalize(remote_content) != normalize(local_content):
                print(f"    ≠ {dst} — DRIFTED")
                total_drift += 1
                if args.verbose:
                    diff_lines = make_diff(local_content, remote_content, dst)
                    for line in diff_lines[:20]:
                        print(f"      {line}")
                    if len(diff_lines) > 20:
                        print(f"      ... ({len(diff_lines) - 20} more lines)")
                drifted_files.append({
                    "path": dst,
                    "content": local_content,
                    "sha": remote_sha,
                    "status": "drifted"
                })
            else:
                total_ok += 1
                if args.verbose:
                    print(f"    ✓ {dst}")

        # Check computed files (settings.json)
        for entry in computed:
            dst = entry["dst"]
            if overrides.get(dst) == "customized":
                continue

            expected = compute_settings(args.templates, repo_type)
            if expected is None:
                if args.verbose:
                    print(f"    ? {dst} (merge-settings failed)")
                continue

            remote_content, remote_sha = fetch_file(org, repo_name, dst)

            if remote_content is None:
                print(f"    ✗ {dst} — MISSING")
                total_missing += 1
                drifted_files.append({
                    "path": dst,
                    "content": expected,
                    "sha": None,
                    "status": "missing"
                })
            elif normalize(remote_content) != normalize(expected):
                print(f"    ≠ {dst} — DRIFTED (computed)")
                total_drift += 1
                drifted_files.append({
                    "path": dst,
                    "content": expected,
                    "sha": remote_sha,
                    "status": "drifted"
                })
            else:
                total_ok += 1
                if args.verbose:
                    print(f"    ✓ {dst}")

        if drifted_files:
            repo_drifts[repo_name] = drifted_files
        print()

    # Summary
    print(f"{'='*60}")
    print(f"  Summary: {total_ok} ok, {total_drift} drifted, {total_missing} missing")
    print(f"  Repos with drift: {len(repo_drifts)}")
    print(f"{'='*60}\n")

    # Apply mode: create PRs
    if args.mode == "apply" and repo_drifts:
        print("Creating PRs...\n")
        created = 0
        for repo_name, files in repo_drifts.items():
            print(f"▶ {repo_name} ({len(files)} files)")
            if create_sync_pr(org, repo_name, files, args.templates):
                created += 1
        print(f"\n✓ {created}/{len(repo_drifts)} PRs created")
    elif args.mode == "apply" and not repo_drifts:
        print("✓ All repos in sync — no PRs needed")


if __name__ == "__main__":
    main()
