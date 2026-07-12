<?php
// backend/api/media.php  –  image + audio upload for quiz questions
declare(strict_types=1);
require_once dirname(__DIR__).'/config/Database.php';
require_once dirname(__DIR__).'/middleware/Auth.php';
require_once dirname(__DIR__).'/redis/RateLimiter.php';
require_once dirname(__DIR__).'/middleware/Monitor.php';
require_once dirname(__DIR__).'/storage/ObjectStorage.php';
Auth::securityHeaders(); Monitor::register();
$db=Database::connect(); $method=$_SERVER['REQUEST_METHOD']; $action=$_GET['action']??'';
match(true){
    $method==='POST'   && $action==='upload' => handleUpload($db),
    $method==='POST'   && $action==='attach' => handleAttach($db),
    $method==='DELETE' && $action==='delete' => handleDelete($db),
    $method==='GET'    && $action==='list'   => handleList($db),
    default => respond(404,false,'Endpoint not found'),
};
function handleUpload(PDO $db):void{
    $claims=Auth::requireAuth(); $userId=(int)$claims['sub']; guard($db,$userId);
    $ip=$_SERVER['REMOTE_ADDR']??'0.0.0.0';
    RateLimiter::enforce($ip,'media_upload',30,3600);
    if(!isset($_FILES['file'])||$_FILES['file']['error']!==UPLOAD_ERR_OK){
        respond(422,false,'No file uploaded or upload error.'); return;}
    $file=$_FILES['file']; $origName=basename($file['name']); $tmpPath=$file['tmp_name'];
    $sizeKb=(int)ceil($file['size']/1024); $mime=(string)mime_content_type($tmpPath);
    $imgMimes=['image/jpeg','image/png','image/webp','image/gif'];
    $audMimes=['audio/mpeg','audio/mp3','audio/wav','audio/x-wav','audio/ogg','audio/mp4','audio/aac','audio/x-m4a'];
    $isImage=in_array($mime,$imgMimes,true); $isAudio=in_array($mime,$audMimes,true);
    if(!$isImage&&!$isAudio){respond(422,false,"Unsupported: {$mime}. Images: JPEG PNG WEBP GIF. Audio: MP3 WAV OGG AAC."); return;}
    $limitKb=$isImage?2048:8192;
    if($sizeKb>$limitKb){respond(422,false,'File too large. Max '.($limitKb/1024).' MB.'); return;}
    if($isImage&&@getimagesize($tmpPath)===false){respond(422,false,'Invalid image file.'); return;}
    $folder=$isImage?'images':'audio'; $storageKey=ObjectStorage::key($folder,$mime);
    try{$publicUrl=ObjectStorage::upload($tmpPath,$storageKey,$mime);}
    catch(\RuntimeException $e){Monitor::error('media_upload',$e->getMessage(),[],$userId); respond(500,false,'Storage upload failed.'); return;}
    $stmt=$db->prepare('INSERT INTO media_uploads (uploader_id,file_type,original_name,storage_key,public_url,file_size_kb,mime_type) VALUES (?,?,?,?,?,?,?) RETURNING id');
    $stmt->execute([$userId,$isImage?'image':'audio',$origName,$storageKey,$publicUrl,$sizeKb,$mime]);
    $uploadId=(int)($stmt->fetch()['id']??0);
    respond(201,true,'Upload successful.',['upload_id'=>$uploadId,'public_url'=>$publicUrl,'file_type'=>$isImage?'image':'audio','size_kb'=>$sizeKb,'mime_type'=>$mime]);
}
function handleAttach(PDO $db):void{
    $claims=Auth::requireAuth(); $userId=(int)$claims['sub']; guard($db,$userId);
    $body=Auth::getJsonBody(); $qId=(int)($body['question_id']??0);
    $uId=(int)($body['upload_id']??0); $ft=Auth::sanitizeString($body['file_type']??'',10);
    if(!$qId||!$uId||!in_array($ft,['image','audio'],true)){respond(422,false,'question_id, upload_id, file_type required.'); return;}
    $uStmt=$db->prepare('SELECT public_url,file_type FROM media_uploads WHERE id=?');
    $uStmt->execute([$uId]); $upload=$uStmt->fetch();
    if(!$upload){respond(404,false,'Upload not found.'); return;}
    if($upload['file_type']!==$ft){respond(422,false,'file_type mismatch.'); return;}
    $col=$ft==='image'?'image_url':'audio_url';
    $db->prepare("UPDATE quiz_questions SET {$col}=? WHERE id=?")->execute([$upload['public_url'],$qId]);
    $db->prepare('UPDATE media_uploads SET question_id=? WHERE id=?')->execute([$qId,$uId]);
    if($ft==='audio') $db->prepare("UPDATE quiz_questions SET question_type='listening' WHERE id=?")->execute([$qId]);
    elseif($ft==='image') $db->prepare("UPDATE quiz_questions SET question_type=CASE WHEN question_type='reading' THEN 'image_reading' WHEN question_type='meaning' THEN 'image_meaning' ELSE question_type END WHERE id=?")->execute([$qId]);
    respond(200,true,ucfirst($ft).' attached.',['question_id'=>$qId,'url'=>$upload['public_url']]);
}
function handleDelete(PDO $db):void{
    $claims=Auth::requireAuth(); guard($db,(int)$claims['sub']);
    $body=Auth::getJsonBody(); $uId=(int)($body['upload_id']??0);
    $uStmt=$db->prepare('SELECT storage_key,file_type,question_id FROM media_uploads WHERE id=?');
    $uStmt->execute([$uId]); $upload=$uStmt->fetch();
    if(!$upload){respond(404,false,'Upload not found.'); return;}
    ObjectStorage::delete($upload['storage_key']);
    if($upload['question_id']){$col=$upload['file_type']==='image'?'image_url':'audio_url';
        $db->prepare("UPDATE quiz_questions SET {$col}=NULL WHERE id=?")->execute([$upload['question_id']]);}
    $db->prepare('DELETE FROM media_uploads WHERE id=?')->execute([$uId]);
    respond(200,true,'File deleted.');
}
function handleList(PDO $db):void{
    $claims=Auth::requireAuth(); guard($db,(int)$claims['sub']);
    $type=in_array($_GET['type']??'',['image','audio'],true)?$_GET['type']:null;
    $limit=min((int)($_GET['limit']??50),100); $offset=max((int)($_GET['offset']??0),0);
    if($type){$stmt=$db->prepare('SELECT mu.*,qq.question_text FROM media_uploads mu LEFT JOIN quiz_questions qq ON qq.id=mu.question_id WHERE mu.file_type=? ORDER BY mu.created_at DESC LIMIT ? OFFSET ?'); $stmt->execute([$type,$limit,$offset]);}
    else{$stmt=$db->prepare('SELECT mu.*,qq.question_text FROM media_uploads mu LEFT JOIN quiz_questions qq ON qq.id=mu.question_id ORDER BY mu.created_at DESC LIMIT ? OFFSET ?'); $stmt->execute([$limit,$offset]);}
    respond(200,true,'Media list fetched.',['uploads'=>$stmt->fetchAll()]);
}
function guard(PDO $db,int $uid):void{$s=$db->prepare('SELECT is_admin FROM users WHERE id=?');$s->execute([$uid]);$u=$s->fetch();if(!$u||!$u['is_admin']){respond(403,false,'Admin access required.');exit;}}
function respond(int $code,bool $ok,string $msg,array $data=[]):void{http_response_code($code);echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),JSON_UNESCAPED_UNICODE);}
