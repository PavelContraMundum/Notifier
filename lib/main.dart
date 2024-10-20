import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Připomínky úkolů',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TaskListScreen(),
    );
  }
}

class Task {
  final int? id;
  final String title;
  final String description;
  final DateTime dateTime;
  final String frequency;
  final int? periodicity;

  const Task({
    this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.frequency,
    this.periodicity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dateTime': dateTime.toIso8601String(),
      'frequency': frequency,
      'periodicity': periodicity,
    };
  }

  static Task fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      dateTime: DateTime.parse(map['dateTime']),
      frequency: map['frequency'],
      periodicity: map['periodicity'],
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = Path.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        dateTime TEXT,
        frequency TEXT,
        periodicity INTEGER
      )
    ''');
  }

  Future<int> insertTask(Task task) async {
    final db = await database;
    return await db.insert('tasks', task.toMap());
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('tasks');
    return List.generate(maps.length, (i) => Task.fromMap(maps[i]));
  }

  Future<int> updateTask(Task task) async {
    final db = await database;
    return await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllTasks() async {
    final db = await database;
    return await db.delete('tasks');
  }
}

Future<void> cancelNotification(int id) async {
  await flutterLocalNotificationsPlugin.cancel(id);
}

// Přidejte tuto funkci pro zrušení všech notifikací
Future<void> cancelAllNotifications() async {
  await flutterLocalNotificationsPlugin.cancelAll();
}

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({Key? key}) : super(key: key);

  @override
  TaskListScreenState createState() => TaskListScreenState();
}

class TaskListScreenState extends State<TaskListScreen> {
  List<Task> tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final loadedTasks = await DatabaseHelper.instance.getTasks();
    setState(() {
      tasks = loadedTasks;
    });
  }

  Future<void> _deleteTask(Task task) async {
    // Smažeme úkol z databáze
    await DatabaseHelper.instance.deleteTask(task.id!);
    // Zrušíme příslušnou notifikaci
    await cancelNotification(task.id!);
    // Znovu načteme seznam úkolů
    await _loadTasks();
  }

  Future<void> _deleteAllTasks() async {
    try {
      // Zrušíme všechny notifikace
      await cancelAllNotifications();
      // Smažeme všechny úkoly z databáze
      await DatabaseHelper.instance.deleteAllTasks();
      // Aktualizujeme UI
      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Všechny úkoly a upozornění byly smazány'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Došlo k chybě při mazání úkolů'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moje úkoly'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_off),
            onPressed: () async {
              // Přidáme dialogové okno pro potvrzení
              final bool? result = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Zrušit všechna upozornění'),
                    content: const Text(
                        'Opravdu chcete zrušit všechna naplánovaná upozornění?'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Ne'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('Ano'),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  );
                },
              );

              if (result == true) {
                await _deleteAllTasks();
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          return Dismissible(
            // Přidáme možnost swipe-to-delete
            key: Key(tasks[index].id.toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Potvrdit smazání'),
                    content: const Text('Opravdu chcete smazat tento úkol?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Ne'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Ano'),
                      ),
                    ],
                  );
                },
              );
            },
            onDismissed: (direction) {
              _deleteTask(tasks[index]);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Úkol byl smazán'),
                ),
              );
            },
            child: ListTile(
              title: Text(tasks[index].title),
              subtitle: Text(tasks[index].description),
              trailing: Text(
                  DateFormat('dd.MM.yyyy HH:mm').format(tasks[index].dateTime)),
              onTap: () => _editTask(tasks[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTask(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addTask() async {
    final newTask = await Navigator.push<Task>(
      context,
      MaterialPageRoute(builder: (context) => const TaskEditScreen()),
    );
    if (newTask != null) {
      await DatabaseHelper.instance.insertTask(newTask);
      await _loadTasks();
      await scheduleNotification(newTask);
    }
  }

  Future<void> _editTask(Task task) async {
    final updatedTask = await Navigator.push<Task>(
      context,
      MaterialPageRoute(builder: (context) => TaskEditScreen(task: task)),
    );
    if (updatedTask != null) {
      await DatabaseHelper.instance.updateTask(updatedTask);
      await _loadTasks();
      await scheduleNotification(updatedTask);
    }
  }
}

class TaskEditScreen extends StatefulWidget {
  final Task? task;

  const TaskEditScreen({Key? key, this.task}) : super(key: key);

  @override
  TaskEditScreenState createState() => TaskEditScreenState();
}

class TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _periodicityController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _frequency = 'once';
  bool _showPeriodicityField = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.task?.description ?? '');
    _periodicityController = TextEditingController(
        text: (widget.task?.periodicity ?? 14).toString());
    _selectedDate = widget.task?.dateTime ?? DateTime.now();
    _selectedTime =
        TimeOfDay.fromDateTime(widget.task?.dateTime ?? DateTime.now());
    _frequency = widget.task?.frequency ?? 'once';
    _showPeriodicityField = _frequency == 'custom';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Přidat úkol' : 'Upravit úkol'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: <Widget>[
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Název'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Prosím zadejte název úkolu';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Popis'),
            ),
            ListTile(
              title: Text(
                  'Datum: ${DateFormat('dd.MM.yyyy').format(_selectedDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            ListTile(
              title: Text('Čas: ${_selectedTime.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
            ),
            DropdownButtonFormField<String>(
              value: _frequency,
              items: [
                DropdownMenuItem(value: 'once', child: Text('Jednou')),
                DropdownMenuItem(value: 'daily', child: Text('Denně')),
                DropdownMenuItem(value: 'weekly', child: Text('Týdně')),
                DropdownMenuItem(value: 'monthly', child: Text('Měsíčně')),
                DropdownMenuItem(
                    value: 'custom', child: Text('Vlastní perioda')),
              ],
              onChanged: (value) {
                setState(() {
                  _frequency = value!;
                  _showPeriodicityField = value == 'custom';
                });
              },
              decoration: const InputDecoration(labelText: 'Frekvence'),
            ),
            if (_showPeriodicityField)
              TextFormField(
                controller: _periodicityController,
                decoration: const InputDecoration(
                  labelText: 'Počet dní mezi opakováním',
                  hintText: 'Např. 14 pro dvoutýdenní opakování',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (_showPeriodicityField) {
                    if (value == null || value.isEmpty) {
                      return 'Zadejte počet dní';
                    }
                    final number = int.tryParse(value);
                    if (number == null || number < 1) {
                      return 'Zadejte platné číslo větší než 0';
                    }
                  }
                  return null;
                },
              ),
            ElevatedButton(
              child: const Text('Uložit'),
              onPressed: _saveTask,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _pickTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (pickedTime != null) {
      setState(() {
        _selectedTime = pickedTime;
      });
    }
  }

  void _saveTask() {
    if (_formKey.currentState!.validate()) {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final task = Task(
        id: widget.task?.id,
        title: _titleController.text,
        description: _descriptionController.text,
        dateTime: dateTime,
        frequency: _frequency,
        periodicity: _showPeriodicityField
            ? int.tryParse(_periodicityController.text)
            : null,
      );
      Navigator.pop(context, task);
    }
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tz.initializeTimeZones();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime scheduledDate) {
  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledTime = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    scheduledDate.hour,
    scheduledDate.minute,
  );

  if (scheduledTime.isBefore(now)) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }
  return scheduledTime;
}

tz.TZDateTime _nextInstanceOfWeekday(tz.TZDateTime scheduledDate) {
  tz.TZDateTime scheduledTime = _nextInstanceOfTime(scheduledDate);
  while (scheduledTime.weekday != scheduledDate.weekday) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }
  return scheduledTime;
}

tz.TZDateTime _nextInstanceOfMonthDay(tz.TZDateTime scheduledDate) {
  tz.TZDateTime scheduledTime = _nextInstanceOfTime(scheduledDate);
  while (scheduledTime.day != scheduledDate.day) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }
  return scheduledTime;
}

Future<void> scheduleNotification(Task task) async {
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      channelDescription: 'your channel description',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final tz.TZDateTime scheduledDate =
      tz.TZDateTime.from(task.dateTime, tz.local);

  DateTimeComponents? matchDateTimeComponents;
  tz.TZDateTime nextValidDate = scheduledDate;

  switch (task.frequency) {
    case 'custom':
      // Pro vlastní periodicitu použijeme specifickou logiku
      nextValidDate = _nextInstanceOfCustomPeriod(
        scheduledDate,
        task.periodicity ?? 14, // defaultně 14 dní, pokud není specifikováno
      );
      matchDateTimeComponents =
          null; // Pro vlastní periodicitu nepoužíváme matchDateTimeComponents
      break;
    case 'daily':
      matchDateTimeComponents = DateTimeComponents.time;
      nextValidDate = _nextInstanceOfTime(scheduledDate);
      break;
    case 'weekly':
      matchDateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
      nextValidDate = _nextInstanceOfWeekday(scheduledDate);
      break;
    case 'monthly':
      matchDateTimeComponents = DateTimeComponents.dayOfMonthAndTime;
      nextValidDate = _nextInstanceOfMonthDay(scheduledDate);
      break;
    case 'once':
    default:
      matchDateTimeComponents = null;
  }

  // Pro vlastní periodicitu musíme vytvořit sérii notifikací
  if (task.frequency == 'custom') {
    // Vytvoříme několik následujících notifikací
    for (int i = 0; i < 10; i++) {
      // Vytvoříme 10 následujících notifikací
      final tz.TZDateTime notificationDate =
          nextValidDate.add(Duration(days: i * (task.periodicity ?? 14)));

      // Kontrola, že datum není v minulosti
      if (notificationDate.isAfter(tz.TZDateTime.now(tz.local))) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          (task.id ?? 0) + (i * 1000), // Unikátní ID pro každou notifikaci
          task.title,
          task.description,
          notificationDate,
          platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  } else {
    // Standardní notifikace pro ostatní frekvence
    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.id ?? 0,
      task.title,
      task.description,
      nextValidDate,
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }
}

// Přidáme novou pomocnou funkci pro výpočet vlastní periodicity
tz.TZDateTime _nextInstanceOfCustomPeriod(
    tz.TZDateTime scheduledDate, int days) {
  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledTime = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    scheduledDate.hour,
    scheduledDate.minute,
  );

  while (scheduledTime.isBefore(now)) {
    scheduledTime = scheduledTime.add(Duration(days: days));
  }

  return scheduledTime;

  /* await flutterLocalNotificationsPlugin.zonedSchedule(
    task.id ?? 0,
    task.title,
    task.description,
    // task.dateTime,
    tz.TZDateTime.from(task.dateTime, tz.local),
    platformChannelSpecifics,
    androidAllowWhileIdle: true,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  ); */
}
