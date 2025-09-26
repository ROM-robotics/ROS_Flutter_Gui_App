import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:ros_flutter_gui_app/display/map.dart';
import 'package:ros_flutter_gui_app/display/grid.dart';
import 'package:ros_flutter_gui_app/display/pose.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/provider/them_provider.dart';
import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ros_flutter_gui_app/global/setting.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:ros_flutter_gui_app/basic/RobotPose.dart';
import 'package:ros_flutter_gui_app/page/map_edit_page.dart';


// Dedicated map editing Flame component
class MapEditFlame extends FlameGame {
  late MapComponent _displayMap;
  late GridComponent _displayGrid;
  final RosChannel? rosChannel;
  final ThemeProvider? themeProvider;
  
  final double minScale = 0.01;
  final double maxScale = 10.0;

  RobotPose currentRobotPose = RobotPose.zero();
  
  // Map transformation parameters
  double mapScale = 1.0;
  
  // Theme mode
  bool isDarkMode = true;
  
  // Currently selected editing tool
  EditToolType? selectedTool;
  
  // Callback function to notify external addition of navigation points
  Future<NavPoint?> Function(double x, double y)? onAddNavPoint;
  
  // Callback function to notify external navigation point selection state changes
  VoidCallback? onWayPointSelectionChanged;
  
  // Callback function to notify external dynamic updates of currently selected points
  VoidCallback? currentSelectPointUpdate;
  
  // Navigation point component list
  final List<PoseComponent> wayPoints = [];
  
  PoseComponent? currentSelectedWayPoint;
  
  // Gesture-related variables
  double _baseScale = 1.0;
  Vector2? _lastFocalPoint;
  
  MapEditFlame({
    this.rosChannel, 
    this.themeProvider,
    this.onAddNavPoint, 
    this.onWayPointSelectionChanged,
    this.currentSelectPointUpdate,
  }) {
    // Initialize theme mode
    isDarkMode = themeProvider?.themeMode == ThemeMode.dark;
  }
  
  @override
  Color backgroundColor() => isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
  
  

  
  // Set currently selected tool
  void setSelectedTool(EditToolType? tool) {
    selectedTool = tool;
  }
  
  // Add navigation point using current robot position
  Future<void> addNavPointAtRobotPosition() async {
    if (selectedTool != EditToolType.addNavPoint) return;
    
    // Add navigation point using current robot position
    final result = await onAddNavPoint!(currentRobotPose.x, currentRobotPose.y);
    if (result != null) {
      print('Added navigation point using robot position: $result x: ${currentRobotPose.x} y: ${currentRobotPose.y}');
      // Create new navigation point using robot's current orientation
      final navPointWithRobotPose = NavPoint(
        name: result.name,
        x: currentRobotPose.x,
        y: currentRobotPose.y,
        theta: currentRobotPose.theta,
        type: result.type,
      );
      addWayPoint(navPointWithRobotPose);
    } else {
      print('User cancelled adding navigation point using robot position');
    }
  }
  
  // Get currently selected navigation point
  PoseComponent? get selectedWayPoint {
    return currentSelectedWayPoint;
  }
  
  // Get information of currently selected navigation point
  NavPoint? getSelectedWayPointInfo() {
    final wayPoint = selectedWayPoint;
    if (wayPoint == null) return null;
    var x = wayPoint.position.x;
    var y = wayPoint.position.y;
    var direction = -wayPoint.direction;
    double mapx = 0;
    double mapy = 0;
    if(rosChannel != null && rosChannel!.map_.value != null){
      vm.Vector2 mapPose = rosChannel!.map_.value.idx2xy(vm.Vector2(x, y));
      mapx = mapPose.x;
      mapy = mapPose.y;
    }

    var pointInfo = wayPoint.getPointInfo();
    if (pointInfo != null) {
      pointInfo.x=mapx;
      pointInfo.y=mapy;
      pointInfo.theta=direction;
    }

    return pointInfo;
  }
  
  // Get information of all navigation points
  List<NavPoint> getAllWayPoint() {
    List<NavPoint> allWayPoints = [];
    
    for (int i = 0; i < wayPoints.length; i++) {
      final wayPoint = wayPoints[i];
      var x = wayPoint.position.x;
      var y = wayPoint.position.y;
      var direction = -wayPoint.direction;
      double mapx = 0;
      double mapy = 0;
      
      if (rosChannel != null && rosChannel!.map_.value != null) {
        vm.Vector2 mapPose = rosChannel!.map_.value.idx2xy(vm.Vector2(x, y));
        mapx = mapPose.x;
        mapy = mapPose.y;
      }

      var pointInfo = wayPoint.getPointInfo();
      if (pointInfo != null) {
        pointInfo.x=mapx;
        pointInfo.y=mapy;
        pointInfo.theta=direction;
      }
      
      allWayPoints.add(pointInfo!);
    }
    
    return allWayPoints;
  }
  
  @override
  Future<void> onLoad() async {
    super.onLoad();
    
    // Add map component
    _displayMap = MapComponent(rosChannel: rosChannel);
    world.add(_displayMap);
    _displayMap.updateThemeMode(isDarkMode);
    
    // Add grid component
    _displayGrid = GridComponent(
      size: size,
      rosChannel: rosChannel,
    );
    _displayGrid.updateThemeMode(isDarkMode);
    world.add(_displayGrid);
    
    // Set up ROS listeners
    _setupRosListeners();
  }
  
  void _setupRosListeners() {
    if (rosChannel != null) {
      // Listen for map data
      rosChannel!.map_.addListener(() {
        _displayMap.updateMapData(rosChannel!.map_.value);
      });

      rosChannel!.robotPoseMap.addListener(() {
        currentRobotPose = rosChannel!.robotPoseMap.value;
      });
      
      // Immediately update map data
      _displayMap.updateMapData(rosChannel!.map_.value);
    }
  }
  
