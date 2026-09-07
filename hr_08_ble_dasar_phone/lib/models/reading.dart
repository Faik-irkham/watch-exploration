class HeartRateReading {
  final int? id;
  final int bpm;
  final DateTime time;

  const HeartRateReading({this.id, required this.bpm, required this.time});

  Map<String, dynamic> toMap() => {
    'bpm': bpm,
    'time': time.millisecondsSinceEpoch,
  };

  factory HeartRateReading.fromMap(Map<String, dynamic> map) {
    return HeartRateReading(
      id: map['id'] as int?,
      bpm: (map['bpm'] as num).toInt(),
      time: DateTime.fromMillisecondsSinceEpoch(map['time'] as int),
    );
  }
}
