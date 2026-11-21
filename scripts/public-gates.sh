#!/usr/bin/env bash
# Going Public gates GP0-GP8. Run from a repo's root, locally or in CI:
#   bash scripts/public-gates.sh              all gates
#   bash scripts/public-gates.sh GP2 GP5      only these gates
# Exit 1 if any gate fails. scripts/test-gates.sh proves each gate catches its planted failures.
#
# Needs: git, python3 (with PyYAML; jsonschema when a JSON file names a local $schema),
# gitleaks v8.30.1+ (GP3) and zizmor 1.32.0+ (GP8). A missing tool FAILS its gate: a gate that
# can't see must never pass. Settings:
#   GH_TOKEN               lets zizmor run its online audits (impostor commits, version comments)
#   ZIZMOR_REQUIRE_ONLINE  1 = GP8 fails without GH_TOKEN (CI sets this)
#   ZIZMOR_OFFLINE         1 = run zizmor's offline audits only, even if a token is present
set -uo pipefail
exec python3 - "$@" <<'PY'
import json, os, re, shutil, subprocess, sys, tarfile, unicodedata, zipfile, io

os.environ["GIT_NO_REPLACE_OBJECTS"] = "1"  # git replace could otherwise hide real commits
ONLY = set(a.upper() for a in sys.argv[1:])
FAILED = False
MIN_GITLEAKS = (8, 30, 1)
MIN_ZIZMOR = (1, 32, 0)
SKIP_DIRS = ("node_modules/", "vendor/", "third_party/", ".git/")

def out(status, gate, msg, details=()):
    global FAILED
    if status == "FAIL":
        FAILED = True
    print(f"{status}  {gate} {msg}")
    for d in details:
        print(f"      {d}")

def want(gate):
    return not ONLY or gate in ONLY

def git(*args, check=False):
    r = subprocess.run(["git", *args], capture_output=True)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr.decode(errors="replace").strip())
    return r.stdout.decode("utf-8", errors="surrogateescape")

def tracked():
    return [p for p in git("ls-files", "-z").split("\0") if p]

def skipped(path):
    return any(path.startswith(d) or f"/{d}" in path for d in SKIP_DIRS)

def clean_name(name):
    """Normalize a file name the way a person reads it: NFKC, no invisible or trailing junk."""
    name = unicodedata.normalize("NFKC", name)
    name = "".join(c for c in name if unicodedata.category(c) not in ("Cf", "Cc"))
    return name.strip().rstrip(". ").lower() if name.strip() not in (".", "..") else name

def version_tuple(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text or "")
    return tuple(int(x) for x in m.groups()) if m else None

def read_bytes(path, limit=5_000_000):
    try:
        if os.path.islink(path) or os.path.getsize(path) > limit:
            return None
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None

# ---------------------------------------------------------------------------------------------
# GP0: the gates can see everything: a real repo, full history, submodules present.
def gp0():
    if git("rev-parse", "--is-inside-work-tree").strip() != "true":
        return out("FAIL", "GP0", "not inside a git repository: nothing can be checked")
    problems = []
    if git("rev-parse", "--is-shallow-repository").strip() == "true":
        problems.append("shallow copy: older commits are missing, so history checks would be blind "
                        "(CI: actions/checkout with fetch-depth: 0)")
    if os.path.exists(".gitmodules"):
        for line in git("submodule", "status", "--recursive").splitlines():
            if line.startswith("-"):
                problems.append(f"submodule not checked out: {line.split()[1]} (git submodule update --init --recursive)")
    if problems:
        out("FAIL", "GP0", "the gates can't see everything:", problems)
    else:
        out("PASS", "GP0", "full history and all submodules visible")

# ---------------------------------------------------------------------------------------------
# GP1: every commit and tag identity is a noreply address, in this repo and its submodules.
ALLOWED_EMAIL = re.compile(
    r"^(\d+\+)?[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(\[bot\])?@users\.noreply\.github\.com$"
    r"|^noreply@github\.com$|^noreply@anthropic\.com$")

