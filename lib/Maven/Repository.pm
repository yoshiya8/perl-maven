use strict;
use warnings;

package Maven::Repository;

# ABSTRACT: An repository from which to resolve artifacts
# PODNAME: Maven::Repository

use parent qw(Class::Accessor);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors( qw(agent url) );

use Carp;
use Log::Any;
use Maven::Artifact;
use Maven::Xml::Metadata;

my $logger = Log::Any->get_logger();

sub new {
    my ($class, @args) = @_;
    my $self = bless( {}, $class );

    return $self->_init( @args );
}

sub _build_url {
    my ($self, $artifact) = @_;

    my @url = ( 
        $self->{url},
        split( /\./, $artifact->get_groupId() ),
        $artifact->get_artifactId()
    );

    my $artifact_name;
    if ( ! $artifact->get_version() ) {
        # no version specified, detect latest
        $logger->debug( "version not specified, detecting..." );
        my $version = $self->_detect_latest_version( 
            join( '/', @url ) );

        return if ( ! $version );

        $artifact->set_version( $version );
    }
    if ( $artifact->get_version() =~ /^.*-SNAPSHOT$/ ) {
        # snapshot version, detect most recent timestamp
        my $snapshotVersion = $self->_detect_latest_snapshotVersion( 
            join( '/', @url, $artifact->get_version() ),
            $artifact->get_packaging(),
            $artifact->get_classifier() );

        return if ( ! $snapshotVersion );

        $artifact_name = join( '-', 
            $artifact->get_artifactId(),
            $snapshotVersion->get_value() );
        if ( $artifact->get_classifier() ) {
            $artifact_name .= '-' . $artifact->get_classifier() 
        }
        $artifact_name .= '.' . $artifact->get_packaging();
    }
    else {
        $artifact_name = join( '-', 
            $artifact->get_artifactId(),
            $artifact->get_version() );
        if ( $artifact->get_classifier() ) {
            $artifact_name .= '-' . $artifact->get_classifier() 
        }
        $artifact_name .= '.' . $artifact->get_packaging();
    }
    $artifact->set_artifact_name( $artifact_name );

    my $url = join( '/', @url, $artifact->get_version(), $artifact_name );
    # verify version is available in repo
    $logger->debug( sub { 'verifying version ',
        $artifact->get_version(),
        ' is available on ', $self->to_string() } );
    return $self->_has_version( $url ) ? $url : undef;
}

sub contains {
    my ($self, $url) = @_;
    return $self->{url} eq substr($url, 0, length($self->{url}));
}

sub _detect_latest_snapshotVersion {
    my ($self, $base_url, $extension, $classifier) = @_;

    $logger->debug( 'loading metadata from ', $base_url );
    my $metadata = Maven::Xml::Metadata->new( agent => $self->{agent},
        url => "$base_url/$self->{metadata_filename}" );
    return if ( ! $metadata );

    my $latest_snapshot;
    foreach my $snapshot_version ( @{$metadata->get_versioning()->get_snapshotVersions()} ) {
        if ( $extension && $extension eq $snapshot_version->get_extension() ) {
            if ( !$classifier || $classifier eq $snapshot_version->get_classifier() ) {
                $latest_snapshot = $snapshot_version;
                last;
            }
        }
    }
    return $latest_snapshot;
}

sub _detect_latest_version {
    my ($self, $base_url) = @_;

    $logger->debug( 'loading metadata from ', $base_url );
    my $metadata = Maven::Xml::Metadata->new( agent => $self->{agent},
        url => "$base_url/$self->{metadata_filename}" );
    return if ( ! $metadata );
    return $metadata->get_versioning()->get_latest();
}

sub _has_version {
    my ($self, $url) = @_;
    $logger->debug( '_has_version(', $url, ')' );
    return $self->{agent}->head( $url )->is_success();
}

sub _init {
    my ($self, $url, %args) = @_;

    $self->{url} = $url;
    if ($args{agent}) {
        $self->{agent} = $args{agent};
    }
    else {
        require Maven::LwpAgent;
        $self->{agent} = Maven::LwpAgent->new();
    }
    $self->{metadata_filename} = $args{metadata_filename} 
        || 'maven-metadata.xml';

    return $self;
}

sub resolve {
    my ($self, $artifact, @parts) = @_;
    
    if ( ref( $artifact ) eq 'Maven::Artifact' ) {
        # already resolved, no need to do so again
        return $artifact if ( $artifact->get_url() );
    }
    else {
        $artifact = Maven::Artifact->new( $artifact, @parts );
        $logger->trace( 'resolving ', $artifact );
    }
    croak( 'invalid artifact, no groupId' ) if ( !$artifact->get_groupId() );
    croak( 'invalid artifact, no artifactId' ) if ( !$artifact->get_artifactId() );
    
    my $url = $self->_build_url( $artifact );
    if ( defined( $url ) ) {
        $artifact->set_url( $url );
        return $artifact;
    }
    return;
}

sub to_string {
    my ($self) = @_;
    return $self->{url};
}

1;
