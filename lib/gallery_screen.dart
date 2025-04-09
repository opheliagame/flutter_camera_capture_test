import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_camera_capture_test/services/file_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GalleryPage extends ConsumerWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(galleryStateNotifierProvider);

    return state.when(
      data: (data) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Captured Images'),
            actions: [
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: () {
                  ref.read(fileServiceProvider).saveFilesToExternalStorage();
                },
              ),
            ],
          ),
          body: data.isEmpty
              ? const Center(child: Text('No images captured yet'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final file = data[index];

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullImageView(
                              imagePath: file.path,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(file.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
        );
      },
      error: (error, stackTrace) => Text(error.toString()),
      loading: () => const CircularProgressIndicator(),
    );
  }
}

class FullImageView extends StatelessWidget {
  final String imagePath;

  const FullImageView({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    // Extract timestamp from filename
    final filename = imagePath.split('/').last;
    final timestamp = filename.split('_').last.split('.').first;
    final date = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    final formattedDate =
        '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}:${date.second}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final file = File(imagePath);
              await file.delete();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Add share functionality
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Captured on: $formattedDate',
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GalleryScreenNotifier extends StateNotifier<AsyncValue<List<XFile>>> {
  GalleryScreenNotifier({required this.fileService})
      : super(const AsyncLoading()) {
    load();
  }

  final FileService fileService;

  Future<void> load() async {
    try {
      final files = await fileService.getFiles();
      state = AsyncData(files);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final galleryStateNotifierProvider = StateNotifierProvider.autoDispose<
    GalleryScreenNotifier, AsyncValue<List<XFile>>>((ref) {
  final fileService = ref.read(fileServiceProvider);
  return GalleryScreenNotifier(fileService: fileService);
});
