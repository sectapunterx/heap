// The state.json example on the page must be the schema the app writes today.
import { describe, expect, it } from 'vitest';
import example from '../../src/data/state-example.json';
import { buildExample, currentSchema } from '../../tools/state-example.mjs';

describe('state.json example', () => {
  it('is the current schema (src/StateSerializer.h)', () => {
    expect(example.state.schemaVersion).toBe(currentSchema());
  });

  it('shows no key the app no longer writes', () => {
    const text = JSON.stringify(example);
    expect(text).not.toMatch(/"deadline"|"hasTime"/);
    expect(text).toMatch(/"scheduledAt"|"dueAt"/);
  });

  it('is what tools/state-example.mjs makes from the newest fixture', () => {
    expect(buildExample()).toEqual(example);
  });
});
