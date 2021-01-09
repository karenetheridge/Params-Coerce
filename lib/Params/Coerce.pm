package Params::Coerce;
# ABSTRACT: Allows your classes to do coercion of parameters

=pod

=head1 NAME


=head1 SYNOPSIS

  # Coerce a object of class Foo to a Bar
  my $bar = Params::Coerce::coerce('Bar', $Foo)

  # Create a coercion param function
  use Params::Coerce '_Bar' => 'Bar';
  my $bar = _Bar($Foo);

  # Usage when Bar has a 'from' method
  my $bar = Bar->from($Foo);

Real world example using L<HTML::Location>.

  # My class needs a URI
  package Web::Spider;

  use URI;
  use Params::Coerce 'coerce';

  sub new {
      my $class = shift;

      # Where do we start spidering
      my $start = coerce('URI', shift) or die "Wasn't passed a URI";

      bless { root => $start }, $class;
  }

  #############################################
  # Now we can do the following

  # Pass a URI as normal
  my $URI     = URI->new('http://ali.as/');
  my $Spider1 = Web::Spider->new( $URI );

  # We can also pass anything that can be coerced into being a URI
  my $Website = HTML::Location->new( '/home/adam/public_html', 'http://ali.as' );
  my $Spider2 = Web::Spider->new( $Website );

=head1 DESCRIPTION

A big part of good API design is that we should be able to be flexible in
the ways that we take parameters.

Params::Coerce attempts to encourage this, by making it easier to take a
variety of different arguments, while adding negligible additional complexity
to your code.

=head2 What is Coercion

"Coercion" in computing terms generally refers to "implicit type
conversion". This is where data and object are converted from one type to
another behind the scenes, and you just just magically get what you need.

The L<overload> pragma, and its string overloading is the form of coercion
you are most likely to have encountered in Perl programming. In this case,
your object is automatically (within perl itself) coerced into a string.

C<Params::Coerce> is intended for higher-order coercion between various
types of different objects, for use mainly in subroutine and (mostly)
method parameters, particularly on external APIs.

=head2 __as_Another_Class Methods

At the heart of C<Params::Coerce> is the ability to transform objects from
one thing to another. This can be done by a variety of different
mechanisms.

The preferred mechanism for this is by creating a specially named method
in a class that indicates it can be coerced into another type of object.

As an example, L<HTML::Location> provides an object method that returns an
equivalent L<URI> object.

  # In the package HTML::Location

  # Coerce to a URI
  sub __as_URI {
  	my $self = shift;
 	return URI->new( $self->uri );
  }

=head2 __from_Another_Class Methods

From version 0.04 of C<Params::Coerce>, you may now also provide
__from_Another_Class methods as well. In the above example, rather then
having to define a method in L<HTML::Location>, you may instead define
one in L<URI>. The following code has an identical effect.

  # In the package URI

  # Coerce from a HTML::Location
  sub __from_HTML_Location {
  	my $Location = shift;
  	return URI->new( $Location->uri );
  }

C<Params::Coerce> will only look for the __from method, if it does not
find a __as method.

=head2 Loading Classes

One thing to note with the C<__as_Another_Class> methods is that you are
B<not> required to load the class you are converting to in the class you
are converting from.

In the above example, L<HTML::Location> does B<not> have to load the URI
class. The need to load the classes for every object we might some day need
to be coerced to would result in highly excessive resource usage.

Instead, C<Params::Coerce> guarantees that the class you are converting to
C<will> be loaded before it calls the __as_Another_Class method. Of course,
in most situations you will have already loaded it for another purpose in
either the From or To classes and this won't be an issue.

If you make use of some class B<other than> the class you are being coerced
to in the __as_Another_Class method, you will need to make sure that is loaded
in your code, but it is suggested that you do it at run-time with a
C<require> if you are not using it already elsewhere.

=head2 Coercing a Parameter

The most explicit way of accessing the coercion functionality is with the
Params::Coerce::coerce function. It takes as its first argument the name
of the class you wish to coerce B<to>, followed by the parameter to which you
wish to apply the coercion.

  package My::Class;

  use URI ();
  use Params::Coerce '_URI' => 'URI';

  sub new {
  	my $class = shift;

  	# Take a URI argument
  	my $URI = Params::Coerce::coerce('URI', shift) or return;

  	...
  }

For people doing procedural programming, you may also import this function.

  # Import the coerce function
  use Params::Coerce 'coerce';

Please note that the C<coerce> function is the B<only> function
that can be imported, and that the two argument pragma (or the passing of
two or more arguments to ->import) means something different entirely.

=head2 Importing Parameter Coercion Methods

The second way of using Params::Coerce, and the more common one for
Object-Oriented programming, is to create method specifically for taking
parameters in a coercing manner.

  package My::Class;

  use URI ();
  use Params::Coerce '_URI' => 'URI';

  sub new {
  	my $class = shift;

	# Take a URI as parameter
  	my $URI1 = $class->_URI(shift) or return;
  	my $URI2 = _URI(shift) or return;
  	...
  }

=head2 The C<from> Constructor

From version C<0.11> of C<Params::Coerce>, an additional mechanism is
available with the importable C<from> constructor.

  package My::Class;

  use Params::Coerce 'from';

  package Other::Class;

  sub method {
  	my $self = shift;
  	my $My   = My::Class->from(shift) or die "Bad param";
  	...
  }

This is mainly a convenience. The above is equivalent to

  package My::Class;

  use Params::Coerce 'from' => 'Params::Coerce';

