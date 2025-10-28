import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedImage {
  final Uint8List? bytes;

  PickedImage({this.bytes});
}

Future<PickedImage?> pickImagePlatform(ImagePicker picker) async {
  final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  return PickedImage(bytes: bytes);
}
