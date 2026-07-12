// lib/screens/admin/media_upload_screen.dart
// ─── Admin tool: upload images and audio, attach to quiz questions ────────────
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class MediaUploadScreen extends StatefulWidget {
  const MediaUploadScreen({super.key});
  @override State<MediaUploadScreen> createState() =>
      _MediaUploadScreenState();
}

class _MediaUploadScreenState extends State<MediaUploadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media upload'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.red,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.red,
          tabs: const [Tab(text: 'Upload image'), Tab(text: 'Upload audio')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ImageUploadTab(),
          _AudioUploadTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image upload tab
// ─────────────────────────────────────────────────────────────────────────────
class _ImageUploadTab extends StatefulWidget {
  const _ImageUploadTab();
  @override State<_ImageUploadTab> createState() => _ImageUploadTabState();
}

class _ImageUploadTabState extends State<_ImageUploadTab> {
  File?   _file;
  String? _uploadedUrl;
  int?    _uploadId;
  bool    _uploading = false;
  String? _error;
  String? _success;
  final _qIdCtrl = TextEditingController();

  @override void dispose() { _qIdCtrl.dispose(); super.dispose(); }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery,
        maxWidth: 1200, maxHeight: 1200, imageQuality: 88);
    if (picked == null) return;
    setState(() {
      _file        = File(picked.path);
      _uploadedUrl = null;
      _uploadId    = null;
      _error       = null;
      _success     = null;
    });
  }

  static const _maxImageBytes = 2 * 1024 * 1024; // matches media.php's 2048 KB limit

  Future<void> _upload() async {
    if (_file == null) return;
    // The "Max size: 2 MB" text below was informational only — nothing
    // actually checked the file before uploading it and relying entirely
    // on the server to reject it. Check locally first so oversized files
    // fail fast instead of burning an upload round-trip.
    final size = await _file!.length();
    if (size > _maxImageBytes) {
      setState(() => _error =
          'Image is ${(size / 1024 / 1024).toStringAsFixed(1)} MB — max is 2 MB.');
      return;
    }
    setState(() { _uploading = true; _error = null; _success = null; });
    try {
      final token = await ApiService.getToken();
      final req   = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.nipino-manabu.com/v1/media/upload'));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath(
          'file', _file!.path,
          contentType: MediaType('image', _mimeExt(_file!.path))));

      final streamed = await req.send();
      final res      = await http.Response.fromStream(streamed);
      final body     = jsonDecode(res.body);

      if (res.statusCode == 201) {
        setState(() {
          _uploading   = false;
          _uploadedUrl = body['public_url'];
          _uploadId    = body['upload_id'];
          _success     = 'Uploaded! Enter a Question ID below to attach it.';
        });
      } else {
        setState(() { _uploading = false; _error = body['message']; });
      }
    } catch (e) {
      setState(() { _uploading = false; _error = 'Network error: $e'; });
    }
  }

  Future<void> _attach() async {
    final qId = int.tryParse(_qIdCtrl.text.trim());
    if (qId == null || _uploadId == null) return;
    setState(() { _error = null; _success = null; });
    try {
      final token = await ApiService.getToken();
      final res   = await http.post(
          Uri.parse('https://api.nipino-manabu.com/v1/media/attach'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'question_id': qId,
            'upload_id':   _uploadId,
            'file_type':   'image',
          }));
      final body = jsonDecode(res.body);
      setState(() {
        if (res.statusCode == 200) {
          _success = 'Image attached to question $qId.';
        } else {
          _error = body['message'];
        }
      });
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    }
  }

  String _mimeExt(String path) {
    final ext = path.split('.').last.toLowerCase();
    return {'jpg':'jpeg','jpeg':'jpeg','png':'png','webp':'webp','gif':'gif'}[ext] ?? 'jpeg';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      _InfoBanner(
          icon: Icons.image_outlined,
          title: 'Image upload',
          body: 'Accepted: JPEG, PNG, WEBP, GIF\nMax size: 2 MB per file\n'
              'Used for image_reading and image_meaning question types'),
      const SizedBox(height: 16),

      if (_file != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(_file!, height: 160, width: double.infinity,
              fit: BoxFit.cover)),
        const SizedBox(height: 8),
        Text(_file!.path.split('/').last,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 12),
      ],

      OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.photo_library_outlined, size: 18),
        label: Text(_file == null ? 'Choose image from gallery' : 'Change image'),
      ),
      const SizedBox(height: 8),

      if (_file != null)
        ElevatedButton.icon(
          onPressed: _uploading ? null : _upload,
          icon: _uploading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.upload, size: 18),
          label: const Text('Upload to server'),
        ),

      if (_error  != null) _StatusBox(msg: _error!,   isError: true),
      if (_success != null) _StatusBox(msg: _success!, isError: false),

      if (_uploadedUrl != null) ...[
        const SizedBox(height: 16),
        const Text('Uploaded URL',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.muted)),
        const SizedBox(height: 4),
        SelectableText(_uploadedUrl!,
            style: const TextStyle(fontSize: 11, color: AppColors.blue)),
        const SizedBox(height: 16),
        const Text('Attach to question (enter question ID)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            controller: _qIdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Question ID'),
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _attach,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14)),
            child: const Text('Attach'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'The question type will be updated to image_reading or image_meaning automatically.',
          style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5)),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio upload tab