def identities(repo="."):
    emails = set()
    log = subprocess.run(["git", "-C", repo, "log", "--all", "--format=%ae%x00%ce%x00"],
                         capture_output=True).stdout.decode("utf-8", errors="replace")
    emails.update(e for e in log.split("\0"))
    tags = subprocess.run(["git", "-C", repo, "for-each-ref", "refs/tags", "--format=%(taggeremail)"],
                          capture_output=True).stdout.decode("utf-8", errors="replace")
    emails.update(t.strip().strip("<>") for t in tags.splitlines())
    return {e.strip() for e in emails if e.strip()}

def gp1():
    bad = []
    repos = ["."]
    if os.path.exists(".gitmodules"):
        for line in git("submodule", "status", "--recursive").splitlines():
            parts = line.split()
            if len(parts) > 1 and not line.startswith("-"):
                repos.append(parts[1])
    for repo in repos:
        for ref in subprocess.run(["git", "-C", repo, "for-each-ref", "refs/replace", "--format=%(refname)"],
                                  capture_output=True, text=True).stdout.split():
            bad.append(f"{repo}: {ref} swaps one commit for another in the history people see (remove it)")
        for e in sorted(identities(repo)):
            low = e.lower()
            if not low.isascii():
                bad.append(f"{repo}: {e!r} contains look-alike or non-ASCII characters")
            elif not ALLOWED_EMAIL.match(low):
                bad.append(f"{repo}: {e}")
    if bad:
        out("FAIL", "GP1", "commit identity: emails that aren't noreply addresses:", bad)
    else:
        out("PASS", "GP1", "commit identity (noreply only, history and tags)")

# ---------------------------------------------------------------------------------------------
# GP2: no secrets-bearing or generated binary files, by name or by content, now or in history.
BACKUP = re.compile(r"(\.(bak|old|orig|backup|copy|save|tmp|swp)|~)+$")
FORBIDDEN = [re.compile(p) for p in [
    r"(^|/)local\.properties$", r"(^|/)google-services\.json$", r"(^|/)googleservice-info\.plist$",
    r"(^|/)\.env$", r"(^|/)\.env\.(?!example$|sample$|template$)[^/]+$",
    r"\.(jks|keystore|p12|pfx|p8|pem|key|mobileprovision|tfstate)$",
    r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$", r"(^|/)keystore\.properties$", r"(^|/)signing\.properties$",
    r"(^|/)credentials\.json$", r"service-account[^/]*\.json$", r"(^|/)\.netrc$",
    r"\.(litertlm|tflite|onnx|gguf|pmtiles)$",
]]
BINARY = re.compile(r"\.(class|jar|war|ear|so|dll|exe|dylib|pyc|pyo|o|a|lib|dex|apk|aab|aar|ipa|bin)$")
ARCHIVES_ZIP = re.compile(r"\.(zip|jar|war|apk|aab|aar|ipa)$")
ARCHIVES_TAR = re.compile(r"\.(tar|tar\.gz|tgz|tar\.bz2|tar\.xz)$")
PEM_KEY = re.compile(rb"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")
MAGIC = {b"\xfe\xed\xfe\xed": "Java keystore (JKS)", b"\xce\xce\xce\xce": "Java keystore (JCEKS)"}
B64_MAGIC = re.compile(rb"(^|[^A-Za-z0-9+/])/u3\+7Q")  # base64 of a JKS header

def name_problem(path):
    n = BACKUP.sub("", clean_name(path))
    for p in FORBIDDEN:
        if p.search(n):
            return "forbidden file"
    return None

def content_problem(data):
    if data is None:
        return None
    for magic, what in MAGIC.items():
        if data.startswith(magic):
            return what
    if PEM_KEY.search(data[:200_000]):
        return "private key"
    if B64_MAGIC.search(data[:200_000]):
        return "Java keystore, base64-encoded"
    return None

