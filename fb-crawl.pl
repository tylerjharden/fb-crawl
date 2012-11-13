#!/usr/bin/perl -w

# fb-crawl.pl version 0.1

use strict;
$| = 1;
use utf8;
use open qw/:std :utf8/;

use Getopt::Long;
GetOptions(
    "u=s" => \(my $fb_user_email),
    "p=s" => \(my $fb_user_pass),
    "host=s" => \(my $mysql_host = '127.0.0.1'),
    "port=s" => \(my $mysql_port = 3306),
    "user=s" => \(my $mysql_user = 'root'),
    "pass=s" => \(my $mysql_pass = ''),
    "db=s" => \(my $mysql_database = 'facebook'),
    "tables=s" => \(my $mysql_tables = 'info:wall:friends'),
    "info=s" => \(my $info_save_method = 'append'),
    "share" => \(my $share_results),
    "t=i" => \(my $thread_count = 16),
    "url=s" => \(my $fb_user_urls),
    "name=s" => \(my $fb_user_names),
    "timeout=i" => \(my $timeout = 30),
    "w" => \(my $save_wall),
    "i" => \(my $save_info),
    "f" => \(my $save_friends),
    "self" => \(my $save_self),
    "h" => \(my $help),
    "mutual=i" => \(my $mutual = 0),
    "new" => \(my $new_only),
    "old" => \(my $old_only),
    "plugins=s" => \(my $plugins),
    "https" => \(my $https),
    "depth=i" => \(my $crawl_depth = 0),
    "proxy=s" => \(my $proxy)
);

usage() if defined($help) || !defined($fb_user_email);

sub usage {
	print "usage: ./fb-crawl.pl -u email\@address -i -w -f\n";
	print "  -u         email address\n";
	print "  -p         password\n";
	print "  -host      mysql host (default: localhost)\n";
	print "  -port      mysql port (default: 3306)\n";
	print "  -user      mysql user (default: root)\n";
	print "  -pass      mysql password\n";
	print "  -db        mysql database (default: facebook)\n";
	print "  -tables    mysql tables (default: info:wall:friends)\n";
	print "  -info      user info save method. (append, insert, replace) (default: append)\n";
	print "  -share     anonymously share crawl results\n";
	print "  -i         crawl user's information\n";
	print "  -w         crawl user's wall posts\n";
	print "  -f         crawl user's friends\n";
	print "  -self      crawl your profile too\n";
	print "  -t         threads (default: 16)\n";
	print "  -https     use ssl encryption\n";
	print "  -proxy     host[:port]\n";
	print "  -timeout   timeout in seconds (default: $timeout)\n";
	print "  -depth     crawl depth (default: 0)\n";
	print "              0 - only your friends\n";
	print "              1 - friends of friends\n";
	print "              2 - friends of friends of friends\n";
	print "              3 - friendception\n";
	print "  -url       start on these url(s)\n";
	print "              example: -url http://fb.com/profile.php?id=12345,profile.php?id=54321,john.smith.3\n";
	print "  -name      start on these people\n";
	print "              example: -name \"John Smith, Jane Smith\"\n";
	print "  -mutual    only crawl users that have at least n mutual friends\n";
	print "  -new       only crawl users that aren't in the database\n";
	print "  -old       only crawl users that are in the database\n";
	print "  -plugins   plugins to include. see readme.\n";
	print "  -h         help\n";
    exit();
}

sub die_report {
	die($_[0]."! Please report errors to https://code.google.com/p/fb-crawl/issues/\n");
}


#
# Initiate the MySQL database
#
use DBI;
print "+ Connecting to $mysql_user\@$mysql_host on port $mysql_port\n";
my $dbh = DBI->connect("DBI:mysql:database=information_schema;host=$mysql_host;port=$mysql_port", $mysql_user, $mysql_pass) or die_report($@);
my $query;
$dbh->{'mysql_enable_utf8'} = 1;
$query = $dbh->prepare("CREATE DATABASE IF NOT EXISTS `$mysql_database` CHARACTER SET utf8 COLLATE utf8_general_ci")->execute or die_report($@);

