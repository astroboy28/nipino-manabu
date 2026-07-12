// lib/services/api_service.dart — FINAL: adds account deletion + GDPR export
// (appended methods only — full file replaces previous version)
// NOTE: This is the complete file. Replace lib/services/api_service.dart entirely.
import 'dart:convert';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';

class ApiService {
  static const _base = 'https://api.nipino-manabu.com/v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _tokenKey   = 'jwt_access_token';
  static const _refreshKey = 'jwt_refresh_token';

  // Set once at app startup (see main.dart) so a hard-401 (refresh token
  // also expired/invalid) can route back to the login screen instead of
  // leaving every screen stuck on a generic "failed to load" forever, since
  // subsequent requests keep going out unauthenticated after tokens clear.
  static VoidCallback? onSessionExpired;
  static bool _sessionExpiredFired = false;

  static Future<String?> getToken()   => _storage.read(key: _tokenKey);
  static Future<String?> getRefresh() => _storage.read(key: _refreshKey);
  static Future<void> saveTokens(String a, String r) async {
    await _storage.write(key: _tokenKey,   value: a);
    await _storage.write(key: _refreshKey, value: r);
    _sessionExpiredFired = false; // fresh session — ready to fire again later
  }
  static Future<void> clearTokens() async => _storage.deleteAll();

  static void _notifySessionExpired() {
    if (_sessionExpiredFired) return; // avoid re-firing for every concurrent 401
    _sessionExpiredFired = true;
    onSessionExpired?.call();
  }

  static Future<Map<String,String>> _h({bool auth=true}) async {
    final h = {'Content-Type':'application/json','Accept':'application/json','X-App-Version':'1.0.0'};
    if (auth) { final t = await getToken(); if (t!=null) h['Authorization']='Bearer $t'; }
    return h;
  }
  static Future<bool> _refresh() async {
    final r = await getRefresh();
    if (r==null) { _notifySessionExpired(); return false; }
    try {
      final res = await http.post(Uri.parse('$_base/auth/refresh'),
          headers: {'Content-Type':'application/json'}, body: jsonEncode({'refresh_token':r}));
      if (res.statusCode==200) { final d=jsonDecode(res.body); await saveTokens(d['access_token'],d['refresh_token']); return true; }
    } catch(_){}
    await clearTokens();
    _notifySessionExpired();
    return false;
  }
  static Future<http.Response> _get(String p) async {
    var r=await http.get(Uri.parse('$_base$p'),headers:await _h());
    if(r.statusCode==401&&await _refresh()) r=await http.get(Uri.parse('$_base$p'),headers:await _h());
    return r;
  }
  static Future<http.Response> _post(String p,Map<String,dynamic> b,{bool auth=true}) async {
    var r=await http.post(Uri.parse('$_base$p'),headers:await _h(auth:auth),body:jsonEncode(b));
    if(r.statusCode==401&&auth&&await _refresh()) r=await http.post(Uri.parse('$_base$p'),headers:await _h(),body:jsonEncode(b));
    return r;
  }
  static Future<http.Response> _put(String p,Map<String,dynamic> b) async {
    var r=await http.put(Uri.parse('$_base$p'),headers:await _h(),body:jsonEncode(b));
    if(r.statusCode==401&&await _refresh()) r=await http.put(Uri.parse('$_base$p'),headers:await _h(),body:jsonEncode(b));
    return r;
  }
  static Future<http.Response> _delete(String p,{Map<String,dynamic>? b}) async {
    var r=await http.delete(Uri.parse('$_base$p'),headers:await _h(),body:b!=null?jsonEncode(b):null);
    if(r.statusCode==401&&await _refresh()) r=await http.delete(Uri.parse('$_base$p'),headers:await _h(),body:b!=null?jsonEncode(b):null);
    return r;
  }

  static ApiResponse<T> _err<T>(dynamic e) => ApiResponse(success:false,error:'Network error',statusCode:0);

