import { describe, expect, it, vi } from 'vitest';
import { collectCanvasSnapshot } from '../src/canvas-api';

const origin = 'https://school.instructure.com';

describe('complete Canvas snapshots', () => {
  it('builds a versioned snapshot after every course assignment page succeeds', async () => {
    const fetchPage = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 1,
        name: 'Course',
        course_code: null,
        term: null,
        html_url: `${origin}/courses/1`,
        enrollments: []
      }])))
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 2,
        name: 'Assignment',
        description: null,
        html_url: `${origin}/courses/1/assignments/2`,
        due_at: null,
        points_possible: 10,
        submission: null
      }])));
    const snapshot = await collectCanvasSnapshot(origin, fetchPage, () => 'snapshot-1', () => new Date('2026-08-06T12:00:00Z'));
    expect(snapshot).toMatchObject({ version: 1, snapshotID: 'snapshot-1', capturedAt: '2026-08-06T12:00:00.000Z' });
    expect(snapshot.courses[0]?.assignments).toHaveLength(1);
  });

  it('aborts the complete read after any assignment page fails', async () => {
    const fetchPage = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 1,
        name: 'Course',
        html_url: `${origin}/courses/1`
      }])))
      .mockResolvedValueOnce(new Response('denied', { status: 403 }));
    await expect(collectCanvasSnapshot(origin, fetchPage)).rejects.toMatchObject({ code: 'CANVAS_DENIED' });
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });
});