sub check_table_exists {
    foreach my $table_name ($_[0]) {
        $query = $dbh->prepare("SELECT * FROM information_schema.TABLES WHERE `TABLE_SCHEMA`='$mysql_database' AND `TABLE_NAME`='$table_name'");
        $query->execute;
        if ($query->rows == 0) {
            print " + Creating table \"$table_name\"\n";
            my $extra_sql = '';
            if ($_[1] eq 'wall') {
                $extra_sql = ', `post` TEXT NOT NULL, `post_search` TEXT NOT NULL, `location` VARCHAR(50) NULL';
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

# Create tables if they don't exist
print "+ Checking Tables\n";
my ($mysql_info_table, $mysql_wall_table, $mysql_friends_table) = split(/:/, $mysql_tables);
check_table_exists($mysql_info_table, 'info') if (defined($save_info));
check_table_exists($mysql_wall_table, 'wall') if (defined($save_wall));
check_table_exists($mysql_friends_table, 'friends') if (defined($save_friends));

#
# load all user information columns into @info_table_columns
#
my @info_table_columns :shared;
$query = $dbh->prepare("SELECT `COLUMN_NAME` FROM `information_schema`.COLUMNS WHERE `TABLE_SCHEMA`='$mysql_database' AND `TABLE_NAME`='$mysql_info_table'");
$query->execute or die_report($@);
$query->bind_columns(\(my $column_name));
while ($query->fetch()) {
    push(@info_table_columns, $column_name);
}

if (!defined($save_wall) and !defined($save_friends) and !defined($save_info)) {
    print "! Please select a crawl option (-i, -w, -f). Info, wall, and friends respectively.\n";
    exit;
}

use Time::HiRes qw(usleep);
use Fcntl;
use HTML::Entities;
use URI::Escape;
use POSIX qw/strftime/;
use LWP::UserAgent;
if (defined($https)) {
    use LWP::Protocol::https;
}

#
# Load any -plugins
#
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

# trims whitespaces from ends of string
sub trim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

#
# Initiate LWP::UserAgent
#
my $ua = LWP::UserAgent->new;
$ua->cookie_jar({});
$ua->agent('Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20120405 Firefox/14.0a1');
$ua->default_header('Accept-Language' => "en,en-us;q=0.5");
$ua->timeout($timeout);
$ua->max_redirect(5);
if (defined($https)) {
	$ua->ssl_opts(verify_hostnames => 0);
}

my $response;

# Checks the -proxy and prints the apparent IP Address
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

#
# Request Facebook password if -p not set
#
if (!defined($fb_user_pass)) {
	print '? Facebook Password: ';
	system('stty','-echo');
	chomp($fb_user_pass=<STDIN>);
	system('stty','echo');
	print "\n";
}

#
# Log in to Facebook
#
$response = $ua->get('http://www.facebook.com/')->decoded_content;
if (index($response, '<input value="Log In"') > -1) {
	print "+ Logging in...";
	push @{ $ua->requests_redirectable }, 'POST';
	$response = $ua->post('http'.(defined($https)?'s':'').'://www.facebook.com/login.php?login_attempt=1', { email => $fb_user_email, pass => $fb_user_pass });
	$response = $response->decoded_content;
	print "done\n";
}else{
	print "+ Using previous session cookies\n";
}


#
# Check for any login issues
#
if (index($response, 'login_error_box') > -1) {
    my $error = $1 if $response =~ /login_error_box[^>]+>(.*?)<\/div>/;
    $error =~ s|</h2>|: |g;
    $error =~ s|<.+?>| |g;
    $error =~ s/\s+/\ /g;
    $error = trim($error);
    print "! Error: $error\n";
    exit;
}

#
# Parse User ID
#
my $fb_user_id = $1 if $response =~ /envFlush\(\{"user"\:"([0-9]+)"/;

#
# Parse User Name
#
my $istart = index($response, '<span class="headerTinymanName"');
$istart = index($response, '<a class="fbxWelcomeBoxName"') if ($istart < 0);
$istart = index($response, '>', $istart)+1;
my $iend = index($response, '</', $istart);
my $fb_user_name = substr($response, $istart, $iend-$istart);


#
# Initiate Threads
#
my $start_time = time();
my @scanned_uids;
my @users;
my @threads;
use threads;
use Thread::Queue;
my $q = Thread::Queue->new();
push(@threads, threads->create(\&crawl_user)) for (1..($thread_count-1));


#
# $ua->get with added functionality to detect Facebook errors
#
sub http_request {
    my $tries = 0;
    my $success = 0;
	if (defined($https)) {
		$_[0] =~ s/http:/https:/;
	}
    while (!$success && $tries < 2) {
        $response = $ua->get($_[0]);
        $success = $response->is_success;
        $tries++;
    }
    $response = $response->decoded_content;
	if (index($response, '<title>Content Not Found</title>') > -1 or index($response, '<title>Page Not Found</title>') > -1) {
		$response = 'Page Not Found.';
		$success = 0;
	}
	if (index($response, '<h1>Sorry, something went wrong.</h1>') > -1) {
		$response = 'Sorry, something went wrong.';
	}
	if (index($response, '<div id="error"') > -1) {
		my $error = $1 if $response =~ /<div id="error">(.*?)<\/div>/;
		$error =~ s|</h2>|: |g;
		$error =~ s|<.+?>| |g;
		$error =~ s/\s+/\ /g;
		$error = trim($error);
		print $error."\n";
		self_destruct();
	}
	if (index($response, 'Log In') > -1) {
		print "! Error: you're not logged in\n";
		self_destruct();
	}
    if ($success) {
		return $response;
    }else{
        print '! Request Failed: '.$_[0].' - '.$response."\n";
        return 0;
    }
}

#
# Converts a string like 'Yesterday at 4:30pm' to MySQL DATETIME (YYYY-MM-DD HH:MM:SS) format.
#
sub strtodate {
    my $date = lc($_[0]);
    if ($date eq 'just now') {
        return strftime("%Y-%m-%d %H:%M:00", localtime(time));
    }
    if ($date =~ m/([0-9]+) minutes? ago/) {
        return strftime("%Y-%m-%d %H:%M:00", localtime(time-(($1*1)*60)));
    }
    if ($date =~ m/([0-9]+) hours? ago/) {
        return strftime("%Y-%m-%d %H:%M:00", localtime(time-(($1*1)*3600)));
    }
    if ($date =~ m/([0-9]+) days? ago/) {
        return strftime("%Y-%m-%d %H:%M:00", localtime(time-(($1*1)*86400)));
    }
    my @months = ('january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december');
    my @days = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday');
    $date =~ m/^([a-z]+) ([0-9]{1,2})?/;
    my $month;
    my $day;
    if (!defined($2)) {
        $month = strftime("%m", localtime(time));
        if ($1 eq 'today') {
            $day = strftime("%d", localtime(time));
        }elsif ($1 eq 'yesterday') {
            $day = strftime("%d", localtime(time-86400));
        }else{ 
            for (my $i = 0; $i < 7; $i++) {
                if (index($days[$i], $1) == 0) {
                    $day = $i;
                    last;
                }
            }
            for (my $time = time;; $time = $time-86400) {
                if (strftime("%w", localtime($time)) == $day) {
                    $day = strftime("%d", localtime($time));
                    last;
                }
            }
        }
    }else{
        for (my $i = 0; $i < 12; $i++) {
            if (index($months[$i], $1) == 0) {
                $month = $i+1;
                last;
            }
        }
        $day = $2;
    }
    if (length($month) == 1) {
        $month = '0'.$month;
    }
    if (length($day) == 1) {
        $day = '0'.$day;
    }
    my $time = '';
    $date =~ m/ at ([0-9]{1,2})\:([0-9]{1,2})([a-z]{2})/;
    if (defined($1) && defined($2) && defined($3)) {
        my $hour = $1*1;
        if ($3 eq 'pm' && $hour < 12) {
            $hour = $hour+12;
        }elsif (length($hour) == 1) {
            $hour = '0'.$hour;
        }
        $time = $hour.':'.$2.':00';
    }else{
        $time = '00:00:00';
    }
    my $year;
    if ($date =~ m/([0-9]{4})/) {
        $year = $1;
    }else{
        $year = strftime("%Y", localtime());
    }
    return $year.'-'.$month.'-'.$day.' '.$time;
}


#
# Gets all the user's friends and sends them to the crawl_user() thread
#
sub find_friends {
    my ($current_name, $html);
	foreach my $scanned_uid (@scanned_uids) {
		if ($scanned_uid eq $_[0]) {
			return;
		}
	}
	$current_name = $_[1]."'s";
    push(@scanned_uids, $_[0]);
    print '+ Loading '.$current_name.' friends. User ID: '.$_[0]."\n";
    
    my $friends_found = 0;
	my @user_friends;
    for (my $start = 0, my $i = 0; 1; $start = $start+24, $i++) {
        my $response = http_request('http://www.facebook.com/ajax/browser/list/allfriends/?uid='.$_[0].'&infinitescroll=1&location=friends_tab_tl&start='.$start.'&__user='.$fb_user_id.'&__a=1');
        $istart = index($response, 'appendContent');
		if ($istart < 0) {
			$response =~ /"errorSummary":"([\"]+)"/;
			print "Error: $1\n" if defined($1);
			last;
		}
		if (index($response, 'No results found.') > -1) {
			print "! Error: Couldn't get friends.\n";
			last;
		}
        $istart = index($response, '"__html":', $istart)+9;
        $istart = index($response, '"', $istart)+1;
        $iend = index($response, '"}', $istart);
        $html = substr($response, $istart, $iend-$istart);
        if ($html eq '') {
            last;
        }
        $html =~ s/\\"/"/g;
        $html =~ s/\\u003C/</g;
        $html =~ s/\\\//\//g;
        my ($name, $uri, $id);
        while ($html =~ m/<a href="https?:\/\/www.facebook.com\/([^\"]+)" data-hovercard="[^\?]+\?id=([0-9]+)">([^<]+)<\/a>/g) {
            if ($2 eq $_[0] || $2 eq $fb_user_id) {
                next;
            }
            if (grep {$_[0] eq $2} @users) {
                next;
            }
            $id = $2;
            $uri = $1;
            $name = $3;
            $name = decode_entities($name);
            $name =~ s/\\u([A-Za-z0-9]{4})/pack("U4", hex($1))/eg;
			$name =~ s/[\ ]{2,}/ /g;
			if (defined($save_friends)) {
				push(@user_friends, $name);
			}
            push(@users, [$id, $name, 'http://m.facebook.com/'.$uri]);
			if (defined($save_wall) || defined($save_info)) {
				$q->enqueue("$id,$name,http://m.facebook.com/$uri");
			}
            $friends_found++;
        }
    }
	if (defined($save_friends)) {
		$query = $dbh->prepare("SELECT `friends` FROM `$mysql_database`.`$mysql_friends_table` WHERE `user_id`='".$_[0]."'");
		$query->execute;
		my @user_new_friends;
		my @user_current_friends;
		if ($query->rows > 0) {
			while (my $friends = $query->fetchrow_array) {
				push(@user_current_friends, split(/, /, $friends));
			}
			foreach my $friend (@user_friends) {
				if (!grep(/^$friend$/, @user_current_friends)) {
					push(@user_new_friends, $friend);
				}
			}
		}else{
			@user_new_friends = @user_friends;
		}
		if (@user_new_friends > 0) {
			print " + Saving $current_name friends - ".@user_new_friends." inserted\n";
			$query = $dbh->prepare("INSERT INTO `$mysql_database`.`$mysql_friends_table` (`crawled_by`, `user_id`, `user_name`, `date`, `friends`) VALUES (?, ?, ?, ?, ?)");
			$query->execute($fb_user_email, $_[0], $_[1], strftime("%Y-%m-%d %H:%M:%S", localtime(time)), join(', ', @user_new_friends));
		}
	}
    while ($q->pending()) {
        sleep 1;
    }
    usleep(100000) for (0..$#threads);
}


#
# Gets a user's name and id from the given URI
#
sub get_user {
    my $url = 'http://m.facebook.com/'.$_[0];
    my $response = http_request($url);
    
    $istart = index($response, '<title');
    $istart = index($response, '>', $istart)+1;
    $iend = index($response, '</title', $istart);
    my $name = decode_entities(substr($response, $istart, $iend-$istart));
    
    $istart = index($response, ';id=')+4;
    $iend = index($response, '&', $istart);
    my $id = substr($response, $istart, $iend-$istart);
	
	push(@users, [$id, $name, $url]);
    $q->enqueue("$id,$name,$url");
	
	if ($crawl_depth > 0 || $id == $fb_user_id) {
		find_friends($id, $name);
	}
}

#######################
#                     #
#  Crawl User Thread  #
#                     #
#######################
sub crawl_user {
	
    my ($query, $response);
    
	# Initiate a MySQL instance for this thread
	my $dbh_thread = DBI->connect("DBI:mysql:database=information_schema;host=$mysql_host;port=$mysql_port", $mysql_user, $mysql_pass) or die('$@');
    $dbh_thread->{'mysql_enable_utf8'} = 1;
	
    while (my $args = $q->dequeue()) {
        
		# kill thread if sent a death signal
		last if ($args eq 'die');
		
        my ($id, $name, $url) = split(/,/, $args);
        
		#
		# This checks the amount of -mutual friends by requesting the user's Info page
		#
		my $info_response;
		if ($mutual > 0) {
            $info_response = http_request($url.((index($url, '?') > -1) ? '&' : '?').'v=info');
			if (index($info_response, 'Add Friend</a>') > -1) {
				$info_response =~ /Mutual Friends \(([0-9]+)\)/;
				next if (!defined($1));
				next if ($1*1 < $mutual); # convert string to int and break if less than -mutual
			}
		}
		
		#########################
		#                       #
		#  GET USER WALL POSTS  #
		#                       #
		#########################
		WALL:
        if (defined($save_wall)) {
			
			#
			# Later we will need to check if we already have a post and break
			# so we fill an array with the 5 latest posts from the user
            #
            my @latest_posts;
            $query = $dbh_thread->prepare("SELECT `date`,`post` FROM `$mysql_database`.`$mysql_wall_table` WHERE `user_id`='$id' ORDER BY `date` DESC LIMIT 0, 5");
            $query->execute or die_report($@);
            $query->bind_columns(\(my $date), \(my $post));
			while ($query->fetch()) {
                push(@latest_posts, $date.$post);
            }
			
			#
			# If we've crawled the user before and we only want new users, skip to INFO crawl
			# If we've never crawled the user before and we only want old users, skip to INFO crawl
			#
			goto INFO if (($query->rows > 0 and defined($new_only)) || ($query->rows == 0 and defined($old_only)));
			
			print ' - '.$name.(' ' x (27-length($name))).$id.(' ' x (20-length($id)))."wall posts : starting\n";
			my $last_post = '';
			my $inserted_posts = 0;
			my $response = http_request('http://m.facebook.com/wall.php?id='.$id); # get first wall page
			
			PAGE: while(1) {
				
				#
				# Parse each wall post
				#
				while ($response =~ m/<div[^>]*? class="msg[^>]+>(.*?)<\/div><div[^>]*? class="actions[^>]+>.*?<abbr>([^<]+)<\/abbr>( (near|in|at) ([^<]+))?/g) {
					
					# set variables from regex match
					my $post = $1;
					my $date = strtodate($2);
					my $location = '';
					$location = trim(decode_entities($5)) if (defined($5));
					
					# sanitize post
					$post = decode_entities($post);
					$post =~ s/<\/?br\ ?\/?>/ -> /;
					$post =~ s/<\/?br\ ?\/?>/ /g;
					$post =~ s|<.+?>||g;
					$post =~ s/[\ ]{2,}/ /g;
					$post = trim($post);
					
					# split post into unique lowercase words for searching purposes
					my $post_search = lc($post);
					$post_search =~ s/[^a-z0-9\ ]+/ /g;
					$post_search =~ s/[\ ]{2,}/ /g;
					$post_search = join(' ', keys %{{ map { $_ => 1 } split(/ /, trim($post_search)) }});
					
					# make sure post isn't empty and that it's not the same as $last_post
					if ($post ne '' && $date.$post_search ne $last_post) {
						
						# make sure we don't already have that post
						if (!grep {$_ eq $date.$post} @latest_posts) {
							$inserted_posts++;
							$query = $dbh_thread->prepare("INSERT INTO `$mysql_database`.`$mysql_wall_table` (`crawled_by`, `user_id`, `user_name`, `date`, `location`, `post`, `post_search`) VALUES (?,?,?,?,?,?,?)");
							$query->execute($fb_user_email, $id, $name, $date, $location, $post, $post_search);
						}else{
							# if we do already have that post, we will have any posts after that, so we break.
							last PAGE;
						}
					}
					$last_post = $date.$post_search;
				}
				
				#
				# Check for next page and request it
				#
				my $istart = index($response, 'id="m_more_item');
				last if ($istart < 0); # break if no more pages
				$istart = index($response, 'href="', $istart)+6; # get URL of next page
				my $iend = index($response, '"', $istart);
				$response = http_request('http://m.facebook.com'.decode_entities(substr($response, $istart, $iend-$istart))); # fetch next page
			}
			
			#
			# WALL POSTS finished. print results.
			#
			print ' - '.$name.(' ' x (27-length($name))).$id.(' ' x (20-length($id)))."wall posts : $inserted_posts inserted\n";
		}
        
		##########################
		#                        #
		#  GET USER INFORMATION  #
		#                        #
		##########################
		INFO:
        if (defined($save_info)) {
			
			# Get current user information out of the database
            $query = $dbh_thread->prepare("SELECT * FROM `$mysql_database`.`$mysql_info_table` WHERE `user_id`='$id'");
            $query->execute or die_report($@);
			
			#
			# If we've crawled the user before and we only want new users, skip current user
			# If we've never crawled the user before and we only want old users, skip current user
			#
			next if (($query->rows > 0 and defined($new_only)) || ($query->rows == 0 and defined($old_only)));
			
			my $row = $query->fetchrow_hashref;
            my %current_user; # contains current user info
			
			#
			# If we already got the user's Info page from the mutual friend check
			# then we use that response instead of requesting it again.
			#
			if (defined($info_response)) {
				$response = $info_response;
			}else{
				$response = http_request($url.((index($url, '?') > -1) ? '&' : '?').'v=info');
			}
			
            $response =~ s/\r|\n//g; # strip newlines from the response for more reliable parsing
			
			#
			# Parses all user information
			#
			# Example: <div class="mfsm">Profile:</div><div class="mfsm"><a href="/mark.zuckerberg">facebook.com/mark.zuckerberg</a></div>
			# 
			# $field = "profile";
			# $value = "facebook.com/mark.zuckerberg";
			#
            while ($response =~ m/<div class="mfsm[^>]+>([^:]+):<\/div>((?!<div).)*<div class="mfsm[^>]+>(((?!<div).)*)<\/div>/g) {
				my $field = $1;
				my $value = $3;
                $field = lc($1);
                $field =~ s|<.+?>||g;
                $field =~ s/[^a-z]/_/g;
                $field =~ s|[_]{2,}|_|g;
                my @values = $value =~ /<a[^>]+>([^<]+)<\/a>/g;
                
                $values[0] = $value if (@values < 2);
                for (my $i = 0; $i < @values; $i++) {
                    $values[$i] =~ s|<.+?>| |g;
                    $values[$i] =~ s|[\ ]{2,}| |g;
                    $values[$i] = trim(decode_entities($values[$i]));
                }
                
                if ($info_save_method ne 'replace' && defined($$row{$field})) {
                    foreach my $value (@values) {
                        if (!grep {$_ eq $value} split(/\n/, $$row{$field})) {
                            $current_user{$field} .= $value."\n";
                        }
                    }
                }else{
                    $current_user{$field} .= join("\n", @values)."\n";
                }
            }
			
			#
			# Append new info with old info if -info == append
			#
			if ($info_save_method eq 'append') {
				%current_user = map {
					$_ => ((defined($$row{$_}))?$$row{$_}.',':'').$current_user{$_}
				} keys %current_user;
			}
			
			# Split information with multiple entries by "\n"
            %current_user = map { $_ => join("\n", split(/\n/, $current_user{$_})) } keys %current_user;
            
			#
			# Send user information to plugins
			#
			foreach my $plugin (@plugin_functions) {
				&$plugin(\%current_user);
			}
			
			#
			# Create any new columns
            #
			foreach my $attr (keys %current_user) {
                lock(@info_table_columns);
				my $column_attr = 'TEXT CHARACTER SET utf8 COLLATE utf8_general_ci';
				my $column = $attr;
				if (index($column, ':') > -1) {
					$column_attr = substr($column, index($column, ':')+1);
					$column = substr($column, 0, index($column, ':'));
					$current_user{$column} = $current_user{$attr};
					delete($current_user{$attr});
				}
				if (!grep {$_ eq $column} @info_table_columns) {
					push(@info_table_columns, $column);
					print "+ Adding column \"$column\" to $mysql_database.$mysql_info_table\n";
					$query = $dbh_thread->prepare("ALTER TABLE `$mysql_database`.`$mysql_info_table` ADD `$column` $column_attr;");
					$query->execute();
				}
            }
			
			#
			# INSERT or UPDATE user information depending on -info option
			#
            if (join('', values %current_user) ne '') {
				my $done_str = 'done';
				if ($info_save_method eq 'insert' || $query->rows == 0) {
					my $info_columns = join(', ', (map { "`$_`" } keys %current_user));
					my $info_values = join(', ', map { '?' } keys %current_user);
					$query = $dbh_thread->prepare("INSERT INTO `$mysql_database`.`$mysql_info_table` (`crawled_by`, `user_id`, `user_name`, `date`, $info_columns) VALUES (?, ?, ?, ?, $info_values)");
					$query->execute($fb_user_email, $id, $name, strftime("%Y-%m-%d %H:%M:%S", localtime(time)), values %current_user);
					$done_str = 'inserted';
				}else{
					my $info_columns = join(', ', (map { "`$_` = ?" } keys %current_user));
					$query = $dbh_thread->prepare("UPDATE `$mysql_database`.`$mysql_info_table` SET `crawled_by`=?, `user_name`=?, `date`=?, $info_columns WHERE `user_id`='$id'");
					$query->execute($fb_user_email, $name, strftime("%Y-%m-%d %H:%M:%S", localtime(time)), values %current_user);
					$done_str = 'updated';
				}
				print ' - '.$name.(' ' x (27-length($name))).$id.(' ' x (20-length($id)))."info : $done_str\n";
            }
        }
    }
    $query->finish() if (defined($query));
    $dbh_thread->disconnect();
    threads->self()->detach();
}

# crowl self if -self option is set
get_user('profile.php?id='.$fb_user_id) if (defined($save_self));

if (defined($fb_user_urls)) {
	
	#
	# Crawl each -url
    #
	foreach my $uri (split(/,/,$fb_user_urls)) {
		$uri = trim($uri);
		$uri =~ s/http:\/\/.*//;
		get_user($uri);
    }
}elsif (defined($fb_user_names)) {
	
	#
	# Crawl each -name
	#
    my ($uri, $response, $istart, $iend);
    foreach my $name (split(/,/,$fb_user_names)) {
        $response = http_request('http://m.facebook.com/search/?search=people&query='.uri_escape(trim($name)));
        $istart = index($response, '<td class="name"');
        $istart = index($response, 'href="', $istart)+6;
        $iend = index($response, '"', $istart);
        $uri = decode_entities(substr($response, $istart, $iend-$istart));
        $uri =~ s/http:\/\/.*//;
        $uri =~ s/\///;
        
        get_user($uri);
    }
}else{
	
	#
	# Get the current logged in user's friends and crawl them
	#
    print "+ Entering depth level: 0 (your friends)\n";
    find_friends($fb_user_id, $fb_user_name);
}

#
# Once done with current user, go on to next crawl depth
#
for (my $d = 1; $d <= $crawl_depth; $d++) {
	print "+ Entering depth level: $d (friends".(' of friends' x $d).")\n";
	foreach my $user (@users) {
		find_friends($$user[0], $$user[1]);
	}
}
self_destruct();

#
# Wait for all threads to die
#
sub self_destruct {
	$q->enqueue('die') for (1..$thread_count);
	foreach my $thread (@threads) {
		while ($thread->is_running()) {
			usleep(50000);
		}
	}
	my $time = time()-$start_time;
	my $unit = 'seconds';
	if ($time > 60) {
		$time = sprintf("%.2f", $time/60);
		$unit = 'minutes';
	}
	if ($time > 60) {
		$time = sprintf("%.2f", $time/60);
		$unit = 'hours';
	}
	
	print '+ '.scalar(@users)." profiles crawled in $time $unit\n";
}

######################################
#
# Anonymous data colloration (for use with fb-share.pl)
#
# If the -share option has been set then this will send the results to anonfiles.com 
#
######################################

# Exclude any identifying information
my @share_columns;
my @exclude_columns = ('id', 'crawled_by');
foreach my $column (@info_table_columns) {
	if (!grep {$_ eq $column} @exclude_columns) {
		push(@share_columns, $column);
	}
}

#
# Anonymize and zip compress the results then send them to anonfiles.com
#
if (defined($share_results)) {
	my $out = "crawl-start: ".localtime($start_time)."\n";
	$out .= "crawl-end: ".localtime()."\n";
	$out .= "table: info\n";
	$out .= "table-columns: ".join(',', @share_columns)."\n";
	$out .= "\n";
	$query = $dbh->prepare("SELECT ".join(', ', map { '`'.$_.'`' } @share_columns)." FROM `$mysql_database`.`$mysql_info_table` WHERE `date` > '".strftime('%Y-%m-%d %H:%M:00', localtime($start_time))."'");
	$query->execute;
	if ($query->rows > 0) {
		print '+ Sharing '.$query->rows." results\n";
		$out .= '<table>';
		while (my @row = $query->fetchrow_array) {
			$out .= '<row>'.join('', map { '<col>'.(defined($_)?$_:'').'</col>' } @row)."</row>\n";
		}
		$out .= '</table>';
		use IO::Compress::Zip;
		my $filename = '/tmp/fb-crawl-info-'.time().'.zip';
		my $z = new IO::Compress::Zip $filename;
		$z->print($out);
		$z->close();
		use HTTP::Request::Common;
		$response = $ua->post('http://anonfiles.com/upload', Content_Type => 'multipart/form-data', Content => [ 'input_file' => [$filename], 'file_publish' => 'on', 'agreement' => 'on' ]);
		unlink($filename);
		$response->decoded_content =~ m/<a href="([^\"]+)" class="download_button"/;
		print '+ Saved results to '.$1."\n";
	}
}