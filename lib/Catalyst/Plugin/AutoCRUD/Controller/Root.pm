package Catalyst::Plugin::AutoCRUD::Controller::Root;

use strict;
use warnings FATAL => 'all';

use base 'Catalyst::Controller';
use Catalyst::Utils;

__PACKAGE__->mk_classdata(_site_conf_cache => {});

sub base : Chained PathPart('autocrud') CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{current_view} = 'AutoCRUD::TT';
    $c->stash->{version} = 'CPAC v'
        . $Catalyst::Plugin::AutoCRUD::VERSION;
    $c->stash->{site} = 'default';
}

# =====================================================================

# old back-compat /<schema>/<source> which uses default site
# also good for friendly URLs which use default site

sub no_db : Chained('base') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->forward('no_schema');
}

sub db : Chained('base') PathPart('') CaptureArgs(1) {
    my ($self, $c) = @_;
    $c->forward('schema');
}

sub no_table : Chained('db') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->forward('no_source');
}

sub table : Chained('db') PathPart('') Args(1) {
    my ($self, $c) = @_;
    $c->forward('source');
}

# new RPC-style which specifies site, schema, source explicitly
# like /site/<site>/schema/<schema>/source/<source>

sub site : Chained('base') PathPart CaptureArgs(1) {
    my ($self, $c, $site) = @_;
    $c->stash->{site} = $site;
}

sub no_schema : Chained('site') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->detach('err_message');
}

sub schema : Chained('site') PathPart CaptureArgs(1) {
    my ($self, $c, $db) = @_;
    $c->stash->{db} = $db;
}

sub no_source : Chained('schema') PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->detach('err_message');
}

sub source : Chained('schema') PathPart Args(1) {
    my ($self, $c) = @_;
    $c->forward('do_meta');
    $c->stash->{title} = $c->stash->{lf}->{main}->{title} .' List';
    $c->stash->{template} = 'list.tt';
}

sub ajax : Chained('schema') PathPart('source') CaptureArgs(1) {
    my ($self, $c) = @_;
    $c->forward('do_meta');
}

# =====================================================================

sub do_meta : Private {
    my ($self, $c, $table) = @_;
    $c->stash->{table} = $table;

    my $db = $c->stash->{db};
    my $site = $c->stash->{site};
    $c->forward('build_site_config');

    # ACLs on the schema and source from site config
    if ($c->stash->{site_conf}->{$db}->{hidden} eq 'yes') {
        if ($site eq 'default') {
            $c->detach('verboden', [$c->uri_for( $self->action_for('no_db') )]);
        }
        else {
            $c->detach('verboden', [$c->uri_for( $self->action_for('no_schema'), [$site] )]);
        }
    }
    if ($c->stash->{site_conf}->{$db}->{$table}->{hidden} eq 'yes') {
        if ($site eq 'default') {
            $c->detach('verboden', [$c->uri_for( $self->action_for('no_table'), [$db] )]);
        }
        else {
            $c->detach('verboden', [$c->uri_for( $self->action_for('no_source'), [$site, $db] )]);
        }
    }

    $c->forward('AutoCRUD::Metadata');
    $c->detach('err_message') if !defined $c->stash->{lf}->{model};
}

sub verboden : Private {
    my ($self, $c, $target, $code) = @_;
    $code ||= 303; # 3xx so RenderView skips template
    $c->response->redirect( $target, $code );
    # detaches -> end
}

sub err_message : Private {
    my ($self, $c) = @_;

    $c->forward('build_site_config') if !exists $c->stash->{site_conf};
    $c->forward('AutoCRUD::Metadata') if !defined $c->stash->{lf}->{db2path};;
    $c->stash->{template} = 'tables.tt';
}

# build site config for filtering the frontend
sub build_site_config : Private {
    my ($self, $c) = @_;
    my $site = $self->_site_conf_cache->{$c->stash->{site}} ||= {};

    # if we have it cached
    if ($site->{__built}) {
        $c->stash->{site_conf} = $site;
        $c->log->debug(sprintf "autocrud: retreived cached config for site [%s]",
            $c->stash->{site}) if $c->debug;
        return;
    }

    # first, prime our structure of schema and source aliases
    # get stash of db path parts
    my $lf = $c->forward(qw/AutoCRUD::Metadata build_db_info/);
    foreach my $db (keys %{$lf->{dbpath2model}}) {
        $site->{$db} ||= {};
        # get stash of table path parts
        $c->forward(qw/AutoCRUD::Metadata build_table_info_for_db/, [$lf, $db]);
        foreach my $table (keys %{$lf->{path2model}->{$db}}) {
            $site->{$db}->{$table} ||= {};
        }
    }

    # load whatever the user set in their site config
    $site = Catalyst::Utils::merge_hashes(
        ($c->config->{'Catalyst::Plugin::AutoCRUD'}->{sites}->{$c->stash->{site}} || {}),
        $site);

    my %defaults = (
        frontend => 'default',
        create_allowed => 'yes',
        update_allowed => 'yes',
        delete_allowed => 'yes',
        hidden => 'no',
    );

    # merge defaults into user prefs
    $site = Catalyst::Utils::merge_hashes (\%defaults, $site);

    # then bubble up the prefs until each source def has a complete set
    foreach my $sc (keys %{$site}) {
        next unless ref $site->{$sc} eq 'HASH';
        $site->{$sc} = Catalyst::Utils::merge_hashes ({
                map {($_ => $site->{$_})} keys %defaults
            }, $site->{$sc});

        foreach my $so (keys %{$site->{$sc}}) {
            next unless ref $site->{$sc}->{$so} eq 'HASH';
            $site->{$sc}->{$so} = Catalyst::Utils::merge_hashes ({
                    map {($_ => $site->{$sc}->{$_})} keys %defaults
                }, $site->{$sc}->{$so});
            # promote arrayref into hashref
            if (exists $site->{$sc}->{$so}->{list_returns}
                and ref $site->{$sc}->{$so}->{list_returns} eq 'ARRAY') {
                $site->{$sc}->{$so}->{list_returns} = {map {($_ => '')
                    } @{$site->{$sc}->{$so}->{list_returns}}};
            }
        }
    }

    $site->{__built} = 1;
    $c->stash->{site_conf} = $site;
    $self->_site_conf_cache->{$c->stash->{site}} = $site;

    $c->log->debug(sprintf "autocrud: cached the config for site [%s]",
            $c->stash->{site}) if $c->debug;
}

sub helloworld : Chained('base') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'helloworld.tt';
}

sub end : ActionClass('RenderView') {}

1;
__END__
