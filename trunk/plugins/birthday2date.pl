#
# This script takes the $current_user->{'birthday'} and converts it into MySQL date format (YYYY-MM-DD) using fb-crawl.pl's strtodate() function.
# It then adds that value to the $current_user hash and fb-crawl.pl creates a 'birthdate' column in the database with 'date' data type.
#
# $current_user is used to retieve current user data.
# the values contained in $current_user have the same name as the database column they go into.
# $current_user only contains data that isn't already stored in the database,
# that way plug-ins are only called when needed.
#
# If you create a new value then that COLUMN_NAME automatically gets added to the database.
#
# User data retrieval:
# $VAL = $current_user->{'COLUMN_NAME'};
#
# Column insertion / user data modification:
# $current_user->{'COLUMN_NAME'} = 'VAL';
#
# Column insertion with custom SQL attributes / user data modification:
# $current_user->{'COLUMN_NAME:COLUMN_ATTRIBUTES'} = 'VAL'
#

sub birthday2date {
    $current_user = shift;
    if (defined($current_user->{'birthday'})) {
        $current_user->{'birthdate:date'} = strtodate($current_user->{'birthday'});
    }
}

return 1;