#!/usr/bin/env bash
# Proves the Going Public gates catch what they're built to catch, and nothing they shouldn't.
#   bash scripts/test-gates.sh            every case
#   bash scripts/test-gates.sh GP2        one gate's cases
# Settings: GATES=<path to public-gates.sh> tests another copy of the gates (CI uses this to run
# the main branch's cases against a pull request's gates, so a weakened gate can't merge).
# REQUIRE_TOOLS=1 fails instead of skipping when gitleaks or zizmor is missing (CI sets it).
#
# Each gate is tested against 15 kinds of planted failure (see docs/BASELINE_RULE.md):
#  1 plain  2 written differently  3 somewhere else  4 hidden in history  5 sneaky edge
#  6 renamed or moved  7 encoding tricks  8 side door  9 many at once  10 blind environment
#  11 deliberately disguised  12 look-alike source  13 drift  14 silenced by settings  15 tampering
# plus look-alikes that must PASS. Planted secrets are generated at run time; none is committed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export GATES="${GATES:-$here/public-gates.sh}"
exec python3 - "$@" <<'PY'
import os, re, shutil, subprocess, sys, tempfile, zipfile, tarfile, io, json, secrets, string
from concurrent.futures import ThreadPoolExecutor

GATES = os.environ["GATES"]
ONLY = set(a.upper() for a in sys.argv[1:])
REQUIRE_TOOLS = os.environ.get("REQUIRE_TOOLS") == "1"
NOREPLY = "1+gate-test@users.noreply.github.com"
PIN = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
SHA_OK = "3d3c42e5aac5ba805825da76410c181273ba90b1"
BASE_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "ZIZMOR_OFFLINE": os.environ.get("ZIZMOR_OFFLINE", "1")}

def rnd(n, alphabet=string.ascii_letters + string.digits):
    return "".join(secrets.choice(alphabet) for _ in range(n))

def gh_token(): return "ghp_" + rnd(36)
def aws_key(): return "AKIA" + rnd(16, string.ascii_uppercase + "234567")
def aws_secret(): return rnd(40, string.ascii_letters + string.digits + "/+")

# --------------------------------------------------------------------------------------------
class Repo:
    def __init__(self, path):
        self.p = path
    def git(self, *a, env=None, ok=False):
        r = subprocess.run(["git", "-C", self.p, *a], capture_output=True, text=True, env={**BASE_ENV, **(env or {})})
        if r.returncode and not ok:
            raise RuntimeError(f"git {' '.join(a)}: {r.stderr.strip()}")
        return r.stdout
    def write(self, rel, data, mode=None):
        full = os.path.join(self.p, rel)
        os.makedirs(os.path.dirname(full) or self.p, exist_ok=True)
        with open(full, "wb") as f:
            f.write(data.encode() if isinstance(data, str) else data)
        if mode: os.chmod(full, mode)
    def commit(self, msg="change", email=None, cemail=None, add=True, force=False):
        if add: self.git("add", "-A", *(["-f", "."] if force else []))
        env = {}
        if email: env.update(GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_EMAIL=cemail or email)
        elif cemail: env.update(GIT_COMMITTER_EMAIL=cemail)
        self.git("commit", "-q", "--allow-empty", "-m", msg, env=env)
    def rm(self, rel):
        self.git("rm", "-q", "-r", rel)

WORKFLOW = f"""name: ci
on:
  pull_request:
permissions: {{}}
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: {PIN}
        with:
          persist-credentials: false
      - run: echo ok
"""
DEPENDABOT = """version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
"""

def clean_repo():
    d = tempfile.mkdtemp(prefix="gate-")
    r = Repo(d)
    r.git("init", "-q", "-b", "main")
    r.git("config", "user.name", "Gate Test"); r.git("config", "user.email", NOREPLY)
    r.write("README.md", "# Test repo\n")
    r.write(".github/workflows/ci.yml", WORKFLOW)
    r.write(".github/dependabot.yml", DEPENDABOT)
    r.write("data.json", '{"ok": true}\n')
    r.commit("clean")
    return r

def run_gates(repo_path, gates, env=None, script=None):
    r = subprocess.run(["bash", script or GATES, *gates], cwd=repo_path, capture_output=True, text=True,
                       env={**BASE_ENV, **(env or {})})
    return r.stdout + r.stderr

def result_of(output, gate):
    m = re.search(rf"^(PASS|FAIL) +{gate} ", output, re.M)
    return m.group(1) if m else "NONE"

# --------------------------------------------------------------------------------------------
CASES = []
def case(gate, kind, what, expect="FAIL", gates=None, mustlist=(), limit=None, needs=None, env=None):
    """expect: FAIL (must catch), PASS (look-alike that must not be flagged), LIMIT (known gap,
    with the control that covers it). gates: which gate lines to judge (default: the gate)."""
    def deco(fn):
        CASES.append(dict(gate=gate, kind=kind, what=what, expect=expect, fn=fn, gates=gates or [gate],
                          mustlist=mustlist, limit=limit, needs=needs, env=env or {}))
        return fn
    return deco

