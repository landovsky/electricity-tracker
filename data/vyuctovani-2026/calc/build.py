import json, html
from collections import OrderedDict

d = json.load(open("out.json"))
scale = d["check"]["scale"]
SYM = {"Jiří": "△", "Kristina": "○", "Petr": "□", "prázdný dům": "·"}
LABEL = {"Jiří": "Jiří", "Kristina": "Kristina (Kristina, Edita, Marek)", "Petr": "Petr (Petr, Tereza, Bára, Johana)"}


def kc(x, dec=2):
    s = f"{x:,.{dec}f}".replace(",", " ").replace(".", ",")
    return s.replace(" ", " ")


def kwh(x):
    return kc(x, 1) if abs(x - round(x)) > 0.05 else kc(round(x), 0)


def dt(s):
    y, m, dd = s.split("-")
    return f"{int(dd)}. {int(m)}. {y}"


def dshort(s):
    y, m, dd = s[:10].split("-")
    return f"{int(dd)}.{int(m)}."


# ---- summary rows: consumption, fixed charges and totals kept apart
rows = d["rows"]
FAM = ("Jiří", "Kristina", "Petr")


def who(p):
    return f"<th scope=\"row\"><span class=\"sym\" aria-hidden=\"true\">{SYM[p]}</span>{LABEL[p]}</th>"


SLUG = {"Jiří": "jiri", "Kristina": "kristina", "Petr": "petr"}
BASE = "/vyuctovani/sucha/2026"   # app URLs: BASE (common page), BASE/<slug> (branch pages)


def link(p):
    return f"<th scope=\"row\"><span class=\"sym\" aria-hidden=\"true\">{SYM[p]}</span><a href=\"{BASE}/{SLUG[p]}\">{LABEL[p]}</a></th>"


summary = fixed_split = branch_links = branch_buttons = ""
members = d["members"]
for r in rows:
    summary += f"""<tr>{link(r['payer'])}
<td class="n">{kc(r['own_kc'])}</td>
<td class="n">{kc(r['empty_kc'])}</td>
<td class="n">{kc(r['fixed_kc'])}</td>
<td class="n total">{kc(r['total_kc'])}</td></tr>"""
    fixed_split += f"""<tr>{who(r['payer'])}<td class="n">⅓</td><td class="n total">{kc(r['fixed_kc'])}</td></tr>"""
    branch_links += f"""<a class="branch-card" href="{BASE}/{SLUG[r['payer']]}"><b><span class="sym" aria-hidden="true">{SYM[r['payer']]}</span>{r['payer']}</b>
<span class="muted">{LABEL[r['payer']].split(' (')[1].rstrip(')') if ' (' in LABEL[r['payer']] else r['payer']}</span>
<span class="n" style="text-align:left">{kc(r['total_kc'])} Kč</span><span class="btn">Otevřít rozpis rodiny →</span></a>"""
    branch_buttons += f"""<a class="btn" href="{BASE}/{SLUG[r['payer']]}"><span class="sym" aria-hidden="true">{SYM[r['payer']]}</span>{r['payer']} →</a>"""
tot_own = sum(r["own_kc"] for r in rows)
tot_empty = sum(r["empty_kc"] for r in rows)
tot = sum(r["total_kc"] for r in rows)
tot_cons = tot - sum(r["fixed_kc"] for r in rows)  # per-row rounding would show 4 604,98
tot_own = tot_cons - tot_empty
tot_fixed = sum(r["fixed_kc"] for r in rows)
tot_kwh = sum(r["kwh"] for r in rows) + (d["empty"]["VT"] + d["empty"]["NT"])

