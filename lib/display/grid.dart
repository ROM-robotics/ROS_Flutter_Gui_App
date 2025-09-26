import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:flame/components.dart';
class GridComponent extends RectangleComponent with HasGameRef {
  final RosChannel? rosChannel;
  bool _isDarkMode = true;
  
  GridComponent({required Vector2 size, this.rosChannel}) : super(
    size: size,
    paint: Paint()..color = const Color(0xFF2C2C2C), // Dark gray background
  );
  
  void updateThemeMode(bool isDarkMode) {
    _isDarkMode = isDarkMode;
    // Update background color
    if (_isDarkMode) {
      paint = Paint()..color = const Color(0xFF2C2C2C); // Dark gray background
    } else {
      paint = Paint()..color = Colors.white; // White background
    }
  }
  
  @override
  void render(Canvas canvas) {

    // Draw grid
    _renderGrid(canvas);
  }
  
  void _renderGrid(Canvas canvas) {
    // Get map resolution, calculate pixels per 1 meter
    double gridStepPixels = 100.0; // Default value
    
    if (rosChannel != null && rosChannel!.map_.value.mapConfig.resolution > 0) {
      // 1 meter / resolution(meters/pixel) = pixel count
      gridStepPixels = 1.0 / rosChannel!.map_.value.mapConfig.resolution;
    }

    
    // Grid line paint
    final paint = Paint()
      ..color = _isDarkMode ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    // Calculate grid range to draw (based on canvas size, ignoring camera)
    final canvasSize = size;
    
    canvas.save();
    // Draw vertical lines (one per meter)
    for (double x = 0; x <= canvasSize.x; x += gridStepPixels) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, canvasSize.y),
        paint,
      );
    }
    
    // Draw horizontal lines (one per meter)
    for (double y = 0; y <= canvasSize.y; y += gridStepPixels) {
      canvas.drawLine(
        Offset(0, y),
        Offset(canvasSize.x, y),
        paint,
      );
    }
    canvas.restore();
  }
  
  @override
  bool get debugMode => false;
}