import { Buffer } from 'node:buffer';
import { expect, test, type APIRequestContext, type APIResponse, type Locator, type Page } from '@playwright/test';

interface TestUser {
  name: string;
  email: string;
  password: string;
}

interface TaskResponse {
  id: string;
  title: string;
  status: string;
  browserPath: string;
}

interface BoardResponse {
  id: string;
  name: string;
  tasks: TaskResponse[];
}

interface TapMutationResponse {
  id: string;
  url: string;
}

function testUser(label: string): TestUser {
  const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
  return {
    name: `${label} Audit`,
    email: `playwright-${label.toLowerCase()}-${suffix}@example.com`,
    password: 'SvelteKit-SSR-123!'
  };
}

async function json<T>(response: APIResponse): Promise<T> {
  if (!response.ok()) {
    throw new Error(`${response.request().method()} ${response.url()} returned ${response.status()}: ${await response.text()}`);
  }
  return (await response.json()) as T;
}

async function register(request: APIRequestContext, label: string): Promise<TestUser> {
  const user = testUser(label);
  await json(
    await request.post('/api/v1/auth/register', {
      data: user
    })
  );
  return user;
}

async function defaultBoard(request: APIRequestContext): Promise<BoardResponse> {
  return json(await request.get('/api/v1/boards/default'));
}

async function createTask(
  request: APIRequestContext,
  boardID: string,
  title: string,
  description = 'Created by the browser regression suite.'
): Promise<TaskResponse> {
  return json(
    await request.post('/api/v1/tasks', {
      data: {
        boardID,
        title,
        description,
        status: 'backlog',
        priority: 'medium',
        labels: ['Browser'],
        startAt: null,
        dueAt: null,
        assigneeID: null,
        properties: {}
      }
    })
  );
}

function collectBrowserErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  return errors;
}

async function waitForHydration(page: Page): Promise<void> {
  await expect(page.locator('.app-shell')).toHaveAttribute('data-hydrated', 'true');
}

async function chooseMenu(root: Page | Locator, label: string, option: string): Promise<void> {
  await root.getByLabel(label).click();
  await root.getByRole('listbox', { name: label }).getByRole('option', { name: option, exact: true }).click();
}

