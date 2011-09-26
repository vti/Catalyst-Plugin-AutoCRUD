package # hide from PAUSE
    DBICTest::Schema;

use base qw/DBIx::Class::Schema/;

no warnings qw/qw/;

__PACKAGE__->load_classes(qw/
  Artist
  SequenceTest
  BindType
  Employee
  CD
  Genre
  Bookmark
  Link
  Track
  Tag
  Year2000CDs
  Year1999CDs
  Money
  TimestampPrimaryKey
  /,
  { 'DBICTest::Schema' => [qw/
    LinerNotes
    Artwork
    Artwork_to_Artist
    Image
    Lyrics
    LyricVersion
    OneKey
    TwoKeys
    Serialized
  /]},
  (
    'FourKeys',
    'FourKeys_to_TwoKeys',
    'SelfRef',
    'ArtistUndirectedMap',
    'ArtistSourceName',
    'ArtistSubclass',
    'Producer',
    'CD_to_Producer',
  ),
  qw/SelfRefAlias TreeLike TwoKeyTreeLike Event EventTZ NoPrimaryKey/,
  qw/Collection CollectionObject TypedObject Owners BooksInLibrary/,
  qw/ForceForeign Encoded/,
);

1;