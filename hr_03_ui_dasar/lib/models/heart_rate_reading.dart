class HeartRateReading {
  final int? id;
  final double bpm;
  final int accuracy;
  final DateTime time;

  const HeartRateReading({
    this.id,
    required this.bpm,
    required this.accuracy,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
    'bpm': bpm,
    'accuracy': accuracy,
    'time': time,
  };

  factory HeartRateReading.fromMap(Map<String, dynamic> map) {
    return HeartRateReading(
      id: map['id'] as int?,
      bpm: (map['bpm'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toInt(),
      time: DateTime.fromMillisecondsSinceEpoch(map['time'] as int),
    );
  }
}
