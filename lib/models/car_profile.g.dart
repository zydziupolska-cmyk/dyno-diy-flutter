// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'car_profile.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCarProfileCollection on Isar {
  IsarCollection<CarProfile> get carProfiles => this.collection();
}

const CarProfileSchema = CollectionSchema(
  name: r'CarProfile',
  id: 3821464849962606029,
  properties: {
    r'area': PropertySchema(
      id: 0,
      name: r'area',
      type: IsarType.double,
    ),
    r'cd': PropertySchema(
      id: 1,
      name: r'cd',
      type: IsarType.double,
    ),
    r'licensePlate': PropertySchema(
      id: 2,
      name: r'licensePlate',
      type: IsarType.string,
    ),
    r'lossDrivetrain': PropertySchema(
      id: 3,
      name: r'lossDrivetrain',
      type: IsarType.double,
    ),
    r'name': PropertySchema(
      id: 4,
      name: r'name',
      type: IsarType.string,
    ),
    r'transmission': PropertySchema(
      id: 5,
      name: r'transmission',
      type: IsarType.byte,
      enumMap: _CarProfiletransmissionEnumValueMap,
    ),
    r'weightKg': PropertySchema(
      id: 6,
      name: r'weightKg',
      type: IsarType.double,
    )
  },
  estimateSize: _carProfileEstimateSize,
  serialize: _carProfileSerialize,
  deserialize: _carProfileDeserialize,
  deserializeProp: _carProfileDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _carProfileGetId,
  getLinks: _carProfileGetLinks,
  attach: _carProfileAttach,
  version: '3.1.0+1',
);

int _carProfileEstimateSize(
  CarProfile object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.licensePlate;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _carProfileSerialize(
  CarProfile object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.area);
  writer.writeDouble(offsets[1], object.cd);
  writer.writeString(offsets[2], object.licensePlate);
  writer.writeDouble(offsets[3], object.lossDrivetrain);
  writer.writeString(offsets[4], object.name);
  writer.writeByte(offsets[5], object.transmission.index);
  writer.writeDouble(offsets[6], object.weightKg);
}

CarProfile _carProfileDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CarProfile(
    area: reader.readDouble(offsets[0]),
    cd: reader.readDouble(offsets[1]),
    licensePlate: reader.readStringOrNull(offsets[2]),
    lossDrivetrain: reader.readDouble(offsets[3]),
    name: reader.readString(offsets[4]),
    transmission: _CarProfiletransmissionValueEnumMap[
            reader.readByteOrNull(offsets[5])] ??
        TransmissionType.manual,
    weightKg: reader.readDouble(offsets[6]),
  );
  object.id = id;
  return object;
}

P _carProfileDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDouble(offset)) as P;
    case 1:
      return (reader.readDouble(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readDouble(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (_CarProfiletransmissionValueEnumMap[
              reader.readByteOrNull(offset)] ??
          TransmissionType.manual) as P;
    case 6:
      return (reader.readDouble(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _CarProfiletransmissionEnumValueMap = {
  'manual': 0,
  'automatic': 1,
  'awdManual': 2,
  'awdAutomatic': 3,
};
const _CarProfiletransmissionValueEnumMap = {
  0: TransmissionType.manual,
  1: TransmissionType.automatic,
  2: TransmissionType.awdManual,
  3: TransmissionType.awdAutomatic,
};

Id _carProfileGetId(CarProfile object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _carProfileGetLinks(CarProfile object) {
  return [];
}

void _carProfileAttach(IsarCollection<dynamic> col, Id id, CarProfile object) {
  object.id = id;
}

extension CarProfileQueryWhereSort
    on QueryBuilder<CarProfile, CarProfile, QWhere> {
  QueryBuilder<CarProfile, CarProfile, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CarProfileQueryWhere
    on QueryBuilder<CarProfile, CarProfile, QWhereClause> {
  QueryBuilder<CarProfile, CarProfile, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CarProfileQueryFilter
    on QueryBuilder<CarProfile, CarProfile, QFilterCondition> {
  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> areaEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> areaGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> areaLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> areaBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'area',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> cdEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cd',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> cdGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cd',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> cdLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cd',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> cdBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cd',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'licensePlate',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'licensePlate',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'licensePlate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'licensePlate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'licensePlate',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'licensePlate',
        value: '',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      licensePlateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'licensePlate',
        value: '',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      lossDrivetrainEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lossDrivetrain',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      lossDrivetrainGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lossDrivetrain',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      lossDrivetrainLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lossDrivetrain',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      lossDrivetrainBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lossDrivetrain',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      transmissionEqualTo(TransmissionType value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'transmission',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      transmissionGreaterThan(
    TransmissionType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'transmission',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      transmissionLessThan(
    TransmissionType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'transmission',
        value: value,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      transmissionBetween(
    TransmissionType lower,
    TransmissionType upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'transmission',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> weightKgEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'weightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition>
      weightKgGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'weightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> weightKgLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'weightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterFilterCondition> weightKgBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'weightKg',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension CarProfileQueryObject
    on QueryBuilder<CarProfile, CarProfile, QFilterCondition> {}

extension CarProfileQueryLinks
    on QueryBuilder<CarProfile, CarProfile, QFilterCondition> {}

extension CarProfileQuerySortBy
    on QueryBuilder<CarProfile, CarProfile, QSortBy> {
  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByAreaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByCd() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cd', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByCdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cd', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByLicensePlate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'licensePlate', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByLicensePlateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'licensePlate', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByLossDrivetrain() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lossDrivetrain', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy>
      sortByLossDrivetrainDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lossDrivetrain', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByTransmission() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transmission', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByTransmissionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transmission', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weightKg', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> sortByWeightKgDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weightKg', Sort.desc);
    });
  }
}

extension CarProfileQuerySortThenBy
    on QueryBuilder<CarProfile, CarProfile, QSortThenBy> {
  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByAreaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByCd() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cd', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByCdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cd', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByLicensePlate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'licensePlate', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByLicensePlateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'licensePlate', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByLossDrivetrain() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lossDrivetrain', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy>
      thenByLossDrivetrainDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lossDrivetrain', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByTransmission() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transmission', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByTransmissionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transmission', Sort.desc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weightKg', Sort.asc);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QAfterSortBy> thenByWeightKgDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weightKg', Sort.desc);
    });
  }
}

extension CarProfileQueryWhereDistinct
    on QueryBuilder<CarProfile, CarProfile, QDistinct> {
  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'area');
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByCd() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cd');
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByLicensePlate(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'licensePlate', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByLossDrivetrain() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lossDrivetrain');
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByTransmission() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'transmission');
    });
  }

  QueryBuilder<CarProfile, CarProfile, QDistinct> distinctByWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'weightKg');
    });
  }
}

