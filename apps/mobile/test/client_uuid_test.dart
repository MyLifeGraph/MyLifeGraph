import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/utils/client_uuid.dart';

void main() {
  test('client request ids stay V4 while source ids accept canonical UUIDs',
      () {
    const requestId = 'f5000000-0000-4000-8000-000000000001';
    const deterministicBlockId = '13aaa242-f488-5a02-a636-52f0b8c1ceba';

    expect(isClientUuid(requestId), isTrue);
    expect(isCanonicalUuid(requestId), isTrue);
    expect(isClientUuid(deterministicBlockId), isFalse);
    expect(isCanonicalUuid(deterministicBlockId), isTrue);
    expect(isCanonicalUuid('13AAA242-F488-5A02-A636-52F0B8C1CEBA'), isFalse);
    expect(isCanonicalUuid('not-a-uuid'), isFalse);
  });
}
