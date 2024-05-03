# *********************************************************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# *********************************************************************************************************************************
package PDNS;

use Log::Log4perl;
use Wstk::WstkException;
use Wstk::WstkDefs qw(RPC_ERR_CODE_INTERNAL_ERROR);

use PDNS::Defs;
use PDNS::SQLite;
use PDNS::SecurityManager;
use PDNS::NsConnectionsManager;
use PDNS::BlobsIOServlet;

use PDNS::DAO::SystemDAO;
use PDNS::DAO::ZoneDAO;
use PDNS::DAO::ZoneRecordDAO;
use PDNS::DAO::ScriptDAO;

use PDNS::Services::AuthenticationService;
use PDNS::Services::SystemInformationService;
use PDNS::Services::ZonesManagementService;
use PDNS::Services::ZoneRecordsManagementService;
use PDNS::Services::ScriptsManagementService;

use constant CONFIG_NAME => 'pdns';

sub new ($$;$) {
        my ($class) = @_;
        my $self = {
                logger      	=> Log::Log4perl::get_logger(__PACKAGE__),
                class_name  	=> $class,
                version     	=> 1.0,
                description 	=> "PerlDNS",
                start_time		=> time(),
                wstk         	=> undef,
                sec_mgr	    	=> undef,
				nsc_mgr			=> undef,
                dbm 			=> undef,
				dao				=> {},
        };
        bless( $self, $class );
        return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

#---------------------------------------------------------------------------------------------------------------------------------
sub init {
	my ($self, $wstk) = @_;
	$self->{'wstk'} = $wstk;
}

sub start {
	my ($self) = @_;

	$self->{'wstk'}->cfg_load(CONFIG_NAME, sub {            
		my $cfg = shift;
		die Wstk::WstkException->new("Missing configuration file!");
	});

	$self->{'dbm'} = PDNS::SQLite->new($self, 'pdns.db');	
	$self->{'sec_mgr'} = PDNS::SecurityManager->new($self);	
	$self->{'nsc_mgr'} = PDNS::NsConnectionsManager->new($self);

	$self->dao_register(PDNS::DAO::SystemDAO->new($self));
	$self->dao_register(PDNS::DAO::ScriptDAO->new($self));
	$self->dao_register(PDNS::DAO::ZoneDAO->new($self));
	$self->dao_register(PDNS::DAO::ZoneRecordDAO->new($self));
	
	$self->{'wstk'}->mapper_alias_register('Zone', PDNS::Models::Zone::CLASS_NAME);
	$self->{'wstk'}->mapper_alias_register('ZoneRecord', PDNS::Models::ZoneRecord::CLASS_NAME);
	$self->{'wstk'}->mapper_alias_register('ServerStatus', PDNS::Models::ServerStatus::CLASS_NAME);
	$self->{'wstk'}->mapper_alias_register('ScriptItem', PDNS::Models::ScriptItem::CLASS_NAME);
		
	$self->{'wstk'}->rpc_service_register('AuthenticationService', PDNS::Services::AuthenticationService->new($self));
	$self->{'wstk'}->rpc_service_register('SystemInformationService', PDNS::Services::SystemInformationService->new($self));
	$self->{'wstk'}->rpc_service_register('ZonesManagementService', PDNS::Services::ZonesManagementService->new($self));
	$self->{'wstk'}->rpc_service_register('ZoneRecordsManagementService', PDNS::Services::ZoneRecordsManagementService->new($self));
	$self->{'wstk'}->rpc_service_register('ScriptsManagementService', PDNS::Services::ScriptsManagementService->new($self));

	$self->{'wstk'}->servlet_register('/blobs/*', PDNS::BlobsIOServlet->new($self));

	unless($self->{'nsc_mgr'}->start()) {
		die Wstk::WstkException->new("Couldn't start connection manager!");
    }
}

sub stop {
	my ($self) = @_;

	if($self->{'nsc_mgr'}) {
		$self->{'nsc_mgr'}->stop();
	}
}

#---------------------------------------------------------------------------------------------------------------------------------
sub get_config {
	my ($self, $section, $property) = @_;
	my $wstk = $self->{wstk}; 
	return $wstk->cfg_get(CONFIG_NAME, $section, $property);
}

sub dao_register {
	my ($self, $inst) = @_;
    my $dao = $self->{dao};

    unless($inst) {
		die Wstk::WstkException->new("Invalid argument: inst");
	}
	my @t = split('::', $inst->get_class_name());
	my $sz = scalar(@t);
	my $name = ($sz > 0 ? $t[$sz - 1] : $inst->get_class_name());

	if(exists($dao->{$name})) {
		die Wstk::WstkException->new("Duplicate DAO: ".$name);
	}

	$dao->{$name} = $inst;
}

sub dao_lookup {
	my ($self, $name, $quiet) = @_;
	my $dao = $self->{dao};

	unless(exists($dao->{$name})) {
		return undef if ($quiet);
		die Wstk::WstkException->new("Unknown DAO: ".$name);
	}

	return $dao->{$name};
}

#---------------------------------------------------------------------------------------------------------------------------------
return PDNS->new();

