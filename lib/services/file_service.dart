import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod/riverpod.dart';

abstract class FileService {
  Future<void> saveFile(XFile file);
  Future<List<XFile>> getFiles();
  Future<void> saveFilesToExternalStorage();
}

class FileServiceImpl implements FileService {
  factory FileServiceImpl() => _instance;

  FileServiceImpl._internal();

  static final FileServiceImpl _instance = FileServiceImpl._internal();

  @override
  Future<void> saveFile(XFile file) async {
    try {
      // Create directory to save images if not exists
      final directory = await getApplicationDocumentsDirectory();
      final String folder = '${directory.path}/random_captures';
      await Directory(folder).create(recursive: true);

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String filename = '$folder/capture_$timestamp.jpg';

      // Save image
      final File savedFile = File(filename);
      await savedFile.writeAsBytes(await file.readAsBytes());
    } catch (e) {
      print('Error capturing image: $e');
    }
  }

  @override
  Future<List<XFile>> getFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final String folder = '${directory.path}/random_captures';

    // Create directory if not exists
    final dir = Directory(folder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // List files
    List<FileSystemEntity> files = dir.listSync();
    files.sort((a, b) => b.path.compareTo(a.path)); // Sort by newest

    List<XFile> xfiles =
        files.where((f) => f.existsSync()).map((f) => XFile(f.path)).toList();

    print("all files");
    print('files:');
    for (final f in xfiles) {
      print('${f.name}.${f.mimeType}');
    }

    return xfiles;
  }

  @override
  Future<void> saveFilesToExternalStorage() async {
    try {
      String? userSelectedDirectory =
          await FilePicker.platform.getDirectoryPath();

      if (userSelectedDirectory == null) {
        return;
      }
      final filesToSave = await getFiles();
      for (XFile xfile in filesToSave) {
        final fileName = xfile.path.split('/').last;
        final destinationPath = '$userSelectedDirectory/$fileName';
        final bytes = await xfile.readAsBytes();
        final destinationFile = File(destinationPath);
        await destinationFile.writeAsBytes(bytes);
      }
    } catch (e) {
      rethrow;
    }
  }
}

final fileServiceProvider = Provider<FileService>((ref) {
  return FileServiceImpl();
});
