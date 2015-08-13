fb-crawl.pl is a script that crawls/scrapes Facebook profiles and adds the information to a MySQL database.<br>
The data can then be used for social graph analysis and refined Facebook searching.<br>
<br>
<h2>Features</h2>

<ul><li>Save user information<br>
</li><li>Save user wall posts<br>
</li><li>Save user friends<br>
</li><li>No API calls<br>
</li><li>Multithreaded (tested with up to 128 threads)<br>
</li><li>Supports plug-ins for custom information processing<br>
</li><li>Automatic database configuration<br>
</li><li>Automatically adds new columns to the database as needed<br>
</li><li>Aggregates information crawled from multiple Facebook accounts<br>
</li><li>Anonymous data collaboration (Coming Soon!)</li></ul>

<h2>Requirements</h2>

<ul><li>Perl 5 or greater<br>
</li><li>MySQL with Perl DBI support<br>
</li><li>Tested on CentOS 6.3</li></ul>

<h2>Installation</h2>

<blockquote><code>unzip fb-crawl_version.zip</code><br>
<code>cd fb-crawl</code><br>
<code>chmod +x fb-crawl.pl</code><br>
<code>./fb-crawl.pl -u email@address.com -host mysql.host -user fb-crawl -pass mysqlPassword</code></blockquote>


<blockquote>fb-crawl.pl will set up all the required database tables.<br>
All you have to do is provide it with the MySQL connection information and Facebook account.</blockquote>

<h2>Examples</h2>

<blockquote>Crawl your friends' Facebook information, wall, and friends:</blockquote>

<blockquote><code> ./fb-crawl.pl -u email@address -i -w -f</code></blockquote>

<blockquote>Crawl John Smith's Facebook information, wall, and friends:</blockquote>

<blockquote><code> ./fb-crawl.pl -u email@address -i -w -f -name 'John Smith'</code></blockquote>

<blockquote>Crawl Facebook information for friends of friends:</blockquote>

<blockquote><code> ./fb-crawl.pl -u email@address -depth 1 -i</code></blockquote>

<blockquote>Crawl Facebook information of John Smith's friends of friends:</blockquote>

<blockquote><code> ./fb-crawl.pl -u email@address -depth 1 -i -name 'John Smith'</code></blockquote>

<blockquote>Extreme: Crawl friends of friends of friends of friends with 200 threads:</blockquote>

<blockquote><code> ./fb-crawl.pl -u email@address -depth 4 -t 200 -i -w -f</code></blockquote>

<h2>Plug-ins</h2>

<blockquote>fb-crawl.pl will open a perl script that can analyze and modify user information before it goes into the database.<br>
The script should contain a function with the same name as the file.<br>
The function is passed a hash reference containing the currently crawled user's information.</blockquote>

<blockquote>To load a plug-in use the <code>-plugins</code> option:</blockquote>

<blockquote><code>./fb-crawl.pl -u email@address -i -plugins location2latlon.pl,birthday2date.pl</code></blockquote>

<ul><li>location2latlon.pl: adds the user's coordinates to the database using the Google Geocoding API.</li></ul>

<ul><li>birthday2date.pl: convert the user's birthday to MySQL date (YYYY-MM-DD) format.</li></ul>

<blockquote>See included plugin files for implementation details.</blockquote>

<h2>FAQ</h2>

<blockquote><h3>It's logging in but won't load my friends?</h3></blockquote>

<blockquote>You probably have SSL enabled on your account. You need to use the <code>-https</code> option.</blockquote>

<blockquote><h3><code>Can't locate object method "ssl_opts" via package "LWP::UserAgent"</code></h3></blockquote>

<blockquote>You need to install LWP::Protocol::https.</blockquote>

<blockquote><code>sudo perl -MCPAN -e 'force install LWP::Protocol::https'</code>