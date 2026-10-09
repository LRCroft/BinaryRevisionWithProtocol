#!/usr/bin/env python3
"""Analyze Phase 2 defect data"""

import json

with open('phase2_audit_data.json') as f:
	data = json.load(f)

defects = data['defects']
results = data['audit_results']

# Analyze by category
prod = [d for d in defects if d['category'] == 'PRODUCTION']
doc = [d for d in defects if d['category'] == 'DOCUMENTATION']

# Show production defect breakdown
reader_defects = [d for d in prod if 'Reader' in d['Title']]
writer_defects = [d for d in prod if 'Writer' in d['Title']]
frozen_defects = [d for d in prod if 'frozen' in d['Title']]

print('=' * 80)
print('PHASE 2 DEFECT ANALYSIS')
print('=' * 80)
print()

print('Total Defects by Category:')
print(f'  PRODUCTION: {len(prod)}')
print(f'    - Reader implementations: {len(reader_defects)} MISSING')
print(f'    - Writer implementations: {len(writer_defects)} MISSING')
print(f'    - Frozen vector support: {len(frozen_defects)} MISSING')
print(f'  DOCUMENTATION: {len(doc)}')
print()

# Show which languages have both reader AND writer
both = [r for r in results if r['has_reader'] and r['has_writer']]
readers_only = [r for r in results if r['has_reader'] and not r['has_writer']]
writers_only = [r for r in results if not r['has_reader'] and r['has_writer']]
neither = [r for r in results if not r['has_reader'] and not r['has_writer']]

print('Implementation Matrix:')
print()
print(f'✓✓ BOTH Reader + Writer ({len(both)}/31):')
for r in both:
	print(f'   {r["language"]}')
print()

print(f'✓✗ Writers Only - NO Reader ({len(writers_only)}/31):')
for r in writers_only:
	print(f'   {r["language"]}')
print()

print(f'✗✓ Readers Only - NO Writer ({len(readers_only)}/31):')
for r in readers_only:
	print(f'   {r["language"]}')
print()

print(f'✗✗ NEITHER Reader nor Writer ({len(neither)}/31):')
for r in neither:
	print(f'   {r["language"]}')
print()

# Interoperability analysis
print('=' * 80)
print('CROSS-LANGUAGE INTEROPERABILITY ASSESSMENT')
print('=' * 80)
print()

producers = [r['language'] for r in results if r['has_writer']]
consumers = [r['language'] for r in results if r['has_reader']]

print(f"Canonical Producers (writers): {len(producers)}")
for p in sorted(producers):
	print(f"  ✓ {p}")
print()

print(f"Potential Consumers (readers): {len(consumers)}")
for c in sorted(consumers):
	print(f"  ✓ {c}")
print()

# Calculate theoretical interop matrix
possible_interop_paths = len(producers) * len(consumers)
print(f"Theoretical interop paths: {len(producers)} producers × {len(consumers)} consumers = {possible_interop_paths}")
print()

# Defect severity breakdown
critical = len([d for d in defects if d['severity'] == 'CRITICAL'])
high = len([d for d in defects if d['severity'] == 'HIGH'])
medium = len([d for d in defects if d['severity'] == 'MEDIUM'])

print('Severity Breakdown:')
print(f'  CRITICAL: {critical} (reader/writer gaps blocking interop)')
print(f'  HIGH: {high} (writers missing for reference languages)')
print(f'  MEDIUM: {medium} (API/documentation issues)')
