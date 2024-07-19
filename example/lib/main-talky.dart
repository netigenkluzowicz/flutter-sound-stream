import 'dart:async';
import 'package:flutter/material.dart';

import 'package:sound_stream/sound_stream.dart';
import 'package:web_socket_channel/io.dart';

// Change this URL to your own
const _SERVER_URL = 'wss://linhlt.ap.ngrok.io';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PlayerStream _player = PlayerStream();

  bool _isPlaying = false;

  StreamSubscription? _playerStatus;
  StreamSubscription? _audioStream;

  final channel = IOWebSocketChannel.connect(_SERVER_URL);

  @override
  void initState() {
    super.initState();
    initPlugin();
  }

  @override
  void dispose() {
    _playerStatus?.cancel();
    _audioStream?.cancel();
    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlugin() async {
    channel.stream.listen((event) async {
      // print(event);
      if (_isPlaying) _player.writeChunk(event);
    });

    _playerStatus = _player.status.listen((status) {
      if (mounted)
        setState(() {
          _isPlaying = status == SoundStreamStatus.Playing;
        });
    });

    await Future.wait([
      _player.initialize(),
    ]);
  }

  void _startRecord() async {
    await _player.stop();
  }

  void _stopRecord() async {
    await _player.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTapDown: (tap) {
                _startRecord();
              },
              onTapUp: (tap) {
                _stopRecord();
              },
              onTapCancel: () {
                _stopRecord();
              },
            ),
          ],
        ),
      ),
    );
  }
}
