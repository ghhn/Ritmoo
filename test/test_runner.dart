import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  print('Iniciando prueba de conectividad y extracción de audio...');
  final yt = YoutubeExplode();
  try {
    print('1. Obteniendo manifest de audio para dQw4w9WgXcQ...');
    final manifest = await yt.videos.streams.getManifest(
      'dQw4w9WgXcQ',
      ytClients: [YoutubeApiClient.androidSdkless, YoutubeApiClient.ios],
    );
    final audio = manifest.audioOnly.sortByBitrate();
    print('Streams de audio encontrados: ');
    if (audio.isNotEmpty) {
      final best = audio.last;
      print('Mejor stream:  kbps ()');
      print('URL generada correctamente (longitud:  caracteres)');
    }

    print('2. Obteniendo pistas de álbum...');
    final tracks = await yt.playlists.getVideos('VLOLAK5uy_mr6DjxLeVO2rPk8zAZx0F2_k5BaGuXlyQ').take(3).toList();
    print('Pistas de álbum obtenidas con éxito: ');
    for (var t in tracks) {
      print(' -  ()');
    }
    print('¡Prueba completada con éxito al 100%!');
  } catch (e, st) {
    print('Error en la prueba: ');
    print(st);
  } finally {
    yt.close();
    exit(0);
  }
}