def archive_members(path, data):
    """Names and first bytes of files inside an archive (one level)."""
    members = []
    try:
        if ARCHIVES_ZIP.search(path.lower()):
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                for i in z.infolist():
                    if not i.is_dir():
                        members.append((i.filename, z.open(i).read(4096)))
        elif ARCHIVES_TAR.search(path.lower()):
            with tarfile.open(fileobj=io.BytesIO(data)) as t:
                for m in t.getmembers():
                    if m.isfile():
                        members.append((m.name, t.extractfile(m).read(4096)))
    except Exception:
        members.append(("(archive could not be opened)", None))
    return members

def binary_allowed(path):
    if not os.path.exists(".binary-allowlist"):
        return False
    pats = [l.strip() for l in open(".binary-allowlist", encoding="utf-8") if l.strip() and not l.startswith("#")]
    import fnmatch
    return any(fnmatch.fnmatch(path, p) for p in pats)

def gp2():
    bad = []
    files = tracked()
    modes = {}
    for line in git("ls-files", "-s", "-z").split("\0"):
        if line:
            meta, path = line.split("\t", 1)
            modes[path] = meta.split()[0]
    for path in files:
        if skipped(path):
            continue
        why = name_problem(path)
        if why:
            bad.append(f"{path}: {why}")
        if BINARY.search(clean_name(path)) and not binary_allowed(path):
            bad.append(f"{path}: generated binary (not reviewable; list it in .binary-allowlist if it must stay)")
        if modes.get(path) == "120000":
            target = os.readlink(path) if os.path.islink(path) else ""
            real = os.path.realpath(path)
            if os.path.isabs(target) or not real.startswith(os.path.realpath(".") + os.sep):
                bad.append(f"{path}: symlink pointing outside the repo ({target})")
            elif name_problem(target):
                bad.append(f"{path}: symlink to a forbidden file ({target})")
            continue
        data = read_bytes(path)
        what = content_problem(data)
        if what:
            bad.append(f"{path}: contains a {what}")
        if data and (ARCHIVES_ZIP.search(path.lower()) or ARCHIVES_TAR.search(path.lower())):
            for member, head in archive_members(path, data):
                w = name_problem(member) or content_problem(head)
                if w:
                    bad.append(f"{path} -> {member}: {w} inside an archive")
    current = set(files)
    for path in sorted(set(git("log", "--all", "--format=", "--name-only", "-z").replace("\n", "\0").split("\0"))):
        if path and path not in current and not skipped(path) and name_problem(path):
            bad.append(f"{path}: forbidden file still in history (rewrite history and rotate the secret)")
    if os.path.exists(".gitignore"):
        for n, line in enumerate(open(".gitignore", encoding="utf-8", errors="replace"), 1):
            l = line.strip()
            if l.startswith("!") and name_problem(l[1:].replace("*", "x").lstrip("/")):
                bad.append(f".gitignore:{n}: '{l}' un-ignores a forbidden file type")
    if bad:
        out("FAIL", "GP2", "forbidden files:", sorted(set(bad)))
    else:
        out("PASS", "GP2", "no forbidden or generated binary files, now or in history")

