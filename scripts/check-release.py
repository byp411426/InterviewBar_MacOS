#!/usr/bin/env python3
"""Scan a clean release tree without printing matched private values.
This targeted preflight complements manual review; it is not a universal detector.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
patterns = {
    'API credential': re.compile(rb'\bsk-[A-Za-z0-9_-]{16,}'),
    'GitHub credential': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'personal absolute path': re.compile(rb'/' + rb'Users/(?!Shared(?:/|$))[^/\s"<>]+/'),
    'private Feishu sheet': re.compile(rb'https://[^\s"<>]*feishu\.cn/sheets/[A-Za-z0-9]{15,}'),
    'private webmail': re.compile(rb'[A-Za-z0-9_.+-]+@(?:163|126|qq|gmail|outlook)\.com'),
}
private_names = {'model-usage.json', 'model-usage.json.lock', 'widget-snapshot.json', 'events.json', 'application-sheet.json', 'application-results.json',
                 'unscheduled-events.json', 'import-history.json', 'import-transaction.json'}
errors = []
count = 0
for path in root.rglob('*'):
    rel = path.relative_to(root)
    if '.git' in rel.parts or not path.is_file():
        continue
    count += 1
    if path.name in private_names or path.name.startswith('.env'):
        errors.append((str(rel), 'private data file'))
    for label, pattern in patterns.items():
        if pattern.search(path.read_bytes()):
            errors.append((str(rel), label))
for filename, label in errors:
    print(f'FAIL: {filename}: {label}')
print(f'Checked {count} files; {len(errors)} findings.')
sys.exit(bool(errors))
