#!/usr/bin/perl

use strict;
use utf8;
use Encode;
use Net::Twitter::Lite::WithAPIv1_1;

=pod
twitterでOAuth認証を使ってつぶやくだけのサンプル
事前に http://dev.twitter.com/ で app として登録しておくこと

=cut
# http://dev.twitter.com/apps/XXXXXX で取得できるやつ
my %CONSUMER_TOKENS = (
    consumer_key    => '< consumer key >',
    consumer_secret => '< consumer secret >',
    );

# http://dev.twitter.com/apps/XXXXXX/my_token で取得できるやつ
my $ACCESS_TOKEN        = '< token >';
my $ACCESS_TOKEN_SECRET = '< token secret >';

# "Net::Twitter::Lite" object
my $t = Net::Twitter::Lite::WithAPIv1_1->new(%CONSUMER_TOKENS);

# トークンをセットする
$t->access_token($ACCESS_TOKEN);
$t->access_token_secret($ACCESS_TOKEN_SECRET);

########## 変数群 ##########
# localtime, 現在の hour と、1時間前の hour, day, month.
my ($sec, $min, $hour, $mday, $mon, $year ) = (localtime(time))[0..5];
my ($hour_1, $mday_1, $mon_1) = (localtime(time - 3600))[2..4];
$mon += 1;
$mon_1 += 1;
$year += 1900;
my $now = sprintf ("%04d/%02d/%02d %02d:%02d", $year,$mon,$mday,$hour,$min,$sec);

my $count = 100;
my $retry = 3;
my $retry_count = 0;
my $destroy_max_id;
my $destroy_since_id;
my $quit_max_id;
my $quit_since_id;
my $last_id;
my $num;
my $yesterday_num;
my $post;
my $status;
my $dat_dir_name = "< datfile dir >";
my $log_dir_name = "< logfile dir >";

# 外部ファイル
my $count_file = "${dat_dirname}naka_fan_quit_count.dat";
my $destroy_id_file = "${dat_dirname}naka_fan_destroy_id.dat";
my $destroy_log_file = "${log_dir_name}naka_fan_destroy.log";
my $quit_id_file = "${dat_dirname}naka_fan_quit_id.dat";
my $quit_log_file = "${log_dir_name}naka_fan_quit.log";
my $destroy_monthly_count_file = "${log_dir_name}naka_fan_destroy_monthly.log";
my $quit_monthly_count_file = "${log_dir_name}naka_fan_quit_monthly.log";


# 検索クエリ
my $destroy_search_keyword = "那珂+解体しました+OR+解体します+OR+解体した+OR+カーンカーン+OR+燃2弾4鋼11";
my $quit_search_keyword = "那珂+ファン+辞めます+OR+やめます+OR+辞める+OR+やめる+OR+辞めた+OR+やめた+OR+辞めちゃった+OR+やめちゃった+OR+辞めちゃう+OR+やめちゃう+OR+辞めちゃいます+OR+やめちゃいます+OR+辞めて+OR+やめて+OR+辞めました+OR+やめました+OR+那フ辞+OR+那フや+OR+#那珂ちゃんのファン辞めます+OR+#那珂ちゃんのファンやめます";

# ポスト内容
my $destroy_hour_post = "$hour_1:00 から $hour:00 までの 1 時間で $num 人が那珂ちゃんを解体しました #艦これ";
my $destroy_daily_post_pattern = "%02d/%02d は %d 人が那珂ちゃんを解体しました #艦これ";
my $destroy_daily_post = "$mon_1/$mday_1 は $num 人が那珂ちゃんを解体しました #艦これ";
my $quit_hour_post_pattern = "%02d:00 から %02d:00 までの 1 時間で %d 人が那珂ちゃんのファンをやめました #艦これ";
my $quit_hour_post = "$hour_1:00 から $hour:00 までの 1 時間で $num 人が那珂ちゃんのファンをやめました #艦これ";
my $quit_daily_post_pattern = "%02d/%02d は %d 人が那珂ちゃんのファンをやめました #艦これ";
my $quit_daily_post = "$mon_1/$mday_1 は $yesterday_num 人が那珂ちゃんのファンをやめました #艦これ";

########## 変数群おわり ##########

########## サブルーチン群 ##########
# $t->search が失敗していた場合 $retry 回数リトライする。施行間隔は sleep にて設定
sub search_retry {
   my ($search_keyword, $since_id) = @_;   
   while ( $retry_count != $retry ) {
      eval { my $r = $t->search({q => $search_keyword, count => $count, since_id => $since_id}); };
      if ($@){
         $retry_count += 1;
         sleep 5;
         print "$retry_count\n";
         print "$@\n";
      } else {
         last;
      }
   }
}

# $count より件数が多かった場合、max_id を書き換えて再度 since_id まで search する
sub search_in_turn {
   my ($search_keyword, $max_id, $since_id) = @_;
   while( $max_id >= $since_id ){
      my $r2 = $t->search({q => $search_keyword, count => $count, max_id => $max_id, since_id => $since_id});
      $num += scalar @{$r2->{statuses}};
      $last_id = pop @{$r2->{statuses}};
      $max_id = $last_id->{id} - 1;
   }
}

# リトライ処理
sub post_retry {
   my ($post) = @_;
   while ( $retry_count != $retry ) {
      eval { $status = $t->update({ status => $post }); };
      if ($@){
         $retry_count += 1;
         sleep 5;
      } else {
         last;
      }
   }
}