# ---------------------------------------------------------------------------------------------
# GP3: secret scan over the full history, nothing silenced without approval, scanner current.
def gp3():
    exe = shutil.which("gitleaks")
    if not exe:
        return out("FAIL", "GP3", "gitleaks is not installed, so secrets can't be checked")
    ver = version_tuple(subprocess.run([exe, "version"], capture_output=True, text=True).stdout)
    if ver and ver < MIN_GITLEAKS:
        return out("FAIL", "GP3", f"gitleaks {'.'.join(map(str, ver))} is older than "
                   f"{'.'.join(map(str, MIN_GITLEAKS))}: older scanners miss newer secret types")
    problems = []
    approved = set()
    if os.path.exists(".suppressions-approved"):
        approved = {l.strip() for l in open(".suppressions-approved", encoding="utf-8") if l.strip()}
    for path in tracked():
        if skipped(path):
            continue
        if os.path.basename(path) == ".gitleaksignore" and path not in approved:
            problems.append(f"{path}: silences secret findings (needs the owner's approval in .suppressions-approved)")
        data = read_bytes(path)
        if data and b"gitleaks:allow" in data and path not in approved and not path.startswith("scripts/"):
            problems.append(f"{path}: 'gitleaks:allow' silences a finding (needs the owner's approval)")
    import tempfile
    report = tempfile.mkstemp(prefix="gitleaks-", suffix=".json")[1]
    r = subprocess.run([exe, "git", "--log-opts=--all", "--redact", "--no-banner",
                        "--max-archive-depth", "3", "--max-decode-depth", "5",
                        "--report-format", "json", "--report-path", report, "."],
                       capture_output=True, text=True)
    findings = []
    try:
        findings = json.load(open(report, encoding="utf-8")) or []
    except Exception:
        pass
    finally:
        os.unlink(report)
    if findings:
        problems.append(f"gitleaks found {len(findings)} possible secret(s) (values hidden):")
        for f in findings[:60]:
            problems.append(f"{f.get('RuleID')}: {f.get('File')}:{f.get('StartLine')} "
                            f"(commit {str(f.get('Commit', ''))[:7]})")
    elif r.returncode != 0:
        problems.append("gitleaks didn't finish cleanly, so the scan can't be trusted:")
        problems.extend([l for l in (r.stdout + r.stderr).splitlines() if l.strip()][-20:])
    if problems:
        out("FAIL", "GP3", "secrets:", problems)
    else:
        out("PASS", "GP3", "no secrets in the full history (gitleaks, archives and encodings included)")

# ---------------------------------------------------------------------------------------------
# Workflow files, parsed as YAML.
def yaml_load(path):
    import yaml
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)

def workflow_files():
    files = []
    for path in tracked():
        p = path.lower()
        if re.match(r"\.github/workflows/[^/]+\.ya?ml$", p) or re.match(r"templates/.*workflows/[^/]+\.ya?ml$", p):
            files.append(path)
    return files

def action_files():
    return [p for p in tracked() if re.search(r"(^|/)action\.ya?ml$", p.lower()) and not skipped(p)]

DANGEROUS_TRIGGERS = {"pull_request_target", "workflow_run", "issue_comment"}
UNTRUSTED = re.compile(
    r"\$\{\{[^}]*github\.(?:event\.(?:issue|pull_request|comment|review|review_comment|discussion|"
    r"discussion_comment|head_commit|commits|pages|workflow_run)\b[^}]*|head_ref\b[^}]*)\}\}")

def triggers(doc):
    on = doc.get("on", doc.get(True)) if isinstance(doc, dict) else None
    if isinstance(on, str):
        return {on}
    if isinstance(on, list):
        return set(map(str, on))
    if isinstance(on, dict):
        return set(map(str, on.keys()))
    return set()

def walk_steps(doc):
    runs = doc.get("runs") if isinstance(doc, dict) else None
    if isinstance(runs, dict):
        for i, step in enumerate(runs.get("steps") or []):
            if isinstance(step, dict):
                yield ("step", f"runs[{i}]", step)
    jobs = doc.get("jobs") or {} if isinstance(doc, dict) else {}
    for jname, job in (jobs.items() if isinstance(jobs, dict) else []):
        if not isinstance(job, dict):
            continue
        yield ("job", jname, job)
        for i, step in enumerate(job.get("steps") or []):
            if isinstance(step, dict):
                yield ("step", f"{jname}[{i}]", step)

