import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedImage {
  final File? file;
  final Uint8List? bytes;

  PickedImage({this.file, this.bytes});
}

Future<PickedImage?> pickImagePlatform(ImagePicker picker) async {
  final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  return PickedImage(file: File(picked.path), bytes: bytes);
}
