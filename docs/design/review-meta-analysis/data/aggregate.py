#!/usr/bin/env python3
"""Aggregate the 9 extraction batches into stats for the review-of-reviews."""
import json, glob, re
from collections import Counter, defaultdict

RAW = sorted(glob.glob('b*.json'))
snapshots, resolutions = [], []
for f in RAW:
    d = json.load(open(f))
    snapshots.extend(d.get('snapshots', []))
    resolutions.extend(d.get('resolutions', []))

def stem_key(stem):
    m = re.match(r'(\d+)\.(\d+)\.(\d+)([a-z]?)', stem)
    return tuple(int(x) for x in m.groups()[:3]) + (ord(m.group(4)) if m.group(4) else 0,)

def vgroup(stem):
    return re.match(r'\d+\.\d+\.\d+', stem).group(0)

def sev_norm(s):
    s = (s or 'INFO').upper()
    if s.startswith('HIGH'): return 'HIGH'
    if s.startswith('MED'): return 'MED'
    if s.startswith('LOW'): return 'LOW'
    return 'INFO'

snaps = sorted(snapshots, key=lambda s: stem_key(s['stem']))
findings = []
for s in snaps:
    for fd in s.get('findings', []):
        fd = dict(fd)
        fd['_stem'], fd['_scope'], fd['_date'] = s['stem'], s.get('scope'), s.get('date')
        findings.append(fd)

reported  = [f for f in findings if f['status'] in ('reported', 'downgraded')]
dropped   = [f for f in findings if f['status'] in ('retracted', 'rejected')]
downgraded= [f for f in findings if f['status'] == 'downgraded']

out = {}
out['totals'] = {
    'batch_files': len(RAW), 'snapshots': len(snaps), 'resolutions': len(resolutions),
    'findings_all': len(findings), 'reported': len(reported),
    'retracted': len([f for f in findings if f['status']=='retracted']),
    'rejected':  len([f for f in findings if f['status']=='rejected']),
    'downgraded': len(downgraded),
}
out['severity'] = dict(Counter(sev_norm(f['severity']) for f in reported))
out['provenance'] = dict(Counter(str(f.get('provenance')) for f in reported))
out['scope'] = dict(Counter(str(s.get('scope')) for s in snaps))

# class stats
cls = {}
for f in reported:
    c = f['class']
    e = cls.setdefault(c, {'n':0,'sev':Counter(),'vgroups':set(),'stems':[],'prov':Counter()})
    e['n'] += 1
    e['sev'][sev_norm(f['severity'])] += 1
    e['vgroups'].add(vgroup(f['_stem']))
    e['stems'].append(f['_stem'] + ' ' + f['id'])
    e['prov'][str(f.get('provenance'))] += 1
out['classes'] = {
    c: {'n': e['n'], 'sev': dict(e['sev']), 'vgroups': sorted(e['vgroups'], key=stem_key),
        'n_vgroups': len(e['vgroups']), 'provenance': dict(e['prov']),
        'hm': e['sev'].get('HIGH',0)+e['sev'].get('MED',0)}
    for c, e in sorted(cls.items(), key=lambda kv: -kv[1]['n'])
}

# class x vgroup matrix (counts)
classes_sorted = [c for c in cls]
matrix = {c: Counter(vgroup(f['_stem']) for f in reported if f['class']==c) for c in classes_sorted}
vg_order = sorted({vgroup(s['stem']) for s in snaps}, key=stem_key)
out['class_x_vgroup'] = {c: {vg: matrix[c].get(vg,0) for vg in vg_order} for c in classes_sorted}
out['vgroup_order'] = vg_order

# per vgroup overview
grp = {}
for s in snaps:
    g = vgroup(s['stem'])
    e = grp.setdefault(g, {'snapshots':0,'stop_met':0,'stop_not_met':0,'scopes':Counter(),'dates':[]})
    e['snapshots'] += 1
    e['scopes'][str(s.get('scope'))] += 1
    e['dates'].append(s.get('date'))
    sr = s.get('stop_rule')
    if sr == 'met': e['stop_met'] += 1
    elif sr == 'not_met': e['stop_not_met'] += 1
for g in grp: grp[g]['dates'] = min(grp[g]['dates'])
grp_f = defaultdict(lambda: Counter())
for f in reported: grp_f[vgroup(f['_stem'])][sev_norm(f['severity'])] += 1
out['per_vgroup'] = {g: {**grp[g], 'scopes': dict(grp[g]['scopes']),
                         'severity': dict(grp_f[g])} for g in vg_order}