# ---- advances: paid - share = refund (+) / to pay (-)
import csv as _csv, os as _os
from collections import Counter
settle = ""
for r in rows:
    bal = r["balance_kc"]
    res = (f'vrací se <b class="total">{kc(bal)} Kč</b>' if bal > 0 else
           f'doplácí <b class="pay">{kc(-bal)} Kč</b>' if bal < 0 else "vyrovnáno")
    settle += f"""<tr>{who(r['payer'])}
<td class="n">{kc(r['advances_kc'])}</td><td class="n">{kc(r['total_kc'])}</td>
<td class="n">{'+' if bal > 0 else '−' if bal < 0 else ''}{kc(abs(bal))}</td><td class="result">{res}</td></tr>"""
adv = list(_csv.DictReader(open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "..", "advances.csv"), encoding="utf-8")))
cnt = Counter((a["payer"], a["kc"]) for a in adv)
span = {p: (min(a["date"] for a in adv if a["payer"] == p), max(a["date"] for a in adv if a["payer"] == p)) for p in FAM}
mon = lambda s: f"{int(s[5:7])}/{s[:4]}"
adv_note = ", ".join(f"{p} {n}× {kc(float(k), 0)} Kč ({mon(span[p][0])}–{mon(span[p][1])})"
                     for (p, k), n in sorted(cnt.items(), key=lambda x: FAM.index(x[0][0])))
tot_adv = sum(r["advances_kc"] for r in rows)
tot_bal = sum(r["balance_kc"] for r in rows)

# ---- ledger grouped by interval
groups = OrderedDict()
for x in d["detail"]:
    groups.setdefault((x["from"], x["to"]), []).append(x)



def ledger_rows(branch=None):
    """All intervals (common page) or only those the branch was present in, others greyed."""
    out = ""
    for (f, t), items in groups.items():
        vt = sum(i["VT"] for i in items)
        nt = sum(i["NT"] for i in items)
        if items[0]["payer"] == "prázdný dům":
            if branch is None:
                out += f"""<tr class="empty"><td class="when">{dshort(f)}–{dshort(t)}</td>
<td class="n">{kwh(vt)}</td><td class="n">{kwh(nt)}</td>
<td colspan="2"><span class="muted">prázdný dům → dělí se na třetiny</span></td></tr>"""
            continue
        if branch and not any(i["payer"] == branch for i in items):
            continue
        parts = ""
        for i in items:
            cls = " class='other'" if branch and i["payer"] != branch else ""
            parts += (f"<li{cls}><span class='sym' aria-hidden='true'>{SYM[i['payer']]}</span>"
                      f"<b>{LABEL[i['payer']].split(' (')[0]}</b> "
                      f"<span class='muted'>{html.escape(i['why'])}</span>"
                      f"<span class='n'>{kwh(i['VT'] + i['NT'])} kWh · {kc(i['Kc_tariff'] * scale)} Kč</span></li>")
        out += f"""<tr><td class="when">{dshort(f)}–{dshort(t)}</td>
<td class="n">{kwh(vt)}</td><td class="n">{kwh(nt)}</td>
<td colspan="2"><ul class="split">{parts}</ul></td></tr>"""
    return out


ledger = ledger_rows()

# ---- logbook transcription
import csv, os
ACT = {"check_in": "P", "check_out": "O", "reading": "odečet", "manual_kwh": "nabíjení"}
LOG = []
for r in csv.DictReader(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "events.csv"), encoding="utf-8")):
    if not ("2025-08-27" <= r["at"][:10] <= "2026-08-28"):
        continue
    y, m, dd = r["at"][:10].split("-")
    who = f'{r["visitor"] or "elektroměr"} {ACT[r["action"]]}'
    vt = f'{r["kwh"]} kWh' if r["action"] == "manual_kwh" else r["vt"].replace(".", ",")
    note = f'[{r["source"]}] {r["note"]}'.strip()
    LOG.append((f"{int(dd)}.{int(m)}.{y}", who, vt, r["nt"].replace(".", ","), r["garage"], html.escape(note)))
logrows = "".join(
    f"<tr><td class='when'>{a}</td><td>{b}</td><td class='n'>{c}</td><td class='n'>{e}</td><td class='n'>{g}</td><td class='muted'>{h}</td></tr>"
    for a, b, c, e, g, h in LOG)

