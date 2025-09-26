import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:provider/provider.dart';
import 'package:ros_flutter_gui_app/provider/global_state.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/provider/them_provider.dart';
import 'package:ros_flutter_gui_app/page/map_edit_flame.dart';
import 'package:ros_flutter_gui_app/provider/nav_point_manager.dart';
import 'package:ros_flutter_gui_app/basic/nav_point.dart';
import 'package:toastification/toastification.dart';
import 'package:ros_flutter_gui_app/basic/topology_map.dart';

enum EditToolType {
  addNavPoint,
  drawObstacle,
  eraseObstacle,
}

class MapEditPage extends StatefulWidget {
  final VoidCallback? onExit;
  
  const MapEditPage({super.key, this.onExit});

  @override
  State<MapEditPage> createState() => _MapEditPageState();
}

class _MapEditPageState extends State<MapEditPage> {
  late MapEditFlame game;
  late GlobalState globalState;
  late RosChannel rosChannel;

  // Currently selected edit tool
  EditToolType? selectedTool;
  
  // Navigation point list
  List<NavPoint> navPoints = [];
  
  // Currently selected waypoint information
  NavPoint? selectedWayPointInfo;



  @override
  void initState() {
    super.initState();
    globalState = Provider.of<GlobalState>(context, listen: false);
    rosChannel = Provider.of<RosChannel>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    // Set map editing mode
    globalState.mode.value = Mode.mapEdit;
 
    // Create dedicated map editing Flame component, pass in callback functions
    game = MapEditFlame(
      rosChannel: rosChannel,
      themeProvider: themeProvider,
      onAddNavPoint: (x, y) async {
        final wayPointInfo = await _addNavPoint(x, y);
        return wayPointInfo;
      },
      onWayPointSelectionChanged: _onWayPointSelectionChanged,
    );
    // Real-time callback for drag/rotation, refresh right panel information
    game.currentSelectPointUpdate = () {
      setState(() {
        final info = game.getSelectedWayPointInfo();
        selectedWayPointInfo = info;
      });
    };
    
    // Load navigation points
    _loadNavPoints();
  }
  
  @override
  void dispose() {
    // Reset to normal mode when exiting map editing mode
    globalState.mode.value = Mode.normal;
    super.dispose();
  }

  // Navigation point selection state change callback
  void _onWayPointSelectionChanged() {
    setState(() {
      final info = game.getSelectedWayPointInfo();
      selectedWayPointInfo = info;
    });
  }
  
  // Load navigation points
  Future<void> _loadNavPoints() async {
    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
    navPoints = await navPointManager.loadNavPoints();
    for(var navPoint in navPoints){
      game.addWayPoint(navPoint);
    }
    setState(() {
    });
  }
  
  // Add navigation point
  Future<NavPoint?> _addNavPoint(double x, double y) async {
    final name = await _showAddNavPointDialog(x, y);
    if (name != null && name.isNotEmpty) {
      // User entered name and clicked OK, create navigation point
      final navPointManager = Provider.of<NavPointManager>(context, listen: false);
      final navPoint = await navPointManager.addNavPoint(x, y, 0.0, name);
      return navPoint;
    } else {
      // User clicked cancel or didn't enter a name
      return null;
    }
  }
  
  // Show add navigation point dialog
  Future<String?> _showAddNavPointDialog(double x, double y) async {
    final TextEditingController nameController = TextEditingController();
    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
    int id = await navPointManager.getNextId();
    nameController.text = 'POINT_${id.toString()}';
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Navigation Point'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Position: (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})'),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Navigation Point Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(nameController.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Stack(
        children: [
          // Game canvas
          Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final position = Vector2(pointerSignal.position.dx, pointerSignal.position.dy);
                game.onScroll(pointerSignal.scrollDelta.dy, position);
              }
            },
            child: GestureDetector(
              onTapDown: (details) async {
                // Use local coordinates to avoid offset influence from other controls in the stack
                final position = Vector2(details.localPosition.dx, details.localPosition.dy);
                await game.onTapDown(position);
              },
              onScaleStart: (details) {
                final position = Vector2(details.localFocalPoint.dx, details.localFocalPoint.dy);
                  game.onScaleStart(position);
              },
              onScaleUpdate: (details) {
                final position = Vector2(details.localFocalPoint.dx, details.localFocalPoint.dy);
                game.onScaleUpdate(details.scale, position);
              },
              onScaleEnd: (details) {
                  game.onScaleEnd();
              },
              child: MouseRegion(
                cursor: _getCursorForTool(selectedTool),
                child: GameWidget(game: game),
              ),
            ),
          ),
          
