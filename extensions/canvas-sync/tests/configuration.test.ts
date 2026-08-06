import { beforeEach, describe, expect, it } from 'vitest';
import { canonicalHTTPSOrigin } from '../src/origins';
import { popupErrorMessage } from '../src/popup-errors';
import { readConfiguration, saveConfiguration } from '../src/storage';

const values: Record<string, unknown> = {};

beforeEach(() => {
  for (const key of Object.keys(values)) delete values[key];
  Object.defineProperty(globalThis, 'chrome', {
    configurable: true,
    value: {
      storage: {
        local: {
          get: async (key: string) => ({ [key]: values[key] }),
          set: async (input: Record<string, unknown>) => Object.assign(values, input)
        }
      }
    }
  });
});

describe('origin and configuration validation', () => {
  it('accepts only an origin-only HTTPS URL', () => {
    expect(canonicalHTTPSOrigin(' https://School.Example.edu/ ')).toBe('https://school.example.edu');
    expect(() => canonicalHTTPSOrigin('https://school.example.edu/courses')).toThrow(/no credentials, path/);
    expect(() => canonicalHTTPSOrigin('http://school.example.edu')).toThrow(/HTTPS origin/);
  });

  it('stores and reads canonical origins with a restricted sync key', async () => {
    const syncKey = `fcs_${'a'.repeat(64)}`;
    await saveConfiguration({
      canvasOrigin: 'https://SCHOOL.example.edu/',
      focalpointOrigin: 'https://focalpoint.example/',
      syncKey
    });
    await expect(readConfiguration()).resolves.toEqual({
      canvasOrigin: 'https://school.example.edu',
      focalpointOrigin: 'https://focalpoint.example',
      syncKey
    });
  });
});

describe('popup error mapping', () => {
  it.each([
    ['CURRENT_TAB_MISMATCH', 'current tab'],
    ['SESSION_EXPIRED', 'session has expired'],
    ['CANVAS_DENIED', 'denied'],
    ['PAGINATION_FAILED', 'pagination failed'],
    ['SYNC_KEY_INVALID', 'sync key is invalid'],
    ['FOCALPOINT_UNAVAILABLE', 'origin is unavailable'],
    ['SYNC_ACTIVE', 'already active']
  ] as const)('maps %s to a useful message', (code, phrase) => {
    expect(popupErrorMessage(code)).toContain(phrase);
  });
});