In future versions, this C<-E<gt>from> syntax may also tweak the resolution
order of the coercion.

=head2 Chained Coercion

While it is intended that Params::Coerce will eventually support coercion
using multiple steps, like C<<Foo::Bar->__as_HTML_Location->__as_URI>>,
it is not currently capable of this. At this time only a single coercion
step is supported.

=head1 FUNCTIONS

=cut

use 5.006;
use strict;
use Carp         ();
use Scalar::Util ();
use Params::Util '_IDENTIFIER',
                 '_INSTANCE',
                 '_CLASS';

# Load Overhead: 52k

our $VERSION = '0.16';

# The hint cache
my %hints = ();





#####################################################################
# Use as a Pragma

sub import {
	my $class = shift;
	my @param = @_ or return;
	Carp::croak("Too many parameters") if @param > 2; # Um, what?

	# We'll need to know who is calling us
	my $pkg = caller();

	# We export them the coerce function if they want it
	if ( @param == 1 ) {
		if ( $param[0] eq 'coerce' ) {
			no strict 'refs';
			*{"${pkg}::coerce"} = *coerce;
			return 1;
		} elsif ( $param[0] eq 'from' ) {
			# They want a from constructor
			no strict 'refs';
			*{"${pkg}::from"} = *from;
			return 1;
		} else {
			Carp::croak "Params::Coerce does not export '$_[0]'";
		}
	}

	# The two argument form is 'method' => 'class'
	# Check the values given to us.
	my $method = _IDENTIFIER($param[0]) or Carp::croak "Illegal method name '$param[0]'";
	my $want   = _CLASS($param[1])      or Carp::croak "Illegal class name '$param[1]'";
	_function_exists($pkg, $method)    and Carp::croak "Cannot create '${pkg}::$method'. It already exists";

	# Make sure the class is loaded
	unless ( _loaded($want) ) {
		eval "require $want";
		croak($@) if $@;
	}

	# Create the method in our caller
	eval "package $pkg;\nsub $method {\n\tParams::Coerce::_coerce('$want', \$_[-1])\n}";
	Carp::croak("Failed to create coercion method '$method' in $pkg': $@") if $@;

	1;
}

=pod

=head2 coerce $class, $param

The C<coerce> function takes a class name and a single parameter and
attempts to coerce the parameter into the intended class, or one of its
subclasses.

Please note that it is the responsibility of the consuming class to ensure
that the class you wish to coerce to is loaded. C<coerce> will check this
and die is it is not loaded.

Returns an instance of the class you specify, or one of its subclasses.
Returns C<undef> if the parameter cannot be coerced into the class you wish.

=cut

sub coerce($$) {
	# Check what they want properly first
	my $want = _CLASS($_[0]) or Carp::croak("Illegal class name '$_[0]'");
	_loaded($want)           or Carp::croak("Tried to coerce to unloaded class '$want'");

	# Now call the real function
	_coerce($want, $_[1]);
}

# The from method that is imported into the classes
sub from {
	@_ == 2 or Carp::croak("'->from must be called as a method with a single param");
	_coerce(@_);
}

# Internal version with less checks. Should ONLY be called once
# the first argument is FULLY validated.
sub _coerce {
	my $want = shift;
	my $have = Scalar::Util::blessed($_[0]) ? shift : return undef;

	# In the simplest case it is already what we need
	return $have if $have->isa($want);

	# Is there a coercion hint for this combination
	my $key = ref($have) . ',' . $want;
	my $hint = exists $hints{$key} ? $hints{$key}
		: _resolve($want, ref($have), $key)
		or return undef;

	# Call the coercion function
	my $type = substr($hint, 0, 1, '');
	if ( $type eq '>' ) {
		# Direct Push
		$have = $have->$hint();
	} elsif ( $type eq '<' ) {
		# Direct Pull
		$have = $want->$hint($have);
	} elsif ( $type eq '^' ) {
		# Third party
		my ($pkg, $function) = $hint =~ m/^(.*)::(.*)\z/s;
		require $pkg;
		no strict 'refs';
		$have = &{"${pkg}::${function}"}($have);
	} else {
		Carp::croak("Unknown coercion hint '$type$hint'");
	}

	# Did we get what we wanted?
	_INSTANCE($have, $want);
}

# Try to work out how to get from one class to the other class
sub _resolve {
	my ($want, $have, $key) = @_;

	# Look for a __as method
	my $method = "__as_$want";
	$method =~ s/::/_/g;
	return _hint($key, ">$method") if $have->can($method);

	# Look for a direct __from method
	$method = "__from_$have";
	$method =~ s/::/_/g;
	return _hint($key, "<$method") if $want->can($method);

	# Give up (and don't try again).
	# We use zero specifically so it will return false in boolean context
	_hint($key, '0');
}

# For now just save to the memory hash.
# Later, this may also involve saving to a database somewhere.
sub _hint {
	$hints{$_[0]} = $_[1];
}





#####################################################################
# Support Functions

# Is a class loaded.
sub _loaded {
	no strict 'refs';
	foreach ( keys %{"$_[0]::"} ) {
		return 1 unless substr($_, -2, 2) eq '::';
	}
	'';
}

# Does a function exist.
sub _function_exists {
	no strict 'refs';
	defined &{"$_[0]::$_[1]"};
}

1;

=pod

=head1 TO DO

- Write more unit tests

- Implement chained coercion

- Provide a way to coerce to string, int, etc that is compatible with
L<overload> and other types of things.

=cut
