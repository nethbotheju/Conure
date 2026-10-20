#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import itertools
import os
import subprocess
import sys

root = sys.argv[1]
credentials = (
    "CONURE_SIGNING_IDENTITY",
    "CONURE_APPLE_TEAM_ID",
    "CONURE_DEVELOPER_ID_P12_BASE64",
    "CONURE_DEVELOPER_ID_P12_PASSWORD",
    "CONURE_NOTARY_KEY_ID",
    "CONURE_NOTARY_ISSUER_ID",
    "CONURE_NOTARY_PRIVATE_KEY",
)
canary = "test-only-sensitive-value"
count = 0


def check(script, config, expected):
    global count
    result = subprocess.run(
        ["/bin/bash", os.path.join(root, "scripts", script)],
        env={"PATH": os.environ["PATH"], **config},
        capture_output=True, text=True, check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == (0 if expected == "ad-hoc" else 1), (script, result)
    assert expected in output, (script, result)
    assert canary not in output, "credential value leaked"
    count += 1
    return output


for mode in (None, "adhoc", "developer-id"):
    for present in itertools.product((False, True), repeat=len(credentials)):
        config = {name: canary if enabled else "" for name, enabled in zip(credentials, present)}
        if mode is not None:
            config["CONURE_SIGNING_MODE"] = mode
        configured = sum(present)
        if 0 < configured < len(credentials):
            expected = "partial Apple signing configuration"
        elif mode == "developer-id" or configured:
            expected = "are disabled pending validation"
        else:
            expected = "ad-hoc"
        output = check("check-apple-signing.sh", config, expected)
        if expected.startswith("partial"):
            for name, enabled in zip(credentials, present):
                if not enabled:
                    assert name in output, "missing credential name not reported"

check("check-apple-signing.sh", {"CONURE_SIGNING_MODE": ""}, "ad-hoc")
check("check-apple-signing.sh", {"SPARKLE_PRIVATE_KEY": canary}, "ad-hoc")
check("check-apple-signing.sh", {"CONURE_SIGNING_MODE": canary}, "must be adhoc or developer-id")
for script in ("make-app.sh", "make-dmg.sh"):
    check(script, {credentials[0]: canary}, "partial Apple signing configuration")
    check(script, dict.fromkeys(credentials, canary), "are disabled pending validation")
    check(script, {"CONURE_SIGNING_MODE": "developer-id"}, "are disabled pending validation")

print(f"Apple signing policy: {count} checks passed (no Apple credentials used).")
PY