  // Handle single click events, implement double-click detection
  Future<bool> onTapDown(Vector2 position) async {
    if (selectedTool == EditToolType.addNavPoint) {
      // position is GestureDetector.localPosition
      final worldPoint = camera.globalToLocal(position);
      final clickedWayPoint = _findWayPointAtPosition(worldPoint);
      
      if (clickedWayPoint != null) {
        print('clickedWayPoint: ${clickedWayPoint.navPoint?.name}');
        // Select navigation point
        _selectWayPoint(clickedWayPoint);
        currentSelectPointUpdate?.call();
        return true;
      }
        double mapX=0;
        double mapY=0;
        if(rosChannel != null && rosChannel!.map_.value != null){
          vm.Vector2 mapPose = rosChannel!.map_.value.idx2xy(vm.Vector2(worldPoint.x, worldPoint.y));
          mapX = mapPose.x;
          mapY = mapPose.y;
        }

        final result = await onAddNavPoint!(mapX, mapY);
        if (result != null) {
          print('Navigation point addition result: $result mapX: $mapX mapY: $mapY');
          // User confirmed the name, create new navigation point
          addWayPoint(result);
        } else {
          print('User cancelled navigation point addition');
        }
      
        return true;  
  
    }else if(selectedTool == EditToolType.drawObstacle){
      // Draw obstacles
      
      return true;
    }
    return false;
  }
  
  // Map dragging is now handled by onScaleStart/Update/End
  
  // Handle scale start
  bool onScaleStart(Vector2 position) {
    _baseScale = mapScale;
    _lastFocalPoint = position;
    return true;
  }
  
  // Handle scale update
  bool onScaleUpdate(double scale, Vector2 position) {
    if (_lastFocalPoint == null) return false;
    
    // Calculate new scale value
    final newScale = (_baseScale * scale).clamp(minScale, maxScale);
    
    // Apply scaling
    mapScale = newScale;
    camera.viewfinder.zoom = mapScale;
    
    // Calculate focal point offset
    final focalPointDelta = position - _lastFocalPoint!;
    camera.viewfinder.position -= focalPointDelta / camera.viewfinder.zoom;
    _lastFocalPoint = position;
    return true;
  }
  
  // Handle scale end
  bool onScaleEnd() {
    _lastFocalPoint = null;
    return true;
  }
  
  // Handle scroll wheel zoom
  bool onScroll(double delta, Vector2 position) {
    const zoomSensitivity = 0.5;
    double zoomChange = -delta.sign * zoomSensitivity;
    final newZoom = (camera.viewfinder.zoom + zoomChange).clamp(minScale, maxScale);
    
    // Get mouse position in world coordinates
    final worldPoint = camera.globalToLocal(position);
    
    // Apply scaling
    camera.viewfinder.zoom = newZoom;
    mapScale = newZoom;
    
    // Adjust camera position to keep mouse position unchanged
    final newScreenPoint = camera.localToGlobal(worldPoint);
    final offset = position - newScreenPoint;
    camera.viewfinder.position -= offset / camera.viewfinder.zoom;
    
    return true;
  }
  
  // Create navigation point
  PoseComponent addWayPoint(NavPoint navPoint) {
    final wayPoint = PoseComponent(
      PoseComponentSize: globalSetting.robotSize,
      color: Colors.green,
      count: 2,
      isEditMode: false,
      direction: navPoint.theta,
      onPoseChanged: (RobotPose pose) {
        // Call drag update callback
        currentSelectPointUpdate?.call();
      },
      navPoint: navPoint,
      rosChannel: rosChannel,
      poseType: PoseType.waypoint,
    );
    
    wayPoint.priority = 1000; // Ensure on top layer
    wayPoint.updatePose(RobotPose(navPoint.x, navPoint.y, navPoint.theta));

    // Add to WayPoint list and world
    wayPoints.add(wayPoint);
    world.add(wayPoint);
    
    // New point is selected by default and shows edit ring
    _selectWayPoint(wayPoint);
    wayPoint.setEditMode(false);
    return wayPoint;
  }
  
  
  // Delete selected navigation point
  String deleteSelectedWayPoint() {
    if (selectedWayPoint != null) {
      var name = selectedWayPoint?.navPoint?.name;
      wayPoints.remove(selectedWayPoint);
      selectedWayPoint?.removeFromParent();
      
      // Notify selection state change
      onWayPointSelectionChanged?.call();
      return name!;
    }
    return "";
  }
  
  // Get navigation point count
  int get wayPointCount => wayPoints.length;
  
  // Find navigation point at specified position
  PoseComponent? _findWayPointAtPosition(Vector2 position) {
    for (final wayPoint in wayPoints) {
      // Use containsPoint method to detect clicks, consistent with MainFlame implementation
      if (wayPoint.containsPoint(position)) {
        return wayPoint;
      }
    }
    currentSelectedWayPoint?.setEditMode(false);
    currentSelectedWayPoint = null;
    return null;
  }
  
  // Select navigation point
  void _selectWayPoint(PoseComponent wayPoint) {
    currentSelectedWayPoint = wayPoint;
    // Deselect other navigation points
    for (final wp in wayPoints) {
      if (wp.navPoint?.name != wayPoint.navPoint?.name) {
        wp.setEditMode(false);
      }
    }
    wayPoint.setEditMode(true);
    
    // Notify external navigation point selection state change
    onWayPointSelectionChanged?.call();
    
    // Notify external dynamic update of currently selected point
    currentSelectPointUpdate?.call();
  }
}
