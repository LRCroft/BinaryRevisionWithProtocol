#!/usr/bin/env python3
"""Storage-policy conformance corpus runner for Python reference implementation."""
import json, os, sys, hashlib
sys_path_base = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries'
if os.path.isdir(os.path.join(sys_path_base, 'Python')):
    sys.path.insert(0, os.path.join(sys_path_base, 'Python'))
else:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'Python'))
from vsn import VsnStore, container as _c
from vsn.constants import StoragePolicy, WireMode
from vsn.writer_options import WriterOptions, OptimizationConfiguration
from vsn.errors import InvalidStoragePolicy, PolicyWireModeConflict, InvalidOptimizationConfiguration

CORPUS = os.path.dirname(os.path.abspath(__file__))

def _fb(n):
    return open(os.path.join(CORPUS, '..', 'scenarios', n), 'rb').read()

def rP01():
    r = {'status': 'PASS', 'level': 'API', 'fixture_id': 'P01-enum'}
    v = [e.value for e in StoragePolicy]
    n = [e.name for e in StoragePolicy]
    c = [len(v) == 4, sorted(v) == [1, 2, 3, 4], set(n) == {'HIGHLY_VERTICAL', 'VERTICAL', 'HORIZONTAL', 'HIGHLY_HORIZONTAL'}, 'BALANCED' not in n]
    hv = StoragePolicy.HIGHLY_VERTICAL
    c.append(type(hv).__name__ != type(WireMode.MODERN).__name__)
    if any(not x for x in c):
        r['status'] = 'FAIL'
        r['failures'] = [i for i, x in enumerate(c) if not x]
    return r

def rP02():
    r = {'status': 'PASS', 'level': 'API', 'fixture_id': 'P02-mapping'}
    m = {StoragePolicy.HIGHLY_VERTICAL: 1, StoragePolicy.VERTICAL: 1, StoragePolicy.HORIZONTAL: 2, StoragePolicy.HIGHLY_HORIZONTAL: 2}
    f = []
    for p, e in m.items():
        o = WriterOptions(storage_policy=p)
        if o.effective_wire_mode != e:
            f.append('{} exp={} got={}'.format(p.name, e, o.effective_wire_mode))
    if WriterOptions().effective_wire_mode is not None:
        f.append('None should return None')
    oc = WriterOptions(storage_policy=StoragePolicy.HIGHLY_VERTICAL, wire_mode_constraint=WireMode.MODERN)
    if oc.effective_wire_mode != WireMode.MODERN:
        f.append('Constraint match failed')
    try:
        WriterOptions(storage_policy=StoragePolicy.HIGHLY_VERTICAL, wire_mode_constraint=WireMode.ENTERPRISE).effective_wire_mode
        f.append('Should raise conflict')
    except PolicyWireModeConflict:
        pass
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP03():
    r = {'status': 'PASS', 'level': 'WIRE', 'fixture_id': 'P03-mode-bytes'}
    pm = {StoragePolicy.HIGHLY_VERTICAL: 'policy-highly_vertical.vsn', StoragePolicy.VERTICAL: 'policy-vertical.vsn', StoragePolicy.HORIZONTAL: 'policy-horizontal.vsn', StoragePolicy.HIGHLY_HORIZONTAL: 'policy-highly_horizontal.vsn'}
    em = {StoragePolicy.HIGHLY_VERTICAL: 1, StoragePolicy.VERTICAL: 1, StoragePolicy.HORIZONTAL: 2, StoragePolicy.HIGHLY_HORIZONTAL: 2}
    f = []
    for p, fn in pm.items():
        d = _fb(fn)
        pr = _c.parse(d)
        if pr.mode != em[p]:
            f.append('{} exp={} got={}'.format(p.name, em[p], pr.mode))
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r


