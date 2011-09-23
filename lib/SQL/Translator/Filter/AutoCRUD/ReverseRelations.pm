package SQL::Translator::Filter::AutoCRUD::ReverseRelations;

use strict;
use warnings FATAL => 'all';

use Scalar::Util 'blessed';
use Lingua::EN::Inflect::Number;
use SQL::Translator::Schema::Constants 'FOREIGN_KEY';
use Algorithm::Permute;

sub make_label { return join ' ', map ucfirst, split /[\W_]+/, lc shift }

sub make_path {
    my $item = shift;
    return $item if $item =~ m/^\w+$/;

    $item =~ s/(\w)([A-Z][a-z0-9])/$1_$2/g;
    return lc $item;
}

sub add_to_fields_at {
    my ($extra, $field) = @_;
    my $name = $field->{name};

    if ($field->{extra}->{rel_type} =~ m/^(?:has_many|many_to_many)$/) {
        $name = Lingua::EN::Inflect::Number::to_PL($name);
        $field->{name} = $name;
    }

    if ($extra->{seen}->{$name}++
        and $field->{extra}->{rel_type} ne 'many_to_many') {
        # we have multiple rels between same two tables
        # rename each to refer to the rel on which it is based

        if (exists $extra->{_new_fields}->{$name}) {
            my $uniq_name = $name .'_'. join '_', @{$extra->{_new_fields}->{$name}->{ref_fields}};
            $extra->{_new_fields}->{$name}->{name} = $uniq_name;
            $extra->{_new_fields}->{$name}->{extra}->{display_name} = make_label($uniq_name);
            $extra->{_new_fields}->{$uniq_name} = delete $extra->{_new_fields}->{$name};
        }

        $name = $name .'_'. join '_', @{$field->{ref_fields}};
        $field->{name} = $name;
    }

    $field->{data_type} = 'text';
    $field->{is_foreign_key} = 1;
    $field->{extra}->{is_reverse} = 1;
    $field->{extra}->{display_name} = make_label($name);

    $extra->{_new_fields}->{$name} = $field;
}

sub filter {
    my ($schema, @args) = @_;

    foreach my $local_table ($schema->get_tables) {
        $local_table = $schema->get_table($local_table)
            if not blessed $local_table;

        $local_table->extra('seen' => {});
        foreach my $c ($local_table->get_constraints) {
            next unless $c->type eq FOREIGN_KEY;
            next if $local_table->extra('seen')->{$c->name}++;

            my $remote_table = $c->reference_table;
            $remote_table = $schema->get_table($remote_table)
                if not blessed $remote_table;

            if (scalar (grep {not ($_->is_unique or $_->is_primary_key)} $c->fields) == 0) {
                # all FK are unique so is one-to-one
                # but we cannot distinguish has_one/might_have
                add_to_fields_at(scalar $remote_table->extra, {
                    name => $local_table->name,
                    extra => {
                        ref_table => $local_table->name,
                        ref_fields => [map {"$_"} @{$c->fields}],
                        rel_type => 'might_have',
                    }
                });
            }
            else {
                add_to_fields_at(scalar $remote_table->extra, {
                    name => $local_table->name,
                    extra => {
                        ref_table => $local_table->name,
                        ref_fields => [map {"$_"} @{$c->fields}],
                        rel_type => 'has_many',
                    }
                });
            }

            # check whether there are additional rels for a m2m link
            my %remote_names = ();

            foreach my $rel ($local_table->get_constraints) {
                next unless $rel->type eq FOREIGN_KEY;
                next unless scalar (grep {$_->is_nullable} $rel->fields) == 0;
                # FIXME configurable reject of tables with non link columns
                $remote_names{$rel->reference_table.''} = [map {"$_"} $rel->fields];
            }

            # we don't make a hash as it could be a many_to_many to same table
            # but it must be at least two relations, for this heuristic to work
            if (scalar keys %remote_names >= 2) {
                my $p = Algorithm::Permute->new([keys %remote_names], 2);

                while ( my ($left, $right) = $p->next ) {
                    add_to_fields_at(scalar $schema->get_table($left)->extra, {
                        name => $right,
                        extra => {
                            ref_table => $right,
                            ref_fields => [map {"$_"} $schema->get_table($right)->primary_key->fields],
                            rel_type => 'many_to_many',
                            via => [
                                Lingua::EN::Inflect::Number::to_PL($local_table->name),
                                @{$remote_names{$right}}
                            ],
                        },
                    });
                }
            }
        } # constraints
    } # tables

    # install these reverse relations as regular SQLT fields
    foreach my $table ($schema->get_tables) {
        $table = $schema->get_table($table)
            if not blessed $table;

        $table->remove_extra('seen');
        next unless defined scalar $table->extra('_new_fields');

        $table->add_field(%$_) for values %{ $table->extra('_new_fields') };
        $table->remove_extra('_new_fields');
    }
} # sub filter

1;
