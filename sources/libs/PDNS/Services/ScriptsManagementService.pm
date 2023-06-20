# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PDNS::Services::ScriptsManagementService;

use strict;

use JSON;
use Log::Log4perl;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::EntityHelper qw(is_empty);
use PDNS::Defs qw(:ROLES);

sub new ($$;$) {
	my ( $class, $pmod ) = @_;
	my $self = {
		logger          => Log::Log4perl::get_logger(__PACKAGE__),
		class_name      => $class,
		pmod         	=> $pmod,
        sec_mgr         => $pmod->{sec_mgr},
		scrip_dao       => $pmod->dao_lookup('ScriptDAO')
	};
	bless( $self, $class );
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

# ---------------------------------------------------------------------------------------------------------------------------------
# public methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub rpc_mkfile {
	my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->mkfile($name);
}

sub rpc_rename {
	my ($self, $sec_ctx, $new_name, $old_name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->rename($new_name, $old_name);
}

sub rpc_copy {
    my ($self, $sec_ctx, $new_name, $orig_name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->copy($new_name, $orig_name);
}

sub rpc_delete {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return ($self->{scrip_dao}->delete($name) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
}

sub rpc_getMeta {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->get_meta($name);
}
    
sub rpc_readBody {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->read_body($name);
}
    
sub rpc_writeBody {
    my ($self, $sec_ctx, $name, $data) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return ($self->{scrip_dao}->write_body($name, $data) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
}

sub rpc_browse {
    my ($self, $sec_ctx, $filter) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);    
    return $self->{scrip_dao}->browse($filter);
}

sub rpc_load {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->load($name, 0);
}

sub rpc_unload {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    return $self->{scrip_dao}->unload($name, 1);
}

sub rpc_reload {
    my ($self, $sec_ctx, $name) = @_;
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    if($self->{scrip_dao}->unload($name)) {
        $self->{scrip_dao}->load($name);
        return Wstk::Boolean::TRUE;
    }     
    return Wstk::Boolean::FALSE;
}

# ---------------------------------------------------------------------------------------------------------------------------------
# private methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub check_permissions {
    my ($self, $ctx, $roles) = @_;
    my $ident = $self->{sec_mgr}->identify($ctx);
    $self->{sec_mgr}->pass($ident, $roles);    
}

1;
