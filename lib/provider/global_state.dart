import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum Mode {
  normal,
  reloc, // Relocalization mode
  addNavPoint, // Add navigation point mode
  robotFixedCenter, // Robot fixed to screen center mode
  mapEdit, // Map editing mode
}

class GlobalState extends ChangeNotifier {
  ValueNotifier<bool> isManualCtrl = ValueNotifier(false);
  ValueNotifier<Mode> mode = ValueNotifier(Mode.normal);
  // Layer toggle states - stored using Map
  final Map<String, ValueNotifier<bool>> _layerStates = {
    'showGrid': ValueNotifier(true),
    'showGlobalCostmap': ValueNotifier(false),
    'showLocalCostmap': ValueNotifier(false),
    'showLaser': ValueNotifier(false),
    'showPointCloud': ValueNotifier(false),
    'showGlobalPath': ValueNotifier(true),
    'showLocalPath': ValueNotifier(true),
    'showTracePath': ValueNotifier(true),
    'showTopology': ValueNotifier(true),
    'showRobotFootprint': ValueNotifier(true),
  };
  


  // Layer state management
  static const String _layerSettingsKey = 'layer_settings';
  
  // Get layer state
  ValueNotifier<bool> getLayerState(String layerName) {
    return _layerStates[layerName] ?? ValueNotifier(false);
  }
  
  // Set layer state
  void setLayerState(String layerName, bool value) {
    final state = _layerStates[layerName];
    if (state != null) {
      state.value = value;
      saveLayerSettings();
    }
  }
  
  // Toggle layer state
  void toggleLayer(String layerName) {
    final state = _layerStates[layerName];
    if (state != null) {
      state.value = !state.value;
      saveLayerSettings();
    }
  }

  // Save all layer states to settings
  Future<void> saveLayerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final layerSettings = <String, bool>{};
    
    _layerStates.forEach((key, valueNotifier) {
      layerSettings[key] = valueNotifier.value;
    });
    
    await prefs.setString(_layerSettingsKey, jsonEncode(layerSettings));
  }
  
  // Load layer states from settings
  Future<void> loadLayerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final layerSettingsStr = prefs.getString(_layerSettingsKey);
    
    if (layerSettingsStr != null) {
      try {
        final layerSettings = Map<String, dynamic>.from(
          jsonDecode(layerSettingsStr)
        );
        
        _layerStates.forEach((key, valueNotifier) {
          if (layerSettings.containsKey(key)) {
            valueNotifier.value = layerSettings[key] ?? false;
          }
        });
      } catch (e) {
        print('Failed to load layer settings: $e');
      }
    }
  }
  
  // Get all layer names
  List<String> get layerNames => _layerStates.keys.toList();
  
  // Check if layer is visible
  bool isLayerVisible(String layerName) {
    return _layerStates[layerName]?.value ?? false;
  }
}