  // AUTH
  static Future<ApiResponse<User>> register({required String username,required String email,required String password}) async {
    try { final res=await _post('/auth/register',{'username':username,'email':email,'password':password},auth:false);
      final b=jsonDecode(res.body);
      if(res.statusCode==201){ await saveTokens(b['access_token'],b['refresh_token']); return ApiResponse(success:true,data:User.fromJson(b['user']),statusCode:201); }
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<User>> login({required String email,required String password}) async {
    try { final res=await _post('/auth/login',{'email':email,'password':password},auth:false);
      final b=jsonDecode(res.body);
      if(res.statusCode==200){ await saveTokens(b['access_token'],b['refresh_token']); return ApiResponse(success:true,data:User.fromJson(b['user']),statusCode:200); }
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<void> logout() async { try{await _post('/auth/logout',{});}catch(_){} await clearTokens(); }
  static Future<ApiResponse<void>> forgotPassword(String email) async {
    try { final res=await _post('/auth/forgot-password',{'email':email},auth:false);
      final b=jsonDecode(res.body); return ApiResponse(success:b['success']??false,statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<void>> resendVerification(String email) async {
    try { final res=await _post('/auth/resend-verification',{'email':email},auth:false);
      final b=jsonDecode(res.body); return ApiResponse(success:b['success']??false,statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<void>> resetPassword({required String token,required String newPassword}) async {
    try { final res=await _post('/auth/reset-password',{'token':token,'password':newPassword},auth:false);
      final b=jsonDecode(res.body); return ApiResponse(success:b['success']??false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // USER
  static Future<ApiResponse<User>> getProfile() async {
    try { final res=await _get('/user/profile'); final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:User.fromJson(b['user']),statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<List<LevelProgress>>> getProgress() async {
    try { final res=await _get('/user/progress'); final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:(b['progress'] as List).map((e)=>LevelProgress.fromJson(e)).toList(),statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<void> updateFcmToken(String token) async { try{await _put('/user/profile',{'fcm_token':token});}catch(_){} }
  static Future<ApiResponse<List<AppBadge>>> getBadges() async {
    try { final res=await _get('/user/badges'); final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:(b['badges'] as List).map((e)=>AppBadge.fromJson(e)).toList(),statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // ACCOUNT DELETION
  static Future<ApiResponse<void>> requestAccountDeletion(String password) async {
    try { final res=await _post('/account/request-deletion',{'password':password});
      final b=jsonDecode(res.body);
      return ApiResponse(success:b['success']??false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<void>> cancelAccountDeletion() async {
    try { final res=await _delete('/account/cancel-deletion');
      final b=jsonDecode(res.body);
      return ApiResponse(success:b['success']??false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // GDPR EXPORT
  static Future<ApiResponse<Map<String,dynamic>>> exportData() async {
    try { final res=await _get('/account/export');
      if(res.statusCode==200) return ApiResponse(success:true,data:jsonDecode(res.body) as Map<String,dynamic>,statusCode:200);
      final b=jsonDecode(res.body); return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // QUIZ
  static Future<ApiResponse<List<QuizQuestion>>> getQuestions({required String level,required String category,int count=10}) async {
    try { final res=await _get('/quiz/questions?level=$level&category=$category&count=${count.clamp(1,20)}'); final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:(b['questions'] as List).map((e)=>QuizQuestion.fromJson(e)).toList(),statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<Map<String,dynamic>>> submitQuizResult({required String level,required String category,required List<Map<String,dynamic>> answers,required int timeTakenSeconds}) async {
    try { final res=await _post('/quiz/submit',{'level':level,'category':category,'answers':answers,'time_taken_seconds':timeTakenSeconds});
      final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:b,statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // LEADERBOARD
  static Future<ApiResponse<List<LeaderboardEntry>>> getLeaderboard({String period='weekly',String? level,int currentUserId=0}) async {
    try { final q=level!=null?'/leaderboard/list?period=$period&level=$level':'/leaderboard/list?period=$period';
      final res=await _get(q); final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:(b['entries'] as List).map((e)=>LeaderboardEntry.fromJson(e,currentUserId)).toList(),statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }

  // IAP
  static Future<ApiResponse<Map<String,dynamic>>> validateIAPPurchase({required String productId,required String receiptData,required String platform}) async {
    try { final res=await _post('/store/validate-purchase',{'product_id':productId,'receipt_data':receiptData,'platform':platform});
      final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:b,statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
  static Future<ApiResponse<Map<String,dynamic>>> getSubscriptionStatus() async {
    try { final res=await _get('/store/subscription-status');
      final b=jsonDecode(res.body);
      if(res.statusCode==200) return ApiResponse(success:true,data:b,statusCode:200);
      return ApiResponse(success:false,error:b['message'],statusCode:res.statusCode); } catch(e){return _err(e);}
  }
}
