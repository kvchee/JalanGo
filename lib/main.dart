import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const JalanGoApp());

class JalanGoApp extends StatelessWidget {
  const JalanGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const green = Color(0xFF087F5B);

    return MaterialApp(
      title: 'JalanGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const MapHome(),
    );
  }
}

class MapHome extends StatefulWidget {
  const MapHome({super.key});

  @override
  State<MapHome> createState() => _MapHomeState();
}

class _MapHomeState extends State<MapHome> {
  final MapController _mapController = MapController();

  final TextEditingController _destinationController =
      TextEditingController();

  LatLng _center = const LatLng(3.1390, 101.6869);

  bool _darkMap = false;
  bool _busy = false;

  LatLng? _currentLocation;
  LatLng? _destinationPoint;

  List<LatLng> _routePoints = [];
  List<_DrivingStep> _directions = [];

  double _routeDistanceKm = 0;
  int _routeDurationMinutes = 0;

  String _destinationName = '';
  String _status = 'Ready to explore Malaysia';

  final List<_RoadReport> _reports = [
    _RoadReport(
      'Road hazard',
      const LatLng(3.145, 101.693),
      Icons.warning_amber_rounded,
    ),
    _RoadReport(
      'Traffic',
      const LatLng(3.132, 101.679),
      Icons.traffic_rounded,
    ),
  ];

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          _status = 'Allow location permission in Android settings.';
        });
        return;
      }

      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          _status = 'Turn on GPS on your phone and try again.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final point = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _center = point;
        _currentLocation = point;
        _status = 'Showing your current location';
      });

      _mapController.move(point, 15);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = 'Could not get location. Check GPS and permissions.';
      });
    }
  }

  Future<void> _searchDestination() async {
    final destination = _destinationController.text.trim();

    if (destination.isEmpty) {
      setState(() {
        _status = 'Enter a destination to search.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Searching for "$destination"...';
    });

    try {
      // Find the destination in Malaysia.
      final searchUri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': '$destination, Malaysia',
          'format': 'jsonv2',
          'limit': '1',
          'addressdetails': '1',
        },
      );

      final searchResponse = await http.get(
        searchUri,
        headers: {
          'User-Agent': 'JalanGo/0.2 (Android navigation app)',
          'Accept-Language': 'en,ms',
        },
      ).timeout(const Duration(seconds: 20));

      if (searchResponse.statusCode != 200) {
        throw Exception('Destination search failed.');
      }

      final searchResults =
          jsonDecode(searchResponse.body) as List<dynamic>;

      if (searchResults.isEmpty) {
        if (!mounted) return;

        setState(() {
          _busy = false;
          _status = 'No place found. Try adding a town or state.';
        });
        return;
      }

      final place = searchResults.first as Map<String, dynamic>;

      final target = LatLng(
        double.parse(place['lat'] as String),
        double.parse(place['lon'] as String),
      );

      final placeName =
          (place['display_name'] as String?) ?? destination;

      // Use GPS as the starting point when available.
      // Otherwise, use the current map centre.
      final start = _currentLocation ?? _center;

      setState(() {
        _status = 'Calculating driving route...';
      });

      // Request the route geometry and individual driving steps.
      final routeUri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/'
            '${start.longitude},${start.latitude};'
            '${target.longitude},${target.latitude}',
        {
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'true',
          'alternatives': 'false',
        },
      );

      final routeResponse = await http.get(
        routeUri,
        headers: {
          'User-Agent': 'JalanGo/0.2 (Android navigation app)',
        },
      ).timeout(const Duration(seconds: 30));

      if (routeResponse.statusCode != 200) {
        throw Exception('Driving route request failed.');
      }

      final routeData =
          jsonDecode(routeResponse.body) as Map<String, dynamic>;

      if (routeData['code'] != 'Ok') {
        throw Exception('No driving route was found.');
      }

      final routes = routeData['routes'] as List<dynamic>? ?? [];

      if (routes.isEmpty) {
        throw Exception('No driving route was found.');
      }

      final route = routes.first as Map<String, dynamic>;

      // Convert the route geometry into map points.
      final geometry =
          route['geometry'] as Map<String, dynamic>;

      final coordinates =
          geometry['coordinates'] as List<dynamic>;

      final points = coordinates.map((coordinate) {
        final pair = coordinate as List<dynamic>;

        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();

      // Read the driving instructions from the route legs.
      final legs = route['legs'] as List<dynamic>? ?? [];
      final List<_DrivingStep> steps = [];

      for (final legValue in legs) {
        final leg = legValue as Map<String, dynamic>;
        final legSteps =
            leg['steps'] as List<dynamic>? ?? [];

        for (final stepValue in legSteps) {
          final step = stepValue as Map<String, dynamic>;

          final maneuver =
              step['maneuver'] as Map<String, dynamic>? ?? {};

          final type = maneuver['type'] as String? ?? 'continue';
          final modifier =
              maneuver['modifier'] as String? ?? '';
          final roadName = step['name'] as String? ?? '';

          final distance =
              (step['distance'] as num?)?.toDouble() ?? 0;

          final instruction = _makeInstruction(
            type: type,
            modifier: modifier,
            roadName: roadName,
            exitNumber: maneuver['exit']?.toString(),
          );

          steps.add(
            _DrivingStep(
              instruction: instruction,
              roadName: roadName,
              distanceMetres: distance,
              icon: _instructionIcon(type, modifier),
            ),
          );
        }
      }

      final distanceKm =
          ((route['distance'] as num).toDouble() / 1000);

      final durationMinutes =
          ((route['duration'] as num).toDouble() / 60).round();

      if (!mounted) return;

      setState(() {
        _busy = false;

        _destinationPoint = target;
        _destinationName = placeName;

        _routePoints = points;
        _directions = steps;

        _routeDistanceKm = distanceKm;
        _routeDurationMinutes = durationMinutes;

        _status = 'Route ready: ${distanceKm.toStringAsFixed(1)} km, '
            'about $durationMinutes min.';
      });

      // Fit the map to show the entire route.
      if (points.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(45),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _status =
            'Could not calculate the route. Check internet and try again.';
      });
    }
  }

  String _makeInstruction({
    required String type,
    required String modifier,
    required String roadName,
    String? exitNumber,
  }) {
    final road = roadName.trim().isEmpty ? '' : ' onto $roadName';

    switch (type) {
      case 'depart':
        return roadName.trim().isEmpty
            ? 'Start driving'
            : 'Start driving on $roadName';

      case 'arrive':
        return 'You have arrived at your destination';

      case 'turn':
        return 'Turn ${modifier.isEmpty ? 'ahead' : modifier}$road';

      case 'new name':
        return roadName.trim().isEmpty
            ? 'Continue on the road'
            : 'Continue onto $roadName';

      case 'continue':
        return roadName.trim().isEmpty
            ? 'Continue straight'
            : 'Continue on $roadName';

      case 'merge':
        return 'Merge ${modifier.isEmpty ? 'ahead' : modifier}$road';

      case 'on ramp':
        return 'Take the ramp$road';

      case 'off ramp':
        return 'Take the exit ramp$road';

      case 'fork':
        return 'Keep ${modifier.isEmpty ? 'straight' : modifier}$road';

      case 'roundabout':
      case 'rotary':
        if (exitNumber != null && exitNumber.isNotEmpty) {
          return 'At the roundabout, take exit $exitNumber$road';
        }
        return 'Enter the roundabout$road';

      case 'end of road':
        return 'At the end of the road, turn '
            '${modifier.isEmpty ? 'ahead' : modifier}$road';

      case 'use lane':
        return 'Follow the indicated lane$road';

      case 'notification':
        return roadName.trim().isEmpty
            ? 'Continue along the route'
            : 'Continue on $roadName';

      default:
        return roadName.trim().isEmpty
            ? 'Continue along the route'
            : 'Continue on $roadName';
    }
  }

  IconData _instructionIcon(String type, String modifier) {
    if (type == 'depart') return Icons.play_arrow_rounded;
    if (type == 'arrive') return Icons.flag_rounded;

    if (type == 'roundabout' || type == 'rotary') {
      return Icons.roundabout_right_rounded;
    }

    if (type == 'merge' || type == 'fork') {
      return Icons.call_split_rounded;
    }

    if (type == 'on ramp' || type == 'off ramp') {
      return Icons.turn_sharp_right_rounded;
    }

    if (modifier.contains('left')) {
      return Icons.turn_left_rounded;
    }

    if (modifier.contains('right')) {
      return Icons.turn_right_rounded;
    }

    if (modifier == 'uturn') {
      return Icons.u_turn_left_rounded;
    }

    return Icons.straight_rounded;
  }

  String _formatDistance(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }

    return '${metres.round()} m';
  }

  void _showDirections() {
    if (_directions.isEmpty) {
      setState(() {
        _status = 'Search for a destination to get driving directions.';
      });
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driving directions',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _destinationName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_routeDistanceKm.toStringAsFixed(1)} km'
                        '  ·  about $_routeDurationMinutes min',
                        style: const TextStyle(
                          color: Color(0xFF087F5B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: _directions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final step = _directions[index];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              const Color(0xFFE5F4ED),
                          foregroundColor:
                              const Color(0xFF087F5B),
                          child: Icon(step.icon),
                        ),
                        title: Text(
                          step.instruction,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: step.roadName.isEmpty
                            ? null
                            : Text(step.roadName),
                        trailing: Text(
                          _formatDistance(step.distanceMetres),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
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

  void _addReport() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report a road issue',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _reportButton(
                    sheetContext,
                    'Traffic',
                    Icons.traffic_rounded,
                  ),
                  _reportButton(
                    sheetContext,
                    'Accident',
                    Icons.car_crash_rounded,
                  ),
                  _reportButton(
                    sheetContext,
                    'Hazard',
                    Icons.warning_amber_rounded,
                  ),
                  _reportButton(
                    sheetContext,
                    'Flood',
                    Icons.flood_rounded,
                  ),
                  _reportButton(
                    sheetContext,
                    'Roadworks',
                    Icons.construction_rounded,
                  ),
                  _reportButton(
                    sheetContext,
                    'Pothole',
                    Icons.tire_repair_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Prototype only: reports are not sent to a server '
                'or shared with other drivers yet.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportButton(
    BuildContext sheetContext,
    String label,
    IconData icon,
  ) {
    return FilledButton.tonalIcon(
      onPressed: () {
        Navigator.pop(sheetContext);

        setState(() {
          _status =
              '$label report selected. Community service is not connected yet.';
        });
      },
      icon: Icon(icon),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _darkMap
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.navigation_rounded,
                color: Color(0xFF087F5B),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'JalanGo',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch map theme',
            onPressed: () {
              setState(() {
                _darkMap = !_darkMap;
              });
            },
            icon: Icon(
              _darkMap ? Icons.light_mode : Icons.dark_mode,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _destinationController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchDestination(),
                    decoration: InputDecoration(
                      hintText: 'Where to? e.g. Johor Bahru',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
        
