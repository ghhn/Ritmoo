import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Multiple clients in priority order. When one fails, the next is tried.
// ios and androidVr avoid PO Token requirements and 403 Forbidden errors on YouTube CDN.
final customClients = [
  YoutubeApiClient.androidVr,
  YoutubeApiClient.tv,
  YoutubeApiClient.ios,
  YoutubeApiClient.mweb,
  YoutubeApiClient.androidMusic,
  YoutubeApiClient.androidSdkless,
];

// Legacy single client kept for manifest fetches that accept a list.
const customAndroidVr = YoutubeApiClient.androidVr;

