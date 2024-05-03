# ******************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# ******************************************************************************************
package PDNS::NsConnectionsManager;

use strict;
use Net::DNS;
use URI::Simple;
use base qw(Net::Server::PreFork);
use PDNS::Defs qw(:ZONES);
use Wstk::Boolean;
use List::Util qw/shuffle/;
use Data::Dumper;

sub new ($$;$) {
	my ( $class, $pmod ) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pmod             	=> $pmod,
        sec_mgr         	=> $pmod->{sec_mgr},
        hpid             	=> undef,
		exit_val			=> undef
	};
	bless( $self, $class );    
	return $self;
}

sub start {
    my ($self) = @_;
	my $pmod = $self->{pmod};
	
	my $wsp_sys_user = $self->{pmod}->{wstk}->wstk_cfg_get('server', 'group');
	my $wsp_sys_group = $self->{pmod}->{wstk}->wstk_cfg_get('server', 'user');

	$self->{hpid} = fork();    
    if(!defined($self->{hpid})) {
        $self->{logger}->warn("fork faild: $!");
        return 0;
    } elsif ($self->{hpid} == 0) {
		__PACKAGE__->run(
			host 				=> $pmod->get_config('dns', 'listen_address'),
			port 				=> $pmod->get_config('dns', 'listen_port'),
			max_requests		=> $pmod->get_config('dns', 'max_requests'),
			max_servers			=> $pmod->get_config('dns', 'max_servers'),
			min_servers			=> 1,
			log_level   		=> 1,
			logger				=> undef, 		  # see post_configure_hook	
			pmod				=> $self->{pmod}, # see post_configure_hook	
			proto           	=> 'udp',
			group 				=> ($wsp_sys_group eq 'undef' ? undef : $wsp_sys_group),
			user  				=> ($wsp_sys_user eq 'undef'  ? undef : $wsp_sys_user)
		);
        exit 0;
    } else {
        return 1;
    }
    return 0
}

sub stop {
    my ($self) = @_;   
	if(defined $self->{hpid}) {
		kill('TERM', $self->{hpid});
	}
}

sub server_exit {
	my ($self) = @_;
	$self->{exit_val} = shift || 0;
	
	if( $self->{exit_val} ) {
		# $self->{logger}->warn("err-code: ". $self->{exit_val} );
	}
	
	exit($self->{exit_val});
}

sub get_exit_val {
	my ($self) = @_;
	return $self->{exit_val};
}

sub post_configure_hook {
    my ($self) = @_;
    my $prop = $self->{'server'};
	my %run_args = @{$prop->{_run_args}};

	unless(defined $prop->{logger}) {
		$prop->{logger} = $self->{logger};
	}

	$self->{pmod} 		= $run_args{pmod};
	$self->{zone_dao} 	= $self->{pmod}->dao_lookup('ZoneDAO');
	$self->{record_dao} = $self->{pmod}->dao_lookup('ZoneRecordDAO');
	$self->{script_dao} = $self->{pmod}->dao_lookup('ScriptDAO');	
}

