import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ephemera_ai/config.dart';

typedef PickedPhoto = ({Uint8List bytes, String filename});

/// Asks camera vs gallery, then returns the photo re-encoded to at most
/// [maxCaptureSide] px, or null if the user cancels.
Future<PickedPhoto?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Lay your scraps flat on a plain surface, in good light. '
              'The camera gives sharper scraps than photos saved from chats.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: maxCaptureSide,
    maxHeight: maxCaptureSide,
    imageQuality: captureJpegQuality,
  );
  if (picked == null) return null;
  return (bytes: await picked.readAsBytes(), filename: picked.name);
}
