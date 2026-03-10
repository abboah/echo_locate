// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $MeasurementsTable extends Measurements
    with TableInfo<$MeasurementsTable, Measurement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeasurementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMeta = const VerificationMeta(
    'distance',
  );
  @override
  late final GeneratedColumn<double> distance = GeneratedColumn<double>(
    'distance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _angleMeta = const VerificationMeta('angle');
  @override
  late final GeneratedColumn<double> angle = GeneratedColumn<double>(
    'angle',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signalStrengthMeta = const VerificationMeta(
    'signalStrength',
  );
  @override
  late final GeneratedColumn<double> signalStrength = GeneratedColumn<double>(
    'signal_strength',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    x,
    y,
    distance,
    angle,
    signalStrength,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'measurements';
  @override
  VerificationContext validateIntegrity(
    Insertable<Measurement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('distance')) {
      context.handle(
        _distanceMeta,
        distance.isAcceptableOrUnknown(data['distance']!, _distanceMeta),
      );
    } else if (isInserting) {
      context.missing(_distanceMeta);
    }
    if (data.containsKey('angle')) {
      context.handle(
        _angleMeta,
        angle.isAcceptableOrUnknown(data['angle']!, _angleMeta),
      );
    } else if (isInserting) {
      context.missing(_angleMeta);
    }
    if (data.containsKey('signal_strength')) {
      context.handle(
        _signalStrengthMeta,
        signalStrength.isAcceptableOrUnknown(
          data['signal_strength']!,
          _signalStrengthMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_signalStrengthMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Measurement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Measurement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      distance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance'],
      )!,
      angle: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}angle'],
      )!,
      signalStrength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}signal_strength'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $MeasurementsTable createAlias(String alias) {
    return $MeasurementsTable(attachedDatabase, alias);
  }
}

