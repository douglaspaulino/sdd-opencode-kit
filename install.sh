#!/usr/bin/env bash
set -euo pipefail

TRACK_STATE=false
TARGET_REPO=""

usage() {
  cat <<'EOF'
Usage: install.sh <target_repo> [--track-state]

Installs the SDD pipeline into the target repository by copying
template/.opencode/ into <target_repo>/.opencode/ (never overwrites
existing files).

Options:
  --track-state  Skip adding .sdd/runs/ to .gitignore (version the state).
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --track-state) TRACK_STATE=true ;;
    --help|-h) usage ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$TARGET_REPO" ]]; then
        TARGET_REPO="$1"
      else
        echo "ERROR: only one target repo path allowed" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$TARGET_REPO" ]]; then
  echo "ERROR: target repo path is required" >&2
  usage
fi

if [[ ! -d "$TARGET_REPO" ]]; then
  echo "ERROR: target repo does not exist: $TARGET_REPO" >&2
  exit 1
fi

TARGET_REPO="$(realpath "$TARGET_REPO")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: template directory not found at $TEMPLATE_DIR" >&2
  exit 1
fi

echo "==> Installing SDD kit into $TARGET_REPO"

COPIED=0
SKIPPED=0

while IFS= read -r -d '' src_file; do
  rel_path="${src_file#$TEMPLATE_DIR/}"
  dst_file="$TARGET_REPO/$rel_path"
  dst_dir="$(dirname "$dst_file")"

  if [[ -f "$dst_file" ]]; then
    echo "  SKIP (already exists): $rel_path"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  mkdir -p "$dst_dir"
  cp "$src_file" "$dst_file"
  COPIED=$((COPIED + 1))
done < <(find "$TEMPLATE_DIR" -type f -print0)

echo "==> Copied $COPIED file(s), skipped $SKIPPED existing file(s)"

if [[ "$TRACK_STATE" == true ]]; then
  echo "==> --track-state: .sdd/runs/ will NOT be added to .gitignore"
else
  GITIGNORE="$TARGET_REPO/.gitignore"
  if ! grep -qxF '.sdd/runs/' "$GITIGNORE" 2>/dev/null; then
    echo '.sdd/runs/' >> "$GITIGNORE"
    echo "==> Added .sdd/runs/ to .gitignore"
  else
    echo "==> .sdd/runs/ already in .gitignore"
  fi
fi

echo ""
echo "Done. Restart opencode in $TARGET_REPO and use /sdd <path>."
