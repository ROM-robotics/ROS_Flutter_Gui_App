import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:ros_flutter_gui_app/basic/occupancy_map.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';

import 'package:flame/components.dart';


class MapComponent extends PositionComponent {
  OccupancyMap? _currentMap;
  ui.Image? _mapImage;
  bool _isProcessing = false;
  RosChannel? _rosChannel;
  bool _isDarkMode = false;
  
  // Public access to current map data
  OccupancyMap? get currentMap => _currentMap;
  
  // Constructor receives RosChannel
  MapComponent({RosChannel? rosChannel}) {
    _rosChannel = rosChannel;
  }
  
  @override
  Future<void> onLoad() async {
    super.onLoad();
    
    // If RosChannel exists, set up listener immediately
    if (_rosChannel != null) {
      _setupMapListener();
    }
  }
  
  void _setupMapListener() {
    if (_rosChannel != null) {
      // Listen to map data changes
      _rosChannel!.map_.addListener(_onMapDataChanged);
      
      // Update current map data immediately
      _onMapDataChanged();
    }
  }
  
  void _onMapDataChanged() {
    if (_rosChannel != null) {
      final newMap = _rosChannel!.map_.value;
      updateMapData(newMap);
    }
  }
  
  void updateMapData(OccupancyMap map) async {
    if (_isProcessing || _currentMap == map) return;
    
    _currentMap = map;
    await _processMapToImage(map);
  }
  
  void updateThemeMode(bool isDarkMode) {
    _isDarkMode = isDarkMode;
    // Re-render map to apply new theme
    if (_currentMap != null) {
      _processMapToImage(_currentMap!);
    }
  }
  
  Future<void> _processMapToImage(OccupancyMap map) async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    try {
      if (map.data.isEmpty || map.mapConfig.width == 0 || map.mapConfig.height == 0) {
        _mapImage?.dispose();
        _mapImage = null;
        return;
      }

      final int width = map.mapConfig.width;
      final int height = map.mapConfig.height;

      // Create pixel data buffer (RGBA format)
      final List<int> pixelData = List.filled(width * height * 4, 0);
      
      // Process map data
      for (int i = 0; i < map.Cols(); i++) {
        for (int j = 0; j < map.Rows(); j++) {
          int mapValue = map.data[j][i];
          final int pixelIndex = (j * width + i) * 4;
          
          if (mapValue > 0) {
            // Occupied area
            int alpha = (mapValue * 2.55).clamp(0, 255).toInt();
            if (_isDarkMode) {
              // Dark theme - light gray obstacles
              pixelData[pixelIndex] = 200;     // R
              pixelData[pixelIndex + 1] = 200; // G
              pixelData[pixelIndex + 2] = 200; // B
              pixelData[pixelIndex + 3] = alpha; // A
            } else {
              // Light theme - dark gray obstacles
              pixelData[pixelIndex] = 60;      // R
              pixelData[pixelIndex + 1] = 60;  // G
              pixelData[pixelIndex + 2] = 60;  // B
              pixelData[pixelIndex + 3] = alpha; // A
            }
          } else if (mapValue == 0) {
            // Free area
            if (_isDarkMode) {
              // Dark theme - dark background
              pixelData[pixelIndex] = 30;      // R
              pixelData[pixelIndex + 1] = 30;  // G
              pixelData[pixelIndex + 2] = 30;  // B
              pixelData[pixelIndex + 3] = 255; // A
            } else {
              // Light theme - white background
              pixelData[pixelIndex] = 255;     // R
              pixelData[pixelIndex + 1] = 255; // G
              pixelData[pixelIndex + 2] = 255; // B
              pixelData[pixelIndex + 3] = 255; // A
            }
          } else {
            // Unknown area
            if (_isDarkMode) {
              // Dark theme - medium gray
              pixelData[pixelIndex] = 80;      // R
              pixelData[pixelIndex + 1] = 80;  // G
              pixelData[pixelIndex + 2] = 80;  // B
              pixelData[pixelIndex + 3] = 128; // A
            } else {
              // Light theme - light gray
              pixelData[pixelIndex] = 200;     // R
              pixelData[pixelIndex + 1] = 200; // G
              pixelData[pixelIndex + 2] = 200; // B
              pixelData[pixelIndex + 3] = 128; // A
            }
          }
        }
      }
      
      // Create image data
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        Uint8List.fromList(pixelData),
      );
      
      // Create image descriptor
      final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      
      // Decode image
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;
      
      // Release resources
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      
      // Update image
      _mapImage?.dispose();
      _mapImage = image;
      
    } catch (e) {
      print('Error processing map in Flame: $e');
    } finally {
      _isProcessing = false;
    }
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    if (_mapImage != null && _currentMap != null) {
      // Draw map image
      canvas.drawImage(_mapImage!, Offset.zero, Paint());
    }
  }
  
  @override
  void onRemove() {
    // Remove listener
    if (_rosChannel != null) {
      _rosChannel!.map_.removeListener(_onMapDataChanged);
    }
    
    // Release image resources
    _mapImage?.dispose();
    super.onRemove();
  }
}
