import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmartGateApp());
}

class SmartGateApp extends StatelessWidget {
  const SmartGateApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Gate Control',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardThemeData(
          elevation: 4,
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const ControlScreen(),
    const TestScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Control',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build),
            label: 'Test',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONTROL SCREEN - Main Traffic Management
// ═══════════════════════════════════════════════════════════

class ControlScreen extends StatefulWidget {
  const ControlScreen({Key? key}) : super(key: key);

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Updated Lane Configuration
  List<LaneData> lanes = [
    LaneData(id: 1, cars: 0, normalServo: 1, emergencyServo: 2, trafficModule: 1),
    LaneData(id: 2, cars: 0, normalServo: 8, emergencyServo: 4, trafficModule: 4),
    LaneData(id: 3, cars: 0, normalServo: 7, emergencyServo: 3, trafficModule: 2),
    LaneData(id: 4, cars: 0, normalServo: 5, emergencyServo: 6, trafficModule: 3),
  ];

  // Temporary car counts (not yet submitted)
  List<int> tempCarCounts = [0, 0, 0, 0];

  Map<int, bool> emergencyMode = {1: false, 2: false, 3: false, 4: false};
  Map<int, Timer?> emergencyTimers = {1: null, 2: null, 3: null, 4: null};

  bool isTrafficCycleRunning = false;
  int currentTrafficLane = -1;

  // Time settings (in seconds)
  double trafficGreenTime = 20.0; // Default 20 seconds per lane
  double emergencyDuration = 20.0; // Default 20 seconds for emergency

  @override
  void initState() {
    super.initState();
    // Initialize temp counts with current lane counts
    for (int i = 0; i < lanes.length; i++) {
      tempCarCounts[i] = lanes[i].cars;
    }
  }

  @override
  void dispose() {
    emergencyTimers.forEach((key, timer) => timer?.cancel());
    super.dispose();
  }

  void _updateTempCarCount(int laneIndex, int cars) {
    setState(() {
      tempCarCounts[laneIndex] = cars;
    });
  }

