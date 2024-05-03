# ******************************************************************************************
#
# (C)2023 aks
# https://github.com/akscf/
# ******************************************************************************************
package PDNS::DAO::ZoneDAO;

use strict;

use Log::Log4perl;
use Wstk::Boolean;
use Wstk::EntityHelper;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PDNS::Models::Zone;
use PDNS::Defs qw(:ZONES);

use constant TABLE_NAME => 'zones';
use constant ENTITY_CLASS_NAME => PDNS::Models::Zone::CLASS_NAME;

sub new ($$;$) {
    my ($class, $pmod) = @_;
    my $self = {
        logger          => Log::Log4perl::get_logger(__PACKAGE__),
        class_name      => $class,
        pmod            => $pmod,
        dbm             => $pmod->{'dbm'},
        system_dao      => $pmod->dao_lookup('SystemDAO')        
    };
    bless($self, $class );

    unless($self->{'dbm'}->table_exists(TABLE_NAME)) {       
        $self->{'logger'}->debug('creating table: ' .TABLE_NAME);        
        my $qres = $self->{'dbm'}->do_query(undef, 'CREATE TABLE '. TABLE_NAME .' '
            .'(id INTEGER PRIMARY KEY, syncId INTEGER NOT NULL, enabled TEXT(5) NOT NULL, name TEXT(255), type TEXT(32), action TEXT(32), ttl INTEGER NOT NULL, script TEXT(255), fwdUrl TEXT(255), authNss TEXT, '
            .' description TEXT(255), options TEXT)'
        );
        
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE UNIQUE INDEX '.TABLE_NAME.'_idx0 ON '.TABLE_NAME.' (id)');
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE INDEX '.TABLE_NAME.'_idx1 ON '.TABLE_NAME.' (name)');

        $self->{'dbm'}->clean($qres);
    }

    return $self;
}

sub get_class_name {
    my ($self) = @_;
    return $self->{class_name};
}

# ---------------------------------------------------------------------------------------------------------------------------------
sub add {
    my ($self, $entity) = @_;
    unless (defined($entity)) {
        die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    
    $entity->id(0);
    $entity->syncId(0);
    $entity->ttl(int($entity->ttl()) > 0 ? $entity->ttl() : 45);
    $entity->name($entity->name() ? lc($entity->name()) : $entity->name());
    $entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
    $entity->type($entity->type() ? uc($entity->type()) : ZONE_TYPE_ORD);
    $entity->action($entity->action() ? uc($entity->action()) : ZONE_ACTION_NONE);
    $entity->options($entity->options() ? $entity->options() : '[]');    

    validate_entity($self, $entity);

    if(is_duplicate($self, $entity)) {
        die Wstk::WstkException->new($entity->name(), RPC_ERR_CODE_ALREADY_EXISTS);
    }
    
    $entity->id(assign_id($self));   
    
    my $qres = $self->{'dbm'}->do_query(undef, 'INSERT INTO '. TABLE_NAME .' '.
        '(id, syncId, enabled, name, type, action, ttl, script, fwdUrl, authNss, description, options) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [ $entity->id(), $entity->syncId(), $entity->enabled(), $entity->name(), $entity->type(), $entity->action(), $entity->ttl(), $entity->script(),
          $entity->fwdUrl(), $entity->authNss(), $entity->description(), $entity->options()
        ]
    );
    $self->{'dbm'}->clean($qres);

    return $entity;
}

sub update {
    my ($self, $entity) = @_;
    validate_entity($self, $entity);

    my $_entity = get($self, $entity->id());
    unless($_entity) {
        die Wstk::WstkException->new($entity->name(), RPC_ERR_CODE_NOT_FOUND);
    }

    if(lc($entity->name()) ne $_entity->name()) {
        $entity->name( $_entity->name() );
    }    
    if($entity->type() ne $_entity->type()) {
        # todo
    }    
    if($entity->action() ne $_entity->action()) {
        # todo
    }
    
    $entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
    $entity->options($entity->options() ? $entity->options() : '[]');
    
    entity_copy_by_fields($_entity, $entity,
        [ 'name', 'enabled', 'type', 'action', 'ttl', 'script', 'fwdUrl', 'authNss', 'description', 'options' ]
    );
    my $qres = $self->{'dbm'}->do_query(undef, 'UPDATE ' . TABLE_NAME .' SET '.
        'name=?, enabled=?, type=?, action=?, ttl=?, script=?, fwdUrl=?, authNss=?, description=?, options=? WHERE id=?',
        [ $_entity->name(), $_entity->enabled(), $_entity->type(), $_entity->action(), $_entity->ttl(), $_entity->script(), $_entity->fwdUrl(), $_entity->authNss(),
          $_entity->description(), $_entity->options(), $_entity->id()
        ]
    );
    $self->{'dbm'}->clean($qres);

    return $_entity;
}

sub delete {
    my ($self, $entity_id) = @_;
    unless(defined($entity_id)) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $entity = get($self, $entity_id);
    unless($entity) { return undef; }

    my $qres = $self->{'dbm'}->do_query(undef, 'DELETE FROM ' . TABLE_NAME . " WHERE id=?", [ int($entity_id)] );
    $self->{'dbm'}->clean($qres);    

    # related objects
    $self->{pmod}->dao_lookup('ZoneRecordDAO')->delete_by_zone($entity_id);

    return $entity;
}

