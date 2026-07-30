import type { Board, Task, TaskDraft, TaskStatus } from './types';

// VITE_API_URL can point to a hosted server. The local default matches Vapor's
// standard port and keeps setup to one frontend command plus one backend command.
const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8080/api/v1';

interface VaporError {
  reason?: string;
  error?: boolean;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...init?.headers
    }
  });

  if (!response.ok) {
    const payload = (await response.json().catch(() => ({}))) as VaporError;
    throw new Error(payload.reason ?? `The server returned ${response.status}.`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export const api = {
  getDefaultBoard: () => request<Board>('/boards/default'),

  createTask: (boardID: string, draft: TaskDraft) =>
    request<Task>('/tasks', {
      method: 'POST',
      body: JSON.stringify({ boardID, ...draft })
    }),

  updateTask: (taskID: string, draft: TaskDraft) =>
    request<Task>(`/tasks/${taskID}`, {
      method: 'PATCH',
      body: JSON.stringify(draft)
    }),

  moveTask: (taskID: string, status: TaskStatus, targetIndex: number) =>
    request<Task>(`/tasks/${taskID}/move`, {
      method: 'POST',
      body: JSON.stringify({ status, targetIndex })
    }),

  deleteTask: (taskID: string) =>
    request<void>(`/tasks/${taskID}`, {
      method: 'DELETE'
    })
};
