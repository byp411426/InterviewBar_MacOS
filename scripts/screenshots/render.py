#!/usr/bin/env python3
"""Render real SwiftUI views with isolated documentation fixtures, never personal data.
Only the build-directory source copies are adjusted for fixture state. Product sources
and the installed application remain unchanged. No model API calls or Keychain access.
"""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
work = root / 'build/documentation-screenshots'
work.mkdir(parents=True, exist_ok=True)
for source in (root / 'Sources').glob('*.swift'):
    shutil.copy2(source, work / source.name)

path = work / 'ModelConfiguration.swift'
s = path.read_text()
a = s.index('    static var current: ModelConfiguration {')
b = s.index('    var adapter:', a)
s = s[:a] + '''    static var current: ModelConfiguration { DocumentationFixtures.config }
    static var enabled: Bool { true }
    static var isConfigured: Bool { true }
''' + s[b:]
path.write_text(s)
path = work / 'ModelSettingsView.swift'
s = path.read_text().replace('@State private var selectedTab = 0', '@State private var selectedTab = DocumentationFixtures.tab')
path.write_text(s)
path = work / 'ModelUsageView.swift'
s = path.read_text().replace('@State private var records: [ModelUsageRecord] = []', '@State private var records: [ModelUsageRecord] = DocumentationFixtures.usage')
a = s.index('    private func refresh() async {')
s = s[:a] + '    private func refresh() async {}\n}\n'
path.write_text(s)
path = work / 'MailImportView.swift'
s = path.read_text().replace('@State private var analysisReady = false', '@State private var analysisReady = true')
s = s.replace('_draft = State(initialValue: MailParser.parse(capture.text, knownCompanies: store.events.map(\\.company)))', '_draft = State(initialValue: try! MailModel.decode(DocumentationFixtures.fields, source: capture.text))')
# Never run recognition, even if appearance behavior changes in the source view.
a = s.index('    func recognize(force: Bool = false) {')
b = s.index('    var body: some View {', a)
s = s[:a] + '    func recognize(force: Bool = false) {}\n' + s[b:]
path.write_text(s)
path = work / 'JourneyView.swift'
s = path.read_text().replace('@State private var quote = JourneyStats.nextEncouragement()', '@State private var quote = "每一次认真准备，都在积累下一次从容。"')
path.write_text(s)
command = ['swiftc', '-D', 'IMPORT_TEST', '-swift-version', '5', '-target', 'arm64-apple-macosx13.0']
command += [str(p) for p in sorted(work.glob('*.swift'))]
command += [str(root / 'scripts/screenshots/Render.swift'), '-o', str(work / 'render')]
for framework in ['AppKit', 'SwiftUI', 'UserNotifications', 'WebKit', 'ServiceManagement']:
    command += ['-framework', framework]
subprocess.run(command, check=True)
subprocess.run([str(work / 'render'), str(root / 'docs/images')], check=True)
