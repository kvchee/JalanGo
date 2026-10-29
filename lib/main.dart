TileLayer(
  urlTemplate: tiles,
  subdomains: _darkMap ? const ['a', 'b', 'c', 'd'] : const [],
  userAgentPackageName: 'my.jalango.app',
  tileProvider: NetworkTileProvider(),
),