// ─────────────────────────────────────────────────────────────────────────────
class _AudioUploadTab extends StatefulWidget {
  const _AudioUploadTab();
  @override State<_AudioUploadTab> createState() => _AudioUploadTabState();
}

class _AudioUploadTabState extends State<_AudioUploadTab> {
  String? _filePath;
  String? _fileName;
  String? _uploadedUrl;
  int?    _uploadId;
  bool    _uploading = false;
  String? _error;
  String? _success;
  final _qIdCtrl = TextEditingController();

  @override void dispose() { _qIdCtrl.dispose(); super.dispose(); }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3','wav','ogg','aac','m4a'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _filePath    = result.files.single.path;
      _fileName    = result.files.single.name;
      _uploadedUrl = null;
      _uploadId    = null;
      _error       = null;
      _success     = null;
    });
  }

  static const _maxAudioBytes = 8 * 1024 * 1024; // matches media.php's 8192 KB limit
  static const _allowedAudioExt = {'mp3','wav','ogg','aac','m4a'};

  Future<void> _upload() async {
    if (_filePath == null) return;
    final ext = _fileName!.split('.').last.toLowerCase();
    if (!_allowedAudioExt.contains(ext)) {
      setState(() => _error = 'Unsupported file type: .$ext');
      return;
    }
    // Same reasoning as the image tab — "Max size: 8 MB" was display text
    // only, nothing checked the actual file size before uploading it.
    final size = await File(_filePath!).length();
    if (size > _maxAudioBytes) {
      setState(() => _error =
          'Audio is ${(size / 1024 / 1024).toStringAsFixed(1)} MB — max is 8 MB.');
      return;
    }
    setState(() { _uploading = true; _error = null; _success = null; });
    try {
      final token = await ApiService.getToken();
      final mime  = {
        'mp3':'audio/mpeg','wav':'audio/wav','ogg':'audio/ogg',
        'aac':'audio/aac','m4a':'audio/mp4',
      }[ext] ?? 'audio/mpeg';

      final req = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.nipino-manabu.com/v1/media/upload'));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath(
          'file', _filePath!,
          contentType: MediaType.parse(mime)));

      final streamed = await req.send();
      final res      = await http.Response.fromStream(streamed);
      final body     = jsonDecode(res.body);

      if (res.statusCode == 201) {
        setState(() {
          _uploading   = false;
          _uploadedUrl = body['public_url'];
          _uploadId    = body['upload_id'];
          _success     = 'Audio uploaded! Enter a Question ID to attach it.';
        });
      } else {
        setState(() { _uploading = false; _error = body['message']; });
      }
    } catch (e) {
      setState(() { _uploading = false; _error = 'Network error: $e'; });
    }
  }

  Future<void> _attach() async {
    final qId = int.tryParse(_qIdCtrl.text.trim());
    if (qId == null || _uploadId == null) return;
    setState(() { _error = null; _success = null; });
    try {
      final token = await ApiService.getToken();
      final res   = await http.post(
          Uri.parse('https://api.nipino-manabu.com/v1/media/attach'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'question_id': qId,
            'upload_id':   _uploadId,
            'file_type':   'audio',
          }));
      final body = jsonDecode(res.body);
      setState(() {
        if (res.statusCode == 200) {
          _success = 'Audio attached to question $qId. '
              'Question type updated to "listening".';
        } else {
          _error = body['message'];
        }
      });
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      _InfoBanner(
          icon: Icons.audiotrack_outlined,
          title: 'Audio upload',
          body: 'Accepted: MP3, WAV, OGG, AAC, M4A\nMax size: 8 MB per file\n'
              'Used for listening question types — audio plays automatically'),
      const SizedBox(height: 16),

      if (_fileName != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.bg2,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.audio_file, color: AppColors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(_fileName!,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        ),
        const SizedBox(height: 12),
      ],

      OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: Text(_fileName == null ? 'Choose audio file' : 'Change file'),
      ),
      const SizedBox(height: 8),

      if (_filePath != null)
        ElevatedButton.icon(
          onPressed: _uploading ? null : _upload,
          icon: _uploading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.upload, size: 18),
          label: const Text('Upload to server'),
        ),

      if (_error  != null) _StatusBox(msg: _error!,   isError: true),
      if (_success != null) _StatusBox(msg: _success!, isError: false),

      if (_uploadedUrl != null) ...[
        const SizedBox(height: 16),
        const Text('Attach to question (enter question ID)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            controller: _qIdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Question ID'),
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _attach,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14)),
            child: const Text('Attach'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'The question type will be changed to "listening" automatically.',
          style: TextStyle(
              fontSize: 11, color: AppColors.muted, height: 1.5)),
      ],
    ]);
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon; final String title, body;
  const _InfoBanner({required this.icon, required this.title,
      required this.body});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppColors.blueLight,
        border: const Border(
            left: BorderSide(color: AppColors.blue, width: 3)),
        borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.blue, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.blue)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(
            fontSize: 12, color: Color(0xFF1E3A6E), height: 1.6)),
      ])),
    ]),
  );
}

class _StatusBox extends StatelessWidget {
  final String msg; final bool isError;
  const _StatusBox({required this.msg, required this.isError});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: isError ? AppColors.redLight : AppColors.greenLight,
        border: Border(left: BorderSide(
            color: isError ? AppColors.red : AppColors.green, width: 3)),
        borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4))),
    child: Text(msg,
        style: TextStyle(
            fontSize: 13,
            color: isError ? AppColors.red : AppColors.green)),
  );
}