def gp4():
    bad = []
    for path in workflow_files() + action_files():
        try:
            doc = yaml_load(path)
        except Exception as e:
            bad.append(f"{path}: can't be read as YAML, so it can't be checked ({str(e).splitlines()[0]})")
            continue
        if not isinstance(doc, dict):
            continue
        for t in sorted(triggers(doc) & DANGEROUS_TRIGGERS):
            bad.append(f"{path}: dangerous trigger '{t}' (runs with the target repo's secrets for outsiders' events)")
        runs_gates = "public-gates" in open(path, encoding="utf-8").read()
        on = doc.get("on", doc.get(True))
        if runs_gates and isinstance(on, dict):
            for ev in ("pull_request", "push"):
                cfg = on.get(ev)
                if isinstance(cfg, dict) and ({"paths", "paths-ignore"} & set(cfg)):
                    bad.append(f"{path}: '{ev}' has a path filter, so the gates don't run on every change")
        for kind, name, item in walk_steps(doc):
            if item.get("continue-on-error") in (True, "true"):
                bad.append(f"{path}: {kind} {name} has continue-on-error, so a failure doesn't block")
            if str(item.get("if", "")).strip().lower() in ("false", "${{ false }}", "0"):
                bad.append(f"{path}: {kind} {name} is switched off with if: false")
            run = item.get("run")
            if isinstance(run, str) and UNTRUSTED.search(run):
                bad.append(f"{path}: {kind} {name} pastes outsider-controlled text into a shell command "
                           f"({UNTRUSTED.search(run).group(0)}): pass it through env instead")
    if bad:
        out("FAIL", "GP4", "dangerous workflows:", bad)
    else:
        out("PASS", "GP4", "no dangerous triggers, injections or switched-off checks")

# ---------------------------------------------------------------------------------------------
# GP5: every data file parses: strict JSON, JSON-with-comments where tools allow it, YAML,
# notebooks, JSON blocks in Markdown, and local $schema references.
JSONC = re.compile(r"(^|/)(tsconfig[^/]*\.json|jsconfig[^/]*\.json|devcontainer[^/]*\.json|"
                   r"\.devcontainer/[^/]+\.json|\.vscode/[^/]+\.json|[^/]+\.jsonc|[^/]+\.code-workspace|"
                   r"\.eslintrc(\.json)?|\.babelrc|\.prettierrc)$")
MAX_DEPTH = 100

def strip_jsonc(text):
    out_, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out_.append(c)
            if c == "\\" and i + 1 < n:
                out_.append(text[i + 1]); i += 2; continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True; out_.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        else:
            out_.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out_))

def no_dupes(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise ValueError(f"duplicate key '{k}'")
        seen[k] = v
    return seen

def depth(x, d=0):
    if d > MAX_DEPTH:
        raise ValueError(f"nested deeper than {MAX_DEPTH} levels")
    if isinstance(x, dict):
        for v in x.values(): depth(v, d + 1)
    elif isinstance(x, list):
        for v in x: depth(v, d + 1)

def parse_json(raw, comments_ok):
    if raw is None:
        raise ValueError("too large or unreadable")
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError("starts with a byte-order mark")
    text = raw.decode("utf-8")  # strict: invalid UTF-8 fails
    if not text.strip():
        raise ValueError("empty file")
    if comments_ok:
        text = strip_jsonc(text)
    doc = json.loads(text, object_pairs_hook=no_dupes)
    depth(doc)
    return doc

def yaml_no_dupes():
    import yaml
    class L(yaml.SafeLoader):
        pass
    def construct(loader, node, deep=False):
        keys = set()
        for k, _ in node.value:
            key = loader.construct_object(k, deep=deep)
            if key in keys:
                raise yaml.constructor.ConstructorError(None, None, f"duplicate key '{key}'", k.start_mark)
            keys.add(key)
        return loader.construct_mapping(node, deep)
    L.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct)
    return L

