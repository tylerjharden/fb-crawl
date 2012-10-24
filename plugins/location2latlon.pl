#
# This script takes the $current_user->{'address'} and converts it into latitude and longitude values using the Google Geocoding API.
# It then adds those values to the $current_user hash and fb-crawl.pl creates 'lat' and 'lon' columns in the database with the 'float' data type.
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
   
sub location2latlon {
    $current_user = shift;
    my $location;
    if (defined($current_user->{'address'})) {
        $location = $current_user->{'address'};
    }elsif (defined($current_user->{'current_city'})) {
        $location = $current_user->{'current_city'};
    }elsif (defined($current_user->{'hometown'})) {
        $location = $current_user->{'hometown'};
    }else{
        return 0;
    }
    
    if (defined($location)) {
        $response = http_request('http://maps.googleapis.com/maps/api/geocode/xml?address='.uri_escape($location).'&sensor=false');
        $response =~ m/<lat>([^<]+)<\/lat>/;
        if (defined($1)) {
            $current_user->{'lat:float'} = $1;
            $response =~ m/<lng>([^<]+)<\/lng>/;
            $current_user->{'lon:float'} = $1;
        }
    }
    return 1;
}

return 1;