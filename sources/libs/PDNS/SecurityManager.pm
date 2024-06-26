# ******************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# ******************************************************************************************
package PDNS::SecurityManager;

use strict;

use Log::Log4perl;
use Digest::SHA::PurePerl qw(sha1_hex);
use Crypt::RandPasswd;
use MIME::Base64;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use Wstk::Boolean;
use Wstk::JSON;
use Wstk::Models::UserIdentity;
use PDNS::Defs qw(:ROLES);

my $ANONYMOUS = Wstk::Models::UserIdentity->new(id => -1, role => ROLE_ANONYMOUS, title => 'anonymous');

sub new ($$;$) {
	my ( $class, $pmod ) = @_;
	my $self = {
		logger     			=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name 			=> $class,
		pmod        		=> $pmod,
		ttl 				=> 3600, # 1 hour
		json	   			=> Wstk::JSON->new(auto_bless => 1)
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
sub session_create {
	my ($self, $login, $title, $role) = @_;
	my $pmod = $self->{pmod};

	my $expiry = (time() + $self->{ttl});
	my $sid = encode_base64(Crypt::RandPasswd->chars( 48, 48 ));
    $sid =~ s/\n|\r//g;    
	my $obj = {sid => $sid, id => 0, login => $login, title => $title, role => $role, expiry => $expiry};
	my $skey = "sid_".$sid;

	my $js = $self->{json}->encode($obj);
	$pmod->{wstk}->sdb_put($skey => $js);

    return $sid;
}

sub session_delete {
	my ($self, $sid) = @_;
	my $pmod = $self->{pmod};
	my $skey = "sid_".$sid;

	$pmod->{wstk}->sdb_put($skey => undef);

	return 1;
}

sub session_get {
	my ($self, $sid) = @_;
	my $pmod = $self->{pmod};
	my $skey = "sid_".$sid;
	
	my $js = $pmod->{wstk}->sdb_get($skey);
	return $self->{json}->decode($js) if($js);
	return undef;
}

sub identify {
	my ($self, $sec_ctx) = @_;
	my $pmod = $self->{pmod};
	my $sid = $sec_ctx->{sessionId};
	my $skey = "sid_".$sid;

	unless($sec_ctx) {
		return $ANONYMOUS;
	}
	if (!$sid && !$sec_ctx->{credentials}) {
		return $ANONYMOUS;
	}

	# by session
	if($sid) {
		my $session = session_get($self, $sid);
		return $ANONYMOUS unless($session);		

		my $ts = time();
		if($ts >= $session->{expiry}) {
			session_delete($self, $sid);
			return $ANONYMOUS;
		}

		$session->{expiry} = (time() + $self->{ttl});
		$pmod->{wstk}->sdb_put($skey => $self->{json}->encode($session)); 

		return Wstk::Models::UserIdentity->new(id => $session->{id}, role => $session->{role}, title => $session->{title});
	}
	
	# by credentials
	if ($sec_ctx->{credentials}) {
		my $auth = 0;

		if ('true' eq $pmod->get_config('users', 'admin_enable')) {
			my $name = $pmod->get_config('users', 'admin_name');
			my $pass = $pmod->get_config('users', 'admin_secret');

			if((($name eq $sec_ctx->{credentials}->{user}) && ($pass eq $sec_ctx->{credentials}->{password}))) {
				return Wstk::Models::UserIdentity->new(id => 0, role => ROLE_ADMIN, title => 'Administrator');
			}
		}
	}	

	return $ANONYMOUS;
}

sub pass {
	my ($self, $user_identity, $roles) = @_;

	unless($user_identity) {
		die Wstk::WstkException->new( 'Unauthorized', RPC_ERR_CODE_UNAUTHORIZED_ACCESS );
	}
	unless($roles) {
		die Wstk::WstkException->new( 'Unauthorized', RPC_ERR_CODE_UNAUTHORIZED_ACCESS );
	}

	my $urole = $user_identity->role();
	my $pass = 0;
	
	if($urole eq ROLE_ANONYMOUS) {
		die Wstk::WstkException->new( 'Unauthorized', RPC_ERR_CODE_UNAUTHORIZED_ACCESS );
	}
	
	if (ref($roles) eq 'SCALAR') {
		$pass = 1 if ($urole eq $roles);
	} else {
		foreach my $r (@{$roles}) {
			if ($urole eq $r) {
				$pass = 1;
				last;
			}		
		}		
	}	
	unless($pass) {
		die Wstk::WstkException->new( 'Permission denined', RPC_ERR_CODE_PERMISSION_DENIED );
	}	
}

sub reject {
	my ($self, $user_identity, $roles) = @_;

	unless($user_identity) {
		die Wstk::WstkException->new( 'Unauthorized', RPC_ERR_CODE_UNAUTHORIZED_ACCESS );
	}

	my $pass = 1;
	my $urole = $user_identity->role();
	if (ref($roles) eq 'SCALAR') {
		$pass = 0 if ($urole eq $roles);
	} else {
		foreach my $r (@{$roles}) {
			if ($urole eq $r) { $pass = 0; last; }
		}		
	}	
	if($pass) {
		die Wstk::WstkException->new( 'Permission denined', RPC_ERR_CODE_PERMISSION_DENIED );
	}		
}

1;
