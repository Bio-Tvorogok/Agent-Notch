import React from 'react';
import {C, MONO, SANS, clamp01} from '../lib';

/* Generic terminal windows for the cold open (not app UI). Stage coordinates. */
export type Term = {x: number; y: number; w: number; h: number; kind: 'claude' | 'codex'; title: string; speed: number; seed: number; prompt?: boolean};
export const TERMS: Term[] = [
  {x: -480, y: 110, w: 1040, h: 660, kind: 'claude', title: 'claude — wedding-app — fix/upload-compress', speed: 4, seed: 1},
  {x: 1500, y: 130, w: 960, h: 620, kind: 'codex', title: 'codex — hexhaven — release-notes', speed: 5, seed: 2},
  {x: 380, y: 520, w: 1060, h: 680, kind: 'codex', title: 'codex — wedding-app — CONF-360', speed: 99, seed: 3, prompt: true},
  {x: 900, y: 200, w: 980, h: 640, kind: 'claude', title: 'claude — agents-village — v6/notch', speed: 3, seed: 4},
  {x: -330, y: 820, w: 1000, h: 640, kind: 'claude', title: 'claude — wedding-app — docs/upload', speed: 6, seed: 5},
  {x: 1660, y: 780, w: 820, h: 660, kind: 'codex', title: 'codex — wedding-app — audit-b10', speed: 4, seed: 6},
  {x: 520, y: 1140, w: 1040, h: 700, kind: 'claude', title: 'claude — wedding-app — feat/guest-tg', speed: 5, seed: 7},
  {x: 100, y: 300, w: 900, h: 620, kind: 'codex', title: 'codex — wedding-app — codex-job · schemas', speed: 3, seed: 8},
  {x: 1220, y: 1180, w: 1000, h: 660, kind: 'codex', title: 'codex — hexhaven — balance-pass', speed: 6, seed: 9},
  {x: -460, y: 1270, w: 980, h: 640, kind: 'claude', title: 'claude — wedding-app — code-reviewer', speed: 4, seed: 10},
  {x: 720, y: 640, w: 960, h: 620, kind: 'claude', title: 'claude — wedding-app — test-writer', speed: 3, seed: 11},
  {x: 1420, y: 430, w: 1000, h: 640, kind: 'claude', title: 'claude — agents-village — og-images', speed: 5, seed: 12},
  {x: 180, y: 920, w: 1000, h: 660, kind: 'codex', title: 'codex — wedding-app — migrations', speed: 4, seed: 13},
  {x: 980, y: 880, w: 900, h: 600, kind: 'codex', title: 'codex — hexhaven — lint', speed: 3, seed: 14},
];
export const PROMPT_I = 2;
export const termAppear = (i: number) => 4 + i * 8;

type Line = {t: string; c: string};
const CL: Line[] = [
  {t: '⏺ Read(apps/api/src/routes/upload.ts)', c: '#e8e8ea'},
  {t: '  ⎿  Read 214 lines', c: '#8a8a90'},
  {t: '⏺ Bash(pnpm --filter api test)', c: '#e8e8ea'},
  {t: '  ⎿  PASS src/services/media.test.ts (38)', c: '#4cd964'},
  {t: '✻ Thinking…', c: '#e0583a'},
  {t: '⏺ Edit(src/services/media.ts)', c: '#e8e8ea'},
  {t: '  ⎿  Updated with 12 additions, 3 removals', c: '#8a8a90'},
  {t: '⏺ Task(Explore · routes)', c: '#e8e8ea'},
  {t: '⏺ Grep("compress", path: apps/)', c: '#e8e8ea'},
  {t: '  ⎿  Found 9 files', c: '#8a8a90'},
  {t: '⏺ Bash(git diff --stat)', c: '#e8e8ea'},
  {t: '   4 files changed, 61 insertions(+)', c: '#8a8a90'},
  {t: '✻ Cogitating… (esc to interrupt)', c: '#e0583a'},
  {t: '  ⎿  FAIL src/upload.test.ts › size limit', c: '#ff6b5e'},
];
const CX: Line[] = [
  {t: '• Running pnpm lint', c: '#e8e8ea'},
  {t: '  └ 0 problems', c: '#8a8a90'},
  {t: '• Explored', c: '#e8e8ea'},
  {t: '  └ Read schema.prisma, migrations/', c: '#8a8a90'},
  {t: '• Edited src/db/schema.ts (+18 -4)', c: '#e8e8ea'},
  {t: '• Running vitest run related', c: '#e8e8ea'},
  {t: '  └ ✓ 42 passed', c: '#4cd964'},
  {t: '• Updated Plan', c: '#e8e8ea'},
  {t: '  └ ✔ Inspect release notes', c: '#8a8a90'},
  {t: '◦ Working (12s • esc to interrupt)', c: '#8f9bff'},
  {t: '  └ error: retrying the same call', c: '#ff6b5e'},
];
const rnd = (s: number) => {
  const x = Math.sin(s * 9301 + 49297) * 233280;
  return x - Math.floor(x);
};
const lineAt = (kind: Term['kind'], seed: number, n: number): Line => {
  const pool = kind === 'claude' ? CL : CX;
  return pool[Math.floor(rnd(seed * 131 + n * 7.3) * pool.length)];
};

