package SCRIPTS::Example;

use Log::Log4perl;
use Data::Dumper;

sub new ($$;$) {
    my ($class) = @_;
    my $self = {
	      logger 		    => Log::Log4perl::get_logger(__PACKAGE__),
        class_name  	=> $class,
    };
    bless( $self, $class );
    return $self;
}

sub process_request {
    my($self, $pmod, $entity, $request, $server) = @_;
    my @answer;
    
    #$self->{logger}->debug("pmod=$pmod, entity=$entity");

    push(@answer, Net::DNS::RR->new("example.com SOA ns1.example.com root1.example.com ".$entity->{syncId}." 3600 3600 86400 1") );

    return { rcode => 'NOERROR', answer => \@answer, authority => undef, additional => undef };
}

return SCRIPTS::Example->new();

