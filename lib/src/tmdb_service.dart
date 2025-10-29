import 'package:flutter/foundation.dart';
import 'package:tmdb_api/tmdb_api.dart';

/// Service class that encapsulates all TMDB API operations.
/// Provides clean methods for movie and TV show operations while managing the TMDB client internally.
class TmdbService {
  final TMDB _tmdb;

  /// Constructor that accepts the API key and initializes the TMDB client.
  ///
  /// The [apiKey] is the TMDB API key from the .env file.
  /// The [readAccessToken] is the optional TMDB v4 read access token.
  TmdbService(String apiKey, {String readAccessToken = ''})
      : _tmdb = TMDB(
          ApiKeys(apiKey, readAccessToken),
          logConfig: const ConfigLogger(
            showLogs: true,
            showErrorLogs: true,
          ),
        );

  /// Searches for movies by title.
  /// 
  /// Returns the first search result or null if no results are found or an error occurs.
  /// The result contains movie details including poster path, release date, overview, etc.
  Future<Map<String, dynamic>?> searchMovie(String title) async {
    try {
      final searchResult = await _tmdb.v3.search.queryMovies(title);
      if (searchResult['results'] != null && 
          (searchResult['results'] as List).isNotEmpty) {
        return (searchResult['results'] as List).first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching for movie "$title": $e');
      }
      return null;
    }
  }

  /// Searches for TV shows by title.
  /// 
  /// Returns the first search result or null if no results are found or an error occurs.
  /// The result contains TV show details including poster path, first air date, overview, etc.
  Future<Map<String, dynamic>?> searchTvShow(String title) async {
    try {
      final searchResult = await _tmdb.v3.search.queryTvShows(title);
      if (searchResult['results'] != null && 
          (searchResult['results'] as List).isNotEmpty) {
        return (searchResult['results'] as List).first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching for TV show "$title": $e');
      }
      return null;
    }
  }

  /// Searches for both movies and TV shows simultaneously.
  ///
  /// Returns the first search result or null if no results are found or an error occurs.
  /// The result contains a `media_type` field with values 'movie' or 'tv' to distinguish content types.
  /// For TV shows, use the `name` field instead of `title` and `first_air_date` instead of `release_date`.
  Future<Map<String, dynamic>?> searchMulti(String query) async {
    try {
      final searchResult = await _tmdb.v3.search.queryMulti(query);
      if (searchResult['results'] != null &&
          (searchResult['results'] as List).isNotEmpty) {
        final results = searchResult['results'] as List;
        final filteredResults = results.where((item) {
          final mediaType = (item as Map<String, dynamic>)['media_type'];
          return mediaType == 'movie' || mediaType == 'tv';
        }).toList();
        
        if (filteredResults.isNotEmpty) {
          return filteredResults.first as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching for "$query": $e');
      }
      return null;
    }
  }

  /// Fetches detailed information for a specific movie by ID.
  ///
  /// Returns a map containing movie details or null if an error occurs.
  Future<Map<String, dynamic>?> getMovieDetails(int movieId) async {
    try {
      final details = await _tmdb.v3.movies.getDetails(movieId);
      return Map<String, dynamic>.from(details);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching movie details for ID $movieId: $e');
      }
      return null;
    }
  }

