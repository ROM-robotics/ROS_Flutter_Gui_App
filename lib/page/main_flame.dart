import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame_svg/flame_svg.dart';
import 'package:flame_svg/svg_component.dart';
import 'package:flutter/material.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/display/map.dart';
import 'package:ros_flutter_gui_app/display/grid.dart';
import 'package:ros_flutter_gui_app/display/pointcloud.dart';
import 'package:ros_flutter_gui_app/display/path.dart';
import 'package:ros_flutter_gui_app/display/laser.dart';
import 'package:ros_flutter_gui_app/basic/RobotPose.dart';
import 'package:ros_flutter_gui_app/display/costmap.dart';
import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:ros_flutter_gui_app/display/pose.dart';
import 'package:ros_flutter_gui_app/display/topology_line.dart';
import 'package:ros_flutter_gui_app/display/polygon.dart' as custom;
import 'package:ros_flutter_gui_app/provider/global_state.dart';
import 'package:ros_flutter_gui_app/provider/them_provider.dart';
import 'package:ros_flutter_gui_app/global/setting.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:ros_flutter_gui_app/provider/nav_point_manager.dart';
import 'dart:math';
import 'package:ros_flutter_gui_app/display/pose.dart';

class MainFlame extends FlameGame {
  late MapComponent _displayMap;
  late GridComponent _displayGrid;
  final RosChannel? rosChannel;
  final ThemeProvider? themeProvider;
  late PoseComponent _displayRobot;

  List<NavPoint> offLineNavPoints = [];

  // New Flame component
  late LaserComponent _laserComponent;
  late PathComponent _tracePathComponent;
  late PointCloudComponent _pointCloudComponent;
  late PathComponent _globalPathComponent;
  late PathComponent _localPathComponent;
  late CostMapComponent _globalCostMapComponent;
  late CostMapComponent _localCostMapComponent;
  
  // Topology layer component
  late TopologyLine _topologyLineComponent;
  late List<PoseComponent> _wayPointComponents;
  
  // Robot footprint component
  late custom.PolygonComponent _robotFootprintComponent;
  
  // Global state reference
  late GlobalState globalState;
  
  // NavPointManager instance
  late NavPointManager navPointManager;
  
  // Add right-side info panel related variables
  PoseComponent? selectedWayPoint;
  bool _showInfoPanel = false;
  Function(NavPoint?)? onNavPointTap;
  
  final double minScale = 0.01;
  final double maxScale = 10.0;

  bool isDarkMode=true;

  // Map transformation parameters (using camera.viewfinder)
  double mapScale = 1.0;
  Vector2 mapOffset = Vector2.zero();
  
  // Gesture-related variables
  double _baseScale = 1.0;
  Vector2? _lastFocalPoint;

  bool isRelocMode = false;
  RobotPose relocRobotPose = RobotPose(0, 0, 0);
  
  MainFlame({
    this.rosChannel, 
    this.themeProvider,
    required GlobalState globalState,
    required NavPointManager navPointManager,
  }) {
    this.globalState = globalState;
    this.navPointManager = navPointManager;
    // Initialize theme mode
    isDarkMode = themeProvider?.themeMode == ThemeMode.dark;
  }
  
  @override
  Color backgroundColor() => isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
  