const LH = 30;
export const Terminal: React.FC<{t: Term; f: number; cursorOn?: boolean}> = ({t, f, cursorOn = true}) => {
  const bodyH = t.h - 52 - 28;
  const rows = Math.floor(bodyH / LH);
  const n = t.prompt ? 0 : Math.max(0, Math.floor(f / t.speed)) + 30;
  const lines: Line[] = [];
  if (!t.prompt) for (let k = n - rows + 1; k <= n; k++) lines.push(lineAt(t.kind, t.seed, k));
  return (
    <div style={{position: 'absolute', left: t.x, top: t.y, width: t.w, height: t.h, borderRadius: 20, overflow: 'hidden', background: 'rgba(24,24,28,0.97)',
      boxShadow: '0 30px 80px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.12)'}}>
      <div style={{height: 52, background: '#2a2a2f', display: 'flex', alignItems: 'center', padding: '0 22px', position: 'relative', borderBottom: '1px solid #000'}}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => <div key={c} style={{width: 18, height: 18, borderRadius: 9, background: c, marginRight: 12}} />)}
        <div style={{position: 'absolute', left: 0, right: 0, textAlign: 'center', fontFamily: SANS, fontSize: 22, fontWeight: 600, color: '#a8a8ae'}}>{t.title}</div>
      </div>
      <div style={{padding: '14px 24px', fontFamily: MONO, fontSize: 21, lineHeight: `${LH}px`, whiteSpace: 'pre'}}>
        {t.prompt ? (
          <>
            {[
              {t: '• Ran pnpm --filter web build', c: '#e8e8ea'},
              {t: '  └ dist/ is stale, cleaning before rebuild', c: '#8a8a90'},
              {t: '• Edited vite.config.ts (+3 -1)', c: '#e8e8ea'},
              {t: '', c: ''},
            ].map((l, i) => <div key={i} style={{color: l.c}}>{l.t || ' '}</div>)}
            <div style={{marginTop: 6, border: `2px solid ${C.yellow}`, borderRadius: 12, padding: '14px 20px', background: 'rgba(255,179,31,0.06)'}}>
              <div style={{color: '#f2f2f5', fontWeight: 600}}>Allow command?</div>
              <div style={{color: C.red, fontWeight: 700, fontSize: 26, margin: '6px 0'}}>  $ rm -rf dist build</div>
              <div style={{color: '#d0d0d5'}}>  › y  yes      n  no{'  '}<span style={{background: cursorOn ? '#e8e8ea' : 'transparent'}}> </span></div>
            </div>
          </>
        ) : (
          lines.map((l, i) => <div key={i} style={{color: l.c}}>{l.t}</div>)
        )}
      </div>
    </div>
  );
};

export const termRect = (i: number) => TERMS[i];
export const springIn = (f: number) => clamp01(f / 8);