# ---- GP0: can the gates see everything? -------------------------------------------------------
@case("GP0", 10, "a shallow copy (only recent commits)")
def _(r):
    for i in range(3): r.commit(f"c{i}")
    d = tempfile.mkdtemp(prefix="gate-shallow-")
    subprocess.run(["git", "clone", "-q", "--depth", "1", f"file://{r.p}", d + "/s"], env=BASE_ENV, check=True)
    return d + "/s"

@case("GP0", 10, "a submodule that isn't checked out")
def _(r):
    sub = clean_repo()
    r.git("-c", "protocol.file.allow=always", "submodule", "-q", "add", sub.p, "libs/sub")
    r.commit("add submodule")
    r.git("submodule", "-q", "deinit", "-f", "libs/sub")

@case("GP0", 10, "not a git repository at all")
def _(r):
    return tempfile.mkdtemp(prefix="gate-norepo-")

# ---- GP1: commit identity ---------------------------------------------------------------------
@case("GP1", 1, "a commit by a personal email")
def _(r): r.commit(email="someone@example.com")
@case("GP1", 2, "a personal email only as the committer")
def _(r): r.commit(email=NOREPLY, cemail="someone@example.com")
@case("GP1", 3, "a personal email on a branch that isn't checked out")
def _(r):
    r.git("checkout", "-q", "-b", "side"); r.commit(email="someone@example.com"); r.git("checkout", "-q", "main")
@case("GP1", 4, "a personal email only in a tag's tagger")
def _(r): r.git("tag", "-a", "v1", "-m", "release", env={"GIT_COMMITTER_EMAIL": "someone@example.com"})
@case("GP1", 5, "odd capitals in a personal email (Example.COM)")
def _(r): r.commit(email="Someone" + "@Example.COM")
@case("GP1", 6, "a .mailmap that renames a personal email to a noreply one")
def _(r):
    r.commit(email="someone@example.com")
    r.write(".mailmap", f"Gate Test <{NOREPLY}> <someone@example.com>\n"); r.commit()
@case("GP1", 7, "a noreply look-alike with a non-ASCII letter (githսb)")
def _(r): r.commit(email="1+me" + "@users.noreply.githսb.com")
@case("GP1", 8, "a personal email inside a submodule's history")
def _(r):
    sub = clean_repo(); sub.commit(email="someone@example.com")
    r.git("-c", "protocol.file.allow=always", "submodule", "-q", "add", sub.p, "libs/sub"); r.commit("sub")
@case("GP1", 9, "three different personal emails: all three listed",
      mustlist=("a@example.com", "b@example.org", "c@example.org"))
def _(r):
    for e in ("a@example.com", "b@example.org", "c@example.org"): r.commit(email=e)
@case("GP1", 10, "checked from a shallow copy that hides the old commit", gates=["GP0"])
def _(r):
    r.commit(email="someone@example.com")
    for i in range(3): r.commit(f"c{i}")
    d = tempfile.mkdtemp(prefix="gate-shallow-")
    subprocess.run(["git", "clone", "-q", "--depth", "1", f"file://{r.p}", d + "/s"], env=BASE_ENV, check=True)
    return d + "/s"
@case("GP1", 11, "a personal address with a +tag: me+github@example.com")
def _(r): r.commit(email="me+github@example.com")
@case("GP1", 12, "a fake noreply: the GitHub domain with .evil.io added")
def _(r): r.commit(email="1+me" + "@users.noreply.github.com" + ".evil.io")  # built here so no file holds it
@case("GP1", 13, "a personal email from long ago, under 20 newer clean commits")
def _(r):
    r.commit(email="someone@example.com")
    for i in range(20): r.commit(f"c{i}")
@case("GP1", 14, "git replace hiding a personal-email commit behind a clean one")
def _(r):
    r.commit(email="someone@example.com"); bad = r.git("rev-parse", "HEAD").strip()
    r.git("reset", "-q", "--hard", "HEAD~1"); r.commit("good"); good = r.git("rev-parse", "HEAD").strip()
    r.git("reset", "-q", "--hard", bad); r.git("replace", bad, good)
@case("GP1", 1, "look-alike: a GitHub noreply address", expect="PASS")
def _(r): r.commit(email="12345+someone@users.noreply.github.com")
@case("GP1", 2, "look-alike: an old-style noreply without the number", expect="PASS")
def _(r): r.commit(email="someone@users.noreply.github.com")
@case("GP1", 3, "look-alike: Dependabot's bot address", expect="PASS")
def _(r): r.commit(email="49699333+dependabot[bot]@users.noreply.github.com")
@case("GP1", 4, "look-alike: Claude's noreply address", expect="PASS")
def _(r): r.commit(email="noreply@anthropic.com")

