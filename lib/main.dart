import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tmdb_api/tmdb_api.dart';

// Conditional import: use the IO implementation on non-web, and the web
// implementation when compiling to the web to avoid importing `dart:io`.
import 'src/image_io_io.dart' if (dart.library.html) 'src/image_io_web.dart';
import 'src/image_processing.dart';
import 'src/mistral_api_service.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  Map? _movieDetails;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  late final TMDB tmdb;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['TMDB_API_KEY'];
    if (apiKey == null) {
      // Handle the case where the API key is not found
      // You might want to show an error or disable the feature
      if (kDebugMode) {
        print('TMDB_API_KEY not found in .env file');
      }
      return;
    }
    tmdb = TMDB(
      ApiKeys(apiKey, 'apiReadAccessTokenv4'),
      logConfig: const ConfigLogger(showLogs: true, showErrorLogs: true),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final PickedImage? picked = await pickImagePlatform(_picker);
      if (picked != null) {
        // If a new image is selected while loading, reset loading to avoid confusion.
        setState(() {
          _isLoading = false;
          _pickedImage = picked;
          _resultTitle = null; // clear previous result
          _movieDetails = null;
          _urlController.clear();
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

  Future<void> _fetchImageFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _resultTitle = null;
      _movieDetails = null;
      _pickedImage = null;
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final imageBytes = response.bodyBytes;
        setState(() {
          _pickedImage = PickedImage(bytes: imageBytes);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _resultTitle = 'Error: Failed to fetch image from URL';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultTitle = 'Error fetching image: $e';
      });
    }
  }

  Future<void> _identifyMovie() async {
    setState(() {
      _isLoading = true;
      _resultTitle = null;
      _movieDetails = null;
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
        _resultTitle = movieTitle;
      });
      if (movieTitle != null && movieTitle != 'Unknown') {
        await _fetchMovieDetails(movieTitle);
      }
      setState(() {
        _isLoading = false;
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

  Future<void> _fetchMovieDetails(String movieTitle) async {
    try {
      final searchResult = await tmdb.v3.search.queryMovies(movieTitle);
      if (searchResult['results'].isNotEmpty) {
        setState(() {
          _movieDetails = searchResult['results'][0];
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  void _shareResult() {
    if (_resultTitle != null && _resultTitle != 'Unknown') {
      Share.share('I found this movie: $_resultTitle');
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
                const Text(
                  'Or enter an image URL:',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/image.jpg',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchImageFromUrl,
                  child: const Text('Fetch Image from URL'),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.share),
                                onPressed: _shareResult,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _resultTitle == 'Unknown' ? 'Sorry, couldn\'t find a title for that one!' : _resultTitle!,
                            style: const TextStyle(fontSize: 18),
                          ),
                          if (_movieDetails != null) ...[
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_movieDetails!['poster_path'] != null)
                                  Image.network(
                                    'https://image.tmdb.org/t/p/w200${_movieDetails!['poster_path']}',
                                    height: 150,
                                  ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_movieDetails!['release_date'] != null)
                                        Text('Year: ${_movieDetails!['release_date'].split('-')[0]}'),
                                      const SizedBox(height: 8),
                                      if (_movieDetails!['overview'] != null)
                                        Text(_movieDetails!['overview'], maxLines: 5, overflow: TextOverflow.ellipsis,),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
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