sub process_request {
	my ($self) = @_;
	my $prop = $self->{'server'};
    my $peeraddr = $prop->{'peeraddr'};
	my ($request, $reply, $err, $headermask, $zs_name, $zname_tmp, $zone);
    my ($rcode, @ans, @auth, @add) = ('NOERROR');

	$@='';
    eval { 
		($request, $err) = Net::DNS::Packet->new(\$prop->{udp_data}, 0); 
	};
    if($@ || !defined $request) {
		my $exc = $@;
		if($err) { $self->{logger}->debug("malformed request from: '".$peeraddr."', err: ".$err); }
		else 	 { $self->{logger}->debug("malformed request from: '".$peeraddr."', err: ".$exc); }
		return;
	}
	my @qres = $request->question;
    $reply = Net::DNS::Packet->new();
    $reply->header->qr(1);	
    @qres = (Net::DNS::Question->new('', 'ANY', 'ANY')) unless(@qres);
    $reply->push("question", @qres);

	if ($request->header->opcode eq 'QUERY' ) {
		my $qr = @qres[0]; 	# only first
		if($qr->qclass eq 'IN') {
			$@='';
			eval {
				# looking for a zone
				my $zone = $self->{zone_dao}->lookup($qr->qname);
				unless($zone) {
					foreach my $nsub (reverse split('\.', $qr->qname)) { 
						$zname_tmp = $nsub . ($zname_tmp ? '.' : '') . $zname_tmp;
						$zone = $self->{zone_dao}->lookup($zname_tmp);
						last if($zone);
					}
				}			
				if(!$zone || !is_true($zone->{enabled})) { goto EVAL_OUT; }
				if($zone->{action} eq ZONE_ACTION_FWD) {
					my $res = fwd_request($self, $zone, $request);
					unless($res) { $rcode = 'FORMERR'; }
					else {
						$rcode = $res->{rcode};
						if($res->{answer}) 		{ push(@ans,  @{$res->{answer}}); }
						if($res->{authority}) 	{ push(@auth, @{$res->{authority}}); }
						if($res->{additional}) 	{ push(@add,  @{$res->{additional}}); }
					}
					goto EVAL_OUT;
				} 
				if($zone->{action} eq ZONE_ACTION_SCRIPT) {
					my $res = eval_uscript($self, $zone, $request, $prop);
					unless($res) { $rcode = 'FORMERR'; }
					else {
						$rcode = $res->{rcode};
						if($res->{answer}) 		{ push(@ans,  @{$res->{answer}}); }
						if($res->{authority}) 	{ push(@auth, @{$res->{authority}}); }
						if($res->{additional}) 	{ push(@add,  @{$res->{additional}}); }
					}
					goto EVAL_OUT;
				} 
				if($zone->{action} eq ZONE_ACTION_NONE) {
					if($zone->{type} eq ZONE_TYPE_ORD) {
						if($zone->{name} ne $qr->qname) { 
							goto FIND_RECS; 
						}
						if($qr->qtype eq 'SOA') {
							push(@ans, Net::DNS::RR->new($qr->qname.' SOA ns.'.$qr->qname.' root.'.$qr->qname.' '.$zone->{syncId}." 3600 3600 86400 1") );
							goto EVAL_OUT;
						} else {
							$zs_name = '@.'.$qr->qname;
							goto FIND_RECS;
						}
					}
					if($zone->{type} eq ZONE_TYPE_AUTH) {
						foreach my $nsr (split ',', $zone->{authNss}) { 
							$nsr =~ s/^\s+|\s+$//g; 
							push(@auth, Net::DNS::RR->new($qr->qname.' NS '.$nsr) );							
						}
						goto EVAL_OUT;
					}
					$rcode = 'FORMERR'; 
					goto EVAL_OUT;
				}												
				# looking for records
				FIND_RECS:
				my $records = $self->{record_dao}->lookup(($zs_name ? $zs_name : $qr->qname), $qr->qtype);
				unless($records) { goto EVAL_OUT; }
				foreach my $rr (@{$records}) {
					next unless (is_true($rr->{enabled}));
					if($rr->{type} eq RECORD_TYPE_SCRIPT) {
						my $res = eval_uscript($self, $rr, $request, $prop);
						if($res && $res->{rcode} eq 'NOERROR') {
							if($res->{answer}) 		{ push(@ans,  @{$res->{answer}}); }
							if($res->{authority}) 	{ push(@auth, @{$res->{authority}}); }
							if($res->{additional}) 	{ push(@add,  @{$res->{additional}}); }
						}
					} else {
						if($rr->{data} =~ /^\[(.*)\]/) {  ## built-in array [...]
							foreach my $rra (shuffle split(',', $1)) {
								$rra =~ s/^\s+|\s+$//g; 
								push(@ans, Net::DNS::RR->new($qr->qname." ".$rr->{ttl}." ".$qr->qtype." ".$rra));
							}
						} else {
							push(@ans, Net::DNS::RR->new($qr->qname." ".$rr->{ttl}." ".$qr->qtype." ".$rr->{data}));
						}						
					}
				}
				#
				EVAL_OUT:
				unless(scalar @ans && scalar @auth && scalar @add) {
					$rcode = ($rcode == 'NOERROR' ? 'NXDOMAIN' : $rcode); 
				}				
			};
			if ($@) {
				$self->{logger}->error("request-fail: $@");
				$rcode = "SERVFAIL";
			}
 			$reply->header->rcode($rcode);
			$reply->push("answer",     @ans)  if (scalar @ans);
			$reply->push("authority",  @auth) if (scalar @auth);
			$reply->push("additional", @add)  if (scalar @add);
		} else {
			$reply->header->rcode("FORMERR");
		}
	} else {
		$headermask = { opcode => "NS_NOTIFY_OP" };
		$reply->header->rcode('NOTIMP');
	}
 	if (!defined ($headermask)) {
		$reply->header->ra(1);
		$reply->header->ad(0);
	} else {
		$reply->header->aa(1) if $headermask->{'aa'};
		$reply->header->ra(1) if $headermask->{'ra'};
		$reply->header->ad(1) if $headermask->{'ad'};
		$reply->header->opcode( $headermask->{'opcode'} ) if ($headermask->{'opcode'} && defined $Net::DNS::opcodesbyname{$headermask->{'opcode'}});
	}
	$reply->header->cd($request->header->cd);
	$reply->header->rd($request->header->rd);
	$reply->header->id($request->header->id);

	$reply->truncate(512);
	$prop->{client}->send($reply->data, 0);

	return 0;
}

#
# without script worker
#
sub eval_uscript {
	my ($self, $entity, $request, $server) = @_;
	my $sdata = $self->{script_dao}->read_body($entity->{script});
	if(defined $sdata) {
		$@='';		
		my $obj = eval($sdata) or die("eval-fail: ".$@);
		if($obj) {
			return $obj->process_request($self->{pmod}, $entity, $request, $server);
		}
	}
	return undef;
}

#
# using built-in resolver 
#
sub fwd_request {
	my ($self, $entity, $request, $sections) = @_;
	unless($entity->{fwdUrl}) {
		$self->{logger}->error("missing fwd-url");
		return undef;
	}
	my $uri = URI::Simple->new($entity->{fwdUrl});
	my $qr = ($request->question)[0];

	my $resolver = Net::DNS::Resolver->new(nameservers => [ $uri->host ], port => $uri->port, udp_timeout => 5, retry => 1, recurse => 0, debug => 0 );
	my $reply = $resolver->send( $qr->qname, $qr->qtype, $qr->qclass );
	if($reply) {
		my @answer;
		foreach my $rr (grep {$_->type eq $qr->qtype} $reply->answer) {
			push(@answer, Net::DNS::RR->new($qr->qname." ".$rr->{ttl}." ".$qr->qtype." ".$rr->rdatastr));
        }
		return {rcode => 'NOERROR', answer => \@answer, authority => undef, additional => undef };
	} else {	
		if($resolver->errorstring eq 'NOERROR' || $resolver->errorstring eq 'NXDOMAIN') {
			return {rcode  => 'NXDOMAIN'};
		} else {
			die('fwd-fail: '.$resolver->errorstring);
		}
	}

	return undef;
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------
1;