test('server-renders auth and overview with an aligned profile control', async ({ page, browser }) => {
  const errors = collectBrowserErrors(page);
  const serverUser = testUser('Server');
  const serverContext = await browser.newContext({ javaScriptEnabled: false });
  const serverPage = await serverContext.newPage();
  const response = await serverPage.goto('/register');
  expect(response?.status()).toBe(200);
  expect(await response?.text()).toContain('Create your account');
  await serverPage.getByLabel('Name').fill(serverUser.name);
  await serverPage.getByLabel('Email').fill(serverUser.email);
  await serverPage.getByLabel('Password').fill(serverUser.password);
  await serverPage.getByRole('button', { name: 'Create account' }).click();
  await expect(serverPage).toHaveURL(/\/app$/);
  await expect(serverPage.getByRole('heading', { name: 'This week' })).toBeVisible();
  await serverContext.close();

  const user = await register(page.request, 'Shell');
  await page.goto('/app');
  await waitForHydration(page);
  await expect(page).toHaveURL(/\/app$/);
  await expect(page.locator('.app-shell')).toHaveClass(/study-overview-page/);
  await expect(page.locator('.brand-logo')).toHaveAttribute('src', '/focalboard-fb-abbreviation-tp.webp');

  const overviewProfileBox = await page.locator('.user-row').boundingBox();
  expect(overviewProfileBox?.width).toBe(52);
  expect(overviewProfileBox?.height).toBe(52);

  await page.evaluate(() => localStorage.setItem('flowboard-sidebar', 'collapsed'));
  await page.reload();
  const collapsedProfileBox = await page.locator('.user-row').boundingBox();
  expect(collapsedProfileBox?.width).toBe(40);
  expect(collapsedProfileBox?.height).toBe(40);

  const opener = page.getByRole('button', { name: 'Add course', exact: true }).first();
  await opener.click();
  const dialog = page.getByRole('dialog', { name: 'Add course' });
  await expect(dialog).toBeVisible();
  await expect(page.locator('#new-board-name')).toBeFocused();
  await expect(page.locator('body')).toHaveClass(/no-scroll/);
  await dialog.getByRole('button', { name: 'Close' }).focus();
  await page.keyboard.press('Shift+Tab');
  await expect(dialog.getByRole('button', { name: 'Add course', exact: true })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(opener).toBeFocused();
  await expect(page.locator('body')).not.toHaveClass(/no-scroll/);

  await page.locator('.user-row').click();
  await expect(page).toHaveURL(/\/app\/settings$/);
  await page.getByLabel('Name').fill('Shell Audit Renamed');
  await page.getByRole('button', { name: 'Save profile' }).click();
  await expect(page.locator('.success-message')).toContainText('Profile saved');

  await page.getByRole('button', { name: 'Log out' }).click();
  await expect(page).toHaveURL(/\/login$/);
  await page.getByLabel('Email').fill(user.email);
  await page.getByLabel('Password').fill(user.password);
  await page.getByRole('button', { name: 'Log in' }).click();
  await expect(page).toHaveURL(/\/app$/);
  expect(errors).toEqual([]);

  await page.goto('/app/route-that-does-not-exist');
  await expect(page.getByRole('heading', { name: 'This card isn’t on the board.' })).toBeVisible();
  await expect(page.getByText('404')).toBeVisible();
});

test('moves board cards and completes every core task-detail action', async ({ page }) => {
  const errors = collectBrowserErrors(page);
  await register(page.request, 'Task');
  const board = await defaultBoard(page.request);
  const firstTask = await createTask(page.request, board.id, 'First browser task');
  const secondTask = await createTask(page.request, board.id, 'Second browser task');
  const detailTask = await createTask(page.request, board.id, 'Task detail browser audit');

  await page.goto(`/app/boards/${board.id}`);
  await waitForHydration(page);
  await expect(page).toHaveURL(/\/views\//);
  const backlog = page.locator('.stage-lane').filter({
    has: page.locator('.stage-lane-header strong').filter({ hasText: /^Backlog$/ })
  });
  const firstCard = backlog.locator(`[data-task-id="${firstTask.id}"]`);
  const secondCard = backlog.locator(`[data-task-id="${secondTask.id}"]`);
  await secondCard.dragTo(firstCard, { targetPosition: { x: 40, y: 1 } });
  await expect(page.getByRole('status')).toContainText('Task moved');
  await expect(backlog.locator('.lane-card').first()).toContainText('Second browser task');
  await expect.poll(async () => {
    const updated = await json<BoardResponse>(await page.request.get(`/api/v1/boards/${board.id}`));
    return updated.tasks.filter((task) => task.status === 'backlog').map((task) => task.title).slice(0, 3);
  }).toEqual(['Second browser task', 'First browser task', 'Task detail browser audit']);

  const detailCard = backlog.locator(`[data-task-id="${detailTask.id}"]`);
  await detailCard.hover();
  await expect(page.locator('.task-preview')).toContainText('Task detail browser audit');
  await detailCard.click();
  await expect(page).toHaveURL(new RegExp(`${detailTask.browserPath}$`));

  const taskMain = await page.locator('.task-main').boundingBox();
  const taskSidebar = await page.locator('.task-sidebar').boundingBox();
  expect(taskMain).not.toBeNull();
  expect(taskSidebar).not.toBeNull();
  expect(taskSidebar!.x).toBeGreaterThan(taskMain!.x + taskMain!.width);

  const moreActions = page.getByRole('button', { name: 'More task actions' });
  await moreActions.click();
  await page.getByRole('menuitem', { name: 'Edit task' }).click();
  await expect(page.locator('#edit-title')).toBeFocused();
  await expect(page.locator('#edit-description')).toHaveAttribute('maxlength', '5000');
  await page.getByLabel('Due date').click();
  const calendar = page.locator('.flatpickr-calendar.open');
  await expect(calendar).toBeVisible();
  await calendar.locator('.flatpickr-day:not(.flatpickr-disabled):not(.prevMonthDay):not(.nextMonthDay)').first().click();
  await expect(page.locator('#edit-due')).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
  await page.keyboard.press('Escape');
  await expect(moreActions).toBeFocused();
  await moreActions.click();
  await page.getByRole('menuitem', { name: 'Edit task' }).click();
  await page.locator('#edit-description').fill('**Browser checked** with native Svelte state.');
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(page.locator('.task-description strong')).toHaveText('Browser checked');

  const statusTrigger = page.locator('.task-status-trigger');
  await statusTrigger.click();
  const statusMenu = page.getByRole('listbox', { name: 'Change task status' });
  await expect(statusMenu).toBeVisible();
  await statusMenu.getByRole('option', { name: 'Review', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Task status updated');
  await expect(statusTrigger).toHaveAttribute('aria-expanded', 'false');
  await expect(statusTrigger.locator('.badge.status')).toHaveText('Review');

  await page.getByLabel('New checklist item').fill('Verify native checklist');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByText('Verify native checklist')).toBeVisible();
  await page.getByRole('button', { name: 'Toggle “Verify native checklist”' }).click();
  await expect(page.getByText('1 of 1')).toBeVisible();

  const comment = page.getByPlaceholder('Leave a comment…');
  await comment.fill('Submitted with the keyboard shortcut.');
  await comment.press('Control+Enter');
  await expect(page.getByText('Submitted with the keyboard shortcut.')).toBeVisible();

  const uploadForm = page.locator('.attachment-upload-form');
  const fileInput = uploadForm.locator('input[type="file"]');
  await fileInput.setInputFiles({
    name: 'too-large.txt',
    mimeType: 'text/plain',
    buffer: Buffer.alloc(10_000_001)
  });
  await expect(uploadForm.getByRole('alert')).toContainText('10 MB or smaller');
  await expect(uploadForm.getByRole('button', { name: 'Upload' })).toBeDisabled();
  await fileInput.setInputFiles({
    name: 'browser-proof.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('SvelteKit SSR browser proof')
  });
  await uploadForm.getByRole('button', { name: 'Upload' }).click();
  await expect(page.getByText('browser-proof.txt')).toBeVisible();

  await moreActions.click();
  await page.getByRole('menuitem', { name: /^Follow/ }).click();
  await moreActions.click();
  await expect(page.getByRole('menuitem', { name: /^Unfollow/ })).toBeVisible();
  expect(errors).toEqual([]);
});

test('configures a board, manages API keys, and runs a public Tap action', async ({ page, browser }) => {
  const errors = collectBrowserErrors(page);
  await register(page.request, 'Settings');
  const board = await defaultBoard(page.request);

  await page.goto('/app/settings/api-keys');
  await waitForHydration(page);
  await expect(page.getByText('GET, POST /tasks')).toBeVisible();
  await page.getByLabel('Name').fill('Browser suite');
  await page.getByRole('button', { name: 'Create key' }).click();
  await expect(page.locator('.api-key-secret')).toHaveText(/^fbk_[a-f0-9]{64}$/);
  await expect(page.getByText('Browser suite', { exact: false })).toBeVisible();
  page.once('dialog', (dialog) => dialog.accept());
  await page.getByRole('button', { name: 'Revoke' }).click();
  await expect(page.getByText('No API keys')).toBeVisible();

  await page.goto(`/app/boards/${board.id}/settings`);
  await waitForHydration(page);
  const viewForm = page.locator('#views form');
  await viewForm.getByPlaceholder('View name').fill('Browser table');
  await chooseMenu(viewForm, 'View type', 'Table');
  await viewForm.getByRole('button', { name: 'Add view' }).click();
  const viewRow = page.locator('#views .panel-row').filter({ hasText: 'Browser table' });
  await expect(viewRow).toBeVisible();
  await viewRow.getByRole('button', { name: 'Configure' }).click();
  const viewDialog = page.getByRole('dialog', { name: 'Configure Browser table' });
  await expect(viewDialog.getByLabel('Group board cards by')).toBeFocused();
  await viewDialog.getByLabel('Name').fill('Browser assignments');
  await chooseMenu(viewDialog, 'Layout', 'Gallery');
  await chooseMenu(viewDialog, 'Group board cards by', 'Severity');
  await viewDialog.getByLabel('Sort field').fill('title');
  await chooseMenu(viewDialog, 'Sort direction', 'Descending');
  await viewDialog.getByRole('button', { name: 'Save view' }).click();
  const editedViewRow = page.locator('#views .panel-row').filter({ hasText: 'Browser assignments' });
  await expect(editedViewRow).toContainText('Gallery · Grouped by Severity');

  const fieldForm = page.locator('#fields form');
  await chooseMenu(fieldForm, 'Field type', 'Select');
  await expect(fieldForm.getByLabel('Field options')).toBeVisible();
  await fieldForm.getByPlaceholder('Field name').fill('Browser region');
  await fieldForm.getByLabel('Field options').fill('North, South');
  await fieldForm.getByRole('button', { name: 'Add field' }).click();
  await expect(page.locator('#fields')).toContainText('Browser region');

  const statusForm = page.locator('#workflow .panel').first().locator('form');
  await statusForm.getByPlaceholder('Status name').fill('Browser complete');
  await statusForm.getByLabel('Color').click();
  await expect(statusForm.getByRole('dialog', { name: 'Choose workflow color' })).toBeVisible();
  const spectrum = statusForm.locator('hex-color-picker');
  await expect(spectrum).toHaveJSProperty('color', '#3b82f6');
  const saturationBox = await spectrum.locator('[part="saturation"]').boundingBox();
  expect(saturationBox?.height).toBeGreaterThan(100);
  await spectrum.locator('[part="hue"]').click({ position: { x: 100, y: 10 } });
  await expect(statusForm.locator('input[name="color"]')).toHaveValue(/^#[0-9a-f]{6}$/);
  await statusForm.getByLabel('Custom color hex value').fill('2563eb');
  await expect(statusForm.locator('input[name="color"]')).toHaveValue('#2563eb');
  await statusForm.getByText('Completed', { exact: true }).click();
  await statusForm.getByRole('button', { name: 'Add status' }).click();
  await expect(page.locator('#workflow')).toContainText('Browser complete');

  const backlogRow = page.locator('#workflow .panel').first().locator('.panel-row').filter({ hasText: 'Backlog' });
  await backlogRow.getByRole('button', { name: 'Edit' }).click();
  const statusDialog = page.getByRole('dialog', { name: 'Edit status' });
  await statusDialog.getByLabel('Name').fill('Queued');
  await statusDialog.getByLabel('Color').click();
  await statusDialog.getByRole('option', { name: 'Purple' }).click();
  await statusDialog.getByText('Counts as completed', { exact: true }).click();
  await statusDialog.getByRole('button', { name: 'Save status' }).click();
  await expect(page.locator('#workflow')).toContainText('Queued');

  await page.getByRole('button', { name: 'New Tap action' }).click();
  const tapDialog = page.getByRole('dialog', { name: 'New Tap action' });
  await tapDialog.getByLabel('Name').fill('Browser Tap');
  await tapDialog.getByLabel('Phone instructions').fill('Create the browser proof task.');
  await tapDialog.getByLabel('Maximum uses').fill('2');
  await tapDialog.getByRole('button', { name: 'Create action' }).click();
  const secret = page.locator('.tap-url-secret');
  await expect(secret).toContainText('/t#fbt_');
  const tapURL = (await secret.textContent())?.trim();
  expect(tapURL).toBeTruthy();

  const publicContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const tapPage = await publicContext.newPage();
  const tapErrors = collectBrowserErrors(tapPage);
  await tapPage.goto(tapURL!);
  await expect(tapPage.getByRole('heading', { name: 'Browser Tap' })).toBeVisible();
  await expect(tapPage.getByLabel('Task title')).toBeFocused();
  await tapPage.getByLabel('Task title').fill('Task created from public Tap');
  await tapPage.getByLabel('Task description').fill('T'.repeat(2_500));
  await tapPage.getByLabel('Labels').fill('Tap, Browser');
  await tapPage.getByRole('button', { name: 'Create task' }).click();
  await expect(tapPage.getByText('Action complete')).toBeVisible();
  expect(tapPage.url()).not.toContain('#');

  await expect.poll(async () => {
    const updated = await json<BoardResponse>(await page.request.get(`/api/v1/boards/${board.id}`));
    return updated.tasks.some((task) => task.title === 'Task created from public Tap');
  }).toBe(true);
  expect(tapErrors).toEqual([]);
  await publicContext.close();
  expect(errors).toEqual([]);
});
