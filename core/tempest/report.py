#!/usr/bin/env python3
"""Render OUT/report.html from a tempest_test run: OUT/parts/*.subunit (one per suite), run.env, exclude-cos.txt."""
import collections
import datetime
import glob
import html
import io
import os
import re
import sys

import subunit
import testtools

OUT = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("OUT", "/work/out")
EXCLUDE = sys.argv[2] if len(sys.argv) > 2 else "/opt/tempest/exclude-cos.txt"

# skip reason -> category, first match wins
SKIP_CATS = [
    ("Upstream known bug", r"\bbug\b|launchpad|Bug #"),
    ("Policy tests not enabled", r"enforce_scope|scope|rbac|policy"),
    ("IPv6 testing disabled", r"ipv6"),
    ("API microversion outside the configured range", r"microversion"),
    ("Topology settings in tempest.conf", r"compute nodes|min_compute_nodes|multinode|resize|migration is not"),
    ("Unsupported by design", r"not support|unsupported|not implemented|does not implement"),
    ("Extension or feature not enabled", r"extension|not enabled|disabled|not available|feature"),
]
PROJECTS = {
    "manila_tempest_tests": "Manila", "neutron_tempest_plugin": "Neutron (plugin)",
    "cinder_tempest_plugin": "Cinder (plugin)", "octavia_tempest_plugin": "Octavia",
    "designate_tempest_plugin": "Designate", "heat_tempest_plugin": "Heat",
    "barbican_tempest_plugin": "Barbican", "watcher_tempest_plugin": "Watcher",
    "cyborg_tempest_plugin": "Cyborg", "ironic_tempest_plugin": "Ironic",
}


def project(tid):
    m = re.search(r"\(([^)]+)\)", tid)  # setUpClass (pkg.mod.Class)
    tid = m.group(1) if m else tid
    root = tid.split(".")[0]
    if root in PROJECTS:
        return PROJECTS[root]
    m = re.match(r"tempest\.(?:serial_tests\.)?api\.(\w+)", tid)
    if m:
        return "Tempest " + m.group(1).replace("_", " ")
    if re.match(r"tempest\.(?:serial_tests\.)?scenario", tid):
        return "Tempest scenario"
    return root


def load(path):
    tests = {}

    def on(t):
        d = t.get("details", {})

        def text(k):
            try:
                return d[k].as_text() if k in d else ""
            except Exception:
                return ""
        ts = t.get("timestamps") or [None, None]
        tests[t["id"]] = {"status": t["status"], "reason": text("reason").strip(),
                          "tb": text("traceback"), "start": ts[0], "end": ts[1]}
    with open(path, "rb") as f:
        stream = subunit.ByteStreamToStreamResult(io.BytesIO(f.read()), non_subunit_name="stdout")
    res = testtools.StreamToDict(on)
    res.startTestRun()
    stream.run(res)
    res.stopTestRun()
    return tests


def status(t):
    s = t["status"]
    return "fail" if s in ("fail", "uxsuccess") else "skip" if s == "skip" else "pass" if s in ("success", "xfail") else None


def read_env():
    env = {}
    try:
        for line in open(os.path.join(OUT, "run.env")):
            k, _, v = line.rstrip("\n").partition("=")
            env[k] = v
    except OSError:
        pass
    return env


def excludes():
    out, why = [], ""
    try:
        for line in open(EXCLUDE):
            line = line.strip()
            if line.startswith("#"):
                why = line.lstrip("# ") if not line.startswith("# COS Tempest") else why
            elif line:
                out.append((line, why))
    except OSError:
        pass
    return out


