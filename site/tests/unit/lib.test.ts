import { describe, expect, it } from 'vitest';
import { detectOS } from '../../src/lib/os';

describe('detectOS', () => {
  it('tells desktop platforms apart', () => {
    expect(detectOS('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')).toBe('windows');
    expect(detectOS('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15')).toBe('macos');
    expect(detectOS('Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0')).toBe('linux');
    expect(detectOS('anything', 'Windows')).toBe('windows');
  });

  it('treats phones as mobile, not Linux or macOS', () => {
    expect(detectOS('Mozilla/5.0 (Linux; Android 14; Pixel 8) Mobile Safari/537.36')).toBe('mobile');
    expect(detectOS('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)')).toBe('mobile');
  });

  it('gives up on unknown agents', () => {
    expect(detectOS('curl/8.9')).toBeNull();
  });
});
