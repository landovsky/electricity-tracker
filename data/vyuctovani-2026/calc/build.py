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


consumption = summary = fixed_split = ""
members = d["members"]
for r in rows:
    fam = r["payer"] in FAM
    summary += f"""<tr>{who(r['payer'])}
<td class="n">{kc(r['own_kc'])}</td>
<td class="n">{kc(r['empty_kc'])}</td>
<td class="n">{kc(r['fixed_kc'])}</td>
<td class="n total">{kc(r['total_kc'])}</td></tr>"""
    fixed_split += f"""<tr>{who(r['payer'])}<td class="n">⅓</td><td class="n total">{kc(r['fixed_kc'])}</td></tr>"""
    ms = [m for m in members if m["payer"] == r["payer"]]
    consumption += f"""<tbody class="branch"><tr class="branch-head"><th colspan="5" scope="rowgroup">
<span class="sym" aria-hidden="true">{SYM[r['payer']]}</span>{r['payer']}</th></tr>"""
    for m in ms:
        consumption += f"""<tr><th scope="row" class="member">{m['member']}</th>
<td class="n">{kwh(m['VT'])}</td><td class="n">{kwh(m['NT'])}</td><td class="n">{kwh(m['kwh'])}</td>
<td class="n">{kc(m['kc'])}</td></tr>"""
    consumption += f"""<tr class="subtotal"><th scope="row">Přímá spotřeba celkem</th>
<td class="n">{kwh(r['VT'])}</td><td class="n">{kwh(r['NT'])}</td><td class="n">{kwh(r['kwh'])}</td>
<td class="n total">{kc(r['own_kc'])}</td></tr></tbody>"""
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

ledger = ""
for (f, t), items in groups.items():
    vt = sum(i["VT"] for i in items)
    nt = sum(i["NT"] for i in items)
    if items[0]["payer"] == "prázdný dům":
        ledger += f"""<tr class="empty"><td class="when">{dshort(f)}–{dshort(t)}</td>
<td class="n">{kwh(vt)}</td><td class="n">{kwh(nt)}</td>
<td colspan="2"><span class="muted">prázdný dům → dělí se na třetiny</span></td></tr>"""
        continue
    parts = ""
    for i in items:
        parts += (f"<li><span class='sym' aria-hidden='true'>{SYM[i['payer']]}</span>"
                  f"<b>{LABEL[i['payer']].split(' (')[0]}</b> "
                  f"<span class='muted'>{html.escape(i['why'])}</span>"
                  f"<span class='n'>{kwh(i['VT'] + i['NT'])} kWh · {kc(i['Kc_tariff'] * scale)} Kč</span></li>")
    ledger += f"""<tr><td class="when">{dshort(f)}–{dshort(t)}</td>
<td class="n">{kwh(vt)}</td><td class="n">{kwh(nt)}</td>
<td colspan="2"><ul class="split">{parts}</ul></td></tr>"""

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
    "{{SUMMARY}}": summary, "{{CONSUMPTION}}": consumption, "{{FIXED_SPLIT}}": fixed_split,
    "{{TOTAL}}": kc(tot), "{{TOTAL_OWN}}": kc(tot_own), "{{TOTAL_EMPTY}}": kc(tot_empty), "{{TOTAL_CONS}}": kc(tot_cons), "{{TOTAL_FIXED}}": kc(tot_fixed), "{{TOTAL_KWH}}": kwh(tot_kwh),
    "{{LEDGER}}": ledger, "{{SETTLE}}": settle, "{{ADV_NOTE}}": adv_note,
    "{{TOTAL_ADV}}": kc(tot_adv), "{{TOTAL_BAL}}": ("+" if tot_bal > 0 else "−") + kc(abs(tot_bal)), "{{LOG}}": logrows,
    "{{P25VT}}": kc(p["2025"]["VT"], 3), "{{P25NT}}": kc(p["2025"]["NT"], 3),
    "{{P26VT}}": kc(p["2026"]["VT"], 3), "{{P26NT}}": kc(p["2026"]["NT"], 3),
    "{{SCALE}}": kc((scale - 1) * 100, 1), "{{EMPTY_KWH}}": kwh(d["empty"]["VT"] + d["empty"]["NT"]),
    "{{EMPTY_KC}}": kc(d["empty"]["Kc"] * scale),
}.items():
    page = page.replace(k, v)
# full standalone document (served by the app at /vyuctovani/sucha/2026, also opens from disk)
head, body = page.split('<div class="wrap">', 1)
page = ('<!doctype html>\n<html lang="cs">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '<meta name="robots" content="noindex, nofollow">\n' + head.strip() + '\n</head>\n<body>\n<div class="wrap">'
        + body.rstrip() + '\n</body>\n</html>\n')
open("vyuctovani-sucha-2026.html", "w").write(page)
print("ok", kc(tot))