sub get {
    my ($self, $entity_id) = @_;
    my $entity = undef;

    unless (defined($entity_id) ) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $qres = $self->{'dbm'}->do_query(undef,'SELECT * FROM ' . TABLE_NAME . " WHERE id=? LIMIT 1", [ int($entity_id)] );
    if($qres) {
        $entity = map_rs($self, $qres->{'sth'}->fetchrow_hashref() );
    }
    $self->{'dbm'}->clean($qres);

    return $entity;
}

sub list {
    my ($self, $filter) = @_;
    my $result = [];

    my $fofs = filter_get_offset($filter);
    my $flimit = filter_get_limit($filter);
    my $fsortColumn = filter_get_sort_column($filter);
    my $fsortDir = filter_get_sort_direction($filter);
    my $ftext = $self->{'dbm'}->format_like(filter_get_text($filter), 1);

    my $query = "SELECT * FROM ".TABLE_NAME." WHERE id > $fofs";
    $query.=" AND (name LIKE '$ftext' OR description LIKE '$ftext')" if($ftext);
    $query.=" ORDER BY id ASC";
    $query.=' LIMIT '.$flimit if ($flimit);

    my $qres = $self->{'dbm'}->do_query(undef, $query);
    if($qres) {
        while(my $res = $qres->{sth}->fetchrow_hashref()) {            
            push(@{$result}, map_rs($self, $res));   
        }
    }
    $self->{'dbm'}->clean($qres);

    return $result;
}

sub lookup {
    my ($self, $name) = @_;
    my $entity = undef;

    if(is_empty($name)) {
        die Wstk::WstkException->new("name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $qres = $self->{'dbm'}->do_query(undef,'SELECT * FROM ' . TABLE_NAME . " WHERE lower(name)=? LIMIT 1", [ lc($name) ] );
    if($qres) {
        $entity = map_rs($self, $qres->{'sth'}->fetchrow_hashref() );
    }
    $self->{'dbm'}->clean($qres);

    return $entity;
}

sub update_sync_id {
    my ($self, $entity_id) = @_;
    unless(defined($entity_id)) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $qres = $self->{'dbm'}->do_query(undef, 'UPDATE ' . TABLE_NAME . " SET syncId=(syncId + 1) WHERE id=?", [ int($entity_id) ] );
    $self->{'dbm'}->clean($qres);
    return 1;
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
    unless(defined($entity->id())) {
        die Wstk::WstkException->new("Invalid property: id", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if(is_empty($entity->name())) {
        die Wstk::WstkException->new("Invalid property: name", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if(is_empty($entity->type())) {
        die Wstk::WstkException->new("Invalid property: type", RPC_ERR_CODE_VALIDATION_FAIL);
    } else {
        if($entity->type() ne ZONE_TYPE_ORD && $entity->type() ne ZONE_TYPE_AUTH) {
            die Wstk::WstkException->new("Invalid property: type (unsupported)", RPC_ERR_CODE_VALIDATION_FAIL);
        }                
    }
    if(is_empty($entity->action())) {
        die Wstk::WstkException->new("Invalid property: action", RPC_ERR_CODE_VALIDATION_FAIL);
    } else {
        if($entity->action() ne ZONE_ACTION_NONE && $entity->action() ne ZONE_ACTION_FWD && $entity->action() ne ZONE_ACTION_SCRIPT) {
            die Wstk::WstkException->new("Invalid property: action", RPC_ERR_CODE_VALIDATION_FAIL);
        }        
    }
    if($entity->action() eq ZONE_ACTION_FWD && is_empty($entity->fwdUrl())) {
        die Wstk::WstkException->new("Invalid property: fwdUrl", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if($entity->action() eq ZONE_ACTION_SCRIPT && is_empty($entity->script())) {
        die Wstk::WstkException->new("Invalid property: script", RPC_ERR_CODE_VALIDATION_FAIL);
    }
}

sub exists_id {
    my($self, $id) = @_;
    my $result = undef;
    my $qo = $self->{'dbm'}->do_query(undef, 'SELECT id FROM '.TABLE_NAME." WHERE id=? LIMIT 1", [int($id)]);
    if($qo) { $result = (defined($qo->{sth}->fetchrow_array()) ? 1 : undef); }
    $self->{'dbm'}->clean($qo);
    return $result;
}

sub is_duplicate {
    my ($self, $entity ) = @_;
    my $result = undef;
    my $qo = $self->{'dbm'}->do_query(undef, 'SELECT id FROM ' . TABLE_NAME . " WHERE lower(name)=? LIMIT 1", [ lc( $entity->name() )]);
    if($qo) { $result = (defined($qo->{sth}->fetchrow_array()) ? 1 : undef); }
    $self->{'dbm'}->clean($qo);
    return $result;
}

sub assign_id {
    my($self) = @_;
    return $self->{system_dao}->sequence_get(TABLE_NAME);
}

sub map_rs {
    my ($self, $rs) = @_;        
    unless (defined $rs) { return undef; }
    return entity_map(PDNS::Models::Zone->new(), $rs);
}

1;
