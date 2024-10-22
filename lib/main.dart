import 'dart:io';
//import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:workmanager/workmanager.dart';

// Top-level callback funkce pro Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case 'checkScheduledTasks':
        await initNotifications(); // Inicializace notifikací
        final db = await DatabaseHelper.instance.database;
        final tasks = await DatabaseHelper.instance.getTasks();
        final now = DateTime.now();
        
        for (var task in tasks) {
          if (shouldShowNotification(task, now)) {
            await flutterLocalNotificationsPlugin.show(
              task.id ?? 0,
              task.title,
              task.description,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'task_notifications',
                  'Task Notifications',
                  channelDescription: 'Notifications for scheduled tasks',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
            );
            
            // Aktualizace času příští notifikace pro opakující se úkoly
            if (task.frequency != 'once') {
              final nextDateTime = calculateNextNotificationTime(task);
              await db.update(
                'tasks',
                {'dateTime': nextDateTime.toIso8601String()},
                where: 'id = ?',
                whereArgs: [task.id],
              );
            }
          }
        }
        break;
    }
    return true;
  });
}


bool shouldShowNotification(Task task, DateTime now) {
  final scheduledTime = task.dateTime;
  final difference = now.difference(scheduledTime);
  
  // Kontrola zda je čas notifikace v rozmezí posledních 5 minut
  if (difference.inMinutes.abs() <= 5) {
    return true;
  }
  
  return false;
}

DateTime calculateNextNotificationTime(Task task) {
  final now = DateTime.now();
  DateTime nextTime = task.dateTime;
  
  switch (task.frequency) {
    case 'daily':
      nextTime = nextTime.add(const Duration(days: 1));
      break;
    case 'weekly':
      nextTime = nextTime.add(const Duration(days: 7));
      break;
    case 'monthly':
      nextTime = DateTime(
        nextTime.year,
        nextTime.month + 1,
        nextTime.day,
        nextTime.hour,
        nextTime.minute,
      );
      break;
    case 'custom':
      nextTime = nextTime.add(Duration(days: task.periodicity ?? 14));
      break;
  }
  
  // Ujistěte se, že příští čas je v budoucnosti
  while (nextTime.isBefore(now)) {
    nextTime = calculateNextNotificationTime(Task(
      id: task.id,
      title: task.title,
      description: task.description,
      dateTime: nextTime,
      frequency: task.frequency,
      periodicity: task.periodicity,
    ));
  }
  
  return nextTime;
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
 
 await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true
  );

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
     _schedulePeriodicCheck();
  }

void _schedulePeriodicCheck() {
  Workmanager().registerPeriodicTask(
    "taskChecker",
    "checkScheduledTasks",
    frequency: const Duration(minutes: 15),  // Minimální interval je 15 minut
    initialDelay: const Duration(seconds: 10),
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
  );
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
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      print('Notification clicked: ${details.payload}');
    },
  );

  // Request permissions right after initialization
  await _requestNotificationPermissions();

  // Add a test notification on app start
  final now = tz.TZDateTime.now(tz.local);
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'task_notifications',
    'Task Notifications',
    channelDescription: 'Notifications for scheduled tasks',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    99998, // unique ID for startup test notification
    'App Started',
    'Notification system initialized',
    now.add(const Duration(seconds: 5)),
    platformChannelSpecifics,
    androidAllowWhileIdle: true,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );

  print('Notifications initialized with test notification scheduled');
}

Future<void> _requestNotificationPermissions() async {
  if (Platform.isAndroid) {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestPermission();
      print('Android notification permissions requested');
    }
  } else if (Platform.isIOS) {
    final bool? result = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    print('iOS notification permissions result: $result');
  }
}

/*tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime scheduledDate) {
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
} */

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
  // Create notification channel details
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'task_notifications', // channel id
    'Task Notifications', // channel name
    channelDescription: 'Notifications for scheduled tasks',
    importance: Importance.max,
    priority: Priority.high,
    enableLights: true,
    playSound: true,
    // Remove custom sound to use default
    visibility: NotificationVisibility.public,
    showWhen: true,
    enableVibration: true,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledDate = tz.TZDateTime.from(task.dateTime, tz.local);

  // Add debug prints
  print('Scheduling notification for task: ${task.title}');
  print('Frequency: ${task.frequency}');
  print('Current time: $now');
  print('Scheduled date: $scheduledDate');

  // Ensure the scheduled time is in the future
  if (scheduledDate.isBefore(now)) {
    switch (task.frequency) {
      case 'daily':
        scheduledDate = _nextInstanceOfTime(scheduledDate);
        break;
      case 'weekly':
        scheduledDate = _nextInstanceOfWeekday(scheduledDate);
        break;
      case 'monthly':
        scheduledDate = _nextInstanceOfMonthDay(scheduledDate);
        break;
      case 'custom':
        scheduledDate =
            _nextInstanceOfCustomPeriod(scheduledDate, task.periodicity ?? 14);
        break;
      default:
        // For one-time notifications in the past, don't schedule
        print('One-time notification in the past, skipping...');
        return;
    }
    print('Adjusted scheduled date: $scheduledDate');
  }

  try {
    // Add immediate test notification
    await flutterLocalNotificationsPlugin.zonedSchedule(
      99999, // unique ID for test notification
      'Test Notification',
      'This is a test notification',
      now.add(const Duration(seconds: 5)), // Schedule for 5 seconds from now
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    print('Test notification scheduled for 5 seconds from now');

    // Schedule the actual task notification
    switch (task.frequency) {
      case 'daily':
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.id ?? 0,
          task.title,
          task.description,
          scheduledDate,
          platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        print('Daily notification scheduled for: $scheduledDate');
        break;

      case 'weekly':
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.id ?? 0,
          task.title,
          task.description,
          scheduledDate,
          platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
        print('Weekly notification scheduled for: $scheduledDate');
        break;

      case 'monthly':
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.id ?? 0,
          task.title,
          task.description,
          scheduledDate,
          platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        );
        print('Monthly notification scheduled for: $scheduledDate');
        break;

      case 'custom':
        // Schedule only the next occurrence for custom frequency
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.id ?? 0,
          task.title,
          task.description,
          scheduledDate,
          platformChannelSpecifics,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        print('Custom notification scheduled for: $scheduledDate');
        break;

      default:
        // One-time notification
        if (scheduledDate.isAfter(now)) {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            task.id ?? 0,
            task.title,
            task.description,
            scheduledDate,
            platformChannelSpecifics,
            androidAllowWhileIdle: true,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          print('One-time notification scheduled for: $scheduledDate');
        }
    }
  } catch (e, stackTrace) {
    print('Error scheduling notification: $e');
    print('Stack trace: $stackTrace');
  }
}

// Pomocná funkce pro výpočet příštího času
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
}
