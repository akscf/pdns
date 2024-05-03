# ******************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# ******************************************************************************************
package PDNS::Models::Zone;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
    my ($class, %args) = @_;
    my %t = (        
        class  			=> CLASS_NAME,
        id              => undef,
        syncId          => undef, # reserved
        enabled         => undef, # true/false
        ttl             => undef, # default for a whole zone (in seconds)
        name            => undef, # full qualified domain name
        type            => undef, # see PDNS::Defs
        action          => undef, # see PDNS::Defs
        script          => undef, # optional script.pm
        fwdUrl          => undef, # optional udp://ip:addr/
        authNss         => undef, # optional [ns1, ns2, ...]
        options         => undef, # json serialized extra props
        description     => undef  #        
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

sub type {
	my ($self, $val) = @_;
	return $self->{type} unless(defined($val));
	$self->{type} = $val;
}

sub action {
	my ($self, $val) = @_;
	return $self->{action} unless(defined($val));
	$self->{action} = $val;
}

sub script {
	my ($self, $val) = @_;
	return $self->{script} unless(defined($val));
	$self->{script} = $val;
}

sub fwdUrl {
	my ($self, $val) = @_;
	return $self->{fwdUrl} unless(defined($val));
	$self->{fwdUrl} = $val;
}

sub authNss {
	my ($self, $val) = @_;
	return $self->{authNss} unless(defined($val));
	$self->{authNss} = $val;
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
