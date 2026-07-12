<?php
// backend/storage/ObjectStorage.php  –  Vultr Object Storage S3-compatible
declare(strict_types=1);
class ObjectStorage {
    private static bool $ready=false;
    private static string $endpoint,$accessKey,$secretKey,$bucket,$publicBase;
    private static function boot():void{
        if(self::$ready)return;
        self::$endpoint  =$_ENV['STORAGE_ENDPOINT']  ??'';
        self::$accessKey =$_ENV['STORAGE_ACCESS_KEY']??'';
        self::$secretKey =$_ENV['STORAGE_SECRET_KEY']??'';
        self::$bucket    =$_ENV['STORAGE_BUCKET']    ??'nipino-manabu';
        self::$publicBase=$_ENV['STORAGE_PUBLIC_URL']??'https://'.self::$bucket.'.'.self::$endpoint;
        self::$ready=true;
    }
    public static function upload(string $localPath,string $storageKey,string $mimeType):string{
        self::boot();
        $body=file_get_contents($localPath); $md5=base64_encode(md5($body,true));
        $date=gmdate('D, d M Y H:i:s T'); $acl='public-read';
        $sign="PUT\n{$md5}\n{$mimeType}\n{$date}\nx-amz-acl:{$acl}\n/".self::$bucket."/{$storageKey}";
        $sig=base64_encode(hash_hmac('sha1',$sign,self::$secretKey,true));
        $host=self::$bucket.'.'.self::$endpoint; $url="https://{$host}/{$storageKey}";
        $ch=curl_init($url);
        curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CUSTOMREQUEST=>'PUT',
            CURLOPT_POSTFIELDS=>$body,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_TIMEOUT=>60,
            CURLOPT_HTTPHEADER=>["Host:$host","Date:$date","Content-Type:$mimeType",
                "Content-MD5:$md5","x-amz-acl:$acl",
                "Authorization: AWS ".self::$accessKey.":$sig"]]);
        $res=curl_exec($ch); $code=curl_getinfo($ch,CURLINFO_HTTP_CODE); $err=curl_error($ch); curl_close($ch);
        if($err) throw new \RuntimeException("Storage cURL: $err");
        if(!in_array($code,[200,201],true)) throw new \RuntimeException("Storage HTTP $code: $res");
        return self::$publicBase.'/'.$storageKey;
    }
    public static function delete(string $storageKey):bool{
        self::boot();
        $date=gmdate('D, d M Y H:i:s T');
        $sign="DELETE\n\n\n{$date}\n/".self::$bucket."/{$storageKey}";
        $sig=base64_encode(hash_hmac('sha1',$sign,self::$secretKey,true));
        $host=self::$bucket.'.'.self::$endpoint; $url="https://{$host}/{$storageKey}";
        $ch=curl_init($url);
        curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CUSTOMREQUEST=>'DELETE',
            CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_TIMEOUT=>15,
            CURLOPT_HTTPHEADER=>["Host:$host","Date:$date","Authorization: AWS ".self::$accessKey.":$sig"]]);
        $code=curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch);
        return in_array($code,[200,204],true);
    }
    // Extension comes from the already-validated MIME type, not the
    // client-supplied filename — a file named shell.php containing valid
    // image bytes previously got stored with a .php extension intact.
    private const MIME_EXT = [
        'image/jpeg' => 'jpg', 'image/png' => 'png',
        'image/webp' => 'webp', 'image/gif' => 'gif',
        'audio/mpeg' => 'mp3', 'audio/mp3' => 'mp3', 'audio/wav' => 'wav',
        'audio/x-wav' => 'wav', 'audio/ogg' => 'ogg', 'audio/mp4' => 'm4a',
        'audio/aac' => 'aac', 'audio/x-m4a' => 'm4a',
    ];
    public static function key(string $folder,string $mimeType):string{
        $ext = self::MIME_EXT[$mimeType] ?? 'bin';
        return "quiz/{$folder}/".bin2hex(random_bytes(8)).".{$ext}";
    }
}
