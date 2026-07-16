<?php
// backend/api/quiz.php — FIXED: count>=1 enforced, Monitor + FCM badge push
declare(strict_types=1);
require_once dirname(__DIR__).'/config/Database.php';
require_once dirname(__DIR__).'/middleware/Auth.php';
require_once dirname(__DIR__).'/redis/RateLimiter.php';
require_once dirname(__DIR__).'/middleware/Monitor.php';
require_once dirname(__DIR__).'/email/FCM.php';
Auth::securityHeaders(); Monitor::register();
$db=Database::connect(); $method=$_SERVER['REQUEST_METHOD']; $action=$_GET['action']??'';
match(true){
    $method==='GET'  && $action==='questions' => handleGetQuestions($db),
    $method==='POST' && $action==='submit'    => handleSubmit($db),
    default => respond(404,false,'Endpoint not found'),
};
function handleGetQuestions(PDO $db):void{
    $claims=Auth::requireAuth(); $userId=(int)$claims['sub'];
    $level=Auth::sanitizeString($_GET['level']??'N5',2);
    $category=Auth::sanitizeString($_GET['category']??'kanji',20);
    $count=max(1,min((int)($_GET['count']??10),20)); // FIX: min 1, max 20
    $validL=['N1','N2','N3','N4','N5']; $validC=['kanji','vocabulary','grammar','listening'];
    if(!in_array($level,$validL,true)){respond(422,false,'Invalid level.'); return;}
    if(!in_array($category,$validC,true)){respond(422,false,'Invalid category.'); return;}

    // Wrong answers cost coins (see handleSubmit's quiz_wrong_penalty), but
    // handleSubmit floors the post-quiz balance at 20, so this gate only
    // fires when a user has spent below that elsewhere (e.g. the store) —
    // block starting a new quiz until they top up rather than letting them
    // grind at a balance that can never go negative anyway.
    $balStmt=$db->prepare('SELECT coins FROM users WHERE id=?');
    $balStmt->execute([$userId]);
    $bal=(int)($balStmt->fetch()['coins']??0);
    if($bal<=0){
        respond(402,false,"You're out of coins. Purchase more coins to keep taking quizzes.",['current_balance'=>$bal]);
        return;
    }
    // image_url/audio_url/media_credit exist on this table since migration
    // 006 but were never added here — every listening question silently had
    // no audio at all (QuizQuestion.hasAudio was always false client-side,
    // so the player widget never even mounted; not a playback failure, the
    // data just never reached the app).
    $stmt=$db->prepare('SELECT id,level,category,question_text,question_type,
        options,correct_index,explanation,memory_tip,point_value,
        image_url,audio_url,media_credit
        FROM quiz_questions WHERE level=? AND category=? AND is_active=TRUE
        ORDER BY RANDOM() LIMIT ?');
    $stmt->execute([$level,$category,$count]);
    $rows=$stmt->fetchAll();
    if(empty($rows)){respond(404,false,"No questions found for $level $category."); return;}
    $questions=array_map(function(array $q):array{
        $q['options']=json_decode($q['options'],true);
        $q['correct_index']=(int)$q['correct_index'];
        $q['point_value']=(int)$q['point_value'];
        return $q;
    },$rows);
    respond(200,true,'Questions fetched.',['questions'=>$questions]);
}
function handleSubmit(PDO $db):void{
    $claims=Auth::requireAuth(); $userId=(int)$claims['sub'];
    RateLimiter::quizSubmit((string)$userId);
    $body=Auth::getJsonBody();
    $level=Auth::sanitizeString($body['level']??'',2);
    $category=Auth::sanitizeString($body['category']??'',20);
    $timeTaken=(int)($body['time_taken_seconds']??0);
    $rawAnswers=is_array($body['answers']??null)?$body['answers']:[];
    $validL=['N1','N2','N3','N4','N5'];
    $validC=['kanji','vocabulary','grammar','listening'];
    if(!in_array($level,$validL,true)){respond(422,false,'Invalid data.'); return;}
    // Unvalidated category used to flow straight into quiz_results, and the
    // level-exam unlock below counts DISTINCT category at >=80% — submitting
    // real questions tagged with made-up category strings could inflate that
    // count past 4 and unlock the level exam without passing all real categories.
    if(!in_array($category,$validC,true)){respond(422,false,'Invalid data.'); return;}

    // Never trust a client-submitted score — re-derive correct_count/total_count
    // server-side from the real answer key. Dedupe by question_id so the same
    // easy question can't be replayed multiple times in one submission to
    // farm coins.
    $byQuestion=[];
    foreach($rawAnswers as $a){
        if(!is_array($a)||!isset($a['question_id'])) continue;
        $qid=(int)$a['question_id'];
        if($qid<=0||isset($byQuestion[$qid])) continue;
        $byQuestion[$qid]=isset($a['chosen_index'])&&$a['chosen_index']!==null?(int)$a['chosen_index']:null;
    }
    $totalCount=count($byQuestion);
    if($totalCount<1||$totalCount>20){respond(422,false,'Invalid data.'); return;}

    $ids=array_keys($byQuestion);
    $placeholders=implode(',',array_fill(0,count($ids),'?'));
    $qStmt=$db->prepare("SELECT id,level,correct_index FROM quiz_questions WHERE id IN ($placeholders)");
    $qStmt->execute($ids);
    $realQuestions=$qStmt->fetchAll();
    if(count($realQuestions)!==$totalCount){respond(422,false,'Invalid question data.'); return;}

    $correctCount=0;
    foreach($realQuestions as $rq){
        if((string)$rq['level']!==$level){respond(422,false,'Question/level mismatch.'); return;}
        $chosen=$byQuestion[(int)$rq['id']];
        if($chosen!==null&&$chosen===(int)$rq['correct_index']) $correctCount++;
    }

    $cfg=require dirname(__DIR__).'/config/config.php';
    $coinPerQ=$cfg['coins'][$level]??10; $streakBonus=0; $perfectBonus=0;
    $wrongPenalty=(int)($cfg['coins']['wrong_answer_penalty']??10);
    $uStmt=$db->prepare('SELECT streak_days,last_quiz_date FROM users WHERE id=?');
    $uStmt->execute([$userId]); $uRow=$uStmt->fetch();
    if($uRow&&(int)$uRow['streak_days']>=7) $streakBonus=$cfg['coins']['streak_bonus'];
    if($correctCount===$totalCount) $perfectBonus=$cfg['coins']['perfect_bonus'];
    $coinsEarned=($correctCount*$coinPerQ)+$streakBonus+$perfectBonus;
    $wrongCount=$totalCount-$correctCount;
    $coinsLost=$wrongCount*$wrongPenalty;
    $db->prepare('INSERT INTO quiz_results (user_id,level,category,correct_count,total_count,time_taken_seconds,coins_earned) VALUES (?,?,?,?,?,?,?)')
       ->execute([$userId,$level,$category,$correctCount,$totalCount,$timeTaken,$coinsEarned]);
    $db->beginTransaction();
    try {
        // Lock the row so the balance we clamp against can't go stale
        // against a concurrent duel/store spend — same reasoning as the
        // duel join/finalize locks elsewhere in this codebase.
        $lockStmt=$db->prepare('SELECT coins FROM users WHERE id=? FOR UPDATE');
        $lockStmt->execute([$userId]);
        $oldBal=(int)($lockStmt->fetch()['coins']??0);

        // The reward always applies in full; the penalty is the part that
        // gets capped so a bad quiz can never leave a user below 20 coins
        // (matches the handleGetQuestions gate above, which blocks starting
        // a new quiz at 0). Beginners failing their first ~10 questions
        // would otherwise hit 0 and get locked out before they've had a
        // chance to improve.
        $balAfterReward=$oldBal+$coinsEarned;
        $actualLost=min($coinsLost,max(0,$balAfterReward-20));
        $newBal=$balAfterReward-$actualLost;

        $db->prepare('UPDATE users SET coins=?,total_score=total_score+?,last_quiz_date=CURRENT_DATE WHERE id=?')
           ->execute([$newBal,$correctCount*$coinPerQ,$userId]);

        // Recorded as two separate ledger rows (reward vs penalty), matching
        // how every other coin movement in this app is itemised. Each row
        // uses the amount actually applied and the balance immediately
        // after it, so balance_after always equals running total — a
        // clamped penalty no longer disagrees with its own ledger entry.
        if($coinsEarned>0){
            $db->prepare("INSERT INTO coin_transactions (user_id,amount,balance_after,type,description) VALUES (?,?,?,'quiz_reward',?)")
               ->execute([$userId,$coinsEarned,$balAfterReward,"Quiz reward — $level $category ($correctCount/$totalCount correct)"]);
        }
        if($actualLost>0){
            $db->prepare("INSERT INTO coin_transactions (user_id,amount,balance_after,type,description) VALUES (?,?,?,'quiz_wrong_penalty',?)")
               ->execute([$userId,-$actualLost,$newBal,"Quiz penalty — $wrongCount wrong answer(s) in $level $category"]);
        }
        $db->commit();
    } catch (\Exception $e) {
        $db->rollBack();
        respond(500,false,'Failed to save quiz result.'); return;
    }
    $today=date('Y-m-d'); $yday=date('Y-m-d',strtotime('-1 day')); $last=$uRow['last_quiz_date']??null;
    if($last!==$today) $db->prepare($last===$yday
        ?'UPDATE users SET streak_days=streak_days+1 WHERE id=?'
        :'UPDATE users SET streak_days=1 WHERE id=?')->execute([$userId]);
    if($totalCount>0&&$correctCount/$totalCount>=0.8){
        $ps=$db->prepare("SELECT COUNT(DISTINCT category) AS passed FROM quiz_results WHERE user_id=? AND level=? AND (correct_count::float/total_count)>=0.8");
        $ps->execute([$userId,$level]); $passed=(int)($ps->fetch()['passed']??0);
        $completed=min($passed,6); $examUnlocked=$completed>=4;
        $db->prepare('INSERT INTO user_level_progress (user_id,level,completed_topics,exam_unlocked) VALUES (?,?,?,?) ON CONFLICT (user_id,level) DO UPDATE SET completed_topics=GREATEST(user_level_progress.completed_topics,?),exam_unlocked=?,updated_at=NOW()')
           ->execute([$userId,$level,$completed,$examUnlocked?'true':'false']);
        if($completed>=6){
            $ft=$db->prepare('SELECT fcm_token FROM users WHERE id=? AND fcm_token IS NOT NULL');
            $ft->execute([$userId]); $fr=$ft->fetch();
            if($fr) FCM::levelComplete($fr['fcm_token'],$level);
        }
    }
    $newBadges=checkBadges($db,$userId,$level,$correctCount,$totalCount,$timeTaken);
    if(!empty($newBadges)){
        $ft=$db->prepare('SELECT fcm_token FROM users WHERE id=? AND fcm_token IS NOT NULL');
        $ft->execute([$userId]); $fr=$ft->fetch();
        if($fr) FCM::badgeEarned($fr['fcm_token'],$newBadges[0]['name'],$newBadges[0]['icon_emoji']);
    }
    $u=$db->prepare('SELECT coins,streak_days FROM users WHERE id=?');
    $u->execute([$userId]); $ud=$u->fetch();
    respond(200,true,'Result saved.',['coins_earned'=>$coinsEarned,'coins_lost'=>$actualLost,'streak_bonus'=>$streakBonus,
        'perfect_bonus'=>$perfectBonus,'total_coins'=>(int)$ud['coins'],
        'streak_days'=>(int)$ud['streak_days'],'new_badges'=>$newBadges]);
}
function checkBadges(PDO $db,int $uid,string $level,int $correct,int $total,int $time):array{
    $awarded=[];
    $bs=$db->prepare('SELECT b.* FROM badges b WHERE b.id NOT IN (SELECT badge_id FROM user_badges WHERE user_id=?)');
    $bs->execute([$uid]); $candidates=$bs->fetchAll();
    $ss=$db->prepare('SELECT streak_days,coins,(SELECT COUNT(*) FROM quiz_results WHERE user_id=?) AS qc FROM users WHERE id=?');
    $ss->execute([$uid,$uid]); $stats=$ss->fetch();
    $pct=$total>0?($correct/$total)*100:0;
    foreach($candidates as $b){
        $c=json_decode($b['condition'],true); $t=$c['type']??''; $v=$c['value']??0; $ok=false;
        switch($t){
            case 'quizzes_completed': $ok=(int)$stats['qc']>=(int)$v; break;
            case 'streak':            $ok=(int)$stats['streak_days']>=(int)$v; break;
            case 'coins':             $ok=(int)$stats['coins']>=(int)$v; break;
            case 'level_complete':
                $lp=$db->prepare('SELECT completed_topics FROM user_level_progress WHERE user_id=? AND level=?');
                $lp->execute([$uid,$v]); $lr=$lp->fetch(); $ok=$lr&&(int)$lr['completed_topics']>=6; break;
            case 'score_percent':     $ok=$pct>=(float)$v; break;
            case 'score_percent_n2n1':$ok=in_array($level,['N1','N2'],true)&&$pct>=(float)$v; break;
            case 'speed':             $ok=$time<=(int)$v&&$total>=10; break;
        }
        if($ok){
            $db->prepare('INSERT INTO user_badges (user_id,badge_id) VALUES (?,?) ON CONFLICT DO NOTHING')->execute([$uid,$b['id']]);
            $awarded[]=['name'=>$b['name'],'icon_emoji'=>$b['icon_emoji']];
        }
    }
    return $awarded;
}
function respond(int $code,bool $ok,string $msg,array $data=[]):void{
    http_response_code($code);
    echo json_encode(array_merge(['success'=>$ok,'message'=>$msg],$data),JSON_UNESCAPED_UNICODE);
}
