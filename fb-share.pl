#!/usr/bin/perl -w

# fb-share.pl version 0.1

use strict;
$| = 1;
use utf8;
use open qw/:std :utf8/;

use Getopt::Long;
GetOptions(
    "host=s" => \(my $mysql_host = '127.0.0.1'),
    "port=s" => \(my $mysql_port = 3306),
    "user=s" => \(my $mysql_user = 'root'),
    "pass=s" => \(my $mysql_pass = ''),
    "db=s" => \(my $mysql_database = 'facebook'),
    "tables=s" => \(my $mysql_tables = 'info:wall:friends'),
    "info=s" => \(my $info_save_method = 'append'),
    "url=s" => \(my $fb_user_urls),
    "name=s" => \(my $fb_user_names),
    "timeout=i" => \(my $timeout = 30),
    "i" => \(my $save_info),
    "w" => \(my $save_wall),
    "f" => \(my $save_friends),
    "h" => \(my $help),
    "new" => \(my $new_only),
    "old" => \(my $old_only),
    "plugins=s" => \(my $plugins),
    "proxy=s" => \(my $proxy)
);

usage() if defined($help);

sub usage {
	print "usage: ./fb-share.pl -i -w -f\n";
	print "  -host      mysql host (default: localhost)\n";
	print "  -port      mysql port (default: 3306)\n";
	print "  -user      mysql user (default: root)\n";
	print "  -pass      mysql password\n";
	print "  -db        mysql database (default: facebook)\n";
	print "  -tables    mysql tables (default: info:wall:friends)\n";
	print "  -info      user info save method. (append, insert, replace) (default: append)\n";
	print "  -i         crawl user information\n";
	print "  -w         crawl user wall posts\n";
	print "  -f         crawl user friends\n";
	print "  -proxy     host[:port]\n";
	print "  -timeout   timeout in seconds (default: $timeout)\n";
	print "  -new       only crawl users that aren't in the database\n";
	print "  -old       only crawl users that are in the database\n";
	print "  -plugins   plugins to include. see readme.\n";
	print "  -h         help\n";
    exit();
}

use DBI;
print "+ Connecting to $mysql_user\@$mysql_host on port $mysql_port\n";
my $dbh = DBI->connect("DBI:mysql:database=information_schema;host=$mysql_host;port=$mysql_port", $mysql_user, $mysql_pass) or die($@);
my $query;
$dbh->{'mysql_enable_utf8'} = 1;
$query = $dbh->prepare("CREATE DATABASE IF NOT EXISTS `$mysql_database` CHARACTER SET utf8 COLLATE utf8_general_ci")->execute or die($@);

sub check_table_exists {
    foreach my $table_name ($_[0]) {
        $query = $dbh->prepare("SELECT * FROM information_schema.TABLES WHERE `TABLE_SCHEMA`='$mysql_database' AND `TABLE_NAME`='$table_name'");
        $query->execute;
        if ($query->rows == 0) {
            print " + Creating table \"$table_name\"\n";
            my $extra_sql = '';
            if ($_[1] eq 'wall') {
                $extra_sql = ', `post` TEXT NOT NULL, `post_search` TEXT NOT NULL'
            }
            if ($_[1] eq 'friends') {
                $extra_sql = ', `friends` TEXT NOT NULL'
            }
            $query = $dbh->prepare("CREATE TABLE `$mysql_database`.`$table_name` (`id` INT(8) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `crawled_by` VARCHAR(250) NOT NULL, `user_id` BIGINT(20) UNSIGNED NOT NULL, `user_name` VARCHAR(250) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL, `date` DATETIME NOT NULL $extra_sql) ENGINE = MYISAM DEFAULT CHARSET=utf8 COLLATE utf8_general_ci")->execute or die($@);
        }else{
            print " | Table \"$table_name\" exists\n";
        }
    }
}

print "+ Checking Tables\n";
my ($mysql_info_table, $mysql_wall_table, $mysql_friends_table) = split(/:/, $mysql_tables);
check_table_exists($mysql_info_table, 'info') if (defined($save_info));
check_table_exists($mysql_wall_table, 'wall') if (defined($save_wall));
check_table_exists($mysql_friends_table, 'friends') if (defined($save_friends));

