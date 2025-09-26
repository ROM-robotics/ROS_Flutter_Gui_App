import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ros_flutter_gui_app/basic/RobotPose.dart';
import 'package:ros_flutter_gui_app/basic/action_status.dart';
import 'package:ros_flutter_gui_app/basic/robot_path.dart';
import 'package:ros_flutter_gui_app/basic/tf2_dart.dart';
import 'package:ros_flutter_gui_app/basic/topology_map.dart';
import 'package:ros_flutter_gui_app/basic/transform.dart';
import 'package:ros_flutter_gui_app/global/setting.dart';
import 'package:roslibdart/roslibdart.dart';
import 'dart:async';
import 'dart:convert';
import "package:ros_flutter_gui_app/basic/occupancy_map.dart";
import 'package:ros_flutter_gui_app/basic/tf.dart';
import 'package:ros_flutter_gui_app/basic/laser_scan.dart';
import "package:ros_flutter_gui_app/basic/math.dart";
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:ros_flutter_gui_app/basic/polygon_stamped.dart';
import 'package:ros_flutter_gui_app/basic/pointcloud2.dart';
import 'package:ros_flutter_gui_app/basic/diagnostic_array.dart';
import 'package:ros_flutter_gui_app/provider/diagnostic_manager.dart';
import 'package:oktoast/oktoast.dart';

class LaserData {
  RobotPose robotPose;
  List<vm.Vector2> laserPoseBaseLink;
  LaserData({required this.robotPose, required this.laserPoseBaseLink});
}

class RobotSpeed {
  double vx;
  double vy;
  double vw;
  RobotSpeed({required this.vx, required this.vy, required this.vw});
}

class RosChannel {
  late Ros ros;
  late Topic mapChannel_;
  late Topic topologyMapChannel_;
  late Topic tfChannel_;
  late Topic tfStaticChannel_;
  late Topic laserChannel_;
  late Topic localPathChannel_;
  late Topic globalPathChannel_;
  late Topic tracePathChannel_;
  late Topic relocChannel_;
  late Topic navGoalChannel_;
  late Topic navGoalCancelChannel_;
  late Topic speedCtrlChannel_;
  late Topic odomChannel_;
  late Topic batteryChannel_;
  late Topic imageTopic_;
  late Topic navToPoseStatusChannel_;
  late Topic navThroughPosesStatusChannel_;
  late Topic robotFootprintChannel_;
  late Topic localCostmapChannel_;
  late Topic globalCostmapChannel_;
  late Topic pointCloud2Channel_;
  late Topic diagnosticChannel_;
  late Service topologyGoalService_;
  late Topic topologyMapUpdateChannel_;

  String rosUrl_ = "";
  Timer? cmdVelTimer;
  bool isReconnect_ = false;

  bool manualCtrlMode_ = false;
  ValueNotifier<double> battery_ = ValueNotifier(78);
  ValueNotifier<Uint8List> imageData = ValueNotifier(Uint8List(0));
  RobotSpeed cmdVel_ = RobotSpeed(vx: 0, vy: 0, vw: 0);
  double vxLeft_ = 0;
  ValueNotifier<RobotSpeed> robotSpeed_ =
      ValueNotifier(RobotSpeed(vx: 0, vy: 0, vw: 0));
  String url_ = "";
  TF2Dart tf_ = TF2Dart();
  ValueNotifier<OccupancyMap> map_ =
      ValueNotifier<OccupancyMap>(OccupancyMap());
  ValueNotifier<TopologyMap> topologyMap_ =
      ValueNotifier<TopologyMap>(TopologyMap(points: []));
  Status rosConnectState_ = Status.none;
  ValueNotifier<RobotPose> robotPoseMap = ValueNotifier(RobotPose.zero());
  ValueNotifier<RobotPose> robotPoseScene = ValueNotifier(RobotPose.zero());
  ValueNotifier<List<vm.Vector2>> laserBasePoint_ = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> localPath = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> globalPath = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> tracePath = ValueNotifier([]);
  ValueNotifier<LaserData> laserPointData = ValueNotifier(
      LaserData(robotPose: RobotPose(0, 0, 0), laserPoseBaseLink: []));
  ValueNotifier<ActionStatus> navStatus_ = ValueNotifier(ActionStatus.unknown);
  ValueNotifier<List<vm.Vector2>> robotFootprint = ValueNotifier([]);
  ValueNotifier<OccupancyMap> localCostmap = ValueNotifier(OccupancyMap());
  ValueNotifier<OccupancyMap> globalCostmap = ValueNotifier(OccupancyMap());
  ValueNotifier<List<Point3D>> pointCloud2Data = ValueNotifier([]);
  ValueNotifier<DiagnosticArray> diagnosticData = ValueNotifier(DiagnosticArray());
  late DiagnosticManager diagnosticManager;

