#!/usr/bin/env python3
"""parse-policy.py — Minimal shoofly.yaml parser (standard library only).

Reads a shoofly.yaml file, resolves imports recursively, and outputs merged
rules as JSON to stdout.

Usage:
    parse-policy.py <path/to/shoofly.yaml>
    parse-policy.py -    (read from stdin, base_dir = cwd)

Exit codes:
    0 = success (JSON on stdout)
    1 = fatal error (details on stderr)

Imports (local paths and HTTPS URLs) are resolved before the current file's
rules. Max import depth: 3. Failed imports are skipped with a warning on
stderr — they do not cause the overall parse to fail.
"""

import json
import os
import re
import sys
import urllib.request

MAX_IMPORT_DEPTH = 3


def _parse_scalar(val):
    """Parse a YAML scalar value (bool, int, null, or string)."""
    v = val.strip()
    if not v or v.lower() in ('null', '~'):
        return None
    if v.lower() == 'true':
        return True
    if v.lower() == 'false':
        return False
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    try:
        return int(v)
    except ValueError:
        pass
    return v


def _indent(line):
    return len(line) - len(line.lstrip(' '))


class _Parser:
    """State-machine YAML parser for the shoofly.yaml subset."""

    def __init__(self, text):
        self.lines = text.splitlines()
        self.i = 0

    # ── Internal helpers ───────────────────────────────────────────────────────

    def _skip_blanks(self):
        """Advance past blank lines and comment lines."""
        while self.i < len(self.lines):
            s = self.lines[self.i].strip()
            if s and not s.startswith('#'):
                return
            self.i += 1

    def _parse_scalar_list(self, parent_indent):
        """Consume a YAML list of scalars at indent > parent_indent."""
        items = []
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            ind = _indent(line)
            if ind <= parent_indent:
                break
            m = re.match(r'^\s+-\s+(.*)', line)
            if not m:
                break
            items.append(_parse_scalar(m.group(1)))
            self.i += 1
        return items

    def _parse_detect(self, parent_indent):
        """Consume a detect: map at indent > parent_indent."""
        detect = {
            'url_contains': [],
            'text_contains': [],
            'action': None,
            'path_matches': [],
        }
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            if _indent(line) <= parent_indent:
                break
            m = re.match(r'^(\s+)(\w+)\s*:\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            ki = len(m.group(1))
            key, val = m.group(2), m.group(3).strip()
            if ki <= parent_indent:
                break
            self.i += 1
            if key in ('url_contains', 'text_contains', 'path_matches'):
                detect[key] = self._parse_scalar_list(ki)
            elif key == 'action':
                detect['action'] = _parse_scalar(val) if val else None
            # unknown detect keys: skip
        return detect

    def _parse_alert(self, parent_indent):
        """Consume an alert: map at indent > parent_indent."""
        alert = {'webhook': None, 'message': None}
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            if _indent(line) <= parent_indent:
                break
            m = re.match(r'^(\s+)(\w+)\s*:\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            ki = len(m.group(1))
            key, val = m.group(2), m.group(3).strip()
            if ki <= parent_indent:
                break
            self.i += 1
            if key == 'webhook':
                alert['webhook'] = _parse_scalar(val)
            elif key == 'message':
                alert['message'] = _parse_scalar(val)
        return alert

    def _parse_rule_body(self, rule, body_indent):
        """Consume rule fields at exactly body_indent, modifying rule in-place."""
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            ind = _indent(line)
            if ind < body_indent:
                break
            m = re.match(r'^(\s+)(\w+)\s*:\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            ki = len(m.group(1))
            key, val = m.group(2), m.group(3).strip()
            if ki < body_indent:
                break
            if ki > body_indent:
                # Deeper than body — stray line, skip
                self.i += 1
                continue
            self.i += 1
            if key == 'id':
                rule['id'] = _parse_scalar(val)
            elif key == 'name':
                rule['name'] = _parse_scalar(val)
            elif key == 'log':
                rule['log'] = _parse_scalar(val)
            elif key == 'block':
                rule['block'] = _parse_scalar(val)
            elif key == 'detect':
                rule['detect'] = self._parse_detect(ki)
            elif key == 'alert':
                rule['alert'] = self._parse_alert(ki)
            # unknown rule keys: skip

    def _parse_rules(self, parent_indent):
        """Consume a rules: list at indent > parent_indent."""
        rules = []
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            ind = _indent(line)
            if ind <= parent_indent:
                break
            stripped = line.strip()
            if not stripped.startswith('-'):
                self.i += 1
                continue
            m = re.match(r'^(\s+)-\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            list_indent = len(m.group(1))
            inline = m.group(2).strip()
            body_indent = list_indent + 2
            self.i += 1

            rule = {
                'id': None,
                'name': None,
                'detect': {
                    'url_contains': [],
                    'text_contains': [],
                    'action': None,
                    'path_matches': [],
                },
                'log': False,
                'block': False,
                'alert': None,
            }

            # Apply the key:value from the inline portion of "  - id: foo"
            if inline:
                km = re.match(r'^(\w+)\s*:\s*(.*)', inline)
                if km:
                    k, v = km.group(1), km.group(2).strip()
                    if k == 'id':
                        rule['id'] = _parse_scalar(v)
                    elif k == 'name':
                        rule['name'] = _parse_scalar(v)
                    elif k == 'log':
                        rule['log'] = _parse_scalar(v)
                    elif k == 'block':
                        rule['block'] = _parse_scalar(v)

            # Parse remaining body fields
            self._parse_rule_body(rule, body_indent)
            rules.append(rule)
        return rules

    def _parse_threat_body(self, rule, body_indent):
        """Consume threat entry fields at exactly body_indent."""
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            ind = _indent(line)
            if ind < body_indent:
                break
            m = re.match(r'^(\s+)(\w+)\s*:\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            ki = len(m.group(1))
            key, val = m.group(2), m.group(3).strip()
            if ki < body_indent:
                break
            if ki > body_indent:
                self.i += 1
                continue
            self.i += 1
            if key == 'id':
                rule['id'] = _parse_scalar(val)
            elif key == 'name':
                rule['name'] = _parse_scalar(val)
            elif key == 'category':
                rule['category'] = _parse_scalar(val)
            elif key == 'severity':
                sev = _parse_scalar(val)
                # Map severity to block/log: HIGH/MEDIUM → block, LOW → log
                if sev in ('HIGH', 'MEDIUM'):
                    rule['block'] = True
                    rule['log'] = True
                else:
                    rule['log'] = True
            elif key == 'action_basic':
                pass  # informational
            elif key == 'action_advanced':
                act = _parse_scalar(val)
                if act == 'block':
                    rule['block'] = True
            elif key == 'patterns':
                # Skip the patterns sub-list
                self._parse_scalar_list(ki)
            elif key == 'description':
                pass  # skip
            # unknown keys: skip

    def _parse_threats(self, parent_indent):
        """Consume a threats: list, converting each threat to a rule."""
        rules = []
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            ind = _indent(line)
            if ind <= parent_indent:
                break
            stripped = line.strip()
            if not stripped.startswith('-'):
                self.i += 1
                continue
            m = re.match(r'^(\s+)-\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            list_indent = len(m.group(1))
            inline = m.group(2).strip()
            body_indent = list_indent + 2
            self.i += 1

            rule = {
                'id': None,
                'name': None,
                'detect': {
                    'url_contains': [],
                    'text_contains': [],
                    'action': None,
                    'path_matches': [],
                },
                'log': False,
                'block': False,
                'alert': None,
            }

            if inline:
                km = re.match(r'^(\w+)\s*:\s*(.*)', inline)
                if km:
                    k, v = km.group(1), km.group(2).strip()
                    if k == 'id':
                        rule['id'] = _parse_scalar(v)
                    elif k == 'name':
                        rule['name'] = _parse_scalar(v)

            self._parse_threat_body(rule, body_indent)
            rules.append(rule)
        return rules

    # ── Public entry point ─────────────────────────────────────────────────────

    def parse(self):
        """Parse the full shoofly.yaml document."""
        result = {'version': 1, 'imports': [], 'rules': []}
        while self.i < len(self.lines):
            self._skip_blanks()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            if _indent(line) != 0:
                self.i += 1
                continue
            m = re.match(r'^(\w+)\s*:\s*(.*)', line)
            if not m:
                self.i += 1
                continue
            key, val = m.group(1), m.group(2).strip()
            self.i += 1
            if key == 'version':
                result['version'] = _parse_scalar(val)
            elif key == 'imports':
                result['imports'] = self._parse_scalar_list(0)
            elif key == 'rules':
                result['rules'] = self._parse_rules(0)
            elif key == 'threats':
                result['rules'] = self._parse_threats(0)
            # unknown top-level keys: skip
        return result


# ── I/O helpers ────────────────────────────────────────────────────────────────

def _load_url(url):
    try:
        req = urllib.request.Request(
            url, headers={'User-Agent': 'shoofly-policy/1.0'}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:  # noqa: S310
            return resp.read().decode('utf-8')
    except Exception as exc:
        print(f"WARNING: failed to load URL {url}: {exc}", file=sys.stderr)
        return None


def _load_file(path):
    try:
        with open(path, 'r') as fh:
            return fh.read()
    except Exception as exc:
        print(f"WARNING: failed to load file {path}: {exc}", file=sys.stderr)
        return None


# ── Import resolution ──────────────────────────────────────────────────────────

def _collect_rules(parsed, base_dir, depth=0):
    """Recursively collect rules: imported rules first, then this file's rules."""
    all_rules = []
    for imp in parsed.get('imports', []):
        if not imp:
            continue
        imp = str(imp)
        if depth >= MAX_IMPORT_DEPTH:
            print(
                f"WARNING: max import depth {MAX_IMPORT_DEPTH} reached, "
                f"skipping: {imp}",
                file=sys.stderr,
            )
            continue
        if imp.startswith('http://') or imp.startswith('https://'):
            text = _load_url(imp)
            imp_base = base_dir
        else:
            abs_path = imp if os.path.isabs(imp) else os.path.join(base_dir, imp)
            text = _load_file(abs_path)
            imp_base = os.path.dirname(os.path.abspath(abs_path))
        if text is None:
            continue
        try:
            imported = _Parser(text).parse()
        except Exception as exc:
            print(f"WARNING: failed to parse {imp}: {exc}", file=sys.stderr)
            continue
        all_rules.extend(_collect_rules(imported, imp_base, depth + 1))
    all_rules.extend(parsed.get('rules', []))
    return all_rules


def _normalize_rule(rule):
    detect = rule.get('detect') or {}
    alert = rule.get('alert')
    if alert and not (alert.get('webhook') or alert.get('message')):
        alert = None
    return {
        'id': rule.get('id'),
        'name': rule.get('name'),
        'detect': {
            'url_contains': list(detect.get('url_contains') or []),
            'text_contains': list(detect.get('text_contains') or []),
            'action': detect.get('action'),
            'path_matches': list(detect.get('path_matches') or []),
        },
        'log': bool(rule.get('log', False)),
        'block': bool(rule.get('block', False)),
        'alert': alert,
    }


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: parse-policy.py <shoofly.yaml>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    if path == '-':
        text = sys.stdin.read()
        base_dir = os.getcwd()
    else:
        if not os.path.exists(path):
            print(f"ERROR: file not found: {path}", file=sys.stderr)
            sys.exit(1)
        base_dir = os.path.dirname(os.path.abspath(path))
        text = _load_file(path)
        if text is None:
            sys.exit(1)

    try:
        parsed = _Parser(text).parse()
    except Exception as exc:
        print(f"ERROR: parse failed: {exc}", file=sys.stderr)
        sys.exit(1)

    rules = [_normalize_rule(r) for r in _collect_rules(parsed, base_dir)]
    output = {'version': parsed.get('version', 1), 'rules': rules}
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
