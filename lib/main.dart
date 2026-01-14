import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late MqttServerClient client;

  String status = "Disconnected";
  String sensorValue = "--";

  String broker = "";
  String port = "";
  String username = "";
  String password = "";

  final topicControl = "akbotix/esp32/control";
  final topicSensor = "akbotix/esp32/sensor";

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      broker = prefs.getString('broker') ?? "";
      port = prefs.getString('port') ?? "";
      username = prefs.getString('username') ?? "";
      password = prefs.getString('password') ?? "";
    });

    if (broker.isNotEmpty) {
      connectMQTT();
    }
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('broker', broker);
    await prefs.setString('port', port);
    await prefs.setString('username', username);
    await prefs.setString('password', password);

    connectMQTT();
  }

  Future<void> connectMQTT() async {
    setState(() => status = "Connecting...");

    client = MqttServerClient(
      broker,
      'flutter_${DateTime.now().millisecondsSinceEpoch}',
    );

    client.port = int.parse(port);
    client.secure = true;
    client.keepAlivePeriod = 20;

    client.onConnected = () {
      setState(() => status = "Connected");
    };

    client.onDisconnected = () {
      setState(() => status = "Disconnected");
    };

    client.connectionMessage =
        MqttConnectMessage().authenticateAs(username, password).startClean();

    try {
      await client.connect();
    } catch (e) {
      setState(() => status = "Connection Failed");
      return;
    }

    client.subscribe(topicSensor, MqttQos.atMostOnce);

    client.updates!.listen((events) {
      final msg = events.first.payload as MqttPublishMessage;
      final value = MqttPublishPayload.bytesToStringAsString(
        msg.payload.message,
      );
      setState(() => sensorValue = value);
    });
  }

  void sendCommand(String cmd) {
    if (status != "Connected") return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(cmd);
    client.publishMessage(
      topicControl,
      MqttQos.atMostOnce,
      builder.payload!,
    );
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
                decoration: const InputDecoration(labelText: "Broker URL"),
                controller: TextEditingController(text: broker),
                onChanged: (v) => broker = v,
              ),
              TextField(
                decoration: const InputDecoration(labelText: "Port"),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: port),
                onChanged: (v) => port = v,
              ),
              TextField(
                decoration: const InputDecoration(labelText: "Username"),
                controller: TextEditingController(text: username),
                onChanged: (v) => username = v,
              ),
              TextField(
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
                controller: TextEditingController(text: password),
                onChanged: (v) => password = v,
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 MQTT App"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: openSettings,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Status: $status", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Text("Sensor: $sensorValue", style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => sendCommand("ON"),
              child: const Text("LED ON"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => sendCommand("OFF"),
              child: const Text("LED OFF"),
            ),
          ],
        ),
      ),
    );
  }
}