  RosChannel() {
    diagnosticManager = DiagnosticManager();
    
    // Start timer to get robot real-time coordinates
    globalSetting.init().then((success) {
       // Listen for connection status

        // Get robot real-time coordinates
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (rosConnectState_ != Status.connected) return;
          try {
            robotPoseMap.value = tf_.lookUpForTransform(
                globalSetting.mapFrameName, globalSetting.baseLinkFrameName);
                            vm.Vector2 poseScene = map_.value
            .xy2idx(vm.Vector2(robotPoseMap.value.x, robotPoseMap.value.y));
        robotPoseScene.value = RobotPose(
            poseScene.x, poseScene.y, robotPoseMap.value.theta);
          } catch (e) {
            print("get robot pose error:${e}");
          }
        });

        // Reconnection
        Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (isReconnect_ && rosConnectState_ != Status.connected){
            showToast(
              "lost connection to ${rosUrl_} try reconnect...",
              position: ToastPosition.bottom,
              backgroundColor: Colors.black.withOpacity(0.8),
              textStyle: const TextStyle( color: Colors.white),
            );
            String error = await connect(rosUrl_);
                         if(error.isEmpty){
               showToast(
                 "reconnect success to ${rosUrl_}!",
                 position: ToastPosition.bottom,
                 backgroundColor: Colors.green.withOpacity(0.8),
                 textStyle: const TextStyle(color: Colors.white),
               );
             }else{
               showToast(
                 "reconnect failed to ${rosUrl_} error: $error",
                 position: ToastPosition.bottom,
                 backgroundColor: Colors.red.withOpacity(0.8),
                 textStyle: const TextStyle( color: Colors.white),
               );
            }
          }
        });
      
    });
  }


  Future<String> connect(String url) async {
    rosUrl_ = url;
    rosConnectState_ = Status.none;
    ros = Ros(url: url);

    // Set up status listener
    ros.statusStream.listen(
      (Status data) {
        rosConnectState_ = data;
      },
      onError: (error) {
        rosConnectState_ = Status.errored;
      },
      onDone: () {
        rosConnectState_ = Status.closed;
      },
      cancelOnError: false, // Set to false to keep listener working
    );

      // Try to connect
      String error = await ros.connect();
    
      if (error != "") {
        return error;
      }

      if(!isReconnect_){
        isReconnect_ = true;
      }
      
      // Connection successful, initialize channels
      Timer(const Duration(seconds: 1), () async {
        await initChannel();
      });
      return "";
      
  }

  void closeConnection() {
    robotFootprint.value.clear();
    map_.value.data.clear();
    topologyMap_.value.points.clear();
    laserBasePoint_.value.clear();
    localPath.value.clear();
    globalPath.value.clear();
    tracePath.value.clear();
    laserPointData.value.laserPoseBaseLink.clear();
    laserPointData.value.robotPose = RobotPose.zero();
    robotSpeed_.value.vx = 0;
    robotSpeed_.value.vy = 0;
    robotSpeed_.value.vw = 0;
    robotPoseMap.value = RobotPose.zero();
    robotPoseScene.value = RobotPose.zero();
    navStatus_.value = ActionStatus.unknown;
    battery_.value = 0;
    imageData.value = Uint8List(0);
    pointCloud2Data.value.clear();
    localCostmap.value.data.clear();
    globalCostmap.value.data.clear();
    diagnosticData.value = DiagnosticArray();
    cmdVel_.vx = 0;
    cmdVel_.vy = 0;
    ros.close();
  }

  ValueNotifier<OccupancyMap> get map => map_;
  Future<void> initChannel() async {
    mapChannel_ = Topic(
        ros: ros,
        name: globalSetting.mapTopic,
        type: "nav_msgs/OccupancyGrid",
        reconnectOnClose: true,
        queueLength: 10,
        queueSize: 10);
    mapChannel_.subscribe(mapCallback);

    topologyMapChannel_ = Topic(
        ros: ros,
        name: globalSetting.topologyMapTopic,
        type: "topology_msgs/TopologyMap",
        reconnectOnClose: true,
        queueLength: 10,
        queueSize: 10);
    topologyMapChannel_.subscribe(topologyMapCallback);

    navToPoseStatusChannel_ = Topic(
      ros: ros,
      name: globalSetting.navToPoseStatusTopic,
      type: "action_msgs/GoalStatusArray",
      queueSize: 1,
      reconnectOnClose: true,
    );
    navToPoseStatusChannel_.subscribe(navStatusCallback);

    navThroughPosesStatusChannel_ = Topic(
      ros: ros,
      name: globalSetting.navThroughPosesStatusTopic,
      type: "action_msgs/GoalStatusArray",
      queueSize: 1,
      reconnectOnClose: true,
    );
    navThroughPosesStatusChannel_.subscribe(navStatusCallback);

    tfChannel_ = Topic(
      ros: ros,
      name: "/tf",
      type: "tf2_msgs/TFMessage",
      queueSize: 1,
      reconnectOnClose: true,
    );
    tfChannel_.subscribe(tfCallback);

    tfStaticChannel_ = Topic(
      ros: ros,
      name: "/tf_static",
      type: "tf2_msgs/TFMessage",
      queueSize: 1,
      reconnectOnClose: true,
    );
    tfStaticChannel_.subscribe(tfStaticCallback);

    laserChannel_ = Topic(
      ros: ros,
      name: globalSetting.laserTopic,
      type: "sensor_msgs/LaserScan",
      queueSize: 1,
      reconnectOnClose: true,
    );

    laserChannel_.subscribe(laserCallback);

    localPathChannel_ = Topic(
      ros: ros,
      name: globalSetting.localPathTopic,
      type: "nav_msgs/Path",
      queueSize: 1,
      reconnectOnClose: true,
    );
    localPathChannel_.subscribe(localPathCallback);

    globalPathChannel_ = Topic(
      ros: ros,
      name: globalSetting.globalPathTopic,
      type: "nav_msgs/Path",
      queueSize: 1,
      reconnectOnClose: true,
    );
    globalPathChannel_.subscribe(globalPathCallback);

    tracePathChannel_ = Topic(
      ros: ros,
      name: globalSetting.tracePathTopic,
      type: "nav_msgs/Path",
      queueSize: 1,
      reconnectOnClose: true,
    );
    tracePathChannel_.subscribe(tracePathCallback);

    odomChannel_ = Topic(
      ros: ros,
      name: globalSetting.odomTopic,
      type: 'nav_msgs/Odometry',
      queueSize: 10,
      queueLength: 10,
    );
    odomChannel_.subscribe(odomCallback);

    batteryChannel_ = Topic(
      ros: ros,
      name: globalSetting.batteryTopic, // Battery level topic name in ROS
      type: 'sensor_msgs/BatteryState', // Message type
      queueSize: 10,
      queueLength: 10,
    );

    batteryChannel_.subscribe(batteryCallback);

    robotFootprintChannel_ = Topic(
      ros: ros,
      name: globalSetting.robotFootprintTopic,
      type: "geometry_msgs/PolygonStamped",
      queueSize: 1,
      reconnectOnClose: true,
    );
    robotFootprintChannel_.subscribe(robotFootprintCallback);

    localCostmapChannel_ = Topic(
      ros: ros,
      name: globalSetting.localCostmapTopic,
      type: "nav_msgs/OccupancyGrid",
      queueSize: 1,
      reconnectOnClose: true,
    );
    localCostmapChannel_.subscribe(localCostmapCallback);

    globalCostmapChannel_ = Topic(
      ros: ros,
      name: globalSetting.globalCostmapTopic,
      type: "nav_msgs/OccupancyGrid",
      queueSize: 1,
      reconnectOnClose: true,
    );
    globalCostmapChannel_.subscribe(globalCostmapCallback);
    
    pointCloud2Channel_ = Topic(
      ros: ros,
      name: globalSetting.pointCloud2Topic,
      type: "sensor_msgs/PointCloud2",
      queueSize: 1,
      reconnectOnClose: true,
    );
    pointCloud2Channel_.subscribe(pointCloud2Callback);

    diagnosticChannel_ = Topic(
      ros: ros,
      name: globalSetting.diagnosticTopic,
      type: "diagnostic_msgs/DiagnosticArray",
      queueSize: 1,
      reconnectOnClose: true,
    );
    diagnosticChannel_.subscribe(diagnosticCallback);

// Publishers
    relocChannel_ = Topic(
      ros: ros,
      name: globalSetting.relocTopic,
      type: "geometry_msgs/PoseWithCovarianceStamped",
      queueSize: 1,
      reconnectOnClose: true,
    );
    navGoalChannel_ = Topic(
      ros: ros,
      name: globalSetting.navGoalTopic,
      type: "geometry_msgs/PoseStamped",
      queueSize: 1,
      reconnectOnClose: true,
    );
    navGoalCancelChannel_ = Topic(
      ros: ros,
      name: "${globalSetting.navGoalTopic}/cancel",
      type: "std_msgs/Empty",
      queueSize: 1,
      reconnectOnClose: true,
    );

    topologyMapUpdateChannel_ = Topic(
        ros: ros,
        name: "${globalSetting.topologyMapTopic}/update",
        type: "topology_msgs/TopologyMap",
        reconnectOnClose: true,
        queueLength: 10,
        queueSize: 10);

    speedCtrlChannel_ = Topic(
      ros: ros,
      name: globalSetting.getConfig("SpeedCtrlTopic"),
      type: "geometry_msgs/Twist",
      queueSize: 1,
      reconnectOnClose: true,
    );

    topologyGoalService_ = Service(
      ros: ros,
      name: "/nav_to_topology_point",
      type: "topology_msgs/srv/NavToTopologyPoint"
    );

  }

  Future<Map<String, dynamic>> sendTopologyGoal(String name) async {
    Map<String, dynamic> msg = {
      "point_name": name
    };
    
    try {
      var result = await topologyGoalService_.call(msg);
      print("result: $result");
      
      // Check if result is a string (error message)
      if (result is String) {
        return {
          "is_success": false,
          "message": result
        };
      }
      
      Map<String, dynamic> resultMap =result;
      print("sendTopologyGoal result: $resultMap");
      return resultMap;
    } catch (e) {
      print("sendTopologyGoal error: $e");
      return {
        "is_success": false,
        "message": e.toString()
      };
    }
  }

  Future<void> sendNavigationGoal(RobotPose pose) async {
    vm.Quaternion quaternion = eulerToQuaternion(pose.theta, 0, 0);
    Map<String, dynamic> msg = {
      "header": {
        // "seq": 0,
        "stamp": {
          "secs": DateTime.now().second,
          "nsecs": DateTime.now().millisecond * 1000000
        },
        "frame_id": "map"
      },
      "pose": {
        "position": {"x": pose.x, "y": pose.y, "z": 0},
        "orientation": {
          "x": quaternion.x,
          "y": quaternion.y,
          "z": quaternion.z,
          "w": quaternion.w
        }
      }
    };

    // Assuming `channel` is a pre-configured MethodChannel connected to ROS
    try {
      await navGoalChannel_.publish(msg);
    } catch (e) {
      print("Failed to send navigation goal: $e");
    }
  }

  Future<void> sendEmergencyStop() async {
    await sendSpeed(0, 0, 0);
  }

  Future<void> sendCancelNav() async {
    await navGoalCancelChannel_.publish({});
  }

  void destroyConnection() async {
    await mapChannel_.unsubscribe();
    await ros.close();
  }

  void setVxRight(double vx) {
    if (vxLeft_ == 0) {
      cmdVel_.vx = vx;
    }
  }

  void setVx(double vx) {
    vxLeft_ = vx;
    cmdVel_.vx = vx;
  }

  void setVy(double vy) {
    cmdVel_.vy = vy;
  }

  void setVw(double vw) {
    cmdVel_.vw = vw;
  }

  void startMunalCtrl() {
    cmdVelTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      await sendSpeed(cmdVel_.vx, cmdVel_.vy, cmdVel_.vw);
    });
  }

  void stopMunalCtrl() {
    if (cmdVelTimer != null) {
      cmdVelTimer!.cancel();
      cmdVelTimer = null;
    }
    
    // Reset speed commands to ensure robot stops
    cmdVel_.vx = 0;
    cmdVel_.vy = 0;
    cmdVel_.vw = 0;
    
    // Send stop command once
    sendSpeed(0, 0, 0);
  }

  Future<void> sendSpeed(double vx, double vy, double vw) async {
    Map<String, dynamic> msg = {
      "linear": {
        "x": vx, // Linear velocity x component
        "y": vy, // Linear velocity y component
        "z": 0.0 // Linear velocity z component
      },
      "angular": {
        "x": 0.0, // Angular velocity x component
        "y": 0.0, // Angular velocity y component
        "z": vw // Angular velocity z component
      }
    };
    await speedCtrlChannel_.publish(msg);
  }

  Future<void> sendRelocPose(RobotPose pose) async {
    vm.Quaternion quation = eulerToQuaternion(pose.theta, 0, 0);
    Map<String, dynamic> msg = {
      "header": {
        // "seq": 0,
        "stamp": {
          "secs": DateTime.now().second,
          "nsecs": DateTime.now().millisecond * 1000000
        },
        "frame_id": "map"
      },
      "pose": {
        "pose": {
          "position": {"x": pose.x, "y": pose.y, "z": 0},
          "orientation": {
            "x": quation.x,
            "y": quation.y,
            "z": quation.z,
            "w": quation.w
          }
        },
        "covariance": [
          0.1,
          0,
          0,
          0,
          0,
          0,
          0,
          0.1,
          0,
          0,
          0,
          0,
          0,
          0,
          0.1,
          0,
          0,
          0,
          0,
          0,
          0,
          0.1,
          0,
          0,
          0,
          0,
          0,
          0,
          0.1,
          0,
          0,
          0,
          0,
          0,
          0,
          0.1
        ]
      }
    };
    try {
      await relocChannel_.publish(msg);
    } catch (e) {
      print("send reloc pose error:$e");
    }
  }

  Future<void> batteryCallback(Map<String, dynamic> message) async {
    double percentage = message['percentage'] * 100; // Assuming battery percentage is in 0-1 range
    battery_.value = percentage;
    // print("battery:$percentage");
  }

  Future<void> odomCallback(Map<String, dynamic> message) async {
    // Parse linear velocity (vx, vy)
    double vx = message['twist']['twist']['linear']['x'];
    double vy = message['twist']['twist']['linear']['y'];

    // Parse angular velocity (vw)
    double vw = message['twist']['twist']['angular']['z'];
    RobotSpeed speed = RobotSpeed(vx: vx, vy: vy, vw: vw);
    robotSpeed_.value = speed;
    // print("vx:$vx,vy:$vy,vw:$vw");
  }

  Future<void> robotFootprintCallback(Map<String, dynamic> message) async {
    try {
      PolygonStamped polygonStamped = PolygonStamped.fromJson(message);

      String framId = polygonStamped.header!.frameId!;
      RobotPose transPose = RobotPose(0, 0, 0);
      try {
        transPose = tf_.lookUpForTransform(globalSetting.mapFrameName, framId);
      } catch (e) {
        print("not find robot footprint transfrom form:map to:$framId");
        return;
      }
      
      List<vm.Vector2> newPoints = [];
      
      if (polygonStamped.polygon != null) {
        for (int i = 0; i < polygonStamped.polygon!.points.length; i++) {
          Point32 point = polygonStamped.polygon!.points[i];
          RobotPose pose = RobotPose(point.x, point.y, 0);
          RobotPose poseMap = absoluteSum(transPose, pose);
          vm.Vector2 poseScene = map_.value.xy2idx(vm.Vector2(poseMap.x, poseMap.y));
          newPoints.add(poseScene);
        }
      }
      robotFootprint.value = newPoints;
    } catch (e) {
      print("Error parsing robot footprint: $e");
    }
  }

  Future<void> localCostmapCallback(Map<String, dynamic> msg) async {
    DateTime currentTime = DateTime.now(); // Get current time

    if (_lastMapCallbackTime != null) {
      Duration difference = currentTime.difference(_lastMapCallbackTime!);
      if (difference.inSeconds < 5) {
        return;
      }
    }

    _lastMapCallbackTime = currentTime; // Update last callback time

    try {
      // Parse local costmap data
      int width = msg["info"]["width"];
      int height = msg["info"]["height"];
      double resolution = msg["info"]["resolution"];
      double originX = msg["info"]["origin"]["position"]["x"];
      double originY = msg["info"]["origin"]["position"]["y"];
      
      // Parse quaternion to get rotation angle
      Map<String, dynamic> orientation = msg["info"]["origin"]["orientation"];
      double qx = orientation["x"]?.toDouble() ?? 0.0;
      double qy = orientation["y"]?.toDouble() ?? 0.0;
      double qz = orientation["z"]?.toDouble() ?? 0.0;
      double qw = orientation["w"]?.toDouble() ?? 1.0;
      
      // Convert quaternion to Euler angles
      vm.Quaternion quaternion = vm.Quaternion(qx, qy, qz, qw);
      List<double> euler = quaternionToEuler(quaternion);
      double originTheta = euler[0]; // yaw angle
      
      // Create local costmap
      OccupancyMap costmap = OccupancyMap();
      costmap.mapConfig.resolution = resolution;
      costmap.mapConfig.width = width;
      costmap.mapConfig.height = height;
      costmap.mapConfig.originX = originX;
      costmap.mapConfig.originY = originY;
      
      List<int> dataList = List<int>.from(msg["data"]);
      costmap.data = List.generate(
        height,
        (i) => List.generate(width, (j) => 0),
      );
      
      for (int i = 0; i < dataList.length; i++) {
        int x = i ~/ width;
        int y = i % width;
        costmap.data[x][y] = dataList[i];
      }
      costmap.setFlip();
      
      // Coordinate system conversion: convert local costmap base coordinates to map coordinate system
      String frameId = msg["header"]["frame_id"];
      RobotPose originPose = RobotPose(0, 0, 0);
      
      try {
        // Get transform from local coordinate system to map coordinate system
        RobotPose transPose = tf_.lookUpForTransform(globalSetting.mapFrameName, frameId);
        
        // Calculate local costmap origin position in map coordinate system
        RobotPose localOrigin = RobotPose(originX, originY, originTheta);
        RobotPose mapOrigin = absoluteSum(transPose, localOrigin);
        
        // Adjust Y coordinate (considering map flip)
        mapOrigin.y += costmap.heightMap();
        originPose = mapOrigin;

        
      } catch (e) {
        print("getTransform localCostMapCallback error: $e");
        return;
      }
      
      // Overlay local costmap using global map size
      OccupancyMap sizedCostMap = map_.value.copy();
      sizedCostMap.setZero();
      
      // Use xy2idx method to convert world coordinates of costmap top-left corner to grid coordinates
      vm.Vector2 occPoint = map_.value.xy2idx(vm.Vector2(originPose.x, originPose.y));
      double mapOX = occPoint.x;
      double mapOY = occPoint.y;
      
      // Clear target area
      for (int x = 0; x < sizedCostMap.mapConfig.height; x++) {
        for (int y = 0; y < sizedCostMap.mapConfig.width; y++) {
          if (x > mapOX && y > mapOY && 
              y < mapOY + costmap.mapConfig.height &&
              x < mapOX + costmap.mapConfig.width) {
            // Within local costmap range, use local costmap values
            int localX = x - mapOX.toInt();
            int localY = y - mapOY.toInt();
            if (localX >= 0 && localX < costmap.mapConfig.height &&
                localY >= 0 && localY < costmap.mapConfig.width) {
              sizedCostMap.data[y][x] = costmap.data[localY][localX];
            }
          }
          // Not in range, keep original values
        }
      }
      
      // Update local costmap
      localCostmap.value = sizedCostMap;
    } catch (e) {
      print("Error processing local costmap: $e");
    }
  }

  Future<void> tfCallback(Map<String, dynamic> msg) async {
    // print("${json.encode(msg)}");
    tf_.updateTF(TF.fromJson(msg));
  }

  Future<void> tfStaticCallback(Map<String, dynamic> msg) async {
    // print("${json.encode(msg)}");
    tf_.updateTF(TF.fromJson(msg));
  }

  Future<void> localPathCallback(Map<String, dynamic> msg) async {
    List<vm.Vector2> newPath = [];
    // print("${json.encode(msg)}");
    RobotPath path = RobotPath.fromJson(msg);
    String framId = path.header!.frameId!;
    RobotPose transPose = RobotPose(0, 0, 0);
    try {
      transPose = tf_.lookUpForTransform(globalSetting.mapFrameName, framId);
    } catch (e) {
      print("not find local path transfrom form:map to:$framId");
      return;
    }

    for (var pose in path.poses!) {
      RosTransform tran = RosTransform(
          translation: pose.pose!.position!, rotation: pose.pose!.orientation!);
      var poseFrame = tran.getRobotPose();
      var poseMap = absoluteSum(transPose, poseFrame);
      vm.Vector2 poseScene = map_.value.xy2idx(vm.Vector2(poseMap.x, poseMap.y));
      newPath.add(vm.Vector2(poseScene.x, poseScene.y));
    }
    
    // Use new list assignment to trigger listeners
    localPath.value = newPath;
  }

  Future<void> globalPathCallback(Map<String, dynamic> msg) async {
    List<vm.Vector2> newPath = [];
    RobotPath path = RobotPath.fromJson(msg);
    String framId = path.header!.frameId!;
    RobotPose transPose = RobotPose(0, 0, 0);
    try {
      transPose = tf_.lookUpForTransform("map", framId);
    } catch (e) {
      print("not find global path transfrom form:map to:$framId");
      return;
    }

    for (var pose in path.poses!) {
      RosTransform tran = RosTransform(
          translation: pose.pose!.position!, rotation: pose.pose!.orientation!);
      var poseFrame = tran.getRobotPose();
      var poseMap = absoluteSum(transPose, poseFrame);
      vm.Vector2 poseScene = map_.value.xy2idx(vm.Vector2(poseMap.x, poseMap.y));
      newPath.add(vm.Vector2(poseScene.x, poseScene.y));
    }
    
    // Use new list assignment to trigger listeners
    globalPath.value = newPath;
  }

  Future<void> tracePathCallback(Map<String, dynamic> msg) async {
    List<vm.Vector2> newPath = [];
    RobotPath path = RobotPath.fromJson(msg);
    String framId = path.header!.frameId!;
    RobotPose transPose = RobotPose(0, 0, 0);
    try {
      transPose = tf_.lookUpForTransform("map", framId);
    } catch (e) {
      print("not find trace path transfrom form:map to:$framId");
      return;
    }

    for (var pose in path.poses!) {
      RosTransform tran = RosTransform(
          translation: pose.pose!.position!, rotation: pose.pose!.orientation!);
      var poseFrame = tran.getRobotPose();
      var poseMap = absoluteSum(transPose, poseFrame);
      vm.Vector2 poseScene = map_.value.xy2idx(vm.Vector2(poseMap.x, poseMap.y));
      newPath.add(vm.Vector2(poseScene.x, poseScene.y));
    }
    
    // Use new list assignment to trigger listeners
    tracePath.value = newPath;
  }


  Future<void> laserCallback(Map<String, dynamic> msg) async {
    // print("${json.encode(msg)}");
    LaserScan laser = LaserScan.fromJson(msg);
    RobotPose laserPoseBase = RobotPose(0, 0, 0);
    try {
      laserPoseBase = tf_.lookUpForTransform(
          globalSetting.baseLinkFrameName, laser.header!.frameId!);
    } catch (e) {
      print("not find transform from:map to ${laser.header!.frameId!}");
      return;
    }
    // print("find laser size:${laser.ranges!.length}");
    double angleMin = laser.angleMin!.toDouble();
    double angleIncrement = laser.angleIncrement!;
    List<vm.Vector2> newLaserPoints = [];
    for (int i = 0; i < laser.ranges!.length; i++) {
      double angle = angleMin + i * angleIncrement;
      // print("${laser.ranges![i]}");
      if (laser.ranges![i].isInfinite || laser.ranges![i].isNaN) continue;
      double dist = laser.ranges![i];
      // Handle null data
      if (dist == -1) continue;
      RobotPose poseLaser = RobotPose(dist * cos(angle), dist * sin(angle), 0);

      // Convert to map coordinate system
      RobotPose poseBaseLink = absoluteSum(laserPoseBase, poseLaser);

      newLaserPoints.add(vm.Vector2(poseBaseLink.x, poseBaseLink.y));
    }
    
    // Use new list assignment to trigger listeners
    laserBasePoint_.value = newLaserPoints;
    laserPointData.value = LaserData(
        robotPose: robotPoseMap.value, laserPoseBaseLink: newLaserPoints);
  }

  DateTime? _lastMapCallbackTime;

  Future<void> mapCallback(Map<String, dynamic> msg) async {
    DateTime currentTime = DateTime.now(); // Get current time

    if (_lastMapCallbackTime != null) {
      Duration difference = currentTime.difference(_lastMapCallbackTime!);
      if (difference.inSeconds < 5) {
        return;
      }
    }

    _lastMapCallbackTime = currentTime; // Update last callback time

    OccupancyMap map = OccupancyMap();
    map.mapConfig.resolution = msg["info"]["resolution"];
    map.mapConfig.width = msg["info"]["width"];
    map.mapConfig.height = msg["info"]["height"];
    map.mapConfig.originX = msg["info"]["origin"]["position"]["x"];
    map.mapConfig.originY = msg["info"]["origin"]["position"]["y"];
    List<int> dataList = List<int>.from(msg["data"]);
    map.data = List.generate(
      map.mapConfig.height, // Outer list length
      (i) => List.generate(
        map.mapConfig.width, // Inner list length
        (j) => 0, // Initial value
      ),
    );
    for (int i = 0; i < dataList.length; i++) {
      int x = i ~/ map.mapConfig.width;
      int y = i % map.mapConfig.width;
      map.data[x][y] = dataList[i];
    }
    map.setFlip();
    map_.value = map;
  }

  String msgReceived = '';
  Future<void> subscribeHandler(Map<String, dynamic> msg) async {
    msgReceived = json.encode(msg);
    print("recv ${msgReceived}");
  }

  Future<void> topologyMapCallback(Map<String, dynamic> msg) async {
    // Delay 1 second to avoid points being sent before map is loaded (sent only once)
    await Future.delayed(Duration(seconds: 1));
    
    print("Received topology map data: $msg");
    
    final map = TopologyMap.fromJson(msg);
    print("Parsed topology map - point count: ${map.points.length}, route count: ${map.routes.length}");

    // Create new points list
    final updatedPoints = map.points.map((point) {
      // Create new NavPoint object
      return NavPoint(
        x: point.x,
        y: point.y,
        theta: point.theta,
        name: point.name,
        type: point.type,
      );
    }).toList();

    // Create new TopologyMap object containing converted points and original route information
    final updatedMap = TopologyMap(
      points: updatedPoints, 
      routes: map.routes,
      mapName: map.mapName,
      mapProperty: map.mapProperty,
    );

    print("Updated topology map - point count: ${updatedMap.points.length}, route count: ${updatedMap.routes.length}");
    
    // Update ValueNotifier
    topologyMap_.value = updatedMap;
  }

  Future<void> updateTopologyMap(TopologyMap updatedMap) async {
    // Convert to JSON and publish via ROS
    try {
      final jsonData = updatedMap.toJson();
      await topologyMapUpdateChannel_.publish(jsonData);
      print("Topology map published to ROS: ${updatedMap.points.length} points, ${updatedMap.routes.length} routes");
    } catch (e) {
      print("Failed to publish topology map: $e");
    }
  }

  Future<void> navStatusCallback(Map<String, dynamic> msg) async {
    GoalStatusArray goalStatusArray = GoalStatusArray.fromJson(msg);
    navStatus_.value = goalStatusArray.statusList.last.status;
  }

  Future<void> pointCloud2Callback(Map<String, dynamic> msg) async {
    try {
      PointCloud2 pointCloud = PointCloud2.fromJson(msg);
      
      // Get point cloud data
      List<Point3D> points = pointCloud.getPoints();
      
      // Convert coordinate system: from point cloud coordinate system to map coordinate system
      String frameId = pointCloud.header!.frameId!;
      RobotPose transPose = RobotPose(0, 0, 0);
      
      try {
        transPose = tf_.lookUpForTransform(globalSetting.mapFrameName, frameId);
      } catch (e) {
        print("not find pointcloud transform from:map to:$frameId");
        return;
      }
      
      // Convert all points to map coordinate system
      List<Point3D> transformedPoints = [];
      for (Point3D point in points) {
        RobotPose pointPose = RobotPose(point.x, point.y, 0);
        RobotPose mapPose = absoluteSum(transPose, pointPose);
        transformedPoints.add(Point3D(mapPose.x, mapPose.y, point.z));
      }
      
      
      // Update point cloud data
      pointCloud2Data.value = transformedPoints;
      
    } catch (e) {
      print("Error processing PointCloud2 data: $e");
    }
  }

  Future<void> globalCostmapCallback(Map<String, dynamic> msg) async {
    DateTime currentTime = DateTime.now(); // Get current time

    if (_lastMapCallbackTime != null) {
      Duration difference = currentTime.difference(_lastMapCallbackTime!);
      if (difference.inSeconds < 5) {
        return;
      }
    }

    _lastMapCallbackTime = currentTime; // Update last callback time

    try {
      // Parse global costmap data
      int width = msg["info"]["width"];
      int height = msg["info"]["height"];
      double resolution = msg["info"]["resolution"];
      double originX = msg["info"]["origin"]["position"]["x"];
      double originY = msg["info"]["origin"]["position"]["y"];
      
      // Create global costmap
      OccupancyMap costmap = OccupancyMap();
      costmap.mapConfig.resolution = resolution;
      costmap.mapConfig.width = width;
      costmap.mapConfig.height = height;
      costmap.mapConfig.originX = originX;
      costmap.mapConfig.originY = originY;
      
      List<int> dataList = List<int>.from(msg["data"]);
      costmap.data = List.generate(
        height,
        (i) => List.generate(width, (j) => 0),
      );
      
      for (int i = 0; i < dataList.length; i++) {
        int x = i ~/ width;
        int y = i % width;
        costmap.data[x][y] = dataList[i];
      }
      costmap.setFlip();
      
      // Directly update global costmap, no resize needed
      globalCostmap.value = costmap;
    } catch (e) {
      print("Error processing global costmap: $e");
    }
  }

  Future<void> diagnosticCallback(Map<String, dynamic> msg) async {
    try {
      DiagnosticArray diagnosticArray = DiagnosticArray.fromJson(msg);
      
      // Update diagnostic data (maintain backward compatibility)
      diagnosticData.value = diagnosticArray;
      
      // Use DiagnosticManager to manage diagnostic states
      diagnosticManager.updateDiagnosticStates(diagnosticArray);
      
    } catch (e) {
      print("Error processing diagnostic data: $e");
    }
  }
}
