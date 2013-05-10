# TODO: make this work

$user_agent = 'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20120405 Firefox/14.0a1';
$headers = {'Accept-Language' => 'en,en-us;q=0.5'};
$proxy_test_url = 'http://ip.appspot.com/';

$login_url = 'http://www.facebook.com/';
$login_form_method = 'POST';
$login_form_action = 'http://www.facebook.com/login.php?login_attempt=1';
$login_form_email = 'email';
$login_form_pass = 'pass';
$login_error = 'login_error_box[^>]+>(.*?)<\/div>';

$user_id = 'envFlush\(\{"user"\:"([0-9]+)"';
$user_name = ('<span class="headerTinymanName"', '<a class="fbxWelcomeBoxName"');

$page_error = ('<div id="error">(.*?)<\/div>', '(Log In)', '(Sorry, something went wrong.)', '<title>(Page Not Found)</title>', '<title>(Content Not Found)</title>');

$friends_url = 'http://www.facebook.com/ajax/browser/list/allfriends/?uid=UID&infinitescroll=1&location=friends_tab_tl&start=START&__user=USER&__a=1';
$friends_url_uid = 'UID';
$friends_url_start = 'START';
$friends_url_user = 'USER';
$friends_page_increment = 24;
$friends_page_limit = 500;
$friends_error = ('"errorSummary":"([\"]+)"', '(No results found.)');
$friends_results = '<a href="https?:\/\/www.facebook.com\/([^\"]+)" data-hovercard="[^\?]+\?id=([0-9]+)">([^<]+)<\/a>';
$friend_name = 'F_NAME';
$friend_uid = 'F_UID';
$friend_url = 'F_URL';

$profile_url = 'http://m.facebook.com/F_URL';
$profile_name = '<title>([^<]+)</title';
$profile_id = ';id=([0-9]+)&';

$profile_info_uri = $profile_url;
$profile_info_param = 'v=info';
$profile_info_mutual = 'Mutual Friends \(([0-9]+)\)';
$profile_info_results = '<div class="mfsm[^>]+>([^:]+):<\/div>((?!<div).)*<div class="mfsm[^>]+>(((?!<div).)*)<\/div>';
$profile_info_result_field = 1;
$profile_info_result_values = 3;
$profile_info_result_value = '<a[^>]+>([^<]+)<\/a>';

$profile_wall_uri = 'wall.php';
$profile_wall_param = 'id=F_UID';
$profile_wall_results = '<div[^>]*?  class="msg[^>]+>(.*?)<\/div><div[^>]*?  class="actions[^>]+>.*?<abbr>([^<]+)<\/abbr>(  (near|in|at) ([^<]+))?';
$profile_wall_results_start_index = '';
$profile_wall_results_end_index = '';
$profile_wall_result_start_index = '';
$profile_wall_result_end_index = '';
$profile_wall_result_post = 1;
$profile_wall_result_date = 2;
$profile_wall_result_location = 5;

$search_url = 'http://m.facebook.com/search/';
$search_param = 'search=people&query=QUERY'
$search_query = 'QUERY';
$search_results = 'href="([^"]+)"';
$search_results_start_index = '';
$search_results_end_index = '';
$search_result_start_index = '<td class="name';
$search_result_end_index = '';
$search_result_url = 1;