sub daily_post {
   my ($daily_post) = @_;
   open (FILE, "$count_file") or die "$!";
   while(<FILE>){
      $yesterday_num += $_;
   }
   close(FILE);
   eval { $status = $t->update({ status => $daily_post }); };
}

# $retry 回失敗したらログに書き出す
sub abort {
    my ($log_file) = @_;
    open (FILE, ">>$log_file") or die "$!";
    print FILE "$now $@\n";
    close(FILE);
    #`echo "$now , $0 Failed." | /bin/mail -s "[Error] $0 Failed" tkdyk88\@gmail.com`;
    exit 2;
}
########## サブルーチン群のおわり ##########

########## 本体 ##########

# 前回の max_id を読み込む
open (FILE, $quit_id_file) or die "$!";
$quit_since_id = <FILE>;
close(FILE);

# 取り敢えず $count 件検索する
my $r;
eval { $r = $t->search({q => $quit_search_keyword, count => $count, since_id => $quit_since_id}); };

# $t->search が失敗していたら &search_retry を呼び出す
if($@){ &search_retry($quit_search_keyword, $quit_since_id); };

# $retry 回失敗したら &abort を呼び出す
if($retry_count == $retry){ &abort($quit_log_file); };

# max_id を取得し、外部ファイルに格納。これは次回実行時の since_id になる
$quit_max_id = $r->{search_metadata}->{max_id};
open (FILE, ">$quit_id_file") or die "$!";
print FILE $quit_max_id;
close(FILE);

# 辞めた人数を $num に格納
$num = scalar @{$r->{statuses}};

# $count 分入手した tweet の最後の ID -1 を入手
$last_id = pop @{$r->{statuses}};

# ID -1 が since_id より大きい場合、$count を超えた tweet が存在するので、繰り返す
# tweet 数は $num に格納する
$quit_max_id = $last_id->{id} - 1;
&search_in_turn($quit_search_keyword, $quit_max_id, $quit_since_id);

# $num をファイルに格納する。
open (FILE, ">>$count_file") or die "$!";
print FILE "$num\n";
close(FILE);

# POST する
$quit_hour_post = sprintf $quit_hour_post_pattern,$hour_1,$hour,$num;
eval { $status = $t->update({ status => $quit_hour_post }); };

# $t->search が失敗していたら &search_retry を呼び出す
# retry, retry_count を再利用するため初期化する
$retry = 3;
$retry_count = 0;
if($@){ &post_retry($quit_hour_post); }

# $retry 回失敗したらログに書き出す
if($retry_count == $retry){ &abort($quit_log_file); }

# hour が 0 だったら、前日分の総計を POST する
if ($hour == 0){
   ##### 前日辞めた人数の POST #####
   open (FILE, "$count_file") or die "$!";
   while(<FILE>){
      $yesterday_num += $_;
   }
   close(FILE);
   $quit_daily_post = sprintf $quit_daily_post_pattern,$mon_1,$mday_1,$yesterday_num;
   eval { $status = $t->update({ status => $quit_daily_post }); };

   # $t->update が失敗していたら &post_retry を呼び出す
   # retry, retry_count を再利用するため初期化する
   $retry = 3;
   $retry_count = 0;
   if($@){ &post_retry($quit_daily_post); }

   # $retry 回失敗したらログに書き出す
   if($retry_count == $retry){ &abort($quit_log_file); }

   # 0 時更新時は count_file を上書き
   open (FILE, ">$count_file") or die "$!";
   print FILE "";
   close(FILE);

   ##### 解体した人数を検索 #####
   eval { $r = $t->search({q => $destroy_search_keyword, count => $count, since_id => $destroy_since_id}); };
   
   # $t->search が失敗していたら &search_retry を呼び出す
   if($@){ &search_retry($destroy_search_keyword, $destroy_since_id); };
   
   # $retry 回失敗したら &abort を呼び出す
   if($retry_count == $retry){ &abort($destroy_log_file); };
   
   # max_id を取得し、外部ファイルに格納。これは次回実行時の since_id になる
   $destroy_max_id = $r->{search_metadata}->{max_id};
   open (FILE, ">$destroy_id_file") or die "$!";
   print FILE $destroy_max_id;
   close(FILE);
   
   # 解体した人数を $num に格納
   $num = scalar @{$r->{statuses}};
   
   # $count 分入手した tweet の最後の ID -1 を入手
   $last_id = pop @{$r->{statuses}};
   
   # ID -1 が since_id より大きい場合、$count を超えた tweet が存在するので、繰り返す
   # tweet 数は $num に格納する
   $quit_max_id = $last_id->{id} - 1;
   &search_in_turn($destroy_search_keyword, $destroy_max_id, $destroy_since_id);

   # 前日解体した人数の POST
   $destroy_daily_post = sprintf $destroy_daily_post_pattern,$mon_1,$mday_1,$num;
   eval { $status = $t->update({ status => $destroy_daily_post }); };

   # $t->update が失敗していたら &post_retry を呼び出す
   # retry, retry_count を再利用するため初期化する
   $retry = 3;
   $retry_count = 0;
   if($@){ &post_retry($destroy_daily_post); }

   # $retry 回失敗したらログに書き出す
   if($retry_count == $retry){ &abort($destroy_log_file); }
}