# areas
out['areas'] = dict(Counter(str(f.get('area')) for f in reported).most_common(20))

# cross-ref edges (explicit "same class as earlier finding" evidence)
edges, issue_refs = [], Counter()
for f in reported:
    for r in f.get('cross_refs') or []:
        m = re.search(r'0\.0\.\d+', r)
        if m: edges.append({'from': f['_stem'] + ' ' + f['id'], 'from_group': vgroup(f['_stem']), 'to_group': m.group(0), 'ref': r})
        elif r.startswith('#'): issue_refs[r] += 1
out['crossref_edges'] = edges
out['crossref_by_target'] = dict(Counter(e['to_group'] for e in edges))
out['issue_refs'] = dict(issue_refs)
# edges that point backwards (to an earlier version group) = real recurrence evidence
out['crossref_backward'] = [e for e in edges if stem_key(e['to_group']) < stem_key(e['from_group'])]

# reviewer coarse groups + dropped/downgraded rates
def reviewer_group(rv):
    rv = (rv or '').lower()
    if 'luna' in rv or 'gpt-6' in rv: return 'GPT-6-Luna'
    if 'flash' in rv: return 'GLM-5.3-Flash'
    if 'glm-5.3' in rv: return 'GLM-5.3-family'
    return 'other/unknown'
rev = defaultdict(lambda: {'snapshots':0,'findings':0,'retracted':0,'rejected':0,'downgraded':0})
for s in snaps:
    rg = reviewer_group(s.get('reviewer'))
    rev[rg]['snapshots'] += 1
for f in findings:
    rg = reviewer_group(next((s.get('reviewer') for s in snaps if s['stem']==f['_stem']), ''))
    rev[rg]['findings'] += 1
    if f['status']=='retracted': rev[rg]['retracted'] += 1
    if f['status']=='rejected': rev[rg]['rejected'] += 1
    if f['status']=='downgraded': rev[rg]['downgraded'] += 1
out['reviewer_groups'] = {k: dict(v) for k,v in rev.items()}

# resolutions
out['resolution_summary'] = [
    {'stem': r.get('stem'), 'dispositions': r.get('dispositions'),
     'follow_ups': r.get('follow_ups_recorded')} for r in resolutions]

# time trend: HIGH+MED reported per snapshot (chronological)
trend = []
for s in snaps:
    fs = [f for f in reported if f['_stem']==s['stem']]
    hm = sum(1 for f in fs if sev_norm(f['severity']) in ('HIGH','MED'))
    trend.append({'stem': s['stem'], 'date': s.get('date'), 'scope': s.get('scope'),
                  'n': len(fs), 'hm': hm, 'stop': s.get('stop_rule')})
out['trend'] = trend

with open('stats.json', 'w') as fh:
    json.dump(out, fh, indent=1, default=list)

# console summary
print("TOTALS", out['totals'])
print("SEV", out['severity'])
print("PROV", out['provenance'])
print("SCOPE", out['scope'])
print("\nCLASSES (n, HIGH/MED/LOW/INFO, #vgroups):")
for c, e in out['classes'].items():
    print(f"  {c:18s} n={e['n']:3d}  H{e['sev'].get('HIGH',0)}/M{e['sev'].get('MED',0)}/L{e['sev'].get('LOW',0)}/I{e['sev'].get('INFO',0)}  vgroups={e['n_vgroups']} {','.join(e['vgroups'])}")
print("\nAREAS", out['areas'])
print("\nCROSSREFS backward:", len(out['crossref_backward']), "by target:", out['crossref_by_target'])
print("ISSUE refs", out['issue_refs'])
print("\nPER VGROUP:")
for g in vg_order:
    e = out['per_vgroup'][g]
    print(f"  {g}: snaps={e['snapshots']} stop_met={e['stop_met']} not_met={e['stop_not_met']} sev={e['severity']}")
print("\nREVIEWER GROUPS:")
for k, v in out['reviewer_groups'].items(): print(' ', k, v)
print("\nTREND (stem: n findings, HIGH+MED, stop):")
for t in trend: print(f"  {t['stem']:8s} {t['date']} {str(t['scope']):8s} n={t['n']:3d} hm={t['hm']:2d} stop={t['stop']}")
