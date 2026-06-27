part of '../core.dart';

extension SortedListExtension on List<int> {
  /// 정렬 상태를 유지하며 값을 삽입합니다.
  /// 이미 존재하는 값은 무시합니다.
  void addSorted(int seq) {
    if (isEmpty || seq > last) return add(seq);
    int min = 0, max = length;
    while (min < max) {
      int mid = min + ((max - min) >> 1);
      if (this[mid] == seq) return;
      if (this[mid] < seq) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    insert(min, seq);
  }

  /// 지정된 갯수만큼 역순으로 탐색합니다.
  bool hasHoles({int limit = 20}) {
    if (length < 2) return false;
    final startIndex = length > limit ? length - limit : 0;
    final count = length - startIndex;
    final expected = last - this[startIndex] + 1;
    return expected != count;
  }

  /// 병합 후 정렬합니다.
  List<int> mergeBulk(List<int> bulkData) =>
      {...this, ...bulkData}.toList()..sort();
}
