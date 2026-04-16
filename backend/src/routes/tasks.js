const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON, deleteJSON } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

const taskKey = (id) => `data/tasks/task-${id}.json`;
const tasksByEmployeePrefix = (empId) => `data/tasks-by-employee/${empId}/`;
const taskPointerKey = (empId, id) => `data/tasks-by-employee/${empId}/task-${id}.json`;
const tasksByAssignerPrefix = (empId) => `data/tasks-by-assigner/${empId}/`;
const taskAssignerPointer = (empId, id) => `data/tasks-by-assigner/${empId}/task-${id}.json`;

// POST /api/tasks — create a task
router.post('/', async (req, res) => {
  try {
    const { title, description, assigned_to, assigned_by, due_date, attachments } = req.body;

    if (!title || !assigned_to || !assigned_by || !due_date) {
      return res.status(400).json({ error: 'title, assigned_to, assigned_by, and due_date are required' });
    }

    const id = uuidv4();
    const task = {
      id,
      title,
      description: description || '',
      assigned_to,
      assigned_by,
      due_date,
      status: 'toDo',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      attachments: attachments || [],
    };

    await putJSON(taskKey(id), task);
    await putJSON(taskPointerKey(assigned_to, id), { id });
    await putJSON(taskAssignerPointer(assigned_by, id), { id });

    // Send push notification to assigned employee
    notificationRoutes.sendPushToEmployee(
      assigned_to,
      'New Task Assigned',
      `You have a new task: ${title}`,
      { type: 'task_assigned', task_id: id }
    ).catch(e => console.error('Push send failed:', e.message));

    res.status(201).json(task);
  } catch (error) {
    console.error('Create task error:', error);
    res.status(500).json({ error: 'Failed to create task' });
  }
});

// GET /api/tasks/all — all tasks for SuperAdmin
router.get('/all', async (req, res) => {
  try {
    const tasks = await listJSON('data/tasks/');
    tasks.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(tasks);
  } catch (error) {
    console.error('List all tasks error:', error);
    res.status(500).json({ error: 'Failed to list all tasks' });
  }
});

// GET /api/tasks/employee/:employeeId — tasks assigned to employee
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const pointers = await listJSON(tasksByEmployeePrefix(req.params.employeeId));
    const tasks = [];
    for (const ptr of pointers) {
      const full = await getJSON(taskKey(ptr.id));
      if (full) tasks.push(full);
    }
    tasks.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(tasks);
  } catch (error) {
    console.error('List tasks error:', error);
    res.status(500).json({ error: 'Failed to list tasks' });
  }
});

// GET /api/tasks/assigned-by/:employeeId — tasks created by this user
router.get('/assigned-by/:employeeId', async (req, res) => {
  try {
    const pointers = await listJSON(tasksByAssignerPrefix(req.params.employeeId));
    const tasks = [];
    for (const ptr of pointers) {
      const full = await getJSON(taskKey(ptr.id));
      if (full) tasks.push(full);
    }
    tasks.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(tasks);
  } catch (error) {
    console.error('List assigned tasks error:', error);
    res.status(500).json({ error: 'Failed to list tasks' });
  }
});

// GET /api/tasks/:id
router.get('/:id', async (req, res) => {
  try {
    const task = await getJSON(taskKey(req.params.id));
    if (!task) return res.status(404).json({ error: 'Task not found' });
    res.json(task);
  } catch (error) {
    console.error('Get task error:', error);
    res.status(500).json({ error: 'Failed to get task' });
  }
});

// PATCH /api/tasks/:id — update status or details
router.patch('/:id', async (req, res) => {
  try {
    const task = await getJSON(taskKey(req.params.id));
    if (!task) return res.status(404).json({ error: 'Task not found' });

    const { status, title, description, due_date, comment, attachments } = req.body;
    if (status) {
      task.status = status;
      // Record when status changed
      if (status === 'inProgress' && !task.started_at) {
        task.started_at = new Date().toISOString();
      }
      if (status === 'done' || status === 'failed') {
        task.completed_at = new Date().toISOString();
        if (comment) task.completion_comment = comment;
        if (attachments) task.completion_attachments = attachments;
      }
    }
    if (title) task.title = title;
    if (description !== undefined) task.description = description;
    if (due_date) task.due_date = due_date;
    task.updated_at = new Date().toISOString();

    await putJSON(taskKey(req.params.id), task);

    // Notify assigner when task status changes to done/failed
    if ((status === 'done' || status === 'failed') && task.assigned_by) {
      notificationRoutes.sendPushToEmployee(
        task.assigned_by,
        `Task ${status === 'done' ? 'Completed' : 'Failed'}`,
        `Task "${task.title}" has been marked as ${status}`,
        { type: 'task_status', task_id: task.id }
      ).catch(e => console.error('Push failed:', e.message));
    }

    res.json(task);
  } catch (error) {
    console.error('Update task error:', error);
    res.status(500).json({ error: 'Failed to update task' });
  }
});

// DELETE /api/tasks/:id
router.delete('/:id', async (req, res) => {
  try {
    const task = await getJSON(taskKey(req.params.id));
    if (!task) return res.status(404).json({ error: 'Task not found' });

    await deleteJSON(taskKey(req.params.id));
    // Clean up pointers (best effort)
    try { await deleteJSON(taskPointerKey(task.assigned_to, req.params.id)); } catch (_) {}
    try { await deleteJSON(taskAssignerPointer(task.assigned_by, req.params.id)); } catch (_) {}

    res.json({ message: 'Task deleted' });
  } catch (error) {
    console.error('Delete task error:', error);
    res.status(500).json({ error: 'Failed to delete task' });
  }
});

module.exports = router;
