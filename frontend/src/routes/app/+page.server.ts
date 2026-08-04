import { loadWorkspacePage } from '$lib/server/backend';
import { renderMarkdown } from '$lib/server/markdown';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
  const context = await loadWorkspacePage(event, `/api/v1/workspace${event.url.search}`);
  return {
    context,
    descriptionHTML: context.taskDetail ? renderMarkdown(context.taskDetail.task.description) : ''
  };
};
