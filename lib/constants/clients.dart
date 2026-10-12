import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Multiple clients in priority order. When one fails, the next is tried.
// androidSdkless (official Android app 20.x), androidVr, tv, and ios
// avoid PO Token requirements, cipher signature throttling, and 403 Forbidden errors.
final customClients = [
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.tv,
  YoutubeApiClient.ios,
  YoutubeApiClient.androidMusic,
  YoutubeApiClient.mweb,
];

// Legacy single client kept for manifest fetches that accept a list.
const customAndroidVr = YoutubeApiClient.androidSdkless;
