import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Processes an image by resizing (if needed), compressing to JPEG, and converting to base64.
///
/// Takes raw image bytes as input and returns a base64 encoded string of the processed image.
/// The image is resized to a maximum dimension of 1024 pixels while maintaining aspect ratio,
/// then compressed to JPEG format with 85% quality for optimal file size.
///
/// Parameters:
///   - imageBytes: Raw image data as Uint8List
///
/// Returns:
///   - String?: Base64 encoded string of the processed image, or null if processing fails
///
/// Example:
/// ```dart
/// final processedImage = await processImageToBase64(rawImageBytes);
/// if (processedImage != null) {
///   // Use the base64 string...
/// }
/// ```
Future<String?> processImageToBase64(Uint8List imageBytes) async {
  try {
    // Decode the image
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    // Calculate resize dimensions if needed
    final width = image.width;
    final height = image.height;
    final longestSide = width > height ? width : height;
    
    late final img.Image processedImage;
    if (longestSide > 1024) {
      // Calculate new dimensions maintaining aspect ratio
      final scaleFactor = 1024 / longestSide;
      final newWidth = (width * scaleFactor).round();
      final newHeight = (height * scaleFactor).round();
      
      // Resize the image
      processedImage = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    } else {
      processedImage = image;
    }

    // Encode to JPEG with compression
    final jpegBytes = img.encodeJpg(processedImage, quality: 85);

    // Convert to base64
    return base64Encode(jpegBytes);
  } catch (e) {
    return null;
  }
}

/// Synchronous version of [processImageToBase64].
///
/// Use this version if you plan to run the processing in an isolate using compute().
/// Has the same functionality as the async version but runs synchronously.
String? processImageToBase64Sync(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final width = image.width;
    final height = image.height;
    final longestSide = width > height ? width : height;
    
    late final img.Image processedImage;
    if (longestSide > 1024) {
      final scaleFactor = 1024 / longestSide;
      final newWidth = (width * scaleFactor).round();
      final newHeight = (height * scaleFactor).round();
      
      processedImage = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    } else {
      processedImage = image;
    }

    final jpegBytes = img.encodeJpg(processedImage, quality: 85);
    return base64Encode(jpegBytes);
  } catch (e) {
    return null;
  }
}