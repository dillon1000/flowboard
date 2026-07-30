export type TaskStatus = 'backlog' | 'in_progress' | 'review' | 'done';
export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent';

export interface Task {
  id: string;
  boardID: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  position: number;
  labels: string[];
  dueAt: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface Board {
  id: string;
  name: string;
  slug: string;
  tasks: Task[];
  createdAt: string | null;
  updatedAt: string | null;
}

export interface TaskDraft {
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  labels: string[];
  dueAt: string | null;
}

export interface Activity {
  id: number;
  verb: string;
  detail: string;
  time: string;
}
