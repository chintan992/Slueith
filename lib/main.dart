import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// Conditional import: use the IO implementation on non-web, and the web
// implementation when compiling to the web to avoid importing `dart:io`.
import 'src/image_io_io.dart' if (dart.library.html) 'src/image_io_web.dart';
import 'src/image_processing.dart';
import 'src/mistral_api_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slueith - Movie Identifier',
      theme: ThemeData.dark(useMaterial3: true),
      home: const MyHomePage(title: 'Movie Identifier'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  PickedImage? _pickedImage;
  String? _resultTitle;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final PickedImage? picked = await pickImagePlatform(_picker);
      if (picked != null) {
        // If a new image is selected while loading, reset loading to avoid confusion.
        setState(() {
          _isLoading = false;
          _pickedImage = picked;
          _resultTitle = null; // clear previous result
        });
      }
    } catch (e) {
      // Simple error handling: show a SnackBar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _identifyMovie() async {
    setState(() {
      _isLoading = true;
      _resultTitle = null;
    });

    try {
      // Validate image availability and handle fallback to file
      late final Uint8List imageBytes;
      if (_pickedImage?.bytes != null) {
        imageBytes = _pickedImage!.bytes!;
      } else if (!kIsWeb && _pickedImage?.file != null) {
        // Fall back to reading bytes from file on non-web platforms
        try {
          imageBytes = await _pickedImage!.file!.readAsBytes();
        } catch (e) {
          setState(() {
            _isLoading = false;
            _resultTitle = 'Error: Failed to read image file';
          });
          return;
        }
      } else {
        setState(() {
          _isLoading = false;
          _resultTitle = 'Error: No image data available';
        });
        return;
      }

      // Process the image in a background isolate
      final base64Image = await compute(processImageToBase64Sync, imageBytes);
      if (base64Image == null) {
        setState(() {
          _isLoading = false;
          _resultTitle = 'Error: Failed to process image';
        });
        return;
      }

      // Call the Mistral API to identify the movie
      final movieTitle = await identifyMovieFromImage(base64Image);
      setState(() {
        _isLoading = false;
        _resultTitle = movieTitle;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultTitle = 'Error: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickImage,
                  icon: const Icon(Icons.upload_file),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('Upload File', style: TextStyle(fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 16),

                if (_pickedImage != null) ...[
                  SizedBox(
                    height: 300,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Builder(builder: (context) {
                          // Prefer bytes for web preview; Image.memory works across
                          // platforms when bytes are available. For mobile prefer
                          // Image.file when a File is present to avoid extra memory copy.
                          if (kIsWeb || _pickedImage!.bytes != null) {
                            final bytes = _pickedImage!.bytes;
                            if (bytes != null) {
                              return Image.memory(bytes, fit: BoxFit.contain, width: double.infinity);
                            }
                          }
                          // Fallback to File when available (non-web platforms)
                          if (_pickedImage!.file != null) {
                            return Image.file(_pickedImage!.file!, fit: BoxFit.contain, width: double.infinity);
                          }
                          return const Center(child: Text('Unable to preview image', style: TextStyle(color: Colors.white60)));
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Center(
                      child: Text('No image selected', style: TextStyle(color: Colors.white60)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                ElevatedButton.icon(
                  onPressed: _pickedImage != null && !_isLoading ? _identifyMovie : null,
                  icon: const Icon(Icons.search),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.0),
                    child: Text('Identify Movie', style: TextStyle(fontSize: 16)),
                  ),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 0)),
                ),

                if (_isLoading) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],

                if (_resultTitle != null) ...[
                  const SizedBox(height: 24),
                  Card(
                    color: Theme.of(context).cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            _resultTitle == 'Unknown' ? 'Sorry, couldn\'t find a title for that one!' : _resultTitle!,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Tip: Upload a clear movie poster or still for best results. Identification integration will be added in the next phase.',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
