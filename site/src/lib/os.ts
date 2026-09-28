export type DesktopOS = 'windows' | 'macos' | 'linux';
export type DetectedOS = DesktopOS | 'mobile' | null;

export const OS_LABEL: Record<DesktopOS, string> = {
  windows: 'Windows',
  macos: 'macOS',
  linux: 'Linux',
};

/**
 * Best guess at the visitor's platform from the user agent and, where the
 * browser has it, `navigator.userAgentData.platform`. Phones and tablets come
 * back as `mobile`: heap. has nothing to install there.
 */
export function detectOS(userAgent: string, platform = ''): DetectedOS {
  const ua = userAgent.toLowerCase();
  const pf = platform.toLowerCase();
  if (/android|iphone|ipad|ipod|mobile/.test(ua)) return 'mobile';
  // iPadOS reports itself as a Mac; a touch-capable "Mac" is caught by the caller.
  if (pf.includes('win') || ua.includes('windows')) return 'windows';
  if (pf.includes('mac') || ua.includes('mac os x') || ua.includes('macintosh')) return 'macos';
  if (pf.includes('linux') || ua.includes('linux') || ua.includes('x11') || ua.includes('cros')) return 'linux';
  return null;
}

/** Runs in the browser only. */
export function detectCurrentOS(): DetectedOS {
  if (typeof navigator === 'undefined') return null;
  const nav = navigator as Navigator & { userAgentData?: { platform?: string; mobile?: boolean } };
  if (nav.userAgentData?.mobile) return 'mobile';
  const os = detectOS(nav.userAgent, nav.userAgentData?.platform ?? '');
  if (os === 'macos' && nav.maxTouchPoints > 1) return 'mobile';
  return os;
}