          // Top toolbar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopToolbar(context, theme),
          ),
          
          // Left edit toolbar
          Positioned(
            left: 10,
            top: 100,
            child: _buildEditToolbar(context, theme),
          ),
          
          // Right information panel
          Positioned(
            right: 10,
            top: 100,
            child: _buildInfoPanel(context, theme),
          ),
          
          // Bottom right button
          Positioned(
            right: 20,
            bottom: 20,
            child: _buildAddRobotPositionButton(context, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(BuildContext context, ThemeData theme) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.orange,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left toolbar buttons
          Expanded(
            child: Row(
              children: [
                // Open file button
                IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white, size: 28),
                  onPressed: () {
                    // TODO: Implement open file functionality
                    print('Open File');
                  },
                  tooltip: 'Open File',
                ),
                
                const SizedBox(width: 16),
                
                // Save button
                IconButton(
                  icon: const Icon(Icons.save, color: Colors.white, size: 28),
                  onPressed: () async {
                    List<NavPoint> navPoints = game.getAllWayPoint();
                    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
                    await navPointManager.saveNavPoints(navPoints);
                    
                    final topologyMap = TopologyMap(
                      points: navPoints,
                      routes: [],
                    );
                    await rosChannel.updateTopologyMap(topologyMap);

                    // Show save success message
                    if (mounted) {
                      toastification.show(
                        context: context,
                        type: ToastificationType.success,
                        style: ToastificationStyle.flatColored,
                        title:const Text('Saved Successfully!'),
                        autoCloseDuration: const Duration(seconds: 2),
                      );
                    }
                  },
                  tooltip: 'Save',
                ),
                
                const SizedBox(width: 16),
                
                // Undo button
                IconButton(
                  icon: const Icon(Icons.undo, color: Colors.white, size: 28),
                  onPressed: () {
                    // TODO: Implement undo functionality
                    print('Undo');
                  },
                  tooltip: 'Undo',
                ),
                
                const SizedBox(width: 16),
                
                // Redo button
                IconButton(
                  icon: const Icon(Icons.redo, color: Colors.white, size: 28),
                  onPressed: () {
                    // TODO: Implement redo functionality
                    print('Redo');
                  },
                  tooltip: 'Redo',
                ),
              ],
            ),
          ),
          
          // Center title
          Expanded(
            child: Center(
              child: Text(
                'Map Editor',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Right exit button
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () async {
                    // Save current state before exiting
                    List<NavPoint> navPoints = game.getAllWayPoint();
                    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
                    await navPointManager.saveNavPoints(navPoints);
                    
                    // Call exit callback
                    widget.onExit?.call();
                    
                    // Exit map editing mode
                    Navigator.pop(context);
                  },
                  tooltip: 'Exit Map Editing Mode',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditToolbar(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Navigation point addition tool
            _buildEditTool(
              icon: Icons.add_location,
              label: 'Nav Point Edit',
              toolName: EditToolType.addNavPoint,
              color: Colors.blue,
            ),
            
            const SizedBox(height: 8),
            
            // Obstacle drawing tool
            _buildEditTool(
              icon: Icons.brush,
              label: 'Draw Obstacle',
              toolName: EditToolType.drawObstacle,
              color: Colors.red,
            ),
            
            const SizedBox(height: 8),
            
            // Obstacle erasing tool
            _buildEditTool(
              icon: Icons.auto_fix_high,
              label: 'Erase Obstacle',
              toolName: EditToolType.eraseObstacle,
              color: Colors.green,
            ),
            
            const SizedBox(height: 8),
            

          ],
        ),
      ),
    );
  }
  


  Widget _buildEditTool({
    required IconData icon,
    required String label,
    required EditToolType toolName,
    required Color color,
  }) {
    final isActive = selectedTool == toolName;
    
    return Container(
      width: 120,
      child: Column(
        children: [
          IconButton(
            icon: Icon(icon, size: 24),
            color: isActive ? color : Colors.grey,
            onPressed: () {
               if (isActive) {
                selectedTool = null; // Deselect
                game.setSelectedTool(null);
                // Exit all waypoint editing modes
                for (final wp in game.wayPoints) {
                  wp.setEditMode(false);
                }
              } else {
                selectedTool = toolName; // Select tool
                game.setSelectedTool(toolName);
                // Exit all waypoint editing modes when switching to other tools
                if (toolName != EditToolType.addNavPoint) {
                  for (final wp in game.wayPoints) {
                    wp.setEditMode(false);
                  }
                }
              }
              setState(() {});
            },
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? color : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 8,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // If there's a selected navigation point, show its information
            if (selectedWayPointInfo != null) ...[
              _buildWayPointInfo(theme),
              const SizedBox(height: 16),
            ] else ...[
              // Otherwise show edit mode instructions
              Text(
                'Edit Mode Instructions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              _buildInstructionItem(
                icon: Icons.add_location,
                title: 'Add Navigation Point',
                description: 'Select tool then double-click map to add navigation point',
                color: Colors.blue,
              ),
              
              const SizedBox(height: 12),
              
              _buildInstructionItem(
                icon: Icons.brush,
                title: 'Draw Obstacle',
                description: 'Drag mouse to draw obstacle areas',
                color: Colors.red,
              ),
              
              const SizedBox(height: 12),
              
              _buildInstructionItem(
                icon: Icons.auto_fix_high,
                title: 'Erase Obstacle',
                description: 'Drag mouse to erase obstacle areas',
                color: Colors.green,
              ),
              
              const SizedBox(height: 12),
              
              _buildInstructionItem(
                icon: Icons.touch_app,
                title: 'Navigation Point Operations',
                description: 'Click to select, drag to move, drag red dot to rotate, delete button to remove selected',
                color: Colors.orange,
              ),
              
              const SizedBox(height: 16),
            ],
            
            // Navigation point count display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_location, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Navigation Points',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          '${game.wayPointCount} points',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child:                    Text(
                      'Tip: Use mouse wheel to zoom, drag to move map',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Build navigation point information display
  Widget _buildWayPointInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                'Navigation Point Info',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          _buildInfoRow('Name', selectedWayPointInfo!.name),
          _buildInfoRow('X Coord', '${selectedWayPointInfo!.x.toStringAsFixed(2)} m'),
          _buildInfoRow('Y Coord', '${selectedWayPointInfo!.y.toStringAsFixed(2)} m'),
          _buildInfoRow('Orientation', '${(selectedWayPointInfo!.theta * 180 / 3.14159).toStringAsFixed(1)}°'),
          
          const SizedBox(height: 12),
          
          // Operation area: delete selected
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    String name = game.deleteSelectedWayPoint();
                    final navPointManager = Provider.of<NavPointManager>(context, listen: false);
                    navPointManager.removeNavPoint(name);
                    setState(() {
                      selectedWayPointInfo = null;
                    });
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // Build information row
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                description,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Build add robot position button
  Widget _buildAddRobotPositionButton(BuildContext context, ThemeData theme) {
    return AnimatedOpacity(
      opacity: selectedTool == EditToolType.addNavPoint ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: selectedTool == EditToolType.addNavPoint ? _onAddRobotPositionButtonPressed : null,
        icon: const Icon(Icons.my_location, size: 18),
        label: const Text('Use Current Position'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 4,
        ),
      ),
    );
  }
  
  // Button click handler
  void _onAddRobotPositionButtonPressed() async {
    await game.addNavPointAtRobotPosition();
  }
  
  // Get mouse cursor based on tool type
  MouseCursor _getCursorForTool(EditToolType? tool) {
    switch (tool) {
      case EditToolType.addNavPoint:
        return SystemMouseCursors.precise;
      case EditToolType.drawObstacle:
        return SystemMouseCursors.precise; // Hide system cursor, use custom brush cursor
      case EditToolType.eraseObstacle:
        return SystemMouseCursors.precise; // Hide system cursor, use custom square cursor
      case null:
        return SystemMouseCursors.basic;
    }
  }
}
