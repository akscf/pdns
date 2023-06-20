# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PDNS::DAO::ZoneRecordDAO;

use strict;

use Log::Log4perl;
use Wstk::Boolean;
use Wstk::EntityHelper;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PDNS::Models::ZoneRecord;

use constant TABLE_NAME => 'zone_records';
use constant ENTITY_CLASS_NAME => PDNS::Models::ZoneRecord::CLASS_NAME;

sub new ($$;$) {
    my ($class, $pmod) = @_;
    my $self = {
        logger          => Log::Log4perl::get_logger(__PACKAGE__),
        class_name      => $class,
        pmod            => $pmod,
        dbm             => $pmod->{'dbm'},
        system_dao      => $pmod->dao_lookup('SystemDAO'),
        zone_dao        => $pmod->dao_lookup('ZoneDAO'),
    };
    bless($self, $class );

    unless($self->{'dbm'}->table_exists(TABLE_NAME)) {       
        $self->{'logger'}->debug('creating table: ' .TABLE_NAME);        
        my $qres = $self->{'dbm'}->do_query(undef, 'CREATE TABLE '. TABLE_NAME .' '
            .'(id INTEGER PRIMARY KEY, zoneId INTEGER NOT NULL, syncId INTEGER NOT NULL, enabled TEXT(5) NOT NULL, ttl INTEGER NOT NULL, name TEXT(128), '
            .' fqName TEXT(255), type TEXT(32), data TEXT, description TEXT(255), options TEXT)'
        );
        
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE UNIQUE INDEX '.TABLE_NAME.'_idx0 ON '.TABLE_NAME.' (id)');
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE INDEX '.TABLE_NAME.'_idx1 ON '.TABLE_NAME.' (zoneId)');
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE INDEX '.TABLE_NAME.'_idx2 ON '.TABLE_NAME.' (fqName)');
        $self->{'dbm'}->do_query($qres->{'dbh'}, 'CREATE INDEX '.TABLE_NAME.'_idx3 ON '.TABLE_NAME.' (type)');

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
    $entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
    $entity->options($entity->options() ? $entity->options() : '[]');
    
    validate_entity($self, $entity);
    
    my $zone = $self->{zone_dao}->get($entity->zoneId());
    unless($zone) {
        die Wstk::WstkException->new('zone #'.$entity->zoneId(), RPC_ERR_CODE_NOT_FOUND);
    }

    my $zname = $zone->name();
    $entity->name(rname_clean($self, lc($entity->name()), $zname) );
    $entity->fqName($entity->name(). "." .$zname);
    $entity->ttl(int($entity->ttl()) > 0 ? $entity->ttl() : $zone->ttl());
    
    $entity->id(assign_id($self));
    
    my $qres = $self->{'dbm'}->do_query(undef, 'INSERT INTO '. TABLE_NAME .' '.
        '(id, zoneId, syncId, enabled, ttl, name, fqName, type, data, description, options) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [ $entity->id(), $entity->zoneId(), $entity->syncId(), $entity->enabled(), $entity->ttl(), $entity->name(), $entity->fqName(),
          $entity->type(), $entity->data(), $entity->description(), $entity->options()
        ]
    );
    $self->{'dbm'}->clean($qres);

    # update zone syncId
    $self->{zone_dao}->update_sync_id( $zone->id() );

    return $entity;
}

