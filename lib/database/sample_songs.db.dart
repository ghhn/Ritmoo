/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Ritmoo is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Ritmoo is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Ritmoo, including how to contribute,
 *     please visit: https://github.com/gokadzev/Ritmoo
 */

/// Curated sample songs database for initial recommendations and instant playback.
final List<Map<String, dynamic>> sampleSongsDB = [
  {
    'id': 0,
    'ytid': '4NRXx6U8ABQ',
    'title': 'Blinding Lights',
    'artist': 'The Weeknd',
    'image': 'https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/4NRXx6U8ABQ/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/4NRXx6U8ABQ/maxresdefault.jpg',
    'duration': 200,
    'isLive': false,
  },
  {
    'id': 1,
    'ytid': 'JGwWNGJdvx8',
    'title': 'Shape of You',
    'artist': 'Ed Sheeran',
    'image': 'https://i.ytimg.com/vi/JGwWNGJdvx8/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/JGwWNGJdvx8/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/JGwWNGJdvx8/maxresdefault.jpg',
    'duration': 233,
    'isLive': false,
  },
  {
    'id': 2,
    'ytid': 'H5v3kku4y6Q',
    'title': 'As It Was',
    'artist': 'Harry Styles',
    'image': 'https://i.ytimg.com/vi/H5v3kku4y6Q/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/H5v3kku4y6Q/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/H5v3kku4y6Q/maxresdefault.jpg',
    'duration': 167,
    'isLive': false,
  },
  {
    'id': 3,
    'ytid': 'q0hyYWKXF0Q',
    'title': 'Dance Monkey',
    'artist': 'Tones and I',
    'image': 'https://i.ytimg.com/vi/q0hyYWKXF0Q/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/q0hyYWKXF0Q/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/q0hyYWKXF0Q/maxresdefault.jpg',
    'duration': 209,
    'isLive': false,
  },
  {
    'id': 4,
    'ytid': 'kTJczUoc26U',
    'title': 'Stay',
    'artist': 'The Kid LAROI, Justin Bieber',
    'image': 'https://i.ytimg.com/vi/kTJczUoc26U/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/kTJczUoc26U/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/kTJczUoc26U/maxresdefault.jpg',
    'duration': 141,
    'isLive': false,
  },
  {
    'id': 5,
    'ytid': 'G7KNmW9a75Y',
    'title': 'Flowers',
    'artist': 'Miley Cyrus',
    'image': 'https://i.ytimg.com/vi/G7KNmW9a75Y/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/G7KNmW9a75Y/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/G7KNmW9a75Y/maxresdefault.jpg',
    'duration': 200,
    'isLive': false,
  },
  {
    'id': 6,
    'ytid': '7wtfhZwyrcc',
    'title': 'Believer',
    'artist': 'Imagine Dragons',
    'image': 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/7wtfhZwyrcc/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/7wtfhZwyrcc/maxresdefault.jpg',
    'duration': 204,
    'isLive': false,
  },
  {
    'id': 7,
    'ytid': 'kJQP7kiw5Fk',
    'title': 'Despacito',
    'artist': 'Luis Fonsi ft. Daddy Yankee',
    'image': 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/kJQP7kiw5Fk/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/kJQP7kiw5Fk/maxresdefault.jpg',
    'duration': 228,
    'isLive': false,
  },
  {
    'id': 8,
    'ytid': 'dyRsYk0LyA8',
    'title': 'bad guy',
    'artist': 'Billie Eilish',
    'image': 'https://i.ytimg.com/vi/dyRsYk0LyA8/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/dyRsYk0LyA8/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/dyRsYk0LyA8/maxresdefault.jpg',
    'duration': 194,
    'isLive': false,
  },
  {
    'id': 9,
    'ytid': '3tmd-ClpJxA',
    'title': 'Starboy',
    'artist': 'The Weeknd ft. Daft Punk',
    'image': 'https://i.ytimg.com/vi/3tmd-ClpJxA/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/3tmd-ClpJxA/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/3tmd-ClpJxA/maxresdefault.jpg',
    'duration': 230,
    'isLive': false,
  },
  {
    'id': 10,
    'ytid': 'fJ9rUzIMcZQ',
    'title': 'Bohemian Rhapsody',
    'artist': 'Queen',
    'image': 'https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/fJ9rUzIMcZQ/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/fJ9rUzIMcZQ/maxresdefault.jpg',
    'duration': 359,
    'isLive': false,
  },
  {
    'id': 11,
    'ytid': 'v2AC41dglnM',
    'title': 'AC/DC - Thunderstruck',
    'artist': 'AC/DC',
    'image': 'https://i.ytimg.com/vi/v2AC41dglnM/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/v2AC41dglnM/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/v2AC41dglnM/maxresdefault.jpg',
    'duration': 292,
    'isLive': false,
  },
  {
    'id': 12,
    'ytid': 'KxGRhd_iWuE',
    'title': 'DAKITI',
    'artist': 'Bad Bunny x Jhay Cortez',
    'image': 'https://i.ytimg.com/vi/KxGRhd_iWuE/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/KxGRhd_iWuE/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/KxGRhd_iWuE/maxresdefault.jpg',
    'duration': 205,
    'isLive': false,
  },
  {
    'id': 13,
    'ytid': 'nfWlot6h_JM',
    'title': 'Shake It Off',
    'artist': 'Taylor Swift',
    'image': 'https://i.ytimg.com/vi/nfWlot6h_JM/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/nfWlot6h_JM/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/nfWlot6h_JM/maxresdefault.jpg',
    'duration': 241,
    'isLive': false,
  },
  {
    'id': 14,
    'ytid': 'hT_nvWreIhg',
    'title': 'Counting Stars',
    'artist': 'OneRepublic',
    'image': 'https://i.ytimg.com/vi/hT_nvWreIhg/hqdefault.jpg',
    'lowResImage': 'https://i.ytimg.com/vi/hT_nvWreIhg/default.jpg',
    'highResImage': 'https://i.ytimg.com/vi/hT_nvWreIhg/maxresdefault.jpg',
    'duration': 257,
    'isLive': false,
  },
];