def gp5():
    bad = []
    try:
        import yaml
    except ImportError:
        return out("FAIL", "GP5", "PyYAML is not installed, so YAML files can't be checked")
    loader = yaml_no_dupes()
    for path in tracked():
        if skipped(path):
            continue
        low = path.lower()
        name = os.path.basename(low)
        is_json = low.endswith((".json", ".geojson", ".ipynb", ".jsonc", ".code-workspace", ".webmanifest"))
        is_rc = name in (".eslintrc", ".babelrc", ".prettierrc")
        raw = read_bytes(path, 20_000_000)
        try:
            if is_json or is_rc:
                doc = parse_json(raw, bool(JSONC.search(low)))
                schema = doc.get("$schema") if isinstance(doc, dict) else None
                if isinstance(schema, str) and not re.match(r"^[a-z]+://", schema):
                    sp = os.path.normpath(os.path.join(os.path.dirname(path), schema))
                    if not os.path.exists(sp):
                        raise ValueError(f"its $schema {schema} doesn't exist")
                    import jsonschema
                    jsonschema.validate({k: v for k, v in doc.items() if k != "$schema"},
                                        json.load(open(sp, encoding="utf-8")))
            elif low.endswith((".yml", ".yaml")):
                if raw is None:
                    raise ValueError("too large or unreadable")
                for _ in yaml.load_all(raw.decode("utf-8"), Loader=loader):
                    pass
            elif low.endswith(".md") and raw:
                text = raw.decode("utf-8", errors="replace")
                for m in re.finditer(r"^```json[ \t]*\n(.*?)^```", text, re.S | re.M):
                    parse_json(m.group(1).encode(), False)
        except ImportError as e:
            bad.append(f"{path}: needs the '{e.name}' Python package to check it")
        except Exception as e:
            bad.append(f"{path}: {str(e).splitlines()[0][:160]}")
    if bad:
        out("FAIL", "GP5", "data files that don't parse:", bad)
    else:
        out("PASS", "GP5", "every JSON, YAML and notebook file parses")

# ---------------------------------------------------------------------------------------------
# GP6: no license chosen without the owner's recorded approval.
LICENSE_NAME = re.compile(r"^(license|licence|copying|unlicense|notice)"
                          r"([-_.](mit|apache|apache-2\.0|bsd|gpl|lgpl|agpl|mpl|isc|cc[-a-z0-9.]*|unlicense))?"
                          r"(\.(md|txt|rst|markdown))*$")
LICENSE_TEXT = re.compile(rb"Permission is hereby granted, free of charge|Licensed under the Apache License|"
                          rb"GNU (?:LESSER |AFFERO )?GENERAL PUBLIC LICENSE|Mozilla Public License|"
                          rb"This is free and unencumbered software released into the public domain")
APPROVAL = re.compile(r"(MIT|Apache-2\.0|GPL|LGPL|AGPL|BSD|MPL|ISC|CC|Unlicense)", re.I)

def license_like(path):
    base = clean_name(os.path.basename(path))
    return bool(LICENSE_NAME.match(base) or LICENSE_NAME.match(base.replace("l", "i").replace("iicense", "license")
                                                                .replace("iicence", "licence")))

def gp6():
    found = []
    for path in tracked():
        if skipped(path):
            continue
        if license_like(path):
            found.append(f"{path}: license file")
            continue
        low = path.lower()
        if os.path.basename(low) == "package.json":
            try:
                if "license" in json.load(open(path, encoding="utf-8")):
                    found.append(f"{path}: 'license' field")
            except Exception:
                pass
        elif low.endswith(("readme.md", "readme", "readme.txt")) or os.path.basename(low) == "pyproject.toml":
            data = read_bytes(path) or b""
            if LICENSE_TEXT.search(data) or (low.endswith("pyproject.toml") and re.search(rb"^license\s*=", data, re.M)):
                found.append(f"{path}: license text or setting")
    if not found:
        return out("PASS", "GP6", "no license added without the owner's decision")
    if not os.path.exists(".license-approved"):
        return out("FAIL", "GP6", "a license was added without the owner's approval (.license-approved missing):", found)
    note = open(".license-approved", encoding="utf-8").read()
    if not APPROVAL.search(note) or not re.search(r"\b20\d\d-\d\d-\d\d\b", note):
        return out("FAIL", "GP6", ".license-approved must name the license and the date (YYYY-MM-DD) "
                   "the owner decided:", found)
    out("PASS", "GP6", "license present and approved")

# ---------------------------------------------------------------------------------------------
# GP7: every action and reusable workflow is pinned to a full commit, with a version comment,
# and Dependabot keeps the pins current.
SHA = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")

def collect_uses(node, found):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "uses" and isinstance(v, str):
                found.append(v)
            else:
                collect_uses(v, found)
    elif isinstance(node, list):
        for v in node:
            collect_uses(v, found)

