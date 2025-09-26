import 'dart:math';
import 'dart:ui';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:ros_flutter_gui_app/basic/RobotPose.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

enum PoseType{
  robot,
  waypoint,
}

class PoseComponent extends PositionComponent with HasGameRef {
  late double PoseComponentSize;
  late Color color;
  int count;
  late Timer animationTimer;
  double animationValue = 0.0;

  // Add edit mode control
  bool isEditMode = false;
  
  // Add direction angle (radians)
  double direction = 0.0;
  
  // Add pose change callback
  Function(RobotPose)? onPoseChanged;

  // Store navigation point information
  NavPoint? navPoint;
  
  // Store occupancy map information
  OccupancyMap? occMap;
  
  // Add RosChannel reference
  RosChannel? rosChannel;
  PoseType poseType;
  
  // Handle gestures within component, no external state needed
  PoseComponent({
    required this.PoseComponentSize,
    this.color = const Color(0xFF0080ff),
    this.count = 2,
    this.isEditMode = false,
    this.direction = 0.0,
    this.onPoseChanged,
    this.navPoint,
    this.occMap,
    this.rosChannel,
    this.poseType = PoseType.waypoint,
  });
  
  @override
  Future<void> onLoad() async {
    size = Vector2.all(PoseComponentSize);
    anchor = Anchor.center;
    animationTimer = Timer(
      2.0,
      onTick: () {
        // Reset animation values
        animationValue = 0.0;
      },
      repeat: true,
    );
    
    // Add renderer
    add(PoseComponentRenderer(
      size: PoseComponentSize,
      color: color,
      count: count,
      animationValue: animationValue,
      poseType: poseType,
    ));
    
    // Control direction ring based on edit mode and selection state
    _updateDirectionControlVisibility();
  }

  @override
  void update(double dt) {
    animationTimer.update(dt);
    // Use progress directly, ensure animation value is between 0 and 1
    animationValue = animationTimer.progress;
    
    // Synchronously update renderer animation value
    final renderer = children.whereType<PoseComponentRenderer>().firstOrNull;
    if (renderer != null) {
      renderer.updateAnimationValue(animationValue);
    }

    
    super.update(dt);
  }
  
  int frameCount = 0;

  @override
  void onRemove() {
    super.onRemove();
  }

  void updatePose(RobotPose pose) {
    // Prioritize passed occMap, if none then get from RosChannel
    OccupancyMap? currentMap = occMap;
    if (currentMap == null && rosChannel != null) {
      currentMap = rosChannel!.map_.value;
    }
    
    if (currentMap != null && currentMap.mapConfig.resolution > 0) {
      var occPose = currentMap.xy2idx(vm.Vector2(pose.x, pose.y));
      position = Vector2(occPose.x, occPose.y);
    } else {
      // If no map data, use original coordinates directly
      position = Vector2(pose.x, pose.y);
    }
    direction = -pose.theta;
  }

  // Update direction angle
  void updatedirection(double newAngle) {
    direction = newAngle;
    
    // Synchronously update DirectionControl angle
    final directionControl = children.whereType<DirectionControl>().firstOrNull;
    if (directionControl != null) {
      directionControl.updateAngle(direction);
    }
  
    // Trigger pose change callback
    _triggerPoseChangedCallback();
  }
  
  // Set angle silently to avoid callback recursion
  void _setAngleSilent(double newAngle) {
    direction = newAngle;
    final renderer = children.whereType<DirectionControlRenderer>().firstOrNull;
    if (renderer != null) {
      renderer.updateAngle(direction);
    }
  }
  
  // Public interface: directly set angle (silent)
  void setAngleDirect(double newAngle) {
    _setAngleSilent(newAngle);
  }
  
  NavPoint? getPointInfo() {
    return navPoint;
  }

  
  // Set edit mode (controlled by map editing tool)
  void setEditMode(bool edit) {
    if (isEditMode == edit) return;
    isEditMode = edit;
    _updateDirectionControlVisibility();
  }
  
  void _updateDirectionControlVisibility() {
    final exists = children.whereType<DirectionControl>().firstOrNull;
    final shouldShow = isEditMode;
    if (shouldShow) {
      if (exists == null) {
        final directionControl = DirectionControl(
          controlSize: PoseComponentSize,
          onDirectionChanged: updatedirection,
          initAngle: direction,
        );
        add(directionControl);
      }
    } else {
      if (exists != null) {
        // Reset gesture state before removal
        exists._resetDragState();
        exists.removeFromParent();
      }
    }
  }
  
  // Set navigation point information
  void setNavPoint(NavPoint point) {
    navPoint = point;
  }
  
  // Set occupancy map information
  void setOccMap(OccupancyMap map) {
    occMap = map;
  }
  
  // Get occupancy map information
  OccupancyMap? getOccMap() {
    // Prioritize returning passed occMap, get from RosChannel if none
    if (occMap != null) {
      return occMap;
    }
    if (rosChannel != null) {
      return rosChannel!.map_.value;
    }
    return null;
  }
  
