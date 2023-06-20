# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PDNS::Models::ScriptItem;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
        my ($class, %args) = @_;
        my %t = (
                class           => CLASS_NAME,
                name            => undef,
                size            => undef,
                date            => undef,
		loaded		=> undef
        );
        my $self= {%t, %args};
        bless( $self, $class );
}

sub get_class_name {
        my ($self) = @_;
        return $self->{class};
}

sub name {
        my ($self, $val) = @_;
        return $self->{name} unless(defined($val));
        $self->{name} = $val;
}

sub size {
        my ($self, $val) = @_;
        return $self->{size} + 0 unless(defined($val));
        $self->{size} = $val + 0;
}

sub date {
        my ($self, $val) = @_;
        return $self->{date} unless(defined($val));
        $self->{date} = $val;
}

sub loaded {
        my ($self, $val) = @_;
        return $self->{loaded} unless(defined($val));
        $self->{loaded} = $val;
}

1;
