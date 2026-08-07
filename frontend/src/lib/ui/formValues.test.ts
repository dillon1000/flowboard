import { describe, expect, it } from 'vitest';
import { estimateMinutes, parseLabels } from './formValues';

describe('form values', () => {
  it('accepts positive whole-minute estimates', () => {
    expect(estimateMinutes('45')).toBe(45);
    expect(estimateMinutes('1.5')).toBeNull();
    expect(estimateMinutes('0')).toBeNull();
    expect(estimateMinutes(null)).toBeNull();
  });

  it('parses comma-separated labels without dropping values', () => {
    expect(parseLabels(' Exam, Reading, , Lab ')).toEqual(['Exam', 'Reading', 'Lab']);
    expect(parseLabels('1,2,3,4,5,6,7')).toHaveLength(7);
  });
});
