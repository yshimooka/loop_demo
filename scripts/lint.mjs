// 依存ゼロの最小リンタ（デモ用）。src/ と test/ を検査する。
// goal.md の「lint clean」を、ネットワーク/インストール無しで再現するためのもの。
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const targets = ['src', 'test'];
const problems = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (['.js', '.mjs'].includes(extname(p))) checkFile(p);
  }
}

function checkFile(p) {
  const text = readFileSync(p, 'utf8');
  text.split('\n').forEach((line, i) => {
    const n = i + 1;
    if (/\bvar\b/.test(line)) problems.push(`${p}:${n} var は使わない（const/let）`);
    if (/[ \t]+$/.test(line)) problems.push(`${p}:${n} 行末の空白`);
    if (/console\.log/.test(line)) problems.push(`${p}:${n} console.log を残さない`);
    if (/\t/.test(line)) problems.push(`${p}:${n} タブではなくスペース`);
  });
  if (text.length > 0 && !text.endsWith('\n')) {
    problems.push(`${p} 末尾に改行が必要`);
  }
}

for (const t of targets) walk(t);

if (problems.length > 0) {
  console.error('lint NG:');
  for (const m of problems) console.error('  - ' + m);
  process.exit(1);
}
console.error('lint clean');
