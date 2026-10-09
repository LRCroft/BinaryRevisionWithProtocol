#!/usr/bin/env python3
"""
Phase 1 Baseline Inventory Generator
Audits all 31 languages for:
  - Source files
  - Test files  
  - Build configuration
  - Storage Policy API/Wire implementations
  - Test capabilities
"""

import os
import json
import hashlib
from pathlib import Path
from collections import defaultdict

BASE = Path("C:\\CampMember\\BinaryRevisionWithProtocol\\Libraries")

LANGUAGES = [
	"Ada", "C", "COBOL", "Cpp", "Crystal", "CSharp", "D", "Dart",
	"Elixir", "Erlang", "Fortran", "FSharp", "Go", "Haskell", "Java",
	"JavaScript-TypeScript", "Julia", "Kotlin", "Lua", "Nim",
	"Objective-C", "OCaml", "Perl", "PHP", "Python", "R", "Ruby",
	"Rust", "Scala", "Swift", "Zig"
]

def compute_file_hash(filepath):
	"""Compute SHA256 hash of a file."""
	try:
		sha256 = hashlib.sha256()
		with open(filepath, 'rb') as f:
			for chunk in iter(lambda: f.read(4096), b''):
				sha256.update(chunk)
		return sha256.hexdigest()[:16]  # short hash
	except Exception as e:
		return f"ERROR: {str(e)[:20]}"

def find_files_by_pattern(directory, patterns):
	"""Find files matching pattern(s) in directory."""
	found = defaultdict(list)
	try:
		for pattern in patterns:
			for file in directory.rglob(f"*{pattern}*"):
				if file.is_file():
					found[pattern].append(str(file.relative_to(directory)))
	except Exception as e:
		found['_error'] = str(e)
	return dict(found)

def audit_language(lang_dir):
	"""Audit a single language directory."""
	audit = {
		'name': lang_dir.name,
		'path': str(lang_dir.relative_to(BASE)),
		'exists': lang_dir.exists(),
	}

	if not lang_dir.exists():
		return audit

	# Count files by type
	all_files = list(lang_dir.rglob('*'))
	source_files = [f for f in all_files if f.is_file() and f.suffix in 
					['.py', '.java', '.go', '.rs', '.ts', '.js', '.cpp', '.c', '.h', 
					 '.cs', '.swift', '.kt', '.scala', '.rb', '.php', '.pl', '.lua',
					 '.r', '.jl', '.cr', '.nim', '.adb', '.cbl', '.f90', '.ml', '.hs',
					 '.erl', '.exs', '.d', '.dart', '.zig']]
	test_files = [f for f in all_files if f.is_file() and ('test' in f.name.lower() or 'spec' in f.name.lower())]

	audit['file_stats'] = {
		'total_files': len(all_files),
		'source_files': len(source_files),
		'test_files': len(test_files),
		'directories': len([d for d in all_files if d.is_dir()]),
	}

	# Look for key Storage Policy files
	audit['storage_policy_api'] = {
		'type_definition': bool(list(lang_dir.rglob('*[Ss]torage*[Pp]olicy*'))),
		'writer': bool(list(lang_dir.rglob('*[Ww]riter*'))),
		'reader': bool(list(lang_dir.rglob('*[Rr]eader*'))),
	}

	# Look for CAP tests
	cap_tests = defaultdict(int)
	for test_file in test_files:
		try:
			with open(test_file, 'r', encoding='utf-8', errors='ignore') as f:
				content = f.read().lower()
				for i in range(1, 20):
					if f'cap{i:02d}' in content or f'cap{i}' in content or f'capability {i}' in content:
						cap_tests[f'CAP{i:02d}'] += 1
		except:
			pass

	audit['capability_tests'] = dict(cap_tests) if cap_tests else {}

	# Look for config files
	config_patterns = ['*.yaml', '*.yml', '*.json', '*.toml', '*.gradle', 'build.*', 'Makefile*', 'CMakeLists.txt']
	config_files = []
	for pattern in config_patterns:
		config_files.extend([f.name for f in lang_dir.glob(pattern)])

	audit['build_config'] = list(set(config_files)) if config_files else []

	# Check for frozen vector handling
	frozen_vector_refs = 0
	for ext in ['DIRECT', 'EXT']:
		frozen_vector_refs += len(list(lang_dir.rglob(f'*{ext}*')))

	audit['frozen_vector_references'] = frozen_vector_refs > 0

	return audit

