import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../global/setting.dart';
import 'package:ros_flutter_gui_app/language/l10n/gen/app_localizations.dart';

class GamepadMappingPage extends StatefulWidget {
  const GamepadMappingPage({super.key});

  @override
  State<GamepadMappingPage> createState() => _GamepadMappingPageState();
}

class MappingResult {
  String key = "";
  double value = 0;
  GamepadEvent? event;
  int count = 0;

  MappingResult(
      {required this.key,
      required this.value,
      this.event,
      required this.count});
}

class _GamepadMappingPageState extends State<GamepadMappingPage> {
  StreamSubscription? _subscription;

  GamepadEvent _recvEvent = GamepadEvent(
      gamepadId: "0",
      timestamp: 0,
      type: KeyType.analog,
      key: "None",
      value: 0);

  final Map<KeyName, String> _mappedKeys = {};
  String _editingKey = ""; // Currently editing key
  Map<String, MappingResult> _mappingResults = {};

  OverlayEntry? _overlayEntry;

  String _msg = ""; // Variable for displaying messages

  @override
  void initState() {
    super.initState();
    _loadMappings();
    _startListening();
  }

  void _loadMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final mappingStr = prefs.getString('gamepadMapping');
    if (mappingStr != null) {
      try {
        final mapping = jsonDecode(mappingStr);
        setState(() {
          // Load axisMapping
          if (mapping['axisMapping'] != null) {
            (mapping['axisMapping'] as Map<String, dynamic>)
                .forEach((key, value) {
              _mappedKeys[_parseKeyName(value['keyName'])] = key;
            });
          }

          // Load buttonMapping
          if (mapping['buttonMapping'] != null) {
            (mapping['buttonMapping'] as Map<String, dynamic>)
                .forEach((key, value) {
              _mappedKeys[_parseKeyName(value['keyName'])] = key;
            });
          }
        });
      } catch (e) {
        print('Error loading gamepad mapping: $e');
        // Use default mapping when loading fails
        _loadDefaultMappings();
      }
    } else {
      // If no saved mapping exists, use default mapping
      _loadDefaultMappings();
    }
  }

  void _loadDefaultMappings() {
    setState(() {
      _mappedKeys.clear();
      // Load default axis mapping
      globalSetting.axisMapping.forEach((key, value) {
        _mappedKeys[value.keyName] = key;
      });
      // Load default button mapping
      globalSetting.buttonMapping.forEach((key, value) {
        _mappedKeys[value.keyName] = key;
      });
    });
  }

  KeyName _parseKeyName(String keyNameStr) {
    // Remove 'KeyName.' prefix
    final enumStr = keyNameStr.replaceAll('KeyName.', '');
    return KeyName.values.firstWhere(
      (e) => e.toString() == 'KeyName.$enumStr',
      orElse: () => KeyName.None,
    );
  }

  void _startListening() {
    _subscription?.cancel(); // Cancel previous subscription
    _subscription = Gamepads.events.listen((event) async {
      _recvEvent = event;

      var curAbsValue = _recvEvent.value.abs();

      // Get the value with the most detections
      double maxValue = 0;
      int maxCount = 0;
      MappingResult? maxResult;
      _mappingResults.forEach((key, value) {
        if (value.count > maxCount) {
          maxCount = value.count;
          maxResult = value;
        }
        if (value.value >= maxValue) {
          maxValue = value.value;
        }
      });

      int detect_count = 10;

      // If detection count exceeds threshold, consider mapping complete
      if (maxCount >= detect_count) {
        _editingKey = "";
        // _mappedKeys[maxResult!.event!.key] = maxResult!.key;
        print(maxResult);
        _mappingResults = {};
        _editingKey = "";
        // Show success popup
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mapping successful, current key mapped to ${maxResult!.key}')),
          );
        }

        // Save mapping
        if (_editingKey == "Left Stick Up") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.leftAxisY);
          // Up is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Left Stick Down") {
          globalSetting.axisMapping[maxResult!.key]!.minValue =
              maxResult!.value;
        } else if (_editingKey == "Left Stick Left") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.leftAxisX);
          // Right is positive value
          if (maxResult!.value > 0) {
            j_event.reverse = true;
          }
          j_event.minValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Left Stick Right") {
          globalSetting.axisMapping[maxResult!.key]!.maxValue =
              maxResult!.value;
        } else if (_editingKey == "Right Stick Up") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.rightAxisY);
          // Up is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Right Stick Down") {
          globalSetting.axisMapping[maxResult!.key]!.minValue =
              maxResult!.value;
        } else if (_editingKey == "Right Stick Left") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.rightAxisX);
          // Right is positive value
          if (maxResult!.value > 0) {
            j_event.reverse = true;
          }
          j_event.minValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Right Stick Right") {
          globalSetting.axisMapping[maxResult!.key]!.maxValue =
              maxResult!.value;
        } else if (_editingKey == "Button A") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.buttonA);
          // Right is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Button B") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.buttonB);
          // Right is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Button X") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.buttonX);
          // Right is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        } else if (_editingKey == "Button Y") {
          JoyStickEvent j_event = JoyStickEvent(KeyName.buttonY);
          // Right is positive value
          if (maxResult!.value < 0) {
            j_event.reverse = true;
          }
          j_event.maxValue = maxResult!.value;

          globalSetting.axisMapping[maxResult!.key] = j_event;
        }
        globalSetting.saveGamepadMapping();

        return;
      }

      // If currently mapping, record detected values
      if (curAbsValue > 0 && _editingKey.isNotEmpty) {
        print("${_recvEvent.key}: ${curAbsValue}");
        if (_mappingResults.containsKey(_recvEvent.key)) {
          if (curAbsValue >= _mappingResults[_recvEvent.key]!.value.abs() &&
              curAbsValue >= maxValue) {
            _mappingResults[_recvEvent.key]!.count++;
            _mappingResults[_recvEvent.key]!.value = event.value;
          }
        } else {
          _mappingResults[_recvEvent.key] = MappingResult(
              key: _recvEvent.key,
              value: event.value,
              event: _recvEvent,
              count: 1);
        }
      }
      _msg =
          'Please move the stick or press the button to this position multiple times. Current detected value: ${_recvEvent.key}: ${_recvEvent.value.toStringAsFixed(2)}, Best value: ${maxResult?.key}: ${maxResult?.value.toStringAsFixed(2)} Still need ${detect_count - maxCount} more detections';
      setState(() {});
    });
  }

  Widget _buildMappingTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Key')),
          DataColumn(label: Text('Action')),
        ],
        rows: [
          _buildDataRow('Left Stick Up'),
          _buildDataRow('Left Stick Down'),
          _buildDataRow('Left Stick Left'),
          _buildDataRow('Left Stick Right'),
          _buildDataRow('Right Stick Up'),
          _buildDataRow('Right Stick Down'),
          _buildDataRow('Right Stick Left'),
          _buildDataRow('Right Stick Right'),
          ...globalSetting.buttonMapping.keys
              .map((key) => _buildDataRow(_translateKey(key))),
        ],
      ),
    );
  }

  void _showPersistentBottomMessage(BuildContext context, String message) {
    _removePersistentBottomMessage(); // Remove previous OverlayEntry first
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 50.0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            margin: const EdgeInsets.symmetric(horizontal: 24.0),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    Overlay.of(context)?.insert(_overlayEntry!);
  }

  void _removePersistentBottomMessage() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  DataRow _buildDataRow(String key) {
    bool isEditing = _editingKey == key;

    return DataRow(
      cells: [
        DataCell(Text(key)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEditing) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _editingKey = "";
                    _mappingResults = {};

                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                  ),
                  child: const Text('Cancel'),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: () {
                    // Start remapping
                    setState(() {
                      _editingKey = key;
                      _mappingResults = {};
                      _msg = AppLocalizations.of(context)!.start_mapping_message;
                      _startListening();
                    });
                  },
                  child: Text(AppLocalizations.of(context)!.remap),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _translateKey(String key) {
    final translations = {
      "AXIS_X": AppLocalizations.of(context)!.left_stick_x,
      "AXIS_Y": AppLocalizations.of(context)!.left_stick_y,
      "AXIS_Z": AppLocalizations.of(context)!.right_stick_x,
      "AXIS_RZ": AppLocalizations.of(context)!.right_stick_y,
      // "triggerRight": "Right Trigger",
      // "triggerLeft": "Left Trigger",
      // "buttonLeftRight": "D-Pad Left/Right",
      // "buttonUpDown": "D-Pad Up/Down",
      "KEYCODE_BUTTON_A": AppLocalizations.of(context)!.button_a,
      "KEYCODE_BUTTON_B": AppLocalizations.of(context)!.button_b,
      "KEYCODE_BUTTON_X": AppLocalizations.of(context)!.button_x,
      "KEYCODE_BUTTON_Y": AppLocalizations.of(context)!.button_y,
      // "KEYCODE_BUTTON_L1": "Button L1",
      // "KEYCODE_BUTTON_R1": "Button R1",
    };
    return translations[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.gamepad_mapping),
        actions: [
          IconButton(
            icon: const Icon(Icons.reset_tv),
            onPressed: () async {
              await globalSetting.resetGamepadMapping();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.mapping_reset)),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildMappingTable(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _editingKey.isNotEmpty
          ? Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _msg,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