  // Trigger pose change callback
  void _triggerPoseChangedCallback() {
    if (onPoseChanged != null) {
      // Create RobotPose object containing current position and direction
      var occMap = getOccMap();
      double mapPosex=0;
      double mapPosey=0;
      if(occMap != null){
        var p = occMap.idx2xy(vm.Vector2(position.x, position.y));
        mapPosex=p.x;
        mapPosey=p.y;
      }
      final robotPose = RobotPose(
        mapPosex,  // x coordinate
        mapPosey,  // y coordinate
        -direction,   // direction angle
      );
      onPoseChanged!(robotPose);
    }
  }
  
  // Set RosChannel reference
  void setRosChannel(RosChannel channel) {
    rosChannel = channel;
  }
  
}

// Direction control component
class DirectionControl extends PositionComponent with DragCallbacks {
  final double controlSize;
  final Function(double) onDirectionChanged;
  final double initAngle;
  
  double _currentAngle = 0.0;
  bool _isUpdating = false; // Prevent duplicate calls
  Vector2? _lastMousePosition;
  bool _isRotating = false;
  bool _isPositionDragging = false;
  Vector2? _positionDragStart;
  
  // Gesture area detection is dynamically calculated in methods

  DirectionControl({
    required this.controlSize,
    required this.onDirectionChanged,
    required this.initAngle,
  });

  @override
  Future<void> onLoad() async {
    size = Vector2.all(controlSize);
    _currentAngle = initAngle;

    
    add(DirectionControlRenderer(
      size: controlSize,
      angle: _currentAngle,
    ));
  }
  
  @override
  void onRemove() {
    super.onRemove();
    // Ensure all gesture states are reset during removal
    _resetDragState();
  }
 
  
  @override
  bool onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    
    // Check if parent component is in edit mode
    if (parent is PoseComponent) {
      final poseComponent = parent as PoseComponent;
      if (!poseComponent.isEditMode) {
        return false; // Don't intercept gestures when not in edit mode
      }
    }
    
    _lastMousePosition = event.localPosition;
    final center = size / 2;
    final distance = (event.localPosition - center).length;
    final ringRadius = controlSize / 2;
    if (distance <= ringRadius / 2) {
      // Center area: position dragging
      _isRotating = false;
      _isPositionDragging = true;
      _positionDragStart = event.localPosition;
      return true;
    } else if (distance <= ringRadius + 2) {
      // Outer ring: rotation
      _isRotating = true;
      _isPositionDragging = false;
      return true;
    }
    return false;
  }

  @override
  bool onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    
    // Check if parent component is in edit mode
    if (parent is PoseComponent) {
      final poseComponent = parent as PoseComponent;
      if (!poseComponent.isEditMode) {
        return false; // Don't intercept gestures when not in edit mode
      }
    }
    
    if (_isRotating) {
      if (_lastMousePosition != null) {
        _lastMousePosition = _lastMousePosition! + event.localDelta;
        final center = size / 2;
        final dx = _lastMousePosition!.x - center.x;
        final dy = _lastMousePosition!.y - center.y;
        final newAngle = atan2(dy, dx);
        _currentAngle = newAngle;
        onDirectionChanged(_currentAngle);
        final renderer = children.whereType<DirectionControlRenderer>().firstOrNull;
        if (renderer != null) {
          renderer.updateAngle(_currentAngle);
        }
      }
      return true;
    } else if (_isPositionDragging) {
      if (parent is PoseComponent && _positionDragStart != null) {
        final poseComponent = parent as PoseComponent;
        final delta = event.localDelta;
        poseComponent.position = poseComponent.position + delta;
        // Trigger pose change callback
        poseComponent._triggerPoseChangedCallback();
      }
      return true;
    }
    return false;
  }

  @override
  bool onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    
    // Check if parent component is in edit mode
    if (parent is PoseComponent) {
      final poseComponent = parent as PoseComponent;
      if (!poseComponent.isEditMode) {
        return false; // Don't intercept gestures when not in edit mode
      }
    }
    
    _resetDragState();
    return true;
  }

  // Reset drag state
  void _resetDragState() {
    _lastMousePosition = null;
    _isRotating = false;
    _isPositionDragging = false;
    _positionDragStart = null;
  }
  
  // Update angle (called by external gesture handling)
  void updateAngle(double newAngle) {
    
    if (_isUpdating) {
      return; // Prevent duplicate calls
    }
    
    _isUpdating = true;
    _currentAngle = newAngle;
    
    // Notify parent component to update direction angle
    onDirectionChanged(_currentAngle);
    
    // Update renderer
    final renderer = children.whereType<DirectionControlRenderer>().firstOrNull;
    if (renderer != null) {
      renderer.updateAngle(_currentAngle);
    }
    
    _isUpdating = false;
  }
}

