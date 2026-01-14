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
  bool state; // for toggle & button

  DashboardItem({
    required this.type,
    required this.topic,
    this.onValue = "ON",
    this.offValue = "OFF",
    this.threshold = 500,
    this.state = false,
  });
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

/* ===================== DASHBOARD ===================== */

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late MqttServerClient client;

  String mqttStatus = "Disconnected";
  int sensorValue = 0;

  /* MQTT SETTINGS CONTROLLERS */
  final brokerCtrl = TextEditingController();
  final portCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  /* DASHBOARD WIDGETS */
  final List<DashboardItem> widgets = [];

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  /* ===================== SETTINGS ===================== */

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    brokerCtrl.text = prefs.getString("broker") ?? "";
    portCtrl.text = prefs.getString("port") ?? "";
    userCtrl.text = prefs.getString("username") ?? "";
    passCtrl.text = prefs.getString("password") ?? "";

    if (brokerCtrl.text.isNotEmpty) {
      connectMQTT();
    }
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("broker", brokerCtrl.text);
    await prefs.setString("port", portCtrl.text);
    await prefs.setString("username", userCtrl.text);
    await prefs.setString("password", passCtrl.text);
    connectMQTT();
  }

  void openSettings() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("MQTT Settings"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: brokerCtrl,
                  decoration: const InputDecoration(labelText: "Broker URL")),
              TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: "Port"),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: "Username")),
              TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: "Password"),
                  obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              saveSettings();
              Navigator.pop(context);
            },
            child: const Text("SAVE & CONNECT"),
          )
        ],
      ),
    );
  }

  /* ===================== MQTT ===================== */

  Future<void> connectMQTT() async {
    setState(() => mqttStatus = "Connecting...");
    client = MqttServerClient(
      brokerCtrl.text,
      "flutter_${DateTime.now().millisecondsSinceEpoch}",
    );
    client.port = int.parse(portCtrl.text);
    client.secure = true;

    client.connectionMessage = MqttConnectMessage()
        .authenticateAs(userCtrl.text, passCtrl.text)
        .startClean();

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

  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  /* ===================== WIDGET MANAGEMENT ===================== */

  void addWidget() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text("Toggle Switch"),
            onTap: () {
              setState(() {
                widgets.add(DashboardItem(
                  type: WidgetType.toggle,
                  topic: "akbotix/esp32/control",
                ));
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text("Button (Momentary)"),
            onTap: () {
              setState(() {
                widgets.add(DashboardItem(
                  type: WidgetType.button,
                  topic: "akbotix/esp32/control",
                ));
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text("Status Indicator"),
            onTap: () {
              setState(() {
                widgets.add(DashboardItem(
                  type: WidgetType.status,
                  topic: "akbotix/esp32/sensor",
                ));
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
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
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: topicCtrl,
                  decoration: const InputDecoration(labelText: "MQTT Topic")),
              if (item.type != WidgetType.status)
                TextField(
                    controller: onCtrl,
                    decoration: const InputDecoration(labelText: "ON Value")),
              if (item.type != WidgetType.status)
                TextField(
                    controller: offCtrl,
                    decoration: const InputDecoration(labelText: "OFF Value")),
              if (item.type == WidgetType.status)
                TextField(
                    controller: thrCtrl,
                    decoration: const InputDecoration(labelText: "Threshold"),
                    keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                item.topic = topicCtrl.text;
                item.onValue = onCtrl.text;
                item.offValue = offCtrl.text;
                item.threshold = int.tryParse(thrCtrl.text) ?? item.threshold;
              });
              Navigator.pop(context);
            },
            child: const Text("SAVE"),
          )
        ],
      ),
    );
  }

  /* ===================== UI BUILD ===================== */

  Widget buildWidget(DashboardItem item) {
    return GestureDetector(
      onLongPress: () => editWidget(item),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: item.type == WidgetType.toggle
              ? SwitchListTile(
                  title: const Text("Toggle"),
                  value: item.state,
                  onChanged: (v) {
                    setState(() => item.state = v);
                    publish(item.topic, v ? item.onValue : item.offValue);
                  },
                )
              : item.type == WidgetType.button
                  ? GestureDetector(
                      onTapDown: (_) {
                        setState(() => item.state = true);
                        publish(item.topic, item.onValue);
                      },
                      onTapUp: (_) {
                        setState(() => item.state = false);
                        publish(item.topic, item.offValue);
                      },
                      onTapCancel: () {
                        setState(() => item.state = false);
                        publish(item.topic, item.offValue);
                      },
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "PRESS",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("STATUS"),
                        const SizedBox(height: 8),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: sensorValue > item.threshold
                                ? Colors.green
                                : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(sensorValue.toString()),
                      ],
                    ),
        ),
      ),
    );
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addWidget,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text("MQTT: $mqttStatus | Sensor: $sensorValue"),
          ),
          Expanded(
            child: GridView.builder(
              itemCount: widgets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
              ),
              itemBuilder: (c, i) => buildWidget(widgets[i]),
            ),
          ),
        ],
      ),
    );
  }
}