  /// Fetches detailed information for a specific TV show by ID.
  ///
  /// Returns a map containing TV show details or null if an error occurs.
  Future<Map<String, dynamic>?> getTvDetails(int tvShowId) async {
    try {
      final details = await _tmdb.v3.tv.getDetails(tvShowId);
      return Map<String, dynamic>.from(details);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching TV show details for ID $tvShowId: $e');
      }
      return null;
    }
  }

  /// Fetches enriched movie details including credits and videos using appendToResponse.
  ///
  /// Returns a map containing complete movie details including:
  /// - Basic movie info (title, runtime, genres, vote_average, overview, poster_path, release_date)
  /// - Credits object with cast and crew arrays
  /// - Videos object with results array containing trailers
  /// Returns null if an error occurs.
  Future<Map<String, dynamic>?> getMovieDetailsWithExtras(int movieId) async {
    try {
      final details = await _tmdb.v3.movies.getDetails(
        movieId,
        appendToResponse: 'credits,videos'
      );
      return Map<String, dynamic>.from(details);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching movie details with extras for ID $movieId: $e');
      }
      return null;
    }
  }

  /// Fetches enriched TV show details including aggregate credits and videos using appendToResponse.
  ///
  /// Uses aggregate_credits instead of credits to get series-wide cast information.
  /// Returns a map containing complete TV show details including:
  /// - Basic TV show info (name, number_of_episodes, number_of_seasons, episode_run_time, genres, vote_average, overview, poster_path, first_air_date)
  /// - Aggregate_credits object with cast array (each cast member has roles array)
  /// - Videos object with results array containing trailers
  /// Returns null if an error occurs.
  Future<Map<String, dynamic>?> getTvDetailsWithExtras(int tvShowId) async {
    try {
      final details = await _tmdb.v3.tv.getDetails(
        tvShowId,
        appendToResponse: 'aggregate_credits,videos'
      );
      return Map<String, dynamic>.from(details);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching TV show details with extras for ID $tvShowId: $e');
      }
      return null;
    }
  }

  /// Helper method to extract YouTube trailer URL from media details.
  ///
  /// Filters the videos array for YouTube trailers, preferring official videos.
  /// Returns YouTube URL in format: https://www.youtube.com/watch?v={key}
  /// Returns null if no suitable trailer is found.
  String? getTrailerUrl(Map<String, dynamic>? details) {
    if (details == null ||
        details['videos'] == null ||
        details['videos']['results'] == null) {
      return null;
    }

    final videos = details['videos']['results'] as List;
    
    // Filter for YouTube videos that are trailers or teasers
    final youtubeVideos = videos.where((video) {
      final site = video['site'] as String?;
      final type = video['type'] as String?;
      return site == 'YouTube' && (type == 'Trailer' || type == 'Teaser');
    }).toList();

    if (youtubeVideos.isEmpty) {
      return null;
    }

    // Sort by type (Trailer first), then official status (true first), then by published date (newest first)
    youtubeVideos.sort((a, b) {
      final aType = a['type'] as String? ?? '';
      final bType = b['type'] as String? ?? '';
      
      // Prioritize 'Trailer' over 'Teaser'
      if (aType != bType) {
        if (aType == 'Trailer') return -1;
        if (bType == 'Trailer') return 1;
      }
      
      final aOfficial = a['official'] as bool? ?? false;
      final bOfficial = b['official'] as bool? ?? false;
      
      if (aOfficial != bOfficial) {
        return bOfficial ? 1 : -1; // Official videos come first
      }
      
      final aDate = a['published_at'] as String? ?? '';
      final bDate = b['published_at'] as String? ?? '';
      return bDate.compareTo(aDate); // Newer videos first
    });

    final firstVideo = youtubeVideos.first;
    final key = firstVideo['key'] as String?;
    
    if (key != null) {
      return 'https://www.youtube.com/watch?v=$key';
    }
    
    return null;
  }

  /// Fetches movie credits including cast and crew information.
  ///
  /// Returns a map containing the credits object with cast and crew arrays.
  /// The cast array contains cast members with their roles and billing order.
  /// Returns null if an error occurs.
  Future<Map<String, dynamic>?> getMovieCredits(int movieId) async {
    try {
      final details = await _tmdb.v3.movies.getDetails(
        movieId,
        appendToResponse: 'credits'
      );
      return details['credits'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching movie credits for ID $movieId: $e');
      }
      return null;
    }
  }

  /// Fetches TV show aggregate credits including cast information.
  ///
  /// Uses aggregate_credits instead of credits to get series-wide cast information.
  /// Returns a map containing the aggregate_credits object with cast array.
  /// Each cast member contains a roles array with their character information.
  /// Returns null if an error occurs.
  Future<Map<String, dynamic>?> getTvCredits(int tvShowId) async {
    try {
      final details = await _tmdb.v3.tv.getDetails(
        tvShowId,
        appendToResponse: 'aggregate_credits'
      );
      return details['aggregate_credits'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching TV show aggregate credits for ID $tvShowId: $e');
      }
      return null;
    }
  }

  /// Fetches videos (trailers, teasers, etc.) for a specific movie or TV show.
  ///
  /// The [mediaType] parameter should be either 'movie' or 'tv'.
  /// The [id] parameter is the TMDB ID of the movie or TV show.
  /// Returns a map containing the videos object with results array.
  /// Each result contains trailer/teaser information including YouTube keys.
  /// Returns null if an error occurs.
  Future<Map<String, dynamic>?> getVideos({
    required String mediaType,
    required int id,
  }) async {
    try {
      Map<String, dynamic> details;
      
      if (mediaType == 'movie') {
        details = Map<String, dynamic>.from(await _tmdb.v3.movies.getDetails(
          id,
          appendToResponse: 'videos'
        ));
      } else if (mediaType == 'tv') {
        details = Map<String, dynamic>.from(await _tmdb.v3.tv.getDetails(
          id,
          appendToResponse: 'videos'
        ));
      } else {
        if (kDebugMode) {
          print('Invalid media type: $mediaType. Must be "movie" or "tv"');
        }
        return null;
      }
      
      return details['videos'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching videos for ${mediaType}_$id: $e');
      }
      return null;
    }
  }
}