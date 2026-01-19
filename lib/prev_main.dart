import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MyApp());
}

/* ===================== MODELS ===================== */

enum WidgetType { toggle, button, status }

class DashboardItem {
  WidgetType type;
  String topic;
  String onValue;
  String offValue;
  int threshold;
  bool state;

  DashboardItem({
    required this.type,
    required this.topic,
    this.onValue = "ON",
    this.offValue = "OFF",
    this.threshold = 500,
    this.state = false,
  });

  Map<String, dynamic> toMap() => {
        "type": type.index,
        "topic": topic,
        "onValue": onValue,
        "offValue": offValue,
        "threshold": threshold,
        "state": state,
      };

  factory DashboardItem.fromMap(Map<String, dynamic> map) {
    return DashboardItem(
      type: WidgetType.values[map["type"]],
      topic: map["topic"],
      onValue: map["onValue"],
      offValue: map["offValue"],
      threshold: map["threshold"],
      state: map["state"],
    );
  }
}

/* ===================== APP ===================== */

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Dashboard(),
    );
  }
}

/* ===================== STORAGE ===================== */

Future<List<DashboardItem>> loadDashboard() async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString("dashboard_widgets");
  if (data == null) return [];
  return (jsonDecode(data) as List)
      .map((e) => DashboardItem.fromMap(e))
      .toList();
}

Future<void> saveDashboard(List<DashboardItem> widgets) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString(
    "dashboard_widgets",
    jsonEncode(widgets.map((e) => e.toMap()).toList()),
  );
}

/* ===================== DASHBOARD ===================== */

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late MqttServerClient client;
  List<DashboardItem> widgets = [];
  int sensorValue = 0;
  String mqttStatus = "Disconnected";

  final brokerCtrl = TextEditingController();
  final portCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    widgets = await loadDashboard();
    await loadSettings();
    setState(() {});
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    brokerCtrl.text = prefs.getString("broker") ?? "";
    portCtrl.text = prefs.getString("port") ?? "8883";
    userCtrl.text = prefs.getString("username") ?? "";
    passCtrl.text = prefs.getString("password") ?? "";

    if (brokerCtrl.text.isNotEmpty) connectMQTT();
  }

  Future<void> connectMQTT() async {
    client = MqttServerClient(
      brokerCtrl.text,
      "flutter_${DateTime.now().millisecondsSinceEpoch}",
    );
    client.port = int.tryParse(portCtrl.text) ?? 8883;
    client.secure = true;
    client.connectionMessage =
        MqttConnectMessage().authenticateAs(userCtrl.text, passCtrl.text);

    try {
      await client.connect();
      mqttStatus = "Connected";
    } catch (_) {
      mqttStatus = "Failed";
      setState(() {});
      return;
    }

    client.subscribe("akbotix/esp32/sensor", MqttQos.atMostOnce);
    client.updates!.listen((events) {
      final msg = events.first.payload as MqttPublishMessage;
      final val = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      setState(() => sensorValue = int.tryParse(val) ?? 0);
    });

    setState(() {});
  }

  void publish(String topic, String msg) {
    final b = MqttClientPayloadBuilder();
    b.addString(msg);
    client.publishMessage(topic, MqttQos.atMostOnce, b.payload!);
  }

  Widget buildWidget(DashboardItem item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: item.type == WidgetType.toggle
            ? SwitchListTile(
                title: const Text("Toggle"),
                value: item.state,
                onChanged: (v) {
                  setState(() => item.state = v);
                  publish(item.topic, v ? item.onValue : item.offValue);
                  saveDashboard(widgets);
                },
              )
            : item.type == WidgetType.button
                ? GestureDetector(
                    onTapDown: (_) => publish(item.topic, item.onValue),
                    onTapUp: (_) => publish(item.topic, item.offValue),
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text("PRESS",
                          style: TextStyle(color: Colors.white)),
                    ),
                  )
                : Column(
                    children: [
                      const Text("STATUS"),
                      const SizedBox(height: 6),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: sensorValue > item.threshold
                              ? Colors.green
                              : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(sensorValue.toString()),
                    ],
                  ),
      ),
    );
  }

  void openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(widgets: widgets),
      ),
    );
    widgets = await loadDashboard();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("IoT Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: openSettings,
          )
        ],
      ),
      body: Column(
        children: [
          Text("MQTT: $mqttStatus | Sensor: $sensorValue"),
          Expanded(
            child: GridView.builder(
              itemCount: widgets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2),
              itemBuilder: (_, i) => buildWidget(widgets[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/* ===================== SETTINGS PAGE ===================== */

class SettingsPage extends StatelessWidget {
  final List<DashboardItem> widgets;
  const SettingsPage({super.key, required this.widgets});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ElevatedButton(
              child: const Text("Edit Dashboard Widgets"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditDashboardPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== EDIT DASHBOARD PAGE ===================== */

class EditDashboardPage extends StatefulWidget {
  const EditDashboardPage({super.key});

  @override
  State<EditDashboardPage> createState() => _EditDashboardPageState();
}

class _EditDashboardPageState extends State<EditDashboardPage> {
  List<DashboardItem> widgets = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    widgets = await loadDashboard();
    setState(() {});
  }

  void addWidget(WidgetType type) {
    widgets.add(DashboardItem(
      type: type,
      topic: type == WidgetType.status
          ? "akbotix/esp32/sensor"
          : "akbotix/esp32/control",
    ));
    saveDashboard(widgets);
    setState(() {});
  }

  void editWidget(DashboardItem item) {
    final topicCtrl = TextEditingController(text: item.topic);
    final onCtrl = TextEditingController(text: item.onValue);
    final offCtrl = TextEditingController(text: item.offValue);
    final thrCtrl = TextEditingController(text: item.threshold.toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Widget"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: topicCtrl),
            if (item.type != WidgetType.status) TextField(controller: onCtrl),
            if (item.type != WidgetType.status) TextField(controller: offCtrl),
            if (item.type == WidgetType.status) TextField(controller: thrCtrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              item.topic = topicCtrl.text;
              item.onValue = onCtrl.text;
              item.offValue = offCtrl.text;
              item.threshold = int.tryParse(thrCtrl.text) ?? item.threshold;
              saveDashboard(widgets);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text("SAVE"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Dashboard"),
        actions: [
          TextButton(
            onPressed: () {
              saveDashboard(widgets);
              Navigator.pop(context);
            },
            child: const Text("DONE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                    title: const Text("Toggle"),
                    onTap: () {
                      addWidget(WidgetType.toggle);
                      Navigator.pop(context);
                    }),
                ListTile(
                    title: const Text("Button"),
                    onTap: () {
                      addWidget(WidgetType.button);
                      Navigator.pop(context);
                    }),
                ListTile(
                    title: const Text("Status"),
                    onTap: () {
                      addWidget(WidgetType.status);
                      Navigator.pop(context);
                    }),
              ],
            ),
          );
        },
      ),
      body: ReorderableListView.builder(
        itemCount: widgets.length,
        onReorder: (o, n) {
          if (n > o) n--;
          final item = widgets.removeAt(o);
          widgets.insert(n, item);
          saveDashboard(widgets);
          setState(() {});
        },
        itemBuilder: (_, i) => ListTile(
          key: ValueKey("$i"),
          title: Text(widgets[i].type.name),
          subtitle: Text(widgets[i].topic),
          leading: const Icon(Icons.drag_handle),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              widgets.removeAt(i);
              saveDashboard(widgets);
              setState(() {});
            },
          ),
          onTap: () => editWidget(widgets[i]),
        ),
      ),
    );
  }
}
