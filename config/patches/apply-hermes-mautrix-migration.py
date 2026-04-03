from pathlib import Path
import re

ROOT = Path("/home/hermes/hermes-agent")
PATCH_ROOT = Path("/tmp/hermes-patches")


def replace_once(path: Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"could not apply mautrix patch: {description}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_regex_once(path: Path, pattern: str, replacement: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"could not apply mautrix patch: {description}")
    path.write_text(updated, encoding="utf-8")


# Replace upstream Matrix adapter wholesale with the wrapper-managed mautrix version.
(ROOT / "gateway/platforms/matrix.py").write_text(
    (PATCH_ROOT / "templates/hermes-matrix-mautrix.py").read_text(encoding="utf-8"),
    encoding="utf-8",
)

# Update dependency metadata.
pyproject = ROOT / "pyproject.toml"
replace_once(
    pyproject,
    'matrix = ["matrix-nio[e2e]>=0.24.0,<1"]',
    'matrix = ["mautrix>=0.20.8,<1", "python-olm>=3.2.16,<4", "unpaddedbase64>=2.1.0,<3", "base58>=2.1.1,<3"]',
    "pyproject matrix dependency",
)

# Update gateway bootstrap warning text.
run_py = ROOT / "gateway/run.py"
replace_once(
    run_py,
    'logger.warning("Matrix: matrix-nio not installed or credentials not set. Run: pip install \'matrix-nio[e2e]\'")',
    'logger.warning("Matrix: mautrix not installed or credentials not set. Run: pip install \'hermes-agent[matrix]\'")',
    "gateway warning text",
)

# Update user-facing Matrix docs in upstream checkout.
matrix_doc = ROOT / "website/docs/user-guide/messaging/matrix.md"
replace_once(
    matrix_doc,
    "`matrix-nio` Python SDK",
    "`mautrix` Python framework",
    "matrix doc intro sdk wording",
)
replace_once(
    matrix_doc,
    "E2EE requires the `matrix-nio` library with encryption extras and the `libolm` C library:",
    "E2EE requires the `mautrix` Python framework, `python-olm`, and the `libolm` C library:",
    "matrix doc requirements wording",
)
replace_once(
    matrix_doc,
    "# Install matrix-nio with E2EE support\npip install 'matrix-nio[e2e]'\n\n# Or install with hermes extras\npip install 'hermes-agent[matrix]'",
    "# Install with hermes Matrix extras\npip install 'hermes-agent[matrix]'",
    "matrix doc install block",
)
replace_once(
    matrix_doc,
    "- Stores encryption keys in `~/.hermes/matrix/store/`",
    "- Stores encryption keys under `HERMES_HOME` in `platforms/matrix/store/`",
    "matrix doc crypto storage path",
)
replace_once(
    matrix_doc,
    "If `matrix-nio[e2e]` is not installed or `libolm` is missing, the bot falls back to a plain (unencrypted) client automatically. You'll see a warning in the logs.",
    "If Matrix crypto dependencies are missing, the Matrix adapter is unavailable. In encrypted-room deployments, fix the dependency issue before starting Hermes.",
    "matrix doc dependency failure mode",
)
replace_once(
    matrix_doc,
    '### "matrix-nio not installed" error',
    '### "mautrix dependencies not installed" error',
    "matrix doc troubleshooting heading",
)
replace_once(
    matrix_doc,
    '**Cause**: The `matrix-nio` Python package is not installed.',
    '**Cause**: The `mautrix` Python packages are not installed.',
    "matrix doc troubleshooting cause",
)
replace_once(
    matrix_doc,
    "**Fix**: Install it:\n\n```bash\npip install 'matrix-nio[e2e]'\n```\n\nOr with Hermes extras:\n\n```bash\npip install 'hermes-agent[matrix]'\n```",
    "**Fix**: Install the Hermes Matrix extras:\n\n```bash\npip install 'hermes-agent[matrix]'\n```",
    "matrix doc troubleshooting install block",
)
