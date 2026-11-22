import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../supabase_client.dart';

const maxDocumentBytes = 10 * 1024 * 1024;
const allowedDocumentTypes = <String, String>{
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

/// Private document vault. Files are stored at "<user id>/<uuid>.<ext>" in a private bucket; storage policies
/// restrict every operation to the owner, and downloads use signed URLs that expire after two minutes.
class DocumentRepository {
  DocumentRepository(this._c);
  final SupabaseClient _c;
  static const bucket = 'user-documents';

  Future<List<UserDocument>> list() => guard(() async {
        final rows = await _c.from('user_documents').select().eq('user_id', requireUserId(_c)).order('created_at', ascending: false);
        return rows.map(UserDocument.fromJson).toList();
      });

  static String? validate(String fileName, int size) {
    final ext = fileName.split('.').last.toLowerCase();
    if (!allowedDocumentTypes.containsKey(ext)) return 'docs.badType';
    if (size > maxDocumentBytes) return 'docs.tooLarge';
    return null;
  }

  Future<void> upload({required String category, required String title, required String fileName, required Uint8List bytes,
      DateTime? expiresOn, UserDocument? replacing}) =>
      guard(() async {
        final err = validate(fileName, bytes.length);
        if (err != null) throw AppException(err == 'docs.tooLarge' ? 'File is larger than 10 MB' : 'Unsupported file type');
        final uid = requireUserId(_c);
        final ext = fileName.split('.').last.toLowerCase();
        final mime = allowedDocumentTypes[ext]!;
        final path = '$uid/${DateTime.now().toUtc().microsecondsSinceEpoch}.$ext';
        await _c.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
        final row = {
          'user_id': uid,
          'category': category,
          'title': title,
          'storage_path': path,
          'mime_type': mime,
          'size_bytes': bytes.length,
          'expires_on': expiresOn == null ? null : '${expiresOn.year}-${expiresOn.month.toString().padLeft(2, '0')}-${expiresOn.day.toString().padLeft(2, '0')}',
        };
        try {
          if (replacing == null) {
            await _c.from('user_documents').insert(row);
          } else {
            await _c.from('user_documents').update(row).eq('id', replacing.id);
            await _c.storage.from(bucket).remove([replacing.storagePath]);
          }
        } catch (e) {
          await _c.storage.from(bucket).remove([path]); // don't leave orphaned files
          rethrow;
        }
      });

  Future<String> signedUrl(UserDocument d) => guard(() => _c.storage.from(bucket).createSignedUrl(d.storagePath, 120));

  Future<Uint8List> download(UserDocument d) => guard(() => _c.storage.from(bucket).download(d.storagePath));

  Future<void> delete(UserDocument d) => guard(() async {
        await _c.storage.from(bucket).remove([d.storagePath]);
        await _c.from('user_documents').delete().eq('id', d.id);
      });
}

final documentRepositoryProvider = Provider<DocumentRepository>((ref) => DocumentRepository(ref.watch(supabaseProvider)));
final documentsProvider = FutureProvider.autoDispose<List<UserDocument>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(documentRepositoryProvider).list();
});