# ---- GP2: forbidden files -----------------------------------------------------------------------
JKS = b"\xfe\xed\xfe\xed\x00\x00\x00\x02" + os.urandom(64)
def zip_bytes(name, data):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z: z.writestr(name, data)
    return b.getvalue()
@case("GP2", 1, "a tracked local.properties")
def _(r): r.write("local.properties", "sdk.dir=/x\n"); r.commit(force=True)
@case("GP2", 2, "a private SSH key file: id_rsa")
def _(r): r.write("id_rsa", "x\n"); r.commit()
@case("GP2", 2, "a cloud service-account key: service-account.json")
def _(r): r.write("deploy/service-account.json", "{}\n"); r.commit()
@case("GP2", 3, "a keystore deep in a subfolder")
def _(r): r.write("app/src/main/release.keystore", JKS); r.commit()
@case("GP2", 4, "a keystore committed, then deleted (still in history)")
def _(r): r.write("release.jks", JKS); r.commit(); r.rm("release.jks"); r.commit()
@case("GP2", 5, "odd capitals: RELEASE.JKS")
def _(r): r.write("RELEASE.JKS", JKS); r.commit()
@case("GP2", 6, "a keystore renamed to release.dat (found by its content)")
def _(r): r.write("release.dat", JKS); r.commit()
@case("GP2", 6, "a private key pasted into notes.txt")
def _(r):
    pem = "RSA " + "PRIVATE KEY"  # split so this file itself holds no key header
    r.write("notes.txt", f"-----BEGIN {pem}-----\n" + rnd(64) + f"\n-----END {pem}-----\n"); r.commit()
@case("GP2", 7, "a file name with an invisible character: local.properties\\u200b")
def _(r): r.write("local.properties\u200b", "sdk.dir=/x\n"); r.commit()
@case("GP2", 8, "a keystore inside a .zip")
def _(r): r.write("backup.zip", zip_bytes("release.jks", JKS)); r.commit()
@case("GP2", 8, "a keystore inside a .tar.gz")
def _(r):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:gz") as t:
        ti = tarfile.TarInfo("keys/upload.keystore"); ti.size = len(JKS); t.addfile(ti, io.BytesIO(JKS))
    r.write("backup.tar.gz", b.getvalue()); r.commit()
@case("GP2", 8, "a symlink pointing outside the repo")
def _(r): os.symlink("/etc/hostname", os.path.join(r.p, "link")); r.commit()
@case("GP2", 9, "a keystore, google-services.json and .env at once: all listed",
      mustlist=("release.jks", "google-services.json", ".env"))
def _(r):
    r.write("release.jks", JKS); r.write("app/google-services.json", "{}\n"); r.write(".env", "A=1\n"); r.commit()
@case("GP2", 10, "run outside a git repository", gates=["GP0"])
def _(r): return tempfile.mkdtemp(prefix="gate-norepo-")
@case("GP2", 11, "a keystore base64-encoded into a .txt")
def _(r):
    import base64
    r.write("keystore.txt", base64.b64encode(JKS).decode() + "\n"); r.commit()
@case("GP2", 12, "a look-alike name: google-services.json.bak")
def _(r): r.write("app/google-services.json.bak", "{}\n"); r.commit()
@case("GP2", 13, "a generated binary committed: build/Main.class")
def _(r): r.write("build/Main.class", b"\xca\xfe\xba\xbe" + os.urandom(32)); r.commit(force=True)
@case("GP2", 14, "a .gitignore line that un-ignores keystores: !*.jks")
def _(r): r.write(".gitignore", "*.log\n!*.jks\n"); r.commit()
@case("GP2", 1, "look-alike: .env.example", expect="PASS")
def _(r): r.write(".env.example", "API_URL=\n"); r.commit()
@case("GP2", 2, "look-alike: a guide named keystore-guide.md", expect="PASS")
def _(r): r.write("docs/keystore-guide.md", "Keep local.properties and *.jks out of git.\n"); r.commit()
@case("GP2", 3, "look-alike: images and fonts", expect="PASS")
def _(r): r.write("assets/logo.png", b"\x89PNG\r\n\x1a\n" + os.urandom(64)); r.write("assets/a.woff2", b"wOF2" + os.urandom(64)); r.commit()

# ---- GP3: secrets ---------------------------------------------------------------------------------
@case("GP3", 1, "a GitHub token in a file", needs="gitleaks")
def _(r): r.write("config.txt", f'token = "{gh_token()}"\n'); r.commit()
@case("GP3", 2, "a cloud access key and secret", needs="gitleaks")
def _(r): r.write("aws.ini", f"aws_access_key_id = {aws_key()}\naws_secret_access_key = {aws_secret()}\n"); r.commit()
@case("GP3", 3, "a token only on another branch", needs="gitleaks")
def _(r):
    r.git("checkout", "-q", "-b", "side"); r.write("t.txt", f'token = "{gh_token()}"\n'); r.commit(); r.git("checkout", "-q", "main")
