import type { UsageProvider, UsageWindow } from '../mock';

/* Shared sample data for the mock island (hero, demo, features). */

export const USAGE_PROVIDERS: UsageProvider[] = [
  { id: 'claude', title: 'Claude', windows: [{ label: '5h', pct: 12, reset: '4h43m' }, { label: '7d', pct: 83, reset: '1d5h' }] },
  { id: 'codex', title: 'Codex', windows: [{ label: '5h', pct: 41, reset: '2h10m' }, { label: '7d', pct: 64, reset: '3d2h' }] },
];

export const MODEL_WEEKLY: UsageWindow[] = [{ label: 'Fable', pct: 32, reset: '1d5h' }];