sub update {
    my ($self, $entity) = @_;
    validate_entity($self, $entity);

    my $_entity = get($self, $entity->id());
    unless($_entity) {
        die Wstk::WstkException->new($entity->fqName(), RPC_ERR_CODE_NOT_FOUND);
    }

    my $zone = $self->{zone_dao}->get($entity->zoneId());
    unless($zone) {
        die Wstk::WstkException->new('zone #'.$entity->zoneId(), RPC_ERR_CODE_NOT_FOUND);
    }

    if(lc($entity->name()) ne $_entity->name()) {
        my $zname = $zone->name();
        $entity->name(rname_clean($self, lc($entity->name()), $zname) );
        $entity->fqName($entity->name(). "." .$zname);
    }

    $entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
    $entity->options($entity->options() ? $entity->options() : '[]');
    
    entity_copy_by_fields($_entity, $entity,
        [ 'name', 'fqName', 'enabled', 'type', 'data', 'ttl', 'description', 'options' ]
    );

    my $qres = $self->{'dbm'}->do_query(undef, 'UPDATE ' . TABLE_NAME .' SET '.
        'name=?, fqName=?, enabled=?, type=?, data=?, ttl=?, description=?, options=?, syncId=(syncId + 1) WHERE id=?',
        [ $_entity->name(), $entity->fqName(), $_entity->enabled(), $_entity->type(), $_entity->data(), $_entity->ttl(), $_entity->description(), $_entity->options(), $_entity->id() ]
    );
    $self->{'dbm'}->clean($qres);
    
    # update zone syncId
    $self->{zone_dao}->update_sync_id( $zone->id() );

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

    # update zone syncId
    my $zone = $self->{zone_dao}->get($entity->zoneId());
    if($zone) {
        $self->{zone_dao}->update_sync_id( $zone->id() );
    }

    return $entity;
}

sub delete_by_zone {
    my ($self, $zone_id) = @_;
    unless(defined($zone_id)) {
        die Wstk::WstkException->new("zone_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $qres = $self->{'dbm'}->do_query(undef, 'DELETE FROM ' . TABLE_NAME . " WHERE zoneId=?", [ int($zone_id)] );
    $self->{'dbm'}->clean($qres);
    
    return 1;
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
    my ($self, $zone_id, $filter) = @_;
    my $result = [];

    my $fofs = filter_get_offset($filter);
    my $flimit = filter_get_limit($filter);
    my $fsortColumn = filter_get_sort_column($filter);
    my $fsortDir = filter_get_sort_direction($filter);
    my $ftext = $self->{'dbm'}->format_like(filter_get_text($filter), 1);

    my $query = "SELECT * FROM ".TABLE_NAME." WHERE id > $fofs";
    $query.=" AND zoneId=".int($zone_id) if(defined($zone_id));
    $query.=" AND (fqName LIKE '$ftext' OR data LIKE '$ftext' OR description LIKE '$ftext')" if($ftext);
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
    my ($self, $name, $type) = @_;
    my $result = [];

    if(is_empty($name)) {
        die Wstk::WstkException->new("name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    if(is_empty($type)) {
        die Wstk::WstkException->new("type", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    
    my $qres = $self->{'dbm'}->do_query(undef,'SELECT * FROM ' . TABLE_NAME . " WHERE lower(fqName)=? AND upper(type)=? ORDER BY id ASC", [ lc($name), uc($type) ] );
    if($qres) {
        while(my $res = $qres->{sth}->fetchrow_hashref()) {
            push(@{$result}, map_rs($self, $res));
        }
    }
    $self->{'dbm'}->clean($qres);

    return $result;
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
    unless(defined($entity->zoneId())) {
        die Wstk::WstkException->new("Invalid property: zoneId", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if(is_empty($entity->name())) {
        die Wstk::WstkException->new("Invalid property: name", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if(is_empty($entity->type())) {
        die Wstk::WstkException->new("Invalid property: type", RPC_ERR_CODE_VALIDATION_FAIL);
    } else {
        # todo: validate type
    }
    if(is_empty($entity->data())) {
        die Wstk::WstkException->new("Invalid property: data", RPC_ERR_CODE_VALIDATION_FAIL);
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

sub assign_id {
    my($self) = @_;
    return $self->{system_dao}->sequence_get(TABLE_NAME);
}

sub map_rs {
    my ($self, $rs) = @_;        
    unless (defined $rs) { return undef; }
    return entity_map(PDNS::Models::ZoneRecord->new(), $rs);
}
sub rname_clean {
    my ($self, $rname, $zname) = @_;
    $rname =~ s/$zname//; 
    $rname =~ s/\.+$//;
    return $rname;
}

1;
