# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# Copyright SvenDowideit@fosiki.com
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::GetAWebPlugin;

# Always use strict to enforce variable scoping
use warnings;
use strict;

require Foswiki::Func;    # The plugins API
require Foswiki::Plugins; # For the API version
use Archive::Tar;
use Error qw(:try);


use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );

$VERSION = '$Rev$';
$RELEASE = 'Foswiki-1.0';
$SHORTDESCRIPTION = 'Create a zipped copy of a whole Web for backup or offline reading ';
$NO_PREFS_IN_TOPIC = 1;
$pluginName = 'GetAWebPlugin';

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }

    Foswiki::Func::registerRESTHandler('getaweb', \&getaweb);
    return 1;
}


sub getaweb {
    my ($session) = @_;
   
    my $query = Foswiki::Func::getCgiQuery();
    my $error = '';
    my $webName;
    if ($query->path_info() =~ /^.*\/([^\/]*)\.(tar)$/x) {
        $webName = $1;
    } 
    my $outputType = 'application/x-tar';
    my $saveasweb = $query->param('saveasweb' ) || $webName;
    
    $error .= qq{web "$webName" doesn't exist (or you lack permission to see it)<br/>} unless Foswiki::Func::webExists( $webName );
    
    # TODO: use oops stuff
    if ( $error ne '' ) 
    {
        print "Content-type: text/html\n\n";
        print $error;
        return;
    }
        
    
    my $tar = Archive::Tar->new() or die $!;
    foreach my $topicName (Foswiki::Func::getTopicList($webName))
    {
        #export topic
        my $rawTopic = Foswiki::Func::readTopicText( $webName, $topicName);
        next if (!Foswiki::Func::checkAccessPermission( 'VIEW', Foswiki::Func::getWikiName(), $rawTopic, $topicName, $webName));
        $tar->add_data( "data/$saveasweb/$topicName.txt", $rawTopic );  # or die ???
        #TODO: ,v file (get store obj, then look at its innards :( )
        my $handler = $session->{store}->_getHandler($webName, $topicName);
        $handler->init();
        if (-e $handler->{rcsFile}) {
	    local( $/, *FH ) ;
	    open( FH, '<', $handler->{rcsFile} ) or die $!;
	    my $contents = <FH>;
            $tar->add_data( "data/$saveasweb/$topicName.txt,v", $contents );  # or die ???
        }
        #attachments
        my( $meta, $text ) = Foswiki::Func::readTopic($webName, $topicName);
        my @attachments = $meta->find( 'FILEATTACHMENT' );
        foreach my $a ( @attachments ) {
            my $handler = $session->{store}->_getHandler($webName, $topicName, $a->{name});
            next unless ($handler->storedDataExists());
            try {
                my $data = Foswiki::Func::readAttachment($webName, $topicName, $a->{name} );
                $tar->add_data( "pub/$saveasweb/$topicName/".$a->{name}, $data );  # or die ???
                #my $handler = $session->{store}->_getHandler($webName, $topicName, $a->{name});
                $handler->init();
                if (-e $handler->{rcsFile}) {
                    local( $/, *FH ) ;
                    open( FH, '<', $handler->{rcsFile} ) or die $!;
                    my $contents = <FH>;
                    $tar->add_data( "pub/$saveasweb/$topicName/".$a->{name}.",v", $contents );  # or die ???
                }
            } catch Foswiki::AccessControlException with {
            };

        }
    }

    $session->{response}->header(
        -type => $outputType, -expire=>'now' );
    $session->{response}->body($tar->write());
      
   return;
}

1;
