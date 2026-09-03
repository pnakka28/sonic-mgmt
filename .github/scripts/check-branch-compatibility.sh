#!/usr/bin/env bash

set -euo pipefail

master_ref=${1:?Usage: check-branch-compatibility.sh <master-ref> [feature-ref] [feature-label]}
feature_ref=${2:-HEAD}
feature_label=${3:-$feature_ref}

write_summary() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"
    fi
}

git rev-parse --verify "${master_ref}^{commit}" >/dev/null
git rev-parse --verify "${feature_ref}^{commit}" >/dev/null

if ! merge_base=$(git merge-base "$master_ref" "$feature_ref"); then
    write_summary \
        "## ❌ \`${feature_label}\` cannot be compared with master" \
        "" \
        "The branch and master do not share any history."
    echo "::error title=Branch compatibility check failed::${feature_label} and master do not share any history"
    exit 1
fi

mapfile -d '' python_files < <(
    git diff --name-only --diff-filter=ACMR -z "$merge_base" "$feature_ref" -- '*.py'
)

if ! git merge --no-commit --no-ff "$master_ref"; then
    mapfile -t conflicts < <(git diff --name-only --diff-filter=U)
    write_summary \
        "## ❌ \`${feature_label}\` conflicts with master" \
        "" \
        "Update the feature branch with the latest master and resolve:"
    for conflict in "${conflicts[@]}"; do
        write_summary "- \`${conflict}\`"
    done
    echo "::error title=Merge conflict with master::Update ${feature_label} with master and resolve the conflicts"
    exit 1
fi

if ((${#python_files[@]} > 0)); then
    if ! python3 - "${python_files[@]}" <<'PY'
import ast
import pathlib
import sys

for filename in sys.argv[1:]:
    path = pathlib.Path(filename)
    try:
        ast.parse(path.read_text(encoding="utf-8"), filename=filename)
    except (SyntaxError, UnicodeError) as error:
        print(f"{filename}: {error}", file=sys.stderr)
        raise SystemExit(1) from error
PY
    then
        write_summary \
            "## ❌ \`${feature_label}\` has invalid Python after merging master" \
            "" \
            "Update the feature branch with master and fix the syntax error shown in the job log."
        echo "::error title=Python syntax check failed::${feature_label} is not valid after merging master"
        exit 1
    fi
fi

write_summary \
    "## ✅ \`${feature_label}\` is compatible with master" \
    "" \
    "Master merges cleanly and changed Python files remain syntactically valid."
