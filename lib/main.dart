import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const JalanGoApp());
}

class JalanGoApp extends StatelessWidget {
  const JalanGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JalanGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F5B),
        ),
      ),
      home: const MapHome(),
    );
  }
}

class _RoadReport {
  final String label;
  final LatLng point;
  final IconData icon;
  final Color color;

  const _RoadReport({
    required this.label,
    required this.point,
    required this.icon,
    required this.color,
  });
}

class _DrivingStep {
  final String instruction;
  final String roadName;
  final double distanceMetres;
  final IconData icon;

  const _DrivingStep({
    required this.instruction,
    required this.roadName,
    required this.distanceMetres,
    required this.icon,
  });
}

class MapHome extends StatefulWidget {
  const MapHome({super.key});

  @override
  State<MapHome> createState() => _MapHomeState();
}

class _MapHomeState extends State<MapHome> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController =
      TextEditingController();

  LatLng _currentLocation = const LatLng(3.1390, 101.6869);
  LatLng? _destination;

  List<LatLng> _routePoints = [];
  List<_DrivingStep> _steps = [];
  final List<_RoadReport> _reports = [];

  bool _isDarkMap = false;
  bool _isLoadingLocation = false;
  bool _isSearching = false;

  String _status = 'Ready to explore';
  String _destinationName = '';

  double? _routeDistanceMetres;
  double? _routeDurationSeconds;

  static const Color _brandGreen = Color(0xFF087F5B);
  static const Color _routeBlue = Color(0xFF087FDE);

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _status = 'Finding your location...';
    });

    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _setLocationStatus(
          'Please turn on your phone location service.',
        );
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _setLocationStatus('Location permission was denied.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _setLocationStatus(
          'Enable location permission in your phone settings.',
        );
        return;
      }

      final Position position =
          await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final LatLng point = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _currentLocation = point;
        _isLoadingLocation = false;
        _status = 'Your location is ready.';
      });

      _mapController.move(point, 16);
    } catch (e) {
      _setLocationStatus(
        'Could not get your location. Please try again.',
      );
    }
  }

  void _setLocationStatus(String message) {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = false;
      _status = message;
    });
  }

  Future<void> _searchDestination() async {
    final String query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _status = 'Enter a destination first.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _status = 'Searching for $query...';
      _routePoints = [];
      _steps = [];
      _routeDistanceMetres = null;
      _routeDurationSeconds = null;
    });

    try {
      final Uri searchUri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
          'countrycodes': 'my',
        },
      );

      final http.Response response = await http.get(
        searchUri,
        headers: const {
          'User-Agent': 'JalanGo/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Destination search failed.');
      }

      final List<dynamic> results =
          jsonDecode(response.body) as List<dynamic>;

      if (results.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isSearching = false;
          _status = 'No destination found. Try another search.';
        });
        return;
      }

      final Map<String, dynamic> place =
          results.first as Map<String, dynamic>;

      final LatLng destination = LatLng(
        double.parse(place['lat'].toString()),
        double.parse(place['lon'].toString()),
      );

      final String name =
          place['display_name']?.toString() ?? query;

      if (!mounted) return;

      setState(() {
        _destination = destination;
        _destinationName = name;
        _isSearching = false;
        _status = 'Destination found. Calculating route...';
      });

      _mapController.move(destination, 14);

      await _getDrivingRoute(destination);
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _status = 'Search timed out. Please try again.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _status =
            'Search failed. Check your internet connection.';
      });
    }
  }

  Future<void> _getDrivingRoute(LatLng destination) async {
    try {
      final String coordinates =
          '${_currentLocation.longitude},${_currentLocation.latitude};'
          '${destination.longitude},${destination.latitude}';

      final Uri routeUri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$coordinates?overview=full&geometries=geojson&steps=true',
      );

      final http.Response response = await http.get(
        routeUri,
        headers: const {
          'User-Agent': 'JalanGo/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Route request failed.');
      }

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (data['code'] != 'Ok') {
        throw Exception('No route found.');
      }

      final List<dynamic> routes = data['routes'] as List<dynamic>;

      if (routes.isEmpty) {
        throw Exception('No route found.');
      }

      final Map<String, dynamic> route =
          routes.first as Map<String, dynamic>;

      final Map<String, dynamic> geometry =
          route['geometry'] as Map<String, dynamic>;

      final List<dynamic> coordinatesList =
          geometry['coordinates'] as List<dynamic>;

      final List<LatLng> points = coordinatesList.map(
        (dynamic item) {
          final List<dynamic> coordinate = item as List<dynamic>;

          return LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          );
        },
      ).toList();

      final List<_DrivingStep> newSteps = [];
      final List<dynamic> legs = route['legs'] as List<dynamic>;

      for (final dynamic legItem in legs) {
        final Map<String, dynamic> leg =
            legItem as Map<String, dynamic>;

        final List<dynamic> legSteps =
            leg['steps'] as List<dynamic>? ?? [];

        for (final dynamic stepItem in legSteps) {
          final Map<String, dynamic> step =
              stepItem as Map<String, dynamic>;

          final Map<String, dynamic> maneuver =
              step['maneuver'] as Map<String, dynamic>? ?? {};

          final String type =
              maneuver['type']?.toString() ?? 'continue';

          final String modifier =
              maneuver['modifier']?.toString() ?? '';

          final String roadName =
              step['name']?.toString() ?? '';

          final double distance =
              (step['distance'] as num?)?.toDouble() ?? 0;

          newSteps.add(
            _DrivingStep(
              instruction: _makeInstruction(type, modifier),
              roadName: roadName,
              distanceMetres: distance,
              icon: _instructionIcon(type, modifier),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _routePoints = points;
        _steps = newSteps;
        _routeDistanceMetres =
            (route['distance'] as num?)?.toDouble() ?? 0;
        _routeDurationSeconds =
            (route['duration'] as num?)?.toDouble() ?? 0;
        _status = 'Route ready. Drive safely!';
      });

      if (points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(60),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _routePoints = [];
        _steps = [];
        _routeDistanceMetres = null;
        _routeDurationSeconds = null;
        _status =
            'Could not calculate the route. Please try again.';
      });
    }
  }

  String _makeInstruction(String type, String modifier) {
    switch (type) {
      case 'depart':
        return 'Start your journey';
      case 'arrive':
        return 'Arrive at your destination';
      case 'turn':
        return 'Turn ${modifier.isEmpty ? 'ahead' : modifier}';
      case 'new name':
        return 'Continue onto the next road';
      case 'merge':
        return 'Merge ${modifier.isEmpty ? 'ahead' : modifier}';
      case 'on ramp':
        return 'Take the ramp';
      case 'off ramp':
        return 'Take the exit ramp';
      case 'fork':
        return 'Keep ${modifier.isEmpty ? 'straight' : modifier} at the fork';
      case 'roundabout':
      case 'rotary':
        return 'Enter the roundabout';
      case 'end of road':
        return 'At the end of the road, turn ${modifier.isEmpty ? 'ahead' : modifier}';
      case 'continue':
        return 'Continue straight';
      default:
        return 'Continue along the route';
    }
  }

  IconData _instructionIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.flag_rounded;
    if (type == 'depart') return Icons.play_arrow_rounded;

    if (type == 'roundabout' || type == 'rotary') {
      return Icons.roundabout_right_rounded;
    }

    if (modifier.contains('left')) {
      return Icons.turn_left_rounded;
    }

    if (modifier.contains('right')) {
      return Icons.turn_right_rounded;
    }

    if (type == 'merge') return Icons.merge_rounded;

    return Icons.straight_rounded;
  }

  String _formatDistance(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }

    return '${metres.round()} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '--';

    final int minutes = (seconds / 60).round();

    if (minutes < 60) return '$minutes min';

    final int hours = minutes ~/ 60;
    final int remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) return '$hours hr';

    return '$hours hr $remainingMinutes min';
  }

  void _addRoadReport(
    String label,
    IconData icon,
    Color color,
  ) {
    setState(() {
      _reports.add(
        _RoadReport(
          label: label,
          point: _currentLocation,
          icon: icon,
          color: color,
        ),
      );

      _status = '$label report added to this session.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label report added.'),
      ),
    );
  }

  Future<void> _openDirections() async {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Search for a destination to get directions.',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Driving directions',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _destinationName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: _steps.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final _DrivingStep step = _steps[index];

                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(step.icon),
                        ),
                        title: Text(step.instruction),
                        subtitle: Text(
                          step.roadName.isEmpty
                              ? 'Unnamed road'
                              : step.roadName,
                        ),
                        trailing: Text(
                          _formatDistance(step.distanceMetres),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRoadReports() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report a road issue',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose an issue at your current GPS location.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _reportButton(
                      sheetContext,
                      'Traffic',
                      Icons.traffic_rounded,
                      Colors.orange,
                    ),
                    _reportButton(
                      sheetContext,
                      'Road hazard',
                      Icons.warning_rounded,
                      Colors.red,
                    ),
                    _reportButton(
                      sheetContext,
                      'Road closure',
                      Icons.block_rounded,
                      Colors.deepPurple,
                    ),
                    _reportButton(
                      sheetContext,
                      'Flooding',
                      Icons.water_rounded,
                      Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reportButton(
    BuildContext sheetContext,
    String label,
    IconData icon,
    Color color,
  ) {
    return FilledButton.tonalIcon(
      onPressed: () {
        Navigator.pop(sheetContext);
        _addRoadReport(label, icon, color);
      },
      icon: Icon(icon, color: color),
      label: Text(label),
    );
  }

  Future<void> _openOpenStreetMap() async {
    final Uri uri = Uri.parse(
      'https://www.openstreetmap.org/'
      '?mlat=${_currentLocation.latitude}'
      '&mlon=${_currentLocation.longitude}'
      '#map=15/${_currentLocation.latitude}/${_currentLocation.longitude}',
    );

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _destination = null;
      _destinationName = '';
      _routePoints = [];
      _steps = [];
      _routeDistanceMetres = null;
      _routeDurationSeconds = null;
      _status = 'Ready to explore';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _brandGreen,
        foregroundColor: Colors.white,
        titleSpacing: 16,
        title: Row(
          children: [
            const Icon(Icons.navigation_rounded, size: 30),
            const SizedBox(width: 8),
            const Text(
              'JalanGo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              tooltip: _isDarkMap ? 'Light map' : 'Dark map',
              onPressed: () {
                setState(() {
                  _isDarkMap = !_isDarkMap;
                });
              },
              icon: Icon(
                _isDarkMap
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchPanel(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation,
                    initialZoom: 12,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _isDarkMap
                          ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.jalango.app',
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 7,
                                                       color: const Color(0xFF087FDE)
                                .withValues(alpha: 0.25),
                          ),
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 4,
                            color: const Color(0xFF087FDE),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLocation,
                          width: 46,
                          height: 46,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.my_location_rounded,
                              color: Color(0xFF087FDE),
                              size: 27,
                            ),
                          ),
                        ),
                        if (_destination != null)
                          Marker(
                            point: _destination!,
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 46,
                            ),
                          ),
                        ..._reports.map(
                          (_RoadReport report) => Marker(
                            point: report.point,
                            width: 42,
                            height: 42,
                            child: Tooltip(
                              message: report.label,
                              child: Icon(
                                report.icon,
                                color: report.color,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          onTap: _openOpenStreetMap,
                        ),
                        const TextSourceAttribution('CARTO'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Column(
                    children: [
                      _mapActionButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'My location',
                        onPressed: _getCurrentLocation,
                      ),
                      const SizedBox(height: 8),
                      _mapActionButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Zoom in',
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom + 1,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _mapActionButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Zoom out',
                        onPressed: () {
                          _mapController.move(
                            _mapController.camera.center,
                            _mapController.camera.zoom - 1,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (_isLoadingLocation || _isSearching)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchDestination(),
            decoration: InputDecoration(
              hintText: 'Where do you want to go?',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: _clearSearch,
                icon: const Icon(Icons.close_rounded),
              ),
              filled: true,
              fillColor: Theme.of(context)
                  .colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF087F5B),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSearching ? null : _searchDestination,
              icon: const Icon(Icons.directions_rounded),
              label: Text(
                _isSearching ? 'Searching...' : 'Find driving route',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF087F5B),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_routeDistanceMetres != null &&
              _routeDurationSeconds != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.route_rounded,
                  color: Color(0xFF087F5B),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDistance(_routeDistanceMetres!),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF087F5B),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(_routeDurationSeconds),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openDirections,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('Directions'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showRoadReports,
                  icon: const Icon(Icons.report_problem_rounded),
                  label: const Text('Report issue'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Route estimates may vary. Follow road signs and drive safely.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _mapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