  @override
  Future<void> onLoad() async {
    super.onLoad();
    
        // Load layer settings
       await globalState.loadLayerSettings();
    
       // Add map component
      _displayMap = MapComponent(rosChannel: rosChannel);
      world.add(_displayMap);
      _displayMap.updateThemeMode(isDarkMode);

     _displayGrid = GridComponent(
      size: size,
      rosChannel: rosChannel,
    );
    _displayGrid.updateThemeMode(isDarkMode);

    _globalCostMapComponent = CostMapComponent(
      opacity: 0.3,
      isGlobal: true
    );
    
    _localCostMapComponent = CostMapComponent(
      opacity: 0.5,
      isGlobal: false
    );

    // Initialize new Flame components
    _laserComponent = LaserComponent(pointList: []);
    
    _pointCloudComponent = PointCloudComponent(
      pointList: [], 
      map: rosChannel!.map.value
    );
    
    _globalPathComponent = PathComponent(
      pointList: [], 
      color: Colors.blue
    );
     _globalPathComponent.priority = 149;
    
    _localPathComponent = PathComponent(
      pointList: [], 
      color: Colors.green
    );
    _localPathComponent.priority = 151;

    _tracePathComponent = PathComponent(
      pointList: [], 
      color: Colors.yellow
    );
    _tracePathComponent.priority = 150;

    // Initialize topology layer component
    _topologyLineComponent = TopologyLine(
      points: [],
      routes: [],
      rosChannel: rosChannel, // Pass rosChannel to get map data
    );
    
    // Initialize robot outline component
    _robotFootprintComponent = custom.PolygonComponent(
      pointList: [],
      color: Colors.green.withAlpha(50),
      enableWaterDropAnimation: false, // Enable water ripple animation
    );
    _robotFootprintComponent.priority = 1001;
    
    // Add to world immediately to ensure animation system works
    world.add(_robotFootprintComponent);
    
    // Robot position - place on top layer
    _displayRobot = PoseComponent(
      PoseComponentSize: globalSetting.robotSize,
      color: Colors.blue,
      count: 2,
      isEditMode: false,
      onPoseChanged: (RobotPose pose) {
       relocRobotPose=pose;
      },
      rosChannel: rosChannel,
      poseType: PoseType.robot,
    );
    _displayRobot.priority = 1002;
    world.add(_displayRobot);

    _wayPointComponents = [];
    
    // Listen to ROS data updates
    _setupRosListeners();
    
    // Set up layer state listening
    _setupLayerListeners();
    
    // Add components based on initial layer state
    _initializeLayerComponents();

  }
 
 

  RobotPose getRelocRobotPose(){
    return relocRobotPose;
  }
  
  void setRelocMode(bool isReloc){
    _displayRobot.setEditMode(isReloc);
    isRelocMode=isReloc;
    if(!isReloc){
      camera..viewfinder..stop();
    }
  }

      // Load navigation points
  Future<void> _loadOfflineNavPoints() async {
    // Use the passed NavPointManager instance
    offLineNavPoints = await navPointManager.loadNavPoints();
    
    // If map is already loaded, update topology layer immediately
    if (rosChannel?.map_.value != null) {
      _updateTopologyLayers();
    }
  }
  
  // Reload navigation points and map data
  Future<void> reloadNavPointsAndMap() async {
    print('Reloading navigation points and map data...');
    
    // Reload offline navigation points
    await _loadOfflineNavPoints();
    
    // If map is already loaded, update topology layer again
    if (rosChannel?.map_.value != null) {
      _updateTopologyLayers();
    }
    
    print('Navigation points and map data reload completed');
  }

  void _setupRosListeners() {
    rosChannel!.robotPoseMap.addListener(() {
      // Use new updatePose method to update robot position
      if(isRelocMode) return;
      _displayRobot.updatePose(rosChannel!.robotPoseMap.value);
      relocRobotPose=rosChannel!.robotPoseMap.value;
    });
    
    // Listen to robot footprint data
    rosChannel!.robotFootprint.addListener(() {
      final footprintPoints = rosChannel!.robotFootprint.value;
        _robotFootprintComponent.updatePointList(footprintPoints);
      
    });
    
    // Listen to laser radar data
    rosChannel!.laserPointData.addListener(() {
      if(rosChannel!.map_.value == null || rosChannel!.map_.value.mapConfig.resolution <= 0 || rosChannel!.map_.value.height() <= 0) return;
      final laserPoints = rosChannel!.laserPointData.value;
      var robotPose = laserPoints.robotPose;
      if(isRelocMode){
        robotPose=relocRobotPose;
      }
      List<Vector2> vector2Points =[];
      for (int i = 0; i < laserPoints.laserPoseBaseLink.length; i++) {
        final laserPointMap=absoluteSum(robotPose, RobotPose(laserPoints.laserPoseBaseLink[i].x, laserPoints.laserPoseBaseLink[i].y, 0));
        vm.Vector2 laserPointScene=rosChannel!.map_.value.xy2idx(vm.Vector2(laserPointMap.x, laserPointMap.y));
        vector2Points.add(Vector2(laserPointScene.x, laserPointScene.y));
      }
      _laserComponent.updateLaser(vector2Points);
    });
    
    // Listen to point cloud data
    rosChannel!.pointCloud2Data.addListener(() {
      final pointCloudData = rosChannel!.pointCloud2Data.value;
      _pointCloudComponent.updatePoints(pointCloudData);
    });
    
    // Listen to global path
    rosChannel!.globalPath.addListener(() {
      final globalPathPoints = rosChannel!.globalPath.value;
      _globalPathComponent.updatePath(globalPathPoints);
    });
    
    // Listen to local path
    rosChannel!.localPath.addListener(() {
      final localPathPoints = rosChannel!.localPath.value;
      _localPathComponent.updatePath(localPathPoints);
    });

    // Listen to trace path
    rosChannel!.tracePath.addListener(() {
      final tracePathPoints = rosChannel!.tracePath.value;
      _tracePathComponent.updatePath(tracePathPoints);
    });
    
    // Listen to cost map
    rosChannel!.globalCostmap.addListener(() {
      _globalCostMapComponent.updateCostMap(rosChannel!.globalCostmap.value);
    });
    
    rosChannel!.localCostmap.addListener(() {
      _localCostMapComponent.updateCostMap(rosChannel!.localCostmap.value);
    });
    
    // Listen to map data
    rosChannel!.map_.addListener(() {
      _displayMap.updateMapData(rosChannel!.map_.value);
    });
    
    // Listen to topology map data
    rosChannel!.topologyMap_.addListener(() {
      _updateTopologyLayers();
    });
    
    // Immediately update map data
    _displayMap.updateMapData(rosChannel!.map_.value);

    _loadOfflineNavPoints();
    
    // Immediately update topology layer data
    _updateTopologyLayers();
  }

  
  // Handle zoom start
  bool onScaleStart(Vector2 position) {
    _baseScale = mapScale;
    _lastFocalPoint = position;
    
    return true;
  }
  
