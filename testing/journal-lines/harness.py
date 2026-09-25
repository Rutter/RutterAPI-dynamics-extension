#!/usr/bin/env python3
"""Shared plumbing for the journal-line parity suites.

Everything here is operation-agnostic: the two sandbox companies, the HTTP client, fixture
lookup, the field-by-field diff and cleanup. A suite for a specific AL block (see parity.py
for CreateLines) imports this and supplies only its own "old way" / "new way" pair.
"""
import builtins, functools, json, os, sys, urllib.error, urllib.parse, urllib.request, uuid

print = functools.partial(builtins.print, flush=True)

BASE = "https://api.businesscentral.dynamics.com/v2.0"

# Refuse to test a build older than this. Bump it when a new block ships; a stale extension
# otherwise reports green against code that isn't there.
MIN_EXTENSION_VERSION = (22, 5, 0, 29)

# The declared test connections — the only ones this suite may ever touch. Adding an entry
# here is the act of declaring a connection safe to write to; anything not listed is assumed
# to be a customer connection and is off limits.
CONFIG = {
    "usa": {
        "label": "CRONUS USA, Inc. (blessed / Production)",
        "env": "Production",
        "company_id": "2887748d-9c8e-ee11-be3f-6045bde9b4bf",
        "company_name": "CRONUS USA, Inc.",
        "item_id": "1912f593-6087-4c8d-aaf0-3615cbdd414e",
        "batch_name": "DEFAULT",
        "batch_id": "ffad50b4-9c8e-ee11-be3f-6045bde9b4bf",
        "gl": ["10231", "11100"],
        "bank": "B010",
        "currency": "EUR",
        "tax": ("MIAMI, FL", "FURNITURE"),
        "vat": None,
        # Accounts carrying defaults, to exercise RestoreAccountDefaults. 60160 already had
        # VAT Bus./Prod. HST/REDUCED in the demo data; no account on this company has default
        # dimensions, so that shape is UAE-only. All 264 posting accounts were probed.
        "vat_default_account": "60160",
        "dim_default_account": None,
    },
    "uae": {
        "label": "CRONUS UAE 2 (taxes_test)",
        "env": "taxes_test",
        "company_id": "af651e34-b68a-f111-8072-6045bd7a8d46",
        "company_name": "CRONUS UAE 2",
        # Machine-specific: this connection lives in whoever created it's local dev DB, so it
        # is read from CLAUDE.local.md rather than pinned here. See the skill.
        "item_id": None,
        "item_id_setting": "uae item",
        "batch_name": "DEFAULT",
        "batch_id": "0a09a119-b78a-f111-8072-6045bd7a8d46",
        "gl": ["61100", "18400"],
        "bank": "CHECKING",
        "currency": "AED",
        "tax": None,
        "vat": ("DOMESTIC", "VAT5"),
        # 60120 carries VAT Bus./Prod. Posting Group DOMESTIC/VAT5, 62120 a DEPARTMENT=ADM
        # default dimension. Nothing else on either company has defaults — all 229 posting
        # accounts were probed — so without these two the restore paths never execute.
        "vat_default_account": "60120",
        "dim_default_account": "62120",
    },
}

# Only the identity fields can legitimately differ between two separate lines.
IGNORED = {"id", "lineNumber", "@odata.etag", "@odata.context", "lastModifiedDatetime",
           "systemCreatedAt", "systemModifiedAt"}


def load_token(cfg):
    """Mint a fresh BC token from rutter-backend's local admin-ops endpoint. There is no
    fallback on purpose: BC tokens last about an hour, so a saved one is a stale one, and the
    suite needs that repo running anyway."""
    port = os.environ.get("PORT", "4000")
    item = item_id(cfg)
    url = f"http://localhost:{port}/admin-ops/blessed-postman-platform-setup/{item}"
    try:
        with urllib.request.urlopen(url, timeout=120) as r:
            d = json.loads(r.read())
        d = d.get("data", d)
        token = (d.get("platform") or {}).get("access_token", "")
    except Exception as e:
        sys.exit(f"could not reach the admin-ops endpoint on port {port} ({type(e).__name__}).\n"
                 f"Start rutter-backend's dev server (yarn dev:web) and retry. If it runs on "
                 f"another port, pass PORT=<port>.")
    if len(token) < 100:
        sys.exit(f"admin-ops returned no platform access token for item {item} — check that "
                 f"the item exists locally and its credential is valid.")
    print(f"  token: minted fresh for {item[:8]}")
    return token


def local_setting(key):
    """Read a `key: value` line from CLAUDE.local.md at the repo root (gitignored)."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "CLAUDE.local.md")
    if not os.path.exists(path):
        return None
    for line in open(path):
        name, sep, value = line.partition(":")
        if sep and name.strip().lower() == key.lower():
            return value.strip() or None
    return None


def item_id(cfg):
    """The Rutter item whose credential mints this company's BC token."""
    found = (cfg.get("item_id")
             or local_setting(cfg.get("item_id_setting", ""))
             or os.environ.get("RUTTER_ITEM_ID"))
    if not found:
        sys.exit(
            f"no Rutter item id for {cfg['label']}.\n"
            f"This connection is local to whoever created it, so there is no id to hardcode. "
            f"Connect {cfg['company_name']} through Rutter Link yourself, or take the item id "
            f"from prod if a connection to that company already exists there, then record it "
            f"in CLAUDE.local.md as:\n\n    {cfg.get('item_id_setting', 'uae item')}: <item-id>")
    return found