p = d["prices"]
page = open("template.html").read()
for k, v in {
    "{{SUMMARY}}": summary, "{{BRANCH_LINKS}}": branch_links, "{{BRANCH_BUTTONS}}": branch_buttons, "{{FIXED_SPLIT}}": fixed_split,
    "{{TOTAL}}": kc(tot), "{{TOTAL_OWN}}": kc(tot_own), "{{TOTAL_EMPTY}}": kc(tot_empty), "{{TOTAL_CONS}}": kc(tot_cons), "{{TOTAL_FIXED}}": kc(tot_fixed), "{{TOTAL_KWH}}": kwh(tot_kwh),
    "{{LEDGER}}": ledger, "{{SETTLE}}": settle, "{{ADV_NOTE}}": adv_note,
    "{{TOTAL_ADV}}": kc(tot_adv), "{{TOTAL_BAL}}": ("+" if tot_bal > 0 else "−") + kc(abs(tot_bal)), "{{LOG}}": logrows,
    "{{P25VT}}": kc(p["2025"]["VT"], 3), "{{P25NT}}": kc(p["2025"]["NT"], 3),
    "{{P26VT}}": kc(p["2026"]["VT"], 3), "{{P26NT}}": kc(p["2026"]["NT"], 3),
    "{{SCALE}}": kc((scale - 1) * 100, 1), "{{EMPTY_KWH}}": kwh(d["empty"]["VT"] + d["empty"]["NT"]),
    "{{EMPTY_KC}}": kc(d["empty"]["Kc"] * scale),
}.items():
    page = page.replace(k, v)
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # data/vyuctovani-2026
head, body = page.split('<div class="wrap">', 1)


def document(body, title=None):
    """Full standalone document (served by the app, also opens from disk)."""
    h = head.strip() if not title else head.strip().replace("<title>Elektřina Suchá 2025/26</title>", f"<title>{title}</title>")
    return ('<!doctype html>\n<html lang="cs">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<meta name="robots" content="noindex, nofollow">\n' + h + '\n</head>\n<body>\n'
            + body.strip() + '\n</body>\n</html>\n')


open(os.path.join(OUT, "vyuctovani-sucha-2026.html"), "w").write(document('<div class="wrap">' + body))

# ---- branch pages: /vyuctovani/sucha/2026/<slug>
fixed_items = page[page.index("<!--FIXED_ITEMS-->"):page.index("<!--/FIXED_ITEMS-->") + len("<!--/FIXED_ITEMS-->")]
branch_tpl = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "template-branch.html")).read()


def spread(amounts, total):
    """Round to haléře so the parts add up exactly to total (largest remainder)."""
    cents = [a * 100 for a in amounts]
    base = [int(c) for c in cents]
    for i in sorted(range(len(cents)), key=lambda i: cents[i] - base[i], reverse=True)[:round(total * 100) - sum(base)]:
        base[i] += 1
    return [c / 100 for c in base]