def gp7():
    bad = []
    files = workflow_files() + action_files()
    for path in files:
        try:
            doc = yaml_load(path)
        except Exception as e:
            bad.append(f"{path}: can't be read as YAML ({str(e).splitlines()[0]})")
            continue
        uses = []
        collect_uses(doc, uses)
        text = open(path, encoding="utf-8").read()
        for u in uses:
            u = u.strip()
            if u.startswith("./"):
                if ".." in u.split("/"):
                    bad.append(f"{path}: local action path leaves its folder: {u}")
                continue
            if u.startswith("docker://"):
                if not DIGEST.search(u):
                    bad.append(f"{path}: container image not pinned to a sha256 digest: {u}")
                continue
            ref_path, _, ref = u.partition("@")
            if "//" in ref_path or "/./" in ref_path or "/../" in ref_path or ref_path.endswith(("/.", "/..")):
                bad.append(f"{path}: disguised action path: {u}")
            if not SHA.match(ref):
                bad.append(f"{path}: not pinned to a full 40-character commit: {u}")
                continue
            line = next((l for l in text.splitlines() if ref in l), "")
            if not re.search(r"#\s*v?\d+(\.\d+)*", line):
                bad.append(f"{path}: pinned without a version comment (# vX.Y.Z), so people and "
                           f"Dependabot can't tell which version: {u}")
    if files and not any(p in tracked() for p in (".github/dependabot.yml", ".github/dependabot.yaml")):
        bad.append(".github/dependabot.yml is missing, so pinned actions would silently age")
    if bad:
        out("FAIL", "GP7", "actions not safely pinned:", bad)
    else:
        out("PASS", "GP7", "every action pinned to a full commit, with Dependabot keeping it current")

# ---------------------------------------------------------------------------------------------
# GP8: zizmor, the dedicated GitHub Actions security scanner, finds nothing.
def gp8():
    exe = shutil.which("zizmor")
    if not exe:
        return out("FAIL", "GP8", "zizmor is not installed, so workflows can't be fully checked")
    ver = version_tuple(subprocess.run([exe, "--version"], capture_output=True, text=True).stdout)
    if ver and ver < MIN_ZIZMOR:
        return out("FAIL", "GP8", f"zizmor {'.'.join(map(str, ver))} is older than {'.'.join(map(str, MIN_ZIZMOR))}")
    online = bool(os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")) and os.environ.get("ZIZMOR_OFFLINE") != "1"
    if not online and os.environ.get("ZIZMOR_REQUIRE_ONLINE") == "1":
        return out("FAIL", "GP8", "GH_TOKEN is not set, so impostor-commit and version-comment checks can't run")
    targets = [p for p in workflow_files() + action_files() + [".github/dependabot.yml"] if os.path.exists(p)]
    if not targets:
        return out("PASS", "GP8", "no workflows to scan")
    args = [exe, "--no-progress", "--color=never", "--min-severity=low", "--persona=regular"]
    if not online:
        args.append("--offline")
    r = subprocess.run(args + targets, capture_output=True, text=True)
    note = "" if online else " (offline: impostor-commit and version-comment audits need GH_TOKEN)"
    if r.returncode != 0:
        lines = [l for l in r.stdout.splitlines() if l.strip()]
        out("FAIL", "GP8", "zizmor found workflow problems" + note + ":", lines[-60:] or r.stderr.splitlines()[-20:])
    else:
        out("PASS", "GP8", "zizmor finds no workflow problems" + note)

for gate, fn in [("GP0", gp0), ("GP1", gp1), ("GP2", gp2), ("GP3", gp3), ("GP4", gp4),
                 ("GP5", gp5), ("GP6", gp6), ("GP7", gp7), ("GP8", gp8)]:
    if want(gate):
        try:
            fn()
        except Exception as e:  # a crashing gate is a failing gate, never a passing one
            out("FAIL", gate, f"the gate itself crashed: {e}")
sys.exit(1 if FAILED else 0)
PY
