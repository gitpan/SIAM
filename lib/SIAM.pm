package SIAM;

use warnings;
use strict;

use base 'SIAM::Object';

use SIAM::Contract;
use SIAM::User;
use SIAM::Privilege;
use SIAM::Attribute;

=head1 NAME

SIAM - Service Inventory Abstraction Model

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    use SIAM;

    # Example SIAM configuration. You would normally load it
    # from a YAML file instead of inline Perl
    my $config = {
      'Driver' => {
        'Class' => 'XYZ::SIAM::Driver',
        'Options' => {
          'dblink' => {
            'dsn' => 'DBI:mysql:database=xyz_inventory;host=dbhost',
            'username' => 'siam',
            'password' => 'Lu9iifoo',
          },
          'logger' => {
            'screen' => {
              'log_to'   => 'STDERR',
              'maxlevel' => 'warning',
              'minlevel' => 'emergency',
          },
        },
      },
      'Root' => {
        'Attributes' => {
          'siam.enterprise_name' => 'XYZ Inc.',
          'siam.enterprise_url' => 'http://www.example.com',
          'siam.enterprise_logo_url' => 'http://www.example.com/l.png',
        },
      },
    };

    my $siam = new SIAM($config) or die('Failed loading SIAM');
    $siam->connect() or die('Failed connecting to SIAM');

    # The monitoring system would normally need all the contracts.
    # Walk down the hierarchy and retrieve the data for the
    # monitoring software configuration

    my $all_contracts = $siam->get_all_contracts();
    foreach my $contract (@{$all_contracts}) {
      my $services = $contract->get_services();
      foreach my $service (@{$services}) {
        my $units = $service->get_service_units();
        foreach my $unit (@{$units}) {
          # some useful attributes for the physical unit
          my $host = $unit->attr('access.node.name');
          my $port = $unit->attr('access.port.name');

          # statistics associated with the service unit
          my $dataelements = $unit->get_data_elements();
          foreach my $element (@{$dataelements}) {
            # do something with the element attributes            
          }
        }
      }
    }
                                     
    # The front-end system deals with privileges
    my $user = $siam->get_user($uid) or return([0, 'User not found']);

    # All the contracts this user is allowed to see
    my $contracts =
      $siam->get_contracts_by_user_privilege($user, 'ViewContract');

    # ... walk down the hierarchy as shown above ...

    # Prepare the unit attributes for display
    my $attrs =
      $siam->filter_visible_attributes($user, $unit->attributes());
        
    # Random access to an object
    my $el =
      $siam->instantiate_object('SIAM::ServiceDataElement', $id);

    # Check privileges on a contract
    if( $user->has_privilege('ViewContract', $contract) ) {
      ...
    }

    # close the database connections
    $siam->disconnect()


=head1 INTRODUCTION

Many Service Provider companies (ISP, Hosting, Carriers, ...) have their
own, historically developed, databases for customer service
inventory. Therefore any system that would require access to such data
should be adapted to the local environment.

SIAM is intended as a common API that would connect to
enterprise-specific service inventory systems and present the inventory
data in a uniform format. The purpose of this universal API is to reduce
the integration costs for such software systems as network monitoring,
CRM, Customer self-service portals, etc.

We assume that monitoring systems (such as: Torrus, ...) and front-end
systems (such as: Customer portal, Extopus, ...) would connect to SIAM
to retrieve any service-specific information, and SIAM would deliver a
complete set of data required for those client applications.

SIAM does not include any database of its own: all data is retrieved
directly from the enterprise systems and databases. The SIAM library
communicates with the enterprise-specific I<driver> and presents
the data in an abstracted way.

SIAM takes its configuration data from a single hierarchical data
structure. This data is usually read from a YAML file. The
configuration describes all data connections, driver configuration,
enterprise-specific modules, etc.

The SIAM core modules are distributed as an open-source Perl package
available at CPAN. Enterprise-specific modules are integrated in a way
that the core can be upgraded without breaking any local setup.


=head1 METHODS

=head2 new

Expects a hashref with SIAM configuration.

=head3 Configuration

=over 4

=item * Driver

A hash with two entries: C<Class> identifying the driver module class
which is going to be C<require>'d; and C<Options>, a hash which is
supplied to the driver's C<new> method.

=item * Root

A hash that sets properties for the root object. The key C<Attributes>
is expected, pointing to the following mandatory attributes:

=over 8

=item * siam.enterprise_name

=item * siam.enterprise_url

=item * siam.enterprise_logo_url

=back

=back

=cut

sub new
{
    my $class = shift;
    my $config = shift;

    my $drvclass = $config->{'Driver'}{'Class'};
    if( not defined($drvclass) )
    {
        SIAM::Object->critical
              ('Missing Driver->Class in SIAM configuration');
        return undef;
    }
    
    my $drvopts = $config->{'Driver'}{'Options'};
    if( not defined($drvopts) )
    {
        SIAM::Object->critical
              ('Missing Driver->Options in SIAM configuration');
        return undef;
    }

    eval('require ' . $drvclass);
    if( $@ )
    {
        SIAM::Object->critical($@);
        return undef;
    }
    
    my $driver = eval($drvclass . '->new($drvopts)');
    if( $@ )
    {
        SIAM::Object->critical($@);
        return undef;
    }
    
    if( not defined($driver) )
    {
        SIAM::Object->critical('Failed to initialize the driver');
        return undef;
    }

    my $root_attr = $config->{'Root'}{'Attributes'};
    if( not defined($root_attr) )
    {
        SIAM::Object->critical
              ('Missing Root->Attributes in SIAM configuration');
        return undef;
    }

    my $self = $class->SUPER::new( $driver, 'SIAM.ROOT' );
    return undef unless defined($self);
    
    foreach my $key ('siam.enterprise_name',
                     'siam.enterprise_url',
                     'siam.enterprise_logo_url')
    {
        if( defined($root_attr->{$key}) )
        {
            $self->{'_attr'}{$key} = $root_attr->{$key};
        }
        else
        {
            SIAM::Object->critical
                  ('Missing mandatory attribute "' . $key .
                   '" in SIAM configuration');
            return undef;
        }            
    }    
    
    return $self;
}


=head2 connect

Connects the driver to its databases. Returns false in case of problems.

=cut

sub connect
{
    my $self = shift;
    if( not $self->_driver->connect() )
    {
        $self->error($self->_driver->errmsg);
        return undef;
    }

    return 1;
}


=head2 disconnect

Disconnects the driver from its underlying databases.

=cut

sub disconnect
{
    my $self = shift;
    $self->_driver->disconnect();
}


=head2 instantiate_object

Expects the object class and ID. Returns an object retrieved from the driver.

=cut

sub instantiate_object
{
    my $self = shift;
    my $obj_class = shift;
    my $obj_id = shift;

    my $obj = eval 'new ' . $obj_class . '($self->_driver, $obj_id)';
    if( $@ )
    {
        $self->error('Cannot instantiate object of class "' . $obj_class .
                     '" and ID "' . $obj_id . '": ' . $@);
        return undef;
    }
    
    return $obj;
}


=head2 get_user

Expects a UID string as an argument. Returns a C<SIAM::User> object or undef.

=cut

sub get_user
{
    my $self = shift;
    my $uid = shift;

    my $users = $self->get_contained_objects
        ('SIAM::User', {'match_attribute' => ['user.uid', [$uid]]});
    if( scalar(@{$users}) > 1 )
    {
        $self->error('Driver returned more than one SIAM::User object with ' .
                     'user.uid=' . $uid);
    }
    return $users->[0];
}


=head2 get_all_contracts

Returns an arrayref with all available C<SIAM::Contract> objects.

=cut

sub get_all_contracts
{
    my $self = shift;
    return $self->get_contained_objects('SIAM::Contract');
}



=head2 get_contracts_by_user_privilege

  my $user_contracts =
      $siam->get_contracts_by_user_privilege($user, 'ViewContract');

Arguments: C<SIAM::User> object and a privilege string.  Returns
arrayref with all available C<SIAM::Contract> objects that match the
privilege.

=cut

sub get_contracts_by_user_privilege
{
    my $self = shift;
    my $user = shift;
    my $priv = shift;

    return $user->get_objects_by_privilege($priv, 'SIAM::Contract', $self);
}
         


=head2 filter_visible_attributes

   my $visible_attrs =
       $siam->filter_visible_attributes($user, $object_attrs);

Arguments: C<SIAM::User> object and a hashref with object attributes.
Returns a new hashref with copies of attributes which are allowed to be
shown to the user as specified by C<ViewAttribute> privileges.

=cut

sub filter_visible_attributes
{
    my $self = shift;
    my $user = shift;
    my $attrs_in = shift;

    my $attrs_out = {};

    # Fetch SIAM::Attribute objects only once and cache them by attribute.name
    if( not defined($self->{'siam_attribute_objects'}) )
    {
        $self->{'siam_attribute_objects'} = {};
        foreach my $obj (@{ $self->get_contained_objects('SIAM::Attribute') })
        {
            $self->{'siam_attribute_objects'}{$obj->name} = $obj;
        }
    }

    my $privileges = $user->get_contained_objects
        ('SIAM::Privilege',
         {'match_attribute' => ['privilege.type', ['ViewAttribute']]});
    
    foreach my $privilege (@{$privileges})
    {
        if( $privilege->matches_all('SIAM::Attribute') )
        {
            # this user can see all. Copy everything and return.
            while( my($key, $val) = each %{$attrs_in} )
            {
                $attrs_out->{$key} = $val;
            }

            return $attrs_out;
        }
        else
        {
            while( my($key, $val) = each %{$attrs_in} )
            {
                my $attr_obj = $self->{'siam_attribute_objects'}{$key};
                if( defined($attr_obj) and
                    $privilege->match_object($attr_obj) )
                {
                    $attrs_out->{$key} = $val;
                }
            }
        }
    }

    return $attrs_out;
}

    

=head1 SEE ALSO

L<SIAM::Documentation::DataModel>, L<SIAM::Documentation::DriverSpec>


=head1 AUTHOR

Stanislav Sinyagin, C<< <ssinyagin at k-open.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-siam at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SIAM>.  I will be
notified, and then you'll automatically be notified of progress on your
bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SIAM


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SIAM>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/SIAM>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/SIAM>

=item * Search CPAN

L<http://search.cpan.org/dist/SIAM/>

=back



=head1 LICENSE AND COPYRIGHT

Copyright 2011 Stanislav Sinyagin.

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.


=cut

1;

# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