def dur(sec):
    sec = int(sec)
    h, m = divmod(sec // 60, 60)
    return f"{h} h {m} min" if h else f"{m} min" if m else f"{sec} s"


def fmt(n):
    return f"{n:,}"


def bar(p, s, f):
    tot = max(p + s + f, 1)
    return (f'<div class="bar" role="img" aria-label="{p} passed, {s} skipped, {f} failed">'
            f'<span class="p" style="width:{100*p/tot:.2f}%"></span><span class="s" style="width:{100*s/tot:.2f}%"></span>'
            f'<span class="f" style="width:{100*f/tot:.2f}%"></span></div>')


def main():
    e = html.escape
    parts = sorted(glob.glob(os.path.join(OUT, "parts", "*.subunit")))
    if not parts and os.path.exists(os.path.join(OUT, "results.subunit")):
        parts = [os.path.join(OUT, "results.subunit")]
    if not parts:
        sys.exit(f"no subunit results in {OUT}")
    env = read_env()
    suites, alltests = [], {}
    for p in parts:
        name = re.sub(r"^\d+-", "", os.path.basename(p)[:-len(".subunit")])
        tests = load(p)
        alltests.update(tests)
        c = collections.Counter(status(t) for t in tests.values())
        st = [t["start"] for t in tests.values() if t["start"]]
        en = [t["end"] for t in tests.values() if t["end"]]
        wall = (max(en) - min(st)).total_seconds() if st and en else 0
        suites.append((name, c["pass"], c["skip"], c["fail"], wall, min(st) if st else None, max(en) if en else None))

    tot = collections.Counter(status(t) for t in alltests.values())
    ran = tot["pass"] + tot["fail"]
    rate = 100.0 * tot["pass"] / ran if ran else 0.0
    classskips = sum(1 for k, t in alltests.items() if status(t) == "skip" and "setUpClass" in k)
    starts = [s[5] for s in suites if s[5]]
    ends = [s[6] for s in suites if s[6]]
    z = re.match(r"([+-])(\d\d)(\d\d)$", env.get("TZ_OFFSET", ""))  # date +%z of the host that ran make
    tz = datetime.timezone((-1 if z.group(1) == "-" else 1) * datetime.timedelta(hours=int(z.group(2)), minutes=int(z.group(3)))) \
        if z else datetime.timezone.utc
    span = ""
    if starts and ends:
        a, b = min(starts).astimezone(tz), max(ends).astimezone(tz)
        span = f'{a:%Y-%m-%d %H:%M} → {b:%Y-%m-%d %H:%M}' if a.date() != b.date() else f'{a:%Y-%m-%d %H:%M} → {b:%H:%M}'
        span += f' (UTC{tz.utcoffset(None).total_seconds()/3600:+g})'

    fails = sorted((k, t) for k, t in alltests.items() if status(t) == "fail")
    skips = [(k, t) for k, t in alltests.items() if status(t) == "skip"]
    cats = collections.OrderedDict((n, collections.Counter()) for n, _ in SKIP_CATS)
    cats["Other"] = collections.Counter()
    for _, t in skips:
        r = t["reason"] or "(no reason given)"
        cat = next((n for n, rx in SKIP_CATS if re.search(rx, r, re.I)), "Other")
        cats[cat][re.sub(r"[0-9a-f]{8}-[0-9a-f-]{27,}|\d+", "N", r)[:160]] += 1
    cats = sorted(((n, c) for n, c in cats.items() if c), key=lambda x: -sum(x[1].values()))
    proj = collections.defaultdict(collections.Counter)
    for k, t in alltests.items():
        s = status(t)
        if s:
            proj[project(k)][s] += 1
    excl = excludes()

    title = env.get("TITLE") or f"{env.get('VIP', 'COS')} Tempest"
    if tot["fail"] == 0:
        verdict, vtext = "No failures.", f"All {fmt(ran)} tests that ran passed."
    else:
        verdict = f"{tot['fail']} test{'s' if tot['fail'] != 1 else ''} failed."
        vtext = "Each failure is listed below with the end of its traceback."

    H = []
    w = H.append
    w(f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      f'<title>{e(title)}</title><style>{CSS}</style></head><body><div class="wrap">')
    m = re.match(r"CUBE_([^_]+)_", env.get("COS_IMAGE", ""))
    w('<header><span class="eyebrow">' + e(" · ".join(x for x in (
        f"CubeCOS {m.group(1)}" if m else "",
        f"OpenStack {env['OPENSTACK_RELEASE'].capitalize()}" if env.get("OPENSTACK_RELEASE") else "",
        f"Tempest {env['TEMPEST_VER']}" if env.get("TEMPEST_VER") else "") if x)) + '</span>')
    w(f'<h1>{e(title)}</h1><div class="meta">')
    for x in (f"Cluster {env['VIP']}" if env.get("VIP") else "", f"Image {env['COS_IMAGE']}" if env.get("COS_IMAGE") else "", f"Run {span}" if span else "",
              f"{len(suites)} suite{'s' if len(suites) != 1 else ''}",
              f"SUITE={env['SUITE']}" if env.get("SUITE") and not env.get("REGEX") else "",
              f"REGEX={env['REGEX']}" if env.get("REGEX") else ""):
        if x:
            w(f"<span>{e(x)}</span>")
    w("</div></header>")
    w('<section class="band" aria-label="Totals">'
      f'<div class="tile pass"><span class="n">{fmt(tot["pass"])}</span><span class="l">passed</span></div>'
      f'<div class="tile skip"><span class="n">{fmt(tot["skip"])}</span><span class="l">skipped</span></div>'
      f'<div class="tile fail"><span class="n">{fmt(tot["fail"])}</span><span class="l">failed</span></div>'
      f'<div class="tile"><span class="n">{rate:.2f}%</span><span class="l">pass rate of tests that ran</span></div></section>')
    w(f'<section class="verdict"><strong>{e(verdict)}</strong><p>{e(vtext)}</p></section>')

    w('<section><h2>Suites</h2><div class="scroll"><table><thead><tr><th>Suite</th><th class="num">Passed</th>'
      '<th class="num">Skipped</th><th class="num">Failed</th><th class="num">Wall time</th><th>Result</th></tr></thead><tbody>')
    for name, p, s, f, wall, _, _ in suites:
        w(f'<tr><td>{e(name)}</td><td class="num">{fmt(p)}</td><td class="num">{fmt(s)}</td><td class="num">{fmt(f)}</td>'
          f'<td class="num">{dur(wall)}</td><td>{bar(p, s, f)}</td></tr>')
    w("</tbody></table></div>")
    if classskips:
        w(f'<p class="note">Counts include class-level setup that skipped as a whole ({fmt(classskips)} of the {fmt(tot["skip"])} skips are whole test classes).</p>')
    w("</section>")

    if fails:
        w(f'<section><h2>Failures</h2><div class="stack">')
        for k, t in fails:
            tb = t["tb"].strip().splitlines()
            last = next((ln for ln in reversed(tb) if ln.strip()), "(no traceback)")
            w(f'<div class="fail-card"><span class="id">{e(k)}</span><div class="quote">{e(last)}</div>'
              f'<details><summary>Traceback</summary><div class="quote">{e(chr(10).join(tb[-60:]))}</div></details></div>')
        w("</div></section>")

    if skips:
        mx = max(sum(c.values()) for _, c in cats)
        w(f'<section><h2>Why {fmt(len(skips))} tests skipped</h2><div class="cats">')
        for n, c in cats:
            v = sum(c.values())
            top = "; ".join(f"{r} ({k})" for r, k in c.most_common(3))
            w(f'<div class="cat"><span class="name">{e(n)}</span><div class="track"><span style="width:{100*v/mx:.1f}%"></span></div>'
              f'<span class="v">{fmt(v)}</span><span class="why">{e(top)}</span></div>')
        w("</div></section>")

    w('<section><h2>Coverage by project</h2><div class="scroll"><table><thead><tr><th>Project</th><th class="num">Passed</th>'
      '<th class="num">Skipped</th><th class="num">Failed</th><th>Result</th></tr></thead><tbody>')
    for n, c in sorted(proj.items(), key=lambda x: -(x[1]["pass"] + x[1]["skip"] + x[1]["fail"])):
        w(f'<tr><td>{e(n)}</td><td class="num">{fmt(c["pass"])}</td><td class="num">{fmt(c["skip"])}</td>'
          f'<td class="num">{fmt(c["fail"])}</td><td>{bar(c["pass"], c["skip"], c["fail"])}</td></tr>')
    w("</tbody></table></div></section>")

    if excl:
        w(f'<section><h2>Excluded before the run</h2><p>{len(excl)} test patterns are excluded in the harness, each with its reason in '
          f'<code>exclude-cos.txt</code>. They are not counted above.</p><div class="scroll"><table><thead><tr><th>Pattern</th>'
          '<th>Reason</th></tr></thead><tbody>')
        for rx, why in excl:
            w(f'<tr><td class="mono">{e(rx)}</td><td>{e(why)}</td></tr>')
        w("</tbody></table></div></section>")

    w('<p class="note">Per-test listing: <a href="results.html">results.html</a> · JUnit: <code>results.xml</code> · '
      'raw: <code>results.subunit</code></p></div></body></html>')
    with open(os.path.join(OUT, "report.html"), "w") as f:
        f.write("".join(H))
    print(f"report: {os.path.join(OUT, 'report.html')} ({tot['pass']} passed, {tot['skip']} skipped, {tot['fail']} failed)")


# system fonts only: the report must render offline
CSS = """
:root{--bg:#f5f7ff;--surface:#fff;--ink:#151a33;--muted:#5b6385;--line:#dfe4f7;--primary:#4c68f9;--primary-soft:#e7ecff;
--pass:#1f9d6b;--skip:#8a93b8;--fail:#d6453d;--warn:#c9850a;
--body:ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0f1224;--surface:#171b33;--ink:#e8ebfa;--muted:#a2a9cc;
--line:#2a3052;--primary:#8a9dff;--primary-soft:#232a52;--pass:#3fc48d;--skip:#7d86ad;--fail:#ff6b61;--warn:#e8a93a;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#0f1224;--surface:#171b33;--ink:#e8ebfa;--muted:#a2a9cc;--line:#2a3052;--primary:#8a9dff;
--primary-soft:#232a52;--pass:#3fc48d;--skip:#7d86ad;--fail:#ff6b61;--warn:#e8a93a;color-scheme:dark}
*{box-sizing:border-box}body{background:var(--bg);color:var(--ink);font:15px/1.6 var(--body);margin:0}
.wrap{max-width:1040px;margin:0 auto;padding:32px 16px 64px;display:flex;flex-direction:column;gap:40px}
h1,h2{margin:0;letter-spacing:-.01em}h1{font-size:clamp(28px,4.4vw,40px);font-weight:800}h2{font-size:22px;margin-bottom:12px}
p{margin:0;max-width:72ch}.eyebrow{font:600 12px/1 var(--body);letter-spacing:.09em;text-transform:uppercase;color:var(--primary)}
.meta{color:var(--muted);display:flex;flex-wrap:wrap;gap:6px 18px;font-size:14px}header{display:flex;flex-direction:column;gap:12px}
code,.mono{font-family:var(--mono);font-size:.88em}
.band{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}
.tile{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:16px 18px;display:flex;flex-direction:column}
.tile .n{font-size:32px;font-weight:800;font-variant-numeric:tabular-nums}.tile .l{color:var(--muted);font-size:13px}
.tile.pass .n{color:var(--pass)}.tile.skip .n{color:var(--skip)}.tile.fail .n{color:var(--fail)}
.verdict{background:var(--primary-soft);border-radius:12px;padding:16px 18px;display:flex;flex-direction:column;gap:6px}
.verdict strong{font-size:18px}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--surface)}
table{border-collapse:collapse;width:100%;font-size:14px;min-width:620px}
th,td{padding:9px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
th{font-weight:600;color:var(--muted);font-size:12px;letter-spacing:.06em;text-transform:uppercase;background:var(--bg)}
tr:last-child td{border-bottom:0}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.mono{word-break:break-all}
.bar{display:flex;height:10px;border-radius:5px;overflow:hidden;background:var(--line);min-width:120px}.bar span{display:block;height:100%}
.bar .p{background:var(--pass)}.bar .s{background:var(--skip)}.bar .f{background:var(--fail)}
.stack{display:flex;flex-direction:column;gap:12px}
.fail-card{background:var(--surface);border:1px solid var(--line);border-left:4px solid var(--fail);border-radius:10px;padding:14px 16px;
display:flex;flex-direction:column;gap:8px;min-width:0}
.fail-card .id{font-family:var(--mono);font-size:12.5px;word-break:break-all;color:var(--muted)}
summary{cursor:pointer;color:var(--primary);font-size:13px}
.quote{font-family:var(--mono);font-size:12.5px;background:var(--bg);border-radius:8px;padding:10px 12px;overflow-x:auto;white-space:pre-wrap;word-break:break-word}
.cats{display:flex;flex-direction:column;gap:10px}
.cat{display:grid;grid-template-columns:minmax(0,16rem) minmax(0,1fr) 3.5rem;gap:12px;align-items:center}
.cat .name{font-weight:600;font-size:14px}.cat .track{height:12px;background:var(--line);border-radius:6px;overflow:hidden}
.cat .track span{display:block;height:100%;background:var(--skip)}.cat .v{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
.cat .why{grid-column:1/-1;color:var(--muted);font-size:13px;margin-top:-4px;word-break:break-word}
.note{color:var(--muted);font-size:13px}a{color:var(--primary)}
@media (max-width:720px){.band{grid-template-columns:repeat(2,minmax(0,1fr))}.cat{grid-template-columns:minmax(0,1fr) 3rem}
.cat .track{grid-column:1/-1;order:3}}
"""

if __name__ == "__main__":
    main()
