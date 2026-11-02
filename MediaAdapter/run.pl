# Loads NotchyMediaAdapter.dylib into this Apple-signed perl and runs its stream loop.
use strict;
use DynaLoader;
my $path = shift @ARGV or die "usage: run.pl <dylib>\n";
my $lib = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, "notchy_media_stream") or die DynaLoader::dl_error();
my $sub = DynaLoader::dl_install_xsub("main::notchy_media_stream", $sym);
&$sub();
