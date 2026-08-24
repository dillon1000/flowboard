import { loadWorkspacePage } from '$lib/server/backend';
import { renderMarkdown } from '$lib/server/markdown';
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
  const context = await loadWorkspacePage(
    event,
    `/api/v1/workspace/${event.params.path}${event.url.search}`
  );

  const boardRoute = event.params.path.match(/^boards\/([^/]+)(?:\/views\/([^/]+)|\/settings)?$/);
  if (boardRoute && /^[0-9a-f-]{36}$/i.test(boardRoute[1])) {
    if (context.board) {
      redirect(308, `${context.board.activeView.href}${event.url.search}`);
    }
    if (context.boardSettings) {
      redirect(308, `/app/boards/${context.boardSettings.slug}/settings${event.url.search}`);
    }
  }

  return {
    context,
    descriptionHTML: context.taskDetail ? renderMarkdown(context.taskDetail.task.description) : ''
  };
};
