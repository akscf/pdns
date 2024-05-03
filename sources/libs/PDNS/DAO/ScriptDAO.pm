# ******************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# ******************************************************************************************
package PDNS::DAO::ScriptDAO;

use strict;

use Log::Log4perl;
use File::Slurp;
use File::Copy;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PDNS::DateHelper;
use PDNS::FilenameHelper;
use PDNS::IOHelper;
use PDNS::Models::ScriptItem;

use constant ENTITY_CLASS_NAME => PDNS::Models::ScriptItem::CLASS_NAME;

sub new ($$;$) {
    my ($class, $pmod) = @_;
    my $self = {
        logger          => Log::Log4perl::get_logger(__PACKAGE__),
        class_name      => $class,
        pmod            => $pmod,
        pdns_rt         => undef,
        base_path       => $pmod->{wstk}->get_path('var').'/scripts'
    };
    bless($self, $class);
    
    $self->{logger}->debug("scripts home: ".$self->{base_path}); 

    unless(-d $self->{base_path}) {
        mkdir($self->{base_path});
    }

    return $self;
}

sub get_class_name {
    my ($self) = @_;
    return $self->{class_name};
}

sub mkfile {
    my ($self, $name) = @_;    
    unless ( is_valid_filename($name) ) {
        die Wstk::WstkException->new("Malformed script name", RPC_ERR_CODE_INVALID_ARGUMENT);
    } 

    my $script_item = PDNS::Models::ScriptItem->new(
        name => $name, 
        size => 0, 
        date => undef, 
        loaded => Wstk::Boolean::FALSE
    );
    
    my $file_name = $self->{base_path} .'/'. $name; 
    if( -e $file_name ) {
        die Wstk::WstkException->new($name, RPC_ERR_CODE_ALREADY_EXISTS);
    }

    open(my $ofile, '>', $file_name); close($ofile);
    $script_item->date( iso_format_datetime(io_get_file_lastmod($file_name)) );

    return $script_item;
}