class Measurement extends DataClass implements Insertable<Measurement> {
  final int id;
  final double x;
  final double y;
  final double distance;
  final double angle;
  final double signalStrength;
  final int timestamp;
  const Measurement({
    required this.id,
    required this.x,
    required this.y,
    required this.distance,
    required this.angle,
    required this.signalStrength,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['distance'] = Variable<double>(distance);
    map['angle'] = Variable<double>(angle);
    map['signal_strength'] = Variable<double>(signalStrength);
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  MeasurementsCompanion toCompanion(bool nullToAbsent) {
    return MeasurementsCompanion(
      id: Value(id),
      x: Value(x),
      y: Value(y),
      distance: Value(distance),
      angle: Value(angle),
      signalStrength: Value(signalStrength),
      timestamp: Value(timestamp),
    );
  }

  factory Measurement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Measurement(
      id: serializer.fromJson<int>(json['id']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      distance: serializer.fromJson<double>(json['distance']),
      angle: serializer.fromJson<double>(json['angle']),
      signalStrength: serializer.fromJson<double>(json['signalStrength']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'distance': serializer.toJson<double>(distance),
      'angle': serializer.toJson<double>(angle),
      'signalStrength': serializer.toJson<double>(signalStrength),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  Measurement copyWith({
    int? id,
    double? x,
    double? y,
    double? distance,
    double? angle,
    double? signalStrength,
    int? timestamp,
  }) => Measurement(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    distance: distance ?? this.distance,
    angle: angle ?? this.angle,
    signalStrength: signalStrength ?? this.signalStrength,
    timestamp: timestamp ?? this.timestamp,
  );
  Measurement copyWithCompanion(MeasurementsCompanion data) {
    return Measurement(
      id: data.id.present ? data.id.value : this.id,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      distance: data.distance.present ? data.distance.value : this.distance,
      angle: data.angle.present ? data.angle.value : this.angle,
      signalStrength: data.signalStrength.present
          ? data.signalStrength.value
          : this.signalStrength,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Measurement(')
          ..write('id: $id, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('distance: $distance, ')
          ..write('angle: $angle, ')
          ..write('signalStrength: $signalStrength, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, x, y, distance, angle, signalStrength, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Measurement &&
          other.id == this.id &&
          other.x == this.x &&
          other.y == this.y &&
          other.distance == this.distance &&
          other.angle == this.angle &&
          other.signalStrength == this.signalStrength &&
          other.timestamp == this.timestamp);
}

class MeasurementsCompanion extends UpdateCompanion<Measurement> {
  final Value<int> id;
  final Value<double> x;
  final Value<double> y;
  final Value<double> distance;
  final Value<double> angle;
  final Value<double> signalStrength;
  final Value<int> timestamp;
  const MeasurementsCompanion({
    this.id = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.distance = const Value.absent(),
    this.angle = const Value.absent(),
    this.signalStrength = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  MeasurementsCompanion.insert({
    this.id = const Value.absent(),
    required double x,
    required double y,
    required double distance,
    required double angle,
    required double signalStrength,
    required int timestamp,
  }) : x = Value(x),
       y = Value(y),
       distance = Value(distance),
       angle = Value(angle),
       signalStrength = Value(signalStrength),
       timestamp = Value(timestamp);
  static Insertable<Measurement> custom({
    Expression<int>? id,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? distance,
    Expression<double>? angle,
    Expression<double>? signalStrength,
    Expression<int>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (distance != null) 'distance': distance,
      if (angle != null) 'angle': angle,
      if (signalStrength != null) 'signal_strength': signalStrength,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  MeasurementsCompanion copyWith({
    Value<int>? id,
    Value<double>? x,
    Value<double>? y,
    Value<double>? distance,
    Value<double>? angle,
    Value<double>? signalStrength,
    Value<int>? timestamp,
  }) {
    return MeasurementsCompanion(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      distance: distance ?? this.distance,
      angle: angle ?? this.angle,
      signalStrength: signalStrength ?? this.signalStrength,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (distance.present) {
      map['distance'] = Variable<double>(distance.value);
    }
    if (angle.present) {
      map['angle'] = Variable<double>(angle.value);
    }
    if (signalStrength.present) {
      map['signal_strength'] = Variable<double>(signalStrength.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementsCompanion(')
          ..write('id: $id, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('distance: $distance, ')
          ..write('angle: $angle, ')
          ..write('signalStrength: $signalStrength, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $FloorPlansTable extends FloorPlans
    with TableInfo<$FloorPlansTable, FloorPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FloorPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalPointsMeta = const VerificationMeta(
    'totalPoints',
  );
  @override
  late final GeneratedColumn<int> totalPoints = GeneratedColumn<int>(
    'total_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaEstimateMeta = const VerificationMeta(
    'areaEstimate',
  );
  @override
  late final GeneratedColumn<double> areaEstimate = GeneratedColumn<double>(
    'area_estimate',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _measurementDateMeta = const VerificationMeta(
    'measurementDate',
  );
  @override
  late final GeneratedColumn<int> measurementDate = GeneratedColumn<int>(
    'measurement_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scanDurationMeta = const VerificationMeta(
    'scanDuration',
  );
  @override
  late final GeneratedColumn<int> scanDuration = GeneratedColumn<int>(
    'scan_duration',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceInfoMeta = const VerificationMeta(
    'deviceInfo',
  );
  @override
  late final GeneratedColumn<String> deviceInfo = GeneratedColumn<String>(
    'device_info',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
    totalPoints,
    areaEstimate,
    measurementDate,
    scanDuration,
    deviceInfo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'floor_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<FloorPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('total_points')) {
      context.handle(
        _totalPointsMeta,
        totalPoints.isAcceptableOrUnknown(
          data['total_points']!,
          _totalPointsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalPointsMeta);
    }
    if (data.containsKey('area_estimate')) {
      context.handle(
        _areaEstimateMeta,
        areaEstimate.isAcceptableOrUnknown(
          data['area_estimate']!,
          _areaEstimateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_areaEstimateMeta);
    }
    if (data.containsKey('measurement_date')) {
      context.handle(
        _measurementDateMeta,
        measurementDate.isAcceptableOrUnknown(
          data['measurement_date']!,
          _measurementDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_measurementDateMeta);
    }
    if (data.containsKey('scan_duration')) {
      context.handle(
        _scanDurationMeta,
        scanDuration.isAcceptableOrUnknown(
          data['scan_duration']!,
          _scanDurationMeta,
        ),
      );
    }
    if (data.containsKey('device_info')) {
      context.handle(
        _deviceInfoMeta,
        deviceInfo.isAcceptableOrUnknown(data['device_info']!, _deviceInfoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FloorPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FloorPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      totalPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_points'],
      )!,
      areaEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_estimate'],
      )!,
      measurementDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}measurement_date'],
      )!,
      scanDuration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scan_duration'],
      ),
      deviceInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_info'],
      ),
    );
  }

  @override
  $FloorPlansTable createAlias(String alias) {
    return $FloorPlansTable(attachedDatabase, alias);
  }
}

class FloorPlan extends DataClass implements Insertable<FloorPlan> {
  final String id;
  final String name;
  final String? description;
  final int createdAt;
  final int updatedAt;
  final int totalPoints;
  final double areaEstimate;
  final int measurementDate;
  final int? scanDuration;
  final String? deviceInfo;
  const FloorPlan({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.totalPoints,
    required this.areaEstimate,
    required this.measurementDate,
    this.scanDuration,
    this.deviceInfo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['total_points'] = Variable<int>(totalPoints);
    map['area_estimate'] = Variable<double>(areaEstimate);
    map['measurement_date'] = Variable<int>(measurementDate);
    if (!nullToAbsent || scanDuration != null) {
      map['scan_duration'] = Variable<int>(scanDuration);
    }
    if (!nullToAbsent || deviceInfo != null) {
      map['device_info'] = Variable<String>(deviceInfo);
    }
    return map;
  }

  FloorPlansCompanion toCompanion(bool nullToAbsent) {
    return FloorPlansCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      totalPoints: Value(totalPoints),
      areaEstimate: Value(areaEstimate),
      measurementDate: Value(measurementDate),
      scanDuration: scanDuration == null && nullToAbsent
          ? const Value.absent()
          : Value(scanDuration),
      deviceInfo: deviceInfo == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceInfo),
    );
  }

  factory FloorPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FloorPlan(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      totalPoints: serializer.fromJson<int>(json['totalPoints']),
      areaEstimate: serializer.fromJson<double>(json['areaEstimate']),
      measurementDate: serializer.fromJson<int>(json['measurementDate']),
      scanDuration: serializer.fromJson<int?>(json['scanDuration']),
      deviceInfo: serializer.fromJson<String?>(json['deviceInfo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'totalPoints': serializer.toJson<int>(totalPoints),
      'areaEstimate': serializer.toJson<double>(areaEstimate),
      'measurementDate': serializer.toJson<int>(measurementDate),
      'scanDuration': serializer.toJson<int?>(scanDuration),
      'deviceInfo': serializer.toJson<String?>(deviceInfo),
    };
  }

  FloorPlan copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    int? totalPoints,
    double? areaEstimate,
    int? measurementDate,
    Value<int?> scanDuration = const Value.absent(),
    Value<String?> deviceInfo = const Value.absent(),
  }) => FloorPlan(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    totalPoints: totalPoints ?? this.totalPoints,
    areaEstimate: areaEstimate ?? this.areaEstimate,
    measurementDate: measurementDate ?? this.measurementDate,
    scanDuration: scanDuration.present ? scanDuration.value : this.scanDuration,
    deviceInfo: deviceInfo.present ? deviceInfo.value : this.deviceInfo,
  );
  FloorPlan copyWithCompanion(FloorPlansCompanion data) {
    return FloorPlan(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      totalPoints: data.totalPoints.present
          ? data.totalPoints.value
          : this.totalPoints,
      areaEstimate: data.areaEstimate.present
          ? data.areaEstimate.value
          : this.areaEstimate,
      measurementDate: data.measurementDate.present
          ? data.measurementDate.value
          : this.measurementDate,
      scanDuration: data.scanDuration.present
          ? data.scanDuration.value
          : this.scanDuration,
      deviceInfo: data.deviceInfo.present
          ? data.deviceInfo.value
          : this.deviceInfo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FloorPlan(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('totalPoints: $totalPoints, ')
          ..write('areaEstimate: $areaEstimate, ')
          ..write('measurementDate: $measurementDate, ')
          ..write('scanDuration: $scanDuration, ')
          ..write('deviceInfo: $deviceInfo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    createdAt,
    updatedAt,
    totalPoints,
    areaEstimate,
    measurementDate,
    scanDuration,
    deviceInfo,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FloorPlan &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.totalPoints == this.totalPoints &&
          other.areaEstimate == this.areaEstimate &&
          other.measurementDate == this.measurementDate &&
          other.scanDuration == this.scanDuration &&
          other.deviceInfo == this.deviceInfo);
}

class FloorPlansCompanion extends UpdateCompanion<FloorPlan> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> totalPoints;
  final Value<double> areaEstimate;
  final Value<int> measurementDate;
  final Value<int?> scanDuration;
  final Value<String?> deviceInfo;
  final Value<int> rowid;
  const FloorPlansCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.totalPoints = const Value.absent(),
    this.areaEstimate = const Value.absent(),
    this.measurementDate = const Value.absent(),
    this.scanDuration = const Value.absent(),
    this.deviceInfo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FloorPlansCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    required int totalPoints,
    required double areaEstimate,
    required int measurementDate,
    this.scanDuration = const Value.absent(),
    this.deviceInfo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       totalPoints = Value(totalPoints),
       areaEstimate = Value(areaEstimate),
       measurementDate = Value(measurementDate);
  static Insertable<FloorPlan> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? totalPoints,
    Expression<double>? areaEstimate,
    Expression<int>? measurementDate,
    Expression<int>? scanDuration,
    Expression<String>? deviceInfo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (totalPoints != null) 'total_points': totalPoints,
      if (areaEstimate != null) 'area_estimate': areaEstimate,
      if (measurementDate != null) 'measurement_date': measurementDate,
      if (scanDuration != null) 'scan_duration': scanDuration,
      if (deviceInfo != null) 'device_info': deviceInfo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FloorPlansCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? totalPoints,
    Value<double>? areaEstimate,
    Value<int>? measurementDate,
    Value<int?>? scanDuration,
    Value<String?>? deviceInfo,
    Value<int>? rowid,
  }) {
    return FloorPlansCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalPoints: totalPoints ?? this.totalPoints,
      areaEstimate: areaEstimate ?? this.areaEstimate,
      measurementDate: measurementDate ?? this.measurementDate,
      scanDuration: scanDuration ?? this.scanDuration,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (totalPoints.present) {
      map['total_points'] = Variable<int>(totalPoints.value);
    }
    if (areaEstimate.present) {
      map['area_estimate'] = Variable<double>(areaEstimate.value);
    }
    if (measurementDate.present) {
      map['measurement_date'] = Variable<int>(measurementDate.value);
    }
    if (scanDuration.present) {
      map['scan_duration'] = Variable<int>(scanDuration.value);
    }
    if (deviceInfo.present) {
      map['device_info'] = Variable<String>(deviceInfo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FloorPlansCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('totalPoints: $totalPoints, ')
          ..write('areaEstimate: $areaEstimate, ')
          ..write('measurementDate: $measurementDate, ')
          ..write('scanDuration: $scanDuration, ')
          ..write('deviceInfo: $deviceInfo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FloorPlanPointsTable extends FloorPlanPoints
    with TableInfo<$FloorPlanPointsTable, FloorPlanPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FloorPlanPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _floorPlanIdMeta = const VerificationMeta(
    'floorPlanId',
  );
  @override
  late final GeneratedColumn<String> floorPlanId = GeneratedColumn<String>(
    'floor_plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES floor_plans (id)',
    ),
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMeta = const VerificationMeta(
    'distance',
  );
  @override
  late final GeneratedColumn<double> distance = GeneratedColumn<double>(
    'distance',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _angleMeta = const VerificationMeta('angle');
  @override
  late final GeneratedColumn<double> angle = GeneratedColumn<double>(
    'angle',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signalStrengthMeta = const VerificationMeta(
    'signalStrength',
  );
  @override
  late final GeneratedColumn<double> signalStrength = GeneratedColumn<double>(
    'signal_strength',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _measuredAtMeta = const VerificationMeta(
    'measuredAt',
  );
  @override
  late final GeneratedColumn<int> measuredAt = GeneratedColumn<int>(
    'measured_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pointTypeMeta = const VerificationMeta(
    'pointType',
  );
  @override
  late final GeneratedColumn<String> pointType = GeneratedColumn<String>(
    'point_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    floorPlanId,
    x,
    y,
    distance,
    angle,
    signalStrength,
    measuredAt,
    pointType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'floor_plan_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<FloorPlanPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('floor_plan_id')) {
      context.handle(
        _floorPlanIdMeta,
        floorPlanId.isAcceptableOrUnknown(
          data['floor_plan_id']!,
          _floorPlanIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_floorPlanIdMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('distance')) {
      context.handle(
        _distanceMeta,
        distance.isAcceptableOrUnknown(data['distance']!, _distanceMeta),
      );
    }
    if (data.containsKey('angle')) {
      context.handle(
        _angleMeta,
        angle.isAcceptableOrUnknown(data['angle']!, _angleMeta),
      );
    }
    if (data.containsKey('signal_strength')) {
      context.handle(
        _signalStrengthMeta,
        signalStrength.isAcceptableOrUnknown(
          data['signal_strength']!,
          _signalStrengthMeta,
        ),
      );
    }
    if (data.containsKey('measured_at')) {
      context.handle(
        _measuredAtMeta,
        measuredAt.isAcceptableOrUnknown(data['measured_at']!, _measuredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_measuredAtMeta);
    }
    if (data.containsKey('point_type')) {
      context.handle(
        _pointTypeMeta,
        pointType.isAcceptableOrUnknown(data['point_type']!, _pointTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_pointTypeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FloorPlanPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FloorPlanPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      floorPlanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}floor_plan_id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      distance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance'],
      ),
      angle: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}angle'],
      ),
      signalStrength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}signal_strength'],
      ),
      measuredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}measured_at'],
      )!,
      pointType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}point_type'],
      )!,
    );
  }

  @override
  $FloorPlanPointsTable createAlias(String alias) {
    return $FloorPlanPointsTable(attachedDatabase, alias);
  }
}

class FloorPlanPoint extends DataClass implements Insertable<FloorPlanPoint> {
  final String id;
  final String floorPlanId;
  final double x;
  final double y;
  final double? distance;
  final double? angle;
  final double? signalStrength;
  final int measuredAt;
  final String pointType;
  const FloorPlanPoint({
    required this.id,
    required this.floorPlanId,
    required this.x,
    required this.y,
    this.distance,
    this.angle,
    this.signalStrength,
    required this.measuredAt,
    required this.pointType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['floor_plan_id'] = Variable<String>(floorPlanId);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    if (!nullToAbsent || distance != null) {
      map['distance'] = Variable<double>(distance);
    }
    if (!nullToAbsent || angle != null) {
      map['angle'] = Variable<double>(angle);
    }
    if (!nullToAbsent || signalStrength != null) {
      map['signal_strength'] = Variable<double>(signalStrength);
    }
    map['measured_at'] = Variable<int>(measuredAt);
    map['point_type'] = Variable<String>(pointType);
    return map;
  }

  FloorPlanPointsCompanion toCompanion(bool nullToAbsent) {
    return FloorPlanPointsCompanion(
      id: Value(id),
      floorPlanId: Value(floorPlanId),
      x: Value(x),
      y: Value(y),
      distance: distance == null && nullToAbsent
          ? const Value.absent()
          : Value(distance),
      angle: angle == null && nullToAbsent
          ? const Value.absent()
          : Value(angle),
      signalStrength: signalStrength == null && nullToAbsent
          ? const Value.absent()
          : Value(signalStrength),
      measuredAt: Value(measuredAt),
      pointType: Value(pointType),
    );
  }

  factory FloorPlanPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FloorPlanPoint(
      id: serializer.fromJson<String>(json['id']),
      floorPlanId: serializer.fromJson<String>(json['floorPlanId']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      distance: serializer.fromJson<double?>(json['distance']),
      angle: serializer.fromJson<double?>(json['angle']),
      signalStrength: serializer.fromJson<double?>(json['signalStrength']),
      measuredAt: serializer.fromJson<int>(json['measuredAt']),
      pointType: serializer.fromJson<String>(json['pointType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'floorPlanId': serializer.toJson<String>(floorPlanId),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'distance': serializer.toJson<double?>(distance),
      'angle': serializer.toJson<double?>(angle),
      'signalStrength': serializer.toJson<double?>(signalStrength),
      'measuredAt': serializer.toJson<int>(measuredAt),
      'pointType': serializer.toJson<String>(pointType),
    };
  }

  FloorPlanPoint copyWith({
    String? id,
    String? floorPlanId,
    double? x,
    double? y,
    Value<double?> distance = const Value.absent(),
    Value<double?> angle = const Value.absent(),
    Value<double?> signalStrength = const Value.absent(),
    int? measuredAt,
    String? pointType,
  }) => FloorPlanPoint(
    id: id ?? this.id,
    floorPlanId: floorPlanId ?? this.floorPlanId,
    x: x ?? this.x,
    y: y ?? this.y,
    distance: distance.present ? distance.value : this.distance,
    angle: angle.present ? angle.value : this.angle,
    signalStrength: signalStrength.present
        ? signalStrength.value
        : this.signalStrength,
    measuredAt: measuredAt ?? this.measuredAt,
    pointType: pointType ?? this.pointType,
  );
  FloorPlanPoint copyWithCompanion(FloorPlanPointsCompanion data) {
    return FloorPlanPoint(
      id: data.id.present ? data.id.value : this.id,
      floorPlanId: data.floorPlanId.present
          ? data.floorPlanId.value
          : this.floorPlanId,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      distance: data.distance.present ? data.distance.value : this.distance,
      angle: data.angle.present ? data.angle.value : this.angle,
      signalStrength: data.signalStrength.present
          ? data.signalStrength.value
          : this.signalStrength,
      measuredAt: data.measuredAt.present
          ? data.measuredAt.value
          : this.measuredAt,
      pointType: data.pointType.present ? data.pointType.value : this.pointType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FloorPlanPoint(')
          ..write('id: $id, ')
          ..write('floorPlanId: $floorPlanId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('distance: $distance, ')
          ..write('angle: $angle, ')
          ..write('signalStrength: $signalStrength, ')
          ..write('measuredAt: $measuredAt, ')
          ..write('pointType: $pointType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    floorPlanId,
    x,
    y,
    distance,
    angle,
    signalStrength,
    measuredAt,
    pointType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FloorPlanPoint &&
          other.id == this.id &&
          other.floorPlanId == this.floorPlanId &&
          other.x == this.x &&
          other.y == this.y &&
          other.distance == this.distance &&
          other.angle == this.angle &&
          other.signalStrength == this.signalStrength &&
          other.measuredAt == this.measuredAt &&
          other.pointType == this.pointType);
}

class FloorPlanPointsCompanion extends UpdateCompanion<FloorPlanPoint> {
  final Value<String> id;
  final Value<String> floorPlanId;
  final Value<double> x;
  final Value<double> y;
  final Value<double?> distance;
  final Value<double?> angle;
  final Value<double?> signalStrength;
  final Value<int> measuredAt;
  final Value<String> pointType;
  final Value<int> rowid;
  const FloorPlanPointsCompanion({
    this.id = const Value.absent(),
    this.floorPlanId = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.distance = const Value.absent(),
    this.angle = const Value.absent(),
    this.signalStrength = const Value.absent(),
    this.measuredAt = const Value.absent(),
    this.pointType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FloorPlanPointsCompanion.insert({
    required String id,
    required String floorPlanId,
    required double x,
    required double y,
    this.distance = const Value.absent(),
    this.angle = const Value.absent(),
    this.signalStrength = const Value.absent(),
    required int measuredAt,
    required String pointType,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       floorPlanId = Value(floorPlanId),
       x = Value(x),
       y = Value(y),
       measuredAt = Value(measuredAt),
       pointType = Value(pointType);
  static Insertable<FloorPlanPoint> custom({
    Expression<String>? id,
    Expression<String>? floorPlanId,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? distance,
    Expression<double>? angle,
    Expression<double>? signalStrength,
    Expression<int>? measuredAt,
    Expression<String>? pointType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (floorPlanId != null) 'floor_plan_id': floorPlanId,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (distance != null) 'distance': distance,
      if (angle != null) 'angle': angle,
      if (signalStrength != null) 'signal_strength': signalStrength,
      if (measuredAt != null) 'measured_at': measuredAt,
      if (pointType != null) 'point_type': pointType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FloorPlanPointsCompanion copyWith({
    Value<String>? id,
    Value<String>? floorPlanId,
    Value<double>? x,
    Value<double>? y,
    Value<double?>? distance,
    Value<double?>? angle,
    Value<double?>? signalStrength,
    Value<int>? measuredAt,
    Value<String>? pointType,
    Value<int>? rowid,
  }) {
    return FloorPlanPointsCompanion(
      id: id ?? this.id,
      floorPlanId: floorPlanId ?? this.floorPlanId,
      x: x ?? this.x,
      y: y ?? this.y,
      distance: distance ?? this.distance,
      angle: angle ?? this.angle,
      signalStrength: signalStrength ?? this.signalStrength,
      measuredAt: measuredAt ?? this.measuredAt,
      pointType: pointType ?? this.pointType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (floorPlanId.present) {
      map['floor_plan_id'] = Variable<String>(floorPlanId.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (distance.present) {
      map['distance'] = Variable<double>(distance.value);
    }
    if (angle.present) {
      map['angle'] = Variable<double>(angle.value);
    }
    if (signalStrength.present) {
      map['signal_strength'] = Variable<double>(signalStrength.value);
    }
    if (measuredAt.present) {
      map['measured_at'] = Variable<int>(measuredAt.value);
    }
    if (pointType.present) {
      map['point_type'] = Variable<String>(pointType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FloorPlanPointsCompanion(')
          ..write('id: $id, ')
          ..write('floorPlanId: $floorPlanId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('distance: $distance, ')
          ..write('angle: $angle, ')
          ..write('signalStrength: $signalStrength, ')
          ..write('measuredAt: $measuredAt, ')
          ..write('pointType: $pointType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MeasurementsTable measurements = $MeasurementsTable(this);
  late final $FloorPlansTable floorPlans = $FloorPlansTable(this);
  late final $FloorPlanPointsTable floorPlanPoints = $FloorPlanPointsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    measurements,
    floorPlans,
    floorPlanPoints,
  ];
}

typedef $$MeasurementsTableCreateCompanionBuilder =
    MeasurementsCompanion Function({
      Value<int> id,
      required double x,
      required double y,
      required double distance,
      required double angle,
      required double signalStrength,
      required int timestamp,
    });
typedef $$MeasurementsTableUpdateCompanionBuilder =
    MeasurementsCompanion Function({
      Value<int> id,
      Value<double> x,
      Value<double> y,
      Value<double> distance,
      Value<double> angle,
      Value<double> signalStrength,
      Value<int> timestamp,
    });

class $$MeasurementsTableFilterComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distance => $composableBuilder(
    column: $table.distance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get angle => $composableBuilder(
    column: $table.angle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeasurementsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distance => $composableBuilder(
    column: $table.distance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get angle => $composableBuilder(
    column: $table.angle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeasurementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get distance =>
      $composableBuilder(column: $table.distance, builder: (column) => column);

  GeneratedColumn<double> get angle =>
      $composableBuilder(column: $table.angle, builder: (column) => column);

  GeneratedColumn<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$MeasurementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeasurementsTable,
          Measurement,
          $$MeasurementsTableFilterComposer,
          $$MeasurementsTableOrderingComposer,
          $$MeasurementsTableAnnotationComposer,
          $$MeasurementsTableCreateCompanionBuilder,
          $$MeasurementsTableUpdateCompanionBuilder,
          (
            Measurement,
            BaseReferences<_$AppDatabase, $MeasurementsTable, Measurement>,
          ),
          Measurement,
          PrefetchHooks Function()
        > {
  $$MeasurementsTableTableManager(_$AppDatabase db, $MeasurementsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeasurementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeasurementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeasurementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double> distance = const Value.absent(),
                Value<double> angle = const Value.absent(),
                Value<double> signalStrength = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
              }) => MeasurementsCompanion(
                id: id,
                x: x,
                y: y,
                distance: distance,
                angle: angle,
                signalStrength: signalStrength,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double x,
                required double y,
                required double distance,
                required double angle,
                required double signalStrength,
                required int timestamp,
              }) => MeasurementsCompanion.insert(
                id: id,
                x: x,
                y: y,
                distance: distance,
                angle: angle,
                signalStrength: signalStrength,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeasurementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeasurementsTable,
      Measurement,
      $$MeasurementsTableFilterComposer,
      $$MeasurementsTableOrderingComposer,
      $$MeasurementsTableAnnotationComposer,
      $$MeasurementsTableCreateCompanionBuilder,
      $$MeasurementsTableUpdateCompanionBuilder,
      (
        Measurement,
        BaseReferences<_$AppDatabase, $MeasurementsTable, Measurement>,
      ),
      Measurement,
      PrefetchHooks Function()
    >;
typedef $$FloorPlansTableCreateCompanionBuilder =
    FloorPlansCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      required int createdAt,
      required int updatedAt,
      required int totalPoints,
      required double areaEstimate,
      required int measurementDate,
      Value<int?> scanDuration,
      Value<String?> deviceInfo,
      Value<int> rowid,
    });
typedef $$FloorPlansTableUpdateCompanionBuilder =
    FloorPlansCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> totalPoints,
      Value<double> areaEstimate,
      Value<int> measurementDate,
      Value<int?> scanDuration,
      Value<String?> deviceInfo,
      Value<int> rowid,
    });

final class $$FloorPlansTableReferences
    extends BaseReferences<_$AppDatabase, $FloorPlansTable, FloorPlan> {
  $$FloorPlansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FloorPlanPointsTable, List<FloorPlanPoint>>
  _floorPlanPointsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.floorPlanPoints,
    aliasName: $_aliasNameGenerator(
      db.floorPlans.id,
      db.floorPlanPoints.floorPlanId,
    ),
  );

  $$FloorPlanPointsTableProcessedTableManager get floorPlanPointsRefs {
    final manager = $$FloorPlanPointsTableTableManager(
      $_db,
      $_db.floorPlanPoints,
    ).filter((f) => f.floorPlanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _floorPlanPointsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FloorPlansTableFilterComposer
    extends Composer<_$AppDatabase, $FloorPlansTable> {
  $$FloorPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaEstimate => $composableBuilder(
    column: $table.areaEstimate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get measurementDate => $composableBuilder(
    column: $table.measurementDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scanDuration => $composableBuilder(
    column: $table.scanDuration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> floorPlanPointsRefs(
    Expression<bool> Function($$FloorPlanPointsTableFilterComposer f) f,
  ) {
    final $$FloorPlanPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.floorPlanPoints,
      getReferencedColumn: (t) => t.floorPlanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FloorPlanPointsTableFilterComposer(
            $db: $db,
            $table: $db.floorPlanPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FloorPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $FloorPlansTable> {
  $$FloorPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaEstimate => $composableBuilder(
    column: $table.areaEstimate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get measurementDate => $composableBuilder(
    column: $table.measurementDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scanDuration => $composableBuilder(
    column: $table.scanDuration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FloorPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $FloorPlansTable> {
  $$FloorPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => column,
  );

  GeneratedColumn<double> get areaEstimate => $composableBuilder(
    column: $table.areaEstimate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get measurementDate => $composableBuilder(
    column: $table.measurementDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scanDuration => $composableBuilder(
    column: $table.scanDuration,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => column,
  );

  Expression<T> floorPlanPointsRefs<T extends Object>(
    Expression<T> Function($$FloorPlanPointsTableAnnotationComposer a) f,
  ) {
    final $$FloorPlanPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.floorPlanPoints,
      getReferencedColumn: (t) => t.floorPlanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FloorPlanPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.floorPlanPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FloorPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FloorPlansTable,
          FloorPlan,
          $$FloorPlansTableFilterComposer,
          $$FloorPlansTableOrderingComposer,
          $$FloorPlansTableAnnotationComposer,
          $$FloorPlansTableCreateCompanionBuilder,
          $$FloorPlansTableUpdateCompanionBuilder,
          (FloorPlan, $$FloorPlansTableReferences),
          FloorPlan,
          PrefetchHooks Function({bool floorPlanPointsRefs})
        > {
  $$FloorPlansTableTableManager(_$AppDatabase db, $FloorPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FloorPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FloorPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FloorPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> totalPoints = const Value.absent(),
                Value<double> areaEstimate = const Value.absent(),
                Value<int> measurementDate = const Value.absent(),
                Value<int?> scanDuration = const Value.absent(),
                Value<String?> deviceInfo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FloorPlansCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                totalPoints: totalPoints,
                areaEstimate: areaEstimate,
                measurementDate: measurementDate,
                scanDuration: scanDuration,
                deviceInfo: deviceInfo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                required int totalPoints,
                required double areaEstimate,
                required int measurementDate,
                Value<int?> scanDuration = const Value.absent(),
                Value<String?> deviceInfo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FloorPlansCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                totalPoints: totalPoints,
                areaEstimate: areaEstimate,
                measurementDate: measurementDate,
                scanDuration: scanDuration,
                deviceInfo: deviceInfo,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FloorPlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({floorPlanPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (floorPlanPointsRefs) db.floorPlanPoints,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (floorPlanPointsRefs)
                    await $_getPrefetchedData<
                      FloorPlan,
                      $FloorPlansTable,
                      FloorPlanPoint
                    >(
                      currentTable: table,
                      referencedTable: $$FloorPlansTableReferences
                          ._floorPlanPointsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FloorPlansTableReferences(
                            db,
                            table,
                            p0,
                          ).floorPlanPointsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.floorPlanId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FloorPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FloorPlansTable,
      FloorPlan,
      $$FloorPlansTableFilterComposer,
      $$FloorPlansTableOrderingComposer,
      $$FloorPlansTableAnnotationComposer,
      $$FloorPlansTableCreateCompanionBuilder,
      $$FloorPlansTableUpdateCompanionBuilder,
      (FloorPlan, $$FloorPlansTableReferences),
      FloorPlan,
      PrefetchHooks Function({bool floorPlanPointsRefs})
    >;
typedef $$FloorPlanPointsTableCreateCompanionBuilder =
    FloorPlanPointsCompanion Function({
      required String id,
      required String floorPlanId,
      required double x,
      required double y,
      Value<double?> distance,
      Value<double?> angle,
      Value<double?> signalStrength,
      required int measuredAt,
      required String pointType,
      Value<int> rowid,
    });
typedef $$FloorPlanPointsTableUpdateCompanionBuilder =
    FloorPlanPointsCompanion Function({
      Value<String> id,
      Value<String> floorPlanId,
      Value<double> x,
      Value<double> y,
      Value<double?> distance,
      Value<double?> angle,
      Value<double?> signalStrength,
      Value<int> measuredAt,
      Value<String> pointType,
      Value<int> rowid,
    });

final class $$FloorPlanPointsTableReferences
    extends
        BaseReferences<_$AppDatabase, $FloorPlanPointsTable, FloorPlanPoint> {
  $$FloorPlanPointsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FloorPlansTable _floorPlanIdTable(_$AppDatabase db) =>
      db.floorPlans.createAlias(
        $_aliasNameGenerator(db.floorPlanPoints.floorPlanId, db.floorPlans.id),
      );

  $$FloorPlansTableProcessedTableManager get floorPlanId {
    final $_column = $_itemColumn<String>('floor_plan_id')!;

    final manager = $$FloorPlansTableTableManager(
      $_db,
      $_db.floorPlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_floorPlanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FloorPlanPointsTableFilterComposer
    extends Composer<_$AppDatabase, $FloorPlanPointsTable> {
  $$FloorPlanPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distance => $composableBuilder(
    column: $table.distance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get angle => $composableBuilder(
    column: $table.angle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get measuredAt => $composableBuilder(
    column: $table.measuredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pointType => $composableBuilder(
    column: $table.pointType,
    builder: (column) => ColumnFilters(column),
  );

  $$FloorPlansTableFilterComposer get floorPlanId {
    final $$FloorPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.floorPlanId,
      referencedTable: $db.floorPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FloorPlansTableFilterComposer(
            $db: $db,
            $table: $db.floorPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FloorPlanPointsTableOrderingComposer
    extends Composer<_$AppDatabase, $FloorPlanPointsTable> {
  $$FloorPlanPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distance => $composableBuilder(
    column: $table.distance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get angle => $composableBuilder(
    column: $table.angle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get measuredAt => $composableBuilder(
    column: $table.measuredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pointType => $composableBuilder(
    column: $table.pointType,
    builder: (column) => ColumnOrderings(column),
  );

  $$FloorPlansTableOrderingComposer get floorPlanId {
    final $$FloorPlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.floorPlanId,
      referencedTable: $db.floorPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FloorPlansTableOrderingComposer(
            $db: $db,
            $table: $db.floorPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FloorPlanPointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FloorPlanPointsTable> {
  $$FloorPlanPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get distance =>
      $composableBuilder(column: $table.distance, builder: (column) => column);

  GeneratedColumn<double> get angle =>
      $composableBuilder(column: $table.angle, builder: (column) => column);

  GeneratedColumn<double> get signalStrength => $composableBuilder(
    column: $table.signalStrength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get measuredAt => $composableBuilder(
    column: $table.measuredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pointType =>
      $composableBuilder(column: $table.pointType, builder: (column) => column);

  $$FloorPlansTableAnnotationComposer get floorPlanId {
    final $$FloorPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.floorPlanId,
      referencedTable: $db.floorPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FloorPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.floorPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FloorPlanPointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FloorPlanPointsTable,
          FloorPlanPoint,
          $$FloorPlanPointsTableFilterComposer,
          $$FloorPlanPointsTableOrderingComposer,
          $$FloorPlanPointsTableAnnotationComposer,
          $$FloorPlanPointsTableCreateCompanionBuilder,
          $$FloorPlanPointsTableUpdateCompanionBuilder,
          (FloorPlanPoint, $$FloorPlanPointsTableReferences),
          FloorPlanPoint,
          PrefetchHooks Function({bool floorPlanId})
        > {
  $$FloorPlanPointsTableTableManager(
    _$AppDatabase db,
    $FloorPlanPointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FloorPlanPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FloorPlanPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FloorPlanPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> floorPlanId = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double?> distance = const Value.absent(),
                Value<double?> angle = const Value.absent(),
                Value<double?> signalStrength = const Value.absent(),
                Value<int> measuredAt = const Value.absent(),
                Value<String> pointType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FloorPlanPointsCompanion(
                id: id,
                floorPlanId: floorPlanId,
                x: x,
                y: y,
                distance: distance,
                angle: angle,
                signalStrength: signalStrength,
                measuredAt: measuredAt,
                pointType: pointType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String floorPlanId,
                required double x,
                required double y,
                Value<double?> distance = const Value.absent(),
                Value<double?> angle = const Value.absent(),
                Value<double?> signalStrength = const Value.absent(),
                required int measuredAt,
                required String pointType,
                Value<int> rowid = const Value.absent(),
              }) => FloorPlanPointsCompanion.insert(
                id: id,
                floorPlanId: floorPlanId,
                x: x,
                y: y,
                distance: distance,
                angle: angle,
                signalStrength: signalStrength,
                measuredAt: measuredAt,
                pointType: pointType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FloorPlanPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({floorPlanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (floorPlanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.floorPlanId,
                                referencedTable:
                                    $$FloorPlanPointsTableReferences
                                        ._floorPlanIdTable(db),
                                referencedColumn:
                                    $$FloorPlanPointsTableReferences
                                        ._floorPlanIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FloorPlanPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FloorPlanPointsTable,
      FloorPlanPoint,
      $$FloorPlanPointsTableFilterComposer,
      $$FloorPlanPointsTableOrderingComposer,
      $$FloorPlanPointsTableAnnotationComposer,
      $$FloorPlanPointsTableCreateCompanionBuilder,
      $$FloorPlanPointsTableUpdateCompanionBuilder,
      (FloorPlanPoint, $$FloorPlanPointsTableReferences),
      FloorPlanPoint,
      PrefetchHooks Function({bool floorPlanId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MeasurementsTableTableManager get measurements =>
      $$MeasurementsTableTableManager(_db, _db.measurements);
  $$FloorPlansTableTableManager get floorPlans =>
      $$FloorPlansTableTableManager(_db, _db.floorPlans);
  $$FloorPlanPointsTableTableManager get floorPlanPoints =>
      $$FloorPlanPointsTableTableManager(_db, _db.floorPlanPoints);
}