if (!defined($save_wall) and !defined($save_friends) and !defined($save_info)) {
    $save_info = 1;
}

use threads;
use threads::shared;
use Thread::Queue;
use Time::HiRes qw(usleep);
use Fcntl;
use HTML::Entities;
use URI::Escape;
use POSIX qw/strftime/;
use LWP::UserAgent;
use LWP::Protocol::https;

no strict "refs";
my @plugin_functions;
if (defined($plugins)) {
	print "+ Loading Plug-ins\n";
	foreach my $plugin (split(/,/, $plugins)) {
		my $plugin_file = $plugin;
		if (! -e $plugin_file) {
			if (-e 'plugins/'.$plugin_file) {
				$plugin_file = 'plugins/'.$plugin_file;
			}else{
				print " ! $plugin not found\n";
				next;
			}
		}
		require($plugin_file);
		print " + Loaded $plugin\n";
		if (rindex($plugin, '.') > -1) {
			push(@plugin_functions, substr($plugin, 0, rindex($plugin, '.')));
		}else{
			push(@plugin_functions, $plugin);
		}
	}
}

sub trim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

my ($response, $error, $istart, $iend);
my $ua = LWP::UserAgent->new;
$ua->cookie_jar({});
$ua->agent('Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20120405 Firefox/14.0a1');
$ua->default_header('Accept-Language' => "en,en-us;q=0.5");
$ua->timeout($timeout);
$ua->max_redirect(5);

if (defined($proxy)) {
	$ua->proxy(['http'], 'http://'.$proxy.'/');
	$response = $ua->get('http://ip.appspot.com/');
	if ($response->is_success) {
		print '+ IP Address: '.$response->decoded_content;
	}else{
		print "! Error: Can't connect to proxy at $proxy\n";
		exit;
	}
}

use IO::Uncompress::Unzip qw(unzip $UnzipError);
$response = $ua->get('https://anonfiles.com/archive')->decoded_content;
my @matches = $response =~ m/<a (href="[^\"]+" title="fb-crawl[^\"]+")/g;
for my $match (@matches) {
	my @file_info = $match =~ m/href="([^\"]+)" title="([^\"]+)"/;
	$response = $ua->get($file_info[0])->decoded_content;
	$response =~ m/<a href="([^\"]+)" class="download_button"/;
	print "+ Found: $1\n";
	my $filename = '/tmp/'.$file_info[1].'.zip';
	open(FILE, '>:raw', $filename);
	print FILE $ua->get($1)->decoded_content;
	close(FILE);
	unzip $filename => \(my $output) or die("! Failed to unzip: $UnzipError");
	unlink($filename);
	my $table_name;
	my $table = join('', $output =~ m/table: ([^\n]+)/);
	if ($table eq 'info') {
		$table_name = $mysql_info_table;
	}elsif ($table eq 'wall') {
		$table_name = $mysql_wall_table;
	}elsif ($table eq 'friends') {
		$table_name = $mysql_friends_table;
	}
	my @table_columns = split(/,/ ,$output =~ m/table-columns: ([^\n]+)/);
	
	$query = $dbh->prepare("SELECT `COLUMN_NAME` FROM `information_schema`.COLUMNS WHERE `TABLE_SCHEMA`='$mysql_database' AND `TABLE_NAME`='$table_name'");
	$query->execute or die($@);
	my @mysql_columns;
	while (my @row = $query->fetchrow_array()) {
		push(@mysql_columns, $row[0]);
	}
	my $column_attr = 'TEXT CHARACTER SET utf8 COLLATE utf8_general_ci';
	foreach my $column_name (@table_columns) {
		if (!grep {$_ eq $column_name} @mysql_columns) {
			print "+ Adding column \"$column_name\" to $mysql_database.$table_name\n";
			$query = $dbh->prepare("ALTER TABLE `$mysql_database`.`$table_name` ADD `$column_name` $column_attr;");
			$query->execute();
		}
	}
}
