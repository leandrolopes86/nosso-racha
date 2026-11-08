class SportConfig {
  static const int minimumLinePlayersPerTeam = 2;
  static const int maximumLinePlayersPerTeam = 10;

  static List<int> get linePlayersPerTeamOptions => List.generate(
    maximumLinePlayersPerTeam - minimumLinePlayersPerTeam + 1,
    (index) => minimumLinePlayersPerTeam + index,
  );

  final String id;
  final String label;
  final int defaultLinePlayersPerTeam;
  final bool hasGoalkeeper;

  const SportConfig({
    required this.id,
    required this.label,
    required this.defaultLinePlayersPerTeam,
    required this.hasGoalkeeper,
  });

  static const List<SportConfig> all = [
    SportConfig(
      id: 'football',
      label: 'Futebol',
      defaultLinePlayersPerTeam: 6,
      hasGoalkeeper: true,
    ),
    SportConfig(
      id: 'futsal',
      label: 'Futsal',
      defaultLinePlayersPerTeam: 4,
      hasGoalkeeper: true,
    ),
    SportConfig(
      id: 'handball',
      label: 'Handebol',
      defaultLinePlayersPerTeam: 6,
      hasGoalkeeper: true,
    ),
    SportConfig(
      id: 'volleyball',
      label: 'Vôlei',
      defaultLinePlayersPerTeam: 6,
      hasGoalkeeper: false,
    ),
    SportConfig(
      id: 'basketball',
      label: 'Basquete',
      defaultLinePlayersPerTeam: 5,
      hasGoalkeeper: false,
    ),
  ];

  static SportConfig fromId(String id) =>
      all.firstWhere((sport) => sport.id == id, orElse: () => all.first);

  static bool isSupported(String id) => all.any((sport) => sport.id == id);
}