// Direction control renderer
class DirectionControlRenderer extends Component {
  final double size;
  double angle;
  
  DirectionControlRenderer({
    required this.size,
    required this.angle,
  });
  
  void updateAngle(double newAngle) {
    angle = newAngle;
  }
  
  @override
  void render(Canvas canvas) {
    // Calculate drawing start point to center the ring around the point
    final center = Offset(size / 2, size / 2);
    final radius = size / 2; // Adjust radius to ensure ring wraps around the point
    canvas.save();
    // canvas.translate(-size / 2, -size / 2);
    // Draw main circle
    final circlePaint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    
    canvas.drawCircle(center, radius, circlePaint);
    
    // Draw direction indicator point
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final pointOffset = Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
    
    canvas.drawCircle(pointOffset, 0.6, pointPaint);
    canvas.restore();
  }
}

// Path point renderer
class PoseComponentRenderer extends Component with HasGameRef {
  final double size;
  final Color color;
  final int count;
  double animationValue; // Remove final to allow updates
  final PoseType poseType;

  PoseComponentRenderer({
    required this.size,
    required this.color,
    required this.count,
    required this.animationValue,
    required this.poseType,
  });
  
  // Add method to update animation value
  void updateAnimationValue(double value) {
    animationValue = value;
  }

  @override
  void render(Canvas canvas) {
    // Add safety check
    if (!isMounted) {
      return;
    }
    
    try {
      canvas.save();
      
      // Get parent component's direction angle
      final parentComponent = parent;
      if (parentComponent is PoseComponent) {
        final double rotationAngle = parentComponent.direction;
        
        // Rotate and draw with component center as origin
        canvas.save();
        canvas.translate(size / 2, size / 2);
        canvas.rotate(rotationAngle);
        
        // Draw robot coordinates
        double radius = min(size / 2, size / 2);

        // Draw different ripple styles based on point type
        if (poseType == PoseType.robot) {
          // Robot type: draw circular ripples
          for (int i = count; i >= 0; i--) {
            final double opacity = (1.0 - ((i + animationValue) / (count + 1)));
            final paint = Paint()
              ..color = color.withOpacity(opacity)
              ..style = PaintingStyle.fill;

            double _radius = radius * ((i + animationValue) / (count + 1));
            canvas.drawCircle(Offset.zero, _radius, paint);
          }
        } else {
          // Navigation point type: draw diamond ripples
          for (int i = count; i >= 0; i--) {
            final double opacity = (1.0 - ((i + animationValue) / (count + 1)));
            final paint = Paint()
              ..color = color.withOpacity(opacity)
              ..style = PaintingStyle.fill;

            double _radius = radius * ((i + animationValue) / (count + 1));

            // Calculate diamond's four vertices with center at (0, 0)
            final path = Path()
              ..moveTo(_radius, 0) // Right vertex
              ..lineTo(0, _radius) // Bottom vertex
              ..lineTo(-_radius, 0) // Left vertex
              ..lineTo(0, -_radius) // Top vertex
              ..close(); // Close path

            // Draw path
            canvas.drawPath(path, paint);
          }
        }

        // Draw different center styles based on point type
        if (poseType == PoseType.robot) {
          // Robot type: draw circular center with slight pulse animation
          final double centerPulse = 1.0 + 0.1 * sin(animationValue * 4 * pi);
          final centerPaint = Paint()
            ..color = color.withOpacity(0.8 + 0.2 * sin(animationValue * 2 * pi))
            ..style = PaintingStyle.fill;
          
          final centerRadius = radius / 3 * centerPulse;
          canvas.drawCircle(Offset.zero, centerRadius, centerPaint);
        } else {
          // Navigation point type: draw diamond center with slight pulse animation
          final double centerPulse = 1.0 + 0.1 * sin(animationValue * 4 * pi);
          final centerPaint = Paint()
            ..color = color.withOpacity(0.8 + 0.2 * sin(animationValue * 2 * pi))
            ..style = PaintingStyle.fill;
          
          final centerPath = Path()
            ..moveTo(radius / 3 * centerPulse, 0) // Right vertex
            ..lineTo(0, radius / 3 * centerPulse) // Bottom vertex
            ..lineTo(-radius / 3 * centerPulse, 0) // Left vertex
            ..lineTo(0, -radius / 3 * centerPulse) // Top vertex
            ..close(); // Close path

          // Draw path
          canvas.drawPath(centerPath, centerPaint);
        }

        // Draw direction indicator with center at (0, 0)
        Paint dirPainter = Paint()
          ..style = PaintingStyle.fill
          ..color = color.withOpacity(0.6);
        
        Rect rect = Rect.fromCircle(
            center: Offset.zero, radius: radius);
        canvas.drawArc(rect, -deg2rad(15), deg2rad(30), true, dirPainter);
        
        canvas.restore(); // Restore rotation transform
      }
      
      canvas.restore();
    } catch (e) {
      print('Error rendering PoseComponent: $e');
    }
  }
}