for r in rows:
    p = r["payer"]
    ms = [dict(m) for m in members if m["payer"] == p]
    # members are rounded one by one; nudge the largest by the leftover haléře so they sum to the branch
    diff = round(r["own_kc"] * 100) - sum(round(m["kc"] * 100) for m in ms)
    for m in sorted(ms, key=lambda m: -m["kc"])[:abs(diff)]:
        m["kc"] = round(m["kc"] + (0.01 if diff > 0 else -0.01), 2)
    assert round(sum(m["kc"] for m in ms), 2) == round(r["own_kc"], 2), p
    factor = r["total_kc"] / r["own_kc"]   # fixed ⅓ + empty-house ⅓ folded into the kWh price
    folded = spread([m["kc"] * factor for m in ms], r["total_kc"])
    sep = fold = ""
    for m, f in zip(ms, folded):
        cells = f"""<th scope="row" class="member">{m['member']}</th>
<td class="n">{kwh(m['VT'])}</td><td class="n">{kwh(m['NT'])}</td><td class="n">{kwh(m['kwh'])}</td>"""
        sep += f"""<tr>{cells}<td class="n">{kc(m['kc'] / m['kwh'])}</td><td class="n">{kc(m['kc'])}</td></tr>"""
        fold += f"""<tr>{cells}<td class="n">{kc(f / m['kwh'])}</td><td class="n">{kc(f)}</td></tr>"""
    shared = round(r["fixed_kc"] + r["empty_kc"], 2)
    # even split: filled in by the page script; server-side values = everyone ticked (works without JS)
    ev = spread([shared / len(ms)] * len(ms), shared)
    even = ""
    for m, s in zip(ms, ev):
        tot_m = m["kc"] + s
        even += f"""<tr data-direct="{round(m['kc'] * 100)}" data-kwh="{m['kwh']}">
<th scope="row" class="member"><label class="pick"><input type="checkbox" checked>{m['member']}</label></th>
<td class="n">{kwh(m['VT'])}</td><td class="n">{kwh(m['NT'])}</td><td class="n">{kwh(m['kwh'])}</td>
<td class="n rate">{kc(tot_m / m['kwh'])}</td>
<td class="n"><span class="kc">{kc(tot_m)}</span><br><span class="muted">{kc(m['kc'])} + <span class="share">{kc(s)}</span></span></td></tr>"""
    sep += f"""<tr class="subtotal"><th scope="row">Přímá spotřeba celkem</th><td class="n">{kwh(r['VT'])}</td><td class="n">{kwh(r['NT'])}</td>
<td class="n">{kwh(r['kwh'])}</td><td class="n">{kc(r['own_kc'] / r['kwh'])}</td><td class="n">{kc(r['own_kc'])}</td></tr>
<tr><th scope="row">Prázdný dům ⅓</th><td></td><td></td><td class="n">{kwh(r['empty_kwh'])}</td><td></td><td class="n">{kc(r['empty_kc'])}</td></tr>
<tr><th scope="row">Pevné poplatky ⅓</th><td></td><td></td><td></td><td></td><td class="n">{kc(r['fixed_kc'])}</td></tr>"""
    bal = r["balance_kc"]
    n_adv = sum(1 for a in adv if a["payer"] == p)
    per = {a["kc"] for a in adv if a["payer"] == p}
    vals = {
        "{{COMMON_URL}}": BASE, "{{SYM}}": SYM[p], "{{BRANCH}}": p, "{{LABEL}}": LABEL[p],
        "{{ADVANCES}}": kc(r["advances_kc"]), "{{TOTAL}}": kc(r["total_kc"]),
        "{{RESULT_LABEL}}": "Vrací se rodině" if bal >= 0 else "Rodina doplácí",
        "{{RESULT_CLASS}}": "total" if bal >= 0 else "pay", "{{RESULT}}": kc(abs(bal)),
        "{{RESULT_NOTE}}": ("Přeplatek pošle společný rodinný účet zpět rodině." if bal >= 0
                            else "Nedoplatek pošle rodina na společný rodinný účet."),
        "{{ADV_NOTE}}": f"{n_adv}× {'/'.join(kc(float(k), 0) for k in sorted(per))} Kč ({mon(span[p][0])}–{mon(span[p][1])})",
        "{{OWN_KWH}}": kwh(r["kwh"]), "{{OWN_VT}}": kwh(r["VT"]), "{{OWN_NT}}": kwh(r["NT"]), "{{OWN_KC}}": kc(r["own_kc"]),
        "{{EMPTY_KWH}}": kwh(r["empty_kwh"]), "{{EMPTY_KC}}": kc(r["empty_kc"]), "{{FIXED_KC}}": kc(r["fixed_kc"]),
        "{{ALL_KWH}}": kwh(r["kwh"] + r["empty_kwh"]),
        "{{MEMBERS_SEP}}": sep, "{{MEMBERS_FOLD}}": fold, "{{MEMBERS_EVEN}}": even,
        "{{SHARED_CENTS}}": str(round(shared * 100)), "{{SHARED_KC}}": kc(shared), "{{FACTOR}}": kc(factor, 2),
        "{{AVG_OWN}}": kc(r["own_kc"] / r["kwh"]), "{{AVG_ALL}}": kc(r["total_kc"] / r["kwh"]),
        "{{FIXED_ITEMS}}": fixed_items, "{{LEDGER}}": ledger_rows(p),
    }
    bp = branch_tpl
    for k, v in vals.items():
        bp = bp.replace(k, v)
    assert "{{" not in bp, bp[bp.index("{{"):bp.index("{{") + 40]
    assert abs(sum(folded) - r["total_kc"]) < 0.005
    open(os.path.join(OUT, f"vyuctovani-sucha-2026-{SLUG[p]}.html"), "w").write(
        document(bp, f"Elektřina Suchá 2025/26 · {p}"))
assert "{{" not in body
print("ok", kc(tot))