sub rename {
    my ($self, $new_name, $old_name) = @_;
    unless ( is_valid_filename($old_name) ) {
        die Wstk::WstkException->new("old_name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless ( is_valid_filename($new_name) ) {
        die Wstk::WstkException->new("new_name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }

    my $old_name_local = $self->{base_path} .'/'. $old_name;
    my $new_name_local = $self->{base_path} .'/'. $new_name;
    
    if( -d $old_name_local ) {
        die Wstk::WstkException->new($old_name, RPC_ERR_CODE_NOT_FOUND);
    }
    if( -e $old_name_local ) {
        if( -e $new_name_local ) {
            die Wstk::WstkException->new($new_name_local, RPC_ERR_CODE_ALREADY_EXISTS);
        }
        File::Copy::move($old_name_local, $new_name_local);        
        
        my $script_item = PDNS::Models::ScriptItem->new(
            name    => $new_name, 
            size    => io_get_file_size($new_name_local),
            date    => iso_format_datetime( io_get_file_lastmod($new_name_local) ),
            loaded  => Wstk::Boolean::FALSE
        );    
        
        return $script_item;
    }

    die Wstk::WstkException->new($old_name, RPC_ERR_CODE_NOT_FOUND);
}

sub copy {
    my ($self, $new_name, $orig_name) = @_;

    if(!is_valid_filename($new_name)) {
        die Wstk::WstkException->new("Malformed 'new_name'", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    if(!is_valid_filename($orig_name)) {
        die Wstk::WstkException->new("Malformed 'copy_name'", RPC_ERR_CODE_INVALID_ARGUMENT);
    }

    my $from_fqname = $self->{base_path} .'/'. $orig_name;
    my $to_fqname = $self->{base_path} .'/'. $new_name;

    if( -d $from_fqname ) {
        die Wstk::WstkException->new($from_fqname, RPC_ERR_CODE_NOT_FOUND);
    }

    if( -e $from_fqname ) {
        unless(-d $to_fqname) {
            die Wstk::WstkException->new($to_fqname, RPC_ERR_CODE_ALREADY_EXISTS);
        }
        File::Copy::copy($from_fqname, $to_fqname);
        return PDNS::Models::ScriptItem->new(
            name    => $new_name, 
            size    => io_get_file_size($to_fqname),
            date    => iso_format_datetime( io_get_file_lastmod($to_fqname) ),
            loaded  => Wstk::Boolean::FALSE
        );
    }

    die Wstk::WstkException->new($from_fqname, RPC_ERR_CODE_NOT_FOUND);
}

sub delete {
    my ($self, $name) = @_;
    unless (is_valid_filename($name)) {
        die Wstk::WstkException->new("Malformed script name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    
    my $tname = $self->{base_path} .'/'. $name;
    if( -d $tname ) {
        die Wstk::WstkException->new($name, RPC_ERR_CODE_NOT_FOUND);
    }
    if( -e $tname ) {
        unlink($tname); 
    }

    return 1;
}

sub get_meta {
    my ($self, $name) = @_;  
    unless (is_valid_filename($name)) {
        die Wstk::WstkException->new("Malformed script name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }

    my $tname = $self->{base_path} .'/'. $name;
    if( -d $tname ) {
        die Wstk::WstkException->new($name, RPC_ERR_CODE_NOT_FOUND);
    }
    if( -e $tname ) {
        return PDNS::Models::ScriptItem->new(
            name    => $name,
            date    => iso_format_datetime( io_get_file_lastmod($tname) ),
            size    => io_get_file_size($tname),
            loaded  => Wstk::Boolean::FALSE
        );
    }
    return undef;
}

sub read_body {
    my ($self, $name) = @_;
    my $entity = undef;

    unless (is_valid_filename($name)) {
        die Wstk::WstkException->new("Malformed script name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }

    my $ep = $self->{base_path} .'/'. $name;
    unless(-d $ep || -e $ep ) {
        die Wstk::WstkException->new($name, RPC_ERR_CODE_NOT_FOUND);
    }

    return read_file($ep);
}

sub write_body {
    my ($self, $name, $body) = @_;
    my $entity = undef;

    unless (is_valid_filename($name)) {
        die Wstk::WstkException->new("Malformed script name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }

    my $ep = $self->{base_path} .'/'. $name;
    if(-d $ep) {
        die Wstk::WstkException->new($name, RPC_ERR_CODE_NOT_FOUND);
    }

    write_file($ep, $body);
    return 1;
}

sub browse {
    my ($self, $filter) = @_;
    my $fmask = filter_get_text($filter);
    my $base_path_lenght = length($self->{base_path}) + 1;

    my $files = [];
    list_files($self, sub {
        my $sfile = $_[0];
        my $tname = $self->{base_path} .'/'. $sfile;
        my $obj = PDNS::Models::ScriptItem->new(
            name    => $sfile,
            date    => iso_format_datetime( io_get_file_lastmod($tname) ),
            size    => io_get_file_size($tname),
            loaded  => Wstk::Boolean::FALSE
        );
        push(@{$files}, $obj);
    });
    return [ sort { $a->{name} cmp $b->{name} } @{$files} ];
}


# ---------------------------------------------------------------------------------------------------------------------------------
sub validate_entity {
    my ($self, $entity) = @_;
    unless ($entity) {
        die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless(entity_instance_of($entity, ENTITY_CLASS_NAME)) {
        die Wstk::WstkException->new("Type mismatch: " . entity_get_class($entity) . ", require: " . ENTITY_CLASS_NAME);
    }
}

sub list_files {
	my ( $self, $cb) = @_;

	opendir( DIR, $self->{base_path} ) || die Wstk::WstkException->new("Couldn't read directory: $!");
	while ( my $fname = readdir(DIR) ) {
		my $fqname = $self->{base_path}.'/'.$fname;
        $cb->($fname) if( -f $fqname );
	}
	closedir(DIR);
}

1;