extension CarProfileQueryProperty
    on QueryBuilder<CarProfile, CarProfile, QQueryProperty> {
  QueryBuilder<CarProfile, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CarProfile, double, QQueryOperations> areaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'area');
    });
  }

  QueryBuilder<CarProfile, double, QQueryOperations> cdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cd');
    });
  }

  QueryBuilder<CarProfile, String?, QQueryOperations> licensePlateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'licensePlate');
    });
  }

  QueryBuilder<CarProfile, double, QQueryOperations> lossDrivetrainProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lossDrivetrain');
    });
  }

  QueryBuilder<CarProfile, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<CarProfile, TransmissionType, QQueryOperations>
      transmissionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'transmission');
    });
  }

  QueryBuilder<CarProfile, double, QQueryOperations> weightKgProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'weightKg');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDynoRunCollection on Isar {
  IsarCollection<DynoRun> get dynoRuns => this.collection();
}

const DynoRunSchema = CollectionSchema(
  name: r'DynoRun',
  id: -4938675503904493176,
  properties: {
    r'carId': PropertySchema(
      id: 0,
      name: r'carId',
      type: IsarType.long,
    ),
    r'correctionFactor': PropertySchema(
      id: 1,
      name: r'correctionFactor',
      type: IsarType.double,
    ),
    r'graphDataPoints': PropertySchema(
      id: 2,
      name: r'graphDataPoints',
      type: IsarType.stringList,
    ),
    r'maxEngineHp': PropertySchema(
      id: 3,
      name: r'maxEngineHp',
      type: IsarType.double,
    ),
    r'maxEngineTorque': PropertySchema(
      id: 4,
      name: r'maxEngineTorque',
      type: IsarType.double,
    ),
    r'sessionWeightKg': PropertySchema(
      id: 5,
      name: r'sessionWeightKg',
      type: IsarType.double,
    ),
    r'timestamp': PropertySchema(
      id: 6,
      name: r'timestamp',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _dynoRunEstimateSize,
  serialize: _dynoRunSerialize,
  deserialize: _dynoRunDeserialize,
  deserializeProp: _dynoRunDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _dynoRunGetId,
  getLinks: _dynoRunGetLinks,
  attach: _dynoRunAttach,
  version: '3.1.0+1',
);

int _dynoRunEstimateSize(
  DynoRun object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.graphDataPoints.length * 3;
  {
    for (var i = 0; i < object.graphDataPoints.length; i++) {
      final value = object.graphDataPoints[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _dynoRunSerialize(
  DynoRun object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.carId);
  writer.writeDouble(offsets[1], object.correctionFactor);
  writer.writeStringList(offsets[2], object.graphDataPoints);
  writer.writeDouble(offsets[3], object.maxEngineHp);
  writer.writeDouble(offsets[4], object.maxEngineTorque);
  writer.writeDouble(offsets[5], object.sessionWeightKg);
  writer.writeDateTime(offsets[6], object.timestamp);
}

DynoRun _dynoRunDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DynoRun(
    carId: reader.readLong(offsets[0]),
    correctionFactor: reader.readDouble(offsets[1]),
    graphDataPoints: reader.readStringList(offsets[2]) ?? [],
    maxEngineHp: reader.readDouble(offsets[3]),
    maxEngineTorque: reader.readDouble(offsets[4]),
    sessionWeightKg: reader.readDouble(offsets[5]),
    timestamp: reader.readDateTime(offsets[6]),
  );
  object.id = id;
  return object;
}

P _dynoRunDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDouble(offset)) as P;
    case 2:
      return (reader.readStringList(offset) ?? []) as P;
    case 3:
      return (reader.readDouble(offset)) as P;
    case 4:
      return (reader.readDouble(offset)) as P;
    case 5:
      return (reader.readDouble(offset)) as P;
    case 6:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _dynoRunGetId(DynoRun object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _dynoRunGetLinks(DynoRun object) {
  return [];
}

void _dynoRunAttach(IsarCollection<dynamic> col, Id id, DynoRun object) {
  object.id = id;
}

extension DynoRunQueryWhereSort on QueryBuilder<DynoRun, DynoRun, QWhere> {
  QueryBuilder<DynoRun, DynoRun, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension DynoRunQueryWhere on QueryBuilder<DynoRun, DynoRun, QWhereClause> {
  QueryBuilder<DynoRun, DynoRun, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension DynoRunQueryFilter
    on QueryBuilder<DynoRun, DynoRun, QFilterCondition> {
  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> carIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'carId',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> carIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'carId',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> carIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'carId',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> carIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'carId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> correctionFactorEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'correctionFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      correctionFactorGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'correctionFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      correctionFactorLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'correctionFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> correctionFactorBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'correctionFactor',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'graphDataPoints',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'graphDataPoints',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'graphDataPoints',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'graphDataPoints',
        value: '',
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'graphDataPoints',
        value: '',
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      graphDataPointsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'graphDataPoints',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineHpEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'maxEngineHp',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineHpGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'maxEngineHp',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineHpLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'maxEngineHp',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineHpBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'maxEngineHp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineTorqueEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'maxEngineTorque',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      maxEngineTorqueGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'maxEngineTorque',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineTorqueLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'maxEngineTorque',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> maxEngineTorqueBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'maxEngineTorque',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> sessionWeightKgEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionWeightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition>
      sessionWeightKgGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionWeightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> sessionWeightKgLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionWeightKg',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> sessionWeightKgBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionWeightKg',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> timestampEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterFilterCondition> timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension DynoRunQueryObject
    on QueryBuilder<DynoRun, DynoRun, QFilterCondition> {}

extension DynoRunQueryLinks
    on QueryBuilder<DynoRun, DynoRun, QFilterCondition> {}

extension DynoRunQuerySortBy on QueryBuilder<DynoRun, DynoRun, QSortBy> {
  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByCarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carId', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByCarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carId', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByCorrectionFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'correctionFactor', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByCorrectionFactorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'correctionFactor', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByMaxEngineHp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineHp', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByMaxEngineHpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineHp', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByMaxEngineTorque() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineTorque', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByMaxEngineTorqueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineTorque', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortBySessionWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionWeightKg', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortBySessionWeightKgDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionWeightKg', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension DynoRunQuerySortThenBy
    on QueryBuilder<DynoRun, DynoRun, QSortThenBy> {
  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByCarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carId', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByCarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carId', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByCorrectionFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'correctionFactor', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByCorrectionFactorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'correctionFactor', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByMaxEngineHp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineHp', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByMaxEngineHpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineHp', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByMaxEngineTorque() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineTorque', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByMaxEngineTorqueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxEngineTorque', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenBySessionWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionWeightKg', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenBySessionWeightKgDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionWeightKg', Sort.desc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<DynoRun, DynoRun, QAfterSortBy> thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension DynoRunQueryWhereDistinct
    on QueryBuilder<DynoRun, DynoRun, QDistinct> {
  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByCarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'carId');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByCorrectionFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'correctionFactor');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByGraphDataPoints() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'graphDataPoints');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByMaxEngineHp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxEngineHp');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByMaxEngineTorque() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxEngineTorque');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctBySessionWeightKg() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionWeightKg');
    });
  }

  QueryBuilder<DynoRun, DynoRun, QDistinct> distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }
}

extension DynoRunQueryProperty
    on QueryBuilder<DynoRun, DynoRun, QQueryProperty> {
  QueryBuilder<DynoRun, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DynoRun, int, QQueryOperations> carIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'carId');
    });
  }

  QueryBuilder<DynoRun, double, QQueryOperations> correctionFactorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'correctionFactor');
    });
  }

  QueryBuilder<DynoRun, List<String>, QQueryOperations>
      graphDataPointsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'graphDataPoints');
    });
  }

  QueryBuilder<DynoRun, double, QQueryOperations> maxEngineHpProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxEngineHp');
    });
  }

  QueryBuilder<DynoRun, double, QQueryOperations> maxEngineTorqueProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxEngineTorque');
    });
  }

  QueryBuilder<DynoRun, double, QQueryOperations> sessionWeightKgProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionWeightKg');
    });
  }

  QueryBuilder<DynoRun, DateTime, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }
}
