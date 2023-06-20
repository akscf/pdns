# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PDNS::Models::ZoneRecord;

use strict;
use constant CLASS_NAME         => __PACKAGE__;

sub new ($$) {
    my ($class, %args) = @_;
    my %t = (        
        class  			=> CLASS_NAME,
        id              => undef,
        zoneId          => undef,   # zone ref id
        syncId          => undef,   # reserved
        enabled         => undef,   # true / false
        ttl             => undef,   # ttl
        name            => undef,   # sort name
        fqName          => undef,   # full qualified domain name, auto fill in
        type            => undef,   # record type or exec script
        data            => undef,   # record data or scriptName       
        options         => undef,   # json serialized extra props
        description     => undef    #
    );
    my $self= {%t, %args};
    bless( $self, $class );
    return $self;
}

sub get_class_name {
    my ($self) = @_;
    return $self->{class};
}

sub id {
    my ($self, $val) = @_;
    return $self->{id} + 0 unless(defined($val));
    $self->{id} = $val + 0;
}

sub zoneId {
    my ($self, $val) = @_;
    return $self->{zoneId} + 0 unless(defined($val));
    $self->{zoneId} = $val + 0;
}

sub syncId {
    my ($self, $val) = @_;
    return $self->{syncId} + 0 unless(defined($val));
    $self->{syncId} = $val + 0;
}

sub enabled {
    my ($self, $val) = @_;
    return $self->{enabled} unless(defined($val));
    $self->{enabled} = $val;
}

sub ttl {
    my ($self, $val) = @_;
    return $self->{ttl} + 0 unless(defined($val));
    $self->{ttl} = $val + 0;
}

sub name {
	my ($self, $val) = @_;
	return $self->{name} unless(defined($val));
	$self->{name} = $val;
}

sub fqName {
	my ($self, $val) = @_;
	return $self->{fqName} unless(defined($val));
	$self->{fqName} = $val;
}

sub type {
	my ($self, $val) = @_;
	return $self->{type} unless(defined($val));
	$self->{type} = $val;
}

sub data {
	my ($self, $val) = @_;
	return $self->{data} unless(defined($val));
	$self->{data} = $val;
}

sub description {
	my ($self, $val) = @_;
	return $self->{description} unless(defined($val));
	$self->{description} = $val;
}

sub options {
    my ($self, $val) = @_;
    return $self->{options} unless(defined($val));
    $self->{options} = $val;
}


# -------------------------------------------------------------------------------------------
1;
