class HearRateReading {
  final int? id;
  final double bpm;
  final int accuracy;
  final DateTime time;

  const HearRateReading({
    this.id,
    required this.bpm,
    required this.accuracy,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
    'bpm': bpm,
    'accuracy': accuracy,
    'time': time.millisecondsSinceEpoch,
  };

  factory HearRateReading.fromMap(Map<String, dynamic> map) {
    return HearRateReading(
      id: map['id'] as int?,
      bpm: (map['bpm'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toInt(),
      time: DateTime.fromMillisecondsSinceEpoch(map['time'] as int),
    );
  }
}
