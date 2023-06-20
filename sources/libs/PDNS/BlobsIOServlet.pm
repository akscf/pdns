# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PDNS::BlobsIOServlet;

use strict;

use Log::Log4perl;
use MIME::Base64;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use PDNS::Defs qw(:ROLES);
use PDNS::IOHelper qw(io_get_file_size);

sub new ($$;$) {
	my ( $class, $pmod) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name 			=> $class,
		fsadmin        		=> $pmod,
        sec_mgr         	=> $pmod->{sec_mgr},
        script_dao	        => $pmod->dao_lookup('ScriptDAO')
	};
	bless( $self, $class );
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

sub execute_request {
	my ( $self, $cgi ) = @_;
	my $credentials = undef;
	my $auth_hdr = $ENV{'HTTP_AUTHORIZATION'};

	if ($auth_hdr) {
		my ($basic, $ucred) = split(' ', $auth_hdr);
		if ($basic) {
			my ( $user, $pass ) = split( ':', decode_base64($ucred) );
			if ( defined($user) && defined($pass) ) {
				$credentials = { method => $basic, user => $user, password => $pass };
			}
		}
	}
	my $sessionId = $cgi->http("X-SESSION-ID");
	unless($sessionId) { $sessionId = $cgi->param('x-session-id'); }
	unless($sessionId) { $sessionId = $cgi->param('sid'); }
	my $ctx = {
		time       	=> time(),
		sessionId 	=> $sessionId,
		userAgent	=> $cgi->http("HTTP_USER_AGENT"),
		remoteIp   	=> $ENV{'REMOTE_ADDR'},
		credentials => $credentials
	};

	$@ = "";	
	eval { 
		$self->{sec_mgr}->pass($self->{sec_mgr}->identify($ctx), [ROLE_ADMIN]); 
	} || do {
		die Wstk::WstkException->new('Permission denied', 403);
  	};

  	my $method = $ENV{REQUEST_METHOD};
  	my $id = $cgi->param('id');
  	my $type = $cgi->param('type');
  	my $data = $cgi->param('data');  	
	
	if('GET' eq $method) {
		if($type eq 'script') {
			my $body = $self->{script_dao}->read_body($id);
			send_response($self, $body);
			return 1;
		}
		die Wstk::WstkException->new('Unsupported type: '.$type, 400);
	}
	if('PUT' eq $method) {
		unless(defined($data)) {
			die Wstk::WstkException->new('Missing parameter: data', 400);
		}	
		if($type eq 'script') {
			$self->{script_dao}->write_body($id, $data);
			send_response($self, "+OK");
			return 1;
		}
		die Wstk::WstkException->new('Unsupported type: '.$type, 400);
	}

	die Wstk::WstkException->new('Unsupported method: '.$method, 400);
	return 1;
}

# ---------------------------------------------------------------------------------------------------------------------------------
# helper methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub get_content_type {
	my ($self, $fileName) = @_;	
	return "application/octet-stream";
}

sub send_response {
	my ($self, $response ) = @_;
	print "Content-type: text/plain; charset=UTF-8\n";
	print "Date: " . localtime( time() ) . "\n\n";
	print $response;
}

1;
