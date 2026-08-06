import { describe, expect, it, vi } from 'vitest';
import { fetchAllCanvasPages, parseCanvasLinkHeader } from '../src/pagination';

describe('Canvas pagination', () => {
  it('parses Canvas Link relations', () => {
    expect(parseCanvasLinkHeader('<https://canvas.test/api?page=2>; rel="next", <https://canvas.test/api?page=4>; rel="last"')).toEqual({
      next: 'https://canvas.test/api?page=2',
      last: 'https://canvas.test/api?page=4'
    });
  });

  it('follows every next page with credentials', async () => {
    const fetchPage = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify([{ id: 1 }]), {
        headers: { Link: '<https://canvas.test/api?page=2>; rel="next"' }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify([{ id: 2 }])));
    await expect(fetchAllCanvasPages('https://canvas.test/api?page=1', fetchPage)).resolves.toEqual([{ id: 1 }, { id: 2 }]);
    expect(fetchPage).toHaveBeenNthCalledWith(2, 'https://canvas.test/api?page=2', { method: 'GET', credentials: 'include' });
  });
});
