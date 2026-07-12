// lib/widgets/quiz_media_widget.dart
// ─── Renders image or audio player for quiz questions ────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Image widget — shown above question text for image_reading / image_meaning
// ─────────────────────────────────────────────────────────────────────────────
class QuizImageWidget extends StatelessWidget {
  final String url;
  final String? credit;
  const QuizImageWidget({super.key, required this.url, this.credit});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width:    double.infinity,
          height:   180,
          fit:      BoxFit.contain,
          placeholder: (_, __) => Container(
            height: 180, color: AppColors.bg2,
            child: const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => Container(
            height: 180, color: AppColors.bg2,
            child: const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.broken_image_outlined,
                    color: AppColors.muted, size: 32),
                SizedBox(height: 6),
                Text('Image unavailable',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            )),
          ),
        ),
      ),
      if (credit != null && credit!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(credit!,
              style: const TextStyle(fontSize: 10, color: AppColors.muted2),
              textAlign: TextAlign.center),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio player widget — for 'listening' type questions
// Auto-plays when the question appears; user can replay manually.
// ─────────────────────────────────────────────────────────────────────────────
class QuizAudioWidget extends StatefulWidget {
  final String url;
  final bool autoPlay;
  const QuizAudioWidget({
    super.key,
    required this.url,
    this.autoPlay = true,
  });
  @override State<QuizAudioWidget> createState() => _QuizAudioWidgetState();
}

class _QuizAudioWidgetState extends State<QuizAudioWidget> {
  late final AudioPlayer _player;
  bool _loading = true;
  bool _playing = false;
  bool _error   = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _posSub, _durSub, _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      _durSub  = _player.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _duration = d);
      });
      _posSub  = _player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _stateSub = _player.playerStateStream.listen((s) {
        if (mounted) setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          if (mounted) setState(() { _playing = false; _position = Duration.zero; });
        }
      });
      if (mounted) setState(() => _loading = false);
      if (widget.autoPlay) _play();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _play() async {
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> _togglePlay() async {
    if (_playing) { await _player.pause(); }
    else { await _play(); }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2,'0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2,'0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _posSub?.cancel(); _durSub?.cancel(); _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.redLight,
            border: Border.all(color: AppColors.red),
            borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Icon(Icons.volume_off, color: AppColors.red, size: 18),
          SizedBox(width: 8),
          Text('Audio unavailable',
              style: TextStyle(fontSize: 13, color: AppColors.red)),
        ]),
      );
    }

    final progress = _duration.inMilliseconds == 0 ? 0.0
        : _position.inMilliseconds / _duration.inMilliseconds;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Row(children: [
          // Headphones icon — visual indicator this is a listening question
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: AppColors.redLight, shape: BoxShape.circle),
            child: const Icon(Icons.headphones,
                color: AppColors.red, size: 18)),
          const SizedBox(width: 10),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Listening question',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            Text('Press play then choose the correct answer',
                style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ])),
          // Play / pause button
          _loading
              ? const SizedBox(width: 36, height: 36,
                  child: CircularProgressIndicator(
                      color: AppColors.red, strokeWidth: 2))
              : GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                        color: AppColors.red, shape: BoxShape.circle),
                    child: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 24),
                  ),
                ),
        ]),
        const SizedBox(height: 10),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: AppColors.bg3,
            color: AppColors.red,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(_fmt(_position),
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          const Spacer(),
          Text(_fmt(_duration),
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      ]),
    );
  }
}
