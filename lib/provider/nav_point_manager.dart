import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:flutter/foundation.dart';

class NavPointManager extends ChangeNotifier {
  static const String _navPointsKey = 'topology_points';
  
  // Singleton pattern
  static final NavPointManager _instance = NavPointManager._internal();
  factory NavPointManager() => _instance;
  NavPointManager._internal();

  // Navigation points list
  List<NavPoint> _navPoints = [];
  
  // Get navigation points list
  List<NavPoint> get navPoints => List.unmodifiable(_navPoints);
  
  // Add navigation point
  Future<NavPoint> addNavPoint(double x, double y, double theta, String name) async {
    final counter = await getNextId();
    final navPoint = NavPoint(
      x: x,
      y: y,
      theta: theta,
      name: name,
      type: NavPointType.navGoal,
    );
    
    _navPoints.add(navPoint);
    await saveNavPoints(_navPoints);
    notifyListeners(); // Notify listeners that data has changed
    return navPoint;
  }
  
  // Remove navigation point
  Future<void> removeNavPoint(String name) async {
    _navPoints.removeWhere((point) => point.name == name);
    await saveNavPoints(_navPoints);
    notifyListeners(); // Notify listeners that data has changed
  }
  

  
  // Get next ID
  Future<int> getNextId() async {
    // Find the smallest available ID
    int nextId = 0;
    final existingIds = navPoints.map((point) => int.tryParse(point.name.split('_')[1]) ?? -1).toSet();
    
    while (existingIds.contains(nextId)) {
      nextId++;
    }
    return nextId;
  }


  
  // Save navigation points to local storage
  Future<void> saveNavPoints(List<NavPoint> navPoints) async {
    _navPoints = navPoints;
    final prefs = await SharedPreferences.getInstance();
    final navPointsJson = navPoints.map((point) => point.toJson()).toList();
    await prefs.setString(_navPointsKey, jsonEncode(navPointsJson));
    notifyListeners(); // Notify listeners that data has changed
  }
  
  // Load navigation points from local storage
  Future<List<NavPoint>> loadNavPoints() async {
    final prefs = await SharedPreferences.getInstance();
    final navPointsStr = prefs.getString(_navPointsKey);
    
    if (navPointsStr != null) {
      try {
        final navPointsJson = jsonDecode(navPointsStr) as List;
        _navPoints = navPointsJson
            .map((json) => NavPoint.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        print('Failed to load navigation points: $e');
        _navPoints = [];
      }
    }
    return _navPoints;
  }
  
  // Clear all navigation points
  Future<void> clearAllNavPoints() async {
    _navPoints.clear();
    await saveNavPoints(_navPoints);
    notifyListeners(); // Notify listeners that data has changed
  }
  
  // Export navigation points as JSON string
  String exportToJson() {
    final navPointsJson = _navPoints.map((point) => point.toJson()).toList();
    return jsonEncode(navPointsJson);
  }
  
  // Import navigation points from JSON string
  Future<void> importFromJson(String jsonString) async {
    try {
      final navPointsJson = jsonDecode(jsonString) as List;
      _navPoints = navPointsJson
          .map((json) => NavPoint.fromJson(json as Map<String, dynamic>))
          .toList();
      await saveNavPoints(_navPoints);
      notifyListeners(); // Notify listeners that data has changed
    } catch (e) {
      print('Failed to import navigation points: $e');
      throw Exception('Import failed: Invalid JSON format');
    }
  }
}