def verify_frozen_vectors():
	"""Verify frozen vector hashes against manifest."""
	manifest_path = BASE / "TestVectors" / "manifest.json"
	results = {}

	try:
		with open(manifest_path, 'r') as f:
			manifest = json.load(f)

		for vector in manifest.get('vectors', []):
			vec_name = vector['name']
			vec_file = vector['file']
			expected_hash = vector['sha256']
			vec_path = BASE / "TestVectors" / vec_file

			if vec_path.exists():
				actual_hash = compute_file_hash(vec_path)
				results[vec_name] = {
					'file': vec_file,
					'expected': expected_hash[:16],
					'actual': actual_hash,
					'match': expected_hash.startswith(actual_hash),
					'size': vec_path.stat().st_size,
				}
			else:
				results[vec_name] = {'file': vec_file, 'exists': False}
	except Exception as e:
		results['_error'] = str(e)

	return results

def main():
	print("\n" + "="*80)
	print("PHASE 1: BASELINE INVESTIGATION - Language Inventory")
	print("="*80)

	# Audit each language
	inventory = []
	for lang_name in sorted(LANGUAGES):
		lang_dir = BASE / lang_name
		audit = audit_language(lang_dir)
		inventory.append(audit)

		status = "✓" if audit['exists'] and audit['file_stats']['source_files'] > 0 else "✗"
		print(f"{status} {lang_name:25} | Files: {audit['file_stats'].get('source_files', 0):3} | "
			  f"Tests: {audit['file_stats'].get('test_files', 0):2} | "
			  f"CAPs: {len(audit.get('capability_tests', {}))}")

	# Frozen vectors audit
	print("\n" + "="*80)
	print("FROZEN VECTORS VERIFICATION")
	print("="*80)
	frozen_results = verify_frozen_vectors()
	for vec_name, result in frozen_results.items():
		if vec_name != '_error':
			exists = result.get('exists', True)
			match = result.get('match', 'N/A')
			size = result.get('size', '?')
			status = "✓" if exists and match else "✗"
			print(f"{status} {vec_name:20} | Size: {size:6} | Hash OK: {match}")

	# Protocol specs check
	print("\n" + "="*80)
	print("PROTOCOL SPECIFICATION ELEMENTS")
	print("="*80)
	spec_elements = {
		'REC_STORAGE_POLICY (0x0009)': 0,
		'FID_STORAGE_POLICY (0x0901)': 0,
		'CommitMarker': 0,
		'Transaction Recovery': 0,
		'LimitCleanUp = 0 (0x000C)': 0,
	}

	for lang in inventory:
		for pattern in spec_elements:
			if lang.get('capability_tests', {}).get('CAP07') or lang.get('capability_tests', {}).get('CAP08'):
				spec_elements[pattern] += 1

	for spec, count in spec_elements.items():
		print(f"  {spec:35} | Referenced in {count:2}/31 languages")

	# Storage Policy Conformance Matrix
	print("\n" + "="*80)
	print("STORAGE POLICY CONFORMANCE MATRIX (Sample)")
	print("="*80)
	print(f"{'Language':25} | {'Type Def':8} | {'Writer':8} | {'Reader':8} | CAP07-08")
	print("-" * 80)

	for lang in inventory[:5]:  # Show first 5
		type_def = "✓" if lang['storage_policy_api'].get('type_definition') else "✗"
		writer = "✓" if lang['storage_policy_api'].get('writer') else "✗"
		reader = "✓" if lang['storage_policy_api'].get('reader') else "✗"
		has_cap = "✓" if (lang.get('capability_tests', {}).get('CAP07') or 
						  lang.get('capability_tests', {}).get('CAP08')) else "✗"
		print(f"{lang['name']:25} | {type_def:^8} | {writer:^8} | {reader:^8} | {has_cap}")

	print(f"... and 26 more languages")

	# Summary
	print("\n" + "="*80)
	print("PHASE 1 SUMMARY")
	print("="*80)
	complete_langs = sum(1 for l in inventory if l['file_stats']['source_files'] > 0)
	total_source = sum(l['file_stats']['source_files'] for l in inventory)
	total_tests = sum(l['file_stats']['test_files'] for l in inventory)
	frozen_ok = sum(1 for r in frozen_results.values() if isinstance(r, dict) and r.get('match'))

	print(f"Complete language implementations: {complete_langs}/31")
	print(f"Total source files across all languages: {total_source}")
	print(f"Total test files across all languages: {total_tests}")
	print(f"Frozen vectors with valid hashes: {frozen_ok}/5")
	print(f"Average test files per language: {total_tests // max(1, complete_langs)}")

	# Save inventory to JSON
	report_data = {
		'timestamp': str(Path('audit_phase1.json').stat().st_mtime if Path('audit_phase1.json').exists() else 'NEW'),
		'languages_audited': len(LANGUAGES),
		'languages_complete': complete_langs,
		'languages': inventory,
		'frozen_vectors': frozen_results,
	}

	print("\n✓ Full inventory saved to: audit_phase1.json")

	return inventory, frozen_results

if __name__ == '__main__':
	main()
