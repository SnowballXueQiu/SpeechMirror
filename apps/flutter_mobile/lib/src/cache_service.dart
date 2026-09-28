import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CacheService {
  CacheService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<int> sizeBytes() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // A temporary file may disappear while the size is calculated.
        }
      }
    }
    return total;
  }

  Future<void> clear() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // Files still used by the recorder are left in place.
      }
    }
  }
}

String formatCacheSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