def line_no():
    return int(uuid.uuid4().int % 2000000000)


class Client:
    def __init__(self, cfg):
        self.cfg = cfg
        self.token = load_token(cfg)
        self.odata = (f"{BASE}/{cfg['env']}/ODataV4/"
                      f"Company('{urllib.parse.quote(cfg['company_name'])}')")
        self.rutter = f"{BASE}/{cfg['env']}/api/Rutter/RutterAPI/v2.0/companies({cfg['company_id']})"
        self.std = f"{BASE}/{cfg['env']}/api/v2.0/companies({cfg['company_id']})"

    def call(self, method, url, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Content-Type", "application/json")
        if method == "PATCH":
            req.add_header("If-Match", "*")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{method} {e.code}: {e.read().decode()[:400]}")
        except (urllib.error.URLError, OSError) as e:
            raise RuntimeError(f"{method} network error: {e}")

    def action(self, name, body):
        """POST a bound action on this company's journal batch."""
        return self.call("POST", f"{self.rutter}/journalBatchActions({self.cfg['batch_id']})"
                                 f"/Microsoft.NAV.{name}", body)

    def read(self, line_id):
        return self.call("GET", f"{self.odata}/workflowGenJournalLines({line_id})")

    def count_lines(self):
        url = (f"{self.odata}/workflowGenJournalLines?$filter=journalBatchName eq "
               f"'{self.cfg['batch_name']}' and journalTemplateName eq 'GENERAL'&$select=id")
        return len(self.call("GET", urllib.parse.quote(url, safe=":/?&=$'")).get("value", []))

    def delete(self, ids):
        self.action("deleteLines", {"lineIdsJson": json.dumps(ids)})


def check_version(client):
    """The harness happily tests a stale build otherwise — the failure mode is a green run
    against code that was never installed."""
    cfg = client.cfg
    url = (f"{BASE}/{cfg['env']}/api/microsoft/automation/v2.0/"
           f"companies({cfg['company_id']})/extensions")
    for e in client.call("GET", url).get("value", []):
        if "AccountLink" in (e.get("displayName") or ""):
            got = (e.get("versionMajor"), e.get("versionMinor"),
                   e.get("versionBuild"), e.get("versionRevision"))
            dotted = ".".join(str(n) for n in got)
            if got < MIN_EXTENSION_VERSION:
                sys.exit(f"{cfg['label']}: AccountLink {dotted} is older than the required "
                         f"{'.'.join(str(n) for n in MIN_EXTENSION_VERSION)} — install the build first")
            print(f"  extension: AccountLink {dotted}")
            return
    sys.exit(f"{cfg['label']}: AccountLink is not installed")


def resolve(client):
    """Look up the ids the legacy path needs (it posts accountId, not a number)."""
    cfg, fx = client.cfg, {}
    wanted = list(cfg["gl"])
    for key in ("vat_default_account", "dim_default_account"):
        if cfg.get(key):
            wanted.append(cfg[key])
    accounts = client.call("GET", urllib.parse.quote(
        f"{client.std}/accounts?$filter=" + " or ".join(f"number eq '{n}'" for n in wanted),
        safe=":/?&=$'"))["value"]
    fx["gl_id"] = {a["number"]: a["id"] for a in accounts}
    missing = [n for n in wanted if n not in fx["gl_id"]]
    if missing:
        sys.exit(f"{cfg['label']}: G/L account(s) {missing} not found")
    banks = client.call("GET", urllib.parse.quote(
        f"{client.rutter}/bankAccounts?$filter=number eq '{cfg['bank']}'", safe=":/?&=$'"))["value"]
    if not banks:
        sys.exit(f"bank account {cfg['bank']} not found on {cfg['label']}")
    fx["bank_gl_id"] = banks[0]["accountId"]      # the G/L account behind the bank account
    return fx


def diff(name, a, b, accepted_map):
    """Compare every field of two lines. Fields listed in accepted_map for this shape may
    differ; anything else fails."""
    out = [(k, a.get(k), b.get(k))
           for k in sorted((set(a) | set(b)) - IGNORED) if a.get(k) != b.get(k)]
    accepted = accepted_map.get(name, set())
    unexpected = [d for d in out if d[0] not in accepted]
    if not out:
        print(f"  PASS  {name}")
    elif not unexpected:
        print(f"  PASS  {name}  (known: {', '.join(sorted(k for k, _, _ in out))})")
    else:
        print(f"  DIFF  {name}")
        for k, old, new in out:
            tag = "known " if k in accepted else ""
            print(f"        {tag}{k}: legacy={old!r}  al={new!r}")
    return not unexpected
