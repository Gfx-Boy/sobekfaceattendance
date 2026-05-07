const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const {
  putJSON,
  getJSON,
  listJSON,
  deleteJSON,
  uploadImage,
  getImageBuffer,
} = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

// Multer for attachment uploads
const uploadStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = path.join(__dirname, '../../uploads');
    if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    cb(null, `${Date.now()}-${file.originalname}`);
  },
});
const upload = multer({
  storage: uploadStorage,
  limits: { fileSize: 15 * 1024 * 1024 }, // 15 MB
});

const employeeKey = (id) => `data/employees/employee-${id}.json`;
const taskKey = (id) => `data/tasks/task-${id}.json`;

// Resolve employee names for tasks that were created without them
async function enrichWithNames(tasks) {
  const cache = {};
  async function getName(id) {
    if (!id) return null;
    if (id in cache) return cache[id];
    try {
      const emp = await getJSON(employeeKey(id));
      cache[id] = emp?.name || null;
    } catch (_) { cache[id] = null; }
    return cache[id];
  }
  for (const t of tasks) {
    if (!t.assigned_to_name) t.assigned_to_name = await getName(t.assigned_to);
    if (!t.assigned_by_name) t.assigned_by_name = await getName(t.assigned_by);
  }
  return tasks;
}
const tasksByEmployeePrefix = (empId) => `data/tasks-by-employee/${empId}/`;
const taskPointerKey = (empId, id) => `data/tasks-by-employee/${empId}/task-${id}.json`;
const tasksByAssignerPrefix = (empId) => `data/tasks-by-assigner/${empId}/`;
const taskAssignerPointer = (empId, id) => `data/tasks-by-assigner/${empId}/task-${id}.json`;

// POST /api/tasks — create a task
router.post('/', async (req, res) => {
  try {
    const {
      title, description, assigned_to, assigned_by, due_date, attachments,
      task_type, item_code,
    } = req.body;

    if (!title || !assigned_to || !assigned_by || !due_date) {
      return res.status(400).json({ error: 'title, assigned_to, assigned_by, and due_date are required' });
    }

    // Look up names so the client never has to display raw IDs
    let assigned_to_name = null;
    let assigned_by_name = null;
    try {
      const toEmp = await getJSON(employeeKey(assigned_to));
      assigned_to_name = toEmp?.name || null;
    } catch (_) {}
    try {
      const byEmp = await getJSON(employeeKey(assigned_by));
      assigned_by_name = byEmp?.name || null;
    } catch (_) {}

    const id = uuidv4();
    const task = {
      id,
      title,
      description: description || '',
      assigned_to,
      assigned_by,
      assigned_to_name,
      assigned_by_name,
      due_date,
      status: 'toDo',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      attachments: attachments || [],
      task_type: task_type || 'general',
      item_code: item_code || null,
      counted_total: null,
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
    await enrichWithNames(tasks);
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
    await enrichWithNames(tasks);
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
    await enrichWithNames(tasks);
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

    const { status, title, description, due_date, comment, attachments, counted_total } = req.body;
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
        if (counted_total !== undefined && counted_total !== null) {
          task.counted_total = Number(counted_total);
        }
      }
    } else if (counted_total !== undefined && counted_total !== null) {
      task.counted_total = Number(counted_total);
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

// GET /api/tasks/all — superadmin
// (already defined above; enrichment applied there)

// POST /api/tasks/upload — upload an attachment and return its URL/key.
// Accepts any file up to the multer limit; client stores returned descriptor
// inside the task's `attachments` array.
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    const id = uuidv4();
    const ext = path.extname(req.file.originalname) || '';
    const key = `data/task-attachments/${id}${ext}`;
    await uploadImage(req.file.path, key); // generic putObject under the hood
    fs.unlinkSync(req.file.path);
    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const url = `${baseUrl}/api/tasks/attachment/${id}${ext}`;
    res.json({
      id,
      key,
      url,
      name: req.file.originalname,
      size: req.file.size,
      content_type: req.file.mimetype,
    });
  } catch (error) {
    console.error('Task upload error:', error);
    res.status(500).json({ error: 'Failed to upload attachment' });
  }
});

// GET /api/tasks/attachment/:filename — proxy-stream from S3
// Also exported so server.js can mount it WITHOUT requireAuth
async function serveAttachment(req, res) {
  try {
    const key = `data/task-attachments/${req.params.filename}`;
    const buffer = await getImageBuffer(key);
    const ext = path.extname(req.params.filename).toLowerCase();
    const ctMap = {
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
    res.setHeader('Content-Type', ctMap[ext] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.send(buffer);
  } catch (error) {
    console.error('Attachment serve error:', error);
    res.status(404).json({ error: 'Attachment not found' });
  }
}
router.get('/attachment/:filename', serveAttachment);

module.exports = router;
module.exports.serveAttachment = serveAttachment;
