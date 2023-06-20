# *****************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# *****************************************************************************************
package PDNS::Defs;

use constant ROLE_ADMIN  	    => 'ADMIN';
use constant ROLE_ANONYMOUS     => 'ANONYMOUS';

use constant ZONE_TYPE_ORD      => 'ORDINARY';      # ordinary zone with records
use constant ZONE_TYPE_AUTH     => 'AUTHORITATIVE'; # contains only SOA and authoritative servers list

use constant ZONE_ACTION_NONE   => 'NONE';          # by default
use constant ZONE_ACTION_FWD    => 'FORWARD';       # redirect request to external server
use constant ZONE_ACTION_SCRIPT => 'SCRIPT';        # handle of request with some script

use constant RECORD_TYPE_SCRIPT => 'SCRIPT';        # handle of request with some script

use Exporter qw(import);
our @EXPORT_OK = qw(
    ROLE_ADMIN
    ROLE_VIEWER
    ROLE_ANONYMOUS
    ZONE_TYPE_ORD
    ZONE_TYPE_AUTH
    ZONE_ACTION_NONE
    ZONE_ACTION_FWD
    ZONE_ACTION_SCRIPT
    RECORD_TYPE_SCRIPT    
);
our @EXPORT_ROLES = qw(
    ROLE_ADMIN
    ROLE_ANONYMOUS
);

our @EXPORT_ZONES = qw(
    ZONE_TYPE_ORD
    ZONE_TYPE_AUTH
    ZONE_ACTION_NONE
    ZONE_ACTION_FWD
    ZONE_ACTION_SCRIPT
    RECORD_TYPE_SCRIPT
);

our %EXPORT_TAGS = (
    'ALL'   => \@EXPORT_OK,
    'ROLES' => \@EXPORT_ROLES,
    'ZONES' => \@EXPORT_ZONES
);

1;
