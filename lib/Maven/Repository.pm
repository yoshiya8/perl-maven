use strict;
use warnings;

package Maven::Repository;

# ABSTRACT: An repository from which to resolve artifacts
# PODNAME: Maven::Repository

use parent qw(Class::Accessor);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors( qw(url) );

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

    if ( $artifact->get_version() ) {
        # verifiy version is available in repo
        $logger->debug( sub { 'verifying version ',
            $artifact->get_version(),
            ' is available on ', $self->to_string() } );
        return if ( ! $self->_has_version( 
            join( '/', @url ),
            $artifact->get_version() ) );
    }
    else {
        # no version specified, detect latest
        $logger->debug( "version not specified, detecting..." );
        my $version = $self->_detect_latest_version( 
            join( '/', @url ) );

        return if ( ! $version );

        $artifact->set_version( $version );
    }

    my $artifact_name;
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
        if ( defined( $artifact->get_classifier() ) ) {
            $artifact_name .= '-' . $artifact->get_classifier() 
        }
        $artifact_name .= '.' . $artifact->get_packaging();
    }
    else {
        $artifact_name = join( '-', 
            $artifact->get_artifactId(),
            $artifact->get_version() );
        if ( defined( $artifact->get_classifier() ) ) {
            $artifact_name .= '-' . $artifact->get_classifier() 
        }
        $artifact_name .= '.' . $artifact->get_packaging();
    }
    $artifact->set_artifact_name( $artifact_name );

    return join( '/', @url, $artifact->get_version(), $artifact_name );
}

sub _detect_latest_snapshotVersion {
    my ($self, $base_url, $extension, $classifier) = @_;

    $logger->debug( 'loading metadata from ', $base_url );
    my $metadata = Maven::Xml::Metadata->new( agent => $self->_get_agent(),
        url => "$base_url/$self->{metadata_filename}" );
    return if ( ! $metadata );
    return $metadata->get_snapshotVersion( $extension, $classifier );
}

sub _detect_latest_version {
    my ($self, $base_url) = @_;

    $logger->debug( 'loading metadata from ', $base_url );
    my $metadata = Maven::Xml::Metadata->new( agent => $self->_get_agent(),
        url => "$base_url/$self->{metadata_filename}" );
    return if ( ! $metadata );
    return $metadata->get_latest_version();
}

sub _get_agent {
    my ($self) = @_;
    my $agent = $self->{agent};
    if ( !$agent ) {
        require LWP::UserAgent;
        $agent = LWP::UserAgent->new();
        $self->{agent} = $agent;
    }
    return $agent;
}

sub _has_version {
    my ($self, $base_url, $version) = @_;

    $logger->debug( 'loading metadata from ', $base_url );
    my $metadata = Maven::Xml::Metadata->new( agent => $self->_get_agent(),
        url => "$base_url/$self->{metadata_filename}" );
    return if ( ! $metadata );
    return $metadata->has_version( $version );
}

sub _init {
    my ($self, %args) = @_;

    $self->{url} = $args{url};
    $self->{agent} = $args{agent};
    $self->{metadata_filename} = $args{metadata_filename} 
        || 'maven-metadata.xml';

    return $self;
}

sub resolve {
    my ($self, $artifact, @parts) = @_;
    
    if ( ref( $artifact ) ne 'Maven::Artifact' ) {
        $artifact = Maven::Artifact->new( $artifact, @parts );
        $logger->trace( 'resolving ', $artifact );
    }

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