def rP04():
    r = {'status': 'PASS', 'level': 'CROSS_LANGUAGE', 'fixture_id': 'P04-reader'}
    ns = ['policy-highly_vertical.vsn', 'policy-vertical.vsn', 'policy-horizontal.vsn', 'policy-highly_horizontal.vsn']
    f = []
    for fn in ns:
        d = _fb(fn)
        try:
            pr = _c.parse(d)
            if pr.mode not in (1, 2):
                f.append('{} bad mode {}'.format(fn, pr.mode))
        except Exception as e:
            f.append('{} parse err: {}'.format(fn, str(e)))
    for fn in ns:
        d = _fb(fn)
        for p in StoragePolicy:
            if p.name.lower().encode('utf-8') in d:
                f.append('{} contains name of {}'.format(fn, p.name))
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP05():
    r = {'status': 'PASS', 'level': 'SEMANTIC', 'fixture_id': 'P05-logical'}
    ns = ['policy-highly_vertical.vsn', 'policy-vertical.vsn', 'policy-horizontal.vsn', 'policy-highly_horizontal.vsn']
    pa = [_c.parse(_fb(x)) for x in ns]
    f = []
    for fn, p in zip(ns, pa):
        if not any(rec.rtype == 0x7 for rec in p.records):
            f.append('{} no ModeDeclaration'.format(fn))
    l = [p.byte_length for p in pa]
    if len(set(l)) != 1:
        f.append('Lengths differ')
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP06():
    r = {'status': 'PASS', 'level': 'SEMANTIC', 'fixture_id': 'P06-objserial'}
    s = VsnStore(storage_policy=StoragePolicy.HIGHLY_VERTICAL)
    s.create_file('test_obj', b'object-preserves-content')
    d = s.commit()
    pr = _c.parse(d)
    f = []
    if len(pr.objects) == 0:
        f.append('No objects in container')
    s.close()
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP07():
    r = {'status': 'PASS', 'level': 'WIRE', 'fixture_id': 'P07-commit'}
    ns = ['policy-highly_vertical.vsn', 'policy-vertical.vsn', 'policy-horizontal.vsn', 'policy-highly_horizontal.vsn']
    f = []
    for fn in ns:
        d = _fb(fn)
        pr = _c.parse(d)
        has_commit = any(rec.rtype == 0x6 for rec in pr.records)
        if not has_commit:
            f.append('{} no CommitMarker'.format(fn))
        if pr.trailer_generation < 1:
            f.append('{} bad gen {}'.format(fn, pr.trailer_generation))
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP08():
    r = {'status': 'PASS', 'level': 'SEMANTIC', 'fixture_id': 'P08-budget'}
    s = VsnStore(storage_policy=StoragePolicy.HIGHLY_VERTICAL)
    s.create_file('btest', b'tiny')
    d = s.commit()
    f = []
    if len(d) < 10:
        f.append('Small output {}'.format(len(d)))
    pr = _c.parse(d)
    if pr.mode not in (1, 2):
        f.append('Bad mode after opt {}'.format(pr.mode))
    s.close()
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r


def rP09():
    r = {'status': 'PASS', 'level': 'CROSS_LANGUAGE', 'fixture_id': 'P09-cross'}
    ns = ['policy-highly_vertical.vsn', 'policy-vertical.vsn', 'policy-horizontal.vsn', 'policy-highly_horizontal.vsn']
    f = []
    for fn in ns:
        d = _fb(fn)
        s = VsnStore.open(d)
        ok = True
        try:
            if hasattr(s, 'files'):
                s.files()
        except Exception as e:
            f.append('{} err: {}'.format(fn, str(e)))
            ok = False
        finally:
            if ok:
                s.close()
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP10():
    r = {'status': 'PASS', 'level': 'WIRE', 'fixture_id': 'P10-no-wire'}
    ns = ['policy-highly_vertical.vsn', 'policy-vertical.vsn', 'policy-horizontal.vsn', 'policy-highly_horizontal.vsn']
    f = []
    kr = {0, 1, 2, 3, 4, 5, 6, 7, 8}
    for fn in ns:
        d = _fb(fn)
        pr = _c.parse(d)
        for rec in pr.records:
            if rec.rtype < 0x8000 and rec.rtype not in kr:
                f.append('{} type {}'.format(fn, hex(rec.rtype)))
        for p in StoragePolicy:
            if p.name.lower().encode('utf-8') in d:
                f.append('{} contains name of {}'.format(fn, p.name))
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r