  // Handle zoom update (simultaneously handle drag and zoom)
  bool onScaleUpdate(double scale, Vector2 position) {
    if (_lastFocalPoint == null) return false;
    
    // Map zoom/move
    final newScale = (_baseScale * scale).clamp(minScale, maxScale);
    mapScale = newScale;
    camera.viewfinder.zoom = mapScale;
    
    final focalPointDelta = position - _lastFocalPoint!;
    camera.viewfinder.position -= focalPointDelta / camera.viewfinder.zoom;
    
    _lastFocalPoint = position;
    return true;
  }
  
  // Handle zoom end
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
    
    // Apply zoom
    camera.viewfinder.zoom = newZoom;
    mapScale = newZoom;
    
    // Adjust camera position to keep mouse position unchanged
    final newScreenPoint = camera.localToGlobal(worldPoint);
    final offset = position - newScreenPoint;
    camera.viewfinder.position -= offset / camera.viewfinder.zoom;
    
    return true;
  }

  
  void centerOnRobot(bool isCenterOnRobot) {
    if(isCenterOnRobot){
     camera.follow(_displayRobot);
    }else{
     camera.stop();
    }
    camera.viewfinder.zoom = 6.0;
    mapScale = 6.0;
  }
  
  void zoomIn() {
    mapScale = (mapScale * 1.2).clamp(minScale, maxScale);
    camera.viewfinder.zoom = mapScale;
  }
  
  void zoomOut() {
    mapScale = (mapScale / 1.2).clamp(minScale, maxScale);
    camera.viewfinder.zoom = mapScale;
  }
  
  // Simplified implementation, keep only basic click effects

  @override
  void update(double dt) {
    super.update(dt);
    // Game logic updates can be added here
  }
  
  // Update topology layer
  void _updateTopologyLayers() {

    // When online navigation points exist, no longer display offline navigation points
    if (rosChannel?.topologyMap_.value == null) {
      print('Topology map data is empty, skip update');
      return;
    }
    
    final topologyMap = rosChannel!.topologyMap_.value;
    
    print('Update online topology layer: ${topologyMap.points.length} points, ${topologyMap.routes.length} routes, offline navigation points: ${offLineNavPoints.length}');
    
    List<NavPoint> navPoints =offLineNavPoints;
    if(topologyMap.points.isNotEmpty){
      navPoints = List<NavPoint>.from(topologyMap.points);
      print('Using online topology points');
    }

    // Update topology line component data, but don't add directly to world
    _topologyLineComponent.removeFromParent();
    _topologyLineComponent = TopologyLine(
      points: topologyMap.points,
      routes: topologyMap.routes,
      rosChannel: rosChannel, // Pass rosChannel parameter
    );
    
    // Clear old waypoint components
    for (final waypoint in _wayPointComponents) {
      waypoint.removeFromParent();
    }
    _wayPointComponents.clear();
    
 

    
  
    // Create new waypoint components
    for (final point in navPoints) {
      final waypoint = PoseComponent(
        PoseComponentSize: globalSetting.robotSize,
        color: Colors.green,
        count: 2,
        isEditMode: false,
        direction: point.theta,
        navPoint: point,
        rosChannel: rosChannel,
        poseType: PoseType.waypoint,
      );

      // Set waypoint position (using map index coordinates)
      waypoint.updatePose(RobotPose(point.x, point.y, point.theta));
      print('waypoint: ${waypoint.position} point: $point');
      _wayPointComponents.add(waypoint);
      
    }
    
    // Decide whether to add to world based on current layer state
    if (globalState.isLayerVisible('showTopology')) {
      // Add topology line component
      if (!world.contains(_topologyLineComponent)) {
        world.add(_topologyLineComponent);
      }
      
      // Add all navigation point components
      for (final waypoint in _wayPointComponents) {
        if (!world.contains(waypoint)) {
          world.add(waypoint);
        }
      }
      
      print('Topology layer updated, displaying ${_wayPointComponents.length} navigation points');
    } else {
      print('Topology layer not visible, removing all navigation point components');
      // When layer is not visible, remove all navigation point components
      for (final waypoint in _wayPointComponents) {
        if (world.contains(waypoint)) {
          waypoint.removeFromParent();
        }
      }
    }
  }
  
  // Set up layer state listening
  void _setupLayerListeners() {
    print('Setting up layer state listeners...');
    
    // Define layer component mapping
    final layerComponentMap = <String, Component>{
      'showGrid': _displayGrid,
      'showGlobalCostmap': _globalCostMapComponent,
      'showLocalCostmap': _localCostMapComponent,
      'showLaser': _laserComponent,
      'showPointCloud': _pointCloudComponent,
      'showGlobalPath': _globalPathComponent,
      'showLocalPath': _localPathComponent,
      'showTracePath': _tracePathComponent,
      'showTopology': _topologyLineComponent,
      'showRobotFootprint': _robotFootprintComponent,
    };
    
    // Set up listener for each layer
    for (final entry in layerComponentMap.entries) {
      final layerName = entry.key;
      final component = entry.value;
      
      print('Setting up listener for layer $layerName');
      
      globalState.getLayerState(layerName).addListener(() {
        final isVisible = globalState.isLayerVisible(layerName);
        print('Layer $layerName state changed: $isVisible');
        
        if (isVisible) {
          if (!world.contains(component)) {
            print('Adding component $layerName to world');
            world.add(component);
          }
        } else {
          if (world.contains(component)) {
            print('Removing component $layerName from world');
            // Add safety check to ensure component is still valid
            if (component.isMounted) {
              component.removeFromParent();
            }
          }
        }
      });
    }
    
    // Special handling for topology layer waypoints
    globalState.getLayerState('showTopology').addListener(() {
      final isVisible = globalState.isLayerVisible('showTopology');
      print('Topology layer state changed: $isVisible');
      
      if (isVisible) {
        if (!world.contains(_topologyLineComponent)) {
          world.add(_topologyLineComponent);
        }
        for (final waypoint in _wayPointComponents) {
          if (!world.contains(waypoint)) {
            world.add(waypoint);
          }
        }
      } else {
        if (world.contains(_topologyLineComponent)) {
          if (_topologyLineComponent.isMounted) {
            _topologyLineComponent.removeFromParent();
          }
        }
        for (final waypoint in _wayPointComponents) {
          if (world.contains(waypoint)) {
            if (waypoint.isMounted) {
              waypoint.removeFromParent();
            }
          }
        }
      }
    });
    
    // Set component display based on initial state
    _updateLayerVisibility();
  }
  
  // Update component visibility based on layer state
  void _updateLayerVisibility() {
    // Define layer component mapping
    final layerComponentMap = <String, Component>{
      'showGrid': _displayGrid,
      'showGlobalCostmap': _globalCostMapComponent,
      'showLocalCostmap': _localCostMapComponent,
      'showLaser': _laserComponent,
      'showPointCloud': _pointCloudComponent,
      'showGlobalPath': _globalPathComponent,
      'showLocalPath': _localPathComponent,
      'showTracePath': _tracePathComponent,
      'showTopology': _topologyLineComponent,
      'showRobotFootprint': _robotFootprintComponent,
    };
    
    // Check visibility of each layer
    for (final entry in layerComponentMap.entries) {
      final layerName = entry.key;
      final component = entry.value;
      
      if (!globalState.isLayerVisible(layerName) && world.contains(component)) {
        component.removeFromParent();
      }
    }
    
    // Special handling for topology layer waypoints
    if (!globalState.isLayerVisible('showTopology')) {
      for (final waypoint in _wayPointComponents) {
        if (world.contains(waypoint)) {
          waypoint.removeFromParent();
        }
      }
    }
  }

  // Add components based on initial layer state
  void _initializeLayerComponents() {
    print('Initializing layer components...');
    
    final layerComponentMap = <String, Component>{
      'showGrid': _displayGrid,
      'showGlobalCostmap': _globalCostMapComponent,
      'showLocalCostmap': _localCostMapComponent,
      'showLaser': _laserComponent,
      'showPointCloud': _pointCloudComponent,
      'showGlobalPath': _globalPathComponent,
      'showLocalPath': _localPathComponent,
      'showTracePath': _tracePathComponent,
      'showTopology': _topologyLineComponent,
      'showRobotFootprint': _robotFootprintComponent,
    };

    for (final entry in layerComponentMap.entries) {
      final layerName = entry.key;
      final component = entry.value;
      final isVisible = globalState.isLayerVisible(layerName);
      
      print('Layer $layerName initial state: $isVisible');

      if (isVisible) {
        if (!world.contains(component)) {
          print('Initially adding component $layerName to world');
          world.add(component);
        }
      } else {
        if (world.contains(component)) {
          print('Initially removing component $layerName from world');
          if (component.isMounted) {
            component.removeFromParent();
          }
        }
      }
    }

    // Special handling for topology layer waypoints
    final topologyVisible = globalState.isLayerVisible('showTopology');
    print('Topology layer initial state: $topologyVisible');
    
    if (topologyVisible) {
      if (!world.contains(_topologyLineComponent)) {
        world.add(_topologyLineComponent);
      }
      for (final waypoint in _wayPointComponents) {
        if (!world.contains(waypoint)) {
          world.add(waypoint);
        }
      }
    } else {
      if (world.contains(_topologyLineComponent)) {
        _topologyLineComponent.removeFromParent();
      }
      for (final waypoint in _wayPointComponents) {
        if (world.contains(waypoint)) {
          waypoint.removeFromParent();
        }
      }
    }
  }
  

  NavPoint? getSelectedWayPointInfo() {
    final wayPoint = selectedWayPoint;
    if (wayPoint == null) return null;
    var x = wayPoint.position.x;
    var y = wayPoint.position.y;
    var direction = -wayPoint.direction;
    double mapx = 0;
    double mapy = 0;
    if(rosChannel?.map_.value != null){
      vm.Vector2 mapPose = rosChannel!.map_.value.idx2xy(vm.Vector2(x, y));
      mapx = mapPose.x;
      mapy = mapPose.y;
    }
    var pointInfo = wayPoint.getPointInfo();
    pointInfo!.x = mapx;
    pointInfo!.y = mapy;
    pointInfo!.theta = direction;
    return pointInfo;
  }


  
  // Get info panel display state
  bool get showInfoPanel => _showInfoPanel;
  
  // Hide info panel
  void hideInfoPanel() {
    _showInfoPanel = false;
  }
  
  // Detect clicked waypoint
  void onTap(Offset position) {

    // Use camera.globalToLocal to convert coordinates, refer to map_edit_flame.dart implementation
    final worldPoint = camera.globalToLocal(Vector2(position.dx, position.dy));

  
    for (int i = 0; i < _wayPointComponents.length; i++) {
      final waypoint = _wayPointComponents[i];
      
      if (waypoint.containsPoint(worldPoint)) {
        if (waypoint.navPoint != null) {
          selectedWayPoint = waypoint;
          _showInfoPanel = true;
          onNavPointTap?.call(getSelectedWayPointInfo()!);
          print('Selected navigation point: ${waypoint.navPoint!.name}');
        } 
       return;
      }
    }
  
   _showInfoPanel=false;
    onNavPointTap?.call(null);
  }
  
  // Set robot edit mode
  void setRobotEditMode(bool edit) {
    _displayRobot.setEditMode(edit);
  }
  
 
  

}