@case("GP3", 4, "a token committed, then deleted", needs="gitleaks")
def _(r): r.write("t.txt", f'token = "{gh_token()}"\n'); r.commit(); r.rm("t.txt"); r.commit()
@case("GP3", 5, "a token as a JSON value", needs="gitleaks")
def _(r): r.write("settings.json", json.dumps({"auth": {"token": gh_token()}}) + "\n"); r.commit()
@case("GP3", 6, "a token in a notebook's saved output", needs="gitleaks")
def _(r):
    nb = {"cells": [{"cell_type": "code", "source": ["print(t)"], "metadata": {}, "execution_count": 1,
                     "outputs": [{"output_type": "stream", "name": "stdout", "text": [gh_token() + "\n"]}]}],
          "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
    r.write("explore.ipynb", json.dumps(nb)); r.commit()
@case("GP3", 7, "a token base64-encoded", needs="gitleaks")
def _(r):
    import base64
    r.write("blob.txt", "data = " + base64.b64encode(f'token="{gh_token()}"'.encode()).decode() + "\n"); r.commit()
@case("GP3", 8, "a token inside a .zip", needs="gitleaks")
def _(r): r.write("old.zip", zip_bytes("config.txt", f'token = "{gh_token()}"\n')); r.commit()
@case("GP3", 9, "three secrets of different kinds: all listed", needs="gitleaks",
      mustlist=("github-pat", "aws-access-token", "slack-webhook-url"))
def _(r):
    r.write("a.txt", f'token = "{gh_token()}"\n')
    r.write("b.txt", f"key = {aws_key()}\n")
    r.write("c.txt", f"hook = https://hooks.slack.com/services/T{rnd(10, string.ascii_uppercase + string.digits)}/B{rnd(10, string.ascii_uppercase + string.digits)}/{rnd(24)}\n")
    r.commit()
@case("GP3", 10, "gitleaks isn't installed", env={"PATH": "/usr/bin:/bin"})
def _(r): pass
@case("GP3", 11, "a token assembled in code from two pieces", needs="gitleaks", expect="LIMIT",
      limit="No scanner can see a secret that only exists once the code runs. Covered by: secrets live "
            "only in GitHub Actions secrets (item 3), code review, and rotation if one ever leaks.")
def _(r): r.write("auth.js", 'const t = "ghp_" + "' + rnd(36) + '";\n'); r.commit()
@case("GP3", 12, "a key for a service with no dedicated rule (generic api_key)", needs="gitleaks")
def _(r): r.write("client.py", f'API_KEY = "{rnd(20, string.ascii_lowercase)}{rnd(12, string.digits)}{rnd(8, string.ascii_uppercase)}"\n'); r.commit()
@case("GP3", 13, "a scanner older than the minimum version")
def _(r):
    shim = tempfile.mkdtemp(prefix="gate-shim-")
    with open(shim + "/gitleaks", "w") as f: f.write("#!/bin/sh\necho 'v8.21.2'\n")
    os.chmod(shim + "/gitleaks", 0o755)
    return (r.p, {"PATH": shim + ":" + os.environ["PATH"]})
@case("GP3", 14, "a .gitleaksignore that silences findings", needs="gitleaks")
def _(r): r.write(".gitleaksignore", "abc123:config.txt:generic-api-key:1\n"); r.commit()
@case("GP3", 14, "a 'gitleaks:allow' comment silencing a real token", needs="gitleaks")
def _(r): r.write("config.txt", f'token = "{gh_token()}"  # gitleaks:allow\n'); r.commit()
@case("GP3", 1, "look-alike: a placeholder YOUR_TOKEN_HERE", expect="PASS", needs="gitleaks")
def _(r): r.write("README.md", 'Set `token = "YOUR_TOKEN_HERE"` in your environment.\n'); r.commit()
@case("GP3", 2, "look-alike: a token read from the environment", expect="PASS", needs="gitleaks")
def _(r): r.write("deploy.sh", 'curl -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/\n'); r.commit()

# ---- GP4: dangerous workflows -----------------------------------------------------------------------
def wf(on, steps="      - run: echo ok\n", name="w.yml", extra_job=""):
    return (name, f"name: w\non:{on}\npermissions: {{}}\njobs:\n  t:\n    runs-on: ubuntu-latest\n{extra_job}    steps:\n{steps}")
def put(r, pair, base=".github/workflows/"):
    r.write(base + pair[0], pair[1]); r.commit()
@case("GP4", 1, "pull_request_target on its own line")
def _(r): put(r, wf("\n  pull_request_target:\n"))
@case("GP4", 2, "pull_request_target in an inline list")
def _(r): put(r, wf(" [push, pull_request_target]\n"))
@case("GP4", 2, "pull_request_target in braces")
def _(r): put(r, wf(" {pull_request_target: {}}\n"))
@case("GP4", 3, "in a second workflow file among several")
def _(r): put(r, wf("\n  push:\n", name="a.yml")); put(r, wf("\n  pull_request_target:\n", name="b.yml"))
@case("GP4", 4, "the workflow_run trigger")
def _(r): put(r, wf("\n  workflow_run:\n    workflows: [ci]\n"))
@case("GP4", 5, 'in quotes: "pull_request_target"')
def _(r): put(r, wf('\n  "pull_request_target":\n'))
@case("GP4", 6, "a workflow file named .yaml")
def _(r): put(r, wf("\n  pull_request_target:\n", name="w.yaml"))
@case("GP4", 7, "Windows line endings")
def _(r):
    n, t = wf("\n  pull_request_target:\n"); r.write(".github/workflows/" + n, t.replace("\n", "\r\n")); r.commit()
@case("GP4", 8, "outsider text injected into a local composite action")
def _(r):
    r.write(".github/actions/greet/action.yml", 'name: greet\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo "${{ github.event.issue.title }}"\n'); r.commit()
@case("GP4", 9, "two dangerous triggers in two files: both listed", mustlist=("a.yml", "b.yml"))
def _(r): put(r, wf("\n  workflow_run:\n    workflows: [x]\n", name="a.yml")); put(r, wf("\n  pull_request_target:\n", name="b.yml"))
@case("GP4", 10, "a workflow that can't be read (a tab breaks the YAML)")
def _(r): r.write(".github/workflows/w.yml", "on:\n\tpull_request_target:\njobs: {}\n"); r.commit()
@case("GP4", 11, "a trigger hidden behind a YAML alias")
def _(r): r.write(".github/workflows/w.yml", "x: &t pull_request_target\non: [*t]\njobs: {}\n"); r.commit()
@case("GP4", 12, "the issue_comment trigger")
def _(r): put(r, wf("\n  issue_comment:\n"))
@case("GP4", 13, "an issue title pasted into a shell command")
def _(r): put(r, wf("\n  issues:\n", steps='      - run: echo "${{ github.event.issue.title }}"\n'))
@case("GP4", 14, "the gates switched off with continue-on-error")
def _(r): put(r, wf("\n  pull_request:\n", steps="      - run: bash scripts/public-gates.sh\n        continue-on-error: true\n"))
@case("GP4", 14, "the gates skipped by a path filter")
def _(r): put(r, wf("\n  pull_request:\n    paths: ['src/**']\n", steps="      - run: bash scripts/public-gates.sh\n"))
@case("GP4", 1, "look-alike: the trigger named only in a comment", expect="PASS")
def _(r): put(r, wf("\n  pull_request: # never use pull_request_target here\n"))
@case("GP4", 2, "look-alike: a step whose name mentions it", expect="PASS")
def _(r): put(r, wf("\n  pull_request:\n", steps="      - name: Explain why not pull_request_target\n        run: echo ok\n"))
@case("GP4", 3, "look-alike: a safe context (github.sha) in a command", expect="PASS")
def _(r): put(r, wf("\n  pull_request:\n", steps='      - run: echo "${{ github.sha }}"\n'))
@case("GP4", 4, "look-alike: an issue title passed safely through env", expect="PASS")
def _(r): put(r, wf("\n  issues:\n", steps='      - env:\n          TITLE: ${{ github.event.issue.title }}\n        run: echo "$TITLE"\n'))

# ---- GP5: data files --------------------------------------------------------------------------------
@case("GP5", 1, "a JSON file that doesn't parse")
def _(r): r.write("broken.json", '{"a": \n'); r.commit()
@case("GP5", 2, "a trailing comma")
def _(r): r.write("config.json", '{"a": 1,}\n'); r.commit()
@case("GP5", 3, "a broken JSON file deep in a subfolder")
def _(r): r.write("app/src/data/x.json", "{oops}\n"); r.commit()
@case("GP5", 4, "a broken JSON file only in history", expect="LIMIT",
      limit="Only files in the current version can break a build; past versions are kept as they were. "
            "Covered by: this gate runs on every pull request, so a broken file can't reach main.")
def _(r): r.write("old.json", "{oops\n"); r.commit(); r.write("old.json", "{}\n"); r.commit()
@case("GP5", 5, "an empty .json file")
def _(r): r.write("empty.json", ""); r.commit()
@case("GP5", 5, "a byte-order mark at the start")
def _(r): r.write("bom.json", b"\xef\xbb\xbf{}\n"); r.commit()
@case("GP5", 6, "a broken .geojson")
def _(r): r.write("map.geojson", '{"type": }\n'); r.commit()
@case("GP5", 7, "invalid UTF-8 bytes")
def _(r): r.write("bad.json", b'{"name": "\xff\xfe"}\n'); r.commit()
@case("GP5", 8, "a broken notebook (.ipynb)")
def _(r): r.write("n.ipynb", '{"cells": [\n'); r.commit()
@case("GP5", 8, "a broken ```json block in Markdown")
def _(r): r.write("docs/api.md", "Example:\n\n```json\n{\"a\": 1,,}\n```\n"); r.commit()
@case("GP5", 9, "three broken files: all listed", mustlist=("a.json", "b.yml", "c.json"))
def _(r): r.write("a.json", "{"); r.write("b.yml", "a: [1\n"); r.write("c.json", "[1,]"); r.commit()
@case("GP5", 10, "PyYAML can't be loaded")
def _(r):
    shim = tempfile.mkdtemp(prefix="gate-shim-")
    with open(shim + "/yaml.py", "w") as f: f.write("raise ImportError('yaml blocked for this test')\n")
    return (r.p, {"PYTHONPATH": shim})
@case("GP5", 11, "JSON nested 500 levels deep")
def _(r): r.write("deep.json", "[" * 500 + "]" * 500); r.commit()
@case("GP5", 12, "a duplicate key in JSON")
def _(r): r.write("dup.json", '{"debug": false, "debug": true}\n'); r.commit()
@case("GP5", 12, "a duplicate key in YAML")
def _(r): r.write("config.yml", "debug: false\ndebug: true\n"); r.commit()
@case("GP5", 13, "a file that no longer matches its schema")
def _(r):
    r.write("schema/item.schema.json", json.dumps({"type": "object", "required": ["name"], "properties": {"name": {"type": "string"}}}))
    r.write("items/one.json", json.dumps({"$schema": "../schema/item.schema.json", "title": "no name"})); r.commit()
@case("GP5", 14, "a broken file that .gitignore would hide, tracked anyway")
def _(r): r.write(".gitignore", "*.json\n"); r.commit(); r.write("hidden.json", "{"); r.commit(force=True)
@case("GP5", 1, "look-alike: tsconfig.json with comments and a trailing comma", expect="PASS")
def _(r): r.write("tsconfig.json", '{\n  // TypeScript allows this\n  "compilerOptions": {"strict": true,},\n}\n'); r.commit()
@case("GP5", 2, "look-alike: a .jsonc file with comments", expect="PASS")
def _(r): r.write("settings.jsonc", '{ /* comment */ "a": 1 }\n'); r.commit()
@case("GP5", 3, "look-alike: a .json5 file (a different format, not checked)", expect="PASS")
def _(r): r.write("cfg.json5", "{a: 1, // ok in JSON5\n}\n"); r.commit()
@case("GP5", 4, "look-alike: a ```jsonc block with a comment in Markdown", expect="PASS")
def _(r): r.write("docs/x.md", "```jsonc\n{ // fine\n \"a\": 1 }\n```\n"); r.commit()

# ---- GP6: license ------------------------------------------------------------------------------------
MIT = "MIT License\n\nPermission is hereby granted, free of charge, to any person...\n"
@case("GP6", 1, "LICENSE without approval")
def _(r): r.write("LICENSE", MIT); r.commit()
@case("GP6", 2, "COPYING without approval")
def _(r): r.write("COPYING", "GNU GENERAL PUBLIC LICENSE\n"); r.commit()
@case("GP6", 3, "a license file in a subfolder")
def _(r): r.write("docs/LICENSE.md", MIT); r.commit()
@case("GP6", 4, "an empty approval note")
def _(r): r.write("LICENSE", MIT); r.write(".license-approved", ""); r.commit()
@case("GP6", 5, "lower case: license.txt")
def _(r): r.write("license.txt", MIT); r.commit()
@case("GP6", 6, "British spelling and a suffix: LICENCE-MIT")
def _(r): r.write("LICENCE-MIT", MIT); r.commit()
@case("GP6", 7, "license text pasted into the README")
def _(r): r.write("README.md", "# App\n\n" + MIT); r.commit()
@case("GP6", 8, "a license field in package.json")
def _(r): r.write("package.json", '{"name": "x", "license": "MIT"}\n'); r.commit()
@case("GP6", 9, "two license files: both listed", mustlist=("LICENSE", "sub/COPYING"))
def _(r): r.write("LICENSE", MIT); r.write("sub/COPYING", MIT); r.commit()
@case("GP6", 10, "an approval note with no date")
def _(r): r.write("LICENSE", MIT); r.write(".license-approved", "MIT\n"); r.commit()
@case("GP6", 11, "a NOTICE file")
def _(r): r.write("NOTICE", "Copyright and license notices\n"); r.commit()
@case("GP6", 12, "a look-alike name: LlCENSE (lower-case L for I)")
def _(r): r.write("LlCENSE", MIT); r.commit()
@case("GP6", 13, "a license set in pyproject.toml")
def _(r): r.write("pyproject.toml", '[project]\nname = "x"\nlicense = "MIT"\n'); r.commit()
@case("GP6", 14, "an approval note written by someone other than the owner", expect="LIMIT",
      limit="A file can't prove who decided. Covered by: branch protection on main, so only the owner "
            "can merge, and the owner reads every pull request that adds .license-approved.")
def _(r): r.write("LICENSE", MIT); r.write(".license-approved", "MIT, approved 2026-11-21\n"); r.commit()
@case("GP6", 1, "look-alike: a dependency's own license in node_modules", expect="PASS")
def _(r): r.write("node_modules/lib/LICENSE", MIT); r.commit(force=True)
@case("GP6", 2, "look-alike: docs/LICENSE_NOTES.md", expect="PASS")
def _(r): r.write("docs/LICENSE_NOTES.md", "Notes on licenses we may choose.\n"); r.commit()
@case("GP6", 3, "look-alike: an approved license with a name and date", expect="PASS")
def _(r): r.write("LICENSE", MIT); r.write(".license-approved", "MIT, approved by the owner on 2026-11-21\n"); r.commit()

# ---- GP7: pinned actions --------------------------------------------------------------------------------
def uses_wf(u, name="u.yml"):
    return wf("\n  pull_request:\n", steps=f"      - uses: {u}\n", name=name)
@case("GP7", 1, "an action at a movable tag: @v4")
def _(r): put(r, uses_wf("actions/checkout@v4"))
@case("GP7", 2, "a branch, a full version and a short commit", mustlist=("@main", "@v4.1.2", "@3d3c42e"))
def _(r): put(r, wf("\n  pull_request:\n", steps="      - uses: a/b@main\n      - uses: c/d@v4.1.2\n      - uses: e/f@3d3c42e\n"))
@case("GP7", 3, "an unpinned action inside a local composite action")
def _(r): r.write(".github/actions/build/action.yml", "name: b\nruns:\n  using: composite\n  steps:\n    - uses: actions/setup-node@v4\n"); r.commit()
@case("GP7", 4, "a reusable workflow at a tag")
def _(r): r.write(".github/workflows/r.yml", "on: pull_request\npermissions: {}\njobs:\n  call:\n    uses: owner/repo/.github/workflows/x.yml@v1\n"); r.commit()
@case("GP7", 5, "a container image by tag: docker://alpine:latest")
def _(r): put(r, uses_wf("docker://alpine:latest"))
@case("GP7", 6, "a workflow named .yaml")
def _(r): put(r, uses_wf("actions/checkout@v4", name="u.yaml"))
@case("GP7", 7, "quoted with extra spaces")
def _(r): put(r, wf("\n  pull_request:\n", steps='      - uses:    "actions/checkout@v4"   \n'))
@case("GP7", 8, "a pinned remote action whose own steps use tags", expect="LIMIT",
      limit="What another repo's action uses inside is outside this repo's files. Covered by: pin the "
            "outer action to a commit you reviewed, and zizmor's online audits in CI.")
def _(r): put(r, uses_wf(f"someone/composite@{SHA_OK} # v1.0.0"))
@case("GP7", 9, "five unpinned actions: all five listed",
      mustlist=("a/a@v1", "b/b@v1", "c/c@v1", "d/d@v1", "e/e@v1"))
def _(r): put(r, wf("\n  pull_request:\n", steps="".join(f"      - uses: {x}/{x}@v1\n" for x in "abcde")))
@case("GP7", 10, "a pin to a commit that doesn't exist", expect="LIMIT",
      limit="Offline, a well-formed commit can't be checked. Covered by: zizmor's online "
            "impostor-commit audit in CI (GH_TOKEN), which fails if the commit isn't in that repo.")
def _(r): put(r, uses_wf("actions/checkout@" + "0" * 40 + " # v7.0.1"))
@case("GP7", 11, "a disguised path: actions//checkout")
def _(r): put(r, uses_wf(f"actions//checkout@{SHA_OK} # v7.0.1"))
@case("GP7", 12, "a misspelled owner: actoins/checkout", gates=["GP7", "GP8"], needs="zizmor")
def _(r): put(r, uses_wf(f"actoins/checkout@{SHA_OK} # v7.0.1"))
@case("GP7", 13, "a pin without a version comment")
def _(r): put(r, uses_wf(f"actions/checkout@{SHA_OK}"))
@case("GP7", 14, "Dependabot removed, so pins silently age")
def _(r): r.rm(".github/dependabot.yml"); r.commit()
@case("GP7", 1, "look-alike: a local action", expect="PASS")
def _(r):
    r.write(".github/actions/x/action.yml", "name: x\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo ok\n")
    put(r, uses_wf("./.github/actions/x"))
@case("GP7", 2, "look-alike: a container image pinned to a digest", expect="PASS")
def _(r): put(r, uses_wf("docker://alpine@sha256:" + "a" * 64))

# ---- GP8: zizmor -----------------------------------------------------------------------------------------
@case("GP8", 13, "Dependabot without a cooldown", needs="zizmor")
def _(r): r.write(".github/dependabot.yml", DEPENDABOT.split("    cooldown")[0]); r.commit()
@case("GP8", 8, "a checkout that leaves its credential on disk", needs="zizmor")
def _(r): r.write(".github/workflows/ci.yml", WORKFLOW.replace("        with:\n          persist-credentials: false\n", "")); r.commit()
@case("GP8", 10, "zizmor isn't installed", env={"PATH": "/usr/bin:/bin"})
def _(r): pass

# ---- Kind 15 for every gate: a weakened gate must be noticed ------------------------------------------------
def weakened(gate):
    src = open(GATES, encoding="utf-8").read()
    fn = gate.lower()
    new = re.sub(rf"(\ndef {fn}\(\):\n)", rf'\1    return out("PASS", "{gate}", "(weakened for testing)")\n', src, count=1)
    path = tempfile.mkstemp(prefix=f"weak-{gate}-", suffix=".sh")[1]
    open(path, "w").write(new)
    return path

# --------------------------------------------------------------------------------------------
def tool_ok(name):
    return shutil.which(name) is not None

def run_case(c):
    if c["needs"] and not tool_ok(c["needs"]):
        return (c, "SKIP" if not REQUIRE_TOOLS else "MISSED", f"{c['needs']} isn't installed here")
    r = clean_repo()
    try:
        ret = c["fn"](r)
    except Exception as e:
        return (c, "ERROR", f"couldn't plant: {e}")
    path, env = r.p, dict(c["env"])
    if isinstance(ret, tuple):
        path, extra = ret; env.update(extra)
    elif isinstance(ret, str):
        path = ret
    out = run_gates(path, c["gates"], env)
    got = {g: result_of(out, g) for g in c["gates"]}
    failed = any(v == "FAIL" for v in got.values())
    if c["expect"] == "PASS":
        return (c, "OK" if not failed else "FALSE ALARM", out)
    if c["expect"] == "LIMIT":
        return (c, "LIMIT" if not failed else "LIMIT NOW CAUGHT", c["limit"])
    if not failed:
        return (c, "MISSED", out)
    missing = [m for m in c["mustlist"] if m not in out]
    if missing:
        return (c, "PARTLY", f"caught, but didn't list: {', '.join(missing)}")
    return (c, "CAUGHT", "")

def run_tamper(gate):
    first = next(c for c in CASES if c["gate"] == gate and c["expect"] == "FAIL" and not c["needs"]
                 and not c["env"] and c["gates"] == [gate])
    r = clean_repo(); first["fn"](r)
    out = run_gates(r.p, [gate], first["env"], script=weakened(gate))
    # The weakened gate lets the planted failure through; the suite (and CI's guard) must notice.
    return (dict(gate=gate, kind=15, what="a weakened copy of the gate is noticed by this suite"),
            "CAUGHT" if result_of(out, gate) != "FAIL" else "MISSED",
            "" if result_of(out, gate) != "FAIL" else "the weakening didn't take effect")

cases = [c for c in CASES if not ONLY or c["gate"] in ONLY]
gates_for_tamper = sorted({c["gate"] for c in cases if c["gate"] not in ("GP0", "GP8")})
with ThreadPoolExecutor(max_workers=min(16, (os.cpu_count() or 4) * 2)) as ex:
    results = list(ex.map(run_case, cases)) + list(ex.map(run_tamper, gates_for_tamper))

results.sort(key=lambda x: (x[0]["gate"], x[0]["kind"], x[0]["what"]))
bad = {"MISSED", "FALSE ALARM", "PARTLY", "ERROR", "LIMIT NOW CAUGHT"}
counts = {}
for c, status, detail in results:
    counts[status] = counts.get(status, 0) + 1
    print(f"{status:<16} {c['gate']} kind {c['kind']:>2}  {c['what']}")
    if status in bad or status == "LIMIT":
        for line in str(detail).strip().splitlines()[:8]:
            print(f"{'':<16}   {line}")
print()
print("Summary: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
problems = sum(counts.get(k, 0) for k in bad)
if counts.get("SKIP") and REQUIRE_TOOLS:
    problems += counts["SKIP"]
print("All gates catch every planted failure and pass every look-alike." if not problems
      else f"{problems} case(s) need attention (see above).")
sys.exit(1 if problems else 0)
PY
