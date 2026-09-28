import { TASK_ID, type Task } from './model';

// A pretend shell in ~/src/acme-web — just enough git to show heap. matching
// the checked-out branch to a task.

export interface TermResult {
  lines: string[];
  /** New branch to focus, or undefined when the command doesn't switch. */
  branch?: string;
  clear?: boolean;
}

const HELP = [
  'Things this pretend shell understands:',
  '  git switch -c <branch>     (or git checkout -b <branch>)',
  '  git switch <branch>        git branch        git status',
  '  clear',
  'Put a task id in the branch name — e.g. APP-112-flaky-sync-test.',
];

export function runCommand(input: string, current: string | null, tasks: Task[]): TermResult {
  const cmd = input.trim().replace(/\s+/g, ' ');
  const head = current ?? 'main';
  if (!cmd) return { lines: [] };
  if (cmd === 'help' || cmd === 'git help' || cmd === 'git') return { lines: HELP };
  if (cmd === 'clear') return { lines: [], clear: true };
  if (cmd === 'git status') return { lines: [`On branch ${head}`, 'nothing to commit, working tree clean'] };
  if (cmd === 'git branch') {
    const names = new Set(['main', ...tasks.filter((t) => t.branch).map((t) => t.branch!), head]);
    return { lines: [...names].sort().map((b) => (b === head ? `* ${b}` : `  ${b}`)) };
  }
  const sw = cmd.match(/^git (?:switch(?: -c| --create)?|checkout(?: -b)?) ([\w./-]+)$/);
  if (sw) {
    const branch = sw[1];
    const creating = / -c | --create | -b /.test(` ${cmd} `);
    const lines = [creating ? `Switched to a new branch '${branch}'` : `Switched to branch '${branch}'`];
    const id = branch.toUpperCase().match(TASK_ID)?.[1];
    const task = id ? tasks.find((t) => t.id === id) : undefined;
    if (task) lines.push(`heap. ⎇ matched ${task.id} — ${task.title}`);
    else if (id) lines.push(`heap. no task ${id} on this board — the branch stays unmatched`);
    else lines.push('heap. no task id in this branch name — nothing to match');
    return { lines, branch };
  }
  if (cmd.startsWith('git ')) return { lines: [`git: '${cmd.slice(4).split(' ')[0]}' isn’t simulated here. Try \`help\`.`] };
  return { lines: [`${cmd.split(' ')[0]}: command not found — this is a pretend shell. Try \`help\`.`] };
}