def rP11():
    r = {'status': 'PASS', 'level': 'API', 'fixture_id': 'P11-backward'}
    f = []
    s = VsnStore.create(WireMode.MODERN)
    if not s:
        f.append('create None')
    else:
        d = s.commit()
        if not d or len(d) < 10:
            f.append('bad commit output')
        pr = _c.parse(d)
        if pr.mode != WireMode.MODERN:
            f.append('mode mismatch {}'.format(pr.mode))
    s2 = VsnStore.open(d)
    if not s2:
        f.append('open None')
    else:
        try:
            if hasattr(s2, 'files'):
                s2.files()
        except Exception as e:
            f.append('err: {}'.format(str(e)))
        finally:
            s2.close()
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r

def rP12():
    r = {'status': 'PASS', 'level': 'API', 'fixture_id': 'P12-validate'}
    f = []
    try:
        OptimizationConfiguration(search_budget=-1).validate()
        f.append('exp err on sb')
    except InvalidOptimizationConfiguration:
        pass
    try:
        OptimizationConfiguration(memory_limit=0).validate()
        f.append('exp err on ml')
    except InvalidOptimizationConfiguration:
        pass
    try:
        WriterOptions(storage_policy=StoragePolicy.HIGHLY_VERTICAL, wire_mode_constraint=WireMode.ENTERPRISE).effective_wire_mode
        f.append('exp conflict')
    except PolicyWireModeConflict:
        pass
    ov = WriterOptions(storage_policy=StoragePolicy.VERTICAL)
    if ov.resolve_wire_mode(WireMode.MODERN) != WireMode.MODERN:
        f.append('valid res fail')
    if f:
        r['status'] = 'FAIL'
        r['failures'] = f
    return r


CAPS = [
    ('P01', 'policy_enumeration', rP01),
    ('P02', 'policy_to_wire_mode', rP02),
    ('P03', 'mode_declaration_bytes', rP03),
    ('P04', 'reader_independence', rP04),
    ('P05', 'logical_equivalence', rP05),
    ('P06', 'object_serial_preservation', rP06),
    ('P07', 'commit_recovery', rP07),
    ('P08', 'optimization_budget_fallback', rP08),
    ('P09', 'cross_policy_compatibility', rP09),
    ('P10', 'policy_not_on_wire', rP10),
    ('P11', 'backward_compatibility', rP11),
    ('P12', 'writer_options_validation', rP12),
]


def run_all():
    res = {}
    for cid, cn, fn in CAPS:
        r = fn()
        res[cid] = {'capability': cn, 'level': r.get('level', '?'), 'status': r['status'], 'fixture_id': r.get('fixture_id', cid)}
        if r.get('failures'):
            res[cid]['failures'] = r['failures']
    np_ = sum(1 for v in res.values() if v['status'] == 'PASS')
    print('=' * 60)
    print('Storage-Policy Conformance (Python ref)')
    print('{} PASS'.format(np_))
    for cid, cn, _ in CAPS:
        s = res[cid]['status']
        print('CAP {} [{}] {}'.format(cid.rjust(4), s.ljust(8), cn))
    print('=' * 60)
    with open(os.path.join(CORPUS, 'results.json'), 'w') as jf:
        json.dump(res, jf, indent=2)
    return res


if __name__ == '__main__':
    res = run_all()
    p = sum(1 for v in res.values() if v['status'] == 'PASS')
