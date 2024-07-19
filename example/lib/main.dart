import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:sound_stream/sound_stream.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PlayerStream _player = PlayerStream();

  List<Uint8List> _micChunks = [];
  bool _isPlaying = false;
  bool _useSpeaker = false;

  StreamSubscription? _playerStatus;
  StreamSubscription? _audioStream;

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

  void _play() async {
    await _player.start();

    if (_micChunks.isNotEmpty) {
      for (var chunk in _micChunks) {
        await _player.writeChunk(chunk);
      }
      _micChunks.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  iconSize: 96.0,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _isPlaying ? _player.stop : _play,
                ),
              ],
            ),
            IconButton(
              iconSize: 96.0,
              icon: Icon(_useSpeaker ? Icons.headset_off : Icons.headset),
              onPressed: () {
                setState(() {
                  _useSpeaker = !_useSpeaker;
                  _player.usePhoneSpeaker(_useSpeaker);
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
