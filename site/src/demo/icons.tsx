interface IconProps {
  size?: number;
}

const base = (size: number) => ({
  width: size,
  height: size,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
  style: { display: 'inline-block', verticalAlign: '-1px' },
});

export function BranchIcon({ size = 14 }: IconProps) {
  return (
    <svg {...base(size)}>
      <circle cx="6" cy="5" r="2" />
      <circle cx="6" cy="19" r="2" />
      <circle cx="18" cy="7" r="2" />
      <path d="M6 7v10M18 9c0 5-6 4-11 8" />
    </svg>
  );
}

export function SearchIcon({ size = 14 }: IconProps) {
  return (
    <svg {...base(size)}>
      <circle cx="11" cy="11" r="7" />
      <path d="M20 20l-3.5-3.5" />
    </svg>
  );
}

export function BoardIcon({ size = 20 }: IconProps) {
  return (
    <svg {...base(size)}>
      <rect x="3.5" y="4" width="7.5" height="16" rx="2" />
      <rect x="13" y="4" width="7.5" height="16" rx="2" />
    </svg>
  );
}

export function WeekIcon({ size = 20 }: IconProps) {
  return (
    <svg {...base(size)}>
      <rect x="4" y="5" width="16" height="15" rx="2" />
      <path d="M4 10h16M9 3v4M15 3v4" />
    </svg>
  );
}

export function NotesIcon({ size = 20 }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M5 4h10l4 4v12H5z" />
      <path d="M8 12h8M8 16h6" />
    </svg>
  );
}

export function TerminalIcon({ size = 14 }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M5 7l5 5-5 5M12 19h7" />
    </svg>
  );
}

export function ThemeIcon({ size = 18 }: IconProps) {
  return (
    <svg {...base(size)}>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

export function PlusIcon({ size = 14 }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function Mark({ size = 20 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
      <rect x="5" y="20" width="22" height="4.4" rx="2.2" fill="var(--mark-ink)" />
      <rect x="8" y="13.8" width="16" height="4.4" rx="2.2" fill="var(--mark-ink)" />
      <rect x="11" y="7.6" width="10" height="4.4" rx="2.2" fill="var(--mark-crown)" />
    </svg>
  );
}