  void _submitCarCounts() {
    setState(() {
      // Update actual lane car counts
      for (int i = 0; i < lanes.length; i++) {
        lanes[i].cars = tempCarCounts[i];
      }
    });

    // Analyze all lanes after submission
    for (int i = 0; i < lanes.length; i++) {
      _analyzeLane(i);
    }

    // Start traffic cycle
    _startTrafficCycle();

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Car counts submitted successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _analyzeLane(int laneIndex) async {
    final lane = lanes[laneIndex];

    if (emergencyMode[lane.id] == true) {
      // Emergency: Close normal servo, open emergency servo for set duration
      // Set all traffic lights to RED during emergency
      for (var l in lanes) {
        await _setTrafficLight(l.trafficModule, true, false, false); // RED
      }

      await _closeServo(lane.normalServo);
      await _openServo(lane.emergencyServo);

      emergencyTimers[lane.id]?.cancel();
      emergencyTimers[lane.id] = Timer(Duration(seconds: emergencyDuration.toInt()), () async {
        await _closeServo(lane.emergencyServo);
        setState(() => emergencyMode[lane.id] = false);
        // Re-analyze after emergency
        _analyzeLane(laneIndex);
        // Restart traffic cycle after emergency
        _startTrafficCycle();
      });

    } else if (lane.cars >= 11) {
      // Congestion: Open normal servo, close emergency servo
      await _openServo(lane.normalServo);
      await _closeServo(lane.emergencyServo);

    } else {
      // No congestion: Close both servos
      await _closeServo(lane.normalServo);
      await _closeServo(lane.emergencyServo);
    }
  }

  void _startTrafficCycle() async {
    if (isTrafficCycleRunning) return;

    isTrafficCycleRunning = true;

    // Sort lanes by number of cars (highest first)
    List<LaneData> sortedLanes = List.from(lanes);
    sortedLanes.sort((a, b) => b.cars.compareTo(a.cars));

    // Cycle through lanes based on congestion priority
    for (var lane in sortedLanes) {
      if (lane.cars > 0) { // Only process lanes with cars
        setState(() => currentTrafficLane = lane.id);

        // Set this lane to GREEN (or YELLOW for module 4), others to RED
        for (var l in lanes) {
          if (l.id == lane.id) {
            // Special case: Traffic Module 4 gets YELLOW instead of GREEN
            if (l.trafficModule == 4) {
              await _setTrafficLight(l.trafficModule, false, true, false); // YELLOW
            } else {
              await _setTrafficLight(l.trafficModule, false, false, true); // GREEN
            }
          } else {
            await _setTrafficLight(l.trafficModule, true, false, false); // RED
          }
        }

        // Wait for configured time
        await Future.delayed(Duration(seconds: trafficGreenTime.toInt()));
      }
    }

    // After cycle, set all to RED
    for (var l in lanes) {
      await _setTrafficLight(l.trafficModule, true, false, false);
    }

    setState(() {
      currentTrafficLane = -1;
      isTrafficCycleRunning = false;
    });
  }

  Future<void> _openServo(int servoNum) async {
    await _database.child('Park2/gates/gate$servoNum/position').set(90);
  }

  Future<void> _closeServo(int servoNum) async {
    await _database.child('Park2/gates/gate$servoNum/position').set(0);
  }

  Future<void> _setTrafficLight(int module, bool red, bool yellow, bool green) async {
    await _database.child('Park2/traffic/module$module').set({
      'red': red,
      'yellow': yellow,
      'green': green,
    });
  }

  void _triggerEmergency(int laneIndex) {
    setState(() => emergencyMode[lanes[laneIndex].id] = true);
    _analyzeLane(laneIndex);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚙️ Time Settings'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Traffic Green Time Slider
              const Text(
                '🚦 Traffic Green Light Duration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: trafficGreenTime,
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${trafficGreenTime.toInt()}s',
                      onChanged: (value) {
                        setDialogState(() => trafficGreenTime = value);
                        setState(() => trafficGreenTime = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${trafficGreenTime.toInt()}s',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              Text(
                'Each lane gets GREEN for ${trafficGreenTime.toInt()} seconds',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),

              // Emergency Duration Slider
              const Text(
                '🚨 Emergency Duration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: emergencyDuration,
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${emergencyDuration.toInt()}s',
                      onChanged: (value) {
                        setDialogState(() => emergencyDuration = value);
                        setState(() => emergencyDuration = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${emergencyDuration.toInt()}s',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              Text(
                'Emergency servo stays open for ${emergencyDuration.toInt()} seconds',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚦 Traffic Control System'),
        centerTitle: true,
        actions: [
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'Time Settings',
          ),
          if (emergencyMode.values.any((e) => e))
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning, size: 16),
                  SizedBox(width: 4),
                  Text('EMERGENCY', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          if (isTrafficCycleRunning)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 6),
                  Text('CYCLING', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Time Settings Display Card
          Card(
            color: Colors.blue.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTimeDisplay(
                    '🚦 Green Time',
                    '${trafficGreenTime.toInt()}s',
                    Colors.green,
                  ),
                  Container(
                    width: 2,
                    height: 40,
                    color: Colors.grey[700],
                  ),
                  _buildTimeDisplay(
                    '🚨 Emergency',
                    '${emergencyDuration.toInt()}s',
                    Colors.red,
                  ),
                  Container(
                    width: 2,
                    height: 40,
                    color: Colors.grey[700],
                  ),
                  InkWell(
                    onTap: _showSettingsDialog,
                    child: Column(
                      children: [
                        Icon(Icons.settings, color: Colors.blue[300], size: 32),
                        const SizedBox(height: 4),
                        const Text(
                          'Settings',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Statistics Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total Cars',
                        lanes.fold(0, (sum, lane) => sum + lane.cars).toString(),
                        Icons.directions_car,
                        Colors.blue,
                      ),
                      _buildStatItem(
                        'Congested',
                        lanes.where((l) => l.cars >= 11).length.toString(),
                        Icons.traffic,
                        Colors.red,
                      ),
                      _buildStatItem(
                        'Clear',
                        lanes.where((l) => l.cars < 11).length.toString(),
                        Icons.check_circle,
                        Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'System Logic',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildLogicRow('Servo Control', '< 11 cars: Both closed | ≥ 11 cars: Normal open', Colors.blue),
                const SizedBox(height: 8),
                _buildLogicRow('Traffic Lights', 'Cycle: Highest congestion gets GREEN for ${trafficGreenTime.toInt()}s', Colors.green),
                const SizedBox(height: 8),
                _buildLogicRow('Emergency', 'Normal closed, Emergency open for ${emergencyDuration.toInt()}s, All traffic RED', Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Lane Cards
          ...lanes.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildLaneCard(entry.key, entry.value),
            );
          }).toList(),

          const SizedBox(height: 16),

          // SUBMIT BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitCarCounts,
              icon: const Icon(Icons.send, size: 28),
              label: const Text(
                'SUBMIT CAR COUNTS',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTimeDisplay(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  Widget _buildLogicRow(String title, String description, Color color) {
    return Row(
      children: [
        Icon(Icons.arrow_right, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14),
              children: [
                TextSpan(
                  text: title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const TextSpan(text: ': '),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLaneCard(int index, LaneData lane) {
    final isCongested = lane.cars >= 11;
    final isEmergency = emergencyMode[lane.id] == true;
    final hasGreenLight = currentTrafficLane == lane.id;
    final tempCount = tempCarCounts[index];

    return Card(
      color: isEmergency
          ? Colors.red.withOpacity(0.2)
          : (isCongested ? Colors.orange.withOpacity(0.1) : const Color(0xFF1E1E1E)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isEmergency
                        ? Colors.red.withOpacity(0.2)
                        : (isCongested ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.route,
                    color: isEmergency ? Colors.red : (isCongested ? Colors.orange : Colors.blue),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lane ${lane.id}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Normal: S${lane.normalServo} | Emergency: S${lane.emergencyServo} | Traffic: M${lane.trafficModule}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isEmergency
                            ? Colors.red
                            : (isCongested ? Colors.orange : Colors.green),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isEmergency ? 'EMERGENCY' : (isCongested ? 'CONGESTED' : 'CLEAR'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (hasGreenLight) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: lane.trafficModule == 4 ? Colors.yellow : Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          lane.trafficModule == 4 ? '🟡 YELLOW' : '🟢 GREEN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: lane.trafficModule == 4 ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Car counter display
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      '$tempCount cars',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (tempCount != lane.cars)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      'Active: ${lane.cars}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Slider
            Slider(
              value: tempCount.toDouble(),
              min: 0,
              max: 30,
              divisions: 30,
              label: '$tempCount cars',
              onChanged: (value) => _updateTempCarCount(index, value.toInt()),
            ),

            const SizedBox(height: 16),

            // Emergency button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isEmergency ? null : () => _triggerEmergency(index),
                icon: const Icon(Icons.warning),
                label: Text(isEmergency ? 'EMERGENCY ACTIVE (${emergencyDuration.toInt()}s)' : 'TRIGGER EMERGENCY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEmergency ? Colors.grey : Colors.red,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LaneData {
  final int id;
  int cars;
  final int normalServo;
  final int emergencyServo;
  final int trafficModule;

  LaneData({
    required this.id,
    required this.cars,
    required this.normalServo,
    required this.emergencyServo,
    required this.trafficModule,
  });
}

// ═══════════════════════════════════════════════════════════
// TEST SCREEN - Hardware Testing
// ═══════════════════════════════════════════════════════════

class TestScreen extends StatefulWidget {
  const TestScreen({Key? key}) : super(key: key);

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  List<int> servoPositions = List.filled(8, 0);
  List<List<bool>> trafficStates = List.generate(4, (_) => [true, false, false]);

  void _updateServo(int servoNum, double position) async {
    setState(() {
      servoPositions[servoNum - 1] = position.toInt();
    });
    await _database.child('Park2/gates/gate$servoNum/position').set(position.toInt());
  }

  void _updateTrafficLight(int module, int colorIndex) async {
    setState(() {
      trafficStates[module - 1] = [
        colorIndex == 0, // Red
        colorIndex == 1, // Yellow
        colorIndex == 2, // Green
      ];
    });

    await _database.child('Park2/traffic/module$module').set({
      'red': colorIndex == 0,
      'yellow': colorIndex == 1,
      'green': colorIndex == 2,
    });
  }

  Future<void> _closeAllServos() async {
    for (int i = 1; i <= 8; i++) {
      await _database.child('Park2/gates/gate$i/position').set(0);
    }
    setState(() {
      servoPositions = List.filled(8, 0);
    });
  }

  Future<void> _openAllServos() async {
    for (int i = 1; i <= 8; i++) {
      await _database.child('Park2/gates/gate$i/position').set(90);
    }
    setState(() {
      servoPositions = List.filled(8, 90);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔧 Hardware Test'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                servoPositions = List.filled(8, 0);
                trafficStates = List.generate(4, (_) => [true, false, false]);
              });
            },
            tooltip: 'Reset All',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openAllServos,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Open All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _closeAllServos,
                  icon: const Icon(Icons.close_fullscreen),
                  label: const Text('Close All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Servo Testing Section
          const Text(
            '🔩 Servo Motors (8 Gates)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          ...List.generate(8, (index) {
            return _buildServoCard(index + 1);
          }),

          const SizedBox(height: 24),

          // Traffic Light Testing Section
          const Text(
            '🚦 Traffic Light Modules (4 Units)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          ...List.generate(4, (index) {
            return _buildTrafficCard(index + 1);
          }),
        ],
      ),
    );
  }

  Widget _buildServoCard(int servoNum) {
    final position = servoPositions[servoNum - 1];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings_input_component, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Text(
                  'Servo $servoNum (Gate $servoNum)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '$position°',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: position.toDouble(),
              min: 0,
              max: 180,
              divisions: 36,
              label: '$position°',
              onChanged: (value) => _updateServo(servoNum, value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Closed (0°)', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                Text('Open (90°)', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                Text('Max (180°)', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficCard(int module) {
    final states = trafficStates[module - 1];
    int activeColor = states[0] ? 0 : (states[1] ? 1 : 2);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.traffic, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Text(
                  'Traffic Module $module',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLightButton(module, 0, 'RED', Colors.red, activeColor == 0),
                _buildLightButton(module, 1, 'YELLOW', Colors.yellow, activeColor == 1),
                _buildLightButton(module, 2, 'GREEN', Colors.green, activeColor == 2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLightButton(int module, int colorIndex, String label, Color color, bool isActive) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: () => _updateTrafficLight(module, colorIndex),
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? color : Colors.grey[800],
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : color.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.black : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}