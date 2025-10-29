import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'src/tmdb_service.dart';

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
  Map<String, dynamic>? _mediaDetails;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  TmdbService? _tmdbService;
  final TextEditingController _urlController = TextEditingController();
  final Set<String> _expandedSections = <String>{};

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
    final readAccessToken = dotenv.env['TMDB_READ_ACCESS_TOKEN'] ?? '';
    _tmdbService = TmdbService(apiKey, readAccessToken: readAccessToken);
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
          _mediaDetails = null;
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
      _mediaDetails = null;
      _pickedImage = null;
    });

    try {
      late final Uint8List imageBytes;
      if (url.startsWith('data:image')) {
        // Handle data URL
        final uri = Uri.parse(url);
        imageBytes = uri.data!.contentAsBytes();
      } else {
        // Handle standard URL
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          throw Exception('Failed to fetch image from URL');
        }
      }
      setState(() {
        _pickedImage = PickedImage(bytes: imageBytes);
        _isLoading = false;
      });
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
      _mediaDetails = null;
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
      if (movieTitle != 'Unknown') {
        await _fetchMediaDetails(movieTitle);
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

  Future<void> _fetchMediaDetails(String movieTitle) async {
    if (_tmdbService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: TMDB service is not available. Please check your API key configuration.')),
        );
      }
      return;
    }
    
    try {
      final searchResult = await _tmdbService!.searchMulti(movieTitle);
      if (searchResult != null) {
        final mediaType = searchResult['media_type'] as String?;
        final id = searchResult['id'] as int?;
        
        if (mediaType != null && id != null) {
          Map<String, dynamic>? enrichedDetails;
          
          if (mediaType == 'movie') {
            enrichedDetails = await _tmdbService!.getMovieDetailsWithExtras(id);
          } else if (mediaType == 'tv') {
            enrichedDetails = await _tmdbService!.getTvDetailsWithExtras(id);
          }
          
          if (enrichedDetails != null) {
            // Add media_type field so the UI knows how to render it
            enrichedDetails['media_type'] = mediaType;
            
            setState(() {
              _mediaDetails = enrichedDetails;
              _expandedSections.clear(); // Reset expansion state for new media
            });
          }
        }
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
                          if (_pickedImage!.bytes != null) {
                            return Image.memory(_pickedImage!.bytes!, fit: BoxFit.contain, width: double.infinity);
                          }
                          if (!kIsWeb && _pickedImage!.file != null) {
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
                  onPressed: _pickedImage != null && !_isLoading && _tmdbService != null ? _identifyMovie : null,
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
                          if (_mediaDetails != null) ...[
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header section (always visible)
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_mediaDetails!['poster_path'] != null)
                                          Image.network(
                                            'https://image.tmdb.org/t/p/w200${_mediaDetails!['poster_path']}',
                                            height: 150,
                                          ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Media type and rating row
                                              Row(
                                                children: [
                                                  if (_mediaDetails!['media_type'] != null)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue[300],
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        _mediaDetails!['media_type'] == 'tv' ? 'TV Show' : 'Movie',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(width: 8),
                                                  if (_mediaDetails!['vote_average'] != null)
                                                    Text(
                                                      '⭐ ${(_mediaDetails!['vote_average'] as num).toStringAsFixed(1)}/10',
                                                      style: TextStyle(
                                                        color: Colors.amber[300],
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              // Year
                                              if (_mediaDetails!['media_type'] == 'tv'
                                                  ? _mediaDetails!['first_air_date'] != null
                                                  : _mediaDetails!['release_date'] != null)
                                                Text('Year: ${(_mediaDetails!['media_type'] == 'tv' ? _mediaDetails!['first_air_date'] : _mediaDetails!['release_date']).split('-')[0]}'),
                                              const SizedBox(height: 8),
                                              // Overview
                                              if (_mediaDetails!['overview'] != null)
                                                Text(
                                                  _mediaDetails!['overview'],
                                                  maxLines: 3,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    const SizedBox(height: 16),
                                    
                                    // Cast Section
                                    if (_mediaDetails!['credits'] != null || _mediaDetails!['aggregate_credits'] != null) ...[
                                      ExpansionTile(
                                        title: Row(
                                          children: [
                                            const Icon(Icons.people, size: 20),
                                            const SizedBox(width: 8),
                                            const Text('Cast'),
                                          ],
                                        ),
                                        initiallyExpanded: _expandedSections.contains('cast'),
                                        onExpansionChanged: (expanded) {
                                          setState(() {
                                            if (expanded) {
                                              _expandedSections.add('cast');
                                            } else {
                                              _expandedSections.remove('cast');
                                            }
                                          });
                                        },
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Builder(
                                              builder: (context) {
                                                // Get cast from either credits (movies) or aggregate_credits (TV)
                                                final castSource = _mediaDetails!['credits']?['cast'] as List? ?? 
                                                                 _mediaDetails!['aggregate_credits']?['cast'] as List? ?? [];
                                                
                                                // Create a mutable copy of the cast list
                                                final cast = List<Map<String, dynamic>>.from(castSource);
                                                
                                                // Sort cast based on media type for top billing
                                                if (_mediaDetails!['media_type'] == 'movie') {
                                                  // For movies, sort by 'order' field (ascending - lower numbers = higher billing)
                                                  cast.sort((a, b) {
                                                    final aOrder = a['order'] as int? ?? 9999;
                                                    final bOrder = b['order'] as int? ?? 9999;
                                                    return aOrder.compareTo(bOrder);
                                                  });
                                                } else {
                                                  // For TV shows, sort by 'total_episode_count' (descending - more episodes = principal presence)
                                                  cast.sort((a, b) {
                                                    final aEpisodes = a['total_episode_count'] as int? ?? 0;
                                                    final bEpisodes = b['total_episode_count'] as int? ?? 0;
                                                    return bEpisodes.compareTo(aEpisodes);
                                                  });
                                                }
                                                
                                                return Column(
                                                  children: cast
                                                      .take(5)
                                                      .map((castMember) {
                                                    final character = castMember['character'] as String? ?? 
                                                       (castMember['roles'] is List && castMember['roles'].isNotEmpty
                                                           ? castMember['roles'][0]['character'] as String?
                                                           : null);
                                                    
                                                    return Padding(
                                                      padding: const EdgeInsets.only(bottom: 12.0),
                                                      child: Row(
                                                        children: [
                                                          if (castMember['profile_path'] != null)
                                                            CircleAvatar(
                                                              radius: 20,
                                                              backgroundImage: NetworkImage(
                                                                'https://image.tmdb.org/t/p/w185${castMember['profile_path']}',
                                                              ),
                                                            ),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  castMember['name'] as String? ?? 'Unknown',
                                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                                ),
                                                                if (character != null)
                                                                  Text(
                                                                    character,
                                                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    
                                    // Genres Section
                                    if (_mediaDetails!['genres'] != null && (_mediaDetails!['genres'] as List).isNotEmpty) ...[
                                      ExpansionTile(
                                        title: Row(
                                          children: [
                                            const Icon(Icons.category, size: 20),
                                            const SizedBox(width: 8),
                                            const Text('Genres'),
                                          ],
                                        ),
                                        initiallyExpanded: _expandedSections.contains('genres'),
                                        onExpansionChanged: (expanded) {
                                          setState(() {
                                            if (expanded) {
                                              _expandedSections.add('genres');
                                            } else {
                                              _expandedSections.remove('genres');
                                            }
                                          });
                                        },
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                ...(_mediaDetails!['genres'] as List).map((genre) {
                                                  return Chip(
                                                    label: Text(genre['name'] as String? ?? 'Unknown'),
                                                    backgroundColor: Colors.blue[100],
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    
                                    // Runtime/Episodes Section
                                    ExpansionTile(
                                      title: Row(
                                        children: [
                                          const Icon(Icons.schedule, size: 20),
                                          const SizedBox(width: 8),
                                          Text(_mediaDetails!['media_type'] == 'tv' ? 'Episodes' : 'Runtime'),
                                        ],
                                      ),
                                      initiallyExpanded: _expandedSections.contains('runtime'),
                                      onExpansionChanged: (expanded) {
                                        setState(() {
                                          if (expanded) {
                                            _expandedSections.add('runtime');
                                          } else {
                                            _expandedSections.remove('runtime');
                                          }
                                        });
                                      },
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (_mediaDetails!['media_type'] == 'tv') ...[
                                                if (_mediaDetails!['number_of_seasons'] != null && _mediaDetails!['number_of_episodes'] != null)
                                                  Text('${_mediaDetails!['number_of_seasons']} Seasons, ${_mediaDetails!['number_of_episodes']} Episodes'),
                                                if (_mediaDetails!['episode_run_time'] != null &&
                                                    (_mediaDetails!['episode_run_time'] as List).isNotEmpty)
                                                  Text('~${_mediaDetails!['episode_run_time'][0]} min per episode'),
                                              ] else ...[
                                                if (_mediaDetails!['runtime'] != null)
                                                  Text('${_mediaDetails!['runtime']} minutes'),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    // Trailer Section
                                    if (_tmdbService != null && _tmdbService!.getTrailerUrl(_mediaDetails) != null) ...[
                                      ExpansionTile(
                                        title: Row(
                                          children: [
                                            const Icon(Icons.play_circle_outline, size: 20),
                                            const SizedBox(width: 8),
                                            const Text('Trailer'),
                                          ],
                                        ),
                                        initiallyExpanded: _expandedSections.contains('trailer'),
                                        onExpansionChanged: (expanded) {
                                          setState(() {
                                            if (expanded) {
                                              _expandedSections.add('trailer');
                                            } else {
                                              _expandedSections.remove('trailer');
                                            }
                                          });
                                        },
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    final trailerUrl = _tmdbService!.getTrailerUrl(_mediaDetails);
                                                    if (trailerUrl != null) {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text('Trailer'),
                                                          content: Text('YouTube URL: $trailerUrl'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.of(context).pop(),
                                                              child: const Text('Close'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  child: const Text(
                                                    'Watch Trailer on YouTube',
                                                    style: TextStyle(
                                                      color: Colors.blue,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                ),
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
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Tip: Upload a clear movie or TV show poster or still for best results. Tap sections to expand and see more details.',
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
